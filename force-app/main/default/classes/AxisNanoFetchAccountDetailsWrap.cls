/*******************************************************************
* @description       : AxisNanoFetchAccountDetailsWrap --> wrapper class for Fetch Account Details integration resposnse
* @author            : Surag Lunagariya
* @TestClass		 : 
* @last modified on  : 23-Feb-2024
* @last modified by  : Surag Lunagariya
********************************************************************/
public class AxisNanoFetchAccountDetailsWrap {
	@AuraEnabled public Data Data;

	public class LeiDetails {
		public Integer recordCount;
		public Boolean matchFound;
		public String leiNumber;
		public String leiExpiryDate;
		public String customerType;
	}

	public class AccountDetails {
		@AuraEnabled public String customerId;
		public String bayUserId;
		@AuraEnabled public String branchId;
		@AuraEnabled public String acid;
		public String currencyCode;
		@AuraEnabled public String schemType;
		@AuraEnabled public String schemCode;
		@AuraEnabled public String productDescription;
		public Double clearBalanceAmount;
		public Double unClearBalanceAmount;
		public String openDate;
		@AuraEnabled public String accountName;
		public String nickName;
		public String interestRate;
		public String xferInd;
		@AuraEnabled public String deleteFlag;
		public String rModId;
		public String rModTime;
		public String rCreId;
		public String rCreTime;
		public String createdBy;
		public String createdOn;
		public String updatedBy;
		public String updatedOn;
		public String accountStatus;
		public String deviceUniqueId;
		@AuraEnabled public String bankId;
		public String mbNickName;
		public String syncType;
		public String accountDesc;
		public String custConst;
		@AuraEnabled public String relationship;
		@AuraEnabled public String mop;
		@AuraEnabled public String ifscCode;
		public String custType;
		public String sysUpdateDate;
		public String closeFlag;
		public String closeDate;
		public String ownership;
		public String acctRPTCode;
		public Double monAvgBal;
		@AuraEnabled public String branchName;
		@AuraEnabled public String acctFrezStatus;
		public Integer ledgerNo;
		public String pbfFlag;
		public String acctManager;
		@AuraEnabled public String status;
		public String areaType;
		public String priority;
		public String burgundy;
		public String labelCode;
		public String baseLoanAccount;
		public Integer sanctionLimit;
		public String typeOfAdvance;
		public String proposalNum;
		public String proposalLabel;
		public String disbursementMode;
		public String lastDateTran;
		public String isSignAvailable;
		public Integer pendingTransactionCount;
	}

	public class Data {
		public List<AccountDetails> AccountDetails;
		public LeiDetails LeiDetails;
	}

	
	public static AxisNanoFetchAccountDetailsWrap parse(String json) {
		return (AxisNanoFetchAccountDetailsWrap) System.JSON.deserialize(json, AxisNanoFetchAccountDetailsWrap.class);
	}
}