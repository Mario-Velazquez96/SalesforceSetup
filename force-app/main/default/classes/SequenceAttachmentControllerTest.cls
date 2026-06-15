/**
 * Tests for SequenceAttachmentController: set/replace/remove/get plus a
 * negative no-access path. (R1, R2, R3, R4, R7)
 */
@IsTest
private class SequenceAttachmentControllerTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Attach Co', BillingCity = 'Reno');
        insert acc;
        Contact con = new Contact(
            FirstName = 'Ada',
            LastName = 'Lake',
            Email = 'ada@example.com',
            AccountId = acc.Id
        );
        insert con;
        // Inserted INACTIVE so the after-insert sequence-start path does not
        // enqueue work and perturb these fixtures.
        Target__c t = new Target__c(
            Name = 'Attach Target',
            Company_Name__c = acc.Id,
            Primary_Contact__c = con.Id,
            Sequence_Active__c = false
        );
        insert t;
    }

    private static Id firstDocumentId(String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.txt',
            VersionData = Blob.valueOf('data-' + title)
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    private static void linkDoc(Id docId, Id recordId) {
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = recordId,
            ShareType = 'V'
        );
    }

    @IsTest
    static void setAttachmentStoresDocumentId() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        Id docId = firstDocumentId('First');
        linkDoc(docId, t.Id);

        Test.startTest();
        SequenceAttachmentController.setAttachment(t.Id, docId);
        Test.stopTest();

        Target__c after = [SELECT Sequence_Attachment_Id__c FROM Target__c WHERE Id = :t.Id];
        Assert.areEqual(
            (String) docId,
            after.Sequence_Attachment_Id__c,
            'setAttachment stores the ContentDocumentId (R1)'
        );
    }

    @IsTest
    static void secondSetAttachmentReplacesPrior() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        Id firstDoc = firstDocumentId('First');
        linkDoc(firstDoc, t.Id);
        Id secondDoc = firstDocumentId('Second');
        linkDoc(secondDoc, t.Id);

        Test.startTest();
        SequenceAttachmentController.setAttachment(t.Id, firstDoc);
        SequenceAttachmentController.setAttachment(t.Id, secondDoc);
        Test.stopTest();

        Target__c after = [SELECT Sequence_Attachment_Id__c FROM Target__c WHERE Id = :t.Id];
        Assert.areEqual(
            (String) secondDoc,
            after.Sequence_Attachment_Id__c,
            'Second setAttachment replaces the field with the new doc (R2)'
        );
        // The prior sequence file's link to the record was removed (single file, R2).
        List<ContentDocumentLink> firstLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :t.Id AND ContentDocumentId = :firstDoc
        ];
        Assert.areEqual(0, firstLinks.size(), 'Prior file is unlinked from the record (R2)');
        List<ContentDocumentLink> secondLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :t.Id AND ContentDocumentId = :secondDoc
        ];
        Assert.areEqual(1, secondLinks.size(), 'New file remains linked (R2)');
    }

    @IsTest
    static void getCurrentAttachmentReturnsCurrentFile() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        Id docId = firstDocumentId('Brochure');
        linkDoc(docId, t.Id);
        SequenceAttachmentController.setAttachment(t.Id, docId);

        Test.startTest();
        SequenceAttachmentController.AttachmentView view =
            SequenceAttachmentController.getCurrentAttachment(t.Id);
        Test.stopTest();

        Assert.isTrue(view.hasAttachment, 'View reports an attachment (R4)');
        Assert.areEqual(docId, view.contentDocumentId, 'View carries the document id (R4)');
        Assert.areEqual('Brochure.txt', view.fileName, 'View carries the file name (R4)');
    }

    @IsTest
    static void getCurrentAttachmentEmptyWhenNoFile() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];

        Test.startTest();
        SequenceAttachmentController.AttachmentView view =
            SequenceAttachmentController.getCurrentAttachment(t.Id);
        Test.stopTest();

        Assert.isFalse(view.hasAttachment, 'No file -> empty view (R5)');
        Assert.areEqual(null, view.fileName, 'No file name in empty view (R5)');
    }

    @IsTest
    static void removeAttachmentClearsFieldAndUnlinks() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        Id docId = firstDocumentId('ToRemove');
        linkDoc(docId, t.Id);
        SequenceAttachmentController.setAttachment(t.Id, docId);

        Test.startTest();
        SequenceAttachmentController.removeAttachment(t.Id);
        Test.stopTest();

        Target__c after = [SELECT Sequence_Attachment_Id__c FROM Target__c WHERE Id = :t.Id];
        Assert.areEqual(null, after.Sequence_Attachment_Id__c, 'removeAttachment clears the field (R3)');
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :t.Id AND ContentDocumentId = :docId
        ];
        Assert.areEqual(0, links.size(), 'removeAttachment unlinks the prior file (R3)');
    }

    @IsTest
    static void setAttachmentNullInputThrows() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        Boolean threw = false;
        Test.startTest();
        try {
            SequenceAttachmentController.setAttachment(t.Id, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Null input throws AuraHandledException (R7)');
    }

    @IsTest
    static void removeAttachmentNullInputThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            SequenceAttachmentController.removeAttachment(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Null record id throws AuraHandledException (R7)');
    }

    @IsTest
    static void noFieldAccessThrows() {
        Target__c t = [SELECT Id FROM Target__c LIMIT 1];
        Id docId = firstDocumentId('NoAccess');
        linkDoc(docId, t.Id);

        User minimal = buildMinimalUser();
        Boolean threw = false;

        System.runAs(minimal) {
            Test.startTest();
            try {
                // No FLS on Sequence_Attachment_Id__c -> USER_MODE DML denied (R7)
                SequenceAttachmentController.setAttachment(t.Id, docId);
            } catch (AuraHandledException e) {
                threw = true;
            } catch (System.NoAccessException e) {
                threw = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(threw, 'User without FLS cannot set the field (R7)');
    }

    private static User buildMinimalUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String unique = 'seqattach' + DateTime.now().getTime();
        User u = new User(
            FirstName = 'No',
            LastName = 'Access',
            Email = unique + '@example.com',
            Username = unique + '@example.com.bluesky',
            Alias = 'noacc',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }
}
