import { LightningElement, track, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getNamespaceDotNotation } from 'omnistudio/omniscriptInternalUtils';
import { OmniscriptBaseMixin } from 'omnistudio/omniscriptBaseMixin';
import getBureauResultsList from '@salesforce/apex/PreviewBureauResultController.getBureauResultsListNano';     // replace method with nano specific method to remove cacheable BB-44750 Surag
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAllConfigurations from '@salesforce/apex/AxisNano_CustomMdtUtility.getAllConfigurations';
import updateOwnerWithManagerId from '@salesforce/apex/axisNanoLoanApplicationFormController.updateOwnerWithManagerId';
import updatePSS from '@salesforce/apex/AxisNanoCustomController.updatePSS';
import updateAppScore from '@salesforce/apex/AxisNanoCustomController.updateAppScore';
import AxisNanoSMUserProfileNames from "@salesforce/label/c.AxisNanoSMUserProfileNames";
import pdflib from "@salesforce/resourceUrl/pdflib";
import DOMPurify from "@salesforce/resourceUrl/sanitizer";

import { getRecord, getFieldValue } from 'lightning/uiRecordApi'; //AA BB-93158 CRIF score for bureau
import PRODUCT_FIELD from '@salesforce/schema/ResidentialLoanApplication.axisltd_Product__c'; //AA BB-93158 CRIF score for bureau

export default class AxisNanoApplicantCreditScore extends OmniscriptBaseMixin(NavigationMixin(LightningElement)) {
    startValue = 300;
    endValue = 900;
    @api applicantName = 'Chetan';
    @api cibilValue; // 700
    @api crifValue; // 800
    @api breDecision = 'REFER';
    @api appScoreBand; //9 BlazeScore
    @api deviationRange;
    @track isGreenBox; @track isYellowBox; @track isRedBox;
    @track isShowModal = false;
    @track isShowModalCrif = false;
    @api loanAppId;
    @api loanApplicantId;
    @api isCoApplicant;
    @api serialNumber;
    @api userProfileName = '';
    @api leadId;
    @track profileNames = [];
    isInternalSalesforce;
    contentVersion;
    documentId;
    _ns;
    isLoading = false;
    isScoresAvailable = false;
    showCrifFilePreview = false;
    showCibilFilePreview = false;
    cibilDocumentId;
    crifDocumentId;
    contentVersionId;
    crifVersionId;
    crifContent;
    showErrorPopup = false;
    buttonName ;
    productValue;
        
    connectedCallback() {
        // Invoke the imperative Apex method when the component is connected to the DOM
        this.loadConfigurations();
        this.checkScoresAvailable();
       //this.callGetBureauResultsList(false);
        this._ns = getNamespaceDotNotation();
        this.isInternalSalesforce = window.location.href.includes('lightning.force.com');

        //AA BB-93158 CRIF score for bureau start
        if(this.loanApplicantId == null) {
            this.loanApplicantId = this.omniJsonData?.isCoApplicant ? this.omniJsonData?.CoAppId : this.omniJsonData?.LoanApplicantDetails?.LoanApplicant?.Id;
        }
        if(this.loanAppId == null) {
            this.loanAppId = this.omniJsonData?.isCoApplicant ? this.omniJsonData?.loanApplicationId : this.omniJsonData?.LoanApplicantDetails?.LoanApplication?.Id;
        }
        //AA BB-93158 CRIF score for bureau end
        
    }
    get showCRIFscreen(){
        // if(this.productValue == null  && this.omniJsonData?.SelectProduct?.Products != null) {
        //     this.productValue = this.omniJsonData?.SelectProduct?.Products;
        // }
        console.log('AA this.productValue', this.productValue);
        let showCRIF = false;
        if(this.cibilValue !== '' && this.cibilValue !== undefined) {
            if(this.productValue ==='Unsecured BL' || this.productValue ==='BIZ_LAA1') {
                showCRIF = true;
            } else if((this.productValue ==='Micro LAP' || this.productValue ==='MICR_LAP') && this.cibilValue <= 0) {
                showCRIF = true;
            }
        }
        return showCRIF;
        // return this.cibilValue != '' && this.cibilValue != undefined && (((this.productValue =='Micro LAP' || this.productValue =='MICR_LAP') && this.cibilValue <= 0) || (this.productValue =='Unsecured BL' || this.productValue =='BIZ_LAA1')); //AA BB-93158 CRIF score for bureau
    }

    //AA BB-93158 CRIF score for bureau start

