<div align="center">
  <h1>sf-devkit</h1>
  <p><strong>A growing collection of Salesforce utilities and toolkits—for clarity, tests, and AI-assisted development.</strong></p>
  <p>Independent modules you can adopt à la carte. TriggerHandler and UnitOfWork are available today; more toolkits ship here over time.</p>
  <br>

  <a href="https://github.com/ehsankorhani/sf-devkit/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge"></a>
  <img alt="API version" src="https://img.shields.io/badge/api-v66.0-blue?style=for-the-badge">
  <img alt="Salesforce" src="https://img.shields.io/badge/platform-Salesforce-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white">
</div>

---

## What is sf-devkit

This repository is a **monorepo of focused toolkits** for Salesforce developers and architects—not a single framework. Each module under `force-app/main/<name>/` is self-contained with its own README, source, and tests. Use one module, combine several, or watch the catalog grow as new utilities land.

---

## Why sf-devkit

### Simplicity

Every toolkit favors readable APIs, explicit data flow, and minimal ceremony—whether that means a one-line trigger or a small utility you drop into an existing project.

### AI-friendly

Consistent patterns and documentation structured so assistants can extend code, write tests, and reason about behavior without guessing project-specific conventions.

### Feature richness

Practical production concerns (guards, bypass, limits, helpers) where they matter—without bundling unrelated capabilities or forcing an all-or-nothing adoption.

---

## Modules

| Status | Module | Path | Summary |
|--------|--------|------|---------|
| Available | TriggerHandler | [force-app/main/triggerHandler/](force-app/main/triggerHandler/) | Fluent, testable Apex trigger base class |
| Available | UnitOfWork | [force-app/main/unitOfWork/](force-app/main/unitOfWork/) | Fluent Unit of Work for transactional DML |
| Planned | — | — | Additional utilities and toolkits will be added gradually |

Each module ships under `force-app/main/<name>/` with dedicated documentation. Pull only what you need into your org.

### TriggerHandler

A fluent trigger handler base class for Apex. Records pass through the chain explicitly, so handler logic is unit-testable without mocking `Trigger`.

```apex
trigger AccountTrigger on Account (before insert, before update, after insert, after update) {
    new AccountHandler().fromTrigger().maxLoops(5).run();
}
```

- **Test without trigger context** — pass records with `.withNew()` and `.withContext()` in `@IsTest` methods
- **Field-change helpers** — `changedRecords()`, `hasChanged()`, and `getOld()` instead of manual map compares
- **Production controls** — static and instance bypass, loop limits, process-once, governor limit tracking

**Documentation:** [TriggerHandler README](force-app/main/triggerHandler/README.md) · **Examples:** [examples/main/](examples/main/)

### UnitOfWork

A fluent Unit of Work for Apex: register inserts, updates, upserts, and deletes across your service layer, then commit once. Parent/child lookups are resolved automatically and the whole transaction rolls back on failure.

```apex
Account parentAcc = new Account(Name = 'Acme');
Contact childCon = new Contact(LastName = 'Doe');

new UnitOfWork()
    .registerNew(parentAcc)
    .registerNew(childCon)
    .withParent(Contact.SObjectType.fields.AccountId, parentAcc)
    .commitWork();
```

- **One transactional commit** — `commitWork()` bulkifies DML by SObject type and rolls back via `Savepoint` on any failure
- **Smart insert ordering** — topological sort on `withParent()` / `registerRelationship()` so registration order does not matter
- **Testable by design** — program against `IUnitOfWork` with an injectable `IUnitOfWorkDML` seam for unit tests without database DML
- **Production options** — user/system mode, `allOrNone`, optimistic concurrency via `withConcurrencyCheck()`, and `onCommitSuccess()` hooks

**Documentation:** [UnitOfWork README](force-app/main/unitOfWork/README.md) · **Examples:** [examples/main/unitOfWork/](examples/main/unitOfWork/)

---

## Adopt in your org

**Any module**

1. Copy the module's folder from `force-app/main/<name>/` into your Salesforce project (or add this repo as a submodule/subtree).
2. Ensure your project's `sourceApiVersion` is **66.0** or higher (see [sfdx-project.json](sfdx-project.json)).
3. Follow that module's README for wiring and tests.
4. Deploy with your usual SFDX or CI workflow.

**TriggerHandler** — extend `TriggerHandler`, implement context overrides, and wire triggers with `.fromTrigger()`. See the [module README](force-app/main/triggerHandler/README.md) for the full guide.

**UnitOfWork** — construct `UnitOfWork` (or inject `IUnitOfWork` in services), register work fluently, and call `commitWork()` once per business transaction. See the [module README](force-app/main/unitOfWork/README.md) for the full guide.

The `examples/` package directory is included for local reference; it is not a default deploy path in this project.

---

## Contributing

New toolkits belong under `force-app/main/<name>/` with a dedicated README, tests, and examples where helpful. Open an issue or pull request on [GitHub](https://github.com/ehsankorhani/sf-devkit).

## License

[MIT](LICENSE) — Copyright (c) 2026 sf-devkit contributors
