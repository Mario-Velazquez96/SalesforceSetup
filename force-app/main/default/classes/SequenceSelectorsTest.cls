/**
 * Tests for TargetSelector, TaskSelector, ContentSelector and
 * SequenceStepConfigService (R1, R2).
 */
@IsTest
private class SequenceSelectorsTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Sel Co', BillingCity = 'Reno');
        insert acc;
        Contact con = new Contact(
            FirstName = 'Lee', LastName = 'Contact', Email = 'lee@example.com', AccountId = acc.Id
        );
        insert con;
        // Insert INACTIVE so the TargetTrigger after-insert start path (feature
        // 03) does not enqueue the start queueable and perturb these selector
        // fixtures; then activate via update (which does not fire the
        // after-insert branch). The persisted field values are identical.
        Target__c t = new Target__c(
            Name = 'Sel Target', Company_Name__c = acc.Id, Primary_Contact__c = con.Id,
            Sequence_Active__c = false, Sequence_Step__c = 3, Days_Until_Next_Email__c = 4,
            Next_Action_Date__c = Datetime.now().addDays(-1)
        );
        insert t;
        t.Sequence_Active__c = true;
        update t;
    }

    @IsTest
    static void testTargetSelectorGetByIds() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        Test.startTest();
        List<Target__c> result = new TargetSelector().getByIds(new Set<Id>{ t.Id });
        List<Target__c> empty = new TargetSelector().getByIds(new Set<Id>());
        List<Target__c> nullArg = new TargetSelector().getByIds(null);
        Test.stopTest();
        Assert.areEqual(1, result.size(), 'getByIds returns the target (R2)');
        Assert.areEqual(0, empty.size(), 'empty set -> empty list');
        Assert.areEqual(0, nullArg.size(), 'null -> empty list');
    }

    @IsTest
    static void testTargetSelectorGetDueForScheduler() {
        Test.startTest();
        List<Target__c> due = new TargetSelector().getDueForScheduler(Datetime.now());
        Test.stopTest();
        Assert.areEqual(1, due.size(), 'Active, due, step<10 target is returned (R2)');
    }

    @IsTest
    static void testTaskSelector() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        insert new Task(
            WhatId = t.Id, Subject = 'Call X', Status = 'Open',
            Is_Sequence_Call__c = true, Sequence_Step__c = 1
        );
        insert new Task(
            WhatId = t.Id, Subject = 'Email X', Status = 'Completed',
            Is_Sequence_Call__c = false, Sequence_Step__c = 1
        );

        Test.startTest();
        List<Task> all = new TaskSelector().getByWhatIds(new Set<Id>{ t.Id });
        List<Task> calls = new TaskSelector().getSequenceCalls(new Set<Id>{ t.Id });
        List<Task> emptyAll = new TaskSelector().getByWhatIds(null);
        List<Task> emptyCalls = new TaskSelector().getSequenceCalls(new Set<Id>());
        Test.stopTest();

        Assert.areEqual(2, all.size(), 'getByWhatIds returns both tasks (R2)');
        Assert.areEqual(1, calls.size(), 'getSequenceCalls returns only call tasks (R2)');
        Assert.areEqual(0, emptyAll.size(), 'null -> empty');
        Assert.areEqual(0, emptyCalls.size(), 'empty set -> empty');
    }

    @IsTest
    static void testContentSelector() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title = 'File', PathOnClient = 'file.txt', VersionData = Blob.valueOf('x')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId, LinkedEntityId = t.Id, ShareType = 'V'
        );

        Test.startTest();
        ContentSelector sel = new ContentSelector();
        Map<Id, ContentVersion> byDoc = sel.getLatestVersionsByDocumentId(new Set<Id>{ docId });
        Id latestId = sel.getLatestVersionId(docId);
        Map<Id, ContentVersion> emptyMap = sel.getLatestVersionsByDocumentId(null);
        Id nullLatest = sel.getLatestVersionId(null);
        Test.stopTest();

        Assert.areEqual(1, byDoc.size(), 'latest version resolved by doc id (R2)');
        Assert.areEqual(cv.Id, latestId, 'latest version id matches (R2)');
        Assert.areEqual(0, emptyMap.size(), 'null docs -> empty map');
        Assert.areEqual(null, nullLatest, 'null doc -> null id');
    }

    @IsTest
    static void testConfigService() {
        Test.startTest();
        Map<Integer, Sequence_Step_Config__mdt> byStep = SequenceStepConfigService.getByStep();
        Map<Integer, Sequence_Step_Config__mdt> cached = SequenceStepConfigService.getByStep();
        Sequence_Step_Config__mdt step6 = SequenceStepConfigService.get(6);
        Sequence_Step_Config__mdt missing = SequenceStepConfigService.get(999);
        Test.stopTest();

        Assert.areEqual(10, byStep.size(), 'All 10 step configs keyed by step (R1)');
        Assert.isTrue(byStep === cached, 'Second call returns cached map (R1)');
        Assert.isNotNull(step6, 'Step 6 config exists (R1)');
        Assert.areEqual('Timer', step6.Next_Trigger_Type__c, 'Step 6 is a Timer step (R1)');
        Assert.areEqual(14, Integer.valueOf(step6.Next_Wait_Days__c), 'Step 6 waits 14 days (R1)');
        Assert.areEqual(null, missing, 'Unknown step -> null (R1)');
    }
}
