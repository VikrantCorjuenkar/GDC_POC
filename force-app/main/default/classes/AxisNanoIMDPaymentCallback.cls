@RestResource(urlMapping='/PaymentCallback/*')
global without sharing class AxisNanoIMDPaymentCallback {

    @HttpPost
    global static void handleCallback() { 

             // Use RestContext to get the request and response objects
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        System.debug('@@@ AxisNanoIMDPaymentCallback class called');
        axisltd_Integration_Master__c masterRecord = [SELECT Id,axisltd_Encryption_Key__c, axisltd_External_Id__c
                                                        FROM axisltd_Integration_Master__c 
                                                        WHERE axisltd_External_Id__c = :IntegrationConstants.IMD_Callback
                                                        AND axisltd_Active__c = True
                                                        WITH SYSTEM_MODE
                                                        ORDER BY Name ASC
                                                        LIMIT 1];

        String privateStoredKey = masterRecord.axisltd_Encryption_Key__c;

        CallbackResponse callbackResp = new CallbackResponse();
        callbackResp.encrypted = true;

        try {
            // Get the JSON string from the request body
            String requestBody = req.requestBody.toString();

            // Deserialize the JSON into a a custom Apex class.
            // It's a good practice to create an inner class to represent the JSON structure.
            CallbackRequest callbackRequest = (CallbackRequest) JSON.deserialize(requestBody, CallbackRequest.class);
            
            // Log the incoming request for debugging and auditing purposes
            System.debug('Incoming Payment Callback Request: ' + requestBody);

            string decryptedRequest = '';
            string requestMessage = callbackRequest.requestMessage;
            FreechargeCallBackResponse reqData = new FreechargeCallBackResponse();

            if(callbackRequest.encrypted){
                decryptedRequest = CryptoUtils.decryptData(
                    EncodingUtil.base64Decode(requestMessage),
                    EncodingUtil.convertFromHex(privateStoredKey)
                );
                reqData = (FreechargeCallBackResponse)JSON.deserialize(decryptedRequest, FreechargeCallBackResponse.class); 
            }else{
                decryptedRequest = requestMessage;
             	reqData = (FreechargeCallBackResponse)JSON.deserialize(requestMessage, FreechargeCallBackResponse.class);      
            }

            String transactionId =  reqData.merchantTxnId;
            List<axisltd_Payment__c> payment = [Select Id, axisltd_Loan_Application__c, axisltd_Status__c, axisltd_Transaction_Id__c FROM axisltd_Payment__c WHERE axisltd_Transaction_Id__c = :transactionId WITH SYSTEM_MODE LIMIT 1];

             
            if(!payment.isEmpty()){
                axisltd_Integration_Checklist__c parentChecklist;
                List<axisltd_Integration_Checklist__c> parentChecklists = [
                    SELECT Id, axisltd_Retry_Count__c,axisltd_Functional_Status__c,RecordTypeId,axisltd_Parent_Checklist__c,
                    axisltd_Integration_Master__c,axisltd_Status__c,axisltd_Loan_Application__c
                    FROM axisltd_Integration_Checklist__c
                    WHERE axisltd_Parent_Checklist__c =null 
                    AND axisltd_Integration_Master__r.axisltd_External_Id__c =: masterRecord.axisltd_External_Id__c
                    AND axisltd_Loan_Application__c =: payment[0].axisltd_Loan_Application__c
                    WITH SYSTEM_MODE
                ];
                if(!parentChecklists.isEmpty()){
                    parentChecklist = parentChecklists[0];
                }
                else{
                    //Creating parent checklist if it doesnt exist
                    parentChecklist = new axisltd_Integration_Checklist__c();
                    parentChecklist.RecordTypeId = Schema.SObjectType.axisltd_Integration_Checklist__c.getRecordTypeInfosByDeveloperName().get('NANO').getRecordTypeId();
                    parentChecklist.axisltd_Integration_Master__c = masterRecord.Id;
                    parentChecklist.axisltd_Loan_Application__c = payment[0].axisltd_Loan_Application__c;
                    parentChecklist.axisltd_Functional_Status__c = 'Pending';
                    //parentChecklist.axisltd_Status__c = '';
                    parentChecklist.axisltd_Retry_Count__c = 0;

                    insert as system parentChecklist;
                    

                }

                String status;
                String responseBody;

                // Process the successful transaction
                if (reqData.statusMessage == 'SUCCESS' && 
                    reqData.statusCode == 'SPG-0000') {

                    payment[0].axisltd_Status__c = Nano_Constants.PAYMENT_COMPLETE;
                    update payment;

                    
                    // Respond to the external service to acknowledge receipt
                    status = 'Completed';
                    res.statusCode = 200;
                    responseBody = '{"status": "success", "message": "Callback received and processed"}';

                    callbackResp.responseMessage = CryptoUtils.encryptDataHex(responseBody, privateStoredKey);
                    res.responseBody = Blob.valueOf(JSON.serialize(callbackResp,true));
                    //res.responseBody = Blob.valueOf(responseBody);
                } else {
                    // Handle cases where the transaction was not successful
                    System.debug('Transaction was not successful. Status: ' + reqData.statusCode);

                    payment[0].axisltd_Status__c = Nano_Constants.PAYMENT_FAILED;
                    update as system payment;
                    
                    // Here, you would update the loan record to reflect the failed payment status.
                    // You might also log the failure and trigger a different workflow.
                    
                    status = 'Failed';
                    res.statusCode = 200; // Still return 200 to acknowledge the callback, but with an error message
                    responseBody = '{"status": "error", "message": "Transaction was not successful"}';

                    callbackResp.responseMessage = CryptoUtils.encryptDataHex(responseBody, privateStoredKey);
                    res.responseBody = Blob.valueOf(JSON.serialize(callbackResp,true));
                    //res.responseBody = Blob.valueOf(responseBody);
                }

                if(parentChecklist!=null){

                    List<axisltd_Integration_Checklist__c> checklistRecordsToInsert = new List<axisltd_Integration_Checklist__c>();

                    axisltd_Integration_Checklist__c childChecklist = new axisltd_Integration_Checklist__c();
                    childChecklist.RecordTypeId = parentChecklist.RecordTypeId;
                    childChecklist.axisltd_Integration_Master__c = parentChecklist.axisltd_Integration_Master__c;
                    childChecklist.axisltd_Loan_Application__c = parentChecklist.axisltd_Loan_Application__c;
                    childChecklist.axisltd_Parent_Checklist__c = parentChecklist.Id;
                    childChecklist.axisltd_Functional_Status__c = status == 'Failed' ? 'Failed' : 'Completed';
                    childChecklist.axisltd_Request_Initiated_At__c = DateTime.Now();
                    childChecklist.axisltd_Response_Received_At__c = DateTime.Now();
                    childChecklist.axisltd_Request__c = decryptedRequest;
                    childChecklist.axisltd_Response__c = responseBody;
                    childChecklist.axisltd_Status__c = status == 'Failed' ? 'Failed' : 'Success';
                    checklistRecordsToInsert.add(childChecklist);

                    parentChecklist.axisltd_Retry_Count__c = parentChecklist.axisltd_Retry_Count__c!=null ? parentChecklist.axisltd_Retry_Count__c+1:1;
                    parentChecklist.axisltd_Functional_Status__c = status == 'Failed' ? 'Failed' : 'Completed';
                    parentChecklist.axisltd_Status__c = status == 'Failed' ? 'Failed' : 'Success';
                    checklistRecordsToInsert.add(parentChecklist);
                    
                    if(!checklistRecordsToInsert.isEmpty()){
                        upsert checklistRecordsToInsert;
                    }
                }
            }
            else{
                res.statusCode = 500;

                callbackResp.responseMessage = CryptoUtils.encryptDataHex('{"status": "error", "message": "No Payment records found for this merchantTxnId"}', privateStoredKey);
                res.responseBody = Blob.valueOf(JSON.serialize(callbackResp,true));
                //res.responseBody = Blob.valueOf('{"status": "error", "message": "No Payment records found for this merchantTxnId"}');
            }

        } catch (Exception e) {
            System.debug('Error processing payment callback: ' + e.getMessage() + ' at line ' + e.getLineNumber());
            LogUtil.log('LOS - IMD callback failed',e,null);
            
            // Set the HTTP status code to an error code (e.g., 500 Internal Server Error)
            // and return a JSON error message.
            res.statusCode = 500;
            callbackResp.responseMessage = CryptoUtils.encryptDataHex('{"status": "error", "message": "An internal server error occurred"}', privateStoredKey);
            res.responseBody = Blob.valueOf(JSON.serialize(callbackResp,true));
            //res.responseBody = Blob.valueOf('{"status": "error", "message": "An internal server error occurred"}');
        }
    }
    
    // Inner class to represent the structure of the incoming JSON request
    global class CallbackRequest {
        global Boolean encrypted;
        global String productCode;
        global String requestMessage;
    }
    
    // Inner class for the nested freechargeCallBackResponse JSON object
    /*
    global class FreechargeCallBackResponse {
        global Integer amount;
        global String currencyType;
        global Integer handlingFee;
        global String merchantTxnId;
        global String mode;
        global String signature;
        global String statusCode;
        global String statusMessage;
        global String subMode;
        global Integer taxAmount;
        global String txnReferenceId;
        global String txnType;
        global String txnState;
        global String merchantId;
    }*/

    global class FreechargeCallBackResponse {
        global Integer amount;
        global String currencyType;
        global Integer handlingFee;
        global String merchantTxnId;
        global String mode;
        global String signature;
        global String statusCode;
        global String statusMessage;
        global String subMode;
        global Integer taxAmount;
        global String txnReferenceId;
        global String merchantId;
    }

    global class CallbackResponse {
        global Boolean encrypted;
        global String responseMessage;
    }
     
    
}