    @wire(getRecord, { recordId: '$loanAppId', fields: [PRODUCT_FIELD] })
    Recordtypdetails({error, data}){
        console.log('AA --loanAppId--',this.loanAppId);
        if(data){
            console.log('--loanAppId--',this.loanAppId);
            console.log('--data--',data);
            this.productValue = data.fields.axisltd_Product__c.value;
            if(this.productValue == null  && this.omniJsonData?.SelectProduct?.Products != null) {
                this.productValue = this.omniJsonData?.SelectProduct?.Products;
            }
        }else{  console.log('--error--',JSON.stringify(error));
            console.log('--error--',error);
        }
    }

    // @wire(getRecord, { recordId: '$loanAppId', fields: [PRODUCT_FIELD] })
    // productRecord({ error, data }) { // Result object with data/error
    //     if (data) {
    //         this.productValue = getFieldValue(data, PRODUCT_FIELD);
    //         console.log('productValue:', this.productValue);
    //         if(this.productValue == null  && this.omniJsonData?.SelectProduct?.Products != null) {
    //             this.productValue = this.omniJsonData?.SelectProduct?.Products;
    //         }
    //         // this.showCRIFscreen = this.cibilValue != '' && this.cibilValue != undefined && (((this.productValue =='Micro LAP' || this.productValue =='MICR_LAP') && this.cibilValue <= 0) || (this.productValue =='Unsecured BL' || this.productValue =='BIZ_LAA1'));
    //     } else if (error) {
    //         console.error('Error fetching account:', error);
    //     }
    // }

    // get productValue() {
    //     return getFieldValue(this.productRecord.data, PRODUCT_FIELD);
    // }
    //AA BB-93158 CRIF score for bureau end

    loadConfigurations() {
        // Make an imperative call to the Apex method
        getAllConfigurations({ metadataTypeName: 'Axis_Nano_Configuration__mdt' })
            .then(result => {
                // Handle the retrieved configurations
                this.configurations = result;
                // Call your method here with the retrieved data
                this.evaluateDynamicConditions();
                
                

            })
            .catch(error => {
                // Handle the error
                console.error('Error retrieving configurations:', error);
            });
    }
    get showREButton() {
        this.profileNames = AxisNanoSMUserProfileNames.split(";");
        return this.isYellowBox == true && !this.profileNames.includes(this.userProfileName);
    }
    get buttonStatus() {
        if (this.appScoreBand > 8) {
            return 'Approve';
        } else if (this.appScoreBand <= 8 && this.appScoreBand >= 3) {
            return 'Refer';
        } else {
            return 'Reject';
        }
    }
    // get isScoresAvailable() {
    //     return this.isScoresAvailable == false && ((this.appScoreBand != undefined && this.appScoreBand != null) || this.isCoApplicant == true) && this.crifValue != undefined && this.crifValue != null && this.cibilValue != undefined && this.cibilValue != null;
    // }

    checkScoresAvailable(){
        if(this.isScoresAvailable == false && ((this.appScoreBand != undefined && this.appScoreBand != null) || this.isCoApplicant == true) && (this.crifValue != undefined || this.cibilValue != undefined) && this.serialNumber != undefined && this.serialNumber != null){
            this.isScoresAvailable = true;
            this.isLoading = false;
            
        }
    }


    /*get isGreenBox(){
        //return this.appScoreBand >= 8;
        return this.evaluateDynamicConditions() == 'Approve';
    }
    get  isYellowBox(){
        //return this.appScoreBand <8 && this.appScoreBand >= 3;
        return this.evaluateDynamicConditions() == 'Refer';
    }
    get isRedBox(){
        //return this.appScoreBand < 3;
        return this.evaluateDynamicConditions() == 'Reject';
    }*/
    /*
renderedCallback() {
    this.setRotations();
}

setRotations() {
    const cibilRotation = ((this.cibilValue - this.startValue) / (this.endValue - this.startValue)) * 180;
    const crifRotation = ((this.crifValue - this.startValue) / (this.endValue - this.startValue)) * 180;

    const cibilGraphAfter = this.template.querySelector('.cibil .graph:after');
    const crifGraphAfter = this.template.querySelector('.crif .graph:after');

    if (cibilGraphAfter) {
        cibilGraphAfter.style.setProperty('--rotation-angle', `${cibilRotation}deg`);
    }

    if (crifGraphAfter) {
        crifGraphAfter.style.setProperty('--rotation-angle', `${crifRotation}deg`);
    }
}

   get cibilNeedleStyle() {
    return `transform: rotate(${((this.cibilValue - this.startValue) / (this.endValue - this.startValue) * 180) - 90}deg);`;
}

get crifNeedleStyle() {
    return `transform: rotate(${((this.crifValue - this.startValue) / (this.endValue - this.startValue) * 180) - 90}deg);`;
}


    get cibilGraphStyle() {
        return `width: 300px; height: 150px; position: relative;`;
    }

    get crifGraphStyle() {
        return `width: 300px; height: 150px; position: relative;`;
    }*/


