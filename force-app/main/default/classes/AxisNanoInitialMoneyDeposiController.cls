/**
* @File Name : AxisNanoInitialMoneyDeposiController.cls
* @Author : Vikrant, Surag
**/

public without sharing class AxisNanoInitialMoneyDeposiController {
    
    //BB-61727 - Vikrant - start
    @AuraEnabled
    public static ResponseWrapper fetchIMDdata(String recordId){

        ResponseWrapper rw = new ResponseWrapper();
        rw.isPaymentCompleted = false;
        
        //BB-67081 || Anjani || Start
        Boolean isNanoCAUWOpsUser = false;
        List<String> lstNanoCAUWOpsProfiles = new List<String>{'Axis_Underwriter', 'Axis_CA', 'Axis Ops Checker User','Axis Ops Maker User','Axis Ops Manager Plus'};
        List<Profile> currentUserProfileList = [SELECT Id, Name FROM Profile WHERE Id = :UserInfo.getProfileId()];
        if(currentUserProfileList?.size()>0){
            rw.isNanoCAUWOpsUser = isNanoCAUWOpsUser = lstNanoCAUWOpsProfiles.contains(currentUserProfileList[0]?.Name);
        }
        //BB-67081 || Anjani || End
        
        
        ResidentialLoanApplication loanApplication = [SELECT id, Status, axisltd_Sub_Stage__c, Product__c, axisltd_Scheme__r.Name,axisltd_Scheme__c, OwnerId,
                                                      (SELECT id, axisltd_Loan_Application__c, axisltd_Status__c, axisltd_Transaction_Id__c, axisltd_Amount__c FROM Payment__r WHERE axisltd_Charge_Details__r.axisltd_Charge_Master_Name__c =: Nano_Constants.CHARGE_MASTER_RATE_BASE ORDER BY createddate desc),
													  (SELECT id FROM Charge_Details__r WHERE axisltd_Charge_Master_Name__c =: Nano_Constants.CHARGE_MASTER_RATE_BASE ORDER BY createddate desc),
                                                      (SELECT Id, Name, Approver__c,Approver__r.Name,axisltd_Status__c,axisltd_Type__c,CreatedDate,axisltd_Submitter_Remarks__c,LastModifiedDate,axisltd_Loan_Application__c,axisltd_Approver_Remarks__c FROM Approval_Requests__r WHERE axisltd_Type__c =: Nano_Constants.IMD_WAIVER_TYPE ORDER BY CreatedDate desc) //BB-64908 - Surag
                                                      FROM ResidentialLoanApplication
                                                      WHERE Id =: recordId
                                                      with SYSTEM_MODE];
        
        if(loanApplication != null){            
            if(loanApplication.Product__c != Nano_Constants.NANO_LOAN_PRODUCT_MICRO_LAP){
                rw.errorMessage = 'IMD collection not applicable for the selected Scheme';
                return rw;
            }

			if(loanApplication.Payment__r.size() > 0 && loanApplication.Payment__r[0].axisltd_Status__c == Nano_Constants.PAYMENT_COMPLETE){
                rw.errorMessage = '';
                rw.isPaymentCompleted = true;
                rw.payments = loanApplication?.Payment__r;
                return rw;
            }

            if(loanApplication.axisltd_Sub_Stage__c != Nano_Constants.LOAN_APP_SUB_STAGE_SCREENINGINPROGRESS 
               && !isNanoCAUWOpsUser){ //BB-67081 Start || Anjani || Added isNanoCAUWOpsUser check
                   rw.errorMessage = 'Loan Application is currently not in Customer Profiling - Screening In Progress stage';
                   return rw;
            }
            
            List<Base_Rate_Master__c> baseRateMaster = [SELECT Id, axisltd_Minimum_Amount__c, axisltd_Maximum_Amount__c
                                                              FROM Base_Rate_Master__c
                                                              WHERE axisltd_Scheme__c =: loanApplication.axisltd_Scheme__c AND axisltd_Rate_Type__c = 'Application Fees - IMD'
                                                              WITH SYSTEM_MODE
                                                              LIMIT 1];
            
            if(!baseRateMaster.isEmpty()){
                rw.imdAmount = baseRateMaster[0].axisltd_Minimum_Amount__c;
                rw.errorMessage = '';
                rw.payments = loanApplication?.Payment__r;
                rw.approvalRequests = loanApplication?.Approval_Requests__r;
				rw.chargeDetail = loanApplication?.Charge_Details__r.size() > 0 ? loanApplication?.Charge_Details__r[0] : null;
                rw.scheme = loanApplication.axisltd_Scheme__c;
                rw.isOwner = UserInfo.getUserId() == loanApplication.OwnerId;

				Axis_Nano_Configuration__mdt nanoConfig = Axis_Nano_Configuration__mdt.getInstance('Nano_Initial_Money_Deposit_Timeout');
				rw.countdownTime = nanoConfig!= null ? Integer.valueOf(nanoConfig.Value__c) : 300; //defaulting to 5 minutes if no config found
            }
            else{
                rw.errorMessage = 'No IMD Rate Matrix available for the selected Scheme';
                return rw;
            }
            
        }
        
        return rw;
    }
    //BB-61727 - Vikrant - end


    //BB-61727 - Vikrant - start
    @AuraEnabled
	public static axisltd_Payment__c initiatePayment(String LoanAppId, String chargeId, Decimal Amount, String transactionId){
		try{
			axisltd_Payment__c payment =  new axisltd_Payment__c(
				axisltd_Loan_Application__c = LoanAppId,
				axisltd_Charge_Details__c = chargeId,
				axisltd_Status__c = Nano_Constants.PAYMENT_INITIATED,
				axisltd_Amount__c = Amount,
				axisltd_Initiated_On__c = System.now(),
                axisltd_Transaction_Id__c = transactionId
			);
			insert payment;
			return payment;

		} catch (Exception e) {
			LogUtil.log('LOS',e,null);
            return null;
			//throw new AuraHandledException('Unable to Generate QR, please retry by clicking on Collect Payment');
		}

	}

	@AuraEnabled
	public static axisltd_Payment__c getPaymentStatus(String paymentId){
		List<axisltd_Payment__c> payments = [SELECT Id, axisltd_Status__c, axisltd_Loan_Application__c, axisltd_Transaction_Id__c, axisltd_Amount__c FROM axisltd_Payment__c WHERE Id = :paymentId];

		if(!payments.isEmpty()){
			return payments[0];
		}
		else{
			return null;
		}
	}

	@AuraEnabled
	public static axisltd_Payment__c updatePaymentStatus(axisltd_Payment__c payment, String Status){
		//axisltd_Payment__c payment =  new axisltd_Payment__c(Id = paymentId, axisltd_Status__c = Status);
        payment.axisltd_Status__c = Status;
		update payment;
		return payment;
	}

    /*
	@AuraEnabled
	public static axisltd_Payment__c fetchPaymentStatus(axisltd_Payment__c payment, String Status){
		axisltd_Payment__c payment =  new axisltd_Payment__c(Id = paymentId, axisltd_Status__c = 'Failed');
		update payment;
		return payment;
	}*/
    //BB-61727 - Vikrant - end

    //BB-64910 | Priyank | START
    @AuraEnabled
	public static List<PaymentWrapper> fetchPaymetTrailList(String loanAppId){
        List<PaymentWrapper> result = new List<PaymentWrapper>();

         for (axisltd_Payment__c p : [SELECT Id, Name, axisltd_Status__c, CreatedDate, LastModifiedDate,axisltd_Transaction_Id__c FROM axisltd_Payment__c WHERE axisltd_Loan_Application__c = :loanAppId Order By CreatedDate Desc]) {
            PaymentWrapper wrap = new PaymentWrapper();
            wrap.id = p.Id;
            wrap.name = p.Name;
            wrap.createdDate = p.CreatedDate.format('dd/MM/yyyy, HH:mm a');
            wrap.modifiedDate = p.LastModifiedDate.format('dd/MM/yyyy, HH:mm a');
            //wrap.phone = p.Phone__c;
            wrap.status = p.axisltd_Status__c;
            wrap.gatewayResponse = p.axisltd_Status__c;
            wrap.transactionId = p.axisltd_Transaction_Id__c;
            result.add( wrap);
        }

		if(!result.isEmpty()){
			return result;
		}
		else{
			return null;
		}
	}
    //BB-64910 | Priyank | END

    //BB-64908 - Surag - start
    @AuraEnabled
    public static Map<String, Object> createApprovalRequests(String remarks,String loanApplicationId,String scheme,String approvalId) {
        Map<String, Object> result = new Map<String, Object>();
        Profile salesManagerProfile = [SELECT Id FROM Profile WHERE Name = 'Axis Sales Manager' LIMIT 1];
        List<User> salesManagers = [SELECT Id FROM User WHERE ProfileId = :salesManagerProfile.Id];
        Approval_Authority__c ApprovalAuthority = [SELECT Id,axisltd_Scheme__c,axisltd_Level_Of_Approval__c,axisltd_User__c FROM Approval_Authority__c WHERE axisltd_Scheme__c = :scheme AND axisltd_User__c IN :salesManagers AND axisltd_Level_Of_Approval__c = : Nano_Constants.IMD_LEVEL_OF_APPROVAL];
        try {
            axisltd_Approval_Request__c approvalRequest = new axisltd_Approval_Request__c();
            if (String.isNotBlank(approvalId)) {
                approvalRequest.Id = approvalId; // Set the Id for update scenario
            }
            
            // Common field assignments
            approvalRequest.axisltd_Status__c = String.isNotBlank(approvalId) ? Nano_Constants.IMD_RECALL_STATUS : Nano_Constants.IMD_SUBMITTED_STATUS;
            approvalRequest.axisltd_Submitter_Remarks__c = remarks;
            
            if (String.isBlank(approvalId)) { // New record scenario
                approvalRequest.axisltd_Type__c = Nano_Constants.IMD_WAIVER_TYPE;
                approvalRequest.axisltd_Submitter__c = UserInfo.getUserId();
                approvalRequest.axisltd_Loan_Application__c = loanApplicationId;
                approvalRequest.Approver__c = (ApprovalAuthority != null) ? ApprovalAuthority.axisltd_User__c : '';
                //approvalRequest.OwnerId = (ApprovalAuthority != null) ? ApprovalAuthority.axisltd_User__c : UserInfo.getUserId();


                // code by meghana
                // Check if approver already has share
                List<ResidentialLoanApplicationShare> existingShare = [
                    SELECT Id 
                    FROM ResidentialLoanApplicationShare
                    WHERE ParentId = :loanApplicationId
                    AND UserOrGroupId = :approvalRequest.Approver__c
                    LIMIT 1
                ];
                
                if (existingShare.isEmpty()) {
                    // Only then share
                    ResidentialLoanApplicationShare shareRec = new ResidentialLoanApplicationShare();
                    shareRec.ParentId = loanApplicationId;
                    shareRec.UserOrGroupId = approvalRequest.Approver__c;     // ApproverId
                    shareRec.AccessLevel = 'Read';     // or 'Edit'
                    shareRec.RowCause = 'Manual';      
                    insert shareRec;
                }
            }
            
            // Perform Upsert
            upsert approvalRequest;
            
            if(String.isNotBlank(approvalId)){
                List<ProcessInstanceWorkitem> Pval = [SELECT Id FROM ProcessInstanceWorkItem WHERE ProcessInstance.TargetObjectId = :approvalId AND ProcessInstance.Status = 'Pending']; 

            if (!Pval.isEmpty()) {
                // To remove an existing pending approval request, use Approval.ProcessWorkitemRequest
                Approval.ProcessWorkitemRequest req2 = new Approval.ProcessWorkitemRequest();
                req2.setComments('Removing pending approval.');
                req2.setAction('Removed');
                req2.setWorkItemId(Pval[0].Id);
                Approval.process(req2);
                result.put('message', 'Waiver Request recalled successfully!');
            }
            }else{
                Approval.ProcessSubmitRequest req1 = 
                new Approval.ProcessSubmitRequest();
                req1.setComments(remarks);
                req1.setObjectId(approvalRequest.Id);
                req1.setSubmitterId(approvalRequest.axisltd_Submitter__c); 
                req1.setProcessDefinitionNameOrId('Approval_Request_Flow');
                req1.setSkipEntryCriteria(true);
                Approval.ProcessResult result1 = Approval.process(req1);
                // Approve the submitted request
                // First, get the ID of the newly created item
                List<Id> newWorkItemIds = result1.getNewWorkitemIds();
                result.put('message', 'Waiver Request is successful!');
            }
            // If successful, return result
            //result.put('message', String.isNotBlank(approvalId) ? null :'Waiver Request is successful!');
            result.put('record', approvalRequest);
            return result;
        } catch (DmlException e) {
            System.debug('DML Error creating approval request: ' + e.getMessage());
            throw new DmlException('Failed to create approval request: ' + e.getDmlMessage(0));
        }
    }
    //BB-64908 - Surag - end

    public static void createChecklistRecordsInboundAPIforLA(
        DateTime requestInitiatedDateTime,
        String requestString,
        String responseString,
        Integer responseStatusCode,
        String loanApplicationId,
        String ExternalId
    ){
        
        List<axisltd_Integration_Checklist__c> parentChecklist = new List<axisltd_Integration_Checklist__c>();
        parentChecklist = 
            [SELECT Id,axisltd_Status__c,axisltd_Functional_Status__c,axisltd_Retry_Count__c,axisltd_Integration_Master__c,CreatedDate, RecordTypeId,
             axisltd_Integration_Master__r.axisltd_Max_number_of_retries_allowed__c,axisltd_Lead__c,axisltd_Applicant__c,
             axisltd_Loan_Application__c
             FROM axisltd_Integration_Checklist__c 
             WHERE axisltd_Parent_Checklist__c = NULL
             AND axisltd_Integration_Master__r.axisltd_External_Id__c=:ExternalId
             AND axisltd_Integration_Master__r.axisltd_Active__c = true
			 AND axisltd_Loan_Application__c = :loanApplicationId
             Order by CreatedDate DESC
             LIMIT 1];


        if(!parentChecklist.IsEmpty()){
            List<axisltd_Integration_Checklist__c> checklistToUpdate = new List<axisltd_Integration_Checklist__c>();
            List<ContentVersion> cvList = new List<ContentVersion>();
            axisltd_Integration_Checklist__c childCheckList = new axisltd_Integration_Checklist__c();

            childCheckList.axisltd_Parent_Checklist__c = parentChecklist[0].Id;
            childCheckList.RecordTypeId = parentChecklist[0].RecordTypeId;
            childCheckList.axisltd_Is_Auto__c = true;
            childCheckList.axisltd_Functional_Status__c = 
                responseStatusCode==IntegrationConstants.RESPONSE_SUCCESS_STATUS_CODE?
                IntegrationConstants.CHECKLIST_COMPLETED_FUNCTIONAL_STATUS:
                IntegrationConstants.CHECKLIST_FAILED_FUNCTIONAL_STATUS;

            childCheckList.axisltd_Status__c = 
                responseStatusCode==IntegrationConstants.RESPONSE_SUCCESS_STATUS_CODE?
                IntegrationConstants.CHECKLIST_SUCCESS_STATUS:
                IntegrationConstants.CHECKLIST_FAILED_STATUS;

            childCheckList.axisltd_Integration_Master__c =  parentChecklist[0].axisltd_Integration_Master__c;
            childCheckList.axisltd_Loan_Application__c = parentChecklist[0].axisltd_Loan_Application__c;

            childCheckList.axisltd_Request__c = requestString;
            if(childCheckList.axisltd_Request__c.length() > IntegrationConstants.TEXT_AREA_MAX_CHAR_LIMIT || Test.isRunningTest()){
                childCheckList.axisltd_Is_Request_in_Attachment__c = true;
                ContentVersion requestCV = new ContentVersion();
                requestCV.VersionData = CryptoUtils.base64Decode(CryptoUtils.base64Encode(Blob.valueOf(childCheckList.axisltd_Request__c)));
                requestCV.title = IntegrationConstants.CHECKLIST_REQUEST_FILE_NAME;
                requestCV.PathOnClient = IntegrationConstants.CHECKLIST_REQUEST_PATH_NAME;
                requestCV.axisltd_Document_Type__c = IntegrationConstants.CHECKLIST_REQUEST_DOCUMENT_TYPE;
                childCheckList.axisltd_Request__c = null;
                cvList.add(requestCV);
            }

            childCheckList.axisltd_Response__c = responseString; 
            if(childCheckList.axisltd_Response__c.length() > IntegrationConstants.TEXT_AREA_MAX_CHAR_LIMIT || Test.isRunningTest()){
                childCheckList.axisltd_Is_Response_in_Attachment__c = true;
                ContentVersion responseCV = new ContentVersion();
                responseCV.VersionData = CryptoUtils.base64Decode(CryptoUtils.base64Encode(Blob.valueOf(childCheckList.axisltd_Response__c)));
                responseCV.title = IntegrationConstants.CHECKLIST_RESPONSE_FILE_NAME;
                responseCV.PathOnClient = IntegrationConstants.CHECKLIST_RESPONSE_PATH_NAME;
                responseCV.axisltd_Document_Type__c = IntegrationConstants.CHECKLIST_RESPONSE_DOCUMENT_TYPE;
                childCheckList.axisltd_Response__c = null;
                cvList.add(responseCV);
            }

            childCheckList.axisltd_Response_Received_At__c = requestInitiatedDateTime;
            childCheckList.axisltd_Is_Latest__c = true;
            checklistToUpdate.add(childCheckList);
            
            parentChecklist[0].axisltd_Functional_Status__c = 
                responseStatusCode==IntegrationConstants.RESPONSE_SUCCESS_STATUS_CODE?
                IntegrationConstants.CHECKLIST_COMPLETED_FUNCTIONAL_STATUS:
                IntegrationConstants.CHECKLIST_FAILED_FUNCTIONAL_STATUS;
            parentChecklist[0].axisltd_Status__c = 
                responseStatusCode==IntegrationConstants.RESPONSE_SUCCESS_STATUS_CODE?
                IntegrationConstants.CHECKLIST_SUCCESS_STATUS:
                IntegrationConstants.CHECKLIST_FAILED_STATUS;

            checklistToUpdate.add(parentChecklist[0]);

            if(!checklistToUpdate.isEmpty()){
                upsert checklistToUpdate;
            }
                
            if(!cvList.isEmpty()){
                for(ContentVersion cv : cvList){
                    cv.FirstPublishLocationId = childCheckList.Id;
                }
                insert cvList;
            }
        }
    }

    @AuraEnabled
    public static Charge_Details__c updateCharges(axisltd_Payment__c payment){

        List<Charge_Details__c> charges = [SELECT Id, axisltd_Charge_Master_Name__c, axisltd_ChargeAmount__c 
                                    FROM Charge_Details__c 
                                    WHERE axisltd_LoanApplicationId__c =: payment.axisltd_Loan_Application__c
                                    AND axisltd_Charge_Master_Name__c =: Nano_Constants.CHARGE_MASTER_RECOVERY_INITIAL_MONEY 
                                    LIMIT 1];

        if(!charges.isEmpty()){
            Decimal chargeAmount = charges[0].axisltd_ChargeAmount__c - payment.axisltd_Amount__c;
            charges[0].axisltd_ChargeAmount__c = chargeAmount;

            update as system charges;

            return charges[0];
        }
        return null;
    }

    public class ResponseWrapper{
        //BB-61727 - Vikrant - start
        @AuraEnabled public String errorMessage {get;set;}
        @AuraEnabled public Boolean isPaymentCompleted {get;set;}
        @AuraEnabled public Decimal imdAmount {get;set;}
        @AuraEnabled public List<axisltd_Payment__c> payments {get;set;}
		@AuraEnabled public Charge_Details__c chargeDetail {get;set;}
        @AuraEnabled public Integer countdownTime {get;set;}
        //BB-61727 - Vikrant  - end

        //BB-64908 - Surag - start
        @AuraEnabled public String scheme {get;set;}
        @AuraEnabled public List<axisltd_Approval_Request__c> approvalRequests {get;set;}
        //BB-64908 - Surag - end
        
        //BB-67081 - Anjani - Start
        @AuraEnabled public Boolean isNanoCAUWOpsUser {get;set;}
        @AuraEnabled public Boolean isOwner {get;set;}
        //BB-67081 - Anjani - end
    }
    //BB-64910 | Priyank | START
    public class PaymentWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String modifiedDate;
        @AuraEnabled public String phone;
        @AuraEnabled public String status;
        @AuraEnabled public String gatewayResponse;
        @AuraEnabled public String transactionId;
    }
    //BB-64910 | Priyank | END    
}