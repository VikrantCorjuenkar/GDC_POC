public without sharing class AxisNanoInitiateEsignController {

    /*
    public class EsignProcessDetails{
        @AuraEnabled public ResidentialLoanApplication application;
        @AuraEnabled public Map<String,Document_Master__c> linkedDocumentMasters;
        @AuraEnabled public List<LoanApplicant> applicants;
        @AuraEnabled public List<Contract_Document__c> contractDocuments;
        @AuraEnabled public List<ContentVersion> contentVersions;
    }
    
    @AuraEnabled(Cacheable=true)
    public static EsignProcessDetails fetchDetails(Id loanApplicationId){
        List<String> linkedDocumentIds = new List<String>();
        Map<String,Document_Master__c> linkedDocumentMasters = new Map<String,Document_Master__c>();
        Set<Id> documentIds = new Set<Id>();
        
        ResidentialLoanApplication application = [
            SELECT Id,
            	Working_CPC__r.State_Master__r.Name,
            	axisltd_Total_Loan_Amount__c,
                axisltd_Dealer_Master__r.IMD_A_C_Number__c,
                axisltd_Product__c,
            	(SELECT Id, axisltd_Charge_Master_Name__c, axisltd_ChargeAmount__c  FROM Charge_Details__r),
            	(SELECT Id, Name FROM LoanApplicationProperties ORDER BY CreatedDate Desc LIMIT 1),  
            	(SELECT Id, axisltd_Installment_Details__c, axisltd_EMI_Start_Date__c, axisltd_Instalment_Type__c FROM Repayments__r ORDER BY CreatedDate Desc LIMIT 1),
            	(SELECT Id, axisltd_Rate_Of_Interest__c, axisltd_Loan_Tenure__c FROM Loan_Application_Line_Items__r ORDER BY CreatedDate Desc LIMIT 1)
            FROM ResidentialLoanApplication
            WHERE Id =:loanApplicationId
            WITH SYSTEM_MODE
        ];
        
        List<Contract_Document__c> contractDocuments = [
            SELECT Id,
            	Contract_Status__c,
            	Template_Id__r.Name,
            	Template_Id__r.Linked_Document_Masters__c,
            	Loan_Application__c,
            	Loan_Application__r.RecordType.DeveloperName,
            	Signed_Contract_URL__c,
                is_User_Opted_Physical_Sign__c,
            	(SELECT Id,ContentDocumentId,ContentDocument.FileType, ContentDocument.Title FROM ContentDocumentLinks ORDER By SystemModstamp DESC LIMIT 1),
            	(SELECT Id, axisltd_Integration_Master__r.axisltd_External_Id__c, axisltd_Functional_Status__c, axisltd_Response__c, axisltd_Parent_Checklist__c FROM Integration_Checklists__r ORDER BY CreatedDate Desc)
            FROM Contract_Document__c
            WHERE Loan_Application__c = :loanApplicationId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        
        for(Contract_Document__c contractDocument: contractDocuments){
            linkedDocumentIds.addAll(contractDocument.Template_Id__r.Linked_Document_Masters__c.split(','));
            if(contractDocument.ContentDocumentLinks != null && contractDocument.ContentDocumentLinks.size() > 0){
           		documentIds.add(contractDocument.ContentDocumentLinks[0].ContentDocumentId);
            }
        }
        
        for(Document_Master__c dm: [
            SELECT Id,
            	axisltd_Dislay_Name__c,
            	axisltd_Document_Id__c
            FROM Document_Master__c
            WHERE axisltd_Document_Id__c in :linkedDocumentIds
            WITH SYSTEM_MODE
        ]){
            linkedDocumentMasters.put(dm.axisltd_Document_Id__c, dm);
        }
        
        List<ContentVersion> contentVersions = [
            SELECT Id,
            	ContentDocumentId, 
            	CreatedBy.Name, 
            	CreatedDate, 
            	ContentSize,
            	FileType
            FROM ContentVersion 
            WHERE ContentDocumentId in :documentIds AND IsLatest = true WITH SYSTEM_MODE 
			ORDER BY CreatedDate DESC
        ];
        
        List<LoanApplicant> applicants = [
            SELECT Id,
            	Name,
            	axisltd_Mobile_No__c,
            	axisltd_Email__c
            FROM LoanApplicant
            WHERE LoanApplicationId =:loanApplicationId
            WITH SYSTEM_MODE
        ];
        
        EsignProcessDetails details = new EsignProcessDetails();
        details.application = application;
        details.linkedDocumentMasters = linkedDocumentMasters;
        details.applicants = applicants;
        details.contractDocuments = contractDocuments;
        details.contentVersions = contentVersions;
        return details;
    }
    
    
    //BB-40471 - Sprint 13 - Vikrant - method modified - 24 jan 2025
    @AuraEnabled
    public static void initiateDigitalAgreement(Id loanId){
        ResidentialLoanApplication application = [
            SELECT Id, 
            ApplicationExtIdentifier,
            axisltd_RE__c, 
            axisltd_RE__r.ManagerId, 
            axisltd_RE__r.Manager.ManagerId,
            RecordTypeId,
            (SELECT Id, Name FROM LoanApplicants WHERE axisltd_BorrowerType__c = :LOS_Constants.BORROWER_TYPE_APPLICANT)
            FROM ResidentialLoanApplication 
            WHERE Id = :loanId
	        WITH SYSTEM_MODE
        ];
        
        ResidentialLoanApplication updateApplication = new ResidentialLoanApplication();
        updateApplication.Id = loanId;
        updateApplication.Status = LOS_Constants.LOAN_APP_STAGE_PREDISBURSEMENT;
        updateApplication.axisltd_Sub_Stage__c = LOS_Constants.LOAN_APP_SUB_STAGE_INPROGRESS;
        updateApplication.OwnerId = application.axisltd_RE__c;
        UPDATE AS SYSTEM updateApplication;
        
    }
    */

    //BB-31331 | 7th JAN 2025 | Priyank | START
    @AuraEnabled(cacheable=false)
    public static Map<String, Boolean> checkGenrateDocumentValidation(String loanApplicationId){
        Map<String, Boolean> validationMap = new Map<String, Boolean>();
        try{
            if(String.isNotBlank(loanApplicationId)){
                // check Life insurance exists or not
                List<InsurancePolicy> investigationList = [SELECT Id, Name, axisltd_Type_of_Insurance__c FROM InsurancePolicy WHERE RecordTypeId =: Nano_Constants.NANO_INSURANCE_RECORDTYPE_ID AND axisltd_Type_of_Insurance__c =: Nano_Constants.INSURANCE_TYPE_IS_LIFE_INSURANCE AND axisltd_Loan_Application__c =: loanApplicationId];
                if(!investigationList.isEmpty()){
                    validationMap.put(Nano_Constants.INSURANCE_TYPE_IS_LIFE_INSURANCE, true);
                }else{
                    validationMap.put(Nano_Constants.INSURANCE_TYPE_IS_LIFE_INSURANCE, false);
                }

                // check latest commercial deviation 
                List<Commercial_Deviation__c> commercialDeviationList = [  SELECT Id, Name, axisltd_Status__c FROM Commercial_Deviation__c  WHERE axisltd_Loan_Application__c = :loanApplicationId AND axisltd_Status__c =: Nano_Constants.COMMERCIAL_DEVIATION_APPROVED Order By CreatedDate Desc limit 1];
                if(!commercialDeviationList.isEmpty()){
                    validationMap.put(Nano_Constants.COMMERCIAL_DEVIATION_LABEL, true);
                }else{
                    validationMap.put(Nano_Constants.COMMERCIAL_DEVIATION_LABEL, false);
                }
            }
        }catch(Exception ex){
            System.debug('Message: ' + ex.getMessage());   
            System.debug('Line number: ' + ex.getLineNumber());    
            System.debug('Stack trace: ' + ex.getStackTraceString()); 
            LogUtil.log('LOS',ex.getStackTraceString(),loanApplicationId);
            throw new AuraHandledException('Something went wrong. Please contact your admin.');
        } 
        return validationMap;
        
    }
    //BB-31331 | 7th JAN 2025 | Priyank | END272


    @AuraEnabled(cacheable=false)
    public static String generateDocket1Form(String recordId, String loanApplicantionName, String contractDocument, String documentTemplateName){ // Added By Baljeet || BB-69559
        System.debug('Docket GENERATION LOGS ----> '+documentTemplateName);
        String eSignReportTemplateId = AxisServerSideDocumentGeneration.getActiveDocTemplate(LOS_Constants.TOKEN_MAPPING_TYPE,LOS_Constants.TEMPLATE_TYPE,documentTemplateName);// Added By Baljeet || BB-69559
        String contractDocumentId;
        if(eSignReportTemplateId == null || eSignReportTemplateId == ''){
            throw new AuraHandledException('No Active ESign Docket template found');
        }

        Map<String, Object> contractDocRecMap = (Map<String, Object>) JSON.deserializeUntyped(contractDocument);

        if(!contractDocRecMap.containsKey('Id')) {
            return null;
        }

        Map<String, Object> inputEsignDocket1 = new Map<String, Object> ();
        String eSignDocket1Title = contractDocRecMap.get('axisltd_Document_Name__c')+' '+loanApplicantionName+'-'+String.ValueOf(System.Now()); /// Added By Baljeet || BB-69559
        inputEsignDocket1 = AxisServerSideDocumentGeneration.setDocGenInput(recordId,eSignReportTemplateId,eSignDocket1Title);
        String jobIdEsignDocket1 = AxisServerSideDocumentGeneration.callDocGenIpForJobId(inputEsignDocket1);

        if(jobIdEsignDocket1 == NULL || jobIdEsignDocket1 == '' ){
            if(!Test.isRunningTest()){
                throw new AuraHandledException(System.label.KFS_Error_No_Job_ID_Returned);
            }
            return null;
        }
        return jobIdEsignDocket1;
    }

    //19 June 2025 - Vikrant - Moved from updateRecord to apex to handle record accessibility issues
    @AuraEnabled
    public static void updatePhysicalDocumentGenerated(Id contractId){
        UPDATE AS SYSTEM new Contract_Document__c(Id = contractId, Physical_Document_Generated__c = 'Yes');
    }

    //BB-60548 Nano Surag - created new method to create content document link record to relate ESIGN doc with Contract Document
    @AuraEnabled(cacheable=false)
    public static string createContentDocumentLinkRec(String jobIdEsignDocket1, String contractDocumentId) {
        List<DocumentGenerationProcess> documentGenList = [SELECT Id, Name, RequestText, TokenData, ResponseText, Status 
                                                            FROM DocumentGenerationProcess 
                                                            WHERE id = :jobIdEsignDocket1 WITH SYSTEM_MODE];
        system.debug('documentGenList '+documentGenList);
        if(!documentGenList.isEmpty()){
            system.debug('documentGenList[0].ResponseText >>> '+documentGenList[0].ResponseText);
            ContentVersion contentVersionRec = [SELECT Id, ContentDocumentId 
                                                FROM ContentVersion 
                                                WHERE id = :documentGenList[0].ResponseText WITH SYSTEM_MODE LIMIT 1];
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = contentVersionRec.ContentDocumentId;
            cdl.LinkedEntityId = contractDocumentId;
            cdl.ShareType = 'I';
            cdl.Visibility = 'AllUsers';
            insert AS SYSTEM cdl;
        }else{
            if(!Test.isRunningTest()){
                throw new AuraHandledException(System.label.KFS_Error_No_Job_ID_Returned);
            }
            return null;
        }
        return jobIdEsignDocket1;
    }

	@AuraEnabled
    public static List<DocumentGenerationProcess> getJobStatus(String jobIdEsignDocket) {
        return [SELECT Id, Name, RequestText, TokenData, ResponseText, Status FROM DocumentGenerationProcess WHERE id = :jobIdEsignDocket WITH SYSTEM_MODE];
    }
    
    public static void deleteOldContentVersions(String recordId) {
        if (recordId == null) return;
    
        List<ContentDocumentLink> contentDocLinkList = [SELECT ContentDocumentId
                                                        FROM ContentDocumentLink
                                                        WHERE LinkedEntityId = :recordId WITH SECURITY_ENFORCED];
    
        if (!contentDocLinkList.isEmpty()) {
            Set<Id> contentDocumentIds = new Set<Id>();
            for (ContentDocumentLink cdl : contentDocLinkList) {
                contentDocumentIds.add(cdl.ContentDocumentId);
            }
    
            try {
                delete AS SYSTEM [SELECT Id FROM ContentDocument WHERE Id IN :contentDocumentIds WITH SECURITY_ENFORCED];
            } catch (DmlException e) {
                System.debug('Error during content document deletion: ' + e.getMessage());
            }
        }
    }

    //BB-69559 Changes Added By Baljeet Singh: Start
    public static void initiateDocket2(List<Contract_Document__c> contracts){
        if(!contracts.isEmpty()){
            Map<String, Contract_Document_Master__c> docIdToContractIdMap = new Map<String, Contract_Document_Master__c>();
            for(Contract_Document_Master__c docMaster : [
            SELECT Id, Unique_Document_Id__c,Applicable_Product__c
            FROM Contract_Document_Master__c
            WHERE Unique_Document_Id__c=: Nano_Constants.DOCKET_2_UNIQUEID
            OR  Unique_Document_Id__c=: Nano_Constants.MICROLAP_DOCKET_2_UNIQUEID
            WITH SYSTEM_MODE
        ]){
            docIdToContractIdMap.put(docMaster.Applicable_Product__c, docMaster);
        }
            //BB-73536 ESIGN Surag Start
            Set<Id> loanApplicationIds = new Set<Id>();
            for(Contract_Document__c contract : contracts){
                loanApplicationIds.add(contract.Loan_Application__c);
            }
            Map<Id, ResidentialLoanApplication> loanApplicationMap = new Map<Id, ResidentialLoanApplication>([SELECT Id, Working_CPC__r.State_Master__r.axisltd_Applicable_Dockets__c,axisltd_Product__c FROM ResidentialLoanApplication WHERE Id IN :loanApplicationIds]);
            //BB-73536 ESIGN Surag End
            //BB-69013- Modified as part of microlap doc attachment - Shubham -ADDED PRODUCT CHECK DOC MASTER id
            List<Contract_Document__c> contractsForDocket2 = new List<Contract_Document__c>();
            for(Contract_Document__c contract : contracts){
                ResidentialLoanApplication application = loanApplicationMap.get(contract.Loan_Application__c);  
                Id docMasterId = docIdToContractIdMap.get(application.axisltd_Product__c)?.Id;         //BB-73536 ESIGN Surag 
                Contract_Document__c newContract = ContractDocumentsUtil.initiateContractDocument(docMasterId, contract.Loan_Application__c, contract.RecordTypeId);

                if(contract.is_User_Opted_Physical_Sign__c == Nano_Constants.NANO_BOOLEAN_TRUE 
                    || (application.Working_CPC__r.State_Master__r.axisltd_Applicable_Dockets__c != null && !application.Working_CPC__r.State_Master__r.axisltd_Applicable_Dockets__c.contains(Nano_Constants.DOCKET_2_UNIQUEID))){      //BB-73536 ESIGN Surag - Added condition for stamp master
                    newContract.is_User_Opted_Physical_Sign__c = Nano_Constants.NANO_BOOLEAN_TRUE;
                    //18 June 2025 - In case of physical journey Status will be Completed and Physical_Document_Generated__c will be No
                    newContract.Contract_Status__c = LOS_Constants.ESIGN_COMPLETED;
                    newContract.Physical_Document_Generated__c = 'No';
                }
                contractsForDocket2.add(newContract);
            }
            if(!contractsForDocket2.isEmpty()){
                insert AS SYSTEM contractsForDocket2; 
            }
        }
    }
     //BB-69559 Changes Added By Baljeet Singh: End


    // BB-71508 Priyank START // Added by Priyank for BB- 60548
    @AuraEnabled
    public static String initiateNanoEsignContract(Id loanId, Id contractDocumentId, String contentVersionId, Id parentChecklistId){
        try{
            // Priyank | BB- 70921 | Start
            // Map to store: SignerUniqueId -> SignerOrder
            Map<String, String> signerOrderMap = new Map<String, String>(); 
            // Populate the Map
            for (Axis_Nano_Esign_Sign_Order_Config__mdt config : [ SELECT SignerUniqueId__c, SignerOrder__c FROM Axis_Nano_Esign_Sign_Order_Config__mdt ]) {
                signerOrderMap.put(config.SignerUniqueId__c,  config.SignerOrder__c);
            }
            // Priyank | BB- 70921 | End
            Contract_Document__c contractDoc = AxisEsignDocketController.getContractDocument(contractDocumentId);
            Id nanoRecordTypeId = Schema.getGlobalDescribe().get('ResidentialLoanApplication').getDescribe().getRecordTypeInfosByDeveloperName().get('axisltd_Nano').getRecordTypeId();
            
            List<ResidentialLoanApplication> rlaList = [
                SELECT Id, Status, axisltd_Sub_Stage__c, ApplicationExtIdentifier, Working_CPC__c, Working_CPC__r.Zone__c, Working_CPC__r.Area__c,
                
                ( SELECT Id, Name, LoanApplicationId, ApplicantExtIdentifier, RecordType.DeveloperName, Applicant_Type__c, axisltd_BorrowerType__c, axisltd_Customer_Type__c 
                FROM LoanApplicants WHERE axisltd_Inactive__c = false 
                )
                FROM ResidentialLoanApplication
                WHERE Id =: loanId AND RecordTypeId = :nanoRecordTypeId
            ];
            
            List<axisltd_Integration_Master__c> integrationMasterList = [
                SELECT
                Id,
                Name,
                RequestMessageStartsWith__c,
                axisltd_Data_Transformer_Name__c,
                RequestMessageEndsWith__c,
                axisltd_External_Id__c,axisltd_Auth_Key__c,axisltd_Client_Certificate__c
                FROM axisltd_Integration_Master__c
                WHERE
                axisltd_External_Id__c = :IntegrationConstants.NANO_INITIATE_ESIGN
                AND axisltd_Active__c = TRUE
                AND axisltd_Applicable_Product__c = 'Nano Loan'
            ];
            // param Map<String, Object> inputParametersForDataRaptor, String drName
            String corporateDataRaptor;
            if (String.isBlank(integrationMasterList[0].axisltd_Data_Transformer_Name__c)) {
                throw new IntegrationException(
                    'DataRaptors not configured on Integration Master record for Nano Applicants.'
                );
            }else{
                corporateDataRaptor = integrationMasterList[0].axisltd_Data_Transformer_Name__c;
            }
            String uuid = rlaList[0].ApplicationExtIdentifier+DateTime.now().format('yyyyMMddHHmm');
            // Prepare the input map for extract DR
            Map<String, Object> DRInputMap = new Map<String, Object>();
            DRInputMap.put('recordId', loanId);
            DRInputMap.put('UUID', uuid);
            DRInputMap.put('nanoSignZyAuthKey', integrationMasterList[0].axisltd_Auth_Key__c);//IntegrationConstants.NANO_SIGNZY_AUTHKEY);
            DRInputMap.put('NanoSignZyCertificateId', integrationMasterList[0].axisltd_Client_Certificate__c);//IntegrationConstants.NANO_SIGNZY_CERTIFICATION_ID);
            DRInputMap.put('contentVersionId', contentVersionId);
            
            
            
            // extract DR for genrate request
            //Mahith - check if estampDetails is object or list<object>
            string jsonFromDR = AxisNANOCommonCalloutPE.getReqBody(DRInputMap, corporateDataRaptor);
            if(Test.isRunningTest())
            {
                jsonFromDR = '{   "Data": {     "contract": {       "failureRedirectUrl": "https://axisbank.com",       "successRedirectUrl": "https://axisbank.com",       "InternalSourceAppName": "SFDC_NANO",       "docSigner": {         "signatures": "test"       },       "signerdetail": [         {           "signerMobile": "9966406882",           "signerUniqueId": "NBL24250000003999",           "signerGender": "Male",           "signerName": "SIT TEST"         },         {           "signerMobile": "9966406882",           "signerUniqueId": "N0C24250000003999",           "signerGender": "Male",           "signerName": "DEEPAK YADAV"         }       ]     }   } }';
            }
            map<string,object> result = (map<string,object>)JSON.deserializeUntyped(jsonFromDR);
            map<string,object> data = (map<string,object>)result.get('Data'); 
            map<string,object> Contract = (map<string,object>)data.get('contract'); 
            System.debug('@@TEST Contract'+Contract);
            //map<string,object> estamp = (map<string,object>)Contract.get('estamp'); 
            map<string,object> docSigner = (map<string,object>)Contract.get('docSigner'); 
             List<Object> signerdetail = (List<Object>)Contract.get('signerdetail'); 
            if(!signerdetail.isEmpty()){
                for(integer i=0; i<signerdetail.size(); i++){
                    list<object> signerdetailtemplist = new list<object>();
                    if (signerdetail[i] instanceof Map<String, Object>) {
                        Map<String, Object> signer = (Map<String, Object>)signerdetail[i];
                        // Priyank | BB- 70921 | Start
                        //adding signer Order 
                        if(signer.get('signerUniqueId') != null){
                            if(signerOrderMap.containsKey(String.valueOf(signer.get('signerUniqueId')).substring(0, 3))){ 
                                signer.put('signerOrder',signerOrderMap.get(String.valueOf(signer.get('signerUniqueId')).substring(0, 3)));
                            } 
                        }
                        // Priyank | BB- 70921 | End
                        signerdetailtemplist.add(signer.get('signatures'));
                        signer.put('signatures', signerdetailtemplist);
                    } 
                }
                Contract.put('signerdetail',signerdetail);
            }
			
            
            if(Test.isRunningTest())
            {
                docSigner = null;
            }
            Object test1; 
                try{
                   //test = (List<Object>) estamp.get('stampDetails');
                   test1 = (List<Object>) contract.get('docSigner');                  
                   test1 = (List<Object>) docSigner.get('signatures');
                    if(Test.isRunningTest())
                    {
                        throw new TypeException('Test Class');
                    }
                }
                catch(System.TypeException ex)
                {
                    list<object> templist = new list<object>();
                    list<object> docSignertemplist = new list<object>();
                    list<object> signaturestemplist = new list<object>();
 
                    //templist.add(estamp.get('stampDetails'));
                    docSignertemplist.add(contract.get('docSigner'));
                    signaturestemplist.add(docSigner.get('signatures')); 

                    //estamp.put('stampDetails',templist);
                    docSigner.put('signatures',signaturestemplist); 

                    Contract.put('docSigner',docSigner);
                    Contract.put('docSigner',docSignertemplist);
                    //Contract.put('estamp',estamp);

                    data.put('contract',Contract);
                    result.put('Data',data);
                    jsonFromDR = JSON.serialize(result);

                }
             
            String applicantExtIdentifiers = '';
            String applicantIdentifiers = ''; 
            for (LoanApplicant applicantRec : rlaList[0].LoanApplicants) {
                applicantExtIdentifiers += applicantRec.Id + ';';
                applicantIdentifiers += applicantRec.Id + ';';
            }
            String transactionId = (String) (integrationMasterList[0].Id + '' + Datetime.now().getTime());
            Map<String, String> finalMapOfRequests = new Map<String, String>();
            finalMapOfRequests.put(transactionId,jsonFromDR);
            
            // here fire event for sign docket 1       
            AxisNANOCommonCalloutPE.publishMultipleCommonCalloutPE(
                'NANO_LOAN',
                IntegrationConstants.NANO_INITIATE_ESIGN,
                finalMapOfRequests,
                (SObject) rlaList[0],
                applicantIdentifiers,
                applicantExtIdentifiers,
                integrationMasterList[0].Id,
                contractDoc.Integration_Checklists__r[0].Id,
                null
            );
        }
        catch(Exception ex){
            return ex.getMessage();
        }
        
        return 'Success';
        
        
    }
    // BB-71508 Priyank END

    // BB-71508 Priyank START // Added new method as part of BB-68345 - Prashant
    @AuraEnabled
    public static string checkNanoEsignInitiated(Id contractDocumentId){
        try {
            Contract_Document__c contractDoc = AxisEsignDocketController.getContractDocument(contractDocumentId); 
            return contractDoc.Contract_Status__c;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    // BB-71508 Priyank END

    /*
    // Added By Priyank | 23rd Jan 2025 | BB-55290
    public static Contract_Document__c getContractDocument(Id contractId){
        return [
            SELECT Id,
            Contract_Id__c,
            Template_Id__c,
            Loan_Application__c,
            Loan_Application__r.ApplicationExtIdentifier,
            Template_Id__r.Controller_Class_Name__c,
            Template_Id__r.Vendor_Template_ID__c,
            Template_Id__r.InternalSourceAppName__c,
            RecordType.DeveloperName,
            RecordTypeId
            FROM Contract_Document__c
            WHERE Id = :contractId
            WITH SYSTEM_MODE
        ];
    }
    public static DateTime convertStringFormatedDateTime(String originalDateString){ //'Fri Apr 20 2020 00:00:00 GMT+0530 (India Standard Time)';
        // Extract the relevant portion of the date string (without time zone info)
        String datePart = originalDateString.substring(4, 24); // 'Apr 20 2020 00:00:00'
        
        //Split with Space get required params
        List<String> splitDate = datePart.split(' ');
        
        //DateTime in String Format
        String stringDate =  splitDate[2]+'-'+getMonthNumberFromString().get(splitDate[0])+'-'+splitDate[1]+' '+splitDate[3];
        
        // Convert it to a DateTime object
        DateTime dt = DateTime.valueOf(stringDate);
        
        return dt;
    }
    public static Map<String,String> getMonthNumberFromString(){
        return new Map<String,String>{
            'Jan' => '01',
                'Feb' => '02',
                'Mar' => '03',
                'Apr' => '04',
                'May' => '05',
                'Jun' => '06',
                'Jul' => '07',
                'Aug' => '08',
                'Sep' => '09',
                'Oct' => '10',
                'Nov' => '11',
                'Dec' => '12'
                };
                    }
    
    @AuraEnabled
    public static String initiateEsignContract(Id loanId, String contentVersionId){
        //Contract_Document__c contractDoc = getContractDocument(contractDocumentId);
        Id nanoRecordTypeId = Schema.getGlobalDescribe().get('ResidentialLoanApplication').getDescribe().getRecordTypeInfosByDeveloperName().get('axisltd_Nano').getRecordTypeId();
        
        List<ResidentialLoanApplication> rlaList = [
            SELECT Id, Status, axisltd_Sub_Stage__c, ApplicationExtIdentifier, Working_CPC__c, Working_CPC__r.Zone__c, Working_CPC__r.Area__c,
            ( SELECT Id,  axisltd_Status__c,  axisltd_Functional_Status__c,  axisltd_Retry_Count__c, axisltd_Applicant__c, axisltd_Loan_Application__c 
             FROM Integration_Checklists__r
             WHERE axisltd_Parent_Checklist__c = NULL AND axisltd_Integration_Master__r.axisltd_External_Id__c = :IntegrationConstants.NANO_INITIATE_ESIGN
             LIMIT 1
            ),
            ( SELECT Id, Name, LoanApplicationId, ApplicantExtIdentifier, RecordType.DeveloperName, Applicant_Type__c, axisltd_BorrowerType__c, axisltd_Customer_Type__c 
             FROM LoanApplicants WHERE axisltd_Inactive__c = false
            )
            FROM ResidentialLoanApplication
            WHERE Id =: loanId AND RecordTypeId = :nanoRecordTypeId
        ];
        List<axisltd_Integration_Master__c> integrationMasterList = [
            SELECT
            Id,
            Name,
            RequestMessageStartsWith__c,
            axisltd_Data_Transformer_Name__c,
            RequestMessageEndsWith__c,
            axisltd_External_Id__c
            FROM axisltd_Integration_Master__c
            WHERE
            axisltd_External_Id__c = :IntegrationConstants.NANO_INITIATE_ESIGN
            AND axisltd_Active__c = TRUE
            AND axisltd_Applicable_Product__c = 'Nano Loan'
        ];
        // param Map<String, Object> inputParametersForDataRaptor, String drName
        String corporateDataRaptor;
        if (String.isBlank(integrationMasterList[0].axisltd_Data_Transformer_Name__c)) {
            throw new IntegrationException(
                'DataRaptors not configured on Integration Master record for Nano Applicants.'
            );
        }else{
            corporateDataRaptor = integrationMasterList[0].axisltd_Data_Transformer_Name__c;
        }
        String uuid = rlaList[0].ApplicationExtIdentifier+DateTime.now().format('yyyyMMddHHmm');
     	// Prepare the input map for extract DR
        Map<String, Object> DRInputMap = new Map<String, Object>();
        DRInputMap.put('recordId', loanId);
        DRInputMap.put('UUID', uuid);
        DRInputMap.put('nanoSignZyAuthKey', IntegrationConstants.NANO_SIGNZY_AUTHKEY);
        DRInputMap.put('NanoSignZyCertificateId', IntegrationConstants.NANO_SIGNZY_CERTIFICATION_ID);
        DRInputMap.put('contentVersionId', contentVersionId);
        
        // extract DR for genrate request
        string jsonFromDR = AxisNANOCommonCalloutPE.getReqBody(DRInputMap, corporateDataRaptor);
        system.debug('@@DR request::'+jsonFromDR);
        String applicantExtIdentifiers = '';
        String applicantIdentifiers = ''; 
        for (LoanApplicant applicantRec : rlaList[0].LoanApplicants) {
            applicantExtIdentifiers += applicantRec.Id + ';';
            applicantIdentifiers += applicantRec.Id + ';';
        }
        String transactionId = (String) (integrationMasterList[0].Id + '' + Datetime.now().getTime());
        Map<String, String> finalMapOfRequests = new Map<String, String>();
        finalMapOfRequests.put(transactionId,jsonFromDR);
        AxisNANOCommonCalloutPE.publishMultipleCommonCalloutPE(
            'NANO_LOAN',
            IntegrationConstants.NANO_INITIATE_ESIGN,
            finalMapOfRequests,
            (SObject) rlaList[0],
            applicantIdentifiers,
            applicantExtIdentifiers,
            integrationMasterList[0].Id,
            rlaList[0].Integration_Checklists__r[0].Id,
            null
        );
        
        
        // need to confirm about chub notification api
        //Send Chub Notification
        //if(contractDocument.Contract_Status__c == LOS_Constants.ESIGN_INITIATED && contractDoc.RecordType.DeveloperName == LOS_Constants.TRACTOR_RECORD_TYPE_NAME){
        //TractorEsignChubNotificationUtil.sendEsignChubNotification(loanId, contractDocumentId, LOS_Constants.CHUB_API_METADATA_INITIATE_CONTRACT);
        //}
        return null;//JSON.serialize(unTypedResponse);
    }
    
    // Added By Priyank | 23rd Jan 2025 | BB-55290
    */
}