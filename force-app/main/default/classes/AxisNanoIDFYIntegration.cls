/*******************************************************************************************
* @Name         AxisNanoIDFYIntegration
* @Author       Anjani Vaddadi
* @Description  This class is used in Re-Trigger scenario of IDFY from "Trigger" button.
*******************************************************************************************/
/* MODIFICATION LOG
* Version          Developer             Date               Description
*-------------------------------------------------------------------------------------------
*  1.0             Anjani Vaddadi        03/03/2025         Initial Creation 
--------------------------------------------------------------------------------------------*/
public class AxisNanoIDFYIntegration extends IntegrationInterface
{
	public override String invokeForNANO(Object param)
	{      
        execute(String.valueOf(param));
        return 'SUCCESS'; 
    }    
    public static void execute(String recordId)
    {
        try{
            Schema.SObjectType sobjectType = Id.valueOf(recordId).getSObjectType();
            String sobjectName = sobjectType.getDescribe().getName();
            String customerName = '';
            String panNumber = '';
            if(sobjectName == 'LoanApplicant')
            {
                LoanApplicant applicant = [SELECT axisltd_PAN__c,Name from LoanApplicant WHERE Id = :recordId];
                customerName = applicant.Name;
                panNumber = applicant.axisltd_PAN__c;
            }	
            if(sObjectName == 'Lead')
            {
               Lead lead = [SELECT Id, axisltd_PAN__c,Name from Lead WHERE Id = :recordId];
               customerName = lead.Name;
               panNumber = lead.axisltd_PAN__c;
            }        	
            HL_IDFYIntegration clsIDFYApiCallout = new HL_IDFYIntegration();
            System.debug('$$PanNumber'+panNumber + '$$CustomerName'+customerName+'$$RecordId'+recordId);
            clsIDFYApiCallout.invokeForIDFYNano(panNumber, customerName, recordId);
        }
        catch(Exception ex)
        {
            System.debug('Error occured while re-triggering IDFY'+ex.getMessage());
            LogUtil.log('LOS - Error occured while re-triggering IDFY',ex,null);
        }
        
    }
}