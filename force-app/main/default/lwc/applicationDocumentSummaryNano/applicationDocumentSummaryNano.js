import { LightningElement, api, track, wire } from 'lwc';
import bypassLocationRestriction from '@salesforce/customPermission/Bypass_Location_Access_Restriction';
import { refreshApex } from '@salesforce/apex';
import getAllRelatedDocsDetails from '@salesforce/apex/ApplicationDocumentSummaryController.getAllRelatedDocsDetails';
import {getRecord,getFieldValue } from 'lightning/uiRecordApi' ;                                           //Avinash
/*import LOAN_APPLICATION_STATUS_FIELD from '@salesforce/schema/ResidentialLoanApplication.Status' ;       //Avinash
import LOAN_APPLICATION_RECORD_TYPE_ID from '@salesforce/schema/ResidentialLoanApplication.RecordTypeId' ; //Avinash
import LOAN_APPLICATION_RECORD_TYPE_DEV_NAME from '@salesforce/schema/ResidentialLoanApplication.RecordType.DeveloperName' ; //Avinash
import LOAN_APPLICATION_OWNERID from '@salesforce/schema/ResidentialLoanApplication.OwnerId' ;*/           //Avinash
import CURRENT_USER_ID from "@salesforce/user/Id";                                                         //Avinash
import getLoanApplicationDetails from '@salesforce/apex/ApplicationDocumentSummaryController.getLoanApplicationDetails'; //Avinash

// WC 17235
import getDocumentCheckWorkCapitalHelper from '@salesforce/apex/ApplicationDocumentSummaryController.getDocumentCheckWorkCapitalHelper';
//import WC_TEMPLATE_DOC_MANAGER from './applicationDocumentSummaryWC.html';
import NANO_TEMPLATE_DOC_MANAGER from './applicationDocumentSummaryNano.html';
//import {errorToStringSingleLine} from 'c/uiErrorHandling';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// WC 17235

export default class ApplicationDocumentSummaryNano extends LightningElement {
    @api recordId = undefined ; //Avinash
    @api isCommunity;
    @api newLayoutFields = `[
        {"apiName":"Name","defaultName":"Other", "readonly": true},
        {"apiName":"axisltd_Status__c","disabled": true},
        {"apiName":"axisltd_is_original__c"},
        {"apiName":"axisltd_remarks__c"},
        {"apiName":"axisltd_received_date__c","readonly": true},
        {"apiName":"axisltd_Approved_By__c","disabled": true}
        ]`;
    @api editLayoutFields = `[
        {"apiName":"axisltd_Display_Name__c", "readonly": true},
        {"apiName":"Name", "readonly": true},
        {"apiName":"axisltd_Mandatory__c", "disabled": true},
        {"apiName":"axisltd_Status__c"},
        {"apiName":"axisltd_is_original__c"},
        {"apiName":"axisltd_remarks__c"},
        {"apiName":"axisltd_received_date__c","readonly": true},
        {"apiName":"axisltd_Approved_By__c","disabled": true},
        {"apiName":"axisltd_deferred_date__c","disabled": true}
        ]`;
    @api additionalTableColumns = `[
        {"fieldToQuery":"tolabel(axisltd_Status__c)","label": "Status", "fieldName": "axisltd_Status__c", "type": "text","hideDefaultActions": true},
        {"fieldToQuery":"axisltd_remarks__c","label": "Remarks", "fieldName": "axisltd_remarks__c", "type": "text","hideDefaultActions": true}
    ]`;
    @api CompressionToggle;
    @api CompressionRequired;
    
    wiredResponse;
    responseWrapper;
    showSpinner = true;
    recordResponse = false;
    navigatorResponse = false;
    @api skipGeoLocation= false;

    @api dclRecordTypeDeveloperName;
    loanApplication = {} ; //Avinash

