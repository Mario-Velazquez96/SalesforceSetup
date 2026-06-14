/**
 * Schedulable wrapper that kicks off SequenceSchedulerBatch with scope 200. (R4)
 *
 * Schedule it every 8 hours (runs 00:00 / 08:00 / 16:00) via the CRON expression
 *   0 0 0,8,16 * * ?
 * The hours list (0,8,16) is the supported way to express "every 8 hours" in the
 * Apex scheduler. See scripts/apex/schedule_sequence_scheduler.apex for the
 * one-line System.schedule helper (operational, not a deployed component).
 *
 * Scope 200 keeps each execute under fresh governor limits (R6); processStep sets
 * a FUTURE Next_Action_Date__c, so an already-advanced target is not re-selected
 * within the same day — running 8-hourly does not increase email volume.
 */
public with sharing class SequenceSchedulerSchedulable implements Schedulable {
    @TestVisible
    private static final Integer SCOPE = 200;

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new SequenceSchedulerBatch(), SCOPE);
    }
}
