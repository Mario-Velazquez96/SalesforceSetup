/**
 * Handler for TargetTrigger. Holds all Target__c trigger logic so the trigger
 * stays logic-free (R3). This feature (03) implements the after-insert branch:
 * enqueue SequenceStartQueueable with the new record Ids so the cadence's first
 * step runs off-trigger, keeping the insert transaction lean (R1).
 *
 * 05_terminal_stop_and_guards will add a beforeUpdate(...) method here for the
 * terminal-stop branch — do not move this logic out into a second trigger.
 */
public with sharing class TargetTriggerHandler {
    /**
     * Recursion guard (R7): the set of Target Ids already processed by the
     * after-insert branch in this transaction. A Set<Id> (not a Boolean) so a
     * partial re-entry only skips the records already handled.
     */
    @TestVisible
    private static Set<Id> processedInsertIds = new Set<Id>();

    /**
     * After-insert entry point (R1). Enqueues SequenceStartQueueable with the
     * Ids of the newly inserted ACTIVE Targets so step 1 is processed
     * asynchronously. Only active-at-insert Targets start a sequence — an
     * inactive Target does not auto-start (consistent with R2/R6 and the
     * engine's own inactive guard, which still applies defensively when the
     * queueable re-queries). No business logic beyond filtering, recursion-
     * guarding and enqueueing.
     */
    public static void afterInsert(List<Target__c> newTargets) {
        if (newTargets == null || newTargets.isEmpty()) {
            return;
        }

        // R7 + active filter: enqueue only active Targets not already handled.
        Set<Id> toProcess = new Set<Id>();
        for (Target__c t : newTargets) {
            if (t.Sequence_Active__c == true && !processedInsertIds.contains(t.Id)) {
                toProcess.add(t.Id);
            }
        }
        if (toProcess.isEmpty()) {
            return;
        }
        processedInsertIds.addAll(toProcess);

        // Queueables cannot be enqueued from a Queueable chain in test context
        // beyond depth limits, but the start path always originates from an
        // insert DML, so a single enqueue is safe and 200-record bulk-friendly.
        System.enqueueJob(new SequenceStartQueueable(toProcess));
    }
}
