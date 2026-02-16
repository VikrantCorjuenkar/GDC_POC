/**
* @author        Vikrant Corjuenkar
* @date          16/09/2024
* @description   Invoked from Loan axisNanoKFSPage for KFS Form document
* Modification Log:
--------------------------------------------------------------------------------------------
Developer               Date            Description
--------------------------------------------------------------------------------------------
Vikrant Corjuenkar      16/09/2024      Original Version
*/

public class AxisNanoKFSController { 
    @AuraEnabled(cacheable=false)
    public static String generateKFSForm(String recordId, String loanApplicantionName){
        System.debug('KFS GENERATION LOGS');

        //BB-68097 - Vikrant - Sprint 19 - start
        String userLanguage = fetchApplicantsPreferredLanguage(recordId);

        String jsonString = System.Label.Nano_KFS_Enabled_Languages;
        Map<String, Object> jsonDataMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
        
        List<String> kfsEnabledLanguages = new List<String>();
        for(Object obj:(List<Object>) jsonDataMap.get('Languages')){
            kfsEnabledLanguages.add((String)obj);
        }

        String kfsTemplate;
        if(userLanguage != '' && kfsEnabledLanguages.contains(userLanguage.toUpperCase())){
            kfsTemplate = Nano_Constants.TEMPLATE_NAME_KFS_FORM+'_'+userLanguage.toUpperCase(); //Language specific KFS template
        }
        else{
            kfsTemplate = Nano_Constants.TEMPLATE_NAME_KFS_FORM; //Default KFS template in English
        }
        //BB-68097 - Vikrant - Sprint 19 - end

        String kfsFormTemplateId =AxisServerSideDocumentGeneration.getActiveDocTemplate(LOS_Constants.TOKEN_MAPPING_TYPE,LOS_Constants.TEMPLATE_TYPE,kfsTemplate);
        system.debug('kfsFormTemplateId >>> '+kfsFormTemplateId);
        if(kfsFormTemplateId == null || kfsFormTemplateId == ''){
            throw new AuraHandledException(System.label.KFS_Error_No_Active_Template_Found);
        }
        Map<String, Object> ipInputKFSForm = new Map<String, Object> ();
        String kfsFormTitle = Nano_Constants.TITLE_KFS_FORM+loanApplicantionName+'-'+String.ValueOf(System.Now());
        system.debug('kfsFormTitle >>> '+kfsFormTitle);
        ipInputKFSForm = AxisServerSideDocumentGeneration.setDocGenInput(recordId,kfsFormTemplateId,kfsFormTitle);
        system.debug('ipInputKFSForm >>> '+ipInputKFSForm);
        String jobIdkfsForm = AxisServerSideDocumentGeneration.callDocGenIpForJobId(ipInputKFSForm);
        system.debug('jobIdkfsForm >>> '+jobIdkfsForm);
        if(jobIdkfsForm == NULL || jobIdkfsForm == '' ){
            if(!Test.isRunningTest()){
                throw new AuraHandledException(System.label.KFS_Error_No_Job_ID_Returned);
            }
            return null;
        }
        else{
           // updateAppFormReqCheckbox(recordId);
            update as system new ResidentialLoanApplication(Id = recordId, axisltd_Regenerate_KFS__c = false);
            return jobIdkfsForm;
        }
    }

    //Added by Sumit | BB-42608 | 22/01/2025 | Start
    @AuraEnabled(cacheable=false)
    public static String generateESignApplicationForm(String recordId, String loanApplicantionName){
                        ResidentialLoanApplication loanApp = [SELECT Id, Status,axisltd_Sub_Stage__c from ResidentialLoanApplication WHERE Id =:recordId WITH SYSTEM_MODE LIMIT 1];
                    if(loanApp.axisltd_Sub_Stage__c == 'Pending Review'){
                        throw new AuraHandledException(System.label.KFS_Error_ApplicationGeneration_If_Pending_Review_Substage);
                    }
        String applFormTemplateId =AxisServerSideDocumentGeneration.getActiveDocTemplate(LOS_Constants.TOKEN_MAPPING_TYPE,LOS_Constants.TEMPLATE_TYPE,Nano_Constants.TEMPLATE_NAME_ESIGN_DOCKET1_DOCUMENT);
        if(applFormTemplateId == null || applFormTemplateId == ''){
            throw new AuraHandledException(System.label.KFS_Error_No_Active_Template_Found);
        }
        Map<String, Object> ipInputApplForm = new Map<String, Object> ();
        String applFormTitle = Nano_Constants.TITLE_APPL_FORM+loanApplicantionName+'-'+String.ValueOf(System.Now());
        ipInputApplForm = AxisServerSideDocumentGeneration.setDocGenInput(recordId,applFormTemplateId,applFormTitle);
        String jobIdApplForm = AxisServerSideDocumentGeneration.callDocGenIpForJobId(ipInputApplForm);
        if(jobIdApplForm == NULL || jobIdApplForm == '' ){
            if(!Test.isRunningTest()){
                throw new AuraHandledException(System.label.KFS_Error_No_Job_ID_Returned);
            }
            return null;
        }
        else{
            return jobIdApplForm;
        }
    }

