/*******************************************************************************************
* @Name         LoanApplicationHelper
* @Author       Narendra Nimmana
* @Description  This Class is Trigger Helper for ResidentialLoanApplication
It consists modular methods, can be reused
*******************************************************************************************/
/* MODIFICATION LOG
* Version          Developer           		Date               Description
*-------------------------------------------------------------------------------------------
*  1.0             Narendra Nimmana        13/06/2023           BB-512 - Initial Creation    
*  2.0			   Alpish Jain			   31/07/2023			Added creditDecisionInReviewValidation() for BB-826 
*  2.1			   Santhosh			   	   07/08/2023			Added updateCreditApprover() for BB-243 
*  2.2			   Rajashree			   08/08/2023			Added loanAppSanctionValidationforRE() and 
loanAppSanctionValidationforOPS for BB-262 and BB-293 
*  2.3			   Rajashree/Alpish		   30/08/2023			Added setTheSLAStagesOnRejectionInsertion() and
setTheSLAStagesOnRejectionUpdate() for BB-787
*  2.4             Himanshu Kumar          14/09/2023           BB-747 Added updateCRMNext Method
*  2.5             Vishal Bandari          25/09/2023.          BB-1022 Added eKYCValidation Method
*  2.6             Avinash Kumar Singh     27/11/2023           BB-1841 Added reGenerateCamReport  Method /30/04/2024 Removed reGenerateCamReport
*  2.7             Akash Harwani           10/01/2024           BB-2605 Added validation to check for rejection of Special Caste Application 
*  2.8             Akash Harwani           15/01/2024           BB-2633 Dealing bank is now being fetched based on the Loan Application Product code and Disbursement Details Instrument Type.
*  2.9             Akash Harwani           19/01/2024           BB-2503 Calling the CHUB API to send the notification to applicant and co-applicant when the Loan Application is rejected.
*  3.0			   Joyson Tuscano		   20/02/2024			BB-2378 Dealer Master Restructuring - updated SOQL query in DealerDisbursementSplit method
*  3.1             Santhosh Maduri         06.03.2024           BB-2462 commented the method loanAppSanctionValidationforOPS
*  3.2			   Joyson Tuscano		   15/04/2024			BB-1694 Archive Deviation and update FCU Deviation.
*  3.3			   Avinash Kumar Singh	   22/05/2024			BB-13534 Sanction Letter Generation Required set to true on stage change from CD / AWAITING FCU to Pre-Disbursement.
*******************************************************************************************/
public without sharing class AxisNanoLoanAppSharingHelper {
//Values can be either Account or Loan
public static final String SHARING_BASED_ON = System.Label.AXIS_TRACTOR_LOAN_SHARE_BASED_ON;
public static final String NANO_SHARING_BASED_ON = System.Label.AXIS_NANO_LOAN_SHARE_BASED_ON;

public static void shareLoanAppRecord(List<sObject> newList, Map<Id, sObject> oldRecordsMap, Boolean isInsert) {
    List<ResidentialLoanApplication> records = (List<ResidentialLoanApplication>) newList;

    Set<Id> recordIds = new Set<Id>();
    ShareRecordUtil.delRacIdRecordIdsMap = new Map<Id, Set<Id>>();
    ShareRecordUtil.delREIdRecordIdsMap = new Map<Id, Set<Id>>();
    ShareRecordUtil.delLonaIdOldRacIdMap = new Map<Id, Id>();
    ShareRecordUtil.delLonaIdOldReIdMap = new Map<Id, Id>();

    Set<Id> nanoRecordIds = new Set<Id>();
    ShareRecordUtilNano.delCPCIdRecordIdsMap = new Map<Id, Set<Id>>();
    ShareRecordUtilNano.delREIdRecordIdsMap = new Map<Id, Set<Id>>();
    ShareRecordUtilNano.delLonaIdOldCPCIdMap = new Map<Id, Id>();
    ShareRecordUtilNano.delLonaIdOldReIdMap = new Map<Id, Id>();
    Id ROReadOnly;
    Set<String> roReadOnlyId = new Set<String>();
    /**
    Changes Made: Added loop to check if oldMap values doesn't match newMap values as part of optimization
    Made By: Saloni 
    Date: 21st Nov 2024
    */
    for (ResidentialLoanApplication loanApp : records) {
        if(oldRecordsMap!=null && !oldRecordsMap.isEmpty()){
            ResidentialLoanApplication oldLoanApp = (ResidentialLoanApplication) oldRecordsMap.get(loanApp.Id);
            if(loanApp.Status != oldLoanApp.Status &&   oldLoanApp.Status == LOS_Constants.LOAN_APP_STAGE_DISBURSEMENT)
            {
                roReadOnlyId.add(loanApp.Id);
            }
        }
    }
    if(!roReadOnlyId.isEmpty()){
        ROReadOnly = NanoUtil.fetcchGroupIdByName('Axis_Read_Only');
    }
    for (ResidentialLoanApplication loanApp : records) {
        String recordId = loanApp.AccountId;

        if (loanApp.RecordTypeId == LOS_Constants.TRACTOR_RECORDTYPE_ID && SHARING_BASED_ON == 'Loan') {
            recordId = loanApp.Id;
        } else if (loanApp.RecordTypeId == Nano_Constants.NANO_RECORDTYPE_ID && NANO_SHARING_BASED_ON == 'Loan') {
            recordId = loanApp.Id;
        }

        if (
            isInsert &&
            (loanApp.axisltd_RE__c != null ||
            loanApp.Working_CPC__c != null) &&
            loanApp.RecordTypeId == LOS_Constants.TRACTOR_RECORDTYPE_ID
        ) {
            recordIds.add(recordId);
        } else if (!isInsert && loanApp.RecordTypeId == LOS_Constants.TRACTOR_RECORDTYPE_ID) {
            ResidentialLoanApplication oldLoanApp = (ResidentialLoanApplication) oldRecordsMap.get(loanApp.Id);
            if (
                (oldLoanApp.axisltd_RE__c != loanApp.axisltd_RE__c) ||
                (oldLoanApp.Working_CPC__c != loanApp.Working_CPC__c) ||
                (oldLoanApp.OwnerId != loanApp.OwnerId)
            ) {
                recordIds.add(recordId);
            }
            if (oldLoanApp.axisltd_RE__c != loanApp.axisltd_RE__c && oldLoanApp.axisltd_RE__c != null) {
                if (ShareRecordUtil.delREIdRecordIdsMap.containsKey(loanApp.axisltd_RE__c)) {
                    ShareRecordUtil.delREIdRecordIdsMap.get(oldLoanApp.axisltd_RE__c).add(recordId);
                } else {
                    ShareRecordUtil.delREIdRecordIdsMap.put(oldLoanApp.axisltd_RE__c, new Set<Id>{ recordId });
                }

                ShareRecordUtil.delLonaIdOldReIdMap.put(loanApp.Id, oldLoanApp.axisltd_RE__c);
            }
            if (oldLoanApp.Working_CPC__c != loanApp.Working_CPC__c && oldLoanApp.Working_CPC__c != null) {
                if (ShareRecordUtil.delRacIdRecordIdsMap.containsKey(loanApp.Working_CPC__c)) {
                    ShareRecordUtil.delRacIdRecordIdsMap.get(oldLoanApp.Working_CPC__c).add(recordId);
                } else {
                    ShareRecordUtil.delRacIdRecordIdsMap.put(oldLoanApp.Working_CPC__c, new Set<Id>{ recordId });
                }

                ShareRecordUtil.delLonaIdOldRacIdMap.put(loanApp.Id, oldLoanApp.Working_CPC__c);
            }
        }

        if (
            isInsert &&
            (loanApp.axisltd_RE__c != null ||
            loanApp.Working_CPC__c != null) &&
            loanApp.RecordTypeId == Nano_Constants.NANO_RECORDTYPE_ID
        ) {
            nanoRecordIds.add(recordId);
        } else if (!isInsert && loanApp.RecordTypeId == Nano_Constants.NANO_RECORDTYPE_ID) {
            ResidentialLoanApplication oldLoanApp = (ResidentialLoanApplication) oldRecordsMap.get(loanApp.Id);
            if (
                (oldLoanApp.axisltd_RE__c != loanApp.axisltd_RE__c) ||
                (oldLoanApp.Working_CPC__c != loanApp.Working_CPC__c) ||
                (oldLoanApp.OwnerId != loanApp.OwnerId) ||
                (oldLoanApp.axisltd_Assigned_OPS_Maker__c !=loanApp.axisltd_Assigned_OPS_Maker__c) ||
                (oldLoanApp.Status != loanApp.Status) //19695
            ) {
                nanoRecordIds.add(recordId);
            }

            if (oldLoanApp.axisltd_RE__c != loanApp.axisltd_RE__c && oldLoanApp.axisltd_RE__c != null) {
                if (ShareRecordUtilNano.delREIdRecordIdsMap.containsKey(loanApp.axisltd_RE__c)) {
                    ShareRecordUtilNano.delREIdRecordIdsMap.get(oldLoanApp.axisltd_RE__c).add(recordId);
                } else {
                    ShareRecordUtilNano.delREIdRecordIdsMap.put(oldLoanApp.axisltd_RE__c, new Set<Id>{ recordId });
                }

                ShareRecordUtilNano.delLonaIdOldReIdMap.put(loanApp.Id, oldLoanApp.axisltd_RE__c);
            }

            if (
                oldLoanApp.Working_CPC__c != loanApp.Working_CPC__c &&
                oldLoanApp.Working_CPC__c != null
            ) {
                if (ShareRecordUtilNano.delCPCIdRecordIdsMap.containsKey(loanApp.Working_CPC__c)) {
                    ShareRecordUtilNano.delCPCIdRecordIdsMap.get(oldLoanApp.Working_CPC__c).add(recordId);
                } else {
                    ShareRecordUtilNano.delCPCIdRecordIdsMap.put(
                        oldLoanApp.Working_CPC__c,
                        new Set<Id>{ recordId }
                    );
                }

                ShareRecordUtilNano.delLonaIdOldCPCIdMap.put(loanApp.Id, oldLoanApp.Working_CPC__c);
            }
            
            //Unshare LA's moved out of Disbursement stage with Axis Read Only-19695
            if(loanApp.Status != oldLoanApp.Status &&   oldLoanApp.Status == LOS_Constants.LOAN_APP_STAGE_DISBURSEMENT)
            {
                if(ShareRecordUtilNano.delRODisbursedLARecIdsMap != null && ShareRecordUtilNano.delRODisbursedLARecIdsMap.containsKey(ROReadOnly))
                    ShareRecordUtilNano.delRODisbursedLARecIdsMap.get(ROReadOnly).add(recordId);
                else {
                    ShareRecordUtilNano.delRODisbursedLARecIdsMap = new Map<Id, Set<Id>>();
                    ShareRecordUtilNano.delRODisbursedLARecIdsMap.put(ROReadOnly, new Set<Id>{recordId});  
                }  
                    
                    
                System.debug('$$$'+ShareRecordUtilNano.delRODisbursedLARecIdsMap);
            } 
            //19695
        }
    }

    if (!recordIds.isEmpty()) {
        ShareRecordUtil.shareLoanRecords(recordIds);
    }

    if (!nanoRecordIds.isEmpty()) {
        System.debug('entered when loanapplication is inserted');
        ShareRecordUtilNano.shareLoanRecords(nanoRecordIds);
    }
    Integer queryCount = Limits.getQueries();

	System.debug('Number of SOQL queries used shareLoanAppRecord: ' + queryCount);
}

/*public static void shareInvestigationRecords(
    List<sObject> newList,
    Map<Id, sObject> oldRecordsMap,
    Boolean isInsert
) {
    Set<Id> recordIds = new Set<Id>();
    Map<Id, Id> delInvIdLoanIdMap = new Map<Id, Id>();
    for (axisltd_Investigation__c investigation : (List<axisltd_Investigation__c>) newList) {
        if (isInsert && investigation.axisltd_Loan_Application__c != null) {
            recordIds.add(investigation.Id);
        } else if (!isInsert) {
            axisltd_Investigation__c oldInvestigation = (axisltd_Investigation__c) oldRecordsMap.get(
                investigation.Id
            );
            if (
                (investigation.OwnerId != oldInvestigation.OwnerId ||
                investigation.axisltd_Loan_Application__c != oldInvestigation.axisltd_Loan_Application__c) &&
                investigation.axisltd_Loan_Application__c != null
            ) {
                recordIds.add(investigation.Id);
            }
            if (
                investigation.axisltd_Loan_Application__c != oldInvestigation.axisltd_Loan_Application__c &&
                oldInvestigation.axisltd_Loan_Application__c != null
            ) {
                delInvIdLoanIdMap.put(investigation.Id, oldInvestigation.axisltd_Loan_Application__c);
            }
        }
    }
    if (!recordIds.isEmpty() || !delInvIdLoanIdMap.isEmpty()) {
        ShareRecordUtilNano.shareInvestigationRecords(recordIds, delInvIdLoanIdMap);
    }
}*/
public static void shareInvestigationRecordsOnStatusChange(List<sObject> newList,
Map<Id, sObject> oldRecordsMap
){
    Id samplerGrpId;
    Id managerGrpId;
    Id levelOneManagerGroupId;
    Id fcuLegalRecordTypeId = Schema.SObjectType.axisltd_Investigation__c.getRecordTypeInfosByDeveloperName().get(LOS_Constants.LEGAL_VERIFICATION_REC_TYPE_DEVNAME).getRecordTypeId();          // L&T Sharing Related Change - Surag - 01/08/2025
    Id fcuTechnicalRecordTypeId = Schema.SObjectType.axisltd_Investigation__c.getRecordTypeInfosByDeveloperName().get(LOS_Constants.TECH_VERIFICATION_REC_TYPE_DEVNAME).getRecordTypeId();       // L&T Sharing Related Change - Surag - 01/08/2025
    Map<Id,ResidentialLoanApplication> loanApplicationMap = new Map<Id,ResidentialLoanApplication>();      //BB-44460 Surag FCU
    Set<Id> laIds = new Set<Id>();                                                                         //BB-44460 Surag FCU    
    Set<Id> lAndTRecTypeIds = new Set<Id>{fcuLegalRecordTypeId, fcuTechnicalRecordTypeId};                                                                         // L&T Sharing Related Change - Surag - 01/08/2025

    List<String> groupNames = new List<String>{
        Nano_Constants.SAMPLER_GROUP,
        Nano_Constants.MANAGER_INTERNAL,
        Nano_Constants.L1_GROUP
    };
    for(Group grp :[SELECT Id,DeveloperName FROM Group WHERE DeveloperName IN:groupNames]){
       if(grp.DeveloperName == Nano_Constants.SAMPLER_GROUP){
            samplerGrpId = grp.Id;
       }
       if(grp.DeveloperName ==Nano_Constants.MANAGER_INTERNAL){
            managerGrpId = grp.Id;
       }
       if(grp.DeveloperName == Nano_Constants.L1_GROUP){
            levelOneManagerGroupId = grp.Id;
        }
    }

    Set<Id> investigationIds = new Set<Id>();
    for (axisltd_Investigation__c newRecord : (List<axisltd_Investigation__c>)newList) {
        axisltd_Investigation__c oldRecord = (oldRecordsMap != null) ? (axisltd_Investigation__c)oldRecordsMap.get(newRecord.Id) : null;
        if (oldRecord == null || oldRecord.axisltd_Status__c != newRecord.axisltd_Status__c || oldRecord.OwnerId != newRecord.OwnerId) {
            investigationIds.add(newRecord.Id);
            laIds.add(newRecord.axisltd_Loan_Application__c);               //BB-44460 Surag FCU
        }
    }

    //Executing in case when  Investigation os getting updated 
    if(oldRecordsMap !=null){
        List<axisltd_Investigation__Share> oldShares = [
            SELECT Id, ParentId 
            FROM axisltd_Investigation__Share 
            WHERE ParentId IN :investigationIds
            AND RowCause != 'Owner'
        ];
         System.debug('the old share recoords' + oldShares);
        if (!oldShares.isEmpty()) {
            delete oldShares;
        }
   }

   
    //BB-44460 Surag FCU Start
    if(!investigationIds.isEmpty() && !laIds.isEmpty()){
        List<ResidentialLoanApplication> loanApplicationList = [SELECT Id, Name, axisltd_Assigned_OPS_Checker__c, axisltd_RE__c, axisltd_CA__c, axisltd_Assigned_OPS_Maker__c, axisltd_Assigned_Underwriter__c, OwnerId, Owner.Profile.Name
                                                                FROM ResidentialLoanApplication  
                                                                WHERE Id IN :laIds];
        if(!loanApplicationList.isEmpty() && loanApplicationList != null){
            for(ResidentialLoanApplication loan : loanApplicationList){
                loanApplicationMap.put(loan.Id,loan);
            }
        }   
    }   
    //BB-44460 Surag FCU End

    List<axisltd_Investigation__Share> sharesToInsert = new List<axisltd_Investigation__Share>();

    for (axisltd_Investigation__c newRecord : (List<axisltd_Investigation__c>)newList) {
        if (!investigationIds.contains(newRecord.Id)){ continue;}

        sharesToInsert.add(new axisltd_Investigation__Share(
                    ParentId = newRecord.Id,
                    UserOrGroupId = levelOneManagerGroupId,
                    AccessLevel = 'Read'
                ));

        switch on newRecord.axisltd_Status__c {
            when 'FCU Initiated' {//Invoked in case when record is inserted 
                sharesToInsert.add(new axisltd_Investigation__Share(
                    ParentId = newRecord.Id,
                    UserOrGroupId = samplerGrpId,
                    AccessLevel = 'Read'
                ));
                sharesToInsert.add(new axisltd_Investigation__Share(
                    ParentId = newRecord.Id,
                    UserOrGroupId = managerGrpId,
                    AccessLevel = 'Read'
                ));
            }
            when else {  //Invoked in case when record is updated
                if (newRecord.axisltd_Initial_Sampler__c != null && newRecord.axisltd_Status__c !='Assigned to Sampler') {
                    sharesToInsert.add(new axisltd_Investigation__Share(
                        ParentId = newRecord.Id,
                        UserOrGroupId = newRecord.axisltd_Initial_Sampler__c,
                        AccessLevel = 'Read'
                    ));
                }
            }
        }
     

        //BB-44460 Surag FCU Start
        if(!loanApplicationMap.isEmpty() && loanApplicationMap.containsKey(newRecord.axisltd_Loan_Application__c)){
            ResidentialLoanApplication laRecord = loanApplicationMap.get(newRecord.axisltd_Loan_Application__c);
            Boolean isUW = laRecord.Owner.Profile.Name == Nano_Constants.AXIS_UW_PROFILE ? laRecord.OwnerId != laRecord.axisltd_Assigned_Underwriter__c ? true : false : false;

            
            axisltd_Investigation__Share wrapOwnerUW = new axisltd_Investigation__Share();
            axisltd_Investigation__Share wrapUW = new axisltd_Investigation__Share();
            axisltd_Investigation__Share wrapOM = new axisltd_Investigation__Share();
            axisltd_Investigation__Share wrapOC = new axisltd_Investigation__Share();
            axisltd_Investigation__Share wrapRE = new axisltd_Investigation__Share();
            axisltd_Investigation__Share wrapCA = new axisltd_Investigation__Share();
            if(Nano_Constants.FCU_CASES_IN_PROGRESS_STATUS_SHARING_LIST.contains(newRecord.axisltd_Status__c)){
                // share record for UW
                if(String.isNotBlank(laRecord.axisltd_Assigned_Underwriter__c)){
                    wrapUW.ParentId=newRecord.Id;
                    wrapUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapUW.userOrGroupId=laRecord.axisltd_Assigned_Underwriter__c;
                    sharesToInsert.add(wrapUW);
                }
                // share record for LA owner if UW
                if(isUW){
                    wrapOwnerUW.ParentId=newRecord.Id;
                    wrapOwnerUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapOwnerUW.userOrGroupId=laRecord.OwnerId;
                    sharesToInsert.add(wrapOwnerUW);
                }
            }else if(newRecord.axisltd_Status__c == Nano_Constants.INVESTIGATION_FCU_SCREENED_OK_STATUS){
                // share record for UW
                if(String.isNotBlank(laRecord.axisltd_Assigned_Underwriter__c)){
                    wrapUW.ParentId=newRecord.Id;
                    wrapUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapUW.userOrGroupId=laRecord.axisltd_Assigned_Underwriter__c;
                    sharesToInsert.add(wrapUW);
                }
                // share record for LA owner if UW
                if(isUW){
                    wrapOwnerUW.ParentId=newRecord.Id;
                    wrapOwnerUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapOwnerUW.userOrGroupId=laRecord.OwnerId;
                    sharesToInsert.add(wrapOwnerUW);
                }
                //share record for Ops Maker
                if(String.isNotBlank(laRecord.axisltd_Assigned_OPS_Maker__c)){
                    wrapOM.ParentId=newRecord.Id;
                    wrapOM.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapOM.userOrGroupId=laRecord.axisltd_Assigned_OPS_Maker__c;
                    sharesToInsert.add(wrapOM);
                }
                // share record for Ops Checker
                if(String.isNotBlank(laRecord.axisltd_Assigned_OPS_Checker__c)){
                    wrapOC.ParentId=newRecord.Id;
                    wrapOC.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapOC.userOrGroupId=laRecord.axisltd_Assigned_OPS_Checker__c;
                    sharesToInsert.add(wrapOC);
                }
            }else if(Nano_Constants.FCU_CASES_COMPLETED_STATUS_SHARING_LIST.contains(newRecord.axisltd_Status__c)){
                // share record for UW
                if(String.isNotBlank(laRecord.axisltd_Assigned_Underwriter__c)){
                    wrapUW.ParentId=newRecord.Id;
                    wrapUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_EDIT_ACCESS;
                    wrapUW.userOrGroupId=laRecord.axisltd_Assigned_Underwriter__c;
                    sharesToInsert.add(wrapUW);
                }
                // share record for LA owner if UW
                if(isUW){
                    wrapOwnerUW.ParentId=newRecord.Id;
                    wrapOwnerUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_EDIT_ACCESS;
                    wrapOwnerUW.userOrGroupId=laRecord.OwnerId;
                    sharesToInsert.add(wrapOwnerUW);
                }
                //share record for Ops Maker
                if(String.isNotBlank(laRecord.axisltd_Assigned_OPS_Maker__c)){
                    wrapOM.ParentId=newRecord.Id;
                    wrapOM.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapOM.userOrGroupId=laRecord.axisltd_Assigned_OPS_Maker__c;
                    sharesToInsert.add(wrapOM);
                }
                // share record for Ops Checker
                if(String.isNotBlank(laRecord.axisltd_Assigned_OPS_Checker__c)){
                    wrapOC.ParentId=newRecord.Id;
                    wrapOC.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapOC.userOrGroupId=laRecord.axisltd_Assigned_OPS_Checker__c;
                    sharesToInsert.add(wrapOC);
                }
            }

            // L&T Sharing Related Change - Surag - 01/08/2025 - Start
            if(lAndTRecTypeIds.contains(newRecord.RecordTypeId)){
                 if(wrapUW.userOrGroupId == NULL && String.isNotBlank(laRecord.axisltd_Assigned_Underwriter__c) && newRecord.OwnerId != laRecord.axisltd_Assigned_Underwriter__c){
                    wrapUW.ParentId=newRecord.Id;
                    wrapUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapUW.userOrGroupId=laRecord.axisltd_Assigned_Underwriter__c;
                    sharesToInsert.add(wrapUW);
                }
                // share record for LA owner if UW
                if(wrapOwnerUW.userOrGroupId == NULL && isUW && newRecord.OwnerId != laRecord.OwnerId){
                    wrapOwnerUW.ParentId=newRecord.Id;
                    wrapOwnerUW.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapOwnerUW.userOrGroupId=laRecord.OwnerId;
                    sharesToInsert.add(wrapOwnerUW);
                }
                if(String.isNotBlank(laRecord.axisltd_RE__c) && newRecord.OwnerId != laRecord.axisltd_RE__c){
                    wrapRE.ParentId=newRecord.Id;
                    wrapRE.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapRE.userOrGroupId=laRecord.axisltd_RE__c;
                    sharesToInsert.add(wrapRE);
                }
                if(String.isNotBlank(laRecord.axisltd_CA__c) && newRecord.OwnerId != laRecord.axisltd_CA__c){
                    wrapCA.ParentId=newRecord.Id;
                    wrapCA.accessLevel=LOS_Constants.STRING_SHARE_RECORDS_READ_ACCESS;
                    wrapCA.userOrGroupId=laRecord.axisltd_CA__c;
                    sharesToInsert.add(wrapCA);
                }
            }
            // L&T Sharing Related Change - Surag - 01/08/2025 - End
        }
        //BB-44460 Surag FCU End
        
    }

     //MODIFICATION 49577- Sharing loan  application related to investigation to All fcumanger/backend/support - Shubham
List<ResidentialLoanApplicationShare> rlsList = new List<ResidentialLoanApplicationShare>();
for(Id ladId :laIds){
    ResidentialLoanApplicationShare rls = new ResidentialLoanApplicationShare();
    rls.ParentId = ladId;
    rls.UserOrGroupId = levelOneManagerGroupId;
    rls.AccessLevel = 'Read';
    rlsList.add(rls);
}

    System.debug('@@sharesToInsert:::'+ sharesToInsert);
    // Insert new shares
    if (!sharesToInsert.isEmpty()) {
        insert  as system sharesToInsert;
    }
    if(!rlsList.isEmpty()){
        insert  as system rlsList;
    }
}

public static void shareFCUToCurrentOppOwner(List<ResidentialLoanApplication> records, Map<Id, ResidentialLoanApplication> oldRecordMap){
    Set<Id> setLoanAppId = new Set<Id>();
    for(ResidentialLoanApplication rla: records){
        if(rla.OwnerId != oldRecordMap.get(rla.Id).OwnerId){
            setLoanAppId.add(rla.Id);
        }
    }

    List<axisltd_Investigation__c> investigationList = new List<axisltd_Investigation__c>();
    /**SH-OPTIMIZATION--START*/
    // investigationList = [SELECT Id,axisltd_Loan_Application__r.OwnerId FROM axisltd_Investigation__c WHERE axisltd_Loan_Application__c IN: setLoanAppId];
    Map<Id, ResidentialLoanApplication> queriedRLAs = new Map<Id, ResidentialLoanApplication>(LoanApplicationTriggerHelper.queryRLAandRelatedRecords(setLoanAppId));

    for(Id loanId : setLoanAppId){
        ResidentialLoanApplication rla = queriedRLAs.get(loanId);
        if(rla != null && !rla.Investigations__r.isEmpty()){
            investigationList.addAll(rla.Investigations__r);
        }
    }
    /**SH-OPTIMIZATION--END*/
    if(!investigationList.isEmpty()){
        ShareRecordUtilNano.shareFCURecordToCurrentOpportunityOwner(investigationList);
    }
}


public static void shareParentChecklistRecordToOwner(List<ResidentialLoanApplication> records, Map<Id, ResidentialLoanApplication> oldRecordMap){
    Set<Id> setLoanAppId = new Set<Id>();
    for(ResidentialLoanApplication rla: records){
        if(rla.OwnerId != oldRecordMap.get(rla.Id).OwnerId){
            setLoanAppId.add(rla.Id);
        }
    }

    List<axisltd_Integration_Checklist__c> integrationChecklistList = new List<axisltd_Integration_Checklist__c>();
    /**SH-OPTIMIZATION--START*/
    //integrationChecklistList = [Select Id,axisltd_Applicant__r.Name,axisltd_Loan_Application__r.OwnerId from axisltd_Integration_Checklist__c Where axisltd_Parent_Checklist__c = null 
    //                        and axisltd_Loan_Application__c IN: setLoanAppId and axisltd_Integration_Master__r.axisltd_External_Id__c = :IntegrationConstants.POSIDEX_MASTER_EXTERNAL_Id];
    Map<Id, ResidentialLoanApplication> queriedRLAs = new Map<Id, ResidentialLoanApplication>(LoanApplicationTriggerHelper.queryRLAandRelatedRecords(setLoanAppId));
        
    for(Id loanId : setLoanAppId){
        ResidentialLoanApplication rla = queriedRLAs.get(loanId);
        if(rla != null){
            for(axisltd_Integration_Checklist__c iCheck : rla.Integration_Checklists__r){
                if(iCheck.axisltd_Parent_Checklist__c == null && iCheck.axisltd_Integration_Master__r.axisltd_External_Id__c == IntegrationConstants.POSIDEX_MASTER_EXTERNAL_Id){
                    integrationChecklistList.add(iCheck);
                }
            }
        }
    }
    /**SH-OPTIMIZATION--END*/
    if(!integrationChecklistList.isEmpty()){
        ShareRecordUtilNano.shareIntChklstToCurrentOppOwner(integrationChecklistList);
    }
}


    public static void shareLARecordToFCUManager(List<ResidentialLoanApplication> records, Map<Id, ResidentialLoanApplication> oldRecordMap){
        Set<Id> setLoanAppId = new Set<Id>();
        for(ResidentialLoanApplication rla: records){
            if(rla.OwnerId != oldRecordMap.get(rla.Id).OwnerId){
                setLoanAppId.add(rla.Id);
            }
        }

        List<axisltd_Investigation__c> investigationList = new List<axisltd_Investigation__c>();
        /**SH-OPTIMIZATION--START*/
        // investigationList = [SELECT Id,axisltd_Loan_Application__r.OwnerId FROM axisltd_Investigation__c WHERE axisltd_Loan_Application__c IN: setLoanAppId];
        Map<Id, ResidentialLoanApplication> queriedRLAs = new Map<Id, ResidentialLoanApplication>(LoanApplicationTriggerHelper.queryRLAandRelatedRecords(setLoanAppId));

        for(Id loanId : setLoanAppId){
            ResidentialLoanApplication rla = queriedRLAs.get(loanId);
            if(rla != null && !rla.Investigations__r.isEmpty()){
                investigationList.addAll(rla.Investigations__r);
            }
        }

        if(!investigationList.isEmpty()){
            List<axisltd_Investigation__c> lstInvestigationToShare = new List<axisltd_Investigation__c>() ;
            for(axisltd_Investigation__c inv: investigationList){
                if(inv.FCU_Manager__c != null && inv.axisltd_Loan_Application__c != null){
                    lstInvestigationToShare.add(inv);
                }
            }
            if(!lstInvestigationToShare.isEmpty()){
                ShareRecordUtilNano.shareLAReadAccessToFCUManager(lstInvestigationToShare);
            }
        }
        
    }
}