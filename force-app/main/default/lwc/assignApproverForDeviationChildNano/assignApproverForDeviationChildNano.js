import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import RefreshMessageChannel from '@salesforce/messageChannel/RefreshMessageChannel__c';
import {publish, MessageContext, subscribe} from 'lightning/messageService';
import { refreshApex } from '@salesforce/apex';
import referTheLoanApplication from '@salesforce/apex/AssignApproverFromDeviationNano.referTheLoanApplication';
import updateApprover from '@salesforce/apex/AssignApproverFromDeviationNano.updateApprover';
import getDeivations from '@salesforce/apex/AssignApproverFromDeviationNano.getDeivations';
import RECORD_TYPE from '@salesforce/schema/ResidentialLoanApplication.RecordType.DeveloperName';
import { getRecord } from 'lightning/uiRecordApi';

const AMOUNT_DEVIATION = 'Amount Deviation';
const NANO_RECORDTYPE = 'axisltd_Nano';

export default class AssignApproverForDeviationChildNano extends LightningElement {

    @api recordId;
    recordtypeName;
    nanoRecordType = false;

    @wire(getRecord, { recordId: '$recordId', fields: [RECORD_TYPE] })
    wiredRecord({ error, data }) {
    if (data) {
        this.recordtypeName = data.fields.RecordType.value.fields.DeveloperName.value;
        
        if (this.recordtypeName == NANO_RECORDTYPE) {
            this.nanoRecordType = true;
        }
        }else if (error) {
            console.error(error);
        }
    }

    @api 
    get userLevelMapping(){
        return this.tempUserLevelMapping;
    }
    set userLevelMapping(val){
        this.tempUserLevelMapping = val;
        let levelOptions = [];
        let usereLevelMappingForOption = {};
        for (const level of Object.keys(val)) {
            levelOptions.push({label: level, value: level});
            let userOptions = [];
            for (const user of val[level]) {
                if(user['axis_EMP_ID__c']){
                    userOptions.push({label: user['FirstName']+' '+ user['axis_EMP_ID__c'], value: user['Id']});
                }
                else{
                    userOptions.push({label: user['FirstName'], value: user['Id']});
                }
            }
            var result = userOptions.reduce((unique, o) => {
                if (!unique.some(obj => obj.label === o.label && obj.value === o.value)) {
                    unique.push(o);
                }
                return unique;
            }, []);
            // usereLevelMappingForOption[level] = userOptions;
            usereLevelMappingForOption[level] = result;
        }
        this.levelOptions = levelOptions;
        this.usereLevelMappingForOption = usereLevelMappingForOption;
    }
    levelOptions = [];
    userOptions = [];
    tempUserLevelMapping;
    @api buttonLabel;
    @api
    get value(){
        return this.userLevel;
    }
    set value(val){
        this.userLevel = val;
        if(val){
            this.userOptions = this.usereLevelMappingForOption[val];
        }
    }
    @api readOnly=false;
    @api forwarding = false;
    @api eligibleApprovalLevel;
    userLevel;
    comments;
    openModal = false;
    selectedItem;
    showSpinner = false;
    usereLevelMappingForOption;

    @wire(MessageContext)
    messageContext;
    subscription=null;
    connectedCallback() {
        this.handleSubscribe();
        this.showSpinner = true;
        this.refeshData();
    }

    handleSubscribe() {
        if (this.subscription) {
            return;
        }
        this.subscription = subscribe(this.messageContext, RefreshMessageChannel, (message) => {
            this.refeshData();
        });
    }
    
    refeshData(){
        this.getRefreshDeviations();
    }

    handleLevelChange(event) {
		this.userLevel = event.detail.value;
		this.userOptions = this.usereLevelMappingForOption[event.detail.value];
    }

    handleCommentsChange(event){
        this.comments = event.detail.value;
    }

    closeModal(){
		this.openModal = false;
	}

    get hasReferalComentsEnabled(){
		return this.selectedItem && this.userLevel;
	}

    handleRefer(){
		let userNameValidity = this.template.querySelector('c-searchable-picklist').checkValidity();
		this.template.querySelector('lightning-textarea').reportValidity();
		if(this.userLevel && userNameValidity && this.comments){
			this.openModal = true;
            let msg;
            if(this.buttonLabel == 'Refer'){
                msg = 'Forwarded';
            }else if(this.buttonLabel == 'Send Back'){
                msg = 'Returned';
            }else if(this.buttonLabel == 'Send for Approval'){
                msg = 'Submitted for Approval';
            }else if(this.buttonLabel == 'Submit'){
                msg = 'Submitted';
            }
			this.popupMessage = 'Application will be '+ msg +' to <b>'+this.selectedItem.label+ '</b>, Kindly confirm';
		}
	}

