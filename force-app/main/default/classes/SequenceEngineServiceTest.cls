/**
 * Tests for SequenceEngineService — positive processStep (R8), each
 * Next_Trigger_Type__c branch (R9/R10/R11), inactive guard (R7), and a
 * 200-record bulk run proving one DML per object with no governor errors (R12).
 */
@IsTest
private class SequenceEngineServiceTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Engine Co', BillingCity = 'Denver');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Sam',
            LastName = 'Lead',
            Email = 'sam.lead@example.com',
            AccountId = acc.Id
        );
        insert con;

        // Insert INACTIVE so the TargetTrigger after-insert start path (feature
        // 03) does not enqueue the start queueable and create extra artifacts
        // during these direct-engine tests; then activate via update (the
        // after-insert branch does not re-fire on update). Persisted values match.
        Target__c t = new Target__c(
            Name = 'Engine Target',
            Company_Name__c = acc.Id,
            Primary_Contact__c = con.Id,
            Sequence_Active__c = false,
            Sequence_Step__c = 0,
            Days_Until_Next_Email__c = 4
        );
        insert t;
        t.Sequence_Active__c = true;
        update t;
    }

    private static Target__c reload(Id targetId) {
        // Query the full set of fields the engine + email service read, mirroring
        // TargetSelector so engine calls never hit unqueried-field exceptions.
        return [
            SELECT Id, Name, Sequence_Step__c, Next_Action_Date__c, Sequence_Active__c,
                   Primary_Contact__c, Sequence_Attachment_Id__c, Days_Until_Next_Email__c,
                   Status__c, Billing_City__c
            FROM Target__c WHERE Id = :targetId
        ];
    }

    private static List<Task> tasksFor(Id targetId) {
        return [
            SELECT Id, Subject, Status, ActivityDate, Is_Sequence_Call__c, Sequence_Step__c
            FROM Task WHERE WhatId = :targetId ORDER BY Is_Sequence_Call__c DESC
        ];
    }

    @IsTest
    static void testProcessStep1Positive() {
        Target__c t = reload([SELECT Id FROM Target__c LIMIT 1].Id);

        Test.startTest();
        SequenceEngineService.processStep(t, 1);
        Test.stopTest();

        // (a) email already counted by platform; (b)(c) tasks; (d) step advance.
        List<Task> tasks = tasksFor(t.Id);
        Assert.areEqual(2, tasks.size(), 'Exactly a Call task + a completed Email task (R8)');

        Task callTask;
        Task emailTask;
        for (Task tk : tasks) {
            if (tk.Is_Sequence_Call__c) { callTask = tk; } else { emailTask = tk; }
        }
        Assert.isNotNull(callTask, 'Call task created (R8b)');
        Assert.areEqual('Call 1', callTask.Subject, 'Call subject from config (R8b)');
        Assert.areEqual('Open', callTask.Status, 'Call task is Open (R8b)');
        Assert.areEqual(1, callTask.Sequence_Step__c, 'Call task step = 1 (R8b)');
        Assert.areEqual(Date.today().addDays(2), callTask.ActivityDate, 'ActivityDate = today+2 (R8b)');

        Assert.isNotNull(emailTask, 'Completed Email task created (R8c)');
        Assert.areEqual('Completed', emailTask.Status, 'Email task Completed (R8c)');
        Assert.isFalse(emailTask.Is_Sequence_Call__c, 'Email log task is not a sequence call (R8c)');
        Assert.areEqual('Email 1', emailTask.Subject, 'Email log task subject (R8c)');

        Target__c after = reload(t.Id);
        Assert.areEqual(1, after.Sequence_Step__c, 'Step advanced to 1 (R8d)');
        // Step 1 trigger = CallCompleted -> Next_Action_Date null (R10).
        Assert.areEqual(null, after.Next_Action_Date__c, 'Step 1 CallCompleted -> null (R10)');
    }

    @IsTest
    static void testTimerSchedulesNextActionDate() {
        // Step 6 config = Timer, Next_Wait_Days__c = 14 (R9).
        Target__c t = reload([SELECT Id FROM Target__c LIMIT 1].Id);
        t.Sequence_Step__c = 5;
        update t;

        Test.startTest();
        SequenceEngineService.processStep(t, 6);
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(6, after.Sequence_Step__c, 'Step advanced to 6');
        Assert.isNotNull(after.Next_Action_Date__c, 'Timer schedules Next_Action_Date (R9)');
        Datetime expected = Datetime.now().addDays(14);
        // within a 5-minute window of now+14d
        Long diffMs = Math.abs(after.Next_Action_Date__c.getTime() - expected.getTime());
        Assert.isTrue(diffMs < 5L * 60L * 1000L, 'Next_Action_Date ~ now + 14d (R9)');
    }

    @IsTest
    static void testNoneLeavesNextActionNull() {
        // Step 10 config = None (R11).
        Target__c t = reload([SELECT Id FROM Target__c LIMIT 1].Id);
        t.Sequence_Step__c = 9;
        update t;

        Test.startTest();
        SequenceEngineService.processStep(t, 10);
        Test.stopTest();

        Target__c after = reload(t.Id);
        Assert.areEqual(10, after.Sequence_Step__c, 'Step advanced to 10');
        Assert.areEqual(null, after.Next_Action_Date__c, 'Step 10 None -> null (R11)');
    }

    @IsTest
    static void testInactiveTargetGuard() {
        Target__c t = reload([SELECT Id FROM Target__c LIMIT 1].Id);
        t.Sequence_Active__c = false;
        t.Sequence_Step__c = 0;
        update t;

        Test.startTest();
        SequenceEngineService.processStep(t, 1);
        Test.stopTest();

        Assert.areEqual(0, tasksFor(t.Id).size(), 'Inactive -> no tasks (R7)');
        Assert.areEqual(0, Limits.getEmailInvocations(), 'Inactive -> no email (R7)');
        Target__c after = reload(t.Id);
        Assert.areEqual(0, after.Sequence_Step__c, 'Inactive -> step unchanged (R7)');
        Assert.areEqual(null, after.Next_Action_Date__c, 'Inactive -> no schedule (R7)');
    }

    @IsTest
    static void testNullArgsNoOp() {
        Test.startTest();
        SequenceEngineService.processStep(null, 1);
        SequenceEngineService.processStep(reload([SELECT Id FROM Target__c LIMIT 1].Id), null);
        SequenceEngineService.processSteps(null);
        SequenceEngineService.processSteps(new List<SequenceEngineService.StepRequest>());
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Task], 'No-op calls create nothing');
    }

    @IsTest
    static void testBulk200OneDmlPerObject() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        List<Target__c> targets = new List<Target__c>();
        for (Integer i = 0; i < 200; i++) {
            targets.add(new Target__c(
                Name = 'Bulk ' + i,
                Company_Name__c = acc.Id,
                Primary_Contact__c = con.Id,
                Sequence_Active__c = false,
                Sequence_Step__c = 0,
                Days_Until_Next_Email__c = 4
            ));
        }
        // Inactive insert avoids the feature-03 start queueable; activate after.
        insert targets;
        for (Target__c t : targets) {
            t.Sequence_Active__c = true;
        }
        update targets;

        List<SequenceEngineService.StepRequest> requests =
            new List<SequenceEngineService.StepRequest>();
        for (Target__c t : targets) {
            requests.add(new SequenceEngineService.StepRequest(t, 1));
        }

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        SequenceEngineService.processSteps(requests);
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        // One Task insert + one Target update = 2 DML statements across all 200. (R12)
        Assert.areEqual(2, dmlAfter - dmlBefore, 'One DML per object (Task insert + Target update) (R12)');

        Integer advanced = [
            SELECT COUNT() FROM Target__c WHERE Id IN :targets AND Sequence_Step__c = 1
        ];
        Assert.areEqual(200, advanced, 'All 200 targets advanced to step 1 (R12)');

        Integer callTasks = [
            SELECT COUNT() FROM Task WHERE WhatId IN :targets AND Is_Sequence_Call__c = true
        ];
        Assert.areEqual(200, callTasks, '200 Call tasks created (R12)');
    }

    @IsTest
    static void testUnknownStepNoConfigSkipped() {
        // Active target but a step number with no Sequence_Step_Config__mdt row:
        // engine must skip it (cfg == null branch) — nothing created. (R8 guard)
        Target__c t = reload([SELECT Id FROM Target__c LIMIT 1].Id);

        Test.startTest();
        SequenceEngineService.processStep(t, 999);
        Test.stopTest();

        Assert.areEqual(0, tasksFor(t.Id).size(), 'Unknown step (no config) -> no tasks');
        Target__c after = reload(t.Id);
        Assert.areEqual(0, after.Sequence_Step__c, 'Unknown step -> step unchanged');
    }

    @IsTest
    static void testDmlFailureSurfacesAsEngineException() {
        // Drive the partial-success error-handling branch (assertSaved): a Task
        // whose WhatId points at a deleted Target fails to insert in USER_MODE,
        // and the engine must surface it as a SequenceEngineException.
        Target__c t = reload([SELECT Id FROM Target__c LIMIT 1].Id);
        Id deletedId = t.Id;
        delete [SELECT Id FROM Target__c WHERE Id = :t.Id];

        Boolean threw = false;
        String msg;
        Test.startTest();
        try {
            // t still holds the (now deleted) Id; active flag carried in-memory.
            SequenceEngineService.processStep(t, 1);
        } catch (SequenceEngineService.SequenceEngineException e) {
            threw = true;
            msg = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'DML failure surfaces as SequenceEngineException (R12)');
        Assert.isTrue(
            msg != null && msg.contains('failed'),
            'Exception message names the failing DML context (R12)'
        );
    }

    @IsTest
    static void testMixedActiveInactiveBulk() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Target__c active = new Target__c(
            Name = 'Active', Company_Name__c = acc.Id, Primary_Contact__c = con.Id,
            Sequence_Active__c = false, Sequence_Step__c = 0, Days_Until_Next_Email__c = 4
        );
        Target__c inactive = new Target__c(
            Name = 'Inactive', Company_Name__c = acc.Id, Primary_Contact__c = con.Id,
            Sequence_Active__c = false, Sequence_Step__c = 0, Days_Until_Next_Email__c = 4
        );
        // Inactive insert avoids the feature-03 start queueable; activate the
        // one that must be processed after insert.
        insert new List<Target__c>{ active, inactive };
        active.Sequence_Active__c = true;
        update active;

        Test.startTest();
        SequenceEngineService.processSteps(new List<SequenceEngineService.StepRequest>{
            new SequenceEngineService.StepRequest(active, 1),
            new SequenceEngineService.StepRequest(inactive, 1)
        });
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Task WHERE WhatId = :active.Id], 'Active processed');
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :inactive.Id], 'Inactive skipped (R7)');
    }
}
