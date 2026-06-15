/**
 * Controller for the targetEmailAttachment LWC. Manages the single file used on
 * every cadence email by reading/writing Target__c.Sequence_Attachment_Id__c and
 * the corresponding ContentDocumentLink. (Feature 06_lwc_attachment)
 *
 * with sharing; CRUD/FLS enforced via WITH USER_MODE SOQL and
 * AccessLevel.USER_MODE DML. Errors surface as AuraHandledException. (R4, R7)
 */
public with sharing class SequenceAttachmentController {
    /**
     * View model returned to the LWC describing the currently attached file.
     */
    public class AttachmentView {
        @AuraEnabled
        public Id contentDocumentId { get; set; }
        @AuraEnabled
        public String fileName { get; set; }
        @AuraEnabled
        public Boolean hasAttachment { get; set; }
    }

    /**
     * Returns the file currently referenced by Sequence_Attachment_Id__c for the
     * given Target__c record, or an empty view when none is set. (R4, R5)
     */
    @AuraEnabled(cacheable=true)
    public static AttachmentView getCurrentAttachment(Id recordId) {
        try {
            AttachmentView view = new AttachmentView();
            view.hasAttachment = false;

            Id documentId = getStoredDocumentId(recordId);
            if (documentId == null) {
                return view;
            }

            List<ContentVersion> versions = [
                SELECT Title, FileExtension, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :documentId AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                // Field points at a document the user can no longer see / that
                // no longer exists. Treat as empty state.
                return view;
            }

            ContentVersion cv = versions[0];
            view.contentDocumentId = cv.ContentDocumentId;
            view.fileName = String.isBlank(cv.FileExtension)
                ? cv.Title
                : cv.Title + '.' + cv.FileExtension;
            view.hasAttachment = true;
            return view;
        } catch (Exception e) {
            throw buildException(e);
        }
    }

    /**
     * Stores the supplied ContentDocumentId in Sequence_Attachment_Id__c, ensuring
     * only ONE sequence file is referenced: any previously linked sequence file is
     * unlinked from the record before the field is repointed. (R1, R2)
     */
    @AuraEnabled
    public static void setAttachment(Id recordId, Id contentDocumentId) {
        try {
            if (recordId == null || contentDocumentId == null) {
                throw new AuraHandledException(System.Label.Sequence_Attachment_Invalid_Input);
            }

            Id priorDocumentId = getStoredDocumentId(recordId);
            if (priorDocumentId != null && priorDocumentId != contentDocumentId) {
                unlinkDocument(recordId, priorDocumentId);
            }

            updateAttachmentField(recordId, (String) contentDocumentId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildException(e);
        }
    }

    /**
     * Clears Sequence_Attachment_Id__c and unlinks the prior sequence file's
     * ContentDocumentLink from the record. (R3)
     */
    @AuraEnabled
    public static void removeAttachment(Id recordId) {
        try {
            if (recordId == null) {
                throw new AuraHandledException(System.Label.Sequence_Attachment_Invalid_Input);
            }

            Id priorDocumentId = getStoredDocumentId(recordId);
            if (priorDocumentId != null) {
                unlinkDocument(recordId, priorDocumentId);
            }

            updateAttachmentField(recordId, null);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildException(e);
        }
    }

    // ---- helpers -----------------------------------------------------------

    /**
     * Reads the stored ContentDocumentId from the record (FLS-enforced).
     */
    private static Id getStoredDocumentId(Id recordId) {
        if (recordId == null) {
            return null;
        }
        List<Target__c> records = [
            SELECT Sequence_Attachment_Id__c
            FROM Target__c
            WHERE Id = :recordId
            WITH USER_MODE
            LIMIT 1
        ];
        if (records.isEmpty()) {
            return null;
        }
        String stored = records[0].Sequence_Attachment_Id__c;
        return String.isBlank(stored) ? null : (Id) stored;
    }

    /**
     * Updates Sequence_Attachment_Id__c (FLS-enforced) to the supplied value.
     */
    private static void updateAttachmentField(Id recordId, String documentId) {
        Target__c record = new Target__c(
            Id = recordId,
            Sequence_Attachment_Id__c = documentId
        );
        update as user record;
    }

    /**
     * Deletes any ContentDocumentLink between the record and the given document so
     * the prior sequence file is no longer associated with the Target__c. (R2, R3)
     */
    private static void unlinkDocument(Id recordId, Id documentId) {
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND ContentDocumentId = :documentId
            WITH USER_MODE
        ];
        if (!links.isEmpty()) {
            delete as user links;
        }
    }

    /**
     * Wraps an exception in an AuraHandledException carrying a usable message.
     */
    private static AuraHandledException buildException(Exception e) {
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
