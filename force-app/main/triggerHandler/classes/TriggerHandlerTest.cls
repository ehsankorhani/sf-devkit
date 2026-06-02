/**
 * @description Tests for the Fluent Trigger Handler Framework.
 * @group Trigger Handler
 */
@IsTest
private class TriggerHandlerTest {

    // ──────────────────────────────────────────────
    //  Test handlers
    // ──────────────────────────────────────────────

    private class TestHandler extends TriggerHandler {
        public String invokedMethod;
        public Boolean andFinallyCalled = false;
        public Boolean limitsLogged = false;
        public List<SObject> capturedNew;
        public List<SObject> capturedOld;
        public Map<Id, SObject> capturedNewMap;

        public TestHandler() {
            super(TestHandler.class);
        }

        protected override void beforeInsert() {
            this.invokedMethod = 'beforeInsert';
            this.capturedNew = this.newRecords;
        }

        protected override void beforeUpdate() {
            this.invokedMethod = 'beforeUpdate';
            this.capturedNew = this.newRecords;
            this.capturedOld = this.oldRecords;
        }

        protected override void beforeDelete() {
            this.invokedMethod = 'beforeDelete';
            this.capturedNew = this.newRecords;
            this.capturedOld = this.oldRecords;
        }

        protected override void afterInsert() {
            this.invokedMethod = 'afterInsert';
            this.capturedNew = this.newRecords;
            this.capturedNewMap = this.newMap;
        }

        protected override void afterUpdate() {
            this.invokedMethod = 'afterUpdate';
            this.capturedNew = this.newRecords;
            this.capturedOld = this.oldRecords;
        }

        protected override void afterDelete() {
            this.invokedMethod = 'afterDelete';
            this.capturedNew = this.newRecords;
            this.capturedOld = this.oldRecords;
        }

        protected override void afterUndelete() {
            this.invokedMethod = 'afterUndelete';
            this.capturedNew = this.newRecords;
        }

        protected override void andFinally() {
            this.andFinallyCalled = true;
        }

        protected override void logLimits(
            String handlerName,
            Integer queriesBefore,
            Integer dmlBefore,
            Integer cpuBefore
        ) {
            this.limitsLogged = true;
        }
    }

    private class ThrowingHandler extends TriggerHandler {
        public Boolean andFinallyCalled = false;

        public ThrowingHandler() {
            super(ThrowingHandler.class);
        }

        protected override void beforeInsert() {
            throw new TriggerHandlerException('boom');
        }

        protected override void andFinally() {
            this.andFinallyCalled = true;
        }
    }

    private class CountingHandler extends TriggerHandler {
        public Integer processedCount = 0;
        public List<SObject> lastProcessed;

        public CountingHandler() {
            super(CountingHandler.class);
        }

        protected override void afterUpdate() {
            this.lastProcessed = this.newRecords;
            this.processedCount += (this.newRecords == null ? 0 : this.newRecords.size());
        }
    }

    private class StateWriterHandler extends TriggerHandler {
        public StateWriterHandler() {
            super(StateWriterHandler.class);
        }

        protected override void beforeUpdate() {
            putState('computed', 42);
        }
    }

    private class StateReaderHandler extends TriggerHandler {
        public Boolean sawState = false;
        public Object readValue;

        public StateReaderHandler() {
            super(StateReaderHandler.class);
        }

        protected override void afterUpdate() {
            this.sawState = hasState('computed');
            this.readValue = getState('computed');
        }
    }

    private class ErrorHookHandler extends TriggerHandler {
        public Boolean onErrorCalled = false;
        public String capturedMessage;

        public ErrorHookHandler() {
            super(ErrorHookHandler.class);
        }

        protected override void beforeInsert() {
            throw new TriggerHandlerException('kaboom');
        }

        protected override void onError(Exception e) {
            this.onErrorCalled = true;
            this.capturedMessage = e.getMessage();
        }
    }

    private class DiffHandler extends TriggerHandler {
        public Boolean nameChanged;
        public Boolean nameOrPhoneChanged;
        public List<SObject> changedNames;
        public SObject capturedOldFirst;

        public DiffHandler() {
            super(DiffHandler.class);
        }

