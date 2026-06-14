/**
 * The single trigger on Task (Rule: one trigger per object; R9).
 *
 * Contains NO business logic — it only routes by Trigger.operationType to the
 * handler. This feature (03) wires the after-update branch that reacts to a
 * completed sequence Call by setting the related Target's Next_Action_Date__c.
 * If other Task automation is added later, add a handler call here rather than
 * a second trigger.
 */
trigger TaskTrigger on Task (after update) {
    switch on Trigger.operationType {
        when AFTER_UPDATE {
            TaskTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