    handleSelect(event){
		this.selectedItem = event.detail.selectedItem;
	}

    handleConfirm(){
		this.openModal = false;
		this.showSpinner = true;
        if(!this.forwarding){
            this.initialSubmission();
        }else{
            this.updateReuest();
        }
	}

    showErrorIfCurrentDeviationsNotApproved(){
        const toastEvent = new ShowToastEvent({
            "title": "Error",
            "message": 'Its mandatory to approve deviations before forwading to next level.',
            "variant": "error"
        });
        this.dispatchEvent(toastEvent);
        this.showSpinner = false;
    }

    initialSubmission(){
        
        if(this.deviationAtCurrentLevelNotApproved && this.nanoRecordType == false){
            this.showErrorIfCurrentDeviationsNotApproved();
            return;
        }
        
        referTheLoanApplication({
            recordId: this.recordId,
			approverId: this.selectedItem.value,
			comments: this.comments,
            level: this.userLevel,
            eligibleApprovalLevel: this.eligibleApprovalLevel
        })
        .then((data) => {
			const toastEvent = new ShowToastEvent({
				"title": "Success",
				"message": 'Successfully Submitted',
				"variant": "success"
			});
			this.dispatchEvent(toastEvent);
			this.showSpinner = false;
			const closeflow = new CustomEvent('closeflow', {
                detail: 'msg'
            });
            this.dispatchEvent(closeflow);
            publish(this.messageContext, RefreshMessageChannel, {message: ''});
        })
        .catch((error) => {
            const toastEvent = new ShowToastEvent({
				"title": "Error",
				"message": error.body.message,
				"variant": "error"
			});
			this.dispatchEvent(toastEvent);
			this.showSpinner = false;
        });
    }

    updateReuest(){
        let action;
        if(this.buttonLabel == 'Refer' || this.buttonLabel == 'Send for Approval'){
            action = 'Forward';
        }else if(this.buttonLabel == 'Send Back'){
            action = 'Returned';
        }
        /*
        if(this.deviationAtCurrentLevelNotApproved && action == 'Forward'){
            this.showErrorIfCurrentDeviationsNotApproved();
            return;
        }
        */
        updateApprover({
            recordId: this.recordId,
			approverId: this.selectedItem.value,
			comments: this.comments,
            action: action
        })
        .then((data) => {
            let act = action == 'Forward' ? 'Forwarded' : 'Returned';
			const toastEvent = new ShowToastEvent({
				"title": "Success",
				"message": 'Loan Application is '+act,
				"variant": "success"
			});
			this.dispatchEvent(toastEvent);
			this.showSpinner = false;
            const success = new CustomEvent('success', {
                detail: 'msg'
            });
            this.dispatchEvent(success);
        })
        .catch((error) => {
            const toastEvent = new ShowToastEvent({
				"title": "Error",
				"message": error.body.message,
				"variant": "error"
			});
			this.dispatchEvent(toastEvent);
			this.showSpinner = false;
        });
    }

    deviationAtCurrentLevelNotApproved = false;
    getRefreshDeviations(){
        getDeivations({
            recordId: this.recordId,
        })
        .then((data) => {
            let deviationAtCurrentLevelNotApproved = false;
            let deviations = data.deviations;
            let authority = data.approvalAuthority;
            if(deviations.length > 0){
                let tempRecords = JSON.parse( JSON.stringify( deviations ) );
                let deviationLevel = 0;
                tempRecords.forEach(res => {
                    deviationLevel = 0;
                    if( res.axisltd_Refer_To__c && res.axisltd_Refer_To__c.length == 2 && !isNaN(res.axisltd_Refer_To__c.substring(1)) &&
                        authority && authority.axisltd_Level_Of_Approval__c && authority.axisltd_Level_Of_Approval__c.length == 2 && !isNaN(authority.axisltd_Level_Of_Approval__c.substring(1))){
                        deviationLevel =  parseInt(res.axisltd_Refer_To__c.substring(1));
                        let userLevel = parseInt(authority.axisltd_Level_Of_Approval__c.substring(1));
                        if(deviationLevel !== 0 && deviationLevel <= userLevel &&
                            (!res.axisltd_Deviation_Description__c.includes(AMOUNT_DEVIATION) || !res.axisltd_Amount__c || res.axisltd_Amount__c <= authority.axisltd_Amount__c) &&
                            res.axisltd_Approval_Status__c != 'Approved'){
                            deviationAtCurrentLevelNotApproved = true;
                        }
                    }
                });
            }
            this.deviationAtCurrentLevelNotApproved = deviationAtCurrentLevelNotApproved;
            this.showSpinner = false;
        })
        .catch((error) => {
            this.showSpinner = false;
        });
    }

}