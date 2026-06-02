/**
 * Opportunity example — fromTrigger with bypassIf, maxLoops, and processOnce.
 * Handler logic: stage-change validation for recursive update scenarios.
 */
public inherited sharing class OpportunityHandler extends TriggerHandler {
    public OpportunityHandler() {
        super(OpportunityHandler.class);
    }

    protected override void beforeUpdate() {
        for (Opportunity opp : (List<Opportunity>) changedRecords(Opportunity.StageName)) {
            if (opp.StageName == 'Closed Won' && opp.Amount == null) {
                opp.Amount = 0;
            }
        }
    }

    protected override void afterUpdate() {
        for (Opportunity opp : (List<Opportunity>) changedRecords(Opportunity.StageName)) {
            System.debug(LoggingLevel.FINE, 'OpportunityHandler: stage changed for ' + opp.Id);
        }
    }
}
