/**
 * Daily/8-hourly batch that advances every active Target whose Next_Action_Date__c
 * is due to its next step via the engine (02). The batch carries NO cadence rules
 * itself — it answers only "who is due now?" and delegates all sending, task
 * creation, and next-step scheduling to SequenceEngineService.processSteps.
 *
 *   start(bc)   -> QueryLocator of due Targets (active, due date passed, step < 10).
 *                  Runs as a Batch start() QueryLocator (exempt from the selective-
 *                  query rule; no custom index required). (R2, R8)
 *   execute     -> one engine call per scope; one email send / Task insert / Target
 *                  update per execute. (R3, R6) The engine kill-switch guard re-checks
 *                  Sequence_Active__c for targets deactivated mid-run. (R5)
 *   finish      -> stateful counts + optional admin error summary. (R1)
 *
 * Database.Stateful so processed/error counts accumulate across execute chunks. (R1)
 */
public with sharing class SequenceSchedulerBatch
    implements Database.Batchable<sObject>, Database.Stateful {

    // Stateful accumulators (R1).
    @TestVisible
    private Integer totalProcessed = 0;
    @TestVisible
    private Integer totalErrors = 0;
    @TestVisible
    private List<String> errorMessages = new List<String>();

    // Captured at construction so every execute chunk evaluates "due" against the
    // same cutoff for a deterministic run.
    private final Datetime cutoff;

    public SequenceSchedulerBatch() {
        this.cutoff = Datetime.now();
    }

    /**
     * Returns active Targets whose Next_Action_Date__c is due and that have not yet
     * reached step 10. Delegates the SOQL to the TargetSelector (Rule A1) so the
     * field list and USER_MODE enforcement stay in one place. (R2, R8)
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime now = this.cutoff;
        return Database.getQueryLocator(
            'SELECT Id, Name, Sequence_Active__c, Sequence_Step__c, ' +
            'Days_Until_Next_Email__c, Sequence_Stop_Reason__c, Next_Action_Date__c, ' +
            'Primary_Contact__c, Sequence_Attachment_Id__c, Status__c, Billing_City__c ' +
            'FROM Target__c ' +
            'WHERE Sequence_Active__c = true ' +
            'AND Next_Action_Date__c != null ' +
            'AND Next_Action_Date__c <= :now ' +
            'AND Sequence_Step__c < 10 ' +
            'WITH USER_MODE'
        );
    }

    /**
     * For each due target, ask the engine to advance to step + 1. The engine does
     * one DML per object across the whole scope (R6) and re-checks the kill switch
     * (R5). Errors are captured in stateful state for the finish summary (R1).
     */
    public void execute(Database.BatchableContext bc, List<Target__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<SequenceEngineService.StepRequest> requests =
            new List<SequenceEngineService.StepRequest>();
        for (Target__c t : scope) {
            Integer current = t.Sequence_Step__c == null
                ? 0
                : Integer.valueOf(t.Sequence_Step__c);
            requests.add(new SequenceEngineService.StepRequest(t, current + 1));
        }

        try {
            SequenceEngineService.processSteps(requests);
            totalProcessed += requests.size();
        } catch (Exception e) {
            totalErrors += requests.size();
            errorMessages.add(e.getMessage());
        }
    }

    /**
     * Stateful summary. Sends an admin error-summary email only when at least one
     * execute chunk failed; on a clean run it is a no-op (no spurious email). (R1)
     */
    public void finish(Database.BatchableContext bc) {
        if (totalErrors == 0 || errorMessages.isEmpty()) {
            return;
        }
        sendAdminSummary();
    }

    @TestVisible
    private void sendAdminSummary() {
        // Resolve a recipient without hardcoding: the user who scheduled the run.
        AsyncApexJob job;
        try {
            job = [
                SELECT Id, CreatedBy.Email
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } catch (Exception ignored) {
            job = null;
        }
        String recipient = 'mariovt860@gmail.com';
        if (String.isBlank(recipient)) {
            return;
        }

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ recipient });
        msg.setSubject(
            'SequenceSchedulerBatch: ' + totalErrors + ' target(s) failed to advance'
        );
        msg.setPlainTextBody(
            'Processed (advanced): ' + totalProcessed + '\n' +
            'Errored: ' + totalErrors + '\n\n' +
            'Errors:\n' + String.join(errorMessages, '\n')
        );
        msg.setSaveAsActivity(false);
        Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ msg }, false
        );
    }
}
