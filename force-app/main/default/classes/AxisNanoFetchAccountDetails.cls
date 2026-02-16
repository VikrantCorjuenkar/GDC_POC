/*******************************************************************
 * @description       : Fetch Account Details
 * @author            : Surag Lunagariya
 * @TestClass		 :
 * @last modified on  : 23-Feb-2024
 * @last modified by  : Surag Lunagariya
 ********************************************************************/
public with sharing class AxisNanoFetchAccountDetails {
  //private static Id recordId = '';
  // initiateFetchAccountDetails method is used to initiate the fetch account integration from quick action on Disbursement Details and Instrument Details.
  @AuraEnabled
  public static ResponseWrap initiateFetchAccountDetails(Id recID) {
    try {
      AxisNanoFetchAccountDetailsIntegration fetchAccountIntegration = new AxisNanoFetchAccountDetailsIntegration();
      IntegrationUtility.ResponseWrapper resp = fetchAccountIntegration.invoke(
        recID
      );

      ResponseWrap wrap = new ResponseWrap();
      AxisNanoFetchAccountDetailsWrap respon = new AxisNanoFetchAccountDetailsWrap();
      if (resp.statusCode == 200) {
        Map<String, Object> tempResponse = (Map<String, Object>) JSON.deserializeUntyped(
          resp.checklistRecord.axisltd_Response__c
        );

        

        respon = AxisNanoFetchAccountDetailsWrap.parse(
          resp.checklistRecord.axisltd_Response__c
        );

        wrap.accList = respon.Data.AccountDetails;
      } else {
        wrap.errorMsg = 'No account found, please validate account number.';
      }
      return wrap;
    } catch (Exception e) {
      throw throwUIException(e.getLineNumber() + ' : ' + e.getMessage());
    }
  }

  //throwUIException method is used to throw exceptions throughout the integration.
  private static AuraHandledException throwUIException(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }

  //getLoanAppDetails method is used to pass the Loan Application data to LWC.
  @AuraEnabled
  public static ObjectDetailWrap getLoanAppDetails(Id recID) {
    ObjectDetailWrap wrap = new ObjectDetailWrap();
    if (recID != null) {
      String currentSobjectName = recID.getSObjectType()
        .getDescribe()
        .getName(); //check which object is this by recordId
      if (currentSobjectName == 'Instrument_Detail__c') {
        wrap.instruDetails = [
          SELECT
            id,
            LoanApplicationId__c,
            LoanApplicationId__r.axisltd_Constitution__c
          FROM Instrument_Detail__c
          WHERE id = :recID
        ];
        wrap.objectName = 'InstrumentDetails';
      } else if (currentSobjectName == 'Disbursement_Details__c') {
        wrap.disburseDetails = [
          SELECT
            id,
            axisltd_Loan_Application__c,
            axisltd_Loan_Application__r.axisltd_Constitution__c
          FROM Disbursement_Details__c
          WHERE id = :recID
        ];
        wrap.objectName = 'DisbursementDetails';
      }
    }
    return wrap;
  }

  //getRecordDetails method is used to fetch record details using auto number field.
  @AuraEnabled
  public static String getRecordId(String recNumber) {
    try {
      if (recNumber != null) {
        if (recNumber.startsWith('Ins')) {
          return [
            SELECT Id
            FROM Instrument_Detail__c
            WHERE Name = :recNumber
            LIMIT 1
          ]
          .Id;
        } else if (recNumber.startsWith('DIS')) {
          return [
            SELECT Id
            FROM Disbursement_Details__c
            WHERE Name = :recNumber
            LIMIT 1
          ]
          .Id;
        }
      }
    } catch (Exception e) {
      return 'ERROR: ' + e.getLineNumber() + ' : ' + e.getMessage();
    }
    return 'ERROR: Something went wrong!! Please try again later.';
  }

  //updateDetailsData method is used to update the Disbursement Details or Instrument Details selected by user from LWC.
  @AuraEnabled
  public static void updateDetailsData(
    Id recID,
    String accName,
    String accNum,
    String ifscCode,
    String accStatus,
    String accType
  ) {
    try {
      //recordId = recID;
      MICR_Master__c micr = getMICRRecord(ifscCode);

      if (recID != null) {
        String currentSobjectName = recID.getSObjectType()
          .getDescribe()
          .getName();

        if (currentSobjectName == 'Instrument_Detail__c') {
          updateInstrumentDetail(accName, accType, micr, recID);
        } else if (currentSobjectName == 'Disbursement_Details__c') {
          updateDisbursementDetail(accName, accStatus, micr, recID);
        }
      }
    } catch (Exception e) {
      throw throwUIException(e.getLineNumber() + ' : ' + e.getMessage());
    }
  }

  private static MICR_Master__c getMICRRecord(String ifscCode) {
    if (
      ifscCode != null &&
      MICR_Master__c.SObjectType.getDescribe().isAccessible()
    ) {
      List<MICR_Master__c> micrList = [
        SELECT
          Id,
          axisltd_BankName__c,
          axisltd_Bank_Branch_Name__c,
          axisltd_IFSCCode__c
        FROM MICR_Master__c
        WHERE axisltd_IFSCCode__c = :ifscCode
      ];
      if (micrList.isEmpty()) {
        throw throwUIException(
          'No master record found for this IFSC code: ' + ifscCode
        );
      }
      return micrList[0];
    }
    return null;
  }

  private static void updateInstrumentDetail(
    String accName,
    String accType,
    MICR_Master__c micr,
    Id recID
  ) {
    if (Instrument_Detail__c.SObjectType.getDescribe().isUpdateable()) {
      Instrument_Detail__c instruDetail = [
        SELECT
          Id,
          axisltd_Customer_Account__c,
          axisltd_MICR__c,
          axisltd_Bank_Name__c,
          axisltd_Branch__c,
          axisltd_IFSC__c
        FROM Instrument_Detail__c
        WHERE Id = :recID
      ];
      instruDetail.axisltd_DestinationHolder__c = accName;
      if (accType.containsIgnoreCase('current')) {
        instruDetail.axisltd_DestinationBankType__c = 'CURRENT';
      } else if (accType.containsIgnoreCase('saving')) {
        instruDetail.axisltd_DestinationBankType__c = 'SAVING';
      }
      if (micr != null) {
        instruDetail.axisltd_Bank_Name__c = micr.axisltd_BankName__c;
        instruDetail.axisltd_Branch__c = micr.axisltd_Bank_Branch_Name__c;
        instruDetail.axisltd_IFSC__c = micr.axisltd_IFSCCode__c;
        instruDetail.axisltd_MICR__c = micr.Id;
      }
      update instruDetail;
    }
  }

  private static void updateDisbursementDetail(
    String accName,
    String accStatus,
    MICR_Master__c micr,
    Id recID
  ) {
    if (Disbursement_Details__c.SObjectType.getDescribe().isUpdateable()) {
      Disbursement_Details__c disburseDetail = [
        SELECT
          Id,
          axisltd_Beneficiary_Account_Name_Finacle__c,
          axisltd_Account_Status_as_per_Finacle__c,
          axisltd_MICR_Master__c,
          axisltd_BankName__c,
          axisltd_BankBranch__c,
          axisltd_ReceiversIFSCCode__c
        FROM Disbursement_Details__c
        WHERE Id = :recID
      ];
      disburseDetail.axisltd_Beneficiary_Account_Name_Finacle__c = accName;
      disburseDetail.axisltd_BeneficiaryAccountName__c = accName;
      disburseDetail.axisltd_Account_Status_as_per_Finacle__c = accStatus;
      if (micr != null) {
        disburseDetail.axisltd_BankName__c = micr.axisltd_BankName__c;
        disburseDetail.axisltd_BankBranch__c = micr.axisltd_Bank_Branch_Name__c;
        disburseDetail.axisltd_ReceiversIFSCCode__c = micr.axisltd_IFSCCode__c;
        disburseDetail.axisltd_MICR_Master__c = micr.Id;
      }
      update disburseDetail;
    }
  }
  @AuraEnabled
  public static boolean rejectNewInstrument(String LoanApplicationId) {
    List<Instrument_Detail__c> ic = [
      SELECT LoanApplicationId__c, axisltd_Status__c
      FROM Instrument_Detail__c
      WHERE
        LoanApplicationId__c = :LoanApplicationId
        AND axisltd_Status__c = 'Active'
    ];
    if (!ic.isEmpty() && ic.size() > 0) {
      return true;
    }
    return false;
  }

  public class ObjectDetailWrap {
    @AuraEnabled
    public Instrument_Detail__c instruDetails;
    @AuraEnabled
    public Disbursement_Details__c disburseDetails;
    @AuraEnabled
    public String objectName;
  }

  public class ResponseWrap {
    @AuraEnabled
    public List<AxisNanoFetchAccountDetailsWrap.AccountDetails> accList = new List<AxisNanoFetchAccountDetailsWrap.AccountDetails>();
    @AuraEnabled
    public String errorMsg = '';
  }
}
