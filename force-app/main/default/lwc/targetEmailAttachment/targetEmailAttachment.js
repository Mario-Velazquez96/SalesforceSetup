import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getCurrentAttachment from '@salesforce/apex/SequenceAttachmentController.getCurrentAttachment';
import setAttachment from '@salesforce/apex/SequenceAttachmentController.setAttachment';
import removeAttachment from '@salesforce/apex/SequenceAttachmentController.removeAttachment';

import UPLOAD_SUCCESS from '@salesforce/label/c.Sequence_Attachment_Upload_Success';
import REMOVE_SUCCESS from '@salesforce/label/c.Sequence_Attachment_Remove_Success';
import ERROR_TITLE from '@salesforce/label/c.Sequence_Attachment_Error_Title';

/**
 * Record-page control on Target__c to manage the single file attached to every
 * cadence email. Thin UI over Sequence_Attachment_Id__c; the engine (02) does the
 * attaching at send time. (Feature 06_lwc_attachment)
 */
export default class TargetEmailAttachment extends LightningElement {
    @api recordId;

    isLoading = false;
    fileName;
    hasAttachment = false;

    wiredAttachment;

    label = {
        uploadSuccess: UPLOAD_SUCCESS,
        removeSuccess: REMOVE_SUCCESS,
        errorTitle: ERROR_TITLE
    };

    @wire(getCurrentAttachment, { recordId: '$recordId' })
    handleWiredAttachment(result) {
        this.wiredAttachment = result;
        const { data, error } = result;
        if (data) {
            this.hasAttachment = data.hasAttachment === true;
            this.fileName = data.fileName;
        } else if (error) {
            this.hasAttachment = false;
            this.fileName = undefined;
            this.showError(error);
        }
    }

    async handleUploadFinished(event) {
        const files = event.detail ? event.detail.files : undefined;
        if (!files || files.length === 0) {
            return;
        }
        const contentDocumentId = files[0].documentId;
        this.isLoading = true;
        try {
            await setAttachment({
                recordId: this.recordId,
                contentDocumentId
            });
            await refreshApex(this.wiredAttachment);
            this.showToast('Success', this.label.uploadSuccess, 'success');
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleRemove() {
        this.isLoading = true;
        try {
            await removeAttachment({ recordId: this.recordId });
            await refreshApex(this.wiredAttachment);
            this.showToast('Success', this.label.removeSuccess, 'success');
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    showError(error) {
        const message = this.reduceError(error);
        this.showToast(this.label.errorTitle, message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {
        if (!error) {
            return this.label.errorTitle;
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return this.label.errorTitle;
    }
}
