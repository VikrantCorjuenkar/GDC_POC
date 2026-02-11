/*
*
* ONLY  to be used in dev instances 
*
*/

//Trigger on gdc_ms_Site_Content_Page__c 
trigger SitePageTest on gdc_ms_Site_Content_Page__c (after insert) {
    gdc_Ms_TestEncrypt.test(Trigger.New);
}
//Controller for above trigger
public class gdc_Ms_TestEncrypt {
    public static void test(List<gdc_ms_Site_Content_Page__c> SitePage){
        gdc_ms_Site_Content_Page__c SitePageRecord = [Select Id,gdc_ms_ContentId__c from gdc_ms_Site_Content_Page__c WHERE Id=:SitePage[0].Id];
        Blob key = Crypto.generateAesKey(128);
        String UniqueKey = EncodingUtil.urlEncode(EncodingUtil.base64Encode(Crypto.encryptWithManagedIV('AES128', Key, Blob.valueOf(SitePageRecord.Id))),'UTF-8');
		System.debug(UniqueKey);
        SitePageRecord.gdc_ms_ContentId__c = UniqueKey;
        database.update(SitePageRecord);
    }
}
