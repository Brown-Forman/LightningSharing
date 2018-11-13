({
	doInit : function(component, event, helper) {
		let pageRef = component.get("v.pageReference");
		component.set("v.recordId", pageRef.state.c__recordId);
		helper.reload(component);

		var action = component.get("c.sayMyName");
		action.setParams({
			recordId : component.get("v.recordId")
		});
		action.setCallback(this, function(response) {
			let state = response.getState();
			if (state === "SUCCESS") {
				let rs = JSON.parse(response.getReturnValue());
				console.log('[LightningSharing.controller.doInit.sayMyName] returned data', rs);
				component.set("v.recordName", rs.recordName);
				component.set("v.sObjectName", rs.objectType);
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

	stopProp : function(component, event) {
		event.stopPropagation();
	},

	goBack : function(component) {
		if (sforce) {
			sforce.one.back();
		} else {
			helper.nav(component, component.get("v.recordId"));
		}
	},

	navToUser : function(component, event, helper) {
		helper.nav(component, event.target.id);
	},
	navToRecord : function(component, event, helper) {
		helper.nav(component, component.get("v.recordId"));
	},

	delete : function(component, event, helper) {
		let action = component.get("c.deletePerm");
		action.setParams({
			"UserOrGroupID" : event.target.id,
			"recordId" : component.get("v.recordId")
		});
		action.setCallback(this, function(response) {
			let state = response.getState();
			if (state === "SUCCESS") {
				helper.reload(component);
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

	setRead : function(component, event, helper) {
		let id = event.target.id;
		helper.commonUpsert(component, id, "Read");
	},

	setReadWrite : function(component, event, helper) {
		let id = event.target.id;
		helper.commonUpsert(component, id, "Edit");
	},

	search : function(component, event, helper) {
    	let isEnterKey = event.keyCode === 13;
        console.log('[LightningSharing.controller.search] keycode', event.keyCode);
        if (isEnterKey) {
            helper.doSearch(component);
        }
	},

	handleSearchButtonClick : function(component, event, helper) {
		console.log('[LightningSharing.controller.handleSearchButtonClick] isSearching', component.get("v.isSearching"));
        if (!component.get("v.isSearching")) {
	        helper.doSearch(component);                    
        }

	}
})