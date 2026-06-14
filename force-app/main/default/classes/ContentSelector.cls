/**
 * Selector for ContentVersion / files. Centralizes all SOQL for content (Rule A1).
 * inherited sharing; queries run WITH USER_MODE. (R2)
 *
 * Resolves the latest published ContentVersion for one or more ContentDocumentIds
 * so the email service can attach the most recent version of an uploaded file.
 */
public inherited sharing class ContentSelector {
    /**
     * Returns the latest (IsLatest = true) ContentVersion for each supplied
     * ContentDocumentId, keyed by ContentDocumentId.
     */
    public Map<Id, ContentVersion> getLatestVersionsByDocumentId(Set<Id> documentIds) {
        Map<Id, ContentVersion> result = new Map<Id, ContentVersion>();
        if (documentIds == null || documentIds.isEmpty()) {
            return result;
        }
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId, Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds AND IsLatest = true
            WITH USER_MODE
        ]) {
            result.put(cv.ContentDocumentId, cv);
        }
        return result;
    }

    /**
     * Convenience: latest ContentVersion Id for a single ContentDocumentId,
     * or null when none is found.
     */
    public Id getLatestVersionId(Id documentId) {
        if (documentId == null) {
            return null;
        }
        Map<Id, ContentVersion> byDoc =
            getLatestVersionsByDocumentId(new Set<Id>{ documentId });
        ContentVersion cv = byDoc.get(documentId);
        return cv == null ? null : cv.Id;
    }
}
