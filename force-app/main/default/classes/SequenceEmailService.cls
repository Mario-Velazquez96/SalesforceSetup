/**
 * Builds and sends the cadence emails. This is the SINGLE place in the solution
 * that attaches the uploaded file (R5/R6) — the reason the cadence is Apex and
 * not Flow.
 *
 * Each send renders the step's Lightning Email Template (resolved by developer
 * name, never a hardcoded Id), targets the Target's Primary Contact, relates the
 * activity to the Target via WhatId, optionally prefixes "RE: ", optionally
 * attaches the latest ContentVersion of the Target's uploaded file, and sets the
 * From to an Org-Wide Email Address resolved by name. (R3, R4, R5, R6, R13, R14)
 */
public with sharing class SequenceEmailService {
    /**
     * Developer-name of the Org-Wide Email Address to send from. Resolved at
     * runtime — never a hardcoded address. When no matching (or no) OWE address
     * exists, the message is sent as the running user (Salesforce default),
     * which keeps the cadence working in sandboxes without an OWE configured.
     */
    @TestVisible
    private static String orgWideDisplayName = 'BlueSky Sequence';

    /**
     * One email to build/send: a Target plus the step config that drives it.
     */
    public class EmailRequest {
        public Target__c target;
        public Sequence_Step_Config__mdt config;

        public EmailRequest(Target__c target, Sequence_Step_Config__mdt config) {
            this.target = target;
            this.config = config;
        }
    }

    /**
     * Builds and sends all requested emails in a SINGLE Messaging.sendEmail call.
     * Returns the SendEmailResult list (empty when nothing to send).
     */
    public static List<Messaging.SendEmailResult> send(List<EmailRequest> requests) {
        List<Messaging.SingleEmailMessage> messages = buildMessages(requests);
        if (messages.isEmpty()) {
            return new List<Messaging.SendEmailResult>();
        }
        // allOrNothing = false: partial-success, one bad address won't abort all.
        return Messaging.sendEmail(messages, false);
    }

    /**
     * Constructs the SingleEmailMessage list without sending — exposed for unit
     * tests to assert subject prefix, attachments, target/what ids.
     */
    @TestVisible
    private static List<Messaging.SingleEmailMessage> buildMessages(List<EmailRequest> requests) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        if (requests == null || requests.isEmpty()) {
            return messages;
        }

        // Resolve template Ids by developer name (bulk).
        Set<String> templateNames = new Set<String>();
        Set<Id> attachmentDocIds = new Set<Id>();
        for (EmailRequest req : requests) {
            if (req.config != null && req.config.Email_Template_Dev_Name__c != null) {
                templateNames.add(req.config.Email_Template_Dev_Name__c);
            }
            Id docId = toContentDocumentId(req.target);
            if (docId != null) {
                attachmentDocIds.add(docId);
            }
        }

        Map<String, Id> templateIdByName = resolveTemplateIds(templateNames);
        Map<Id, ContentVersion> latestVersionByDoc =
            new ContentSelector().getLatestVersionsByDocumentId(attachmentDocIds);
        Id orgWideId = resolveOrgWideEmailAddressId();

        for (EmailRequest req : requests) {
            Sequence_Step_Config__mdt cfg = req.config;
            Target__c t = req.target;
            if (cfg == null || t == null || t.Primary_Contact__c == null) {
                continue;
            }
            Id templateId = templateIdByName.get(cfg.Email_Template_Dev_Name__c);
            if (templateId == null) {
                continue;
            }

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTargetObjectId(t.Primary_Contact__c);
            msg.setWhatId(t.Id);
            msg.setSaveAsActivity(false); // we log our own completed Email task
            msg.setTreatTargetObjectAsRecipient(true);

            if (cfg.Is_Reply__c == true) {
                // Reply step: render so we can prefix the subject with "RE: " (R4).
                // setSubject/body only take effect when no template Id is set on the
                // message, so we copy the rendered content over.
                Messaging.SingleEmailMessage rendered =
                    Messaging.renderStoredEmailTemplate(templateId, t.Primary_Contact__c, t.Id);
                String subject = rendered.getSubject();
                msg.setSubject('RE: ' + (subject == null ? '' : subject)); // R4
                msg.setHtmlBody(rendered.getHtmlBody());
                msg.setPlainTextBody(rendered.getPlainTextBody());
            } else {
                // Non-reply step: let Salesforce render the template server-side at
                // send time — no per-record SOQL, so the engine stays 200-safe (R12).
                msg.setTemplateId(templateId);
            }

            if (orgWideId != null) {
                msg.setOrgWideEmailAddressId(orgWideId); // R3/R14
            }

            // Attachment: latest ContentVersion of the uploaded file. (R5/R6)
            Id docId = toContentDocumentId(t);
            if (docId != null) {
                ContentVersion cv = latestVersionByDoc.get(docId);
                if (cv != null) {
                    msg.setEntityAttachments(new List<String>{ cv.Id });
                }
            }

            messages.add(msg);
        }
        return messages;
    }

    /**
     * @InvocableMethod wrapper so a Flow can trigger a cadence send. Delegates to
     * the same send logic. (R13)
     */
    @InvocableMethod(
        label='Send Sequence Email'
        description='Sends the cadence email for a Target at a given step (resolves template, RE: prefix, attachment, and Org-Wide Email Address).'
    )
    public static void sendInvocable(List<InvocableRequest> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }
        Set<Id> targetIds = new Set<Id>();
        for (InvocableRequest req : inputs) {
            if (req.targetId != null) {
                targetIds.add(req.targetId);
            }
        }
        Map<Id, Target__c> targetsById = new Map<Id, Target__c>();
        for (Target__c t : new TargetSelector().getByIds(targetIds)) {
            targetsById.put(t.Id, t);
        }
        List<EmailRequest> requests = new List<EmailRequest>();
        for (InvocableRequest req : inputs) {
            Target__c t = targetsById.get(req.targetId);
            Sequence_Step_Config__mdt cfg = SequenceStepConfigService.get(req.stepNumber);
            if (t != null && cfg != null) {
                requests.add(new EmailRequest(t, cfg));
            }
        }
        send(requests);
    }

    /**
     * Flow-facing input for the invocable send.
     */
    public class InvocableRequest {
        @InvocableVariable(label='Target Id' required=true)
        public Id targetId;

        @InvocableVariable(label='Step Number' required=true)
        public Integer stepNumber;
    }

    // ---- helpers ---------------------------------------------------------

    private static Map<String, Id> resolveTemplateIds(Set<String> developerNames) {
        Map<String, Id> result = new Map<String, Id>();
        if (developerNames == null || developerNames.isEmpty()) {
            return result;
        }
        for (EmailTemplate tmpl : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :developerNames
            WITH USER_MODE
        ]) {
            result.put(tmpl.DeveloperName, tmpl.Id);
        }
        return result;
    }

    private static Id resolveOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owes = [
            SELECT Id, DisplayName
            FROM OrgWideEmailAddress
            WHERE DisplayName = :orgWideDisplayName
            LIMIT 1
        ];
        if (!owes.isEmpty()) {
            return owes[0].Id;
        }
        // Fall back to any available OWE address (still resolved at runtime,
        // never hardcoded). If none exist, return null -> send as running user.
        List<OrgWideEmailAddress> anyOwe = [
            SELECT Id FROM OrgWideEmailAddress LIMIT 1
        ];
        return anyOwe.isEmpty() ? null : anyOwe[0].Id;
    }

    /**
     * Sequence_Attachment_Id__c is a Text(18) holding a ContentDocumentId.
     * Returns it as an Id, or null when blank/invalid. (R6)
     */
    private static Id toContentDocumentId(Target__c t) {
        if (t == null || String.isBlank(t.Sequence_Attachment_Id__c)) {
            return null;
        }
        try {
            return Id.valueOf(t.Sequence_Attachment_Id__c);
        } catch (System.StringException e) {
            return null;
        }
    }
}
