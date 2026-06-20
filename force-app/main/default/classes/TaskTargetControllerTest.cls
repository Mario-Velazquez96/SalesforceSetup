@isTest
public class TaskTargetControllerTest {
    
    @TestSetup
    static void setupData() {
        
        // Create Account
        Account acc = new Account(
            Name      = 'Test Account',
            Region__c = 'Midwest'
        );
        insert acc;
        
        // Create Engagement
        Engagement__c eng = new Engagement__c(
            Name = 'Test Engagement'
        );
        insert eng;
        
        // Create Target__c
        // Sequence_Active__c = false keeps the cadence TargetTrigger from
        // enrolling this Target (which would create an extra 'Call 1' Task and
        // skew the task counts asserted below). Test-data only.
        Target__c target = new Target__c(
            Name              = 'Test Target',
            Company_Name__c   = acc.Id,
            Engagement__c     = eng.Id,
            Sequence_Active__c = false
        );
        insert target;
        
        // Create open Task 1 related to Target
        Task t1 = new Task(
            Subject      = 'Test Task 1',
            ActivityDate = Date.today().addDays(5),
            Status       = 'Not Started',
            OwnerId      = UserInfo.getUserId(),
            WhatId       = target.Id
        );
        insert t1;
        
        // Create open Task 2 related to Target
        Task t2 = new Task(
            Subject      = 'Test Task 2',
            ActivityDate = Date.today().addDays(10),
            Status       = 'In Progress',
            OwnerId      = UserInfo.getUserId(),
            WhatId       = target.Id
        );
        insert t2;
        
        // Create a closed Task (should NOT appear)
        Task t3 = new Task(
            Subject      = 'Closed Task',
            ActivityDate = Date.today(),
            Status       = 'Completed',
            OwnerId      = UserInfo.getUserId(),
            WhatId       = target.Id
        );
        insert t3;
        
        // Create a Task related to Account (should NOT appear)
        Task t4 = new Task(
            Subject      = 'Account Task',
            ActivityDate = Date.today().addDays(3),
            Status       = 'Not Started',
            OwnerId      = UserInfo.getUserId(),
            WhatId       = acc.Id
        );
        insert t4;
    }
    
    // Helper to call with default page params
    private static TaskTargetController.ResultWrapper fetchPage(Integer pageSize, Integer offset) {
        return TaskTargetController.getTargetTasks(pageSize, offset);
    }
    
    @isTest
    static void testGetTargetTasks_returnsOpenTargetTasks() {
        Test.startTest();
        TaskTargetController.ResultWrapper result = fetchPage(50, 0);
        Test.stopTest();
        
        System.assertNotEquals(null, result,       'Result wrapper should not be null');
        System.assertNotEquals(null, result.tasks, 'Tasks list should not be null');
        System.assertEquals(2, result.tasks.size(),    'Should return 2 open Target tasks');
        System.assertEquals(2, result.totalRecords,    'totalRecords should be 2');
        System.assertEquals(false, result.hasMore,     'hasMore should be false for 2 records with pageSize 50');
    }
    
    @isTest
    static void testGetTargetTasks_fieldsPopulated() {
        Test.startTest();
        TaskTargetController.ResultWrapper result = fetchPage(50, 0);
        Test.stopTest();
        
        System.assertNotEquals(null, result.tasks, 'Tasks should not be null');
        System.assert(result.tasks.size() > 0, 'Should have at least one task');
        
        TaskTargetController.TaskWrapper tw = result.tasks[0];
        
        System.assertNotEquals(null, tw.taskId,    'taskId should not be null');
        System.assertNotEquals(null, tw.subject,   'subject should not be null');
        System.assertNotEquals(null, tw.targetId,  'targetId should not be null');
        System.assertNotEquals(null, tw.targetName,'targetName should not be null');
        System.assert(String.isNotBlank(tw.assignedTo), 'assignedTo should not be blank');
        System.assertEquals('Midwest',         tw.region,     'Region should be Midwest');
        System.assertEquals('Test Engagement', tw.engagement, 'Engagement name should match');
    }
    
    @isTest
    static void testGetTargetTasks_excludesClosedTasks() {
        Test.startTest();
        TaskTargetController.ResultWrapper result = fetchPage(50, 0);
        Test.stopTest();
        
        for (TaskTargetController.TaskWrapper tw : result.tasks) {
            System.assertNotEquals('Closed Task', tw.subject, 'Closed tasks should not be returned');
        }
    }
    
