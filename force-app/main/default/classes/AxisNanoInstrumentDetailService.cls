/*******************************************************************************************
* @Name         AxisNanoInstrumentDetailService 
* @Author       
* @Description  This is a service class for InstrumentDetailTrigger
*******************************************************************************************/
public class AxisNanoInstrumentDetailService implements ServiceInterface{
  public void beforeInsert(List<sObject> newRecordList){
  }
  public void afterInsert(List<sObject> newRecordList,Map<id,sObject> newRecordMap){
    // RepaymentChecklistCreationHelper.createIntegrationChecklistEngine( newRecordList, newRecordMap );
      //AxisNanoInstrumentDetailTriggerHelper.validateOneInstrumentDetailPerLA( newRecordList) ;
      if(!newRecordList.isEmpty()){
        AxisNanoInstrumentDetailTriggerHelper.createIntegrationChecklistEngine( newRecordList, newRecordMap );
        AxisNanoPennyDropIntegration.initiatePennyDrop((List<Instrument_Detail__c>) newRecordList) ;
        InstrumentDetailsDocumentChecklistItems.validateAndUpdateChecklistItems(newRecordList, null);

      }
    
    
  }
  public void beforeUpdate(List<sObject> newRecordList,Map<id,sObject> oldRecordMap,Map<id,sObject> newRecordMap){
    if(!newRecordList.isEmpty()){
    AxisNanoInstrumentDetailTriggerHelper.validatePennyDrop((List<Instrument_Detail__c>) newRecordList,oldRecordMap);

    //Defect fixes for BB-70817 - Vikrant
    AxisNanoInstrumentDetailTriggerHelper.makeInstrumentStatusPending(oldRecordMap,newRecordMap);
    }
  }
  public void afterUpdate(List<sObject> newRecordList,Map<id,sObject> oldRecordMap,Map<id,sObject> newRecordMap){
    //CheckList changes to 'Retry Required' if the Loan purpose is changed
    if(!newRecordList.isEmpty()){
      AxisNanoInstrumentDetailTriggerHelper.updateChecklistStatus(oldRecordMap,newRecordMap);
      InstrumentDetailsDocumentChecklistItems.validateAndUpdateChecklistItems(newRecordList, oldRecordMap);

    }
    
  }
  public void beforeDelete(Map<id,sObject> oldRecordMap){
  }
  public void afterDelete(Map<id,sObject> oldRecordMap){
  }
  public void afterUndelete(Map<id,sObject> newRecordMap){
  }   
}