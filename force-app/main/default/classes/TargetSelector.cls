/**
 * Selector for Target__c. Centralizes all SOQL for the object (Rule A1).
 * inherited sharing so the caller's sharing context applies; all queries
 * run WITH USER_MODE to enforce CRUD/FLS. (R2)
 */
public inherited sharing class TargetSelector {
    /**
     * Every field the engine (and downstream features 03/04/05) reference on
     * Target__c, so a single query feeds the whole engine.
     */
    private static final String FIELD_LIST =
        'Id, Name, Sequence_Active__c, Sequence_Step__c, Days_Until_Next_Email__c, ' +
        'Sequence_Stop_Reason__c, Next_Action_Date__c, Primary_Contact__c, ' +
        'Sequence_Attachment_Id__c, Status__c, Billing_City__c';

    /**
     * Returns the Targets for the given Ids with every engine-referenced field.
     */
    public List<Target__c> getByIds(Set<Id> targetIds) {
        if (targetIds == null || targetIds.isEmpty()) {
            return new List<Target__c>();
        }
        String soql =
            'SELECT ' + FIELD_LIST + ' FROM Target__c WHERE Id IN :targetIds WITH USER_MODE';
        return Database.query(soql);
    }

    /**
     * Returns active Targets whose Next_Action_Date__c is due (<= the supplied
     * cutoff) and that have not reached step 10. Used by the scheduler (feature 04).
     */
    public List<Target__c> getDueForScheduler(Datetime cutoff) {
        String soql =
            'SELECT ' + FIELD_LIST + ' FROM Target__c ' +
            'WHERE Sequence_Active__c = true ' +
            'AND Next_Action_Date__c != null ' +
            'AND Next_Action_Date__c <= :cutoff ' +
            'AND Sequence_Step__c < 10 ' +
            'WITH USER_MODE';
        return Database.query(soql);
    }
}