    @isTest
    static void testGetTargetTasks_excludesNonTargetTasks() {
        Test.startTest();
        TaskTargetController.ResultWrapper result = fetchPage(50, 0);
        Test.stopTest();
        
        for (TaskTargetController.TaskWrapper tw : result.tasks) {
            System.assertNotEquals('Account Task', tw.subject, 'Non-Target tasks should not be returned');
        }
    }
    
    @isTest
    static void testGetTargetTasks_noTasks() {
        delete [SELECT Id FROM Task];
        
        Test.startTest();
        TaskTargetController.ResultWrapper result = fetchPage(50, 0);
        Test.stopTest();
        
        System.assertNotEquals(null, result,            'Result should not be null');
        System.assertNotEquals(null, result.tasks,      'Tasks list should not be null');
        System.assertEquals(0,     result.tasks.size(), 'Should return empty list');
        System.assertEquals(0,     result.totalRecords, 'totalRecords should be 0');
        System.assertEquals(false, result.hasMore,      'hasMore should be false');
    }
    
    @isTest
    static void testGetTargetTasks_pagination() {
        // Add 3 more tasks to test pagination (total = 5 open target tasks)
        Target__c target = [SELECT Id FROM Target__c WHERE Name = 'Test Target' LIMIT 1];
        
        List<Task> extraTasks = new List<Task>();
        for (Integer i = 1; i <= 3; i++) {
            extraTasks.add(new Task(
                Subject      = 'Extra Task ' + i,
                ActivityDate = Date.today().addDays(i),
                Status       = 'Not Started',
                OwnerId      = UserInfo.getUserId(),
                WhatId       = target.Id
            ));
        }
        insert extraTasks;
        
        Test.startTest();
        // Page 1: pageSize=3, offset=0 → should return 3 records, hasMore=true
        TaskTargetController.ResultWrapper page1 = fetchPage(3, 0);
        // Page 2: pageSize=3, offset=3 → should return 2 records, hasMore=false
        TaskTargetController.ResultWrapper page2 = fetchPage(3, 3);
        Test.stopTest();
        
        System.assertEquals(5,    page1.totalRecords, 'Total should be 5');
        System.assertEquals(3,    page1.tasks.size(), 'Page 1 should have 3 tasks');
        System.assertEquals(true, page1.hasMore,      'Page 1 hasMore should be true');
        
        System.assertEquals(5,     page2.totalRecords, 'Total should be 5');
        System.assertEquals(2,     page2.tasks.size(), 'Page 2 should have 2 tasks');
        System.assertEquals(false, page2.hasMore,      'Page 2 hasMore should be false');
    }
    
    @isTest
    static void testGetTargetTasks_offsetBeyondTotal() {
        Test.startTest();
        // Offset beyond total records should return empty tasks
        TaskTargetController.ResultWrapper result = fetchPage(50, 100);
        Test.stopTest();
        
        System.assertNotEquals(null, result,            'Result should not be null');
        System.assertEquals(0,     result.tasks.size(), 'Should return empty when offset exceeds total');
        System.assertEquals(false, result.hasMore,      'hasMore should be false');
    }
    
    @isTest
    static void testGetTargetTasks_targetWithNoAccount() {
        Target__c bareTarget = new Target__c(
            Name              = 'Bare Target',
            Sequence_Active__c = false
        );
        insert bareTarget;
        
        Task t = new Task(
            Subject      = 'Bare Target Task',
            ActivityDate = Date.today().addDays(1),
            Status       = 'Not Started',
            OwnerId      = UserInfo.getUserId(),
            WhatId       = bareTarget.Id
        );
        insert t;
        
        Test.startTest();
        TaskTargetController.ResultWrapper result = fetchPage(50, 0);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        
        TaskTargetController.TaskWrapper bareWrapper;
        for (TaskTargetController.TaskWrapper tw : result.tasks) {
            if (tw.subject == 'Bare Target Task') {
                bareWrapper = tw;
            }
        }
        
        System.assertNotEquals(null, bareWrapper,           'Bare target task should be in results');
        System.assertEquals(null,   bareWrapper.region,     'Region should be null when no account');
        System.assertEquals(null,   bareWrapper.engagement, 'Engagement should be null when not set');
    }
}