# TriggerHandler

A fluent trigger handler base class for Salesforce Apex.

This framework keeps what works from Kevin O'Hara's and dschach's handlers—static bypass control and recursion limits—and fixes their two biggest pain points.

**Testable by design.** Records are passed in explicitly via `withNew()`, `withOld()`, `withOldMap()`, and `withNewMap()` instead of being read from static Trigger context. Handler logic can be unit-tested without mocking Trigger, and without running DML just to exercise a branch.

**A fluent, refactor-safe API.** Triggers stay thin and readable through method chaining. The Type-based constructor (`super(AccountHandler.class)`) supplies stable handler names for bypass and loop tracking—no fragile `toString()` name parsing when classes are renamed.

Beyond those fixes, it adds capabilities the older patterns lack: record filtering with `onlyThese()`, an `andFinally()` hook that runs even when a handler throws, per-context loop budgets with optional soft-exit, type-safe bypass helpers, and an overridable governor-limit logger you can route to your own logging framework.

If you want zero dependencies, straightforward testing, and a modern API, this is a strong fit—just know you are trading some community maturity and third-party ecosystem for that simplicity.

## Table of Contents

- [TriggerHandler](#triggerhandler)
  - [Table of Contents](#table-of-contents)
  - [Quick Start](#quick-start)
  - [Guide](#guide)
    - [1. Create a handler class](#1-create-a-handler-class)
    - [2. Wire the trigger](#2-wire-the-trigger)
    - [3. Override context methods](#3-override-context-methods)
    - [4. Test without trigger context](#4-test-without-trigger-context)
  - [Fluent API](#fluent-api)
  - [Bypass API](#bypass-api)
  - [Loop Limits](#loop-limits)
  - [Record Filtering](#record-filtering)
  - [Governor Limit Tracking](#governor-limit-tracking)
  - [Cleanup with `andFinally()`](#cleanup-with-andfinally)
  - [Examples](#examples)
    - [Full Account handler](#full-account-handler)
    - [Delete trigger](#delete-trigger)
    - [Bypass in a test](#bypass-in-a-test)
    - [Recursive update guard](#recursive-update-guard)
    - [Test with record filter](#test-with-record-filter)
  - [Best Practices](#best-practices)
  - [Errors](#errors)

---

## Quick Start

**Trigger**

```apex
trigger AccountTrigger on Account (before insert, before update, after insert, after update) {
    new AccountHandler()
        .withNew(Trigger.new)
        .withOld(Trigger.old)
        .withOldMap((Map<Id, SObject>) Trigger.oldMap)
        .withNewMap((Map<Id, SObject>) Trigger.newMap)
        .maxLoops(5)
        .run();
}
```

**Handler**

```apex
public class AccountHandler extends TriggerHandler {
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
}
```

**Test**

```apex
@IsTest
static void beforeInsert_setsDescription() {
    List<Account> records = new List<Account>{
        new Account(Name = 'Test Co')
    };

    new AccountHandler()
        .withNew(records)
        .withContext(System.TriggerOperation.BEFORE_INSERT)
        .run();

    System.assertEquals('Created via TriggerHandler', records[0].Description);
}
```

---

## Guide

### 1. Create a handler class

Extend `TriggerHandler` and pass your concrete class type to the constructor. That gives you a stable handler name for bypass and loop tracking (refactor-safe, no string parsing).

```apex
public class AccountHandler extends TriggerHandler {
    public AccountHandler() {
        super(AccountHandler.class);
    }
}
```

Use `inherited sharing` on the base class so your handler respects `with sharing` / `without sharing` on the concrete class.

### 2. Wire the trigger

Keep the trigger thin: instantiate the handler, pass trigger context through the fluent chain, and call `run()`.

| Trigger context | Pass to handler |
|-----------------|-----------------|
| `Trigger.new` | `.withNew(Trigger.new)` |
| `Trigger.old` | `.withOld(Trigger.old)` |
| `Trigger.oldMap` | `.withOldMap((Map<Id, SObject>) Trigger.oldMap)` |
| `Trigger.newMap` | `.withNewMap((Map<Id, SObject>) Trigger.newMap)` |

`Trigger.operationType` is read automatically in trigger context. You do not need `.withContext()` in a real trigger.

Optional chain methods:

- `.maxLoops(n)` — prevent runaway recursion
- `.trackLimits()` — log SOQL, DML, and CPU consumed by this handler
- `.onlyThese(recordIds)` — process only specific records (not valid on `BEFORE_INSERT`)

### 3. Override context methods

Override the virtual methods that match the trigger events you handle. Inside overrides, use the protected fields populated by the fluent chain:

| Field | Description |
|-------|-------------|
| `this.newRecords` | Current/new records (`Trigger.new`) |
| `this.oldRecords` | Prior records (`Trigger.old`) |
| `this.oldMap` | Id → old record map |
| `this.newMap` | Id → new record map |
| `this.triggerOp` | Current operation (`BEFORE_INSERT`, `AFTER_UPDATE`, etc.) |

```apex
protected override void beforeUpdate() {
    for (Account acc : (List<Account>) this.newRecords) {
        Account oldAcc = (Account) this.oldMap.get(acc.Id);
        if (acc.AnnualRevenue != oldAcc.AnnualRevenue) {
            acc.Description = 'Revenue changed';
        }
    }
}

protected override void afterInsert() {
    // this.newMap is available after insert
    for (Account acc : (List<Account>) this.newRecords) {
        // enqueue work, publish platform events, etc.
    }
}
```

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
```

### 4. Test without trigger context

In tests, pass records directly and set the operation with `.withContext()`. No `Test.startTest()` trigger hacks or static mocks required.

```apex
@IsTest
static void beforeUpdate_detectsRevenueChange() {
    Id accountId = TestUtility.getFakeId(Account.SObjectType);

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

Call `TriggerHandler.clearAll()` in test setup when tests touch bypass or loop state:

```apex
@IsTest
static void setup() {
    TriggerHandler.clearAll();
}
```

---

## Fluent API

All methods except `run()` return `this` and can be chained in any order.

| Method | Purpose |
|--------|---------|
| `withNew(List<SObject>)` | Provide current/new records |
| `withOld(List<SObject>)` | Provide old records (update/delete) |
| `withOldMap(Map<Id, SObject>)` | Provide old record map |
| `withNewMap(Map<Id, SObject>)` | Provide new record map (after insert/update/undelete) |
| `withContext(System.TriggerOperation)` | Set operation — **required in tests** |
| `maxLoops(Integer)` | Limit re-entries; throws when exceeded |
| `maxLoops(Integer, Boolean)` | Second arg `false` = soft exit instead of throw |
| `trackLimits()` | Log governor limits after execution |
| `onlyThese(Set<Id>)` | Filter to specific record Ids |
| `run()` | **Terminal** — validate, dispatch, cleanup |

---

## Bypass API

Skip a handler for the remainder of the transaction (useful in tests, data migration, or recursive updates).

```apex
// By class name or Type
TriggerHandler.bypass('AccountHandler');
TriggerHandler.bypass(AccountHandler.class);

TriggerHandler.isBypassed(AccountHandler.class);   // true
TriggerHandler.clearBypass(AccountHandler.class);

TriggerHandler.getBypassedHandlers();              // defensive copy
TriggerHandler.clearAllBypasses();
TriggerHandler.clearAll();                         // bypasses + loop counters
```

When bypassed, the handler does not dispatch and `andFinally()` does not run.

---

## Loop Limits

Use `.maxLoops(n)` when a handler may update records that re-fire the same trigger.

```apex
new AccountHandler()
    .withNew(Trigger.new)
    .maxLoops(3)
    .run();
```

- Tracking is keyed per **handler + operation** (`AccountHandler::BEFORE_UPDATE`), so `BEFORE_INSERT` and `AFTER_INSERT` each get their own budget.
- Default behavior throws `TriggerHandlerException` when the limit is exceeded.
- Pass `false` as the second argument to soft-exit silently:

```apex
.maxLoops(3, false)   // stops running; does not throw
```

Reset counters in tests with `TriggerHandler.clearAll()`.

---

## Record Filtering

Process only a subset of records in the current batch:

```apex
new AccountHandler()
    .withNew(Trigger.new)
    .withOld(Trigger.old)
    .onlyThese(new Set<Id>{ parentAccountId })
    .run();
```

Filtering applies to `newRecords`, `oldRecords`, `oldMap`, and `newMap` before dispatch.

**Limitation:** `onlyThese()` cannot be used in `BEFORE_INSERT` because records do not have Ids yet.

---

## Governor Limit Tracking

Enable per-handler limit logging:

```apex
new AccountHandler()
    .withNew(Trigger.new)
    .trackLimits()
    .run();
```

By default, deltas are written with `System.debug`. Override `logLimits()` to integrate with your logging framework (e.g. Nebula Logger):

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

## Cleanup with `andFinally()`

`andFinally()` runs after the context method in a `finally` block — even when the override throws. Use it for cleanup, summary validation, or cross-cutting concerns.

It does **not** run when the handler is bypassed or soft-exits due to loop limits.

```apex
protected override void andFinally() {
    // always runs after beforeInsert/beforeUpdate/... unless bypassed
}
```

---

## Examples

### Full Account handler

```apex
public class AccountHandler extends TriggerHandler {
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
        for (Account acc : (List<Account>) this.newRecords) {
            Account oldAcc = (Account) this.oldMap.get(acc.Id);
            if (acc.AnnualRevenue != oldAcc.AnnualRevenue) {
                acc.Description = 'Revenue changed';
            }
        }
    }

    protected override void afterInsert() {
        List<Account> toNotify = (List<Account>) this.newRecords;
        // publish events, enqueue async work, etc.
    }

    protected override void andFinally() {
        System.debug(LoggingLevel.FINE, 'AccountHandler finished: ' + this.triggerOp);
    }
}
```

### Delete trigger

For delete contexts, `Trigger.new` is empty. Pass old records:

```apex
trigger AccountTrigger on Account (before delete, after delete) {
    new AccountHandler()
        .withOld(Trigger.old)
        .withOldMap((Map<Id, SObject>) Trigger.oldMap)
        .run();
}
```

```apex
protected override void beforeDelete() {
    for (Account acc : (List<Account>) this.oldRecords) {
        if (acc.Name == 'Protected') {
            acc.addError('Cannot delete protected accounts.');
        }
    }
}
```

### Bypass in a test

```apex
@IsTest
static void insertWithoutHandlerSideEffects() {
    TriggerHandler.bypass(AccountHandler.class);

    Account acc = new Account(Name = 'No Handler');
    insert acc;

    TriggerHandler.clearBypass(AccountHandler.class);
    // or TriggerHandler.clearAll();
}
```

### Recursive update guard

```apex
trigger OpportunityTrigger on Opportunity (before update, after update) {
    new OpportunityHandler()
        .withNew(Trigger.new)
        .withOldMap((Map<Id, SObject>) Trigger.oldMap)
        .maxLoops(2)
        .run();
}
```

### Test with record filter

```apex
@IsTest
static void onlyThese_processesSubset() {
    Id keep = TestUtility.getFakeId(Account.SObjectType);
    Id skip = TestUtility.getFakeId(Account.SObjectType);

    List<SObject> records = new List<SObject>{
        new Account(Id = keep, Name = 'Keep'),
        new Account(Id = skip, Name = 'Skip')
    };

    TestHandler h = new TestHandler();
    h.withNew(records)
        .onlyThese(new Set<Id>{ keep })
        .withContext(System.TriggerOperation.BEFORE_UPDATE)
        .run();

    System.assertEquals(1, h.capturedNew.size());
}
```

---

## Best Practices

1. **Always use `super(YourHandler.class)`** in the constructor for stable bypass/loop keys.
2. **Keep triggers one line** — all logic belongs in the handler class.
3. **Cast record lists** to your SObject type inside overrides: `(List<Account>) this.newRecords`.
4. **Use `.withContext()` in every test** that calls `.run()` outside a trigger.
5. **Call `TriggerHandler.clearAll()`** in `@TestSetup` or `@IsTest` methods that use bypass or loop limits.
6. **Set `.maxLoops()`** on handlers that perform DML on the same object.
7. **Prefer bypass over commented-out trigger code** for migrations and isolated tests.
8. **Override `logLimits()`** instead of sprinkling debug statements when profiling governor usage.

---

## Errors

| Situation | Exception |
|-----------|-----------|
| `run()` outside trigger without `.withContext()` | `TriggerHandlerException`: called outside of trigger execution |
| Test missing `.withContext()` | `TriggerHandlerException`: Trigger operation is null |
| Loop limit exceeded (default) | `TriggerHandlerException`: Maximum loop count reached |
| `onlyThese()` on `BEFORE_INSERT` | `TriggerHandlerException`: records have no Id yet |

Custom errors in your handler should use `TriggerHandler.TriggerHandlerException` or domain-specific exceptions as appropriate.