    // WC 17235
    parentTabActive = 'loan_application_tab';
    childTabActive = '';
    applicantSections;
    collateralSections;
    @track _documentCheckListListWc = null;
    _searchFilterSelectedRecord = null;
    _statusFilterSelectedValue = 'all';
    _defaultDcListRecordTypeId;
    isLoadingWc = true;

    showEditNewModal = false;
    historyModal = false;
    attachPropertyModal = false;
    documentCheckListIdSelectedForHistory = null;
    documentCheckListNameSelectedForHistory = null;
    documentCheckListIdSelectedForAttachingProperty = null;
    
    documentChecklistListWc = {
        loanApplication : null,
        loanApplicant : null,
        loanCollateral : null,

    };

    get isCreateButtonVisibleWc(){
        return this._profileName.toLowerCase().includes('administrator') || CURRENT_USER_ID === this.loanApplication['ownerId']
    }

    _profileName
    @wire(getRecord,{recordId : CURRENT_USER_ID, fields : ['User.Profile.Name']})
    wiredUser({ error, data }) {
        if (data) {
             this._profileName = getFieldValue(data, 'User.Profile.Name');
        } else if (error) {
            console.error('Error fetching user record:', error);
        }
    }

    handleOpenHistoryModal(event){
        this.documentCheckListIdSelectedForHistory = event.detail.recordId;
        this.documentCheckListNameSelectedForHistory = event.detail.recordName;
        this.historyModal = true;
    }

    handleCloseHistoryModal(){
        this.historyModal = false;
        this.documentCheckListIdSelectedForHistory = null;
        this.documentCheckListNameSelectedForHistory = null;
    }
    handleCloseAttachingPropertyModal(){
        this.attachPropertyModal = false;
        this.documentCheckListIdSelectedForAttachingProperty = null;
        this.handleDocumentFilterChildMethodCall('master_refresh');
    }
    handleOpenAttachingPropertyModal(event){
        this.documentCheckListIdSelectedForAttachingProperty = event.detail.recordId;
        this.attachPropertyModal = true;
    }
    handleNewCreateRefresh(){
        this.handleCloseNewModal();
        this.handleDocumentFilterChildMethodCall('master_refresh');
    }
    handleCloseNewModal(){
        this.showEditNewModal = false;
    }

    handleNewDocumentCheckList(){
        this.showEditNewModal = true;
    }

    handleParentTabName(tab_id){
        switch(tab_id){
            case 'loan':
                this.parentTabActive = 'loan_application_tab';
                break;
            case 'applicant':
                this.parentTabActive = 'loan_applicant_tab';
            break;
            case 'collateral':
                this.parentTabActive = 'loan_collateral_tab';
            break;
        }
    }

    render() {
        return this.isWcLoanApplication ? WC_TEMPLATE_DOC_MANAGER : NANO_TEMPLATE_DOC_MANAGER;
    }

    get isLoanApplicationLevelDocumentExist(){
        return this.documentChecklistListWc.loanApplication !== null;
    }

    get isWcLoanApplication(){
        return this.loanApplication?.recordTypeDevName == 'WC';
    }

    get isDocumentChecklistInitialized(){
        return this._documentCheckListListWc;
    }

    handleDefaultDocumentCheckListRecordTypeId(data){
        if(data && data.length > 0){
            this._defaultDcListRecordTypeId = data[0].RecordTypeId;
        }
    }

    handleInitiateWcInitialization(){
        if(this.isWcLoanApplication && this.isDocumentChecklistInitialized){
            this.handleGetDocumentChecklist(this._documentCheckListListWc);
        }
    }

    handleExpandAccordionApplicant(data){
        let uniqueApplicantNames = new Set();
        for(let i of data){
            if(i.axisltd_Loan_Applicant__c){
                uniqueApplicantNames.add(i.axisltd_Loan_Applicant__c);
            }
        }
        this.applicantSections = [...uniqueApplicantNames];
    }

