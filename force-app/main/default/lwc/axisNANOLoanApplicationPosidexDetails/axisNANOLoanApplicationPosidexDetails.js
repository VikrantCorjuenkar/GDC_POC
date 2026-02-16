/**
 * @description       : 
 * @author            : Amol
 * @group             : 
 * @last modified on  : 03-08-2024
 * @last modified by  : Amol 
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   03-08-2024   Amol   Initial Version
**/
import { LightningElement, api, track, wire } from 'lwc';
import getWCLoanAppApplicantsTypeAndIdsMap from '@salesforce/apex/AxisNANOLoanApplicantPosidexController.getNANOLoanAppApplicantsTypeAndIdsMap';
export default class AxisNANOLoanApplicationPosidexDetails extends LightningElement {
    @api
    recordId;
    @api
    isReadonlyuser;
    @track
    loanApplicantTypeAndIdsMap=[];
    
    @track
    completePosidexInfo;

    showSpinner = false;

    activeSections = ['Primary Applicant'];

    @wire(getWCLoanAppApplicantsTypeAndIdsMap, { applicationId: '$recordId'}) //$recordId
    wiredWCLoanAppApplicantsTypeAndIdsMap(result) {
        this.completePosidexInfo = result;
        const {data, error} = this.completePosidexInfo;
        if (data) {
            let applicantsData = data;
            for(var key in applicantsData){
                this.loanApplicantTypeAndIdsMap.push({value:applicantsData[key], key:key});
                applicantsData[key].forEach(appdata=> {
                    if(appdata && appdata.isFirst) {
                        this.activeSections.push(appdata.applicantName);
                    }
                });

            }
        } else if (error) {
            this.loanApplicantTypeAndIdsMap=[]; 
            
        } 
    }

}