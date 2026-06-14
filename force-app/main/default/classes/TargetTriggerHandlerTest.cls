/**
 * Tests for TargetTrigger / TargetTriggerHandler / SequenceStartQueueable (R1, R2, R3, R7, R8).
 *
 * Inserting an active Target__c fires the after-insert branch, which enqueues
 * SequenceStartQueueable; after Test.stopTest the queueable runs and the engine
 * produces the step-1 artifacts (Email 1 in test context, open Call 1 task,
 * completed Email task, Sequence_Step__c = 1). Inactive inserts produce nothing.
 */
@IsTest
private class TargetTriggerHandlerTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Entry Co', BillingCity = 'Denver');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Eve',
            LastName = 'Entry',
            Email = 'eve.entry@example.com',
            AccountId = acc.Id
        );
        insert con;
    }

    private static Id accId { get { if (accId == null) { accId = [SELECT Id FROM Account LIMIT 1].Id; } return accId; } set; }
    private static Id conId { get { if (conId == null) { conId = [SELECT Id FROM Contact LIMIT 1].Id; } return conId; } set; }

    private static Target__c newTarget(String name, Boolean active) {
        return new Target__c(
            Name = name,
            Company_Name__c = accId,
            Primary_Contact__c = conId,
            Sequence_Active__c = active,
            Sequence_Step__c = 0,
            Days_Until_Next_Email__c = 4
        );
    }

    private static Target__c reload(Id targetId) {
        return [
            SELECT Id, Sequence_Step__c, Next_Action_Date__c, Sequence_Active__c,
                   Status__c, Sequence_Stop_Reason__c
            FROM Target__c WHERE Id = :targetId
        ];
    }

    /**
     * Seeds an INACTIVE target then flips it active in a separate update so the
     * feature-03 after-insert start queueable does not fire and create artifacts.
     * Used by the terminal-stop / kill-switch tests (05).
     */
    private static Target__c seedActiveMidCadence(String name, Integer step, Datetime nextDate) {
        Target__c t = newTarget(name, false);
        insert t;
        t.Sequence_Active__c = true;
        t.Sequence_Step__c = step;
        t.Next_Action_Date__c = nextDate;
        update t;
        return t;
    }

    private static List<Task> tasksFor(Id targetId) {
        return [
            SELECT Id, Subject, Status, Is_Sequence_Call__c, Sequence_Step__c
            FROM Task WHERE WhatId = :targetId ORDER BY Is_Sequence_Call__c DESC
        ];
    }

    @IsTest
    static void testActiveInsertStartsStep1() {
        Test.startTest();
        Target__c t = newTarget('Active Entry', true);
        insert t; // fires TargetTrigger after-insert -> enqueues queueable (R1)
        Test.stopTest(); // queueable runs here (R2)

        Target__c after = reload(t.Id);
        Assert.areEqual(1, after.Sequence_Step__c, 'Step advanced to 1 by the engine (R2)');
        // Step 1 = CallCompleted -> Next_Action_Date stays null until the call completes.
        Assert.areEqual(null, after.Next_Action_Date__c, 'Step 1 CallCompleted -> null (R2)');

        List<Task> tasks = tasksFor(t.Id);
        Assert.areEqual(2, tasks.size(), 'Open Call task + completed Email task (R2)');

        Task callTask;
        Task emailTask;
        for (Task tk : tasks) {
            if (tk.Is_Sequence_Call__c) { callTask = tk; } else { emailTask = tk; }
        }
        Assert.isNotNull(callTask, 'Call task created');
        Assert.areEqual('Open', callTask.Status, 'Call task is Open');
        Assert.areEqual(1, callTask.Sequence_Step__c, 'Call task step = 1');

        Assert.isNotNull(emailTask, 'Completed Email task created');
        Assert.areEqual('Completed', emailTask.Status, 'Email task Completed');
        Assert.isFalse(emailTask.Is_Sequence_Call__c, 'Email log task is not a sequence call');
    }

    @IsTest
    static void testInactiveInsertDoesNothing() {
        Test.startTest();
        Target__c t = newTarget('Inactive Entry', false);
        insert t;
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(0, after.Sequence_Step__c, 'Inactive -> step unchanged (R2 guard)');
        Assert.areEqual(null, after.Next_Action_Date__c, 'Inactive -> no schedule');
        Assert.areEqual(0, tasksFor(t.Id).size(), 'Inactive -> no tasks');
    }

    @IsTest
    static void testRecursionGuardSkipsAlreadyProcessedIds() {
        // The insert enqueues once and records the Id in the guard; a second
        // direct invocation with the same active Target must NOT re-enqueue (R7).
        Target__c t = newTarget('Guarded', true);
        insert t; // first enqueue happens; guard now holds t.Id
        Target__c reloaded = [
            SELECT Id, Sequence_Active__c FROM Target__c WHERE Id = :t.Id
        ];

        Test.startTest();
        Integer before = Limits.getQueueableJobs();
        TargetTriggerHandler.afterInsert(new List<Target__c>{ reloaded });
        Integer afterCount = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(before, afterCount, 'Already-processed Id is not re-enqueued (R7)');
    }

    @IsTest
    static void testInactiveInputNotEnqueued() {
        // An inactive Target passed to afterInsert must not be enqueued (R2/R6).
        Target__c t = newTarget('InactiveDirect', false);
        insert t;
        Target__c reloaded = [
            SELECT Id, Sequence_Active__c FROM Target__c WHERE Id = :t.Id
        ];

        Test.startTest();
        Integer before = Limits.getQueueableJobs();
        TargetTriggerHandler.afterInsert(new List<Target__c>{ reloaded });
        Integer afterCount = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(before, afterCount, 'Inactive Target is not enqueued');
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :t.Id], 'Inactive -> no artifacts');
    }

    @IsTest
    static void testEmptyAndNullInputNoOp() {
        Test.startTest();
        TargetTriggerHandler.afterInsert((List<Target__c>) null);
        TargetTriggerHandler.afterInsert(new List<Target__c>());
        new SequenceStartQueueable(null).execute(null);
        new SequenceStartQueueable(new Set<Id>()).execute(null);
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Task], 'No-op calls create nothing');
    }

    @IsTest
    static void testBulk200ActiveInsert() {
        List<Target__c> targets = new List<Target__c>();
        for (Integer i = 0; i < 200; i++) {
            targets.add(newTarget('Bulk ' + i, true));
        }

        Test.startTest();
        insert targets; // one after-insert, one enqueue (R1, R8)
        Test.stopTest(); // queueable runs -> engine one DML per object (R8)

        Integer advanced = [
            SELECT COUNT() FROM Target__c WHERE Id IN :targets AND Sequence_Step__c = 1
        ];
        Assert.areEqual(200, advanced, 'All 200 targets advanced to step 1 (R8)');

        Integer callTasks = [
            SELECT COUNT() FROM Task WHERE WhatId IN :targets AND Is_Sequence_Call__c = true
        ];
        Assert.areEqual(200, callTasks, '200 Call tasks created (R8)');
    }

    // =====================================================================
    // 05_terminal_stop_and_guards — before-update terminal-status stop
    // =====================================================================

    /**
     * R1/R2/R8: changing Status__c to each terminal value on an ACTIVE target
     * flips Sequence_Active__c=false, writes the matching Sequence_Stop_Reason__c
     * (CMDT Status_Value__c -> Stop_Reason__c is identity), and clears
     * Next_Action_Date__c — all in the before-update context with NO extra DML
     * for the stamp (one update DML statement total).
     */
    @IsTest
    static void testEachTerminalStatusStopsActiveTarget() {
        Map<String, String> expected = new Map<String, String>{
            'Converted' => 'Converted',
            'Meeting Booked' => 'Meeting Booked',
            'Do Not Contact' => 'Do Not Contact',
            'Replied' => 'Replied'
        };

        // Baseline: a NON-terminal status-change update on an identical active
        // target — captures any org-side automation DML so the terminal-stamp
        // assertion isolates the branch's OWN added DML (which must be zero, R2).
        Target__c baseline = seedActiveMidCadence(
            'Term Baseline', 5, Datetime.now().addDays(4)
        );

        Test.startTest();
        baseline.Status__c = 'Interested'; // non-terminal change -> branch does NOTHING
        Integer baseBefore = Limits.getDmlStatements();
        update baseline;
        Integer baselineDml = Limits.getDmlStatements() - baseBefore;

        for (String terminal : expected.keySet()) {
            Target__c t = seedActiveMidCadence(
                'Term ' + terminal, 5, Datetime.now().addDays(4)
            );

            t.Status__c = terminal;
            Integer dmlBefore = Limits.getDmlStatements();
            update t; // fires before-update terminal stop (R1, R2)
            Integer terminalDml = Limits.getDmlStatements() - dmlBefore;

            // R2: the before-update stamp mutates Trigger.new only — it adds NO DML
            // beyond what the same update already costs (baseline).
            Assert.areEqual(
                baselineDml, terminalDml,
                'Before-update stamp adds no DML beyond a normal update (R2): ' + terminal
            );

            Target__c after = reload(t.Id);
            Assert.isFalse(after.Sequence_Active__c, 'Deactivated by terminal status (R1): ' + terminal);
            Assert.areEqual(
                expected.get(terminal), after.Sequence_Stop_Reason__c,
                'Stop reason written from CMDT (R1): ' + terminal
            );
            Assert.areEqual(null, after.Next_Action_Date__c, 'Next action cleared (R1): ' + terminal);
        }
        Test.stopTest();
    }

    /**
     * R3: an update that does NOT change Status__c performs no stop action even if
     * Status__c already holds a (non-terminal) value.
     */
    @IsTest
    static void testUnchangedStatusNoStop() {
        Target__c t = seedActiveMidCadence('NoChange', 5, Datetime.now().addDays(4));
        // Set a non-terminal status, then update again WITHOUT changing it.
        t.Status__c = 'In-Process';
        update t;

        Test.startTest();
        t.Sequence_Step__c = 6; // change a different field; Status__c stays In-Process
        update t;
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.isTrue(after.Sequence_Active__c, 'Unchanged status -> still active (R3)');
        Assert.areEqual(null, after.Sequence_Stop_Reason__c, 'Unchanged status -> no stop reason (R3)');
        Assert.areEqual(6, after.Sequence_Step__c, 'Other field still updates normally');
    }

    /**
     * R4: a target that is already inactive is not touched, even when Status__c
     * changes to a terminal value.
     */
    @IsTest
    static void testAlreadyInactiveNoStop() {
        Target__c t = newTarget('AlreadyInactive', false);
        insert t; // inactive at insert -> no start queueable
        t.Sequence_Step__c = 5;
        update t;

        Test.startTest();
        t.Status__c = 'Converted'; // terminal, but target already inactive
        update t;
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.isFalse(after.Sequence_Active__c, 'Stays inactive (R4)');
        Assert.areEqual(
            null, after.Sequence_Stop_Reason__c,
            'No stop reason stamped on an already-inactive target (R4)'
        );
    }

    /**
     * Negative: changing Status__c to a NON-terminal value leaves an active
     * target untouched (only the four CMDT values are terminal).
     */
    @IsTest
    static void testNonTerminalStatusChangeNoStop() {
        Target__c t = seedActiveMidCadence('NonTerminal', 5, Datetime.now().addDays(4));

        Test.startTest();
        t.Status__c = 'Closed'; // existing non-terminal value
        update t;
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.isTrue(after.Sequence_Active__c, 'Non-terminal change -> still active');
        Assert.areEqual(null, after.Sequence_Stop_Reason__c, 'Non-terminal change -> no stop reason');
        Assert.areEqual('Closed', after.Status__c, 'Status update itself succeeds');
    }

    /**
     * R6 kill switch (auto): a target auto-deactivated via a terminal status is no
     * longer advanced or sent by the scheduler (04). After deactivation the batch
     * neither advances Sequence_Step__c nor sends an email.
     */
    @IsTest
    static void testKillSwitchAutoTerminalStopsScheduler() {
        Target__c t = seedActiveMidCadence('AutoKill', 6, Datetime.now().addHours(-1));

        // Auto-deactivate via terminal status (R1) — before-update stamp.
        t.Status__c = 'Do Not Contact';
        update t;
        Integer stepBefore = reload(t.Id).Sequence_Step__c.intValue();

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        Database.executeBatch(new SequenceSchedulerBatch(), 200);
        Test.stopTest();
        Integer emailsAfter = Limits.getEmailInvocations();

        Target__c after = reload(t.Id);
        Assert.isFalse(after.Sequence_Active__c, 'Still inactive after run (R6)');
        Assert.areEqual(stepBefore, after.Sequence_Step__c.intValue(), 'Step unchanged — not advanced (R6)');
        Assert.areEqual(emailsBefore, emailsAfter, 'No email sent for deactivated target (R6)');
        Assert.areEqual(
            0, [SELECT COUNT() FROM Task WHERE WhatId = :t.Id AND Is_Sequence_Call__c = true],
            'No new Call task for deactivated target (R6)'
        );
    }

    /**
     * R6 kill switch (manual): a target manually unchecked (Sequence_Active__c =
     * false) mid-cadence is likewise not advanced or sent by the scheduler.
     */
    @IsTest
    static void testKillSwitchManualUncheckStopsScheduler() {
        Target__c t = seedActiveMidCadence('ManualKill', 6, Datetime.now().addHours(-1));

        // Manual uncheck (no status change).
        t.Sequence_Active__c = false;
        update t;
        Integer stepBefore = reload(t.Id).Sequence_Step__c.intValue();

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        Database.executeBatch(new SequenceSchedulerBatch(), 200);
        Test.stopTest();
        Integer emailsAfter = Limits.getEmailInvocations();

        Target__c after = reload(t.Id);
        Assert.isFalse(after.Sequence_Active__c, 'Still inactive after run (R6)');
        Assert.areEqual(stepBefore, after.Sequence_Step__c.intValue(), 'Step unchanged — not advanced (R6)');
        Assert.areEqual(emailsBefore, emailsAfter, 'No email sent for manually-stopped target (R6)');
    }

    /**
     * R7: 200-record bulk update to a terminal status in one transaction
     * deactivates all 200 with the correct stop reason and cleared dates, with no
     * governor errors and no extra DML for the stamp (before-update mutation).
     */
    @IsTest
    static void testBulk200TerminalStop() {
        List<Target__c> targets = new List<Target__c>();
        for (Integer i = 0; i < 200; i++) {
            targets.add(newTarget('BulkTerm ' + i, false));
        }
        insert targets; // inactive -> no start queueable
        for (Target__c t : targets) {
            t.Sequence_Active__c = true;
            t.Sequence_Step__c = 5;
            t.Next_Action_Date__c = Datetime.now().addDays(4);
        }
        update targets; // activate; non-terminal -> no stop

        Test.startTest();
        // Baseline: a non-terminal bulk status change on the same 200 records —
        // the branch does nothing, capturing org-side automation DML cost.
        for (Target__c t : targets) {
            t.Status__c = 'Interested';
        }
        Integer baseBefore = Limits.getDmlStatements();
        update targets;
        Integer baselineDml = Limits.getDmlStatements() - baseBefore;

        // Now the terminal bulk change: the before-update stamp must add no DML
        // beyond the baseline (pure in-memory mutation of Trigger.new) (R7).
        for (Target__c t : targets) {
            t.Status__c = 'Meeting Booked';
        }
        Integer dmlBefore = Limits.getDmlStatements();
        update targets;
        Integer terminalDml = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(
            baselineDml, terminalDml,
            'Bulk terminal stamp adds no DML beyond a normal bulk update for 200 (R7)'
        );

        Integer stopped = [
            SELECT COUNT() FROM Target__c
            WHERE Id IN :targets
              AND Sequence_Active__c = false
              AND Sequence_Stop_Reason__c = 'Meeting Booked'
              AND Next_Action_Date__c = null
        ];
        Assert.areEqual(200, stopped, 'All 200 deactivated with stop reason + cleared date (R7)');
    }

    /**
     * Guard coverage: null/empty inputs and a null oldMap are safe no-ops.
     */
    @IsTest
    static void testBeforeUpdateGuardInputsNoOp() {
        Test.startTest();
        TargetTriggerHandler.beforeUpdate(null, new Map<Id, Target__c>());
        TargetTriggerHandler.beforeUpdate(new List<Target__c>(), new Map<Id, Target__c>());
        TargetTriggerHandler.beforeUpdate(
            new List<Target__c>{ newTarget('x', true) }, null
        );
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Task], 'Guarded no-op calls create nothing');
    }
}
