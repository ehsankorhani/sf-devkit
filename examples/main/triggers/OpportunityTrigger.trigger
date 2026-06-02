trigger OpportunityTrigger on Opportunity (before update, after update) {
    new OpportunityHandler()
        .fromTrigger()
        .bypassIf(UserInfo.getUserType() == 'AutomatedProcess')
        .maxLoops(2)
        .processOnce()
        .run();
}
