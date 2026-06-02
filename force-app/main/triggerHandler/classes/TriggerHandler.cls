/**
 * @description Fluent Trigger Handler Framework
 *
 * A modern trigger handler with a true fluent API. Records are passed explicitly
 * via the fluent chain, making the framework testable by design without needing
 * to mock Trigger static context.
 *
 * Usage (in trigger):
 *   new AccountHandler()
 *       .withNew(Trigger.new)
 *       .withOld(Trigger.old)
 *       .withOldMap((Map<Id, SObject>) Trigger.oldMap)
 *       .withNewMap((Map<Id, SObject>) Trigger.newMap)
 *       .maxLoops(5)
 *       .trackLimits()
 *       .run();
 *
 * Usage (in test — no Trigger mocking needed):
 *   new AccountHandler()
 *       .withNew(testRecords)
 *       .withOld(testOldRecords)
 *       .withOldMap(testOldMap)
 *       .withContext(System.TriggerOperation.BEFORE_UPDATE)
 *       .run();
 *
 * Handler naming: pass the concrete Type to the constructor for a stable,
 * refactor-safe name used by bypass and loop tracking, e.g.
 *   public AccountHandler() { super(AccountHandler.class); }
 *
 * @group Trigger Handler
 */
public inherited sharing virtual class TriggerHandler {

    @TestVisible
    private static Map<String, LoopTracker> loopTracker = new Map<String, LoopTracker>();

    @TestVisible
    private static Set<String> bypassedHandlers = new Set<String>();

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

        String resolvedName = resolveHandlerName();

        if (bypassedHandlers.contains(resolvedName)) {
            return;
        }

        if (!withinLoopLimit(resolvedName + '::' + this.triggerOp)) {
            return;
        }

        guardFilterContext();
        applyFilter();

        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        Integer cpuBefore = Limits.getCpuTime();

        try {
            dispatch();
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
     * Reset all static state (bypasses and loop trackers).
     * Useful in test setup or when resetting between operations.
     */
    public static void clearAll() {
        clearAllBypasses();
        loopTracker.clear();
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
