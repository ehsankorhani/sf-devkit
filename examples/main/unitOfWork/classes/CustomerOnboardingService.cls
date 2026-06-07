/**
 * Service-layer example — onboard a customer (Account + Contacts + Opportunity)
 * in a single Unit of Work commit with a post-commit side effect.
 */
public inherited sharing class CustomerOnboardingService {

    private static final Schema.SObjectField CONTACT_ACCOUNT_ID = Contact.SObjectType.fields.AccountId;
    private static final Schema.SObjectField OPPORTUNITY_ACCOUNT_ID = Opportunity.SObjectType.fields.AccountId;

    public class OnboardingRequest {
        public String accountName;
        public List<Contact> contacts = new List<Contact>();
        public Opportunity opportunity;
    }

    public class OnboardingResult {
        public Account account;
        public List<Contact> contacts;
        public Opportunity opportunity;
    }

    public static OnboardingResult onboard(OnboardingRequest request) {
        Account account = new Account(Name = request.accountName);
        Opportunity opportunity = request.opportunity;

        IUnitOfWork uow = new UnitOfWork()
            .asUserMode()
            .onCommitSuccess(new LogOnboardingCompleteAction(account));

        uow.registerNew(account);

        for (Contact contact : request.contacts) {
            uow.registerNew(contact).withParent(CONTACT_ACCOUNT_ID, account);
        }

        if (opportunity != null) {
            uow.registerNew(opportunity).withParent(OPPORTUNITY_ACCOUNT_ID, account);
        }

        uow.commitWork();

        OnboardingResult result = new OnboardingResult();
        result.account = account;
        result.contacts = request.contacts;
        result.opportunity = opportunity;
        return result;
    }

    private class LogOnboardingCompleteAction implements IUnitOfWorkAction {
        private Account account;

        private LogOnboardingCompleteAction(Account account) {
            this.account = account;
        }

        public void execute() {
            System.debug(
                LoggingLevel.INFO,
                'CustomerOnboardingService: onboarding committed for Account ' + this.account.Id
            );
        }
    }
}
