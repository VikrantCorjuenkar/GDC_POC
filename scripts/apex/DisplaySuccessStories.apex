List<gdc_ms_Engagement__c> DSS = [SELECT Id,name,gdc_ms_DisplayonSuccessStories__c  FROM gdc_ms_Engagement__c];
for(gdc_ms_Engagement__c DS:DSS){
    DS.gdc_ms_DisplayonSuccessStories__c = true;
}
update DSS;