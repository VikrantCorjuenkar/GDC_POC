/**
 * @description       :
 * @author            : Amol
 * @group             :
 * @last modified on  : 03-10-2024
 * @last modified by  : Amol
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   03-08-2024   Amol   Initial Version
 **/
import { LightningElement, wire, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getWCLoanApplicantPosidexDetails from '@salesforce/apex/AxisNANOLoanApplicantPosidexController.getNANOLoanApplicantPosidexDetails';
import updateCustomerSurvivingCIF from '@salesforce/apex/AxisNANOLoanApplicantPosidexController.updateCustomerSurvivingCIF';
import invokeBorrowerDedupe from '@salesforce/apex/AxisNANOLoanApplicantPosidexController.invokeBorrowerDedupe';
import getCurrentUserProfileName from '@salesforce/apex/AxisNANOLoanApplicantPosidexController.getUserProfile';
import usrId from '@salesforce/user/Id';
import { updateRecord } from 'lightning/uiRecordApi';
import APPLICANT_ID_FIELD from "@salesforce/schema/LoanApplicant.Id";
import APPLICANT_CIF_SKIP_FIELD from "@salesforce/schema/LoanApplicant.axisltd_CIF_tagging_Skipped__c";


const COLUMNS = [
    { label: 'CIF Id', fieldName: 'customerId', editable: false, hideDefaultActions: true },
    { label: 'Name', fieldName: 'name', editable: false, hideDefaultActions: true },
    { label: 'PAN', fieldName: 'pan', editable: false, hideDefaultActions: true },
    { label: 'DOB/DOI', fieldName: 'dateOfBirth', editable: false, hideDefaultActions: true, wrapText: true },
    { label: 'Mobile Number', fieldName: 'contactNumbers', editable: false, hideDefaultActions: true },
    { label: 'Reason Match', fieldName: 'reasonMatch', editable: false, hideDefaultActions: true },
    { label: 'CIF Type', fieldName: 'cifType', editable: false, hideDefaultActions: true },
    { label: 'CIF Status', fieldName: 'cifStatus', editable: false, hideDefaultActions: true },
    {
        label: 'Surviving CIF',
        fieldName: 'isServivingCIF',
        type: 'boolean',
        editable: false,
        hideDefaultActions: true,
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Edit',
        type: 'button',
        typeAttributes: { label: 'Edit', name: 'Edit', variant: 'base', iconName: { fieldName: 'buttonIcon' } },
        hideDefaultActions: true
    }
];

const COLUMNS_UPDATED = [
    { label: 'Name', fieldName: 'name', editable: false, hideDefaultActions: true },
    { label: 'DOB/DOI', fieldName: 'dateOfBirth', editable: false, hideDefaultActions: true, wrapText: true },
    { label: 'CIF Id', fieldName: 'customerId', editable: false, hideDefaultActions: true },
    { label: 'Address', fieldName: 'reasonMatch', editable: false, hideDefaultActions: true }, //add
    { label: 'Mobile No.', fieldName: 'contactNumbers', editable: false, hideDefaultActions: true },
    { label: 'Email ID', fieldName: 'cifType', editable: false, hideDefaultActions: true }, //add
    { label: 'Constitution Code', fieldName: 'cifStatus', editable: false, hideDefaultActions: true },
    { label: 'PAN', fieldName: 'pan', editable: false, hideDefaultActions: true },
    {
        label: 'Is Valid',
        fieldName: 'isServivingCIF',
        type: 'boolean',
        editable: false,
        hideDefaultActions: true,
        cellAttributes: { alignment: 'center' }
    }, //add
    {
        label: 'Surviving CIF',
        fieldName: 'isServivingCIF',
        type: 'boolean',
        editable: false,
        hideDefaultActions: true,
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Edit',
        type: 'button',
        typeAttributes: { label: 'Edit', name: 'Edit', variant: 'base', iconName: { fieldName: 'buttonIcon' } },
        hideDefaultActions: true
    }
];

export default class AxisNANOLoanApplicantPosidexDetails extends LightningElement {
    @api
    recordId;

    @api
    applicant;
    @api
    isReadonlyuser;

    tableColumns = [];
    draftValues = [];
    showSpinner = false;
    noRecToDisplay = 'NO MATCH FOUND';
    awaitingDisplay = 'AWAITING FOR LATEST RESULTS PLEASE REFRESH AFTER SOMETIME';
    @track isModalOpen = false;
    @track
    selectedDemographic = {};

    @track
    completePosidexInfo;

    @track
    loanApplicantPosidexInfo;

    @track
    loanApplicantDemographics;

    isBorrowerDedupeInProgrss = false;
    isErrorOccured = false;
    errorCode = '';
    errorMessage = '';

    applicationStage = '';

    currentUserProfileName;
    readOnlyForUWUser = false;

    //UAT 11/6 D51
    formattedDate;
    formattedAddresses = [];

    openModal() {
        this.isModalOpen = true;
    }
    closeModal() {
        this.isModalOpen = false;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        if (actionName === 'Edit') {
            this.openModal();
            let isServivingCIF =
                event.detail.row.isServivingCIF &&
                    (event.detail.row.isServivingCIF == true ||
                        event.detail.row.isServivingCIF == 'true' ||
                        event.detail.row.isServivingCIF == 'True' ||
                        event.detail.row.isServivingCIF == 'TRUE')
                    ? true
                    : false;
            this.selectedDemographic = event.detail.row;
            this.selectedDemographic = { ...this.selectedDemographic, isServivingCIF };
        }
    }
    handleEdit(event) {
        let customerId = event.target.dataset.id;
        this.selectedDemographic = this.loanApplicantDemographics.find((demographic) => {
            return demographic.customerId === customerId;
        });
        let isServivingCIF =
            this.selectedDemographic.isServivingCIF &&
                (this.selectedDemographic.isServivingCIF == true ||
                    this.selectedDemographic.isServivingCIF == 'true' ||
                    this.selectedDemographic.isServivingCIF == 'True' ||
                    this.selectedDemographic.isServivingCIF == 'TRUE')
                ? true
                : false;
        let isValidCIF =
            this.selectedDemographic.isValidCIF &&
                (this.selectedDemographic.isValidCIF == true ||
                    this.selectedDemographic.isValidCIF == 'true' ||
                    this.selectedDemographic.isValidCIF == 'True' ||
                    this.selectedDemographic.isValidCIF == 'TRUE')
                ? true
                : false;
        this.selectedDemographic = { ...this.selectedDemographic, isServivingCIF, isValidCIF };
        let validCIFEditableObj = {};
        if (
            this.applicationStage &&
            ('Underwriting' === this.applicationStage || 'Underwriting Auth' === this.applicationStage)
        ) {
            validCIFEditableObj = { isValidCIFEditable: true };
        } else {
            validCIFEditableObj = { isValidCIFEditable: false };
        }
        this.selectedDemographic = { ...this.selectedDemographic, ...validCIFEditableObj };
        this.openModal();
    }

    handleIsServivingCIFChange(event) {
        this.selectedDemographic.isServivingCIF = event.target.checked ? 'true' : 'false';
    }

    handleIsValidCIFChange(event) {
        this.selectedDemographic.isValidCIF = event.target.checked ? 'true' : 'false';
    }

    // get to check is mobile device
    get isMobileDevice() {
        return FORM_FACTOR === 'Small' ? true : false;
    }

    connectedCallback() {
        
        this.tableColumns = [...COLUMNS_UPDATED];
        getCurrentUserProfileName({ userId: usrId })
            .then((data) => {
                this.currentUserProfileName = data;
                if (this.currentUserProfileName == 'Axis_Underwriter') {
                    this.readOnlyForUWUser = true;
                } else {
                    this.readOnlyForUWUser = false;
                }
            })
            .catch((err) => { });
    }

    @wire(getWCLoanApplicantPosidexDetails, { applicantId: '$recordId' })
    wiredWCLoanApplicationPosidexDetails(value) {
        this.completePosidexInfo = value;
        const { data, error } = this.completePosidexInfo;

        if (data) {
            this.loanApplicantPosidexInfo = JSON.parse(JSON.stringify(data));
            console.log('checking CIN/DIN',this.loanApplicantPosidexInfo.currentRequestDetails.applicantCINDIN)
            let applicantCINDIN = this.loanApplicantPosidexInfo.currentRequestDetails.applicantCINDIN
            this.isBorrowerDedupeInProgrss = false;
            this.isErrorOccured = false;
            this.applicationStage = this.loanApplicantPosidexInfo.currentRequestDetails.applicationStage;
            if (this.loanApplicantPosidexInfo.currentRequestDetails.isDedupeInProgress) {
                this.isBorrowerDedupeInProgrss = true;
                this.loanApplicantDemographics = [];
            } else if (
                this.loanApplicantPosidexInfo.currentRequestDetails.errorCode &&
                this.loanApplicantPosidexInfo.currentRequestDetails.errorCode != ''
            ) {
                this.isErrorOccured = true;
                this.errorCode = this.loanApplicantPosidexInfo.currentRequestDetails.errorCode;
                this.errorMessage = this.loanApplicantPosidexInfo.currentRequestDetails.errorMessage;
            } else {
                this.isValidCIFEditable =
                    this.applicationStage &&
                    ('Underwriting' === this.applicationStage || 'Underwriting Auth' === this.applicationStage);
                this.loanApplicantDemographics = this.loanApplicantPosidexInfo.demographics.map((posidexInfo) => {
                    let isServivingCIF =
                        posidexInfo.isServivingCIF &&
                            (posidexInfo.isServivingCIF == true ||
                                posidexInfo.isServivingCIF == 'true' ||
                                posidexInfo.isServivingCIF == 'True' ||
                                posidexInfo.isServivingCIF == 'TRUE')
                            ? true
                            : false;
                    let isValidCIF =
                        posidexInfo.isValidCIF &&
                            (posidexInfo.isValidCIF == true ||
                                posidexInfo.isValidCIF == 'true' ||
                                posidexInfo.isValidCIF == 'True' ||
                                posidexInfo.isValidCIF == 'TRUE')
                            ? true
                            : false;
                    let cifStatus =
                        posidexInfo.cifStatus == 'N' || posidexInfo.cifStatus == 'n'
                            ? 'Active'
                            : posidexInfo.cifStatus == 'Y' || posidexInfo.cifStatus == 'y'
                                ? 'Suspended'
                                : posidexInfo.cifStatus;
                    let cifType =
                        posidexInfo.cifType == 'R' || posidexInfo.cifType == 'r'
                            ? 'Retail'
                            : posidexInfo.cifType == 'C' || posidexInfo.cifType == 'c'
                                ? 'Corporate'
                                : posidexInfo.cifType;
                    return { ...posidexInfo, isServivingCIF, cifStatus, cifType, isValidCIF,applicantCINDIN };
                });
            }

            //UAT 11/6 D51
            let tempDate = new Date(this.loanApplicantPosidexInfo.currentRequestDetails.applicantDOB).toLocaleDateString( {
                year: '4-digit',
                month: 'numeric',
                day: 'numeric',
              });
            this.formattedDate = tempDate;

            if(this.loanApplicantPosidexInfo.currentRequestDetails.applicantAddress && this.loanApplicantPosidexInfo.currentRequestDetails.applicantAddress != undefined && this.loanApplicantPosidexInfo.currentRequestDetails.applicantAddress != ''){
            this.formattedAddresses = this.formatAddresses(this.loanApplicantPosidexInfo.currentRequestDetails.applicantAddress);
            }

        } else if (error) {
            this.loanApplicantDemographics = [];
            
        }
    }

    //UAT 11/6 D51
    formatAddresses(addressArray) {
        return addressArray.map((address, index) => {
            let parts = address.split(',');
            if (parts.length > 1) {
                // Format first part normally, subsequent parts with newline
                let formattedAddress = parts.map((part, idx) => {
                    return idx === 0 ? part : part.trim();
                }).join(', ');
                return formattedAddress;
            } else {
                // Return address as is if no commas
                return address;
            }
        });
    }

    updateSurvivingCIF() {
        if (this.selectedDemographic && this.selectedDemographic.cifStatus === 'Suspended') {
            const toastEvent = new ShowToastEvent({
                title: 'Error',
                message: "A Suspended CIF can't be selected as surving CIF ",
                variant: 'error'
            });
            this.dispatchEvent(toastEvent);
            return;
        }
        let isAlreadySelectedSurviver = false;
        if (
            this.selectedDemographic.isServivingCIF &&
            (this.selectedDemographic.isServivingCIF == true || this.selectedDemographic.isServivingCIF == 'true')
        ) {
            isAlreadySelectedSurviver = this.loanApplicantDemographics.find((posidexInfo) => {
                return posidexInfo.isServivingCIF === true;
            });
        }
        if (isAlreadySelectedSurviver && this.selectedDemographic.customerId != isAlreadySelectedSurviver.customerId) {
            const toastEvent = new ShowToastEvent({
                title: 'Error',
                message: 'Already one of the other match selected as Surviver, please unselect other one',
                variant: 'error'
            });
            this.dispatchEvent(toastEvent);
            return;
        }
        this.showSpinner = true;
        updateCustomerSurvivingCIF({
            applicantId: this.recordId,
            isServivingCIF: this.selectedDemographic.isServivingCIF,
            isValidCIF: this.selectedDemographic.isValidCIF,
            customerId: this.selectedDemographic.customerId,
            hasServivingCIFChanged: this.selectedDemographic.isServivingCIF,
            hasisValidCIFChanged: this.selectedDemographic.isValidCIF
        })
            .then((data) => {
                const toastEvent = new ShowToastEvent({
                    title: 'Success',
                    message: 'Successfully Saved',
                    variant: 'success'
                });
                this.dispatchEvent(toastEvent);
                refreshApex(this.completePosidexInfo);
                this.showSpinner = false;
                this.isModalOpen = false;
                this.selectedDemographic = {};
            })
            .catch((error) => {
                const toastEvent = new ShowToastEvent({
                    title: 'Error',
                    message: error.body.message,
                    variant: 'error'
                });
                this.dispatchEvent(toastEvent);
                this.showSpinner = false;
                this.isModalOpen = false;
                this.selectedDemographic = {};
            });
    }

    // BB-2548
    handleBorrowerDedupe(event) {
        this.showSpinner = true;
        invokeBorrowerDedupe({
            applicantId: this.recordId
        })
            .then((data) => {
                const toastEvent = new ShowToastEvent({
                    title: 'Success',
                    message: 'Successfully submitted',
                    variant: 'success'
                });
                this.dispatchEvent(toastEvent);
                refreshApex(this.completePosidexInfo);
                this.showSpinner = false;
            })
            .catch((error) => {
                const toastEvent = new ShowToastEvent({
                    title: 'Error',
                    message: error.body.message,
                    variant: 'error'
                });
                this.dispatchEvent(toastEvent);
                this.showSpinner = false;
            });
    }
    // BB-2548

    get hasPosidexResults() {
        return this.loanApplicantDemographics && this.loanApplicantDemographics.length > 0;
    }

    get posidexMatchResultsCount() {
        return this.loanApplicantDemographics && this.loanApplicantDemographics.length > 0
            ? this.loanApplicantDemographics.length
            : 0;
    }

    get isValidCIFChangeAllowed() {
        return (
            this.applicationStage &&
            ('Underwriting' === this.applicationStage || 'Underwriting Auth' === this.applicationStage)
        );
    }
    /* BB-2548
    handleRefresh() {
        this.showSpinner = true;
        this.refresh();
        this.showSpinner = false;
    }
    BB-2548 */

    /* BB-2548 */
    handleSkip() {
        if (this.readOnlyForUWUser) {
        const toastEvent = new ShowToastEvent({
            title: 'Error',
            message: 'Button action not applicable for UW user.',
            variant: 'error'
        });
        this.dispatchEvent(toastEvent);

        } else {
            //update the loan applicant field
            const fields = {};
            fields[APPLICANT_ID_FIELD.fieldApiName] = this.recordId;
            fields[APPLICANT_CIF_SKIP_FIELD.fieldApiName] = true;
            const recordInput = { fields };
            updateRecord(recordInput)
                .then(() => {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: "Success",
                            message: "CIF tagging is skipped successfully",
                            variant: "success",
                        }),
                    );
                    // Display fresh data in the form
                    return refreshApex(this.contact);
                })
                .catch((error) => {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: "Error updating record",
                            message: error.body.message,
                            variant: "error",
                        }),
                    );
                });
        }

        this.showSpinner = false;
    }
    /* BB-2548 */

    async refresh() {
        await refreshApex(this.completePosidexInfo);
    }
}