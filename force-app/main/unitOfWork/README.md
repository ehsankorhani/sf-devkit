<div align="center">
  <h1>UnitOfWork</h1>

<a href="https://github.com/ehsankorhani/sf-devkit"><img alt="sf-devkit" src="https://img.shields.io/badge/PART_OF-SF_DEVKIT-555?style=for-the-badge"></a>

<img alt="API version" src="https://img.shields.io/badge/api-v66.0-blue?style=for-the-badge">
<a href="https://github.com/ehsankorhani/sf-devkit/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge"></a>
<a href="https://github.com/ehsankorhani/sf-devkit/tree/main/force-app/main/unitOfWork"><img alt="Source" src="https://img.shields.io/badge/source-unitOfWork-green?style=for-the-badge"></a>
</div>

# About

A simple, fluent Unit of Work for Salesforce Apex — part of [sf-devkit](https://github.com/ehsankorhani/sf-devkit), a collection of utilities and toolkits for Salesforce developers and architects.

A Unit of Work groups all the database changes for a single business transaction, then commits them together with **one** `commitWork()` call. It bulkifies DML by SObject type, resolves parent/child lookups automatically, and rolls everything back as a unit if anything fails.

This library was built on one principle: **most teams abandon Unit of Work frameworks because they are too complex to use correctly.** Heavyweight frameworks force developers to declare rigid SObject ordering up front and bury relationship wiring inside overloaded method signatures. This implementation keeps the power but removes the cognitive load, so the average developer can pick it up in minutes.

### Why use it

- **One commit, fully transactional.** Register inserts, updates, upserts, and deletes anywhere in your code, then commit once. A failure anywhere rolls back the entire transaction via an automatic `Savepoint`.
- **Automatic bulkification.** Records are grouped by SObject type and operation, so you get at most one DML statement per type per operation — no manual list juggling, no governor-limit surprises.
- **Automatic relationship resolution.** Register a parent and a child together; the framework populates the child's lookup with the parent's generated Id after the parent is inserted. You never write the lookup back yourself.
- **Readable fluent API.** Every registration method returns the instance, so wiring reads like a sentence.
- **Secure by default.** Runs in `AccessLevel.USER_MODE` out of the box, honouring FLS and CRUD.
- **Fully mockable.** Fronted by the `IUnitOfWork` interface with an injectable `IUnitOfWorkDML` seam, so service logic is unit-testable without hitting the database.

### Enhancements over existing frameworks

Compared to fflib and lighter frameworks (e.g. ZackFra), this library adds:

| Enhancement | What it gives you |
|-------------|-------------------|
| **True fluent chaining** | Every `register*` method returns `this`; no repeated `uow.` statements. |
| **Decoupled `withParent()` / `registerRelationship()`** | Relationships are declared explicitly and read clearly, instead of being hidden as extra parameters on `registerNew`. |
| **Smart topological ordering** | A dependency graph orders inserts automatically — register a child before its parent and it still works. No up-front SObject ordering block. |
| **Post-commit hooks** | `onCommitSuccess()` runs queueables, callouts, or logging **only** when the transaction succeeds, avoiding side effects on rollback. |
| **Platform event publishing** | `registerPublish()` fires events through `EventBus` after a successful commit. |
| **Optimistic concurrency** | `withConcurrencyCheck()` rejects updates to records that changed in the database since they were loaded — a feature borrowed from JPA `@Version` / EF rowversion that few SF frameworks offer. |
| **Identity-map de-duplication** | Registering the same record twice for the same operation is a safe no-op. |
| **Partial-success control** | `allOrNone(false)` opts into partial DML success when you need it. |

---

# Getting Started

Register the records that make up a business transaction, then commit once.

```apex
Account parentAcc = new Account(Name = 'Acme');
Contact childCon = new Contact(LastName = 'Doe');

new UnitOfWork()
    .registerNew(parentAcc)
    .registerNew(childCon)
    .withParent(Contact.AccountId, parentAcc)
    .commitWork();
```

`parentAcc` is inserted first, its new Id is written to `childCon.AccountId`, then `childCon` is inserted — all inside one transaction. If either insert fails, both are rolled back.

A full set of runnable samples lives in [`examples/main/unitOfWork`](../../../examples/main/unitOfWork/classes/UnitOfWorkExamples.cls).

---

## Guide

### 1. Create a Unit of Work

```apex
IUnitOfWork uow = new UnitOfWork();          // USER_MODE, all-or-none by default
```

Program against the `IUnitOfWork` interface so your service code stays mockable.

### 2. Register records

| Method | Operation |
|--------|-----------|
| `registerNew(record)` / `registerNew(records)` | Insert |
| `registerDirty(record)` / `registerDirty(records)` | Update |
| `registerDeleted(record)` / `registerDeleted(records)` | Delete |
| `registerUpsert(record, externalIdField)` | Upsert (pass `null` to match on Id) |
| `registerPublish(platformEvent)` | Publish a platform event after commit |

```apex
uow.registerNew(new Account(Name = 'New'));
uow.registerDirty(existingContact);
uow.registerDeleted(oldCase);
uow.registerNew(new List<SObject>{ acc1, acc2, acc3 });   // bulk overload
```

### 3. Wire relationships

Use `withParent()` to link the **most recently registered** record to a parent, or `registerRelationship()` to link an explicitly named child — clearer in long chains.

```apex
// Fluent: attaches to the record just registered
uow.registerNew(childCon).withParent(Contact.AccountId, parentAcc);

// Explicit: child is named, order-independent
uow.registerNew(parentAcc);
uow.registerNew(childCon);
uow.registerRelationship(childCon, Contact.AccountId, parentAcc);
```

The parent can be a record being inserted in the same commit (its Id is resolved automatically) or an already-persisted record (its existing Id is used).

### 4. Commit

```apex
uow.commitWork();
```

`commitWork()` sets a savepoint, then executes in this order: **inserts → updates → upserts → deletes**, then publishes events, then runs post-commit actions. Any exception rolls back to the savepoint and rethrows a `UnitOfWork.UnitOfWorkException`. After a successful commit the instance is cleared, so it will not re-run prior work.

---

## Fluent API

All methods except `commitWork()` return `IUnitOfWork` and can be chained.

| Method | Purpose |
|--------|---------|
| `registerNew(SObject)` / `registerNew(List<SObject>)` | Register record(s) for insert |
| `registerDirty(SObject)` / `registerDirty(List<SObject>)` | Register record(s) for update |
| `registerDeleted(SObject)` / `registerDeleted(List<SObject>)` | Register record(s) for delete |
| `registerUpsert(SObject, SObjectField)` | Register for upsert by external Id (or Id when `null`) |
| `registerPublish(SObject)` | Queue a platform event to publish after commit |
| `withParent(SObjectField, SObject)` | Link the last registered record to a parent |
| `registerRelationship(SObject, SObjectField, SObject)` | Link a named child to a parent |
| `asUserMode()` | Run DML in user mode (default) — enforces FLS/CRUD |
| `asSystemMode()` | Run DML in system mode |
| `allOrNone(Boolean)` | `false` allows partial success (`null` defaults to `true`) |
| `withConcurrencyCheck()` | Reject updates to records changed in the DB since load |
| `onCommitSuccess(IUnitOfWorkAction)` | Register work that runs only after a successful commit |
| `commitWork()` | **Terminal** — savepoint, ordered DML, publish, post-commit, rollback on failure |

---

## Relationship Resolution & Ordering

You do **not** need to register parents before children. The framework builds a dependency graph from the relationships you declare and topologically sorts inserts so parents are always persisted first.

```apex
Account parentAcc = new Account(Name = 'Parent');
Contact childCon = new Contact(LastName = 'Child');

new UnitOfWork()
    .registerNew(childCon)                          // child registered first
    .withParent(Contact.AccountId, parentAcc)
    .registerNew(parentAcc)                          // parent registered second
    .commitWork();                                   // parent still inserts first
```

- **Bulkified by level:** all records at the same dependency level and SObject type are inserted in a single DML statement.
- **Deletes run children-first:** delete ordering is reversed so child records are removed before their parents.
- **Circular dependencies** throw `UnitOfWork.UnitOfWorkException` (wrapping an `IllegalStateException`) instead of failing silently.

---

## Transaction Management

`commitWork()` is the single trigger point for all database work.

- An automatic `Database.Savepoint` is set before any DML.
- On any exception the transaction is rolled back to the savepoint and a `UnitOfWork.UnitOfWorkException` is thrown with the original error as its cause.
- `allOrNone(true)` (default) makes each DML statement all-or-none. `allOrNone(false)` permits partial success.

```apex
try {
    new UnitOfWork()
        .registerNew(acc)
        .registerNew(con).withParent(Contact.AccountId, acc)
        .commitWork();
} catch (UnitOfWork.UnitOfWorkException e) {
    // acc and con are both rolled back
    System.debug(e.getMessage());
}
```

---

## Security & Access Level

DML runs in `AccessLevel.USER_MODE` by default, enforcing the running user's field-level security and object permissions. Opt into system mode explicitly when needed.

```apex
new UnitOfWork().asSystemMode().registerNew(acc).commitWork();   // bypass FLS/CRUD
new UnitOfWork().asUserMode().registerNew(acc).commitWork();     // default
```

---

## Optimistic Concurrency

`withConcurrencyCheck()` guards against the lost-update problem: when enabled, each update is compared against the database's current `LastModifiedDate`. If the record changed after your copy was loaded, the commit is rejected.

```apex
Account acc = [SELECT Id, Name, LastModifiedDate FROM Account WHERE Id = :id];
acc.Name = 'Edited';

new UnitOfWork()
    .withConcurrencyCheck()
    .registerDirty(acc)
    .commitWork();   // throws UnitOfWorkException if acc was modified elsewhere
```

> The in-memory record must include `LastModifiedDate` (query it). Records without it are skipped by the check. This adds one SOQL query per SObject type being updated.

---

## Post-Commit Actions

Register work that must run **only** when the database transaction succeeds — queueables, callouts, or platform-event side effects that should never fire on rollback.

```apex
public class SendWelcomeEmail implements IUnitOfWorkAction {
    private Id accountId;
    public SendWelcomeEmail(Id accountId) { this.accountId = accountId; }
    public void execute() {
        // enqueue email / callout — only runs after a clean commit
    }
}

new UnitOfWork()
    .registerNew(acc)
    .onCommitSuccess(new SendWelcomeEmail(acc.Id))
    .commitWork();
```

For platform events specifically, prefer `registerPublish()`, which publishes via `EventBus.publish` after a successful commit:

```apex
new UnitOfWork()
    .registerNew(acc)
    .registerPublish(new Order_Event__e(Account__c = acc.Id))
    .commitWork();
```

---

## Testing & Mocking

`UnitOfWork` is fronted by `IUnitOfWork` and delegates all DML to the `IUnitOfWorkDML` interface. A `@TestVisible` constructor accepts a custom DML implementation, so you can spy on or fail DML without touching the database.

```apex
@IsTest
private class MyServiceTest {

    private class SpyDML implements IUnitOfWorkDML {
        public Integer insertCalls = 0;
        public void doInsert(List<SObject> records, Boolean allOrNone, AccessLevel access) {
            insertCalls++;
            Database.insert(records, allOrNone, access);
        }
        public void doUpdate(List<SObject> records, Boolean allOrNone, AccessLevel access) {
            Database.update(records, allOrNone, access);
        }
        public void doDelete(List<SObject> records, Boolean allOrNone, AccessLevel access) {
            Database.delete(records, allOrNone, access);
        }
        public void doUpsert(List<SObject> records, Schema.SObjectField f, Boolean allOrNone, AccessLevel access) {
            Database.upsert(records, f, allOrNone, access);
        }
    }

    @IsTest
    static void commitWork_SingleInsert_PerformsOneInsert() {
        // Arrange
        SpyDML spy = new SpyDML();
        UnitOfWork uow = new UnitOfWork(spy);

        // Act
        Test.startTest();
        uow.registerNew(new Account(Name = 'Test')).commitWork();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, spy.insertCalls, 'A single registered insert must trigger one insert DML call');
    }
}
```

A `FailingDML` double (throws on `doInsert`) lets you assert rollback and exception behaviour. See [`UnitOfWorkTest.cls`](classes/UnitOfWorkTest.cls) for the full pattern.

---

## Examples

| Scenario | Demonstrates |
|----------|--------------|
| `hierarchicalInsert()` | Fluent parent + children with `withParent()` |
| `childRegisteredBeforeParent()` | Smart topological ordering |
| `explicitRelationship()` | `registerRelationship()` decoupled wiring |
| `mixedOperations()` | Insert, update, and delete in one commit |
| `upsertByExternalId()` | Insert-or-update by an `idLookup` field |
| `bulkInsert()` | Bulk list registration |
| `postCommitAction()` | `onCommitSuccess()` side effects |
| `configurationOptions()` | `asSystemMode()`, `allOrNone(false)`, `withConcurrencyCheck()` |
| `existingParentReference()` | Linking a new child to a persisted parent |
| `concurrencyConflictDetected()` | Optimistic concurrency rejecting a stale update |
| `CustomerOnboardingService` | Service-layer pattern wrapping a Unit of Work |

Run them from Anonymous Apex:

```apex
UnitOfWorkExamples.runAll();
```

---

## Best Practices

1. **Program against `IUnitOfWork`**, not the concrete class, so service logic stays mockable.
2. **One Unit of Work per business transaction.** Build it up, commit once, discard it.
3. **Prefer `withParent()` / `registerRelationship()`** over manually setting lookup Ids — let the framework resolve them.
4. **Use `registerRelationship()` in long chains** where `withParent()`'s "last registered" target is ambiguous.
5. **Keep `asUserMode()` (the default)** unless you have a deliberate reason to bypass FLS/CRUD.
6. **Use `onCommitSuccess()` / `registerPublish()`** for callouts, queueables, and events — never fire them inline before the commit succeeds.
7. **Enable `withConcurrencyCheck()`** on edit flows where lost updates matter, and query `LastModifiedDate` on the records you intend to update.
8. **Inject a custom `IUnitOfWorkDML`** in tests to verify DML grouping and rollback without large data setup.

---

## Errors

| Situation | Exception |
|-----------|-----------|
| `registerNew/Dirty/Deleted(null)` | `IllegalArgumentException` |
| `registerPublish(null)` | `IllegalArgumentException` |
| `withParent()` before any registration | `UnitOfWork.IllegalStateException` |
| `withParent(null, ...)` / `withParent(..., null)` | `IllegalArgumentException` |
| `registerRelationship()` with a null argument | `IllegalArgumentException` |
| `registerRelationship()` on an unregistered child | `UnitOfWork.IllegalStateException` |
| Circular insert dependency | `UnitOfWork.UnitOfWorkException` |
| Any DML failure during `commitWork()` | `UnitOfWork.UnitOfWorkException` (rolled back, original error as cause) |
| Stale record with `withConcurrencyCheck()` | `UnitOfWork.UnitOfWorkException` |

All commit-time failures roll the transaction back to the savepoint before rethrowing, so partial writes never persist.
