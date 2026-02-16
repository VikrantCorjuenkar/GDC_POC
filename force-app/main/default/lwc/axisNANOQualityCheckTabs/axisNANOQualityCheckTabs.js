import { LightningElement, api, wire } from 'lwc';
import userId from '@salesforce/user/Id';
import USERPROFILE_ID from '@salesforce/schema/User.Profile.Name';
import USER_PERSONA from '@salesforce/schema/User.PERSONA__c'; //BB-68145 (FCU) - Vikrant - Sprint 18
import { getRecord ,getFieldValue } from 'lightning/uiRecordApi';
import STAGE_FIELD from "@salesforce/schema/ResidentialLoanApplication.Status";

const FIELDS = [STAGE_FIELD];

export default class AxisNANOQualityCheckTabs extends LightningElement {
    @api
    recordId;
    @api objectApiName;
    currentUser = userId;
    isReadOnlyUser = false;
    lstReadOnlyProfiles = ['Axis Internal Read Only','Axis External Read Only'];

    //BB-BB-25843 - Vikrant - Sprint 15 - start
    profileName;
    prodDelinqAllowedProfiles = ['System Administrator', 'Axis_Underwriter', 'Axis Ops Maker User','Axis Ops Checker User'];
    get showCrossProductDelinquencyDetails(){
        return this.prodDelinqAllowedProfiles.includes(this.profileName);
    }
    //BB-BB-25843 - Vikrant - Sprint 15 - end

    //BB-68145 (FCU) - Vikrant - Sprint 18 - start - // Updated by Vikrant in Sprint 24 for BB-67868
    readOnlyPersona = false;
    personaList = ['FCU Sampler', 'FCU Manager', 'FCU Support Staff','HL Legal Manager', 'HL Technical Manager'];
    //BB-68145 (FCU) - Vikrant - Sprint 18 - end

    //BB-72956 ELK changes
    WIP_TABLE_VISIBLE = ['Axis_CA','Axis_Underwriter','System Administrator'];
    showWIPTable = false;

    @wire(getRecord, { recordId: userId, fields: [USERPROFILE_ID,USER_PERSONA]}) 
    userDetails({error, data}) {
        if (data) {
            console.log('Profile Name'+data.fields.Profile.value.fields.Name.value);
            this.profileName = data.fields.Profile.value.fields.Name.value; //BB-BB-25843 - Vikrant - Sprint 15
            this.isReadOnlyUser = !this.isReadOnlyUser ? this.lstReadOnlyProfiles?.includes(data.fields.Profile.value.fields.Name.value):this.isReadOnlyUser;

            //BB-68145 (FCU) - Vikrant - Sprint 18 - // Updated by Vikrant in Sprint 24 for BB-67868
            this.readOnlyPersona = this.personaList.includes(data.fields.PERSONA__c.value);
            if(this.readOnlyPersona){
                this.isReadOnlyUser = true;
            }

            //BB-72956 ELK changes
            this.showWIPTable = this.WIP_TABLE_VISIBLE.includes(this.profileName);
        } else if (error) {
            this.error = error ;
        }
    }

    @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
    loandetails({error,data}){
        if(data){
            this.isReadOnlyUser = !this.isReadOnlyUser ? data.fields.Status.value == 'Pre-Disbursement':this.isReadOnlyUser;
        }else if (error) {
            console.log('error:',error);
            this.error = error ;
        }
        
    }

    connectedCallback(){
    }
}