global with sharing class AxisNanoIncomeAssessmentGetApplicants implements Omnistudio.VlocityOpenInterface, callable{
    public Object call(String action, Map<String,Object>args){
        Map<String,Object>input=(Map<String,Object>)args.get('input');
        Map<String,Object>output=(Map<String,Object>)args.get('output');
        Map<String,Object>options=(Map<String,Object>)args.get('options');
        
        return invokeMethod(action, input, output, options);
    }
    
    
    public Boolean invokeMethod(String methodName, Map<String,Object> inputMap, Map<String,Object> outMap, Map<String,Object> options) {
        if(methodName.equalsIgnoreCase('getNanoLoanApplicants')){
            getNanoLoanApplicants(inputMap, outMap, options);
        }
        
        return true;
    }
    
    public static Void getNanoLoanApplicants( Map<String,Object> input, Map<String,Object> output, Map<String,Object> options){
        if( !input.containsKey('ContextId') || (String) input.get('ContextId') == NULL){
            output.put('error','Invalid JSON passed, Please try again!!');
            return;
        }
        List<Map<String, object>> picklistOptions = New List<Map<String, object>>();
        
        String loanAppId = (String) input.get('ContextId');
        Id primaryRecordTypeId = Schema.SObjectType.LoanApplicant.getRecordTypeInfosByDeveloperName().get('axisltd_Primary_Applicant').getRecordTypeId();

        List<LoanApplicant> activeLoanApplicants = [Select Id,Name from LoanApplicant where LoanApplicationId = :loanAppId and axisltd_Inactive__c = false and axisltd_Customer_Type__c =: Nano_Constants.CUSTOMER_TYPE_RESIDENT_FIN and  (Journey_Status__c ='Completed' OR RecordTypeId = :primaryRecordTypeId)];
        if(activeLoanApplicants.size() > 0){
            for(LoanApplicant lap: activeLoanApplicants){
                // options.put(lap.Name,lap.Id);
                Map<String, object> option = New Map<String, object>();
                option.put('value', lap.Name);
                option.put('name', new map<string,string>{'LoanApplicantName'=>lap.Name,'id'=>lap.Id,'name'=>lap.Name});
                picklistOptions.add(option);
            }
            output.put('options', picklistOptions);
        }else{
            output.put('error','No Active Applicants found on loan');
        }
        
        
    }
    
    
}