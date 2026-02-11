//To Be used only for fresh load of data for Site content

List <gdc_ms_Site_Content_Page__c> SCP = [Select Id from gdc_ms_Site_Content_Page__c];
delete SCP;