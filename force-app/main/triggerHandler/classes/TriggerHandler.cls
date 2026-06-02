/**
 * Copyright (c) 2026 Ehsan Korhani
 * SPDX-License-Identifier: MIT
 *
 * @author Ehsan Korhani
 * @version 1.0.0
 */
public inherited sharing virtual class TriggerHandler {

    @TestVisible
    private static Map<String, LoopTracker> loopTracker = new Map<String, LoopTracker>();

    @TestVisible
    private static Set<String> bypassedHandlers = new Set<String>();

    @TestVisible
    private static Map<String, Set<Id>> processedRecords = new Map<String, Set<Id>>();

    @TestVisible
    private static Map<String, Object> stateBag = new Map<String, Object>();

    @TestVisible
    protected List<SObject> newRecords;

    @TestVisible
    protected List<SObject> oldRecords;

    @TestVisible
    protected Map<Id, SObject> oldMap;

    @TestVisible
    protected Map<Id, SObject> newMap;

    @TestVisible
    protected System.TriggerOperation triggerOp;

    @TestVisible
    protected Boolean isTestContext = false;

    @TestVisible
    protected Integer maxLoops;

    @TestVisible
    protected Boolean throwOnMaxLoops = true;

    @TestVisible
    protected Boolean shouldTrackLimits = false;

    @TestVisible
    protected Set<Id> recordFilter;

    @TestVisible
    protected Boolean instanceBypassed = false;

    @TestVisible
    protected Boolean processOnceEnabled = false;

    private String handlerName;

    /**
     * Default constructor. Falls back to parsing the class name from the object
     * string. Prefer the Type-based constructor for stability and performance.
     */
    public TriggerHandler() {
    }

    /**
     * Preferred constructor — provides a stable, refactor-safe handler name
     * without serializing the entire object state on every run().
     */
    public TriggerHandler(Type handlerType) {
        this.handlerName = handlerType.getName();
    }

    /**
     * Provide the new (or current) version of records.
     * For delete operations, this is typically null and oldRecords is used.
     */
    public TriggerHandler withNew(List<SObject> records) {
        this.newRecords = records;
        return this;
    }

    /**
     * Provide the old version of records (before the update/delete).
     */
    public TriggerHandler withOld(List<SObject> records) {
        this.oldRecords = records;
        return this;
    }

    /**
     * Provide a map of Id -> old SObject for update/delete contexts.
     */
    public TriggerHandler withOldMap(Map<Id, SObject> oldMap) {
        this.oldMap = oldMap;
        return this;
    }

    /**
     * Provide a map of Id -> new SObject for after-insert/update/undelete contexts.
     */
    public TriggerHandler withNewMap(Map<Id, SObject> newMap) {
        this.newMap = newMap;
        return this;
    }

    /**
     * Auto-wire all record collections from the running Trigger context.
     * Convenience for production triggers: new AccountHandler().fromTrigger().run();
     * The operation type is still resolved from Trigger.operationType in run().
     */
    public TriggerHandler fromTrigger() {
        this.newRecords = Trigger.new;
        this.oldRecords = Trigger.old;
        this.oldMap = Trigger.oldMap;
        this.newMap = Trigger.newMap;
        return this;
    }

    /**
     * Explicitly set the trigger operation context.
     * Required in test methods where Trigger.operationType is unavailable.
     */
    public TriggerHandler withContext(System.TriggerOperation op) {
        this.triggerOp = op;
        this.isTestContext = true;
        return this;
    }

    /**
     * Limit the number of times this handler+context can re-enter.
     * Throws TriggerHandlerException if exceeded.
     */
    public TriggerHandler maxLoops(Integer max) {
        return maxLoops(max, true);
    }

    /**
     * Limit the number of times this handler+context can re-enter.
     * When throwOnExceed is false, the handler soft-exits (stops running)
     * instead of throwing, letting the rest of the transaction proceed.
     */
    public TriggerHandler maxLoops(Integer max, Boolean throwOnExceed) {
        this.maxLoops = max;
        this.throwOnMaxLoops = throwOnExceed;
        return this;
    }

    /**
     * Enable governor limit logging after execution.
     * Logs query, DML, and CPU deltas consumed by this handler.
     */
    public TriggerHandler trackLimits() {
        this.shouldTrackLimits = true;
        return this;
    }

    /**
     * Restrict processing to only the records with the given IDs.
     * Filtering is applied to new/old lists and maps before dispatch.
     * Not valid in BEFORE_INSERT (records have no Id yet).
     */
    public TriggerHandler onlyThese(Set<Id> recordIds) {
        this.recordFilter = recordIds;
        return this;
    }

    /**
     * Skip this handler invocation when the condition is true.
     * Useful for user/profile/data-load driven bypass, e.g.
     *   .bypassIf(UserInfo.getUserId() == integrationUserId)
     * Unlike the static bypass API, this affects only the current run.
     */
    public TriggerHandler bypassIf(Boolean condition) {
        if (condition == true) {
            this.instanceBypassed = true;
        }
        return this;
    }

    /**
     * Skip this handler invocation when the running user has the given
     * Custom Permission. No hard dependency: if the permission does not
     * exist, checkPermission returns false and the handler runs normally.
     */
    public TriggerHandler bypassIfPermission(String customPermissionApiName) {
        return bypassIf(FeatureManagement.checkPermission(customPermissionApiName));
    }

    /**
     * Process each record at most once per handler+context for the duration of
     * the transaction. On re-entry, already-processed records are filtered out,
     * so recursive DML re-runs only the records it hasn't seen. Records without
     * an Id (e.g. BEFORE_INSERT) cannot be de-duplicated and always pass through.
     */
    public TriggerHandler processOnce() {
        this.processOnceEnabled = true;
        return this;
    }

    /**
     * Terminal method — executes the handler.
     * Validates context, checks bypass, enforces loop limits,
     * applies filters, dispatches to the appropriate virtual method,
     * always calls andFinally(), and optionally logs governor limits.
     */
    public void run() {
        if (!Trigger.isExecuting && !this.isTestContext) {
            throw new TriggerHandlerException(
                'Trigger handler called outside of trigger execution'
            );
        }

        if (this.triggerOp == null) {
            this.triggerOp = Trigger.operationType;
        }

        if (this.triggerOp == null) {
            throw new TriggerHandlerException(
                'Trigger operation is null. If running in a test, ' +
                'call withContext(System.TriggerOperation) before run().'
            );
        }

        if (this.instanceBypassed) {
            return;
        }

        String resolvedName = resolveHandlerName();

        if (bypassedHandlers.contains(resolvedName)) {
            return;
        }

        if (!withinLoopLimit(resolvedName + '::' + this.triggerOp)) {
            return;
        }

        guardFilterContext();
        applyFilter();

        if (this.processOnceEnabled &&
            !applyProcessOnce(resolvedName + '::' + this.triggerOp)) {
            return;
        }

        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        Integer cpuBefore = Limits.getCpuTime();

        try {
            dispatch();
        } catch (Exception e) {
            onError(e);
            throw e;
        } finally {
            andFinally();
            if (this.shouldTrackLimits) {
                logLimits(resolvedName, queriesBefore, dmlBefore, cpuBefore);
            }
        }
    }

    private void dispatch() {
        switch on this.triggerOp {
            when BEFORE_INSERT {
                beforeInsert();
            }
            when BEFORE_UPDATE {
                beforeUpdate();
            }
            when BEFORE_DELETE {
                beforeDelete();
            }
            when AFTER_INSERT {
                afterInsert();
            }
            when AFTER_UPDATE {
                afterUpdate();
            }
            when AFTER_DELETE {
                afterDelete();
            }
            when AFTER_UNDELETE {
                afterUndelete();
            }
        }
    }

    /**
     * Returns true if the handler may proceed, false if it should soft-exit.
     * Throws when the limit is exceeded and throwOnMaxLoops is true.
     * Tracking is keyed per handler+context so a normal insert (before + after)
     * does not consume a single handler's budget twice.
     */
    private Boolean withinLoopLimit(String loopKey) {
        if (this.maxLoops == null) {
            return true;
        }

        LoopTracker tracker = loopTracker.get(loopKey);
        if (tracker == null) {
            tracker = new LoopTracker(this.maxLoops);
            loopTracker.put(loopKey, tracker);
        } else {
            tracker.max = this.maxLoops;
        }

        tracker.count++;
        if (tracker.count > tracker.max) {
            if (this.throwOnMaxLoops) {
                throw new TriggerHandlerException(
                    'Maximum loop count of ' + tracker.max +
                    ' reached in ' + loopKey
                );
            }
            return false;
        }
        return true;
    }

    private void guardFilterContext() {
        if (this.recordFilter != null &&
            this.triggerOp == System.TriggerOperation.BEFORE_INSERT) {
            throw new TriggerHandlerException(
                'onlyThese() cannot be used in BEFORE_INSERT because records have no Id yet.'
            );
        }
    }

    private void applyFilter() {
        if (this.recordFilter == null) {
            return;
        }

        if (this.newRecords != null) {
            List<SObject> filtered = new List<SObject>();
            for (SObject rec : this.newRecords) {
                if (this.recordFilter.contains(rec.Id)) {
                    filtered.add(rec);
                }
            }
            this.newRecords = filtered;
        }

        if (this.oldRecords != null) {
            List<SObject> filtered = new List<SObject>();
            for (SObject rec : this.oldRecords) {
                if (this.recordFilter.contains(rec.Id)) {
                    filtered.add(rec);
                }
            }
            this.oldRecords = filtered;
        }

        this.oldMap = filterMap(this.oldMap);
        this.newMap = filterMap(this.newMap);
    }

    private Map<Id, SObject> filterMap(Map<Id, SObject> source) {
        if (source == null) {
            return null;
        }
        Map<Id, SObject> filtered = new Map<Id, SObject>();
        for (Id key : source.keySet()) {
            if (this.recordFilter.contains(key)) {
                filtered.put(key, source.get(key));
            }
        }
        return filtered;
    }

    /**
     * Filters out records already processed under this key, marking the
     * remaining ones as processed. Returns true if anything is left to run.
     */
    private Boolean applyProcessOnce(String key) {
        Set<Id> processed = processedRecords.get(key);
        if (processed == null) {
            processed = new Set<Id>();
            processedRecords.put(key, processed);
        }

        Boolean useNew = this.newRecords != null;
        List<SObject> primary = useNew ? this.newRecords : this.oldRecords;
        if (primary == null) {
            return true;
        }

        Set<Id> keptIds = new Set<Id>();
        Boolean keptAny = false;
        List<SObject> remaining = new List<SObject>();
        for (SObject rec : primary) {
            if (rec.Id == null) {
                remaining.add(rec);
                keptAny = true;
            } else if (!processed.contains(rec.Id)) {
                remaining.add(rec);
                processed.add(rec.Id);
                keptIds.add(rec.Id);
                keptAny = true;
            }
        }

        if (useNew) {
            this.newRecords = remaining;
            if (this.oldRecords != null) {
                this.oldRecords = filterListByIds(this.oldRecords, keptIds);
            }
        } else {
            this.oldRecords = remaining;
        }
        this.oldMap = filterMapByIds(this.oldMap, keptIds);
        this.newMap = filterMapByIds(this.newMap, keptIds);

        return keptAny;
    }

    private List<SObject> filterListByIds(List<SObject> source, Set<Id> ids) {
        List<SObject> out = new List<SObject>();
        for (SObject rec : source) {
            if (rec.Id == null || ids.contains(rec.Id)) {
                out.add(rec);
            }
        }
        return out;
    }

    private Map<Id, SObject> filterMapByIds(Map<Id, SObject> source, Set<Id> ids) {
        if (source == null) {
            return null;
        }
        Map<Id, SObject> out = new Map<Id, SObject>();
        for (Id key : source.keySet()) {
            if (ids.contains(key)) {
                out.put(key, source.get(key));
            }
        }
        return out;
    }

    /**
     * Logs the governor limits consumed by this handler.
     * Override to route to a custom logging framework (e.g. Nebula Logger).
     */
    @TestVisible
    protected virtual void logLimits(
        String handlerName,
        Integer queriesBefore,
        Integer dmlBefore,
        Integer cpuBefore
    ) {
        System.debug(LoggingLevel.INFO,
            handlerName + ' [' + this.triggerOp + '] — ' +
            'Queries: ' + (Limits.getQueries() - queriesBefore) +
            '/' + Limits.getLimitQueries() + ', ' +
            'DML: ' + (Limits.getDmlStatements() - dmlBefore) +
            '/' + Limits.getLimitDmlStatements() + ', ' +
            'CPU: ' + (Limits.getCpuTime() - cpuBefore) + '/' +
            Limits.getLimitCpuTime() + ' ms'
        );
    }

    @TestVisible
    protected virtual String resolveHandlerName() {
        if (String.isNotBlank(this.handlerName)) {
            return this.handlerName;
        }
        return String.valueOf(this).substringBefore(':');
    }

    // ──────────────────────────────────────────────
    //  Field-change diff helpers (require oldMap)
    // ──────────────────────────────────────────────

    /**
     * Returns the old version of a record from oldMap, or null if unavailable.
     */
    @TestVisible
    protected SObject getOld(SObject record) {
        if (this.oldMap == null || record == null || record.Id == null) {
            return null;
        }
        return this.oldMap.get(record.Id);
    }

    /**
     * True if the given field value differs between the new record and its
     * old version. Returns false when no old version is available (e.g. insert).
     */
    @TestVisible
    protected Boolean hasChanged(SObject record, SObjectField field) {
        SObject oldRecord = getOld(record);
        if (oldRecord == null) {
            return false;
        }
        return record.get(field) != oldRecord.get(field);
    }

    /**
     * True if any of the given fields changed on the record.
     */
    @TestVisible
    protected Boolean hasChanged(SObject record, List<SObjectField> fields) {
        for (SObjectField field : fields) {
            if (hasChanged(record, field)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Returns the subset of newRecords whose given field changed.
     */
    @TestVisible
    protected List<SObject> changedRecords(SObjectField field) {
        List<SObject> changed = new List<SObject>();
        if (this.newRecords == null) {
            return changed;
        }
        for (SObject record : this.newRecords) {
            if (hasChanged(record, field)) {
                changed.add(record);
            }
        }
        return changed;
    }

    // ──────────────────────────────────────────────
    //  Virtual methods — override in concrete handler
    // ──────────────────────────────────────────────

    @TestVisible
    protected virtual void beforeInsert() {
    }

    @TestVisible
    protected virtual void beforeUpdate() {
    }

    @TestVisible
    protected virtual void beforeDelete() {
    }

    @TestVisible
    protected virtual void afterInsert() {
    }

    @TestVisible
    protected virtual void afterUpdate() {
    }

    @TestVisible
    protected virtual void afterDelete() {
    }

    @TestVisible
    protected virtual void afterUndelete() {
    }

    /**
     * Always called after the context-specific method (even if it throws),
     * unless the handler was bypassed or soft-exited via loop limit.
     * Useful for cleanup, validation summaries, or cross-cutting concerns.
     */
    @TestVisible
    protected virtual void andFinally() {
    }

    /**
     * Called when a dispatched method throws, before the exception is rethrown.
     * Override to log/route errors (e.g. Nebula Logger). The default rethrows
     * so transaction behavior is unchanged unless you override this hook.
     */
    @TestVisible
    protected virtual void onError(Exception e) {
    }

    // ──────────────────────────────────────────────
    //  Transaction state bag (before ↔ after handoff)
    // ──────────────────────────────────────────────

    /**
     * Stash a value in transaction-scoped state, e.g. so beforeUpdate can hand
     * data to afterUpdate without re-querying. Cleared by clearAll().
     */
    @TestVisible
    protected void putState(String key, Object value) {
        stateBag.put(key, value);
    }

    @TestVisible
    protected Object getState(String key) {
        return stateBag.get(key);
    }

    @TestVisible
    protected Boolean hasState(String key) {
        return stateBag.containsKey(key);
    }

    // ──────────────────────────────────────────────
    //  Static bypass API
    // ──────────────────────────────────────────────

    public static void bypass(String handlerName) {
        bypassedHandlers.add(handlerName);
    }
 
    public static void bypass(Type handlerType) {
        bypass(handlerType.getName());
    }

    public static void clearBypass(String handlerName) {
        bypassedHandlers.remove(handlerName);
    }

    public static void clearBypass(Type handlerType) {
        clearBypass(handlerType.getName());
    }

    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName);
    }

    public static Boolean isBypassed(Type handlerType) {
        return isBypassed(handlerType.getName());
    }

    public static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    public static Set<String> getBypassedHandlers() {
        return new Set<String>(bypassedHandlers);
    }

    /**
     * Reset all static state (bypasses, loop trackers, processed-record
     * tracking, and the transaction state bag).
     * Useful in test setup or when resetting between operations.
     */
    public static void clearAll() {
        clearAllBypasses();
        loopTracker.clear();
        processedRecords.clear();
        stateBag.clear();
    }

    // ──────────────────────────────────────────────
    //  Inner types
    // ──────────────────────────────────────────────

    public class TriggerHandlerException extends Exception {
    }

    @TestVisible
    private class LoopTracker {
        public Integer max;
        public Integer count;

        public LoopTracker(Integer max) {
            this.max = max;
            this.count = 0;
        }
    }
}
