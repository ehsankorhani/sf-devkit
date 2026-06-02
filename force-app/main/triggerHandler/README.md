<div align="center">
  <h1>TriggerHandler</h1>

<a href="https://github.com/ehsankorhani/sf-devkit"><img alt="sf-devkit" src="https://img.shields.io/badge/PART_OF-SF_DEVKIT-555?style=for-the-badge"></a>

<img alt="API version" src="https://img.shields.io/badge/api-v66.0-blue?style=for-the-badge">
<a href="https://github.com/ehsankorhani/sf-devkit/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge"></a>
<a href="https://github.com/ehsankorhani/sf-devkit/tree/main/force-app/main/triggerHandler"><img alt="Source" src="https://img.shields.io/badge/source-triggerHandler-green?style=for-the-badge"></a>
</div>

# Getting Started

A fluent trigger handler base class for Salesforce Apex — part of [sf-devkit](https://github.com/ehsankorhani/sf-devkit), a collection of utilities and toolkits for Salesforce developers and architects.

Records are passed explicitly via the fluent chain, so handler logic is unit-testable without mocking `Trigger`. Triggers stay one line; business logic lives in handler classes.

**Concise trigger**

```apex
trigger AccountTrigger on Account (before insert, before update, after insert, after update) {
    new AccountHandler().fromTrigger().maxLoops(5).run();
}
```

**Explicit trigger wiring**

```apex
trigger AccountTrigger on Account (before insert, before update, after insert, after update) {
    new AccountHandler()
        .withNew(Trigger.new)
        .withOld(Trigger.old)
        .withOldMap((Map<Id, SObject>) Trigger.oldMap)
        .withNewMap((Map<Id, SObject>) Trigger.newMap)
        .maxLoops(5)
        .trackLimits()
        .run();
}
```

**Handler**

```apex
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
}
```

**Test**

```apex
@IsTest
static void beforeInsert_setsDescription() {
    List<Account> records = new List<Account>{ new Account(Name = 'Test Co') };

    new AccountHandler()
        .withNew(records)
        .withContext(System.TriggerOperation.BEFORE_INSERT)
        .run();

    System.assertEquals('Created via TriggerHandler', records[0].Description);
}
```

A full working sample lives in [`examples/main/triggerHandler`](../../../examples/main/triggerHandler/classes/AccountHandler.cls) and [`examples/main/triggers`](../../../examples/main/triggers/AccountTrigger.trigger).

---

## Guide

### 1. Create a handler class

Extend `TriggerHandler` and pass your concrete class type to the constructor for stable bypass, loop, and process-once keys.

```apex
public inherited sharing class AccountHandler extends TriggerHandler {
    public AccountHandler() {
        super(AccountHandler.class);
    }
}
```

The base class uses `inherited sharing` so your handler respects `with sharing` / `without sharing` on the concrete class.

### 2. Wire the trigger

Prefer `.fromTrigger()` in production triggers — it wires `Trigger.new`, `Trigger.old`, `Trigger.oldMap`, and `Trigger.newMap` in one call. `Trigger.operationType` is resolved automatically in `run()`.

| Trigger context | Explicit equivalent |
|-----------------|---------------------|
| `Trigger.new` | `.withNew(Trigger.new)` |
| `Trigger.old` | `.withOld(Trigger.old)` |
| `Trigger.oldMap` | `.withOldMap((Map<Id, SObject>) Trigger.oldMap)` |
| `Trigger.newMap` | `.withNewMap((Map<Id, SObject>) Trigger.newMap)` |

Optional chain methods:

| Method | Purpose |
|--------|---------|
| `.maxLoops(n)` | Cap re-entries per handler + operation |
| `.trackLimits()` | Log SOQL, DML, and CPU consumed by this handler |
| `.onlyThese(recordIds)` | Process only specific records (not valid on `BEFORE_INSERT`) |
| `.bypassIf(condition)` | Skip this invocation only (instance-level) |
| `.bypassIfPermission(name)` | Skip when the running user has a Custom Permission |
| `.processOnce()` | Process each record at most once per handler + context per transaction |

### 3. Override context methods

Use the protected fields populated by the fluent chain inside overrides:

| Field | Description |
|-------|-------------|
| `this.newRecords` | Current/new records |
| `this.oldRecords` | Prior records (update/delete) |
| `this.oldMap` | Id → old record map |
| `this.newMap` | Id → new record map |
| `this.triggerOp` | Current operation |

Available overrides:

```apex
protected virtual void beforeInsert()
protected virtual void beforeUpdate()
protected virtual void beforeDelete()
protected virtual void afterInsert()
protected virtual void afterUpdate()
protected virtual void afterDelete()
protected virtual void afterUndelete()
protected virtual void andFinally()
protected virtual void onError(Exception e)
protected virtual void logLimits(...)
```

### 4. Test without trigger context

Pass records directly and set the operation with `.withContext()`. No trigger DML or static mocks required.

```apex
@IsTest
static void beforeUpdate_detectsRevenueChange() {
    Id accountId = fakeAccountId();

    Account oldAcc = new Account(Id = accountId, Name = 'Acme', AnnualRevenue = 100);
    Account newAcc = new Account(Id = accountId, Name = 'Acme', AnnualRevenue = 200);

    new AccountHandler()
        .withNew(new List<SObject>{ newAcc })
        .withOldMap(new Map<Id, SObject>{ accountId => oldAcc })
        .withContext(System.TriggerOperation.BEFORE_UPDATE)
        .run();

    System.assertEquals('Revenue changed', newAcc.Description);
}
```

Call `TriggerHandler.clearAll()` in test setup when tests touch bypass, loop, process-once, or state-bag state.

---

## Field Change Helpers

Compare old and new values without manual `oldMap.get()` boilerplate. Requires `oldMap` (via `.fromTrigger()`, `.withOldMap()`, or explicit wiring).

```apex
protected override void beforeUpdate() {
    for (Account acc : (List<Account>) changedRecords(Account.AnnualRevenue)) {
        acc.Description = 'Revenue changed';
    }

    for (Account acc : (List<Account>) this.newRecords) {
        if (hasChanged(acc, Account.Name)) {
            // single field
        }
        if (hasChanged(acc, new List<SObjectField>{ Account.Name, Account.Phone })) {
            // any listed field changed
        }
        Account prior = (Account) getOld(acc);
    }
}
```

| Method | Returns |
|--------|---------|
| `getOld(SObject record)` | Old version from `oldMap`, or `null` |
| `hasChanged(SObject, SObjectField)` | `true` if the field value differs |
| `hasChanged(SObject, List<SObjectField>)` | `true` if any listed field changed |
| `changedRecords(SObjectField)` | Subset of `newRecords` where the field changed |

On insert (no `oldMap`), helpers return `false` / empty lists.

---

## Fluent API

All methods except `run()` return `this` and can be chained.

| Method | Purpose |
|--------|---------|
| `withNew(List<SObject>)` | Provide current/new records |
| `withOld(List<SObject>)` | Provide old records (update/delete) |
| `withOldMap(Map<Id, SObject>)` | Provide old record map |
| `withNewMap(Map<Id, SObject>)` | Provide new record map |
| `fromTrigger()` | Auto-wire all four collections from `Trigger` |
| `withContext(System.TriggerOperation)` | Set operation — **required in tests** |
| `maxLoops(Integer)` | Limit re-entries; throws when exceeded |
| `maxLoops(Integer, Boolean)` | Second arg `false` = soft exit instead of throw |
| `trackLimits()` | Log governor limits after execution |
| `onlyThese(Set<Id>)` | Filter to specific record Ids |
| `bypassIf(Boolean)` | Skip this run when condition is `true` |
| `bypassIfPermission(String)` | Skip when user has the Custom Permission |
| `processOnce()` | De-duplicate records per handler + context per transaction |
| `run()` | **Terminal** — validate, dispatch, cleanup |

---

## Bypass API

**Static bypass** — skip a handler for the remainder of the transaction (tests, migrations, recursive updates):

```apex
TriggerHandler.bypass(AccountHandler.class);
TriggerHandler.isBypassed(AccountHandler.class);   // true
TriggerHandler.clearBypass(AccountHandler.class);
TriggerHandler.clearAllBypasses();
```

**Instance bypass** — skip only the current chain invocation:

```apex
new AccountHandler()
    .fromTrigger()
    .bypassIf(UserInfo.getUserId() == integrationUserId)
    .run();

new AccountHandler()
    .fromTrigger()
    .bypassIfPermission('Skip_Account_Trigger')
    .run();
```

`bypassIfPermission` uses `FeatureManagement.checkPermission`. If the permission does not exist, the handler runs normally.

When bypassed (static or instance), dispatch and `andFinally()` do not run.

---

## Loop Limits

Use `.maxLoops(n)` when a handler may update records that re-fire the same trigger.

```apex
new AccountHandler().fromTrigger().maxLoops(3).run();
```

- Tracking is keyed per **handler + operation** (`AccountHandler::BEFORE_UPDATE`), so `BEFORE_INSERT` and `AFTER_INSERT` each get their own budget.
- Default behavior throws `TriggerHandlerException` when exceeded.
- Pass `false` as the second argument to soft-exit silently: `.maxLoops(3, false)`.

Reset counters with `TriggerHandler.clearAll()`.

---

## Process Once

`.processOnce()` ensures each record is handled at most once per handler + operation for the transaction. On re-entry (e.g. recursive DML), already-processed records are filtered out.

```apex
new AccountHandler().fromTrigger().processOnce().run();
```

Records without an Id (`BEFORE_INSERT`) always pass through — they cannot be de-duplicated.

If every record was already processed, the handler soft-exits (no dispatch, no `andFinally()`).

Reset tracking with `TriggerHandler.clearAll()`.

---

## Record Filtering

Process only a subset of records in the current batch:

```apex
new AccountHandler()
    .fromTrigger()
    .onlyThese(new Set<Id>{ parentAccountId })
    .run();
```

Filtering applies to `newRecords`, `oldRecords`, `oldMap`, and `newMap` before dispatch.

**Limitation:** `onlyThese()` cannot be used in `BEFORE_INSERT` because records do not have Ids yet.

---

## Transaction State Bag

Hand data from `before` to `after` (or between handlers) without re-querying:

```apex
protected override void beforeUpdate() {
    putState('idsToSync', new Set<Id>{ acc.Id });
}

protected override void afterUpdate() {
    Set<Id> ids = (Set<Id>) getState('idsToSync');
    if (hasState('idsToSync')) {
        // enqueue sync job for ids
    }
}
```

State is transaction-scoped and cleared by `TriggerHandler.clearAll()`.

---

## Governor Limit Tracking

```apex
new AccountHandler().fromTrigger().trackLimits().run();
```

By default, deltas are written with `System.debug`. Override `logLimits()` to route to your logging framework:

```apex
protected override void logLimits(
    String handlerName,
    Integer queriesBefore,
    Integer dmlBefore,
    Integer cpuBefore
) {
    // route to custom logger
}
```

---

## Hooks

### `andFinally()`

Runs after the context method in a `finally` block — even when the override throws.

Does **not** run when the handler is bypassed, soft-exits due to loop limits, or soft-exits because `processOnce()` filtered all records.

```apex
protected override void andFinally() {
    // cleanup, summary validation, cross-cutting concerns
}
```

### `onError(Exception e)`

Called when a dispatched method throws, before the exception is rethrown. Override to log or route errors; the default is a no-op rethrow.

```apex
protected override void onError(Exception e) {
    System.debug(LoggingLevel.ERROR, 'AccountHandler failed: ' + e.getMessage());
}
```

---

## Examples

### Full Account handler

```apex
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
        putState('insertedCount', this.newRecords.size());
    }

    protected override void andFinally() {
        System.debug(LoggingLevel.FINE, 'AccountHandler finished: ' + this.triggerOp);
    }
}
```

### Delete trigger

For delete contexts, `Trigger.new` is empty. Use `.fromTrigger()` or pass old records explicitly:

```apex
trigger AccountTrigger on Account (before delete, after delete) {
    new AccountHandler().fromTrigger().run();
}
```

### Bypass in a test

```apex
@IsTest
static void insertWithoutHandlerSideEffects() {
    TriggerHandler.bypass(AccountHandler.class);

    insert new Account(Name = 'No Handler');

    TriggerHandler.clearAll();
}
```

### Recursive update guard

```apex
trigger OpportunityTrigger on Opportunity (before update, after update) {
    new OpportunityHandler()
        .fromTrigger()
        .maxLoops(2)
        .processOnce()
        .run();
}
```

### Integration user skip

```apex
trigger AccountTrigger on Account (before update) {
    new AccountHandler()
        .fromTrigger()
        .bypassIf(UserInfo.getUserType() == 'AutomatedProcess')
        .run();
}
```

---

## Best Practices

1. **Always use `super(YourHandler.class)`** for stable bypass, loop, and process-once keys.
2. **Prefer `.fromTrigger()`** in production triggers — one readable line.
3. **Use `changedRecords()` / `hasChanged()`** instead of manual old/new field compares.
4. **Use `.withContext()` in every test** that calls `.run()` outside a trigger.
5. **Call `TriggerHandler.clearAll()`** in tests that use bypass, loops, process-once, or state bag.
6. **Set `.maxLoops()` and/or `.processOnce()`** on handlers that DML the same object.
7. **Use static bypass** for tests and migrations; **use `.bypassIf()`** for runtime conditions.
8. **Use `putState()` / `getState()`** to pass computed data from before to after without re-querying.
9. **Override `logLimits()` and `onError()`** instead of scattering debug/logging in handler methods.

---

## Errors

| Situation | Exception / behavior |
|-----------|----------------------|
| `run()` outside trigger without `.withContext()` | `TriggerHandlerException`: called outside of trigger execution |
| Test missing `.withContext()` | `TriggerHandlerException`: Trigger operation is null |
| Loop limit exceeded (default) | `TriggerHandlerException`: Maximum loop count reached |
| `onlyThese()` on `BEFORE_INSERT` | `TriggerHandlerException`: records have no Id yet |
| Static or instance bypass | Silent skip — no dispatch, no `andFinally()` |
| Loop soft-exit (`maxLoops(n, false)`) | Silent skip |
| `processOnce()` filtered all records | Silent skip |

Custom errors in your handler should use `TriggerHandler.TriggerHandlerException` or domain-specific exceptions as appropriate.
