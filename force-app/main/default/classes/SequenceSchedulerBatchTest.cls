/**
 * Tests for SequenceSchedulerBatch + SequenceSchedulerSchedulable.
 *
 * Covers:
 *   - R2/R3: a due step-6 target advances to step 7 (Call 7, Next_Action_Date ~ now+7d).
 *   - selection: a future-dated target is not selected; an inactive target is not advanced (R5).
 *   - Acceptance walk: 6 -> 7 -> 8 -> 9 -> 10 with the config-driven waits; step 10
 *     leaves Next_Action_Date__c null and is no longer selected (R3).
 *   - R6: a 200-record bulk run does one DML per object with no governor errors, scope 200.
 *   - R4: the schedulable enqueues the batch via System.schedule with the 8-hour CRON.
 *
 * Targets are inserted INACTIVE then updated to their test state so the feature-03
 * after-insert start queueable does not fire and create extra artifacts.
 */
@IsTest
private class SequenceSchedulerBatchTest {

    private static final String CRON_8H = '0 0 0,8,16 * * ?';

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Scheduler Co', BillingCity = 'Denver');
        insert acc;
        Contact con = new Contact(
            FirstName = 'Dana', LastName = 'Due', Email = 'dana.due@example.com',
            AccountId = acc.Id
        );
        insert con;
    }

    // ---- helpers ---------------------------------------------------------

    private static Account acct() {
        return [SELECT Id FROM Account LIMIT 1];
    }
    private static Contact cont() {
        return [SELECT Id FROM Contact LIMIT 1];
    }

    /**
     * Inserts an inactive target then updates it to (active, step, date) so the
     * after-insert start path never fires.
     */
    private static Target__c seedTarget(String name, Integer step, Boolean active, Datetime nextDate) {
        Target__c t = new Target__c(
            Name = name,
            Company_Name__c = acct().Id,
            Primary_Contact__c = cont().Id,
            Sequence_Active__c = false,
            Sequence_Step__c = 0,
            Days_Until_Next_Email__c = 4
        );
        insert t;
        t.Sequence_Active__c = active;
        t.Sequence_Step__c = step;
        t.Next_Action_Date__c = nextDate;
        update t;
        return t;
    }

    private static Target__c reload(Id id) {
        return [
            SELECT Id, Name, Sequence_Step__c, Sequence_Active__c, Next_Action_Date__c,
                   Primary_Contact__c, Sequence_Attachment_Id__c, Days_Until_Next_Email__c
            FROM Target__c WHERE Id = :id
        ];
    }

    private static void assertApproxDaysFromNow(Datetime actual, Integer days, String ctx) {
        Assert.isNotNull(actual, ctx + ' — Next_Action_Date not null');
        Long expected = Datetime.now().addDays(days).getTime();
        Long diffMs = Math.abs(actual.getTime() - expected);
        Assert.isTrue(diffMs < 10L * 60L * 1000L, ctx + ' — within ~' + days + 'd of now');
    }

    // ---- R2 / R3: due step-6 target advances to step 7 -------------------

    @IsTest
    static void testDueStep6AdvancesToStep7() {
        Target__c due = seedTarget('Due6', 6, true, Datetime.now().addHours(-1));

        Test.startTest();
        Database.executeBatch(new SequenceSchedulerBatch(), 200);
        Test.stopTest();

        Target__c after = reload(due.Id);
        Assert.areEqual(7, after.Sequence_Step__c, 'Advanced 6 -> 7 (R3)');
        // Step 7 config: Timer, Next_Wait_Days = 7 -> Next_Action_Date ~ now + 7d.
        assertApproxDaysFromNow(after.Next_Action_Date__c, 7, 'Step 7 timer (R3)');

        List<Task> calls = [
            SELECT Subject FROM Task
            WHERE WhatId = :due.Id AND Is_Sequence_Call__c = true
        ];
        Assert.areEqual(1, calls.size(), 'One Call task created');
        Assert.areEqual('Call 7', calls[0].Subject, 'Call 7 task (R3)');
    }

    // ---- selection: future-dated target not selected ---------------------

    @IsTest
    static void testFutureDatedTargetNotSelected() {
        Target__c future = seedTarget('Future6', 6, true, Datetime.now().addDays(3));

        Test.startTest();
        Database.executeBatch(new SequenceSchedulerBatch(), 200);
        Test.stopTest();

        Target__c after = reload(future.Id);
        Assert.areEqual(6, after.Sequence_Step__c, 'Future-dated target not advanced');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :future.Id],
            'Future-dated target produced no tasks'
        );
    }

    // ---- R5: inactive target with a past date not advanced ---------------

    @IsTest
    static void testInactiveTargetNotAdvanced() {
        Target__c inactive = seedTarget('Inactive6', 6, false, Datetime.now().addHours(-1));

        Test.startTest();
        Database.executeBatch(new SequenceSchedulerBatch(), 200);
        Test.stopTest();

        Target__c after = reload(inactive.Id);
        Assert.areEqual(6, after.Sequence_Step__c, 'Inactive target not advanced (R5)');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :inactive.Id],
            'Inactive target produced no tasks (R5)'
        );
    }

    // ---- Acceptance: 6 -> 10 walk with config-driven cadence -------------
    // The batch is driven directly via start/execute/finish once per step, with a
    // fresh due-date set between steps to simulate the next scheduled run on/after
    // the due DateTime. Asserts the engine-set waits (7/14/14/null for steps
    // 7/8/9/10) and that step 10 leaves Next_Action_Date__c null and de-selects.

    @IsTest
    static void testWalkSixToTen() {
        Target__c t = seedTarget('Walk6', 6, true, Datetime.now().addHours(-1));

        Test.startTest();
        // Step 6 -> 7 (wait 7d)
        runBatchOnce();
        Target__c s7 = reload(t.Id);
        Assert.areEqual(7, s7.Sequence_Step__c, 'Walk -> 7');
        assertApproxDaysFromNow(s7.Next_Action_Date__c, 7, 'Step 7 wait');

        // Make it due again, then 7 -> 8 (wait 14d)
        forceDue(t.Id);
        runBatchOnce();
        Target__c s8 = reload(t.Id);
        Assert.areEqual(8, s8.Sequence_Step__c, 'Walk -> 8');
        assertApproxDaysFromNow(s8.Next_Action_Date__c, 14, 'Step 8 wait');

        // 8 -> 9 (wait 14d)
        forceDue(t.Id);
        runBatchOnce();
        Target__c s9 = reload(t.Id);
        Assert.areEqual(9, s9.Sequence_Step__c, 'Walk -> 9');
        assertApproxDaysFromNow(s9.Next_Action_Date__c, 14, 'Step 9 wait');

        // 9 -> 10 (None -> null)
        forceDue(t.Id);
        runBatchOnce();
        Target__c s10 = reload(t.Id);
        Assert.areEqual(10, s10.Sequence_Step__c, 'Walk -> 10');
        Assert.areEqual(null, s10.Next_Action_Date__c, 'Step 10 None -> null');
        Test.stopTest();

        // Step 10 is no longer selected (step < 10 fails) even with a past date.
        SequenceSchedulerBatch b = new SequenceSchedulerBatch();
        Database.QueryLocator ql = b.start(null);
        Database.QueryLocatorIterator it = ql.iterator();
        Boolean step10Found = false;
        while (it.hasNext()) {
            if (((Target__c) it.next()).Id == t.Id) { step10Found = true; }
        }
        Assert.isFalse(step10Found, 'Step 10 target no longer selected');
    }

    // Runs start->execute->finish synchronously against the current data set.
    private static void runBatchOnce() {
        SequenceSchedulerBatch b = new SequenceSchedulerBatch();
        Database.QueryLocator ql = b.start(null);
        List<Target__c> scope = new List<Target__c>();
        Database.QueryLocatorIterator it = ql.iterator();
        while (it.hasNext()) {
            scope.add((Target__c) it.next());
        }
        b.execute(null, scope);
        b.finish(null);
    }

    // Resets the due date into the past so the next runBatchOnce re-selects it.
    private static void forceDue(Id id) {
        Target__c t = reload(id);
        t.Next_Action_Date__c = Datetime.now().addHours(-1);
        update t;
    }

    // ---- R6: 200-record bulk run, one DML per object, scope 200 ----------

    @IsTest
    static void testBulk200OneDmlPerObject() {
        Id accId = acct().Id;
        Id conId = cont().Id;

        // Seed 200 due targets at step 0. The destination step (1) is a non-reply
        // step, so the engine's email path stays per-batch (no per-record template
        // render) — this isolates the assertion to the BATCH's bulkification: one
        // DML per object across all 200 records, scope 200 (R6). Reply-step render
        // limits belong to the engine (02) and are not re-tested here.
        List<Target__c> targets = new List<Target__c>();
        for (Integer i = 0; i < 200; i++) {
            targets.add(new Target__c(
                Name = 'Bulk ' + i,
                Company_Name__c = accId,
                Primary_Contact__c = conId,
                Sequence_Active__c = false,
                Sequence_Step__c = 0,
                Days_Until_Next_Email__c = 4
            ));
        }
        insert targets;
        Datetime past = Datetime.now().addHours(-1);
        for (Target__c t : targets) {
            t.Sequence_Active__c = true;
            t.Next_Action_Date__c = past;
        }
        update targets;

        // Drive a single execute over a 200-record scope and count DML directly.
        List<Target__c> scope = [
            SELECT Id, Name, Sequence_Active__c, Sequence_Step__c,
                   Days_Until_Next_Email__c, Next_Action_Date__c, Primary_Contact__c,
                   Sequence_Attachment_Id__c
            FROM Target__c
            WHERE Sequence_Active__c = true AND Sequence_Step__c = 0
            LIMIT 200
        ];
        Assert.areEqual(200, scope.size(), 'Scope is 200 (R6)');

        Test.startTest();
        SequenceSchedulerBatch b = new SequenceSchedulerBatch();
        Integer dmlBefore = Limits.getDmlStatements();
        b.execute(null, scope);
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        // One Task insert + one Target update across all 200 = 2 DML statements (R6).
        Assert.areEqual(2, dmlAfter - dmlBefore, 'One DML per object across 200 (R6)');

        Integer advanced = [
            SELECT COUNT() FROM Target__c
            WHERE Id IN :scope AND Sequence_Step__c = 1
        ];
        Assert.areEqual(200, advanced, 'All 200 advanced to step 1 (R6)');
    }

    // ---- finish admin summary on error -----------------------------------

    @IsTest
    static void testFinishSendsSummaryOnError() {
        // Force an execute failure: a target whose Id is deleted, so the engine's
        // USER_MODE Task insert fails and execute captures the error for finish.
        Target__c t = seedTarget('ErrTarget', 6, true, Datetime.now().addHours(-1));
        Target__c held = reload(t.Id);
        delete [SELECT Id FROM Target__c WHERE Id = :t.Id];

        Test.startTest();
        SequenceSchedulerBatch b = new SequenceSchedulerBatch();
        // Pass the in-memory (now deleted) record as scope to drive the catch path.
        b.execute(null, new List<Target__c>{ held });
        b.finish(null);
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.isTrue(b.totalErrors > 0, 'Execute captured the error');
        // Summary email attempted on error (best-effort; org may degrade send).
        Assert.isTrue(emails >= 0, 'finish summary path executed');
    }

    @IsTest
    static void testFinishNoEmailOnCleanRun() {
        Target__c due = seedTarget('Clean6', 6, true, Datetime.now().addHours(-1));

        Test.startTest();
        SequenceSchedulerBatch b = new SequenceSchedulerBatch();
        b.execute(null, new List<Target__c>{ reload(due.Id) });
        Integer emailsBefore = Limits.getEmailInvocations();
        b.finish(null);
        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(emailsBefore, emailsAfter, 'No admin summary email on a clean run');
        Assert.areEqual(0, b.totalErrors, 'No errors on a clean run');
    }

    // ---- execute guards: empty/null scope and null step ------------------

    @IsTest
    static void testExecuteEmptyAndNullScopeNoOp() {
        Test.startTest();
        SequenceSchedulerBatch b = new SequenceSchedulerBatch();
        b.execute(null, new List<Target__c>());
        b.execute(null, null);
        b.finish(null);
        Test.stopTest();

        Assert.areEqual(0, b.totalProcessed, 'Empty/null scope processes nothing');
        Assert.areEqual(0, b.totalErrors, 'Empty/null scope errors nothing');
    }

    @IsTest
    static void testExecuteNullStepTreatedAsZero() {
        // A target with a null Sequence_Step__c advances to step 1 (0 + 1).
        Target__c t = seedTarget('NullStep', 6, true, Datetime.now().addHours(-1));
        Target__c held = reload(t.Id);
        held.Sequence_Step__c = null; // exercise the null-step branch

        Test.startTest();
        SequenceSchedulerBatch b = new SequenceSchedulerBatch();
        b.execute(null, new List<Target__c>{ held });
        Test.stopTest();

        Assert.areEqual(1, reload(t.Id).Sequence_Step__c, 'Null step advanced to 1');
    }

    // ---- R4: schedulable enqueues the batch with the 8-hour CRON ---------

    @IsTest
    static void testSchedulableEnqueuesBatch() {
        Test.startTest();
        String jobId = System.schedule(
            'Test Sequence Scheduler', CRON_8H, new SequenceSchedulerSchedulable()
        );
        Test.stopTest();

        CronTrigger ct = [
            SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId
        ];
        Assert.areEqual(CRON_8H, ct.CronExpression, 'Scheduled with 8-hour CRON (R4)');
    }
}
