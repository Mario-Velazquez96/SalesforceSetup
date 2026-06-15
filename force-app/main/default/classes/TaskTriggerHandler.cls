/**
 * Handler for TaskTrigger. Holds all Task trigger logic so the trigger stays
 * logic-free (R9). This feature (03) implements the after-update branch: when a
 * sequence Call Task is completed, schedule the related active Target's next
 * action by setting Next_Action_Date__c = now + Days_Until_Next_Email__c (R4).
 *
 * It does NOT send the next email — the scheduler batch (04) picks up due
 * Targets and sends. The call-completion path only sets the due date so the
 * 4-day call wait is unified with the timer waits.
 */
public with sharing class TaskTriggerHandler {
    /**
     * Recursion guard (R7): Target Ids whose Next_Action_Date__c has already
     * been scheduled by this branch in the current transaction. A Set<Id>
     * (not a Boolean) so re-entry only skips already-handled records.
     */
    @TestVisible
    private static Set<Id> processedTargetIds = new Set<Id>();

    /**
     * After-update entry point (R4–R6). For each Task that transitioned to
     * Status='Completed' and is a sequence Call (Is_Sequence_Call__c=true, R5),
     * find the related active Target (R6) whose Sequence_Step__c matches the
     * Task's Sequence_Step__c and set its Next_Action_Date__c.
     */
    public static void afterUpdate(List<Task> newTasks, Map<Id, Task> oldMap) {
        if (newTasks == null || newTasks.isEmpty()) {
            return;
        }

        // 1) Filter to sequence calls that just became Completed (R4, R5).
        //    Map Target (WhatId) -> the Task's Sequence_Step__c for matching.
        Map<Id, Decimal> stepByTargetId = new Map<Id, Decimal>();
        for (Task t : newTasks) {
            if (t.Is_Sequence_Call__c != true) {
                continue; // R5: non-sequence tasks (e.g. logged Email) -> no action
            }
            if (t.Status != 'Completed') {
                continue;
            }
            Task oldTask = oldMap == null ? null : oldMap.get(t.Id);
            Boolean newlyCompleted = oldTask == null || oldTask.Status != 'Completed';
            if (!newlyCompleted) {
                continue; // only react to the transition INTO Completed
            }
            Id whatId = t.WhatId;
            if (whatId == null || whatId.getSObjectType() != Target__c.SObjectType) {
                continue;
            }
            // If two completed calls target the same Target in one transaction,
            // last write wins on the step key — engine semantics are one step
            // per Target so this is acceptable.
            stepByTargetId.put(whatId, t.Sequence_Step__c);
        }

        if (stepByTargetId.isEmpty()) {
            return;
        }

        // 2) One query for all related Targets (R8).
        List<Target__c> targets = new TargetSelector().getByIds(stepByTargetId.keySet());
        if (targets.isEmpty()) {
            return;
        }

        // 3) Read all step configs once (R8) so the per-Target loop stays
        //    SOQL-free; custom metadata is cached by the service.
        Map<Integer, Sequence_Step_Config__mdt> configByStep =
            SequenceStepConfigService.getByStep();

        // 4) Build the single update set (R4, R6, R7, R10).
        List<Target__c> toUpdate = new List<Target__c>();
        for (Target__c target : targets) {
            if (processedTargetIds.contains(target.Id)) {
                continue; // R7: already scheduled this transaction
            }
            if (target.Sequence_Active__c != true) {
                continue; // R6: inactive target -> no update
            }
            Decimal taskStep = stepByTargetId.get(target.Id);
            // R6/R4: step must match the Task's step.
            if (taskStep == null || target.Sequence_Step__c != taskStep) {
                continue;
            }
            // R4/R10: only reschedule when the matched step is a CallCompleted
            // step. Timer/None steps (or a missing config) are a no-op — the
            // engine already set Next_Action_Date__c = now + Next_Wait_Days__c
            // and that timer must not be clobbered by the call wait.
            Sequence_Step_Config__mdt stepConfig =
                configByStep.get(Integer.valueOf(target.Sequence_Step__c));
            if (stepConfig == null || stepConfig.Next_Trigger_Type__c != 'CallCompleted') {
                continue; // R10: Timer/None step -> leave engine-set date intact
            }
            Integer waitDays = target.Days_Until_Next_Email__c == null
                ? 0
                : Integer.valueOf(target.Days_Until_Next_Email__c);
            target.Next_Action_Date__c = Datetime.now().addDays(waitDays); // R4
            processedTargetIds.add(target.Id);
            toUpdate.add(target);
        }

        // 5) One DML (R8).
        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> results =
                Database.update(toUpdate, false, AccessLevel.USER_MODE);
            assertSaved(results);
        }
    }

    private static void assertSaved(List<Database.SaveResult> results) {
        List<String> errors = new List<String>();
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    errors.add(err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
        if (!errors.isEmpty()) {
            throw new TaskTriggerHandlerException(
                'Target Next_Action_Date update failed: ' + String.join(errors, '; ')
            );
        }
    }

    public class TaskTriggerHandlerException extends Exception {}
}
