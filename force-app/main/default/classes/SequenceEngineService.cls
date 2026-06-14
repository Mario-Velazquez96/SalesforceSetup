/**
 * The heart of the cadence. For each active Target it:
 *   (a) sends the step's email (via SequenceEmailService),
 *   (b) creates the open "Call N" Task,
 *   (c) logs a completed Email Task,
 *   (d) advances Sequence_Step__c, and
 *   (e) schedules the next action per the step's Next_Trigger_Type__c.
 *
 * All public methods accept collections and perform exactly one DML per object
 * (one sendEmail, one Task insert, one Target update) so the engine is 200-record
 * safe. (R7, R8, R9, R10, R11, R12)
 *
 * No triggers or jobs live here — features 03/04/05 invoke this engine.
 */
public with sharing class SequenceEngineService {
    @TestVisible
    private static final String TRIGGER_TIMER = 'Timer';
    @TestVisible
    private static final String TRIGGER_CALL_COMPLETED = 'CallCompleted';
    @TestVisible
    private static final String TRIGGER_NONE = 'None';

    /**
     * Single-record convenience wrapper. Bulk-safe callers should prefer
     * processSteps.
     */
    public static void processStep(Target__c target, Integer stepToSend) {
        if (target == null || stepToSend == null) {
            return;
        }
        processSteps(new List<StepRequest>{ new StepRequest(target, stepToSend) });
    }

    /**
     * One unit of engine work: the Target and the step to send to it.
     */
    public class StepRequest {
        public Target__c target;
        public Integer stepToSend;

        public StepRequest(Target__c target, Integer stepToSend) {
            this.target = target;
            this.stepToSend = stepToSend;
        }
    }

    /**
     * Bulk entry point. Processes every request, collecting emails / tasks /
     * target updates and committing one DML per object. (R12)
     */
    public static void processSteps(List<StepRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Integer, Sequence_Step_Config__mdt> configByStep =
            SequenceStepConfigService.getByStep();

        List<SequenceEmailService.EmailRequest> emailRequests =
            new List<SequenceEmailService.EmailRequest>();
        List<Task> tasksToInsert = new List<Task>();
        Map<Id, Target__c> targetsToUpdate = new Map<Id, Target__c>();

        for (StepRequest req : requests) {
            Target__c t = req.target;
            Integer stepToSend = req.stepToSend;

            // R7 kill-switch guard: inactive targets produce nothing.
            if (t == null || stepToSend == null || t.Sequence_Active__c != true) {
                continue;
            }
            Sequence_Step_Config__mdt cfg = configByStep.get(stepToSend);
            if (cfg == null) {
                continue;
            }

            // (a) email
            emailRequests.add(new SequenceEmailService.EmailRequest(t, cfg));

            // (b) open "Call N" Task (R8b)
            tasksToInsert.add(buildCallTask(t, stepToSend, cfg));

            // (c) completed Email Task (R8c)
            tasksToInsert.add(buildEmailTask(t, stepToSend));

            // (d) advance the step (R8d)
            t.Sequence_Step__c = stepToSend;

            // (e) schedule the next action (R9/R10/R11)
            applyNextSchedule(t, cfg);

            targetsToUpdate.put(t.Id, t);
        }

        // One DML per object. (R12)
        if (!emailRequests.isEmpty()) {
            SequenceEmailService.send(emailRequests);
        }
        if (!tasksToInsert.isEmpty()) {
            insertTasks(tasksToInsert);
        }
        if (!targetsToUpdate.isEmpty()) {
            updateTargets(targetsToUpdate.values());
        }
    }

    // ---- builders --------------------------------------------------------

    private static Task buildCallTask(Target__c t, Integer step, Sequence_Step_Config__mdt cfg) {
        Integer offset = cfg.Call_Due_Offset_Days__c == null
            ? 0
            : Integer.valueOf(cfg.Call_Due_Offset_Days__c);
        String subject = String.isBlank(cfg.Call_Task_Subject__c)
            ? 'Call ' + step
            : cfg.Call_Task_Subject__c;
        return new Task(
            WhatId = t.Id,
            Subject = subject,
            ActivityDate = Date.today().addDays(offset),
            Status = 'Open',
            Is_Sequence_Call__c = true,
            Sequence_Step__c = step
        );
    }

    // Whether the running user can create the standard Task.Type field. We gate on
    // FLS (not mere existence) because engine DML runs in USER_MODE: setting a field
    // the user cannot write would abort the insert. When false, the
    // Is_Sequence_Call__c=false + "Email N" subject still distinguish the log task.
    private static Boolean taskTypeAvailable {
        get {
            if (taskTypeAvailable == null) {
                Map<String, Schema.SObjectField> fields =
                    Schema.SObjectType.Task.fields.getMap();
                Schema.SObjectField typeField = fields.get('type');
                taskTypeAvailable =
                    typeField != null && typeField.getDescribe().isCreateable();
            }
            return taskTypeAvailable;
        }
        set;
    }

    private static Task buildEmailTask(Target__c t, Integer step) {
        Task emailTask = new Task(
            WhatId = t.Id,
            Subject = 'Email ' + step,
            Status = 'Completed',
            ActivityDate = Date.today(),
            Is_Sequence_Call__c = false,
            Sequence_Step__c = step
        );
        // R8c: mark as an Email activity when the org has Activity Types enabled.
        // Some orgs disable the standard Task.Type field; in that case the
        // Is_Sequence_Call__c=false + "Email N" subject distinguish the log task.
        if (taskTypeAvailable) {
            emailTask.put('Type', 'Email');
        }
        return emailTask;
    }

    /**
     * Schedules Next_Action_Date__c from the step config (R9/R10/R11):
     *   Timer         -> now + Next_Wait_Days__c
     *   CallCompleted -> null (waits on the call-completion event)
     *   None          -> null (sequence complete at step 10)
     */
    private static void applyNextSchedule(Target__c t, Sequence_Step_Config__mdt cfg) {
        String triggerType = cfg.Next_Trigger_Type__c;
        if (TRIGGER_TIMER.equals(triggerType)) {
            Integer waitDays = cfg.Next_Wait_Days__c == null
                ? (t.Days_Until_Next_Email__c == null ? 0 : Integer.valueOf(t.Days_Until_Next_Email__c))
                : Integer.valueOf(cfg.Next_Wait_Days__c);
            t.Next_Action_Date__c = Datetime.now().addDays(waitDays); // R9
        } else {
            // CallCompleted (R10) and None (R11): no scheduled date here.
            t.Next_Action_Date__c = null;
        }
    }

    // ---- DML with USER_MODE + partial-success handling (R12) --------------

    private static void insertTasks(List<Task> tasks) {
        List<Database.SaveResult> results =
            Database.insert(tasks, false, AccessLevel.USER_MODE);
        assertSaved(results, 'Task insert');
    }

    private static void updateTargets(List<Target__c> targets) {
        List<Database.SaveResult> results =
            Database.update(targets, false, AccessLevel.USER_MODE);
        assertSaved(results, 'Target update');
    }

    private static void assertSaved(List<Database.SaveResult> results, String context) {
        List<String> errors = new List<String>();
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    errors.add(err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
        if (!errors.isEmpty()) {
            throw new SequenceEngineException(
                context + ' failed: ' + String.join(errors, '; ')
            );
        }
    }

    public class SequenceEngineException extends Exception {}
}