    @AuraEnabled(cacheable=false)
    public static String uploadApplFormToDocManager(String loanAppId, String contentDocId){
        String result = 'Failure';
        try {
            if(String.isNotBlank(loanAppId) && String.isNotBlank(contentDocId)) {
                String docChecklistId = [SELECT Id, Name from Document_Checklist__c where axisltd_Loan_Application__c =: loanAppId
                                        AND Name =: Nano_Constants.APPLICATION_FORM_DOCUMENT_MASTER_NAME
                                        LIMIT 1].Id;
                if(String.isNotBlank(docChecklistId)) {
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.contentDocumentId = contentDocId;
                    cdl.LinkedEntityId = docChecklistId;
                    cdl.Visibility = 'AllUsers';
                    insert cdl;
                    result = 'Success';
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static List<String> getApplFormValidations(Id loanAppId) {
        List<String> validationsApplForm = new List<String>();
        try {
            List<ResidentialLoanApplication> loanApp = [SELECT Id, Status,axisltd_Sub_Stage__c from ResidentialLoanApplication WHERE Id =:loanAppId WITH SYSTEM_MODE LIMIT 1];
            if(loanApp[0].Status != Nano_Constants.LOAN_APP_STAGE_CUSTOMER_PROFILING && !(loanApp[0].Status == Nano_Constants.LOAN_APP_STAGE_PREDISBURSEMENT &&  loanApp[0].axisltd_Sub_Stage__c == Nano_Constants.LOAN_APP_SUB_STAGE_PENDING_REVIEW)) {
                validationsApplForm.add(System.Label.Application_Form_Validation_Message);
            }
            return validationsApplForm;
        } catch (Exception ex) {
            system.debug('Error is : '+ex.getMessage() + ' : ' +ex.getLineNumber()+' '+ex.getStackTraceString());
            throw new AuraHandledException(ex.getMessage());
        }
    }
    //Added by Sumit | BB-42608 | 22/01/2025 | End

    @AuraEnabled(cacheable=false)
    public static List<ContentVersionWrapper> getContentDocuments(Id recordId, String fileTitle) {
        try{
            String titleFilter = fileTitle+'%';
            List<Id> contentDocumentLinkIds = new List<Id>();
            List<ContentVersionWrapper> contentVersionList = new List<ContentVersionWrapper>();
            List<ContentDocumentLink> contentDocumentLink = [SELECT Id, ContentDocumentId, ContentDocument.Title, ContentDocument.CreatedDate
                                                             FROM ContentDocumentLink 
                                                             WHERE LinkedEntityId = :recordId 
                                                             AND ContentDocument.Title LIKE :titleFilter  
                                                             WITH SYSTEM_MODE ORDER By ContentDocument.CreatedDate DESC  LIMIT  1
                                                            ];
            
            if(contentDocumentLink.size()>0){
                List<ContentVersion> cVersions = [SELECT Id, Title,ContentDocumentId,FileType,ContentDocument.Title,ContentDocument.createdDate, CreatedDate
                                                  FROM ContentVersion 
                                                  WHERE ContentDocumentId = :contentDocumentLink[0].ContentDocumentId
                                                  WITH SYSTEM_MODE
                                                  ORDER BY CreatedDate DESC LIMIT 1
                                                 ];
                
                for(ContentVersion c: cVersions)
                {
                    ContentVersionWrapper cw = new ContentVersionWrapper();
                    cw.docVersionId = c.Id;
                    cw.contentDocumentId = c.ContentDocumentId;
                    cw.docTitle = c.ContentDocument.Title;
                    //cw.docTitle = c.Title;
                    cw.createdDate = c.createdDate;
                    //cw.createdDate = c.ContentDocument.createdDate;
                    cw.fileType = c.FileType;
                    contentVersionList.add(cw);
                }
            }
            return contentVersionList;
            
        }
        catch(DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<String> getKSFValidations(Id loanAppId) {

        List<String> validationsKSF = new List<String>();
        Boolean cdApproved = false;
        try {
            List<ResidentialLoanApplication> loanApp = [Select Id, Status from ResidentialLoanApplication where Id =:loanAppId WITH SYSTEM_MODE limit 1];
            if(loanApp[0].Status != Nano_Constants.LOAN_APP_STAGE_PREDISBURSEMENT) {
                validationsKSF.add(System.Label.KFS_Validation_Stage_Not_PreDisb);
            }
            else {

                //1 Check if Insurance not captured and no approved commercial deviation for insurance waiver
                //2 Proposed rate is less than rack rate and no commercial deviation is approved!
                //3 Commercial deviations raised but not approved. if no com dev raised at all then error

                List<InsurancePolicy> lifeInsurancelist = [Select Id, axisltd_Type_of_Insurance__c from InsurancePolicy where axisltd_Loan_Application__c =:loanAppId and axisltd_Type_of_Insurance__c =:Nano_Constants.KSF_VALIDATION_LIFE_INSURANCE_TYPE WITH SYSTEM_MODE];
                List<Loan_Apllication_Line_Item__c> loanAppLineItem = [Select Id, axisltd_Proposed_ROI__c, ROI_RAAC_Rate__c from Loan_Apllication_Line_Item__c where axisltd_LoanApplicationId__c = :loanAppId WITH SYSTEM_MODE limit 1];

                List<Commercial_Deviation__c> parentCommDeviationList = [Select id, axisltd_Status__c, (select id, axisltd_Status__c, axisltd_Approved_ROI__c,  LI_Insurance_waiver__c from Commercial_Deviations__r) from Commercial_Deviation__c  where axisltd_Loan_Application__c = :loanAppId and axisltd_Commercial_Deviation__c = null and axisltd_Status__c IN ('Approved', 'In Progress')  WITH SYSTEM_MODE ORDER BY createdDate desc LIMIT 1];

                Boolean insuranceWaiverApproved = false;
                Boolean commDevApproved = false;
                if(!parentCommDeviationList.isEmpty() && parentCommDeviationList[0].axisltd_Status__c == Nano_Constants.LOAN_APP_APPROVED){
                    commDevApproved = true;
                    insuranceWaiverApproved = parentCommDeviationList[0].Commercial_Deviations__r[0].LI_Insurance_waiver__c;

                }

                if(lifeInsurancelist.isEmpty() && !insuranceWaiverApproved) {
                    validationsKSF.add(System.Label.KFS_Validation_Insurance_Not_Present);
                }
                if(!loanAppLineItem.isEmpty()) {
                    if(loanAppLineItem[0].axisltd_Proposed_ROI__c < loanAppLineItem[0].ROI_RAAC_Rate__c && !commDevApproved) {
                        validationsKSF.add(System.Label.KFS_Validation_Proposed_Rate_Less);
                    }
                }
                if(!parentCommDeviationList.isEmpty()) {

                    if(parentCommDeviationList[0].axisltd_Status__c != Nano_Constants.LOAN_APP_APPROVED){
                        validationsKSF.add(System.Label.KFS_Validation_ComDev_Not_Approved);
                    }
                }

            }
            return validationsKSF;
        } catch (Exception ex) {
            system.debug('Error is : '+ex.getMessage() + ' : ' +ex.getLineNumber()+' '+ex.getStackTraceString());
            throw new AuraHandledException(ex.getMessage());
        }
    }

    //BB-68097 - Vikrant - Sprint 19 - start
    public static string fetchApplicantsPreferredLanguage(Id loanAppId){
        try {
            String language = '';
            LoanApplicant applicant = [SELECT Id, toLabel(PreferredLanguage) FROM LoanApplicant
                                        WHERE loanApplicationId =:loanAppId AND RecordType.developerName =: Nano_Constants.APPLICANT_RECORDTYPE_PRIMARY_APP 
                                        WITH SYSTEM_MODE
                                        LIMIT 1];
            
            if(applicant.PreferredLanguage != NULL){
                language = applicant.PreferredLanguage;
            }
            return language;
            
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static List<DocumentGenerationProcess> getJobStatus(String jobIdEsignDocket) {
        return [SELECT Id, Name, RequestText, TokenData, ResponseText, Status FROM DocumentGenerationProcess WHERE id = :jobIdEsignDocket WITH SYSTEM_MODE];
    }
    //BB-68097 - Vikrant - Sprint 19 - end

    public class ContentVersionWrapper
    {
        @AuraEnabled
        public String docVersionId;
        @AuraEnabled
        public String contentDocumentId;
        @AuraEnabled
        public String docTitle;
        @AuraEnabled
        public DateTime createdDate;
        @AuraEnabled
        public String fileType;
        
    }
}