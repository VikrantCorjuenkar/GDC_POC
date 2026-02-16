public with sharing class AxisNanoGetRecordDetails {
    @AuraEnabled
    public static String getAccountRecord(String loanId) {
         return [select Id, AccountId From ResidentialLoanApplication Where Id =:loanId].AccountId;
    }
}