/**
 * Contact example — explicit trigger wiring and trackLimits.
 * Handler logic: changedRecords helper and transaction state bag (before → after).
 */
public inherited sharing class ContactHandler extends TriggerHandler {
    private static final String STATE_EMAIL_CHANGED = 'emailChangedIds';

    public ContactHandler() {
        super(ContactHandler.class);
    }

    protected override void beforeUpdate() {
        Set<Id> emailChanged = new Set<Id>();
        for (Contact con : (List<Contact>) changedRecords(Contact.Email)) {
            emailChanged.add(con.Id);
        }
        if (!emailChanged.isEmpty()) {
            putState(STATE_EMAIL_CHANGED, emailChanged);
        }
    }

    protected override void afterUpdate() {
        if (!hasState(STATE_EMAIL_CHANGED)) {
            return;
        }
        Set<Id> ids = (Set<Id>) getState(STATE_EMAIL_CHANGED);
        System.debug(LoggingLevel.FINE, 'ContactHandler: email changed for ' + ids.size() + ' record(s)');
    }
}
