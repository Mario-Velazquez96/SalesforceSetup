/**
 * Builds and sends the cadence emails. This is the SINGLE place in the solution
 * that attaches the uploaded file (R5/R6) — the reason the cadence is Apex and
 * not Flow.
 *
 * Each send renders the step's Lightning Email Template (resolved by developer
 * name, never a hardcoded Id), targets the Target's Primary Contact, relates the
 * activity to the Target via WhatId, optionally prefixes "RE: ", optionally
 * attaches the latest ContentVersion of the Target's uploaded file, and sets the
 * From using SEND-AS-OWNER (Option A): the verified Org-Wide Email Address whose
 * address matches the Target record OWNER's email, falling back to a default OWE
 * (resolved by display name) and ultimately the running user. (R3, R4, R5, R6,
 * R13, R14)
 */
public without sharing class SequenceEmailService {
    /**
     * Developer-name of the DEFAULT Org-Wide Email Address to fall back to.
     * Resolved at runtime — never a hardcoded address. Used only when the Target
     * owner has no verified OWE matching their email. When no matching (or no)
     * OWE address exists, the message is sent as the running user (Salesforce
     * default), which keeps the cadence working in sandboxes without an OWE.
     */
    @TestVisible
    private static String orgWideDisplayName = 'BlueSky Sequence';

    /**
     * Test seam for send-as-owner OWE matching. OrgWideEmailAddress is NOT
     * insertable in Apex tests, so tests cannot create real OWEs. When this map
     * is non-null, buildMessages uses it INSTEAD of querying OrgWideEmailAddress
     * — letting unit tests inject a known {ownerEmailLowerCased -> oweId} map and
     * assert which OWE id is selected per message. Null in production (a live
     * query runs). (R3, R14)
     */
    @TestVisible
    private static Map<String, Id> ownerOweByAddressOverride = null;

    /**
     * Test oracle for send-as-owner SELECTION. SingleEmailMessage has no
     * getOrgWideEmailAddressId() getter, so the chosen OWE id per Target cannot
     * be read back off the message object. buildMessages records the OWE id it
     * selected for each Target here (Target Id -> oweId or null), so unit tests
     * can assert (a) an owner with a matching OWE selects that id and (b) an owner
     * with no match falls back to the default OWE id (or null). (R3)
     */
    @TestVisible
    private static Map<Id, Id> selectedOweByTarget = new Map<Id, Id>();

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

        // Send-as-owner (Option A): the From is the Target OWNER's own verified
        // Org-Wide Email Address. Bulk-resolve once (200-safe, no SOQL in the
        // per-request loop): owner emails per Target, then OWEs keyed by address.
        Id defaultOrgWideId = resolveOrgWideEmailAddressId(); // fallback only
        Map<Id, String> ownerEmailByTarget = resolveOwnerEmails(requests);
        Map<String, Id> ownerOweByAddress = resolveOwnerOweByAddress(ownerEmailByTarget);

        // Reset the selection oracle for this build (R3 test seam).
        selectedOweByTarget = new Map<Id, Id>();

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

            // Send-as-owner (Option A): From = the Target owner's verified OWE
            // when their email matches one; else fall back to the default OWE
            // (by display name); else leave unset = running user. (R3/R14)
            Id ownerOweId = null;
            String ownerEmail = ownerEmailByTarget.get(t.Id);
            if (String.isNotBlank(ownerEmail)) {
                ownerOweId = ownerOweByAddress.get(ownerEmail.toLowerCase());
            }
            Id chosenOweId = (ownerOweId != null) ? ownerOweId : defaultOrgWideId;
            if (chosenOweId != null) {
                msg.setOrgWideEmailAddressId(chosenOweId);
            }
            // Record the selection for the test oracle (null = running-user path).
            selectedOweByTarget.put(t.Id, chosenOweId);

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

    /**
     * Send-as-owner (Option A) — bulk-resolve each Target OWNER's email. Returns a
     * Map keyed by Target Id whose value is that Target owner's User.Email. Runs a
     * SINGLE User query across all requests (200-safe, no SOQL in a loop). The
     * owner's email is later matched to a verified OWE so the From IS the owner.
     * @TestVisible so unit tests can assert the per-Target owner email.
     */
    @TestVisible
    private static Map<Id, String> resolveOwnerEmails(List<EmailRequest> requests) {
        Map<Id, String> result = new Map<Id, String>();
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        Set<Id> ownerIds = new Set<Id>();
        for (EmailRequest req : requests) {
            if (req != null && req.target != null && req.target.OwnerId != null) {
                ownerIds.add(req.target.OwnerId);
            }
        }
        if (ownerIds.isEmpty()) {
            return result;
        }
        Map<Id, String> emailByOwner = new Map<Id, String>();
        for (User u : [
            SELECT Id, Email
            FROM User
            WHERE Id IN :ownerIds
            WITH SYSTEM_MODE    
        ]) {
            emailByOwner.put(u.Id, u.Email);
        }
        for (EmailRequest req : requests) {
            if (req == null || req.target == null || req.target.OwnerId == null) {
                continue;
            }
            String email = emailByOwner.get(req.target.OwnerId);
            if (String.isNotBlank(email)) {
                result.put(req.target.Id, email);
            }
        }
        return result;
    }

    /**
     * Send-as-owner (Option A) — bulk-resolve the verified OWEs whose Address
     * matches an owner email. Returns Map<addressLowerCased, oweId> for
     * case-insensitive matching. Runs ONE OrgWideEmailAddress query.
     *
     * Test seam: OrgWideEmailAddress is NOT insertable in Apex tests, so when
     * ownerOweByAddressOverride is set, that injected map is used INSTEAD of
     * querying — letting tests assert owner->OWE selection without real OWEs.
     */
    @TestVisible
    private static Map<String, Id> resolveOwnerOweByAddress(Map<Id, String> ownerEmailByTarget) {
        if (ownerOweByAddressOverride != null) {
            return ownerOweByAddressOverride;
        }
        Map<String, Id> result = new Map<String, Id>();
        if (ownerEmailByTarget == null || ownerEmailByTarget.isEmpty()) {
            return result;
        }
        Set<String> ownerEmails = new Set<String>(ownerEmailByTarget.values());
        for (OrgWideEmailAddress owe : [
            SELECT Id, Address
            FROM OrgWideEmailAddress
            WHERE Address IN :ownerEmails
        ]) {
            if (String.isNotBlank(owe.Address)) {
                result.put(owe.Address.toLowerCase(), owe.Id);
            }
        }
        return result;
    }

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

    @TestVisible
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