        protected override void beforeUpdate() {
            this.changedNames = changedRecords(Account.Name);
            if (this.newRecords != null && !this.newRecords.isEmpty()) {
                this.nameChanged = hasChanged(this.newRecords[0], Account.Name);
                this.nameOrPhoneChanged = hasChanged(
                    this.newRecords[0],
                    new List<SObjectField>{ Account.Name, Account.Phone }
                );
                this.capturedOldFirst = getOld(this.newRecords[0]);
            }
        }
    }

    // ──────────────────────────────────────────────
    //  Dispatch tests
    // ──────────────────────────────────────────────

    @IsTest
    static void dispatchesBeforeInsert() {
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        h.withNew(records).withContext(System.TriggerOperation.BEFORE_INSERT).run();
        System.assertEquals('beforeInsert', h.invokedMethod, 'Should dispatch to beforeInsert');
        System.assert(h.andFinallyCalled, 'andFinally should be called');
    }

    @IsTest
    static void dispatchesBeforeUpdate() {
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        List<SObject> oldRecords = new List<SObject>{ new Account(Name = 'Old') };
        h.withNew(records)
            .withOld(oldRecords)
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();
        System.assertEquals('beforeUpdate', h.invokedMethod);
    }

    @IsTest
    static void dispatchesBeforeDelete() {
        TestHandler h = new TestHandler();
        List<SObject> oldRecords = new List<SObject>{ new Account(Id = fakeId(1)) };
        h.withOld(oldRecords).withContext(System.TriggerOperation.BEFORE_DELETE).run();
        System.assertEquals('beforeDelete', h.invokedMethod);
        System.assertEquals(1, h.capturedOld.size());
    }

    @IsTest
    static void dispatchesAfterInsert() {
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        h.withNew(records).withContext(System.TriggerOperation.AFTER_INSERT).run();
        System.assertEquals('afterInsert', h.invokedMethod);
    }

    @IsTest
    static void dispatchesAfterUpdate() {
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        h.withNew(records)
            .withOldMap(new Map<Id, SObject>())
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();
        System.assertEquals('afterUpdate', h.invokedMethod);
    }

    @IsTest
    static void dispatchesAfterDelete() {
        TestHandler h = new TestHandler();
        List<SObject> oldRecords = new List<SObject>{ new Account(Id = fakeId(1)) };
        h.withOld(oldRecords).withContext(System.TriggerOperation.AFTER_DELETE).run();
        System.assertEquals('afterDelete', h.invokedMethod);
    }

