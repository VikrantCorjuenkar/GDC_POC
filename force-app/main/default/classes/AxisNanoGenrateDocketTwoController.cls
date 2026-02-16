public class AxisNanoGenrateDocketTwoController {
 @AuraEnabled(cacheable= true)   
    public static Boolean throwValidation(String loanId){
        ResidentialLoanApplication rla = [Select Id,Status,axisltd_Sub_Stage__c 
                                          From ResidentialLoanApplication
                                          Where Id =:loanId];
        if(rla.Status==Nano_Constants.LOAN_APP_STAGE_PREDISBURSEMENT && (rla.axisltd_Sub_Stage__c == Nano_Constants.LOAN_APP_SUB_STAGE_DOCKET_AND_ESIGN || rla.axisltd_Sub_Stage__c == Nano_Constants.LOAN_APP_SUB_STAGE_PENDING_REVIEW)){
            return false;
        }
        else{
            return true;
        }
        
    }
    @AuraEnabled(cacheable=true)
    public static String getUserProfileName() {
        return [
            SELECT Profile.Name 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
        ].Profile.Name;
    }

    @AuraEnabled(cacheable=false)
    public static String generateDocketForm(String recordId, String loanApplicantionName){

        String kfsFormTemplateId =AxisServerSideDocumentGeneration.getActiveDocTemplate(LOS_Constants.TOKEN_MAPPING_TYPE,LOS_Constants.TEMPLATE_TYPE,Nano_Constants.TEMPLATE_NAME_DOCKET_2);

        if(kfsFormTemplateId == null || kfsFormTemplateId == ''){
            throw new AuraHandledException(System.label.KFS_Error_No_Active_Template_Found);
        }
        Map<String, Object> ipInputKFSForm = new Map<String, Object> ();
        String kfsFormTitle = 'Docket2_'+loanApplicantionName+'-'+String.ValueOf(System.Now());

        ipInputKFSForm = AxisServerSideDocumentGeneration.setDocGenInput(recordId,kfsFormTemplateId,kfsFormTitle);

        String jobIdkfsForm = AxisServerSideDocumentGeneration.callDocGenIpForJobId(ipInputKFSForm);

        if(jobIdkfsForm == NULL || jobIdkfsForm == '' ){
            if(!Test.isRunningTest()){
                throw new AuraHandledException(System.label.KFS_Error_No_Job_ID_Returned);
            }
            return null;
        }
        else{
            Id loandetailRecId = [Select Loan_Details__c 
            From ResidentialLoanApplication
            Where Id =:recordId]?.Loan_Details__c;

            Loan_detail__c obj = new Loan_detail__c();
            obj.id = loandetailRecId;
            obj.axisltd_DocketReverse__c = false;
            update as system obj;

            return jobIdkfsForm;
        }
    }

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