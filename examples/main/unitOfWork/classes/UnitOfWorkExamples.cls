/**
 * Runnable Unit of Work examples — execute individual methods from Anonymous Apex
 * or call UnitOfWorkExamples.runAll() to walk through every scenario.
 */
public inherited sharing class UnitOfWorkExamples {

    private static final Schema.SObjectField LEAD_EMAIL_FIELD = Lead.SObjectType.fields.Email;
    private static final Schema.SObjectField CONTACT_ACCOUNT_ID = Contact.SObjectType.fields.AccountId;
    private static final Schema.SObjectField OPPORTUNITY_ACCOUNT_ID = Opportunity.SObjectType.fields.AccountId;

    public static void runAll() {
        resetTriggerState();
        hierarchicalInsert();

        resetTriggerState();
        childRegisteredBeforeParent();

        resetTriggerState();
        explicitRelationship();

        resetTriggerState();
        mixedOperations();

        resetTriggerState();
        upsertByExternalId();

        resetTriggerState();
        bulkInsert();

        resetTriggerState();
        postCommitAction();

        resetTriggerState();
        configurationOptions();

        resetTriggerState();
        existingParentReference();

        resetTriggerState();
        concurrencyConflictDetected();

        resetTriggerState();
        serviceLayerOnboarding();
    }

    /**
     * Examples share one Anonymous Apex transaction; reset TriggerHandler loop
     * counters between scenarios so AccountTrigger maxLoops is not exhausted.
     */
    private static void resetTriggerState() {
        TriggerHandler.clearAll();
    }

    /**
     * Fluent chaining: register parent and children, link lookups with withParent(),
     * then commit once. Parent IDs are resolved automatically before child inserts.
     */
    public static void hierarchicalInsert() {
        Account parentAcc = new Account(Name = 'UOW Example Parent');
        Contact primaryContact = new Contact(FirstName = 'Alex', LastName = 'Rivera');
        Contact secondaryContact = new Contact(FirstName = 'Sam', LastName = 'Rivera');
        Opportunity deal = new Opportunity(
            Name = 'UOW Example Deal',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );

        new UnitOfWork()
            .asUserMode()
            .registerNew(parentAcc)
            .registerNew(primaryContact)
            .withParent(CONTACT_ACCOUNT_ID, parentAcc)
            .registerNew(secondaryContact)
            .withParent(CONTACT_ACCOUNT_ID, parentAcc)
            .registerNew(deal)
            .withParent(OPPORTUNITY_ACCOUNT_ID, parentAcc)
            .commitWork();

        System.debug(
            LoggingLevel.INFO,
            'hierarchicalInsert: Account=' + parentAcc.Id +
            ', Contact=' + primaryContact.Id +
            ', Opportunity=' + deal.Id
        );
    }

    /**
     * Smart ordering: children may be registered before their parent. The framework
     * topologically sorts inserts so parents are persisted first.
     */
    public static void childRegisteredBeforeParent() {
        Account parentAcc = new Account(Name = 'UOW Child-First Parent');
        Contact childCon = new Contact(FirstName = 'Jordan', LastName = 'Lee');

        new UnitOfWork()
            .registerNew(childCon)
            .withParent(CONTACT_ACCOUNT_ID, parentAcc)
            .registerNew(parentAcc)
            .commitWork();

        System.debug(
            LoggingLevel.INFO,
            'childRegisteredBeforeParent: Contact.AccountId=' + childCon.AccountId
        );
    }

    /**
     * Decouple relationship wiring from registration order using registerRelationship().
     */
    public static void explicitRelationship() {
        Account parentAcc = new Account(Name = 'UOW Explicit Rel Parent');
        Contact childCon = new Contact(FirstName = 'Taylor', LastName = 'Nguyen');

        IUnitOfWork uow = new UnitOfWork();
        uow.registerNew(parentAcc);
        uow.registerNew(childCon);
        uow.registerRelationship(childCon, CONTACT_ACCOUNT_ID, parentAcc);
        uow.commitWork();

        System.debug(
            LoggingLevel.INFO,
            'explicitRelationship: Contact.AccountId=' + childCon.AccountId
        );
    }

    /**
     * Single commit with inserts, updates, and deletes. Operations run in the
     * safe order: inserts, updates, upserts, then deletes (children before parents).
     */
    public static void mixedOperations() {
        Account existing = new Account(Name = 'UOW Mixed Existing');
        insert existing;

        Account toInsert = new Account(Name = 'UOW Mixed Inserted');
        Account toDelete = new Account(Name = 'UOW Mixed Deleted');
        insert toDelete;

        existing.Description = 'Updated via Unit of Work';

        new UnitOfWork()
            .registerNew(toInsert)
            .registerDirty(existing)
            .registerDeleted(toDelete)
            .commitWork();

        System.debug(
            LoggingLevel.INFO,
            'mixedOperations: inserted=' + toInsert.Id + ', updated=' + existing.Id
        );
    }

    /**
     * Upsert by external id — insert when absent, update when the key already exists.
     */
    public static void upsertByExternalId() {
        Lead inboundLead = new Lead(
            LastName = 'Prospect',
            Company = 'Example Corp',
            Email = 'uow-example@example.com'
        );

        new UnitOfWork()
            .registerUpsert(inboundLead, LEAD_EMAIL_FIELD)
            .commitWork();

        Lead refreshed = new Lead(
            LastName = 'Prospect Updated',
            Company = 'Example Corp',
            Email = 'uow-example@example.com'
        );

        new UnitOfWork()
            .registerUpsert(refreshed, LEAD_EMAIL_FIELD)
            .commitWork();

        Lead persisted = [
            SELECT LastName
            FROM Lead
            WHERE Email = 'uow-example@example.com'
            LIMIT 1
        ];
        System.debug(LoggingLevel.INFO, 'upsertByExternalId: LastName=' + persisted.LastName);
    }

    /**
     * Bulk registration — pass a list instead of registering one record at a time.
     */
    public static void bulkInsert() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'UOW Bulk A'),
            new Account(Name = 'UOW Bulk B'),
            new Account(Name = 'UOW Bulk C')
        };

        new UnitOfWork()
            .registerNew(accounts)
            .commitWork();

        Integer count = [SELECT COUNT() FROM Account WHERE Name LIKE 'UOW Bulk %'];
        System.debug(LoggingLevel.INFO, 'bulkInsert: count=' + count);
    }

    /**
     * Post-commit actions run only after all DML succeeds. They are skipped when
     * commitWork rolls back, making them safe for queueables, callouts, or logging.
     */
    public static void postCommitAction() {
        Account acc = new Account(Name = 'UOW Post-Commit Account');

        new UnitOfWork()
            .registerNew(acc)
            .onCommitSuccess(new AccountCommittedAction(acc))
            .commitWork();

        System.debug(LoggingLevel.INFO, 'postCommitAction: Account Id=' + acc.Id);
    }

    /**
     * Configuration fluents: access level, partial-success DML, and optimistic
     * concurrency checks on updates.
     */
    public static void configurationOptions() {
        Account systemModeAccount = new Account(Name = 'UOW System Mode');
        new UnitOfWork()
            .asSystemMode()
            .registerNew(systemModeAccount)
            .commitWork();

        Account partialSuccessAccount = new Account(Name = 'UOW Partial Success');
        new UnitOfWork()
            .asUserMode()
            .allOrNone(false)
            .registerNew(partialSuccessAccount)
            .commitWork();

        Account toUpdate = [
            SELECT Id, Name, LastModifiedDate
            FROM Account
            WHERE Id = :systemModeAccount.Id
            LIMIT 1
        ];
        toUpdate.Description = 'Updated with concurrency check';

        new UnitOfWork()
            .asUserMode()
            .withConcurrencyCheck()
            .registerDirty(toUpdate)
            .commitWork();

        System.debug(
            LoggingLevel.INFO,
            'configurationOptions: system=' + systemModeAccount.Id +
            ', partial=' + partialSuccessAccount.Id
        );
    }

    /**
     * Link a new child to a parent that already exists in the database (parent
     * is not part of the insert batch).
     */
    public static void existingParentReference() {
        Account existingParent = new Account(Name = 'UOW Existing Parent');
        insert existingParent;

        Contact childCon = new Contact(FirstName = 'Casey', LastName = 'Existing');

        new UnitOfWork()
            .registerNew(childCon)
            .withParent(CONTACT_ACCOUNT_ID, existingParent)
            .commitWork();

        System.debug(
            LoggingLevel.INFO,
            'existingParentReference: Contact.AccountId=' + childCon.AccountId
        );
    }

    /**
     * Optimistic concurrency — withConcurrencyCheck() blocks an update when the
     * record changed in the database after the in-memory copy was loaded. The stale
     * copy is fabricated via JSON so its LastModifiedDate is intentionally older than
     * the database value (this branch is hard to reproduce in a single test transaction).
     */
    public static void concurrencyConflictDetected() {
        Account acc = new Account(Name = 'UOW Concurrency Conflict');
        insert acc;

        // Simulate another process updating the record, advancing LastModifiedDate.
        update new Account(Id = acc.Id, Description = 'Changed by another process');

        // Stale in-memory copy with an intentionally old LastModifiedDate.
        Account staleCopy = (Account) JSON.deserialize(
            '{"attributes":{"type":"Account"},"Id":"' + acc.Id + '",' +
            '"Name":"UOW Concurrency Stale Edit",' +
            '"LastModifiedDate":"2000-01-01T00:00:00.000Z"}',
            Account.class
        );

        try {
            new UnitOfWork()
                .withConcurrencyCheck()
                .registerDirty(staleCopy)
                .commitWork();
            System.debug(
                LoggingLevel.ERROR,
                'concurrencyConflictDetected: expected a conflict but the stale update committed'
            );
        } catch (UnitOfWork.UnitOfWorkException e) {
            System.debug(
                LoggingLevel.INFO,
                'concurrencyConflictDetected: correctly blocked stale update -> ' + e.getMessage()
            );
        }
    }

    /**
     * Service-layer pattern — delegate business orchestration to a dedicated class
     * that internally uses Unit of Work.
     */
    public static void serviceLayerOnboarding() {
        CustomerOnboardingService.OnboardingRequest request = new CustomerOnboardingService.OnboardingRequest();
        request.accountName = 'UOW Service Layer Account';
        request.contacts = new List<Contact>{
            new Contact(FirstName = 'Morgan', LastName = 'Service'),
            new Contact(FirstName = 'Riley', LastName = 'Service')
        };
        request.opportunity = new Opportunity(
            Name = 'UOW Service Layer Opp',
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(45)
        );

        CustomerOnboardingService.OnboardingResult result = CustomerOnboardingService.onboard(request);
        System.debug(
            LoggingLevel.INFO,
            'serviceLayerOnboarding: Account=' + result.account.Id +
            ', contacts=' + result.contacts.size()
        );
    }

    private class AccountCommittedAction implements IUnitOfWorkAction {
        private Account account;

        private AccountCommittedAction(Account account) {
            this.account = account;
        }

        public void execute() {
            System.debug(
                LoggingLevel.INFO,
                'UnitOfWorkExamples postCommitAction: committed Account ' + this.account.Id
            );
        }
    }

    private class DebugCommitAction implements IUnitOfWorkAction {
        private String message;

        private DebugCommitAction(String message) {
            this.message = message;
        }

        public void execute() {
            System.debug(LoggingLevel.INFO, 'UnitOfWorkExamples: ' + this.message);
        }
    }
}
