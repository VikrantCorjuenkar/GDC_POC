/**
 * @description       :
 * @author            : Amol
 * @group             :
 * @last modified on  : 03-10-2024
 * @last modified by  : Amol
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   03-10-2024   Amol   Initial Version
 **/
import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getHunterDetails from '@salesforce/apex/AxisWCHunterDetailsService.getHunterDetails';
import invokeHunterOnline from '@salesforce/apex/AxisWCHunterDetailsService.invokeHunterOnline';
import userId from '@salesforce/user/Id';
import USERPROFILE_ID from '@salesforce/schema/User.Profile.Name';
import { getRecord } from 'lightning/uiRecordApi';

const COLUMNS = [
    {
        label: 'Action Date',
        fieldName: 'ActionDate',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 135
    },
    {
        label: 'Match/UnMatch',
        fieldName: 'MatchOrNoMatch',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 120
    },
    {
        label: 'Hunter Comments',
        fieldName: 'HunterComments',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 135
    },
    {
        label: 'Hunter Submission Date',
        fieldName: 'DateOfSubmission',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 165
    },
    {
        label: 'Final Hunter Status',
        fieldName: 'HunterFinalStatus',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 140
    },
    {
        label: 'Final Hunter Status Date Change',
        fieldName: 'FraudStatusChangeDate',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 220
    },
    {
        label: 'Action Remarks',
        fieldName: 'Remarks',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 185
    },
    {
        label: 'Decline of Suspect Reason',
        fieldName: 'DeclineofSuspectReason',
        editable: false,
        hideDefaultActions: true,
        wrapText: true,
        fixedWidth: 185
    }
];
export default class AxisNANOHunterDetailsTable extends LightningElement {
    hunterColumns = [];
    @api
    recordId;
    @api
    isReadonlyuser;
    @track
    hunterDetails = [];
    isHunterEmpty = false;
    isHunterInvokeEligible = false;
    noRecToDisplay = 'NO RECORDS TO DISPLAY';
    awaitingDisplay = 'AWAITING LATEST RESULTS PLEASE REFRESH AFTER SOMETIME';
    maximumHunterLimitTextDisplay =
        'Maximum 14 Guarantors and 1 Primary applicant can be sent for Hunter Check in a Single request, subsequent Guarantors will be sent in another request automatically, please wait for Final Match/No Match Status in such case.';
    isHunterInProgress = false;
    activeSections = ['HunterDetails'];
    isErrorEncountered = false;
    errorMessage;
    actionDate;
    completeHunterInfo;
    showSpinner = false;
    /*currentUser = userId;
    isReadOnlyUser = false;
    lstReadOnlyProfiles = ['Axis Internal Read Only','Axis External Read Only'];

    @wire(getRecord, { recordId: userId, fields: [USERPROFILE_ID]}) 
    userDetails({error, data}) {
        if (data) {
            console.log('Profile Name'+data.fields.Profile.value.fields.Name.value);
            this.isReadOnlyUser = this.lstReadOnlyProfiles?.includes(data.fields.Profile.value.fields.Name.value);
           
        } else if (error) {
            this.error = error ;
        }
    } */

    @wire(getHunterDetails, { applicationId: '$recordId' })
    getLoanAppHunterDetails(value) {
        this.completeHunterInfo = value;
        const { data, error } = this.completeHunterInfo;
        if (data) {
            
            this.processHunterData(data);
        } else if (error) {
            let errorMassage = error.body ? error.body.message : JSON.stringify(error);
            
        } else {
            this.hunterDetails = [];
            this.isHunterEmpty = true;
            this.isHunterInvokeEligible = true;
        }
    }

    processHunterData(data) {
        if (data != '') {
            let details = JSON.parse(data);
            if (details && details.isHunterInProgress) {
                this.isHunterInProgress = true;
                this.isHunterInvokeEligible = false;
                this.hunterDetails = [];
                return;
            }
            if (details.errorText) {
                this.isErrorEncountered = true;
                this.errorMessage = details.errorText;
                this.actionDate = details.ActionDate;
                this.hunterDetails = [];
                this.isHunterEmpty = true;
                this.isHunterInProgress = false;
                this.isHunterInvokeEligible = true;
            } else {
                this.hunterDetails = [
                    {
                        ActionDate: details.ActionDate,
                        MatchOrNoMatch: details.MatchOrNoMatch,
                        HunterComments: details.HunterComments,
                        DateOfSubmission: details.DateOfSubmission,
                        HunterFinalStatus: details.HunterFinalStatus,
                        FraudStatusChangeDate: details.FraudStatusChangeDate,
                        Remarks: details.HunterRemarks,
                        DeclineofSuspectReason: details.DeclineofSuspectReason,
                        identifier: details.identifier
                    }
                ];
                this.isHunterEmpty = false;
                this.isHunterInProgress = false;
                this.isHunterInvokeEligible =
                    'Unmatch' == details.MatchOrNoMatch ||
                    ('Match' == details.MatchOrNoMatch && 'Results Awaiting' != details.HunterFinalStatus)
                        ? true
                        : false;
            }
        } else {
            this.isHunterInvokeEligible = true;
            this.hunterDetails = [];
            this.isHunterEmpty = true;
            this.isHunterInProgress = false;
        }
    }

    connectedCallback() {
        this.hunterColumns = COLUMNS;
    }

    handleHunterOnline(event) {
        
        this.showSpinner = true;
        invokeHunterOnline({
            applicationId: this.recordId
        })
            .then((data) => {
                
                const toastEvent = new ShowToastEvent({
                    title: 'Success',
                    message: 'Successfully submitted',
                    variant: 'success'
                });
                this.dispatchEvent(toastEvent);
                this.isErrorEncountered = false;
                refreshApex(this.completeHunterInfo);
                this.showSpinner = false;
            })
            .catch((error) => {
                
                let errorMessage = error.body ? error.body.message : JSON.stringify(error);
                const toastEvent = new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error'
                });
                this.dispatchEvent(toastEvent);
                this.showSpinner = false;
            });
    }

    handleRefresh() {
        this.showSpinner = true;
        this.refresh();
        this.showSpinner = false;
    }

    async refresh() {
        await refreshApex(this.completeHunterInfo);
    }
}