    handleLoadAllParentTabs(){
        setTimeout(() => {
            this.handleParentTabName('loan');
            setTimeout(() => {
                this.handleParentTabName('applicant');
                setTimeout(() => {
                    this.handleParentTabName('collateral');
                    setTimeout(() => {
                        this.handleParentTabName('loan');
                    });
                });
            });
            
        });
    }

    handleExpandAccordionCollateral(data){
        let uniqueApplicantNames = new Set();
        for(let i of data){
            if(i.Loan_Application_Asset__c){
                uniqueApplicantNames.add(i.Loan_Application_Asset__c);
            }
        }
        this.collateralSections = [...uniqueApplicantNames];
    }


    async handleGetDocumentChecklist(data){
        try {
            // SWC-27421
            let mutableData = JSON.parse(JSON.stringify(data));
            this.handleDefaultDocumentCheckListRecordTypeId(mutableData);
            this.isLoadingWc = true;
            // let resp = await getDocumentCheckWorkCapitalHelper({recordId : this.recordId});
            const loanApplicationDocumentRecords = this.handleLoanApplicationDocumentsJsonFormation(mutableData);
            const loanApplicantDocumentRecords = this.handleLoanApplicantDocumentJsonFormation(mutableData);
            const loanApplicationAssetDocumentRecords = this.handleLoanAssetDocumentJsonFormation(mutableData);
            // SWC-27421
            this.documentChecklistListWc = {
                loanApplication : {
                    records : loanApplicationDocumentRecords,
                    hasRecords : loanApplicationDocumentRecords[0].categoryTab.length > 0
                },
                loanApplicant : {
                    records : loanApplicantDocumentRecords,
                    hasRecords : loanApplicantDocumentRecords.length > 0
                },
                loanCollateral : {
                    records : loanApplicationAssetDocumentRecords,
                    hasRecords : loanApplicationAssetDocumentRecords.length > 0
                }
            }
            console.log('this.documentChecklistListWc ' + JSON.stringify(this.documentChecklistListWc));
            this.handleExpandAccordionApplicant(data);
            this.handleExpandAccordionCollateral(data);
            this.handleLoadAllParentTabs();
            this.isLoadingWc = false;
        } catch (error) {
            this.handleError(error);
        }
    }

    handleCategorySubCategory(data){
        let documentCategorySubCategoryMap = new Map();
        let categorySubCategoryAlreadyAdded = new Set();
        // let categoryAdded = new Set();
        for(let i of data){
            let subCategoryData = [];
            // SWC-27241
            if(!i.axisltd_Document_Category__c){
                i.axisltd_Document_Category__c = 'Login Documents';
            }
            if(!i.axisltd_Document_Sub_Category__c){
                i.axisltd_Document_Sub_Category__c = 'Others';
            }
            // SWC-27241
            if(documentCategorySubCategoryMap.has(i.axisltd_Document_Category__c)){
                subCategoryData = documentCategorySubCategoryMap.get(i.axisltd_Document_Category__c);
            }
            // SWC-27241
            /*if(!i.axisltd_Document_Sub_Category__c || !i.axisltd_Document_Category__c || categorySubCategoryAlreadyAdded.has(i.axisltd_Document_Category__c + i.axisltd_Document_Sub_Category__c)){
                continue;
            }*/
           if(categorySubCategoryAlreadyAdded.has(i.axisltd_Document_Category__c + i.axisltd_Document_Sub_Category__c)){
                continue;
            }
            
           // SWC-27241
            categorySubCategoryAlreadyAdded.add(i.axisltd_Document_Category__c + i.axisltd_Document_Sub_Category__c);
            // categoryAdded.add(i.axisltd_Document_Category__c);

            subCategoryData.push({
                label : i.axisltd_Document_Sub_Category__c
            });
            documentCategorySubCategoryMap.set(i.axisltd_Document_Category__c, subCategoryData);
        }
        let categoryArr = [];
        for(const [key, value] of documentCategorySubCategoryMap){
            if(value.length > 0){
                categoryArr.push({
                    value : key,
                    subCategories : value
                });
            }
        }
        
        // return {categoryArr, categoryAdded};
        return categoryArr;
    }

