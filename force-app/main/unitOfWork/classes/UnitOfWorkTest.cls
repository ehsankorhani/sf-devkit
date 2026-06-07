/**
 * Copyright (c) 2026 Ehsan Korhani
 * SPDX-License-Identifier: MIT
 *
 * @author Ehsan Korhani
 * @version 1.0.0
 */
@IsTest
private class UnitOfWorkTest {

    private static final Schema.SObjectField LEAD_EMAIL_FIELD = Lead.SObjectType.fields.Email;

    private class SpyDML implements IUnitOfWorkDML {
        public Integer insertCallCount = 0;
        public Integer updateCallCount = 0;
        public Integer deleteCallCount = 0;
        public Integer upsertCallCount = 0;
        public Boolean lastAllOrNone;
        public AccessLevel lastAccessLevel;
        public Schema.SObjectField lastUpsertExternalIdField;

        public void doInsert(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            this.insertCallCount++;
            this.lastAllOrNone = allOrNone;
            this.lastAccessLevel = accessLevel;
            Database.insert(records, allOrNone, accessLevel);
        }

        public void doUpdate(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            this.updateCallCount++;
            this.lastAllOrNone = allOrNone;
            this.lastAccessLevel = accessLevel;
            Database.update(records, allOrNone, accessLevel);
        }

        public void doDelete(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            this.deleteCallCount++;
            this.lastAllOrNone = allOrNone;
            this.lastAccessLevel = accessLevel;
            Database.delete(records, allOrNone, accessLevel);
        }

        public void doUpsert(
            List<SObject> records,
            Schema.SObjectField externalIdField,
            Boolean allOrNone,
            AccessLevel accessLevel
        ) {
            this.upsertCallCount++;
            this.lastAllOrNone = allOrNone;
            this.lastAccessLevel = accessLevel;
            this.lastUpsertExternalIdField = externalIdField;
            Database.upsert(records, externalIdField, allOrNone, accessLevel);
        }
    }

    private class FailingDML implements IUnitOfWorkDML {
        public void doInsert(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            throw new DmlException('Forced insert failure');
        }

        public void doUpdate(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            Database.update(records, allOrNone, accessLevel);
        }

        public void doDelete(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            Database.delete(records, allOrNone, accessLevel);
        }

        public void doUpsert(
            List<SObject> records,
            Schema.SObjectField externalIdField,
            Boolean allOrNone,
            AccessLevel accessLevel
        ) {
            Database.upsert(records, externalIdField, allOrNone, accessLevel);
        }
    }

    private class PartialFailInsertDML implements IUnitOfWorkDML {
        public Integer insertCallCount = 0;

        public void doInsert(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            this.insertCallCount++;
            if (this.insertCallCount == 1) {
                Database.insert(records, allOrNone, accessLevel);
            } else {
                throw new DmlException('Forced failure after first insert');
            }
        }

        public void doUpdate(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            Database.update(records, allOrNone, accessLevel);
        }

        public void doDelete(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            Database.delete(records, allOrNone, accessLevel);
        }

        public void doUpsert(
            List<SObject> records,
            Schema.SObjectField externalIdField,
            Boolean allOrNone,
            AccessLevel accessLevel
        ) {
            Database.upsert(records, externalIdField, allOrNone, accessLevel);
        }
    }

    private class CommitActionTracker implements IUnitOfWorkAction {
        public Integer executionCount = 0;

        public void execute() {
            this.executionCount++;
        }
    }

    @IsTest
    static void commitWork_HierarchicalNewRecords_InsertsWithResolvedLookups() {
        // Arrange
        final String parentName = 'Parent Account';
        final String contactLastName = 'Doe';
        Account parentAcc = new Account(Name = parentName);
        Contact childCon = new Contact(FirstName = 'John', LastName = contactLastName);
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerNew(parentAcc)
            .registerNew(childCon)
            .withParent(Contact.AccountId, parentAcc)
            .commitWork();
        Test.stopTest();

        // Assert
        Contact persisted = [
            SELECT AccountId, Account.Name
            FROM Contact
            WHERE Id = :childCon.Id
            LIMIT 1
        ];
        Assert.areEqual(parentAcc.Id, persisted.AccountId, 'Child contact must reference the inserted parent account');
        Assert.areEqual(parentName, persisted.Account.Name, 'Parent account name must persist through the hierarchy commit');
    }

