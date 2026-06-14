/**
 * The single trigger on Target__c (Rule: one trigger per object; R3 of 03, R2 of 05).
 *
 * Contains NO business logic — it only routes by Trigger.operationType to the
 * handler. Feature 03 wires the after-insert branch that starts the cadence.
 * Feature 05_terminal_stop_and_guards adds the BEFORE_UPDATE branch (terminal
 * status auto-stop) to THIS same trigger/handler — no second trigger exists.
 */
trigger TargetTrigger on Target__c (after insert, before update) {
    switch on Trigger.operationType {
        when AFTER_INSERT {
            TargetTriggerHandler.afterInsert(Trigger.new);
        }
        when BEFORE_UPDATE {
            TargetTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