    navigateToRecordPage() {
        //let currentApplicant = this.loanAppId; //BB-93129: Commented by : Puru
        let currentApplicant = this.loanAppId ? this.loanAppId : this.omniJsonData?.LoanApplicantDetails?.LoanApplication?.Id; //BB-93129: LoanAppId fix : Puru
        if(this.isCoApplicant == true){
            currentApplicant = this.omniJsonData?.CoAppId;
        }
        //this.loanAppId = '0cdFf0000002JWPIA2';
        if(this.isInternalSalesforce){
          // const url = `/${this.loanAppId}`;
           const url = `/${currentApplicant}`;
           // Use window.location.href to navigate
           window.location.href = url;
        }else{
            let url;
            if(this.isCoApplicant == true){
            url  = `/s/loanapplicant/${currentApplicant}`;
            }
            else{
                //const url = `/s/residentialloanapplication/${this.loanAppId}`;
            url = `/s/residentialloanapplication/${currentApplicant}`;
            }
            
            // Use window.location.href to navigate
            window.location.href = url;
        }
       
    }
    @track isShowModal = false;

    showModalBox() {
        this.isShowModal = true;
    }

    hideModalBox() {
        this.isShowModal = false;
    }

    buildDynamicConditions(conditions) {
        const dynamicConditions = conditions.map((condition, index) => {
            const subConditions = condition.split(';');
            const subConditionStatements = subConditions.map(subCondition => {
                const parts = subCondition.split(/([<>]=?)/);
                const operator = parts[1];
                const value = parts[2];
                return `(this.appScoreBand ${operator} ${value})`;
            });
            return subConditionStatements.join(' && ');
        });

        return dynamicConditions.join(' else ');
    }