    @IsTest
    static void registerNew_Bulk200Records_InsertsAllRecords() {
        // Arrange
        final Integer bulkSize = 200;
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < bulkSize; i++) {
            accounts.add(new Account(Name = 'Bulk Account ' + i));
        }
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerNew(accounts).commitWork();
        Test.stopTest();

        // Assert
        Integer insertedCount = [SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk Account %'];
        Assert.areEqual(bulkSize, insertedCount, 'Bulk registration must insert every account in a single commit');
    }

    @IsTest
    static void registerNew_NullRecord_ThrowsIllegalArgumentException() {
        // Arrange
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        try {
            uow.registerNew((SObject) null);
            Assert.fail('Null record registration must throw IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('Record cannot be null'),
                'Null record registration must describe the missing record'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for null registerNew input');
    }

    @IsTest
    static void registerNew_NullList_CompletesWithoutError() {
        // Arrange
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerNew((List<SObject>) null).commitWork();
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Null list registration must be ignored without error');
    }

    @IsTest
    static void registerNew_DuplicateInsertRegistration_DeduplicatesEntry() {
        // Arrange
        final String accountName = 'Dedup Account';
        Account acc = new Account(Name = accountName);
        IUnitOfWork uow = new UnitOfWork();
        uow.registerNew(acc);
        uow.registerNew(acc);

        // Act
        Test.startTest();
        uow.commitWork();
        Test.stopTest();

        // Assert
        Integer accountCount = [SELECT COUNT() FROM Account WHERE Name = :accountName];
        Assert.areEqual(1, accountCount, 'Duplicate insert registration must produce a single persisted record');
    }

    @IsTest
    static void registerDirty_ExistingRecord_PersistsChanges() {
        // Arrange
        final String originalName = 'Original Name';
        final String updatedName = 'Updated Name';
        Account acc = new Account(Name = originalName);
        insert acc;
        acc.Name = updatedName;
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerDirty(acc).commitWork();
        Test.stopTest();

        // Assert
        Account persisted = [SELECT Name FROM Account WHERE Id = :acc.Id LIMIT 1];
        Assert.areEqual(updatedName, persisted.Name, 'Dirty registration must persist field changes on commit');
    }

    @IsTest
    static void registerDirty_NullRecord_ThrowsIllegalArgumentException() {
        // Arrange
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        try {
            uow.registerDirty((SObject) null);
            Assert.fail('Null record registration must throw IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('Record cannot be null'),
                'Null dirty registration must describe the missing record'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for null registerDirty input');
    }

    @IsTest
    static void registerDirty_BulkRecords_UpdatesAllRecords() {
        // Arrange
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Bulk Dirty A'),
            new Account(Name = 'Bulk Dirty B'),
            new Account(Name = 'Bulk Dirty C')
        };
        insert accounts;
        for (Account acc : accounts) {
            acc.Name = acc.Name + ' Updated';
        }
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerDirty(accounts).commitWork();
        Test.stopTest();

        // Assert
        Integer updatedCount = [SELECT COUNT() FROM Account WHERE Name LIKE '% Updated'];
        Assert.areEqual(accounts.size(), updatedCount, 'Bulk dirty registration must update every registered account');
    }

    @IsTest
    static void registerDeleted_RegisteredRecords_RemovesFromDatabase() {
        // Arrange
        Account parentAcc = new Account(Name = 'Delete Parent');
        insert parentAcc;
        Contact childCon = new Contact(FirstName = 'Del', LastName = 'Child', AccountId = parentAcc.Id);
        insert childCon;
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerDeleted(parentAcc).registerDeleted(childCon).commitWork();
        Test.stopTest();

        // Assert
        Integer remainingContacts = [SELECT COUNT() FROM Contact WHERE Id = :childCon.Id];
        Integer remainingAccounts = [SELECT COUNT() FROM Account WHERE Id = :parentAcc.Id];
        Assert.areEqual(0, remainingContacts, 'Registered contact delete must remove the child record');
        Assert.areEqual(0, remainingAccounts, 'Registered account delete must remove the parent record');
    }

    @IsTest
    static void registerDeleted_NullRecord_ThrowsIllegalArgumentException() {
        // Arrange
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        try {
            uow.registerDeleted((SObject) null);
            Assert.fail('Null delete registration must throw IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('Record cannot be null'),
                'Null delete registration must describe the missing record'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for null registerDeleted input');
    }

    @IsTest
    static void registerUpsert_NewLeadByEmail_InsertsRecord() {
        // Arrange
        final String email = 'new-lead@example.com';
        Lead lead = new Lead(LastName = 'Upsert', Company = 'Test Co', Email = email);
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerUpsert(lead, LEAD_EMAIL_FIELD).commitWork();
        Test.stopTest();

        // Assert
        Integer leadCount = [SELECT COUNT() FROM Lead WHERE Email = :email];
        Assert.areEqual(1, leadCount, 'Upsert registration must insert a lead keyed by external email');
    }

    @IsTest
    static void registerUpsert_ExistingEmail_UpdatesRecord() {
        // Arrange
        final String email = 'existing-lead@example.com';
        final String originalLastName = 'Original';
        final String updatedLastName = 'Updated';
        Lead existing = new Lead(LastName = originalLastName, Company = 'Test Co', Email = email);
        insert existing;
        Lead upsertLead = new Lead(LastName = updatedLastName, Company = 'Test Co', Email = email);
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerUpsert(upsertLead, LEAD_EMAIL_FIELD).commitWork();
        Test.stopTest();

        // Assert
        Lead persisted = [SELECT LastName FROM Lead WHERE Email = :email LIMIT 1];
        Assert.areEqual(updatedLastName, persisted.LastName, 'Upsert registration must update an existing lead matched by email');
    }

    @IsTest
    static void registerPublish_NullEvent_ThrowsIllegalArgumentException() {
        // Arrange
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        try {
            uow.registerPublish(null);
            Assert.fail('Null platform event registration must throw IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('Platform event cannot be null'),
                'Null platform event registration must describe the missing event'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for null registerPublish input');
    }

    @IsTest
    static void withParent_WithoutPriorRegistration_ThrowsIllegalStateException() {
        // Arrange
        IUnitOfWork uow = new UnitOfWork();
        Account parentAcc = new Account(Name = 'Orphan Parent');

        // Act
        Test.startTest();
        try {
            uow.withParent(Contact.AccountId, parentAcc);
            Assert.fail('withParent without a registered child must throw IllegalStateException');
        } catch (UnitOfWork.IllegalStateException e) {
            Assert.isTrue(
                e.getMessage().contains('No record registered'),
                'withParent without a child must explain that no record was registered'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for withParent without prior registration');
    }

    @IsTest
    static void withParent_NullLookupOrParent_ThrowsIllegalArgumentException() {
        // Arrange
        Contact childCon = new Contact(FirstName = 'Null', LastName = 'Parent');
        IUnitOfWork uow = new UnitOfWork().registerNew(childCon);

        // Act
        Test.startTest();
        try {
            uow.withParent(null, new Account(Name = 'Parent'));
            Assert.fail('Null lookup field must throw IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('Lookup field and parent record must be provided'),
                'Null lookup field must describe missing relationship inputs'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for null withParent lookup field');
    }

    @IsTest
    static void registerRelationship_UnregisteredChild_ThrowsIllegalStateException() {
        // Arrange
        Contact unregisteredChild = new Contact(FirstName = 'Unreg', LastName = 'Child');
        Account parentAcc = new Account(Name = 'Rel Parent');
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        try {
            uow.registerRelationship(unregisteredChild, Contact.AccountId, parentAcc);
            Assert.fail('Relationship on unregistered child must throw IllegalStateException');
        } catch (UnitOfWork.IllegalStateException e) {
            Assert.isTrue(
                e.getMessage().contains('Child record must be registered'),
                'Unregistered child relationship must explain the child was not registered'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for registerRelationship on unregistered child');
    }

    @IsTest
    static void registerRelationship_NullArguments_ThrowsIllegalArgumentException() {
        // Arrange
        Contact childCon = new Contact(FirstName = 'Rel', LastName = 'Child');
        IUnitOfWork uow = new UnitOfWork().registerNew(childCon);

        // Act
        Test.startTest();
        try {
            uow.registerRelationship(null, Contact.AccountId, new Account(Name = 'Parent'));
            Assert.fail('Null child record must throw IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('Child record, lookup field, and parent record must be provided'),
                'Null child record must describe missing relationship inputs'
            );
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Exception contract verified for null registerRelationship child');
    }

    @IsTest
    static void registerRelationship_RegisteredChild_SetsParentLookup() {
        // Arrange
        Account parentAcc = new Account(Name = 'Relationship Parent');
        Contact childCon = new Contact(FirstName = 'Rel', LastName = 'Child');
        IUnitOfWork uow = new UnitOfWork();
        uow.registerNew(parentAcc);
        uow.registerNew(childCon);

        // Act
        Test.startTest();
        uow.registerRelationship(childCon, Contact.AccountId, parentAcc).commitWork();
        Test.stopTest();

        // Assert
        Contact persisted = [SELECT AccountId FROM Contact WHERE Id = :childCon.Id LIMIT 1];
        Assert.areEqual(parentAcc.Id, persisted.AccountId, 'Explicit relationship registration must resolve the parent lookup on commit');
    }

    @IsTest
    static void registerNew_ChildWithExistingParentId_SetsLookupOnInsert() {
        // Arrange
        Account existingParent = new Account(Name = 'Existing Parent');
        insert existingParent;
        Contact childCon = new Contact(FirstName = 'Existing', LastName = 'Parent Ref');
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerNew(childCon).withParent(Contact.AccountId, existingParent).commitWork();
        Test.stopTest();

        // Assert
        Contact persisted = [SELECT AccountId FROM Contact WHERE Id = :childCon.Id LIMIT 1];
        Assert.areEqual(
            existingParent.Id,
            persisted.AccountId,
            'Child insert must use an already-persisted parent Id when the parent is not part of the insert batch'
        );
    }

    @IsTest
    static void commitWork_CircularInsertDependencies_ThrowsUnitOfWorkException() {
        // Arrange
        Account accA = new Account(Name = 'Circular A');
        Account accB = new Account(Name = 'Circular B');
        IUnitOfWork uow = new UnitOfWork();
        uow.registerNew(accA).withParent(Account.ParentId, accB);
        uow.registerNew(accB).withParent(Account.ParentId, accA);

        // Act
        Test.startTest();
        try {
            uow.commitWork();
            Assert.fail('Circular insert dependencies must throw UnitOfWorkException');
        } catch (UnitOfWork.UnitOfWorkException e) {
            Assert.isTrue(
                e.getMessage().contains('Circular dependency'),
                'Circular insert dependencies must report a circular dependency'
            );
        }
        Test.stopTest();

        // Assert
        Integer accountCount = [SELECT COUNT() FROM Account WHERE Name IN ('Circular A', 'Circular B')];
        Assert.areEqual(0, accountCount, 'Failed circular commit must roll back all pending inserts');
    }

    @IsTest
    static void commitWork_DmlFailure_RollsBackTransaction() {
        // Arrange
        Account acc = new Account(Name = 'Rollback Account');
        UnitOfWork uow = new UnitOfWork(new FailingDML());
        uow.registerNew(acc);

        // Act
        Test.startTest();
        try {
            uow.commitWork();
            Assert.fail('DML failure during commit must throw UnitOfWorkException');
        } catch (UnitOfWork.UnitOfWorkException e) {
            Assert.isTrue(
                e.getMessage().contains('Forced insert failure'),
                'Commit failure must surface the underlying DML error message'
            );
        }
        Test.stopTest();

        // Assert
        Integer accountCount = [SELECT COUNT() FROM Account WHERE Name = 'Rollback Account'];
        Assert.areEqual(0, accountCount, 'Failed commit must roll back inserts registered in the same transaction');
    }

    @IsTest
    static void commitWork_FailureAfterPartialInsert_RollsBackPriorDml() {
        // Arrange
        final String parentName = 'Rollback Parent';
        Account parentAcc = new Account(Name = parentName);
        Contact childCon = new Contact(FirstName = 'Roll', LastName = 'Back');
        UnitOfWork uow = new UnitOfWork(new PartialFailInsertDML());
        uow.registerNew(parentAcc)
            .registerNew(childCon)
            .withParent(Contact.AccountId, parentAcc);

        // Act
        Test.startTest();
        try {
            uow.commitWork();
            Assert.fail('Commit must throw when a later DML operation fails');
        } catch (UnitOfWork.UnitOfWorkException e) {
            Assert.isTrue(
                e.getMessage().contains('Forced failure after first insert'),
                'Commit failure must surface the underlying DML error message'
            );
        }
        Test.stopTest();

        // Assert
        Integer parentCount = [SELECT COUNT() FROM Account WHERE Name = :parentName];
        Assert.areEqual(
            0,
            parentCount,
            'A successfully inserted parent must be rolled back when a later insert in the same commit fails'
        );
    }

    @IsTest
    static void commitWork_NoRegisteredWork_CompletesWithoutError() {
        // Arrange
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.commitWork();
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Empty commit must complete without error');
    }

    @IsTest
    static void onCommitSuccess_AfterCommit_ExecutesRegisteredAction() {
        // Arrange
        CommitActionTracker tracker = new CommitActionTracker();
        Account acc = new Account(Name = 'Action Account');
        IUnitOfWork uow = new UnitOfWork().onCommitSuccess(tracker);

        // Act
        Test.startTest();
        uow.registerNew(acc).commitWork();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, tracker.executionCount, 'Successful commit must execute registered post-commit actions');
    }

    @IsTest
    static void onCommitSuccess_CommitFailure_SkipsAction() {
        // Arrange
        CommitActionTracker tracker = new CommitActionTracker();
        UnitOfWork uow = new UnitOfWork(new FailingDML());
        uow.onCommitSuccess(tracker);
        uow.registerNew(new Account(Name = 'Skipped Action'));

        // Act
        Test.startTest();
        try {
            uow.commitWork();
            Assert.fail('Commit failure must throw UnitOfWorkException');
        } catch (UnitOfWork.UnitOfWorkException e) {
            Assert.isTrue(
                e.getMessage().contains('Forced insert failure'),
                'Commit failure must surface the underlying DML error message'
            );
        }
        Test.stopTest();

        // Assert
        Assert.areEqual(0, tracker.executionCount, 'Failed commit must not execute post-commit actions');
    }

    @IsTest
    static void onCommitSuccess_NullAction_IgnoresGracefully() {
        // Arrange
        Account acc = new Account(Name = 'Null Action Account');
        IUnitOfWork uow = new UnitOfWork().onCommitSuccess(null);

        // Act
        Test.startTest();
        uow.registerNew(acc).commitWork();
        Test.stopTest();

        // Assert
        Integer accountCount = [SELECT COUNT() FROM Account WHERE Name = 'Null Action Account'];
        Assert.areEqual(1, accountCount, 'Null post-commit action must not prevent a successful commit');
    }

    @IsTest
    static void asSystemMode_CommitWork_UsesSystemAccessLevel() {
        // Arrange
        SpyDML spy = new SpyDML();
        UnitOfWork uow = new UnitOfWork(spy);
        Account acc = new Account(Name = 'System Mode Account');

        // Act
        Test.startTest();
        uow.asSystemMode().registerNew(acc).commitWork();
        Test.stopTest();

        // Assert
        Assert.areEqual(AccessLevel.SYSTEM_MODE, spy.lastAccessLevel, 'System mode commit must delegate DML at SYSTEM access level');
        Assert.areEqual(1, spy.insertCallCount, 'System mode commit must perform the registered insert');
    }

    @IsTest
    static void asUserMode_CommitWork_UsesUserAccessLevel() {
        // Arrange
        SpyDML spy = new SpyDML();
        UnitOfWork uow = new UnitOfWork(spy);
        Account acc = new Account(Name = 'User Mode Account');

        // Act
        Test.startTest();
        uow.asUserMode().registerNew(acc).commitWork();
        Test.stopTest();

        // Assert
        Assert.areEqual(AccessLevel.USER_MODE, spy.lastAccessLevel, 'User mode commit must delegate DML at USER access level');
    }

    @IsTest
    static void allOrNone_FalseValue_PassesPartialSuccessFlag() {
        // Arrange
        SpyDML spy = new SpyDML();
        UnitOfWork uow = new UnitOfWork(spy);
        Account acc = new Account(Name = 'Partial Success Account');

        // Act
        Test.startTest();
        uow.allOrNone(false).registerNew(acc).commitWork();
        Test.stopTest();

        // Assert
        Assert.isFalse(spy.lastAllOrNone, 'allOrNone(false) must allow partial success on DML operations');
    }

    @IsTest
    static void allOrNone_NullValue_DefaultsToTrue() {
        // Arrange
        SpyDML spy = new SpyDML();
        UnitOfWork uow = new UnitOfWork(spy);
        Account acc = new Account(Name = 'All Or None Default Account');

        // Act
        Test.startTest();
        uow.allOrNone(null).registerNew(acc).commitWork();
        Test.stopTest();

        // Assert
        Assert.isTrue(spy.lastAllOrNone, 'Null allOrNone must default to all-or-none DML behavior');
    }

    @IsTest
    static void withConcurrencyCheck_Disabled_AllowsUpdateWithoutTimestampValidation() {
        // Arrange
        Account acc = new Account(Name = 'No Check Original');
        insert acc;
        Account loaded = [SELECT Id, Name, LastModifiedDate FROM Account WHERE Id = :acc.Id LIMIT 1];
        Account snapshot = loaded.clone(true, true, true, true);
        update new Account(Id = loaded.Id, Name = 'No Check External');
        snapshot.Name = 'No Check Attempted';
        IUnitOfWork uow = new UnitOfWork();

        // Act
        Test.startTest();
        uow.registerDirty(snapshot).commitWork();
        Test.stopTest();

        // Assert
        Account persisted = [SELECT Name FROM Account WHERE Id = :acc.Id LIMIT 1];
        Assert.areEqual(
            'No Check Attempted',
            persisted.Name,
            'Updates must succeed without concurrency check even when LastModifiedDate differs from the database'
        );
    }
    @IsTest
    static void withConcurrencyCheck_CurrentLastModifiedDate_CommitsUpdate() {
        // Arrange
        final String updatedName = 'Concurrency Updated';
        Account acc = new Account(Name = 'Concurrency Original');
        insert acc;
        Account loaded = [SELECT Id, Name, LastModifiedDate FROM Account WHERE Id = :acc.Id LIMIT 1];
        loaded.Name = updatedName;
        IUnitOfWork uow = new UnitOfWork().withConcurrencyCheck();

        // Act
        Test.startTest();
        uow.registerDirty(loaded).commitWork();
        Test.stopTest();

        // Assert
        Account persisted = [SELECT Name FROM Account WHERE Id = :acc.Id LIMIT 1];
        Assert.areEqual(updatedName, persisted.Name, 'Concurrency check must allow updates when LastModifiedDate matches the database');
    }

    @IsTest
    static void commitWork_MixedOperations_ExecutesInCorrectOrder() {
        // Arrange
        Account existing = new Account(Name = 'Mixed Existing');
        insert existing;
        Account toInsert = new Account(Name = 'Mixed Inserted');
        existing.Name = 'Mixed Updated';
        Account toDelete = new Account(Name = 'Mixed Deleted');
        insert toDelete;
        IUnitOfWork uow = new UnitOfWork();
        uow.registerNew(toInsert);
        uow.registerDirty(existing);
        uow.registerDeleted(toDelete);

        // Act
        Test.startTest();
        uow.commitWork();
        Test.stopTest();

        // Assert
        Integer insertedCount = [SELECT COUNT() FROM Account WHERE Name = 'Mixed Inserted'];
        Integer deletedCount = [SELECT COUNT() FROM Account WHERE Name = 'Mixed Deleted'];
        Account updated = [SELECT Name FROM Account WHERE Id = :existing.Id LIMIT 1];
        Assert.areEqual(1, insertedCount, 'Mixed commit must insert newly registered records');
        Assert.areEqual(0, deletedCount, 'Mixed commit must delete registered records');
        Assert.areEqual('Mixed Updated', updated.Name, 'Mixed commit must update dirty records');
    }

    @IsTest
    static void registerUpsert_DuplicateRegistration_UpdatesExternalIdField() {
        // Arrange
        SpyDML spy = new SpyDML();
        UnitOfWork uow = new UnitOfWork(spy);
        Lead lead = new Lead(LastName = 'Dup Upsert', Company = 'Test Co', Email = 'dup-upsert@example.com');
        uow.registerUpsert(lead, LEAD_EMAIL_FIELD);
        uow.registerUpsert(lead, LEAD_EMAIL_FIELD);

        // Act
        Test.startTest();
        uow.commitWork();
        Test.stopTest();

        // Assert
        Assert.areEqual(LEAD_EMAIL_FIELD, spy.lastUpsertExternalIdField, 'Duplicate upsert registration must retain the external id field for commit');
        Assert.areEqual(1, spy.upsertCallCount, 'Duplicate upsert registration must produce a single upsert DML call');
    }
}