    @IsTest
    static void dispatchesAfterUndelete() {
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Id = fakeId(1)) };
        h.withNew(records).withContext(System.TriggerOperation.AFTER_UNDELETE).run();
        System.assertEquals('afterUndelete', h.invokedMethod);
    }

    // ──────────────────────────────────────────────
    //  Fluent API tests
    // ──────────────────────────────────────────────

    @IsTest
    static void fluentChainReturnsHandler() {
        TestHandler h = new TestHandler();
        TriggerHandler result = h.withNew(new List<SObject>())
            .withOld(new List<SObject>())
            .withOldMap(new Map<Id, SObject>())
            .withNewMap(new Map<Id, SObject>())
            .maxLoops(3)
            .trackLimits();
        System.assert(result === h, 'Chaining should return the same handler instance');
    }

    @IsTest
    static void withNewMapIsAccessible() {
        TestHandler h = new TestHandler();
        Account a = new Account(Id = fakeId(1), Name = 'Mapped');
        Map<Id, SObject> newMap = new Map<Id, SObject>{ a.Id => a };
        h.withNew(new List<SObject>{ a })
            .withNewMap(newMap)
            .withContext(System.TriggerOperation.AFTER_INSERT)
            .run();
        System.assertEquals(1, h.capturedNewMap.size(), 'newMap should be available to handler');
    }

    // ──────────────────────────────────────────────
    //  Filtering tests
    // ──────────────────────────────────────────────

    @IsTest
    static void onlyTheseFiltersNewAndOld() {
        Id keep1 = fakeId(1);
        Id keep2 = fakeId(2);
        Id discard = fakeId(3);

        List<SObject> newRecs = new List<SObject>{
            new Account(Id = keep1, Name = 'Keep1'),
            new Account(Id = keep2, Name = 'Keep2'),
            new Account(Id = discard, Name = 'Discard')
        };
        List<SObject> oldRecs = new List<SObject>{
            new Account(Id = keep1, Name = 'Keep1 Old'),
            new Account(Id = keep2, Name = 'Keep2 Old'),
            new Account(Id = discard, Name = 'Discard Old')
        };

        TestHandler h = new TestHandler();
        h.withNew(newRecs)
            .withOld(oldRecs)
            .onlyThese(new Set<Id>{ keep1, keep2 })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();

        System.assertEquals(2, h.capturedNew.size(), 'newRecords should be filtered');
        System.assertEquals(2, h.capturedOld.size(), 'oldRecords should be filtered for parity');
    }

    @IsTest
    static void onlyTheseFiltersOnDelete() {
        Id keep = fakeId(1);
        Id discard = fakeId(2);

        TestHandler h = new TestHandler();
        h.withOld(new List<SObject>{
                new Account(Id = keep, Name = 'Keep'),
                new Account(Id = discard, Name = 'Discard')
            })
            .onlyThese(new Set<Id>{ keep })
            .withContext(System.TriggerOperation.BEFORE_DELETE)
            .run();

        System.assertEquals(1, h.capturedOld.size(), 'Delete contexts should still filter oldRecords');
    }

    @IsTest
    static void onlyTheseInBeforeInsertThrows() {
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Test') })
            .onlyThese(new Set<Id>{ fakeId(1) })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        try {
            h.run();
            System.assert(false, 'Should have thrown for onlyThese in BEFORE_INSERT');
        } catch (TriggerHandler.TriggerHandlerException e) {
            System.assert(e.getMessage().contains('BEFORE_INSERT'),
                'Should explain the BEFORE_INSERT limitation: ' + e.getMessage());
        }
    }

    @IsTest
    static void onlyTheseWithNullRecordsDoesNotFilter() {
        TestHandler h = new TestHandler();
        h.withNew(null)
            .onlyThese(new Set<Id>{ fakeId(1) })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();

        System.assertEquals(null, h.capturedNew);
        System.assertEquals('beforeUpdate', h.invokedMethod);
    }

    // ──────────────────────────────────────────────
    //  Bypass tests
    // ──────────────────────────────────────────────

    @IsTest
    static void bypassedHandlerDoesNotExecute() {
        TriggerHandler.clearAll();
        TriggerHandler.bypass(TestHandler.class);

        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Test') })
            .withContext(System.TriggerOperation.BEFORE_INSERT)
            .run();

        System.assertEquals(null, h.invokedMethod, 'Bypassed handler should not execute');
        System.assertEquals(false, h.andFinallyCalled, 'andFinally should not run when bypassed');
    }

    @IsTest
    static void clearBypassRestoresExecution() {
        TriggerHandler.clearAll();
        TriggerHandler.bypass(TestHandler.class);
        TriggerHandler.clearBypass(TestHandler.class);

        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Test') })
            .withContext(System.TriggerOperation.BEFORE_INSERT)
            .run();

        System.assertEquals('beforeInsert', h.invokedMethod, 'Cleared bypass should execute');
    }

    @IsTest
    static void typeAndStringBypassAreEquivalent() {
        TriggerHandler.clearAll();
        TriggerHandler.bypass(TestHandler.class);
        System.assert(TriggerHandler.isBypassed(TestHandler.class.getName()),
            'Type bypass should be readable by name');
        System.assert(TriggerHandler.isBypassed(TestHandler.class),
            'Type bypass should be readable by Type');
    }

    @IsTest
    static void isBypassedReturnsCorrectState() {
        TriggerHandler.clearAll();
        System.assertEquals(false, TriggerHandler.isBypassed('SomeHandler'));

        TriggerHandler.bypass('SomeHandler');
        System.assertEquals(true, TriggerHandler.isBypassed('SomeHandler'));

        TriggerHandler.clearBypass('SomeHandler');
        System.assertEquals(false, TriggerHandler.isBypassed('SomeHandler'));
    }

    @IsTest
    static void clearAllBypassesRemovesAll() {
        TriggerHandler.clearAll();
        TriggerHandler.bypass('HandlerA');
        TriggerHandler.bypass('HandlerB');
        TriggerHandler.clearAllBypasses();

        System.assertEquals(0, TriggerHandler.getBypassedHandlers().size());
    }

    @IsTest
    static void getBypassedHandlersReturnsCopy() {
        TriggerHandler.clearAll();
        TriggerHandler.bypass('HandlerX');

        Set<String> retrieved = TriggerHandler.getBypassedHandlers();
        System.assertEquals(1, retrieved.size());

        retrieved.add('HandlerY');

        Set<String> after = TriggerHandler.getBypassedHandlers();
        System.assertEquals(1, after.size(), 'Should return a defensive copy');
    }

    // ──────────────────────────────────────────────
    //  Loop limit tests
    // ──────────────────────────────────────────────

    @IsTest
    static void maxLoopsAllowsConfiguredRuns() {
        TriggerHandler.clearAll();

        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Loop Test') })
            .maxLoops(3)
            .withContext(System.TriggerOperation.BEFORE_INSERT)
            .run();

        System.assertEquals('beforeInsert', h.invokedMethod, 'First run should work');
    }

    @IsTest
    static void maxLoopsThrowsAfterLimit() {
        TriggerHandler.clearAll();

        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Loop Test') })
            .maxLoops(1)
            .withContext(System.TriggerOperation.BEFORE_INSERT);
        h.run();

        TestHandler h2 = new TestHandler();
        h2.withNew(new List<SObject>{ new Account(Name = 'Loop Test 2') })
            .maxLoops(1)
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        try {
            h2.run();
            System.assert(false, 'Should have thrown on second run');
        } catch (TriggerHandler.TriggerHandlerException e) {
            System.assert(e.getMessage().contains('Maximum loop count'),
                'Should mention loop count: ' + e.getMessage());
        }
    }

    @IsTest
    static void maxLoopsSoftExitDoesNotThrow() {
        TriggerHandler.clearAll();

        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Soft 1') })
            .maxLoops(1, false)
            .withContext(System.TriggerOperation.BEFORE_INSERT);
        h.run();

        TestHandler h2 = new TestHandler();
        h2.withNew(new List<SObject>{ new Account(Name = 'Soft 2') })
            .maxLoops(1, false)
            .withContext(System.TriggerOperation.BEFORE_INSERT);
        h2.run();

        System.assertEquals(null, h2.invokedMethod, 'Soft exit should skip dispatch');
        System.assertEquals(false, h2.andFinallyCalled, 'Soft exit should skip andFinally');
    }

    @IsTest
    static void loopBudgetIsPerContext() {
        TriggerHandler.clearAll();
        List<SObject> recs = new List<SObject>{ new Account(Name = 'Per Context') };

        TestHandler before = new TestHandler();
        before.withNew(recs).maxLoops(1).withContext(System.TriggerOperation.BEFORE_INSERT).run();

        TestHandler afterH = new TestHandler();
        afterH.withNew(recs).maxLoops(1).withContext(System.TriggerOperation.AFTER_INSERT).run();

        System.assertEquals('afterInsert', afterH.invokedMethod,
            'before+after should not share the same loop budget');
    }

    // ──────────────────────────────────────────────
    //  Exception / context tests
    // ──────────────────────────────────────────────

    @IsTest
    static void throwsWhenCalledOutsideTrigger() {
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'No Trigger') });

        try {
            h.run();
            System.assert(false, 'Should have thrown');
        } catch (TriggerHandler.TriggerHandlerException e) {
            System.assert(e.getMessage().contains('outside of trigger'),
                'Should mention outside trigger: ' + e.getMessage());
        }
    }

    @IsTest
    static void throwsWhenContextIsNull() {
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Null Ctx') })
            .withContext(null);

        try {
            h.run();
            System.assert(false, 'Should have thrown for null operation');
        } catch (TriggerHandler.TriggerHandlerException e) {
            System.assert(e.getMessage().contains('withContext'),
                'Should hint at withContext: ' + e.getMessage());
        }
    }

    // ──────────────────────────────────────────────
    //  andFinally tests
    // ──────────────────────────────────────────────

    @IsTest
    static void andFinallyCalledInEveryContext() {
        for (System.TriggerOperation op : System.TriggerOperation.values()) {
            TriggerHandler.clearAll();
            TestHandler h = new TestHandler();
            h.withNew(new List<SObject>{ new Account(Name = 'Final ' + op) })
                .withContext(op)
                .run();
            System.assert(h.andFinallyCalled,
                'andFinally should be called for ' + op);
        }
    }

    @IsTest
    static void andFinallyRunsWhenDispatchThrows() {
        ThrowingHandler h = new ThrowingHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Throws') })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        try {
            h.run();
            System.assert(false, 'Should have rethrown the dispatch exception');
        } catch (TriggerHandler.TriggerHandlerException e) {
            System.assertEquals('boom', e.getMessage());
        }

        System.assert(h.andFinallyCalled,
            'andFinally must run even when the dispatched method throws');
    }

    // ──────────────────────────────────────────────
    //  Track limits test
    // ──────────────────────────────────────────────

    @IsTest
    static void trackLimitsInvokesOverridableLogger() {
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Limits') })
            .trackLimits()
            .withContext(System.TriggerOperation.BEFORE_INSERT)
            .run();
        System.assert(h.andFinallyCalled, 'Should complete without error');
        System.assert(h.limitsLogged, 'Overridable logLimits should have been invoked');
    }

    // ──────────────────────────────────────────────
    //  fromTrigger tests
    // ──────────────────────────────────────────────

    @IsTest
    static void fromTriggerIsChainableAndSafeOutsideTrigger() {
        TestHandler h = new TestHandler();
        TriggerHandler result = h.fromTrigger();
        System.assert(result === h, 'fromTrigger should be chainable');

        h.withContext(System.TriggerOperation.BEFORE_INSERT).run();
        System.assertEquals('beforeInsert', h.invokedMethod);
        System.assertEquals(null, h.capturedNew,
            'No Trigger context in test → record collections are null');
    }

    // ──────────────────────────────────────────────
    //  Diff helper tests
    // ──────────────────────────────────────────────

    @IsTest
    static void diffHelpersDetectChanges() {
        Id rid = fakeId(1);
        Account newRec = new Account(Id = rid, Name = 'New', Phone = '111');
        Account oldRec = new Account(Id = rid, Name = 'Old', Phone = '111');

        DiffHandler h = new DiffHandler();
        h.withNew(new List<SObject>{ newRec })
            .withOldMap(new Map<Id, SObject>{ rid => oldRec })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();

        System.assertEquals(1, h.changedNames.size(), 'Name changed → 1 record');
        System.assertEquals(true, h.nameChanged);
        System.assertEquals(true, h.nameOrPhoneChanged,
            'Multi-field check is true when any field changed');
        System.assertEquals('Old', (String) h.capturedOldFirst.get(Account.Name));
    }

    @IsTest
    static void diffHelpersReportNoChange() {
        Id rid = fakeId(1);
        Account newRec = new Account(Id = rid, Name = 'Same', Phone = '111');
        Account oldRec = new Account(Id = rid, Name = 'Same', Phone = '111');

        DiffHandler h = new DiffHandler();
        h.withNew(new List<SObject>{ newRec })
            .withOldMap(new Map<Id, SObject>{ rid => oldRec })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();

        System.assertEquals(0, h.changedNames.size(), 'No change → empty');
        System.assertEquals(false, h.nameChanged);
        System.assertEquals(false, h.nameOrPhoneChanged);
    }

    @IsTest
    static void diffHelpersReturnFalseWithoutOldMap() {
        DiffHandler h = new DiffHandler();
        h.withNew(new List<SObject>{ new Account(Id = fakeId(1), Name = 'X') })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();

        System.assertEquals(0, h.changedNames.size(),
            'No oldMap → no detected changes');
        System.assertEquals(false, h.nameChanged);
        System.assertEquals(null, h.capturedOldFirst);
    }

    // ──────────────────────────────────────────────
    //  Instance bypass tests
    // ──────────────────────────────────────────────

    @IsTest
    static void bypassIfTrueSkipsExecution() {
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Skip') })
            .bypassIf(true)
            .withContext(System.TriggerOperation.BEFORE_INSERT)
            .run();

        System.assertEquals(null, h.invokedMethod, 'bypassIf(true) should skip dispatch');
        System.assertEquals(false, h.andFinallyCalled);
    }

    @IsTest
    static void bypassIfFalseRunsNormally() {
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Run') })
            .bypassIf(false)
            .withContext(System.TriggerOperation.BEFORE_INSERT)
            .run();

        System.assertEquals('beforeInsert', h.invokedMethod);
    }

    @IsTest
    static void bypassIfPermissionMissingPermissionRuns() {
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Perm') })
            .bypassIfPermission('Nonexistent_Custom_Permission_XYZ')
            .withContext(System.TriggerOperation.BEFORE_INSERT)
            .run();

        System.assertEquals('beforeInsert', h.invokedMethod,
            'Missing custom permission → not bypassed');
    }

    // ──────────────────────────────────────────────
    //  processOnce (idempotency) tests
    // ──────────────────────────────────────────────

    @IsTest
    static void processOnceSkipsAlreadyProcessedRecords() {
        TriggerHandler.clearAll();
        Id idA = fakeId(1);
        Id idB = fakeId(2);

        CountingHandler first = new CountingHandler();
        first.withNew(new List<SObject>{
                new Account(Id = idA, Name = 'A'),
                new Account(Id = idB, Name = 'B')
            })
            .processOnce()
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();
        System.assertEquals(2, first.processedCount, 'First run processes both records');

        CountingHandler second = new CountingHandler();
        second.withNew(new List<SObject>{
                new Account(Id = idA, Name = 'A2'),
                new Account(Id = idB, Name = 'B2')
            })
            .processOnce()
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();
        System.assertEquals(0, second.processedCount,
            'Re-entry should skip records already processed');
    }

    @IsTest
    static void processOnceProcessesOnlyNewRecords() {
        TriggerHandler.clearAll();
        Id idA = fakeId(1);
        Id idB = fakeId(2);

        CountingHandler first = new CountingHandler();
        first.withNew(new List<SObject>{ new Account(Id = idA, Name = 'A') })
            .processOnce()
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();
        System.assertEquals(1, first.processedCount);

        CountingHandler second = new CountingHandler();
        second.withNew(new List<SObject>{
                new Account(Id = idA, Name = 'A'),
                new Account(Id = idB, Name = 'B')
            })
            .processOnce()
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();
        System.assertEquals(1, second.processedCount, 'Only the new record should process');
        System.assertEquals(idB, second.lastProcessed[0].Id, 'Remaining record should be B');
    }

    // ──────────────────────────────────────────────
    //  Transaction state bag tests
    // ──────────────────────────────────────────────

    @IsTest
    static void stateBagHandsOffBetweenHandlers() {
        TriggerHandler.clearAll();
        Id rid = fakeId(1);

        StateWriterHandler writer = new StateWriterHandler();
        writer.withNew(new List<SObject>{ new Account(Id = rid, Name = 'W') })
            .withOldMap(new Map<Id, SObject>{ rid => new Account(Id = rid, Name = 'Old') })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();

        StateReaderHandler reader = new StateReaderHandler();
        reader.withNew(new List<SObject>{ new Account(Id = rid, Name = 'W') })
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();

        System.assert(reader.sawState, 'State written earlier should be visible');
        System.assertEquals(42, (Integer) reader.readValue);
    }

    @IsTest
    static void clearAllResetsStateBag() {
        TriggerHandler.clearAll();
        Id rid = fakeId(1);

        StateWriterHandler writer = new StateWriterHandler();
        writer.withNew(new List<SObject>{ new Account(Id = rid, Name = 'W') })
            .withOldMap(new Map<Id, SObject>{ rid => new Account(Id = rid, Name = 'Old') })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();

        TriggerHandler.clearAll();

        StateReaderHandler reader = new StateReaderHandler();
        reader.withNew(new List<SObject>{ new Account(Id = rid, Name = 'W') })
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();

        System.assertEquals(false, reader.sawState, 'clearAll should wipe the state bag');
    }

    // ──────────────────────────────────────────────
    //  onError hook tests
    // ──────────────────────────────────────────────

    @IsTest
    static void onErrorIsCalledThenRethrows() {
        ErrorHookHandler h = new ErrorHookHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Err') })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        try {
            h.run();
            System.assert(false, 'Should rethrow after onError');
        } catch (TriggerHandler.TriggerHandlerException e) {
            System.assertEquals('kaboom', e.getMessage());
        }

        System.assert(h.onErrorCalled, 'onError hook should be invoked');
        System.assertEquals('kaboom', h.capturedMessage);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    private static Id fakeId(Integer seed) {
        return (Id) ('001' + String.valueOf(seed).leftPad(12, '0'));
    }
}
