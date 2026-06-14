/**
 * Reads Sequence_Step_Config__mdt and exposes it as a
 * Map<Integer, Sequence_Step_Config__mdt> keyed by Step_Number__c. (R1)
 *
 * Custom Metadata is fetched once via getAll() (no SOQL cost) and cached for
 * the transaction.
 */
public with sharing class SequenceStepConfigService {
    @TestVisible
    private static Map<Integer, Sequence_Step_Config__mdt> cache;

    /**
     * All step configs keyed by step number. Cached per-transaction.
     */
    public static Map<Integer, Sequence_Step_Config__mdt> getByStep() {
        if (cache != null) {
            return cache;
        }
        cache = new Map<Integer, Sequence_Step_Config__mdt>();
        for (Sequence_Step_Config__mdt cfg : Sequence_Step_Config__mdt.getAll().values()) {
            if (cfg.Step_Number__c != null) {
                cache.put(Integer.valueOf(cfg.Step_Number__c), cfg);
            }
        }
        return cache;
    }

    /**
     * Config for a single step, or null when no row exists for that step.
     */
    public static Sequence_Step_Config__mdt get(Integer stepNumber) {
        return getByStep().get(stepNumber);
    }
}
