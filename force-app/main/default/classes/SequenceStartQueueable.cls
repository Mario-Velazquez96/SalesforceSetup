/**
 * Off-trigger start of the cadence (R2). Enqueued by TargetTriggerHandler on
 * Target__c insert. Re-queries the Targets (so the engine works from a fully
 * field-loaded, committed copy) and calls the bulk engine entry point with
 * stepToSend = 1 for every active Target.
 *
 * The engine (SequenceEngineService) owns the inactive-target guard, so this
 * class simply hands every requested Target to processSteps; inactive ones
 * produce nothing (defence in depth). One SOQL (via the selector) + the engine's
 * own one-DML-per-object — 200-record safe (R8).
 */
public with sharing class SequenceStartQueueable implements Queueable {
    private final Set<Id> targetIds;

    public SequenceStartQueueable(Set<Id> targetIds) {
        this.targetIds = targetIds == null ? new Set<Id>() : targetIds;
    }

    public void execute(QueueableContext context) {
        if (targetIds.isEmpty()) {
            return;
        }

        // One query for all related Targets (R8), loading every engine-referenced
        // field via the selector (USER_MODE).
        List<Target__c> targets = new TargetSelector().getByIds(targetIds);
        if (targets.isEmpty()) {
            return;
        }

        List<SequenceEngineService.StepRequest> requests =
            new List<SequenceEngineService.StepRequest>();
        for (Target__c t : targets) {
            // Engine guards inactive Targets, but skipping here avoids needless
            // StepRequest objects on large batches.
            if (t.Sequence_Active__c == true) {
                requests.add(new SequenceEngineService.StepRequest(t, 1));
            }
        }

        if (!requests.isEmpty()) {
            SequenceEngineService.processSteps(requests); // R2
        }
    }
}
