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
            SELECT Id, Sequence_Step__c, Next_Action_Date__c, Sequence_Active__c
            FROM Target__c WHERE Id = :targetId
        ];
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
}