    handleLoanApplicationDocumentsJsonFormation(data){
        let resp = [];
        let loanApplicantDocumentList = data.filter(ele => {
            return ele.axisltd_Loan_Application__c;
            
        });
        // let {categoryArr,categoryAdded } = this.handleCategorySubCategory(loanApplicantDocumentList);
        let categoryArr = this.handleCategorySubCategory(loanApplicantDocumentList);
        resp.push({
            recordId : this.recordId,
            categoryTab : categoryArr
            // categoryAdded
        });
        return resp;
    }

    handleLoanApplicantDocumentJsonFormation(data){
        let resp = [];
        let loanApplicantDocumentList = data.filter(ele => {
            return ele.axisltd_Loan_Applicant__c;
        });
        let applicantNameWiseDocumentList = new Map();
        for(let i of loanApplicantDocumentList){
            let documentList = [];
            if(applicantNameWiseDocumentList.has(i.axisltd_Loan_Applicant__c)){
                documentList = applicantNameWiseDocumentList.get(i.axisltd_Loan_Applicant__c);
            }
            documentList.push(i);
            applicantNameWiseDocumentList.set(i.axisltd_Loan_Applicant__c, documentList);
        }

        for(const [key, value] of applicantNameWiseDocumentList){
            let categoryArr = this.handleCategorySubCategory(value);
            resp.push({
                recordId : key, 
                categoryTab : categoryArr,
                recordName : value[0].axisltd_Loan_Applicant__r.Name
            });
        }
        return resp;
    }

    handleLoanAssetDocumentJsonFormation(data){
        let resp = [];
        let loanAssetDocumentList = data.filter(ele => {
            return ele.Loan_Application_Asset__c;
        });
        let loanAssetNameWise = new Map();
        for(let i of loanAssetDocumentList){
            let documentList = [];
            if(loanAssetNameWise.has(i.Loan_Application_Asset__c)){
                documentList = loanAssetNameWise.get(i.Loan_Application_Asset__c);
            }
            documentList.push(i);
            loanAssetNameWise.set(i.Loan_Application_Asset__c, documentList);
        }

        for(const [key, value] of loanAssetNameWise){
            let categoryArr = this.handleCategorySubCategory(value);
            resp.push({
                recordId : key, 
                categoryTab : categoryArr,
                recordName : value[0].Loan_Application_Asset__r.Name
            });
        }
        return resp;
    }

    

    handleError(errorObject){
        console.error('Error occurred ' + errorObject);
        const errorMessage = ''; //errorToStringSingleLine(errorObject);
        const event = new ShowToastEvent({
            title: 'Error',
            variant : 'error',
            message: errorMessage
        });
        this.dispatchEvent(event);
    }
    
    handleLookupUpdate(event){
        const documentCheckListSelected = event.detail.selectedRecord;
        this._searchFilterSelectedRecord = documentCheckListSelected;
        if(documentCheckListSelected){
            if(documentCheckListSelected.axisltd_Loan_Applicant__c){ 
                this.handleParentTabName('applicant');
            }
            else if(documentCheckListSelected.Loan_Application_Asset__c){
                this.handleParentTabName('collateral');
            }
            else{
                this.handleParentTabName('loan');
            }
            setTimeout(() => {
                this.childTabActive = documentCheckListSelected.axisltd_Document_Category__c;
                // setTimeout(() => {
                //     this.handleDocumentFilterChildMethodCall();
                // });
            });
        }
        this.handleDocumentFilterChildMethodCall();
    }

    handleStatusFilterChange(event){
        this._statusFilterSelectedValue = event.detail.selectedStatus;
        this.handleDocumentFilterChildMethodCall();
    }

