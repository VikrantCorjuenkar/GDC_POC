/**
* @author        Vikrant Corjuenkar
* @description   Invocable Apex class to validate IPA and ELK integrations for Flow
*                Calls the validation method from axisNanoDecisionChangeValidation class
* Modification Log:
*--------------------------------------------------------------------------------------------
* Developer            Date            Description
*--------------------------------------------------------------------------------------------
* Vikrant           [Date]         BB-89011 - Created for IPA and ELK validation in approval flow
*/
public with sharing class AxisNanoIPAELKValidator {
    
    /**
     * @description Invocable method to validate IPA and ELK integrations from Flow
     * @param requests List of FlowRequest objects containing loan application IDs
     * @return List<FlowResponse> with validation results
     */
    @InvocableMethod(
        label='Validate IPA and ELK Integrations before UW Approval'
        description='Validates that IPA and ELK integrations are completed before submitting for approval'
        category='Nano Loan Validation'
    )
    public static List<FlowResponse> validateIntegrationsFromFlow(List<FlowRequest> requests) {
        List<FlowResponse> responses = new List<FlowResponse>();
        
        for (FlowRequest request : requests) {
            FlowResponse response = new FlowResponse();
            
            // Validate input
            if (request.loanApplicationId == null) {
                response.isValid = false;
                response.errorMessage = 'Loan Application ID is required';
                responses.add(response);
                continue;
            }
            
            // Call the validation method from axisNanoDecisionChangeValidation class
            Map<Id, Set<String>> validationResults = axisNanoDecisionChangeValidation.checkIPAAndELKIntegrations(
                new List<Id>{request.loanApplicationId}
            );
            
            // Check if there are any errors for this loan application
            if (validationResults.containsKey(request.loanApplicationId) && 
                !validationResults.get(request.loanApplicationId).isEmpty()) {
                response.isValid = false;
                Set<String> errors = validationResults.get(request.loanApplicationId);
                response.errorMessage = String.join(new List<String>(errors), '\n');
            } else {
                response.isValid = true;
                response.errorMessage = '';
            }
            
            responses.add(response);
        }
        
        return responses;
    }
    
    /**
     * Input wrapper class for Flow invocable method
     */
    public class FlowRequest {
        @InvocableVariable(
            label='Loan Application ID'
            description='ID of the loan application to validate'
            required=true
        )
        public Id loanApplicationId;
    }
    
    /**
     * Output wrapper class for Flow invocable method
     */
    public class FlowResponse {
        @InvocableVariable(
            label='Is Valid'
            description='True if all integrations are completed, False if there are errors'
        )
        public Boolean isValid;
        
        @InvocableVariable(
            label='Error Message'
            description='Validation error message (empty if valid)'
        )
        public String errorMessage;
    }
}