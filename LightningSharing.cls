global without sharing class LightningSharing {
    global class SharingPermsException extends Exception{}

    class RecordStuff {
        String recordName               { get; set; }
        String objectType               { get; set; }
    }

    global class SharingHolder {
        global String UserOrGroupName   { get; set; }
        global String SubType           { get; set; }
        global String UserOrGroupType   { get; set; }
        global String UserOrGroupID     { get; set; }
        global String AccessLevel       { get; set; }
        global String RowCause          { get; set; }
    }

    @AuraEnabled
    public static string sayMyName(id recordId){
        String nameField;

        Schema.SObjectType token = recordId.getSobjectType();
        for (Schema.SObjectField dfr:token.getDescribe().fields.getMap().values()) {
            if (dfr.getDescribe().isNameField()) {
                nameField = dfr.getDescribe().getName();
            }
        }

        String query = 'SELECT ' + nameField + ' FROM ' + recordId.getSobjectType() + ' WHERE Id = \'' + recordId + '\'';
        RecordStuff rs = new RecordStuff();
        rs.recordName = String.valueOf(Database.query(query)[0].get(nameField));
        rs.objectType = String.valueOf(recordId.getSobjectType().getDescribe().getLabel());

        return JSON.serialize(rs);
    }

    @AuraEnabled
    global static boolean canIEditPerms(Id recordId) {
        try {
            String query = 'SELECT RecordId, HasDeleteAccess, HasAllAccess FROM UserRecordAccess WHERE RecordId = \'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\' AND UserId = \'' + UserInfo.getUserId() + '\''; 
            sObject o = Database.query(query);
            if ((Boolean)o.get('HasDeleteAccess') || (Boolean)o.get('HasAllAccess')) {
                return true;
            }
        } catch(System.QueryException ex) {
            return false;
        }

        return false;
    }

    @AuraEnabled
    global static void deletePerm(Id UserOrGroupID, Id recordId) {
        Schema.DescribeSObjectResult describe = getSharingDescribe(recordId);

        if (!describe.isDeletable() || !describe.isAccessible()) {
            throw new AuraHandledException('You don\'t have the proper permissions for this action');
        }

        String query = buildQuery(recordId);
        query = query + ' AND UserOrGroupId = \'' + String.escapeSingleQuotes(UserOrGroupID) + '\'';

        List<sObject> existing = Database.query(query);
        delete existing;
      
    }

    @AuraEnabled
    global static string upsertPerm(Id UserOrGroupID, Id recordId, String level) {
        Schema.DescribeSObjectResult describe = getSharingDescribe(recordId);
        level = String.escapeSingleQuotes(level);

        if (!canIEditPerms(recordId)) {
            throw new AuraHandledException('Only the record owner or administrators can modify permissions');
        }

        if (UserOrGroupID.getSObjectType() == Schema.UserRole.getSObjectType()) {
            // It's a role.. Find the matching group
            List<Group> matchingGroups = [SELECT Id, Name, Type FROM Group WHERE RelatedId =:UserOrGroupID AND Type = 'Role'];
            if (matchingGroups.size() > 1) {
                throw new AuraHandledException('There are multiple groups for that role');
            }

            UserOrGroupID = matchingGroups[0].Id;
        }

        String query = buildQuery(recordId);
        query += ' AND UserOrGroupID = \'' + String.escapeSingleQuotes(String.valueOf(UserOrGroupID)) + '\'';
        
        List<sObject> existing = Database.query(query);
        String sobj = objectTypeFromId(recordId);
        if (existing.size() > 0) {
            if (!describe.isUpdateable() || !describe.fields.getMap().get(getAccessLevelField(sobj)).getDescribe().isUpdateable()) {
                throw new AuraHandledException('Only the record owner or administrators can modify permissions');
            }

            existing[0].put(getAccessLevelField(sobj), level);
            update existing;

            return JSON.serialize(existing);
        } else {
            Map<String, Schema.SObjectField> fields = describe.fields.getMap();
            if (!describe.isCreateable() || !fields.get(getAccessLevelField(sobj)).getDescribe().isCreateable() || !fields.get(getLookupField(sobj)).getDescribe().isCreateable() || !fields.get('UserOrGroupID').getDescribe().isCreateable()) {
                throw new AuraHandledException('Only the record owner or administrators can create new permissions');
            }

            Schema.SObjectType newObj = Schema.getGlobalDescribe().get(getSharingTableName(sobj));
            sObject share = newObj.newSObject();

            share.put(getAccessLevelField(sobj), level);
            share.put(getLookupField(sobj), recordId);
            share.put('UserOrGroupID', String.escapeSingleQuotes(String.valueOf(UserOrGroupID)));

            if (objectTypeFromId(recordId) == 'Account') {
                share.put('CaseAccessLevel', level);
                share.put('OpportunityAccessLevel', level);
            }
            insert share;
            return JSON.serialize(share);
        }
    }

    @AuraEnabled
    global static string doSOSL(String searchString, String objectType) {
        searchString = String.escapeSingleQuotes(searchString);
        objectType = String.escapeSingleQuotes(objectType);

        Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(objectType).getDescribe();

        if (!describe.isQueryable() || !describe.isAccessible()) {
            throw new AuraHandledException('You don\'t have the proper permissions for this action');
        }

        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
        for(Schema.SObjectField field : fieldMap.values()) {
            if (field.getDescribe().isNameField()) {
                if (!field.getDescribe().isAccessible()) {
                    throw new AuraHandledException('You don\'t have the proper permissions for this action');
                }
            }
        }

        String sosl = 'FIND \'*' + searchString + '*\' IN NAME FIELDS RETURNING ' + getReturning(objectType) + ' LIMIT 200';
        List<List<SObject>> results = Search.query(sosl);

        List<SObject> output = new List<SObject>();
        for(List<SObject> result : results) {
            output.addAll(result);
        }

        return JSON.serialize(output);
    }

    @TestVisible
    private static String getReturning(String objectType) {
        if (!User.Id.getDescribe().isAccessible() || !User.Name.getDescribe().isAccessible() || !User.UserType.getDescribe().isAccessible() || !Group.Id.getDescribe().isAccessible() || !Group.Name.getDescribe().isAccessible()) {
            throw new AuraHandledException('You don\'t have the required permissions for this action');
        }

        if (objectType == 'User') {
            return 'User(Id, Name, UserType WHERE UserType IN (\'Standard\', \'PowerCustomerSuccess\',\'PowerPartner\'))';
        }

        if (objectType == 'Group') {
            return objectType + '(Id, Name, Type)';
        } else {
            return objectType + '(Id, Name)';
        }        
    }

    @AuraEnabled
    global static String objectTypeFromId(Id recordId) {
        Schema.SObjectType token = recordId.getSobjectType();
        Schema.DescribeSObjectResult dr = token.getDescribe();
        return dr.getName();
      
    }

    @AuraEnabled(cacheable=true)
    global static String getSharings(Id recordId) {
        if (!canIEditPerms(recordId)) {
            throw new AuraHandledException('Only the record owner or administrator can access permissions');
        }

        if (!sharingExists(objectTypeFromId(recordId))) {
            throw new AuraHandledException('Sharing Settings must be private or public read/write to enable manual sharing');
        }

        List<SObject> results = Database.query(buildQuery(recordId));
        List<SharingHolder> output = new List<SharingHolder>();

        Set<Id> groupAndUserIDs = new Set<Id>();
        Set<Id> RoleIds = new Set<Id>();

        for (SObject so : results) {
            SharingHolder sh = new SharingHolder();
            sh.RowCause = String.valueOf(so.get('RowCause'));
            sh.AccessLevel = String.valueOf(so.get(getAccessLevelField(objectTypeFromId(recordId))));
            sh.UserOrGroupID = String.valueOf(so.get('UserOrGroupID'));
            groupAndUserIDs.add(sh.UserOrGroupID);
            output.add(sh);
        }

        if (!User.Id.getDescribe().isAccessible() || !User.Name.getDescribe().isAccessible() || !User.UserType.getDescribe().isAccessible() || !Group.Id.getDescribe().isAccessible() || !Group.Name.getDescribe().isAccessible() || !Group.Type.getDescribe().isAccessible()) {
            throw new AuraHandledException('You don\'t have the required permissions for this action');
        }

        Map<Id, User> userMap = new Map<Id, User>([SELECT Name, UserType FROM User WHERE Id IN :groupAndUserIDs]);
        Map<Id, Group> groupMap = new Map<Id, Group>([SELECT Name, Type, RelatedId FROM Group WHERE Id IN :groupAndUserIDs]);
        for (Group g : groupMap.values()) {
            if (g.RelatedId != null) {
                RoleIds.add(g.RelatedId);
            }
        }

        Map<Id, UserRole> RoleMap = new Map<Id, UserRole>([SELECT Name FROM UserRole WHERE Id IN :RoleIds]);
        for (SharingHolder sh : output) {
            if (UserMap.get(sh.UserOrGroupID) != null) {
                sh.UserOrGroupType = 'User';
                sh.UserOrGroupName = userMap.get(sh.UserOrGroupID).Name;
                sh.SubType = huh(UserMap.get(sh.UserOrGroupID).UserType);                
            } else if (GroupMap.get(sh.UserOrGroupID) != null) {
                sh.UserOrGroupType = 'Group';
                sh.SubType = GroupMap.get(sh.UserOrGroupID).Type;
                sh.UserOrGroupName = GroupMap.get(sh.UserOrGroupID).Name;
                if (sh.SubType.contains('Role')) {
                    sh.UserOrGroupName = RoleMap.get(GroupMap.get(sh.UserOrGroupID).RelatedId).Name;
                }
            }            
        }

        return JSON.serialize(output);
    }

    @TestVisible
    private static String buildQuery(Id recordId) {
        String sobj = objectTypeFromId(recordId);
        String lookupField = getLookupField(sobj);
        String accessField = getAccessLevelField(sobj);

        Schema.DescribeSObjectResult describe = getSharingDescribe(recordId);
        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
        if (!describe.isAccessible() || !fieldMap.get('Id').getDescribe().isAccessible() || !fieldMap.get('RowCause').getDescribe().isAccessible() || !fieldMap.get('UserOrGroupId').getDescribe().isAccessible() || !fieldMap.get(accessField).getDescribe().isAccessible() || !fieldMap.get(lookupField).getDescribe().isAccessible()) {
            throw new AuraHandledException('You don\'t have the required permissions for this action');
        }

        String sharingTableName = getSharingTableName(sobj);
        String query = 'SELECT Id, RowCause, UserOrGroupId, ' + accessField + ' FROM ' + sharingTableName + ' WHERE ' + lookupField + ' = \'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\'';
        return query;
    }

    @TestVisible
    private static String huh(String userType) {
        if (userType == 'PowerCustomerSuccess') { return 'Customer Plus (with Sharing)'; }
        else if (userType == 'PowerPartner') { return 'Partner'; }
        else if (userType == 'CustomerSuccess') { return 'Customer'; }
        else if (userType == 'CsnOnly') { return 'Chatter'; }
        else if (userType == 'CSPLitePortal') { return 'High Volume Customer'; }
        else { return userType; }
    }

    private static Boolean isStandard(String sobj) {
        if (sobj == 'Account' || sobj == 'Contact' || sobj == 'User') {
            return true;
        }

        return false;
    }

    @TestVisible
    private static String getLookupField(String sobj) {
        if (isStandard(sobj)) {
            return sobj + 'Id';
        } else { 
            return 'ParentId';
        }
    }

    @TestVisible
    private static String getAccessLevelField(String sobj) {
        if (isStandard(sobj)) {
            return sobj + 'AccessLevel';
        } else {
            return 'AccessLevel';
        }
    }

    @TestVisible
    private static String getSharingTableName(String sobj) {
        if (sobj.contains('__c')) {
            return sobj.replace('__c', '__Share');
        } else {
            return sobj + 'Share';
        }
    }

    @TestVisible
    private static Schema.DescribeSObjectResult getSharingDescribe(Id recordId) {
        try {
            String sharingName = getSharingTableName(objectTypeFromId(recordId));
            return Schema.getGlobalDescribe().get(sharingName).getDescribe();
        } catch(Exception ex) {
            throw new AuraHandledException('There is no sharing table for that object. Are you SURE you changed the sharing setting to PRIVATE or READ?');
        }
    }

    @TestVisible
    private static Boolean sharingExists(String sobj) {
        String sharingTableName = getSharingTableName(sobj);

        if (sobj.contains('__c')) {
            Map<String, Schema.SObjectType> tokens = Schema.getGlobalDescribe();
            if (tokens.containsKey(sharingTableName) || tokens.containsKey('ltngsharing__'+sharingTableName)) {
                return true;
            }
        } else {
            String query = 'SELECT COUNT() FROM ' + sharingTableName;
            try {
                Integer count = Database.countQuery(query);
                if (count > 0) {
                    return true;
                } else {
                    return false;
                }
            } catch(Exception ex) {
                System.debug(ex);
            }

            return false;
        }

        return false;
    }
}