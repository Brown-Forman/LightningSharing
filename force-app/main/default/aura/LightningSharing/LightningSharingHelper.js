({
    nav : function(component, recordId) {
        component.find("navService").navigate({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: "view"
            }
        });        
    },

    reload : function(component) {
        component.set("v.isWorking", true);

        let helper = this;
        let action = component.get("c.getSharings");
        action.setStorable();
        action.setParams({
            "recordId" : component.get("v.recordId")
        });
        action.setCallback(this, function(response) {
            let state = response.getState();
            if (state === "SUCCESS") {
                let shares = JSON.parse(response.getReturnValue());
                console.log('[LightningSharing.helper.reload] shares', shares);
                component.set("v.shares", shares);
                component.set("v.selectedTab", "current");
            } else if (state === "ERROR") {
                let appEvent = $A.get("e.c:handleCallbackError");
                appEvent.setParams({
                    "errors" : response.getError()
                });
                appEvent.fire();
                helper.nav(component, component.get("v.recordId"));
            }

            component.set("v.isWorking", false);

        });
        $A.enqueueAction(action);
    },

    commonUpsert : function(component, id, level) {
        let helper = this;
        let action = component.get("c.upsertPerm");
        action.setParams({
            "UserOrGroupID" : id,
            "recordId" : component.get("v.recordId"),
            "level" : level 
        });
        action.setCallback(this, function(response) {
            let state = response.getState();
            if (state === "SUCCESS") {
                var sharedWithName = "";
                var results = component.get("v.results");
                for(var i = 0; i < results.length; i++) {
                    if (results[i].Id == id) {
                        sharedWithName = results[i].Name;
                        results.splice(i, 1);                        
                        break;
                    }
                }
                component.set("v.results", results);

                let searchObject = component.get("v.sObjectName");
                
                component.find("notiflib").showNotice({
                    "variant" : "info",
                    "header" : "Info",
                    "message" : searchObject + " has been shared with " + sharedWithName,
                    closeCallback : function() {
                        helper.reload(component);
                    }
                });
            } else if (state === "ERROR") {
                let appEvent = $A.get("e.c:handleCallbackError");
                appEvent.setParams({
                    "errors" : response.getError()
                });
                appEvent.fire();
            }
        });
        $A.enqueueAction(action);
    },

    translateTypes : function(userType) {
        if (userType === 'PowerCustomerSuccess') { return 'Customer + Sharing'; }
        else if (userType === 'PowerPartner') { return 'Partner'; }
        else if (userType === 'CustomerSuccess') { return 'Customer'; }
        else if (userType === 'CsnOnly') { return 'Chatter'; }
        else if (userType === 'CSPLitePortal') { return 'High Volume Customer'; }
        else { return userType; }
    },

    getStuff : function(component) {
        let sobj = component.get("v.sObjectName");

        let output = {};
        output.lookupField = "ParentId";
        output.accessLevelField = "AccessLevel";

        if (sobj.includes('__c')) {
            output.objectName = sobj.replace('__c', '__Share');
        } else {
            output.objectName = sobj+'Share';
        }

        if (sobj === 'Account' || sobj === 'User') {
            output.lookupField = sobj + 'Id';
            outoput.accessLevelField = sobj + "AccessLevel";
        }

        return output;
    },

    doSearch : function(component) {
        component.set("v.isSearching", true);

        let helper = this;
        let searchString = component.find("search").get("v.value");
		if (searchString.length < 1) {
			component.set("v.results", []);
		}

        let searchObject = component.find("searchPicklist").get("v.value");
		let action = component.get("c.doSOSL");
		action.setParams({
			"searchString" : searchString,
			"objectType" : searchObject
		});
		action.setCallback(this, function(response) {
			let state = response.getState();
			if (state === "SUCCESS") {
                let result = JSON.parse(response.getReturnValue());
                console.log('[LightningSharing.helper.doSearch] result', result);
				if (searchObject === 'User' || searchObject === 'user') {
					let correctedResults = [];
					for(let u of result) {
						u.Type = helper.translateTypes(u.UserType);
						correctedResults.push(u);
					}
					component.set("v.results", correctedResults);
				} else {
					component.set("v.results", result);
				}
			} else if (state === "ERROR") {
				let appEvent = $A.get("e.c:handleCallbackError");
				appEvent.setParams({
					"errors" : response.getError()
				});
				appEvent.fire();
            }
            
            component.set("v.isSearching", false);            
		});
		$A.enqueueAction(action);

    }
})