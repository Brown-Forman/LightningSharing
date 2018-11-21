@isTest
public class Test_LightningSharing {
    static testMethod void unitTest() {
        INFW_TestHelper helper = new INFW_TestHelper();

        User admin = helper.createUser('System Administrator', 'Test', 'Tsakiridis', 'Australia');
        insert admin;

        User usr = helper.createUser('System Administrator', 'TestUser', 'Tsakiridis', 'Australia');
        insert usr;

        Market__c mAU = helper.createMarket('Australia');
        mAU.Vistex_Clearing_Account__c = '0123456789';
        insert mAU;

        Account account1 = helper.createAccount('TestAccount1', mAU.Id, 'Off');
        account1.Status__c = 'Called On';
        insert account1;

        String recordDetails = LightningSharing.sayMyName(account1.Id);
        System.assertNotEquals(null, recordDetails);

        Boolean canIEditPerms = LightningSharing.canIEditPerms(account1.Id);
        System.assertEquals(true, canIEditPerms);

        String objectName = LightningSharing.objectTypeFromId(account1.Id);
        System.assertEquals('Account', objectName);

        try {
            String listOfShares = LightningSharing.doSOSL('TestUser', 'Account');
            System.assertNotEquals(null, listOfShares);

            listOfShares = LightningSharing.getSharings(account1.Id);
            System.assertNotEquals(null, listOfShares);
            
            String sharing = LightningSharing.upsertPerm(usr.Id, account1.Id, 'Edit');
            System.assertNotEquals(null, sharing);

            LightningSharing.deletePerm(usr.Id, account1.Id);

        }catch(AuraHandledException aex) {
            System.debug(aex.getMessage());
        }


    }
}
