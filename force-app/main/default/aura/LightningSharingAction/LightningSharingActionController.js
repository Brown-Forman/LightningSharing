({
    doInit : function(component, event, helper) {
        component.find('navService').navigate({
            type: 'standard__component',
            attributes: {
                componentName : 'c:LightningSharing'
            },
            state: {
                "c__recordId": component.get("v.recordId")
            }
        });
    }
})
