/**
 * Handler for TargetTrigger. Holds all Target__c trigger logic so the trigger
 * stays logic-free (03/R3, 05/R2). Feature 03 implements the after-insert branch:
 * enqueue SequenceStartQueueable with the new record Ids so the cadence's first
 * step runs off-trigger, keeping the insert transaction lean (03/R1).
 *
 * Feature 05_terminal_stop_and_guards adds the beforeUpdate(...) branch below for
 * the terminal-status auto-stop — same handler, no second trigger (05/R2).
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
     * Recursion guard (05/R7): the set of Target Ids already stamped by the
     * before-update terminal-stop branch in this transaction. Consistent with
     * feature 03's Set<Id> guard pattern so re-entry on a partially handled set
     * only skips the records already processed.
     */
    @TestVisible
    private static Set<Id> processedTerminalStopIds = new Set<Id>();

    /**
     * Cached terminal-status map (05/R5): Status_Value__c -> Stop_Reason__c, read
     * once from Sequence_Terminal_Status__mdt.getAll() (no SOQL). Lazily built and
     * held static so a 200-record before-update transaction reads the CMDT once.
     */
    private static Map<String, String> stopReasonByStatusCache;

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

    /**
     * Before-update branch (05/R1, R2). When a Target__c's Status__c CHANGES to a
     * value present in Sequence_Terminal_Status__mdt and the cadence is currently
     * active, stamp the same-record fields directly on Trigger.new — NO DML:
     *   Sequence_Active__c     = false
     *   Sequence_Stop_Reason__c = the matching Stop_Reason__c
     *   Next_Action_Date__c    = null
     *
     * Skips (no change) when Status__c did not change (R3) or the target is already
     * inactive (R4), or the new status is not terminal. Pure in-memory mutation,
     * CMDT cached, so it is 200-record safe with zero added SOQL/DML (R7).
     */
    public static void beforeUpdate(List<Target__c> newList, Map<Id, Target__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }

        Map<String, String> stopReasonByStatus = getStopReasonByStatus();
        if (stopReasonByStatus.isEmpty()) {
            return;
        }

        for (Target__c rec : newList) {
            // R7: skip records already stamped in this transaction.
            if (processedTerminalStopIds.contains(rec.Id)) {
                continue;
            }

            // R4: already inactive -> no stop action.
            if (rec.Sequence_Active__c != true) {
                continue;
            }

            Target__c old = oldMap.get(rec.Id);
            String newStatus = rec.Status__c;

            // R3: status did not change -> no stop action.
            if (old != null && old.Status__c == newStatus) {
                continue;
            }

            // R1: status changed to a terminal value -> stamp the stop on Trigger.new.
            if (newStatus != null && stopReasonByStatus.containsKey(newStatus)) {
                rec.Sequence_Active__c = false;
                rec.Sequence_Stop_Reason__c = stopReasonByStatus.get(newStatus);
                rec.Next_Action_Date__c = null;
                processedTerminalStopIds.add(rec.Id);
            }
        }
    }

    /**
     * Builds (once per transaction) and returns the terminal-status map from
     * Sequence_Terminal_Status__mdt.getAll() (05/R5). Status_Value__c keys map to
     * Stop_Reason__c values. No SOQL — getAll() is cached metadata, so this is
     * bulk-safe (R7).
     */
    private static Map<String, String> getStopReasonByStatus() {
        if (stopReasonByStatusCache == null) {
            stopReasonByStatusCache = new Map<String, String>();
            for (Sequence_Terminal_Status__mdt row : Sequence_Terminal_Status__mdt.getAll().values()) {
                if (String.isNotBlank(row.Status_Value__c)) {
                    stopReasonByStatusCache.put(row.Status_Value__c, row.Stop_Reason__c);
                }
            }
        }
        return stopReasonByStatusCache;
    }
}
