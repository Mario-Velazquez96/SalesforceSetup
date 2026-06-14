/**
 * The single trigger on Target__c (Rule: one trigger per object; R3).
 *
 * Contains NO business logic — it only routes by Trigger.operationType to the
 * handler. This feature (03) wires the after-insert branch that starts the
 * cadence. 05_terminal_stop_and_guards will add a BEFORE_UPDATE branch to THIS
 * same trigger/handler (do not create a second trigger).
 */
trigger TargetTrigger on Target__c (after insert) {
    switch on Trigger.operationType {
        when AFTER_INSERT {
            TargetTriggerHandler.afterInsert(Trigger.new);
        }
    }
}