    handleDocumentFilterChildMethodCall(type){
        let typeOfRefresh = type;
        if(typeOfRefresh === 'master_refresh'){
            refreshApex(this.wiredResponse);
        }
        else{
            for(let i of this.template.querySelectorAll('c-document-checklist-item-relatedlist')){
                i.handleFilterDocumentCheckList(this._searchFilterSelectedRecord?.Id, this._statusFilterSelectedValue, typeOfRefresh);
            }
        } 
        
    }

    handleParentChildTabManualChange(){
       this.parentTabActive = null;
       this.childTabActive = null;
    }

    // WC 17235 End

    /*@wire(getRecord , {recordId : '$recordId', fields : [LOAN_APPLICATION_STATUS_FIELD,LOAN_APPLICATION_RECORD_TYPE_ID,LOAN_APPLICATION_RECORD_TYPE_DEV_NAME,LOAN_APPLICATION_OWNERID]}) //Avinash
    setLoanApplicationDetails({data, error}){                                                                                                                                              //Avinash
        let loanApplication = {} ;                                                                                                                                                         //Avinash
        if(data){                                                                                                                                                                          //Avinash
            loanApplication['ownerId'] = getFieldValue(data,LOAN_APPLICATION_OWNERID) ;                                                                                                    //Avinash
            loanApplication['recordTypeId'] = data.recordTypeId ;                                                                                                                          //Avinash
            loanApplication['recordTypeDevName'] = data.recordTypeInfo.name ;                                                                                                              //Avinash
            loanApplication['status'] = getFieldValue(data,LOAN_APPLICATION_STATUS_FIELD) ;                                                                                                //Avinash
            this.loanApplication = loanApplication ;                                                                                                                                       //Avinash
        }else{                                                                                                                                                                             //Avinash
            console.log('----setLoanApplicationDetails error ' , error) ;                                                                                                                  //Avinash
        }                                                                                                                                                                                  //Avinash
    }*/                                                                                                                                                                                    //Avinash

    @wire(getAllRelatedDocsDetails, { recordId: '$recordId' })
    wiredAccounts(result) {
        this.wiredResponse = result;
        console.log('wired response '+JSON.stringify(this.wiredResponse));
        let { data, error } = result;
        console.log('wired response 2'+JSON.stringify(data));
        if (data) {
            this.responseWrapper = data;
            this.hideTotalSummary = false;
            this.headerButtonIcon = 'utility:dash';
            this.showSpinner = false;
            this.recordResponse = true;
            // WC 17235
            this._documentCheckListListWc = this.responseWrapper.dciList;
            this.handleInitiateWcInitialization();
            // WC 17235
        } else if (error) {

        }
    }

    hideTotalSummary = true;
    headerButtonIcon = 'utility:add';

    handleSummaryDisplay() {
        if (this.hideTotalSummary) {
            this.hideTotalSummary = false;
            this.headerButtonIcon = 'utility:dash';
        } else {
            this.hideTotalSummary = true;
            this.headerButtonIcon = 'utility:add';
        }
    }

    handleDataChange(event) {
        refreshApex(this.wiredResponse);
    }

    get hasApplicants() {
        return this.responseWrapper.loanApplicants.length > 0;
    }
// BB-64469 | Priyank | START 
    get hasGApplicants() {
        return this.responseWrapper?.guarantorloanApplicants?.length > 0;
    }
    // BB-64469 | Priyank | END 

    get hasLineItems() {
        return this.responseWrapper.lineItems.length > 0;
    }

    get hasInsurances() {
        return this.responseWrapper.insurancePolicies.length > 0;
    }

    get hasMitigants() {
        return this.responseWrapper.mitigants.length > 0;
    }

    //BB-2305 check invoice records exists
    get hasInvoices() {
        return this.responseWrapper.invoices.length > 0;
    }

    //BB-4614 - Vikrant - Sprint 16
    get hasProperties() {
        return this.responseWrapper?.properties?.length > 0;
    }

    latitude;
    longitude;
    errorMessage;

