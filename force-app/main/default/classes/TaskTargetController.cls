public with sharing class TaskTargetController {
    
    @AuraEnabled(cacheable=true)
    public static ResultWrapper getTargetTasks(Integer pageSize, Integer offset) {
        
        String targetPrefix = Target__c.SObjectType.getDescribe().getKeyPrefix();
        
        List<Task> allTasks = [
            SELECT Id, Subject, ActivityDate, OwnerId, WhatId
            FROM Task
            WHERE IsClosed = false
              AND WhatId != null
        ];
        
        // Filter by Target__c prefix
        List<Task> targetTasks = new List<Task>();
        Set<Id> targetIds = new Set<Id>();
        Set<Id> ownerIds  = new Set<Id>();
        for (Task t : allTasks) {
            if (String.valueOf(t.WhatId).startsWith(targetPrefix)) {
                targetTasks.add(t);
                targetIds.add(t.WhatId);
                ownerIds.add(t.OwnerId);
            }
        }
        
        Integer totalRecords = targetTasks.size();
        
        // Apply pagination
        List<Task> pagedTasks = new List<Task>();
        for (Integer i = offset; i < Math.min(offset + pageSize, totalRecords); i++) {
            pagedTasks.add(targetTasks[i]);
        }
        
        // Query User names
        Map<Id, String> userNameMap = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
            userNameMap.put(u.Id, u.Name);
        }
        
        // Query Target__c
        Map<Id, Target__c> targetMap = new Map<Id, Target__c>([
            SELECT Id, Name, State__c,
                   Company_Name__c, Company_Name__r.Region__c,
                   Engagement__c, Engagement__r.Name
            FROM Target__c
            WHERE Id IN :targetIds
        ]);
        
        // Build wrappers
        List<TaskWrapper> results = new List<TaskWrapper>();
        for (Task t : pagedTasks) {
            TaskWrapper tw = new TaskWrapper();
            tw.taskId     = t.Id;
            tw.subject    = t.Subject;
            tw.dueDate    = t.ActivityDate;
            tw.targetId   = t.WhatId;
            tw.assignedTo = userNameMap.containsKey(t.OwnerId)
                            ? userNameMap.get(t.OwnerId)
                            : UserInfo.getName();
            
            Target__c tgt = targetMap.get(t.WhatId);
            if (tgt != null) {
                tw.targetName = tgt.Name;
                tw.state      = tgt.State__c;
                tw.region     = tgt.Company_Name__r != null ? tgt.Company_Name__r.Region__c : null;
                tw.engagement = tgt.Engagement__r   != null ? tgt.Engagement__r.Name        : null;
            }
            results.add(tw);
        }
        
        ResultWrapper rw = new ResultWrapper();
        rw.tasks        = results;
        rw.totalRecords = totalRecords;
        rw.hasMore      = (offset + pageSize) < totalRecords;
        return rw;
    }
    
    public class ResultWrapper {
        @AuraEnabled public List<TaskWrapper> tasks;
        @AuraEnabled public Integer           totalRecords;
        @AuraEnabled public Boolean           hasMore;
    }
    
    public class TaskWrapper {
        @AuraEnabled public Id     taskId;
        @AuraEnabled public String subject;
        @AuraEnabled public Date   dueDate;
        @AuraEnabled public Id     targetId;
        @AuraEnabled public String targetName;
        @AuraEnabled public String state;
        @AuraEnabled public String region;
        @AuraEnabled public String engagement;
        @AuraEnabled public String assignedTo;
    }
}