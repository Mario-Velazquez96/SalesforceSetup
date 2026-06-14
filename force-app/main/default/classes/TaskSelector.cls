/**
 * Selector for Task. Centralizes all SOQL for the object (Rule A1).
 * inherited sharing; queries run WITH USER_MODE. (R2)
 */
public inherited sharing class TaskSelector {
    private static final String FIELD_LIST =
        'Id, WhatId, Subject, Status, ActivityDate, ' +
        'Is_Sequence_Call__c, Sequence_Step__c';

    /**
     * Returns Tasks for the given WhatIds (e.g. all cadence tasks on a set of
     * Targets). Used by tests and downstream features.
     */
    public List<Task> getByWhatIds(Set<Id> whatIds) {
        if (whatIds == null || whatIds.isEmpty()) {
            return new List<Task>();
        }
        String soql =
            'SELECT ' + FIELD_LIST + ' FROM Task WHERE WhatId IN :whatIds WITH USER_MODE';
        return Database.query(soql);
    }

    /**
     * Returns only the open sequence-call Tasks for the given WhatIds.
     */
    public List<Task> getSequenceCalls(Set<Id> whatIds) {
        if (whatIds == null || whatIds.isEmpty()) {
            return new List<Task>();
        }
        String soql =
            'SELECT ' + FIELD_LIST + ' FROM Task ' +
            'WHERE WhatId IN :whatIds AND Is_Sequence_Call__c = true ' +
            'WITH USER_MODE';
        return Database.query(soql);
    }
}