    connectedCallback() {
        /*Avinash Code start */
        getLoanApplicationDetails({recordId : this.recordId}).then(res =>{
            if(res != null && res != undefined){
                let loanApplication = {} ;
                loanApplication['recordId'] = res?.recordId ;
                loanApplication['ownerId'] = res?.ownerId ;
                loanApplication['recordTypeId'] = res?.recordTypeId ;
                loanApplication['recordTypeDevName'] = res?.recordTypeDevName ;
                loanApplication['status'] = res?.status ;
                this.loanApplication = loanApplication ;

                // WC 17235
                this.handleInitiateWcInitialization();
                // WC 17235
            }
        }).catch(err => {
           console.log('----err',err) ; 
        })
        /*Avinash Code End */
        //Get the Location Cordinates
        if (navigator.geolocation && !this.skipGeoLocation && !bypassLocationRestriction) {
            navigator.geolocation.getCurrentPosition(position => {
                this.navigatorResponse = true;
                // Get the Latitude and Longitude from Geolocation API
                this.latitude = position.coords.latitude;
                this.longitude = position.coords.longitude;
            },
                error => {
                    this.navigatorResponse = true;
                    switch (error.code) {
                        case error.PERMISSION_DENIED:
                            this.errorMessage = "Please enable location services.";
                            break;
                        case error.POSITION_UNAVAILABLE:
                            this.errorMessage = "Location information is unavailable.";
                            break;
                        case error.TIMEOUT:
                            this.errorMessage = "The request to get user location timed out.";
                            break;
                        case error.UNKNOWN_ERROR:
                            this.errorMessage = "An unknown error occurred.";
                            break;
                    }
                },
                { timeout: 5000, enableHighAccuracy: false, maximumAge: Infinity }
            );
        } else if(this.skipGeoLocation || bypassLocationRestriction){
            this.navigatorResponse = true;
        }
        else {
            this.navigatorResponse = true;
            this.errorMessage = "Geolocation is not supported by this browser.";
        }
    }

    get gotTheResponse() {
        return this.recordResponse && this.navigatorResponse;
    }    

    /*Avinash code start */
    get createDocument(){
        return this.checkAccess ;
    }

    //BB-28575 New Button will always be disabled for LoanApplication and LoanApplicant
    get createDocumentDisabled(){
        return false ;
    }

    get editDocument(){
        return this.checkAccess ;
    }

    get disableUpload(){
        console.log('disable upload getter',this.checkAccess)
        return this.checkAccess === false;
    }

    get checkAccess(){
        let accessGranted ;
        console.log('---this.loanApplication.recordTypeDevName',this.loanApplication.recordTypeDevName) ;
        console.log('---this.loanApplication.status',this.loanApplication.status) ;
        console.log('---this.loanApplication.ownerId',this.loanApplication.ownerId) ;
        console.log('---CURRENT_USER_ID',CURRENT_USER_ID) ;
        console.log('checking access',this.hasValue(this.loanApplication?.recordTypeDevName) && 
        this.hasValue(this.loanApplication?.status) &&
        this.hasValue(this.loanApplication?.ownerId) &&
        this.loanApplication.recordTypeDevName == 'axisltd_Nano' && 
        (this.loanApplication.status == 'Disbursement' || this.loanApplication.ownerId != CURRENT_USER_ID))
        if(this.hasValue(this.loanApplication?.recordTypeDevName) && 
        this.hasValue(this.loanApplication?.status) &&
        this.hasValue(this.loanApplication?.ownerId) &&
        this.loanApplication.recordTypeDevName == 'axisltd_Nano' && 
        (this.loanApplication.status == 'Disbursement' || this.loanApplication.ownerId != CURRENT_USER_ID)){
            accessGranted = false ;
        }else{
            accessGranted = true ;
        }
        console.log('---accessGranted',accessGranted) ;
        return accessGranted ;
    }

    hasValue(val){
        return (val != '' && val != null && val != undefined) ;
    }
    /*Avinash code end */
}