    evaluateDynamicConditions() {
        if (!this.configurations) {
            // Configurations not available, return or handle accordingly
            return;
        }

        const conditions = this.configurations;//['>8', '>3;=<8', '<3;'];
        
        for (let i = 0; i < conditions.length; i++) {
            const subConditions = conditions[i].split(';');
            let isConditionMet = true;

            for (let j = 0; j < subConditions.length; j++) {
                const parts = subConditions[j].split(/([<>]=?)/);
                const operator = parts[1];
                const value = parseInt(parts[2], 10);

                if (operator === '>' && !(this.appScoreBand > value)) {
                    isConditionMet = false;
                    break;
                } else if (operator === '<' && !(this.appScoreBand < value)) {
                    isConditionMet = false;
                    break;
                } else if (operator === '>=' && !(this.appScoreBand >= value)) {
                    isConditionMet = false;
                    break;
                } else if (operator === '<=' && !(this.appScoreBand <= value)) {
                    isConditionMet = false;
                    break;
                }
            }

            if (isConditionMet) {
                if (i === 0) {
                    this.isGreenBox = true;  //'Approve';
                } else if (i === 1) {
                    //return 'Refer';
                    this.isYellowBox = true;
                } else if (i === 2) {
                    // Handle the case when i === 2
                    // return 'Reject';
                    this.isRedBox = true;
                }
            }
        }

        // Default case if none of the conditions are met
        return 'Default';
    }
    hideModalBoxCrif() {
        this.isShowModalCrif = false;
    }
    showModalBoxCrif() {
        this.isShowModalCrif = true;
        
    }
    handleReferToSMClick() {
        updateOwnerWithManagerId({ loanApplicationId: this.loanAppId })
            .then(result => {
                if (result === 'Success') {
                    // Handle success, if needed
                    this.navigateToRecordPage();
                } else {
                    this.showToast('Error', result, 'error');
                }
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }


    bureauResultList;
    isCommunity = false;
    cibilContent;
    disableButton = false;

   /* callGetBureauResultsList(checkError) {
        getBureauResultsList({ loanApplicantId: this.loanApplicantId, isFromCommunity: this.isCommunity })
            .then(result => {
                
                
                this.bureauResultList = result;
                
                this.bureauResultList.forEach((itm) => {
                    if(itm.brType == 'CIBIL'){
                        this.cibilContent = itm.contentValue;
                        this.contentVersionId = itm.contentVersionId;
                        this.cibilDocumentId = itm.documentId;
                        
                        if(this.cibilContent){
                            this.showCibilFilePreview = true;
                        }else if(checkError){
                            
                            this.showErrorPopup = true;
                        }
                    }else if(itm.brType == 'CRIF'){
                        this.crifContent = itm.contentValue;
                        this.crifVersionId = itm.contentVersionId;
                        this.crifDocumentId = itm.documentId;
                        
                        if(this.crifContent){
                            this.showCrifFilePreview = true;
                        }else if(checkError){
                            this.showErrorPopup = true;
                        }
                    }
                }) 
            })
            .catch(error => {
                console.error('Error fetching data:', error);
                // Handle the error as needed
            });
    }*/
    callGetBureauResultsList(checkError) {
        // Add a time delay of 2 seconds
        const delayInMilliseconds = 4000;
        
        // Call getBureauResultsList after the delay
        this.isLoading = true;
        // setTimeout(() => {
            if(this.loanApplicantId == null) {
                this.loanApplicantId = this.omniJsonData?.LoanApplicantDetails?.LoanApplicant?.Id;
            }
            if(this.loanAppId == null) {
                this.loanAppId = this.omniJsonData?.LoanApplicantDetails?.LoanApplication?.Id;
            }
            let currentApplicantId = this.loanApplicantId;
            if(this.isCoApplicant == true){
                currentApplicantId = this.omniJsonData?.CoAppId;
            }

            
            getBureauResultsList({ loanApplicantId: currentApplicantId, isFromCommunity: this.isCommunity })
                .then(result => {
                    
                    
                    
                    this.bureauResultList = result;
                    
                    this.bureauResultList.forEach((itm) => {
                        if(itm.brType == 'CIBIL'){
                            this.cibilContent = itm.contentValue;
                            this.contentVersionId = itm.contentVersionId;
                            this.cibilDocumentId = itm.documentId;
                            
                            if(this.cibilContent && this.buttonName =='View CIBIL Report'){
                                this.showCibilFilePreview = true;
                                //
                                
                            }else if(checkError && this.buttonName =='View CIBIL Report'){
                                
                                this.showErrorPopup = true;
                            }
                        }else if(itm.brType == 'CRIF'){
                            this.crifContent = itm.contentValue;
                            this.crifVersionId = itm.contentVersionId;
                            this.crifDocumentId = itm.documentId;
                            
                            if(this.crifContent && this.buttonName == 'View CRIF Report'){
                               // this.template.querySelector('c-file-preview').handleValueChange();
                               this.showCrifFilePreview = true;
                            }else if(checkError && this.buttonName == 'View CRIF Report'){
                                this.showErrorPopup = true;
                            }
                        }
                    }) 
                    this.isLoading = false;
                })
                .catch(error => {
                    console.error('Error fetching data:', error);
                    this.isLoading = false;
                    // Handle the error as needed
                });
        // }, delayInMilliseconds);
    }

    handlePreviewFile(event){
        this.buttonName = event.target.name;
        
        console.log('entered in timeout')
     //   clearTimeout(this.timeoutId); // no-op if invalid id
    //  this.timeoutId = setTimeout(this.callGetBureauResultsList.bind(this,true), 2000);
        this.callGetBureauResultsList(true);
    }

    closeModal(){
        this.showErrorPopup = false;
    }

    handleRefresh() {
        this.isLoading = true;
        //app score band and CIBIL/CRIF score api call
        
        
        if (this.cibilValue == undefined || this.crifValue == undefined || this.serialNumber == undefined || this.serialNumber == null) {
            
            //(TG) : BB-90129 ( BugFix for co-applicant credit score)
            if(this.omniJsonData !== undefined && this.omniJsonData?.CoAppId != undefined){
                //For Co-Applicant
                this.getCibilAndCrifScore(this.omniJsonData?.ContextId, this.omniJsonData?.CoAppId);
            }else{
                //For Primary Applicant
                this.getCibilAndCrifScore(this.loanAppId, this.loanApplicantId);
            }
            
        }
        if (this.appScoreBand == undefined && this.isCoApplicant == false && this.serialNumber != undefined && this.serialNumber != null) {
            
            this.getAppScore(this.loanAppId, this.loanApplicantId);
        }
        this.checkScoresAvailable();
    }

    getAppScore(LoanApplicationId, LoanApplicantId) {
        
        this.isLoading = true;
        const params = {
            input: JSON.stringify({ LoanApplicationId, LoanApplicantId, LeadId: this.leadId,isCoApplicant:this.isCoApplicant, serialNo : this.serialNumber }),
            sClassName: this._ns + 'IntegrationProcedureService',
            sMethodName: 'AppScoreIP_AppScoreIP',
            options: '{}',
        };

        this.omniRemoteCall(params, true).then(response => {
            // {"result":{"IPResult":{"success":false,"result":{"errorCode":"INVOKE-500","error":"Invalid integer: "}},"error":"OK"},"error":false}
            // {"result":{"IPResult":{"AppScoreBand":"3"},"error":"OK"},"error":false}
            
            
            let getAppScoreResponse = response.result.IPResult;

            if (Object.keys(getAppScoreResponse).includes('success') && !getAppScoreResponse.success) {
                
                if(getAppScoreResponse.result.error && getAppScoreResponse.result.error.includes('Invalid initialization vector')){
                    this.showToast('Error', 'No response received from API. Please try again.', 'error');
                }else{
                    this.showToast('Error', getAppScoreResponse.result.error, 'error');
                }
            } else if (!Object.keys(getAppScoreResponse).includes('AppScoreBand')) {
                
                this.showToast('Error', 'Something went wrong while fetching app score band. Please try again!', 'error');
            } else {
                this.appScoreBand = getAppScoreResponse.AppScoreBand;
                this.evaluateDynamicConditions();
                let rejectApplication = false;
                if(this.isRedBox == true && !this.isCoApplicant && this.this.appScoreBand != undefined){
                    rejectApplication = true;
                }
                if(this.appScoreBand != undefined){
                    updateAppScore({loanAppId: LoanApplicationId, appScore: this.appScoreBand, rejectApplication: rejectApplication})
                    .then((result) => {
                    })
                    .catch((error) => {
                        
                        this.error = error;
                    });
                }
            }
            
            
            this.omniApplyCallResp(getAppScoreResponse);
            this.checkScoresAvailable();
            this.isLoading = false;
        }).catch(error => {
            
            this.isLoading = false;
        });
    }

    getCibilAndCrifScore(LoanApplicationId, LoanApplicantId) {
        this.isLoading = true;
        
        let params;

        if(this.isCoApplicant){
             params = {
                input: JSON.stringify({ LoanApplicationId, LoanApplicantId,isCoApplicant:this.isCoApplicant }),
                sClassName: this._ns + 'IntegrationProcedureService',
                sMethodName: 'BureauResultComp_BureauResultComp',
                options: '{}',
            };
        }
        else{
             params = {
                input: JSON.stringify({ LoanApplicationId, LoanApplicantId,LeadId: this.leadId,isCoApplicant:this.isCoApplicant }),
                sClassName: this._ns + 'IntegrationProcedureService',
                sMethodName: 'BureauResultComp_BureauResultComp',
                options: '{}',
            };
        }

        this.omniRemoteCall(params, true).then(response => {
            
            let cibilAndCrifScoreResponseResponse = response.result.IPResult;
            if(Object.keys(cibilAndCrifScoreResponseResponse).includes('SRNO')){
                this.serialNumber = cibilAndCrifScoreResponseResponse.SRNO;
                }
            
            

            if (Object.keys(cibilAndCrifScoreResponseResponse).includes('success') && !cibilAndCrifScoreResponseResponse.success) {
                
                if(cibilAndCrifScoreResponseResponse.result.error && cibilAndCrifScoreResponseResponse.result.error.includes('Invalid initialization vector')){
                    this.showToast('Error', 'No response received from API. Please try again.', 'error');
                }else{
                    this.showToast('Error', cibilAndCrifScoreResponseResponse.result.error, 'error');
                }
            } else if (!Object.keys(cibilAndCrifScoreResponseResponse).includes('CIBIL') && !Object.keys(cibilAndCrifScoreResponseResponse).includes('CRIF') && Object.keys(cibilAndCrifScoreResponseResponse).includes('error')) {
                
                if(cibilAndCrifScoreResponseResponse.error && cibilAndCrifScoreResponseResponse.error.includes('Invalid initialization vector')){
                    this.showToast('Error', 'No response received from API. Please try again.', 'error');
                }else{
                    this.showToast('Error', cibilAndCrifScoreResponseResponse.error, 'error');
                }
            } 
            // else if (!Object.keys(cibilAndCrifScoreResponseResponse).includes('CIBIL') || !Object.keys(cibilAndCrifScoreResponseResponse).includes('CRIF')) {
                
                
            //     this.showToast('Error', 'Something went wrong while fetching CIBIL and CRIF score. Please try again!', 'error');
            // }
            // else if(cibilAndCrifScoreResponseResponse.CIBIL == '' && cibilAndCrifScoreResponseResponse.CRIF ==''){
                
            //     this.cibilValue = 0;
            //     this.crifValue = 0;
            //     //this.showToast('Error', 'Something went wrong while fetching CIBIL and CRIF score. Please try again!', 'error');
            // }else if(cibilAndCrifScoreResponseResponse.CIBIL == ''){
            //     console.error('@@CBIL value null::');
            //     this.cibilValue = 0;
            //     this.crifValue = cibilAndCrifScoreResponseResponse.CRIF;
            // }else if(cibilAndCrifScoreResponseResponse.CRIF == ''){
            //     console.error('@@CRIF value null::');
            //     this.crifValue = 0;
            //     this.cibilValue = cibilAndCrifScoreResponseResponse.CIBIL;
            // }else if(cibilAndCrifScoreResponseResponse.CIBIL == 'Score not obtained from bureau' && cibilAndCrifScoreResponseResponse.CRIF == 'Score not obtained from bureau'){
            //     this.cibilValue = 0;
            //     this.crifValue = 0;
            // }else if(cibilAndCrifScoreResponseResponse.CIBIL == 'Score not obtained from bureau'){
            //     this.cibilValue = 0;
            //     this.crifValue = cibilAndCrifScoreResponseResponse.CRIF;
            // }else if(cibilAndCrifScoreResponseResponse.CRIF == 'Score not obtained from bureau'){
            //     this.crifValue = 0;
            //     this.cibilValue = cibilAndCrifScoreResponseResponse.CIBIL;
            // } else {
            //     this.cibilValue = cibilAndCrifScoreResponseResponse.CIBIL;
            //     this.crifValue = cibilAndCrifScoreResponseResponse.CRIF;
            // }

            this.cibilValue = null;
            this.crifValue = null;
            //  if (Object.keys(cibilAndCrifScoreResponseResponse).includes('SRNO')) {
                if (Object.keys(cibilAndCrifScoreResponseResponse).includes('CIBIL')){
                    if (cibilAndCrifScoreResponseResponse.CIBIL == '') {
                        this.cibilValue = 0;
                    }  else if (cibilAndCrifScoreResponseResponse.CIBIL == 'Score not obtained from bureau') {
                        this.cibilValue = 0;
                    } else {
                        this.cibilValue = cibilAndCrifScoreResponseResponse.CIBIL;
                    }
                } 
                if(Object.keys(cibilAndCrifScoreResponseResponse).includes('CRIF')) {
                    if (cibilAndCrifScoreResponseResponse.CRIF == '') {
                        this.crifValue = 0;
                    } else if (cibilAndCrifScoreResponseResponse.CRIF == 'Score not obtained from bureau') {
                        this.crifValue = 0;
                    } else {
                        this.crifValue = cibilAndCrifScoreResponseResponse.CRIF;
                    }
                } 
            // }
            
            if(this.cibilValue){
                if(this.cibilValue.includes('-')){
                    this.cibilValue = '-' + this.cibilValue.split('-')[1];
                }
            }

            if(this.crifValue){
                if(this.crifValue.includes('-')){
                    this.crifValue = '-' + this.crifValue.split('-')[1];
                }
            }

            
            
            
            
                        
            if(this.isScoresAvailable == false && ((this.appScoreBand != undefined && this.appScoreBand != null) || this.isCoApplicant == true) && this.crifValue != undefined && this.crifValue != null && this.cibilValue != undefined && this.cibilValue != null){
                this.isScoresAvailable = true;
            

            }
            
            this.omniApplyCallResp(cibilAndCrifScoreResponseResponse);
            if(this.crifValue != undefined && this.cibilValue != undefined){
                
                updatePSS({loanApplicantId: LoanApplicantId , cibilValue: this.cibilValue, crifValue: this.crifValue,serialNo :this.serialNumber,isCoApplicant:this.isCoApplicant})
                .then(result => {
                    this.callGetBureauResultsList(false);
                })
                .catch(error => {
                    console.error('Error updating pss data:', error);
                    // Handle the error as needed
                });
            }
            this.checkScoresAvailable();
            this.isLoading = false;
        }).catch(error => {
            
            this.showToast('Error', error.message, 'error');
            this.isLoading = false;
        });
    }

}