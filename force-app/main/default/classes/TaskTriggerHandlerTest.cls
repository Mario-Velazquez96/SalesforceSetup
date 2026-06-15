/**
 * Tests for TaskTrigger / TaskTriggerHandler (R4, R5, R6, R7, R8, R9).
 *
 * Completing a sequence Call (Is_Sequence_Call__c=true) whose Sequence_Step__c
 * matches the related active Target's Sequence_Step__c sets Next_Action_Date__c
 * = now + Days_Until_Next_Email__c (R4) and sends NO email. Non-sequence tasks
 * (R5), inactive targets (R6) and step mismatches leave the Target unchanged.
 */
@IsTest
private class TaskTriggerHandlerTest {
    private static final Integer WAIT_DAYS = 4;

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Call Co', BillingCity = 'Denver');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Cal',
            LastName = 'Lead',
            Email = 'cal.lead@example.com',
            AccountId = acc.Id
        );
        insert con;
    }

    private static Id accId { get { if (accId == null) { accId = [SELECT Id FROM Account LIMIT 1].Id; } return accId; } set; }
    private static Id conId { get { if (conId == null) { conId = [SELECT Id FROM Contact LIMIT 1].Id; } return conId; } set; }

    private static Target__c newTarget(String name, Boolean active, Integer step) {
        return new Target__c(
            Name = name,
            Company_Name__c = accId,
            Primary_Contact__c = conId,
            // Inserted INACTIVE so the after-insert start path does NOT enqueue
            // SequenceStartQueueable (which would later run at Test.stopTest and
            // re-process step 1, corrupting these call-completion assertions).
            // The desired active flag is applied via a post-insert update, which
            // does not fire the after-insert branch.
            Sequence_Active__c = false,
            Sequence_Step__c = step,
            Days_Until_Next_Email__c = WAIT_DAYS
        );
    }

    /**
     * Inserts the Target inactive (no start enqueue) then sets the real active
     * flag via update so call-completion tests run against a clean Target.
     */
    private static Target__c insertTarget(String name, Boolean active, Integer step) {
        Target__c t = newTarget(name, active, step);
        insert t;
        t.Sequence_Active__c = active;
        update t;
        return t;
    }

    private static List<Target__c> insertTargets(List<Target__c> targets, Boolean active) {
        insert targets;
        for (Target__c t : targets) {
            t.Sequence_Active__c = active;
        }
        update targets;
        return targets;
    }

    private static Task newCallTask(Id targetId, Integer step, Boolean isSequenceCall) {
        return new Task(
            WhatId = targetId,
            Subject = 'Call ' + step,
            Status = 'Open',
            ActivityDate = Date.today(),
            Is_Sequence_Call__c = isSequenceCall,
            Sequence_Step__c = step
        );
    }

    private static Target__c reload(Id targetId) {
        return [
            SELECT Id, Sequence_Step__c, Next_Action_Date__c, Sequence_Active__c,
                   Days_Until_Next_Email__c
            FROM Target__c WHERE Id = :targetId
        ];
    }

    private static void assertAboutNowPlusWait(Datetime actual) {
        Assert.isNotNull(actual, 'Next_Action_Date set (R4)');
        Datetime expected = Datetime.now().addDays(WAIT_DAYS);
        Long diffMs = Math.abs(actual.getTime() - expected.getTime());
        Assert.isTrue(diffMs < 5L * 60L * 1000L, 'Next_Action_Date ~ now + Days_Until_Next_Email (R4)');
    }

    @IsTest
    static void testMatchingCallCompleteSchedulesNextAction() {
        Target__c t = insertTarget('Match', true, 1);
        Task call = newCallTask(t.Id, 1, true);
        insert call;

        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        call.Status = 'Completed';
        update call; // fires TaskTrigger after-update synchronously (R4)

        // Assert the synchronous handler result BEFORE stopTest. (The Target was
        // inserted inactive then flipped active to suppress the insert start
        // path; any queueable that was enqueued runs at stopTest and is
        // irrelevant to the call-completion behaviour under test.)
        Target__c after = reload(t.Id);
        assertAboutNowPlusWait(after.Next_Action_Date__c);
        Assert.areEqual(1, after.Sequence_Step__c, 'Step is unchanged by call completion (04 sends)');
        Assert.areEqual(
            emailsBefore,
            Limits.getEmailInvocations(),
            'No email sent on call completion — that is feature 04'
        );
        Test.stopTest();
    }

    @IsTest
    static void testNonSequenceTaskCompleteDoesNothing() {
        Target__c t = insertTarget('NonSeq', true, 1);
        Task logTask = newCallTask(t.Id, 1, false); // Is_Sequence_Call__c = false (R5)
        insert logTask;

        Test.startTest();
        logTask.Status = 'Completed';
        update logTask;
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(null, after.Next_Action_Date__c, 'Non-sequence task -> unchanged (R5)');
    }

    @IsTest
    static void testInactiveTargetDoesNothing() {
        Target__c t = insertTarget('Inactive', false, 1);
        Task call = newCallTask(t.Id, 1, true);
        insert call;

        Test.startTest();
        call.Status = 'Completed';
        update call;
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(null, after.Next_Action_Date__c, 'Inactive target -> unchanged (R6)');
    }

    @IsTest
    static void testTimerStepCallCompleteLeavesDateUnchanged() {
        // R10: step 6 is a Timer step (Next_Trigger_Type__c='Timer'). The engine
        // already set Next_Action_Date__c = now + Next_Wait_Days__c (14). The
        // engine still creates a Call 6 task; completing it must NOT overwrite
        // the engine-set 14-day timer with the 4-day call wait.
        Target__c t = insertTarget('Timer', true, 6);
        Datetime engineTimer = Datetime.now().addDays(14);
        t.Next_Action_Date__c = engineTimer; // simulate the engine's timer
        update t;

        Task call = newCallTask(t.Id, 6, true); // matching Call on the Timer step
        insert call;

        Test.startTest();
        call.Status = 'Completed';
        update call; // fires after-update; R10 -> no-op for Timer steps
        Target__c after = reload(t.Id);
        // Assert the date is UNCHANGED (still ~now+14, NOT now+Days_Until_Next_Email).
        Assert.isNotNull(after.Next_Action_Date__c, 'Timer date still present (R10)');
        Long diffFromTimerMs = Math.abs(after.Next_Action_Date__c.getTime() - engineTimer.getTime());
        Assert.isTrue(
            diffFromTimerMs < 5L * 60L * 1000L,
            'Timer-step Next_Action_Date unchanged (~now+14, engine timer stands) (R10)'
        );
        // Prove it was NOT rewritten to the 4-day call wait.
        Datetime callWait = Datetime.now().addDays(WAIT_DAYS);
        Long diffFromCallWaitMs = Math.abs(after.Next_Action_Date__c.getTime() - callWait.getTime());
        Assert.isTrue(
            diffFromCallWaitMs > 5L * 60L * 1000L,
            'Timer date was NOT overwritten with now + Days_Until_Next_Email (R10)'
        );
        Test.stopTest();
    }

    @IsTest
    static void testStepMismatchDoesNothing() {
        Target__c t = insertTarget('Mismatch', true, 2); // target on step 2
        Task call = newCallTask(t.Id, 1, true); // call for step 1 — mismatch
        insert call;

        Test.startTest();
        call.Status = 'Completed';
        update call;
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(null, after.Next_Action_Date__c, 'Step mismatch -> unchanged (R6)');
    }

    @IsTest
    static void testAlreadyCompletedUpdateDoesNothing() {
        // A task already Completed that is updated again (not a transition INTO
        // Completed) must not re-schedule.
        Target__c t = insertTarget('AlreadyDone', true, 1);
        Task call = newCallTask(t.Id, 1, true);
        call.Status = 'Completed';
        insert call; // inserted already-completed (no after-update yet)

        Test.startTest();
        call.Subject = 'Call 1 edited';
        update call; // status stays Completed -> not a transition
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(null, after.Next_Action_Date__c, 'No transition into Completed -> unchanged');
    }

    @IsTest
    static void testNullAndEmptyInputNoOp() {
        Test.startTest();
        TaskTriggerHandler.afterUpdate(null, null);
        TaskTriggerHandler.afterUpdate(new List<Task>(), new Map<Id, Task>());
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Target__c WHERE Next_Action_Date__c != null],
            'Null/empty input -> nothing scheduled');
    }

    @IsTest
    static void testNullDaysUntilNextEmailUsesZero() {
        // Days_Until_Next_Email__c null -> waitDays = 0 -> Next_Action_Date ~ now.
        Target__c t = insertTarget('NullDays', true, 1);
        t.Days_Until_Next_Email__c = null;
        update t;
        Task call = newCallTask(t.Id, 1, true);
        insert call;

        Test.startTest();
        call.Status = 'Completed';
        update call;
        Target__c after = reload(t.Id);
        Assert.isNotNull(after.Next_Action_Date__c, 'Null days still schedules (waitDays=0)');
        Long diffMs = Math.abs(after.Next_Action_Date__c.getTime() - Datetime.now().getTime());
        Assert.isTrue(diffMs < 5L * 60L * 1000L, 'Null days -> Next_Action_Date ~ now');
        Test.stopTest();
    }

    @IsTest
    static void testRecursionGuardSkipsAlreadyProcessed() {
        Target__c t = insertTarget('Guard', true, 1);
        Task call = newCallTask(t.Id, 1, true);
        call.Status = 'Completed';

        Test.startTest();
        // Pre-seed the guard so the handler treats this Target as already done (R7).
        TaskTriggerHandler.processedTargetIds.add(t.Id);
        TaskTriggerHandler.afterUpdate(
            new List<Task>{ call },
            new Map<Id, Task>{ call.Id => new Task(Id = call.Id, Status = 'Open') }
        );
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(null, after.Next_Action_Date__c, 'Already-processed Target skipped (R7)');
    }

    @IsTest
    static void testTaskWithNonTargetWhatIdIgnored() {
        // A completed sequence call whose WhatId is NOT a Target__c (e.g. an
        // Account) must be ignored (R4 only applies to Target-related calls).
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Task call = new Task(
            WhatId = acc.Id, Subject = 'Call X', Status = 'Open',
            ActivityDate = Date.today(), Is_Sequence_Call__c = true, Sequence_Step__c = 1
        );
        insert call;

        Test.startTest();
        call.Status = 'Completed';
        update call; // handler sees non-Target WhatId -> skip
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Target__c WHERE Next_Action_Date__c != null],
            'Non-Target WhatId -> nothing scheduled');
    }

    @IsTest
    static void testBulk200CallCompletions() {
        List<Target__c> targets = new List<Target__c>();
        for (Integer i = 0; i < 200; i++) {
            targets.add(newTarget('Bulk ' + i, true, 1));
        }
        insertTargets(targets, true);

        List<Task> calls = new List<Task>();
        for (Target__c t : targets) {
            calls.add(newCallTask(t.Id, 1, true));
        }
        insert calls;

        Test.startTest();
        for (Task c : calls) {
            c.Status = 'Completed';
        }
        Integer dmlBefore = Limits.getDmlStatements();
        Integer soqlBefore = Limits.getQueries();
        update calls; // single after-update for all 200
        Integer dmlAfter = Limits.getDmlStatements();
        Integer soqlAfter = Limits.getQueries();

        // The update DML itself + the handler's single Target update = 2 (R8).
        Assert.areEqual(2, dmlAfter - dmlBefore, 'One Target DML for 200 completions (R8)');
        // Handler issues exactly one SOQL for all related Targets (R8).
        Assert.areEqual(1, soqlAfter - soqlBefore, 'One SOQL for related Targets (R8)');

        // Assert synchronously before stopTest (the inactive-insert start
        // queueables flush at stopTest and would re-null step-1 dates).
        Integer scheduled = [
            SELECT COUNT() FROM Target__c WHERE Id IN :targets AND Next_Action_Date__c != null
        ];
        Assert.areEqual(200, scheduled, 'All 200 targets scheduled (R8)');
        Test.stopTest();
    }
}
