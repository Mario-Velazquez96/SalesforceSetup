import { createElement } from 'lwc';
import TargetEmailAttachment from 'c/targetEmailAttachment';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import { refreshApex } from '@salesforce/apex';

import getCurrentAttachment from '@salesforce/apex/SequenceAttachmentController.getCurrentAttachment';
import setAttachment from '@salesforce/apex/SequenceAttachmentController.setAttachment';
import removeAttachment from '@salesforce/apex/SequenceAttachmentController.removeAttachment';

// Wire adapter for the cacheable getCurrentAttachment
const getCurrentAttachmentAdapter = registerApexTestWireAdapter(getCurrentAttachment);

// Imperative Apex mocks
jest.mock(
    '@salesforce/apex/SequenceAttachmentController.setAttachment',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SequenceAttachmentController.removeAttachment',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// refreshApex mock
jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);

// The default lwc-jest stub for ShowToastEvent drops the detail payload, so we
// mock it with a CustomEvent that preserves { title, message, variant } and
// keeps the platform event name (lowercase, R6).
const TOAST_EVENT_NAME = 'lightning__showtoast';
jest.mock(
    'lightning/platformShowToastEvent',
    () => {
        const ShowToastEventName = 'lightning__showtoast';
        return {
            ShowToastEventName,
            ShowToastEvent: class extends CustomEvent {
                constructor(detail) {
                    super(ShowToastEventName, { composed: true, bubbles: true, detail });
                }
            }
        };
    },
    { virtual: true }
);

const FILLED_STATE = {
    hasAttachment: true,
    fileName: 'brochure.pdf',
    contentDocumentId: '069000000000001'
};
const EMPTY_STATE = { hasAttachment: false, fileName: undefined, contentDocumentId: undefined };
const RECORD_ID = 'a01000000000001';

function createComponent() {
    const element = createElement('c-target-email-attachment', { is: TargetEmailAttachment });
    element.recordId = RECORD_ID;
    document.body.appendChild(element);
    return element;
}

// Macrotask-based flush drains the multi-step await chains in the async handlers
// (imperative Apex -> refreshApex -> toast).
function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-target-email-attachment', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the empty state with a file-upload when no file is attached (R5)', () => {
        const element = createComponent();
        getCurrentAttachmentAdapter.emit(EMPTY_STATE);

        return flushPromises().then(() => {
            const upload = element.shadowRoot.querySelector('lightning-file-upload');
            const removeBtn = element.shadowRoot.querySelector('lightning-button');
            expect(upload).not.toBeNull();
            expect(removeBtn).toBeNull();
        });
    });

    it('shows the current file name and a Remove button when a file is attached (R4)', () => {
        const element = createComponent();
        getCurrentAttachmentAdapter.emit(FILLED_STATE);

        return flushPromises().then(() => {
            const removeBtn = element.shadowRoot.querySelector('lightning-button');
            expect(removeBtn).not.toBeNull();
            expect(element.shadowRoot.textContent).toContain('brochure.pdf');
            const upload = element.shadowRoot.querySelector('lightning-file-upload');
            expect(upload).toBeNull();
        });
    });

    it('calls setAttachment, refreshes, and fires a success toast on upload (R1, R6)', () => {
        setAttachment.mockResolvedValue(undefined);
        const element = createComponent();
        getCurrentAttachmentAdapter.emit(EMPTY_STATE);

        const toastHandler = jest.fn();
        element.addEventListener(TOAST_EVENT_NAME, toastHandler);

        return flushPromises()
            .then(() => {
                const upload = element.shadowRoot.querySelector('lightning-file-upload');
                upload.dispatchEvent(
                    new CustomEvent('uploadfinished', {
                        detail: { files: [{ documentId: '069000000000999' }] }
                    })
                );
                return flushPromises();
            })
            .then(() => {
                expect(setAttachment).toHaveBeenCalledWith({
                    recordId: RECORD_ID,
                    contentDocumentId: '069000000000999'
                });
                expect(refreshApex).toHaveBeenCalled();
                expect(toastHandler).toHaveBeenCalled();
                expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
            });
    });

    it('fires an error toast and clears the spinner when upload fails (R6)', () => {
        setAttachment.mockRejectedValue({ body: { message: 'no access' } });
        const element = createComponent();
        getCurrentAttachmentAdapter.emit(EMPTY_STATE);

        const toastHandler = jest.fn();
        element.addEventListener(TOAST_EVENT_NAME, toastHandler);

        return flushPromises()
            .then(() => {
                const upload = element.shadowRoot.querySelector('lightning-file-upload');
                upload.dispatchEvent(
                    new CustomEvent('uploadfinished', {
                        detail: { files: [{ documentId: '069000000000999' }] }
                    })
                );
                return flushPromises();
            })
            .then(() => {
                expect(toastHandler).toHaveBeenCalled();
                expect(toastHandler.mock.calls[0][0].detail.variant).toBe('error');
                expect(toastHandler.mock.calls[0][0].detail.message).toBe('no access');
                const spinner = element.shadowRoot.querySelector('lightning-spinner');
                expect(spinner).toBeNull();
            });
    });

    it('replaces the prior file when a new file is uploaded (single file, R2)', () => {
        setAttachment.mockResolvedValue(undefined);
        const element = createComponent();
        // start with an existing attachment, then the wire re-emits empty to
        // expose the uploader for the replacement file
        getCurrentAttachmentAdapter.emit(FILLED_STATE);

        return flushPromises()
            .then(() => {
                getCurrentAttachmentAdapter.emit(EMPTY_STATE);
                return flushPromises();
            })
            .then(() => {
                const upload = element.shadowRoot.querySelector('lightning-file-upload');
                upload.dispatchEvent(
                    new CustomEvent('uploadfinished', {
                        detail: { files: [{ documentId: '069000000000002' }] }
                    })
                );
                return flushPromises();
            })
            .then(() => {
                expect(setAttachment).toHaveBeenCalledTimes(1);
                expect(setAttachment).toHaveBeenCalledWith({
                    recordId: RECORD_ID,
                    contentDocumentId: '069000000000002'
                });
            });
    });

    it('removes the attachment and returns to the empty state (R3, R5)', () => {
        removeAttachment.mockResolvedValue(undefined);
        const element = createComponent();
        getCurrentAttachmentAdapter.emit(FILLED_STATE);

        const toastHandler = jest.fn();
        element.addEventListener(TOAST_EVENT_NAME, toastHandler);

        return flushPromises()
            .then(() => {
                const removeBtn = element.shadowRoot.querySelector('lightning-button');
                removeBtn.click();
                return flushPromises();
            })
            .then(() => {
                expect(removeAttachment).toHaveBeenCalledWith({ recordId: RECORD_ID });
                expect(refreshApex).toHaveBeenCalled();
                expect(toastHandler).toHaveBeenCalled();
                expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
                // wire re-emits empty after removal
                getCurrentAttachmentAdapter.emit(EMPTY_STATE);
                return flushPromises();
            })
            .then(() => {
                const upload = element.shadowRoot.querySelector('lightning-file-upload');
                expect(upload).not.toBeNull();
            });
    });
});
