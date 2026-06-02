/**
 * Account example — concise trigger wiring with fromTrigger() and maxLoops.
 * Handler logic: defaults, field-change detection, delete guard, andFinally.
 */
public inherited sharing class AccountHandler extends TriggerHandler {
    public AccountHandler() {
        super(AccountHandler.class);
    }

    protected override void beforeInsert() {
        for (Account acc : (List<Account>) this.newRecords) {
            if (String.isBlank(acc.Description)) {
                acc.Description = 'Created via TriggerHandler';
            }
        }
    }

    protected override void beforeUpdate() {
        for (Account acc : (List<Account>) changedRecords(Account.AnnualRevenue)) {
            acc.Description = 'Revenue changed';
        }
    }

    protected override void beforeDelete() {
        for (Account acc : (List<Account>) this.oldRecords) {
            if (acc.Name == 'Protected') {
                acc.addError('Cannot delete protected accounts.');
            }
        }
    }

    protected override void afterInsert() {
        System.debug(LoggingLevel.FINE, 'AccountHandler afterInsert: ' + this.newRecords.size());
    }

    protected override void andFinally() {
        System.debug(LoggingLevel.FINE, 'AccountHandler finished: ' + this.triggerOp);
    }
}
