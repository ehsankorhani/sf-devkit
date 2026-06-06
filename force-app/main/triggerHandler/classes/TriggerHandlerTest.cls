/**
 * Copyright (c) 2026 Ehsan Korhani
 * SPDX-License-Identifier: MIT
 *
 * @author Ehsan Korhani
 * @version 1.0.0
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
    static void run_BeforeInsertContext_DispatchesToBeforeInsert() {
        // Arrange
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        h.withNew(records).withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('beforeInsert', h.invokedMethod, 'BEFORE_INSERT context must dispatch to beforeInsert');
        Assert.isTrue(h.andFinallyCalled, 'andFinally must execute after dispatch completes');
    }

    @IsTest
    static void run_BeforeUpdateContext_DispatchesToBeforeUpdate() {
        // Arrange
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        List<SObject> oldRecords = new List<SObject>{ new Account(Name = 'Old') };
        h.withNew(records).withOld(oldRecords).withContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('beforeUpdate', h.invokedMethod, 'BEFORE_UPDATE context must dispatch to beforeUpdate');
    }

    @IsTest
    static void run_BeforeDeleteContext_DispatchesToBeforeDelete() {
        // Arrange
        TestHandler h = new TestHandler();
        List<SObject> oldRecords = new List<SObject>{ new Account(Id = fakeId(1)) };
        h.withOld(oldRecords).withContext(System.TriggerOperation.BEFORE_DELETE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('beforeDelete', h.invokedMethod, 'BEFORE_DELETE context must dispatch to beforeDelete');
        Assert.areEqual(1, h.capturedOld.size(), 'Handler must receive the old records collection');
    }

    @IsTest
    static void run_AfterInsertContext_DispatchesToAfterInsert() {
        // Arrange
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        h.withNew(records).withContext(System.TriggerOperation.AFTER_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('afterInsert', h.invokedMethod, 'AFTER_INSERT context must dispatch to afterInsert');
    }

    @IsTest
    static void run_AfterUpdateContext_DispatchesToAfterUpdate() {
        // Arrange
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Name = 'Test') };
        h.withNew(records)
            .withOldMap(new Map<Id, SObject>())
            .withContext(System.TriggerOperation.AFTER_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('afterUpdate', h.invokedMethod, 'AFTER_UPDATE context must dispatch to afterUpdate');
    }

    @IsTest
    static void run_AfterDeleteContext_DispatchesToAfterDelete() {
        // Arrange
        TestHandler h = new TestHandler();
        List<SObject> oldRecords = new List<SObject>{ new Account(Id = fakeId(1)) };
        h.withOld(oldRecords).withContext(System.TriggerOperation.AFTER_DELETE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('afterDelete', h.invokedMethod, 'AFTER_DELETE context must dispatch to afterDelete');
    }

    @IsTest
    static void run_AfterUndeleteContext_DispatchesToAfterUndelete() {
        // Arrange
        TestHandler h = new TestHandler();
        List<SObject> records = new List<SObject>{ new Account(Id = fakeId(1)) };
        h.withNew(records).withContext(System.TriggerOperation.AFTER_UNDELETE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('afterUndelete', h.invokedMethod, 'AFTER_UNDELETE context must dispatch to afterUndelete');
    }

    // ──────────────────────────────────────────────
    //  Fluent API tests
    // ──────────────────────────────────────────────

    @IsTest
    static void withNew_FluentChaining_ReturnsSameInstance() {
        // Arrange
        TestHandler h = new TestHandler();

        // Act
        Test.startTest();
        TriggerHandler result = h.withNew(new List<SObject>())
            .withOld(new List<SObject>())
            .withOldMap(new Map<Id, SObject>())
            .withNewMap(new Map<Id, SObject>())
            .maxLoops(3)
            .trackLimits();
        Test.stopTest();

        // Assert
        Assert.isTrue(result === h, 'Fluent chaining must return the same handler instance');
    }

    @IsTest
    static void withNewMap_AfterInsertContext_ExposesMapToHandler() {
        // Arrange
        TestHandler h = new TestHandler();
        Account a = new Account(Id = fakeId(1), Name = 'Mapped');
        Map<Id, SObject> newMap = new Map<Id, SObject>{ a.Id => a };
        h.withNew(new List<SObject>{ a })
            .withNewMap(newMap)
            .withContext(System.TriggerOperation.AFTER_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, h.capturedNewMap.size(), 'newMap must be accessible to the handler');
    }

    // ──────────────────────────────────────────────
    //  Filtering tests
    // ──────────────────────────────────────────────

    @IsTest
    static void onlyThese_SubsetOfIds_FiltersNewAndOldRecords() {
        // Arrange
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
            .withContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(2, h.capturedNew.size(), 'newRecords must be filtered to the specified Ids');
        Assert.areEqual(2, h.capturedOld.size(), 'oldRecords must be filtered for parity with newRecords');
    }

    @IsTest
    static void onlyThese_DeleteContext_FiltersOldRecords() {
        // Arrange
        Id keep = fakeId(1);
        Id discard = fakeId(2);
        TestHandler h = new TestHandler();
        h.withOld(new List<SObject>{
                new Account(Id = keep, Name = 'Keep'),
                new Account(Id = discard, Name = 'Discard')
            })
            .onlyThese(new Set<Id>{ keep })
            .withContext(System.TriggerOperation.BEFORE_DELETE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, h.capturedOld.size(), 'Delete contexts must still filter oldRecords');
    }

    @IsTest
    static void onlyThese_BeforeInsertContext_ThrowsException() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Test') })
            .onlyThese(new Set<Id>{ fakeId(1) })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        try {
            h.run();
            Assert.fail('onlyThese must throw in BEFORE_INSERT because records lack Ids');
        } catch (TriggerHandler.TriggerHandlerException e) {
            // Assert
            Assert.isTrue(e.getMessage().contains('BEFORE_INSERT'),
                'Exception must explain the BEFORE_INSERT limitation');
        }
        Test.stopTest();
    }

    @IsTest
    static void onlyThese_NullNewRecords_SkipsFiltering() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(null)
            .onlyThese(new Set<Id>{ fakeId(1) })
            .withContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isNull(h.capturedNew, 'Null newRecords must pass through without filtering');
        Assert.areEqual('beforeUpdate', h.invokedMethod, 'Handler must still dispatch despite null records');
    }

    // ──────────────────────────────────────────────
    //  Bypass tests
    // ──────────────────────────────────────────────

    @IsTest
    static void run_HandlerBypassed_SkipsDispatch() {
        // Arrange
        TriggerHandler.clearAll();
        TriggerHandler.bypass(TestHandler.class);
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Test') })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isNull(h.invokedMethod, 'Bypassed handler must not execute any dispatch method');
        Assert.isFalse(h.andFinallyCalled, 'andFinally must not run when handler is bypassed');
    }

    @IsTest
    static void clearBypass_AfterBypass_RestoresExecution() {
        // Arrange
        TriggerHandler.clearAll();
        TriggerHandler.bypass(TestHandler.class);
        TriggerHandler.clearBypass(TestHandler.class);
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Test') })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('beforeInsert', h.invokedMethod, 'Clearing a bypass must restore normal execution');
    }

    @IsTest
    static void isBypassed_TypeAndStringBypass_AreEquivalent() {
        // Arrange
        TriggerHandler.clearAll();

        // Act
        Test.startTest();
        TriggerHandler.bypass(TestHandler.class);
        Boolean byName = TriggerHandler.isBypassed(TestHandler.class.getName());
        Boolean byType = TriggerHandler.isBypassed(TestHandler.class);
        Test.stopTest();

        // Assert
        Assert.isTrue(byName, 'Type bypass must be readable by handler name string');
        Assert.isTrue(byType, 'Type bypass must be readable by Type reference');
    }

    @IsTest
    static void isBypassed_NoBypasses_ReturnsFalse() {
        // Arrange
        TriggerHandler.clearAll();

        // Act
        Test.startTest();
        Boolean result = TriggerHandler.isBypassed('SomeHandler');
        Test.stopTest();

        // Assert
        Assert.isFalse(result, 'isBypassed must return false when no bypass is registered');
    }

    @IsTest
    static void isBypassed_AfterBypass_ReturnsTrue() {
        // Arrange
        TriggerHandler.clearAll();
        TriggerHandler.bypass('SomeHandler');

        // Act
        Test.startTest();
        Boolean result = TriggerHandler.isBypassed('SomeHandler');
        Test.stopTest();

        // Assert
        Assert.isTrue(result, 'isBypassed must return true after bypass is registered');
    }

    @IsTest
    static void isBypassed_AfterClearBypass_ReturnsFalse() {
        // Arrange
        TriggerHandler.clearAll();
        TriggerHandler.bypass('SomeHandler');
        TriggerHandler.clearBypass('SomeHandler');

        // Act
        Test.startTest();
        Boolean result = TriggerHandler.isBypassed('SomeHandler');
        Test.stopTest();

        // Assert
        Assert.isFalse(result, 'isBypassed must return false after bypass is cleared');
    }

    @IsTest
    static void clearAllBypasses_MultipleBypassed_RemovesAll() {
        // Arrange
        TriggerHandler.clearAll();
        TriggerHandler.bypass('HandlerA');
        TriggerHandler.bypass('HandlerB');

        // Act
        Test.startTest();
        TriggerHandler.clearAllBypasses();
        Test.stopTest();

        // Assert
        Assert.areEqual(0, TriggerHandler.getBypassedHandlers().size(),
            'clearAllBypasses must remove every registered bypass');
    }

    @IsTest
    static void getBypassedHandlers_ExternalModification_DoesNotAffectOriginal() {
        // Arrange
        TriggerHandler.clearAll();
        TriggerHandler.bypass('HandlerX');

        // Act
        Test.startTest();
        Set<String> retrieved = TriggerHandler.getBypassedHandlers();
        retrieved.add('HandlerY');
        Set<String> after = TriggerHandler.getBypassedHandlers();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, after.size(), 'getBypassedHandlers must return a defensive copy');
    }

    // ──────────────────────────────────────────────
    //  Loop limit tests
    // ──────────────────────────────────────────────

    @IsTest
    static void run_WithinMaxLoops_ExecutesSuccessfully() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Loop Test') })
            .maxLoops(3)
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('beforeInsert', h.invokedMethod, 'First run within loop limit must execute');
    }

    @IsTest
    static void run_ExceedsMaxLoops_ThrowsException() {
        // Arrange
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

        // Act
        Test.startTest();
        try {
            h2.run();
            Assert.fail('Exceeding max loop count must throw TriggerHandlerException');
        } catch (TriggerHandler.TriggerHandlerException e) {
            // Assert
            Assert.isTrue(e.getMessage().contains('Maximum loop count'),
                'Exception must mention the loop count limit');
        }
        Test.stopTest();
    }

    @IsTest
    static void run_ExceedsMaxLoopsSoftExit_SkipsWithoutThrowing() {
        // Arrange
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

        // Act
        Test.startTest();
        h2.run();
        Test.stopTest();

        // Assert
        Assert.isNull(h2.invokedMethod, 'Soft exit must skip dispatch without throwing');
        Assert.isFalse(h2.andFinallyCalled, 'Soft exit must skip andFinally');
    }

    @IsTest
    static void run_DifferentTriggerContexts_LoopBudgetsAreIndependent() {
        // Arrange
        TriggerHandler.clearAll();
        List<SObject> recs = new List<SObject>{ new Account(Name = 'Per Context') };
        TestHandler before = new TestHandler();
        before.withNew(recs).maxLoops(1).withContext(System.TriggerOperation.BEFORE_INSERT).run();
        TestHandler afterH = new TestHandler();
        afterH.withNew(recs).maxLoops(1).withContext(System.TriggerOperation.AFTER_INSERT);

        // Act
        Test.startTest();
        afterH.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('afterInsert', afterH.invokedMethod,
            'BEFORE and AFTER contexts must not share the same loop budget');
    }

    // ──────────────────────────────────────────────
    //  Exception / context tests
    // ──────────────────────────────────────────────

    @IsTest
    static void run_NoTriggerContext_ThrowsException() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'No Trigger') });

        // Act
        Test.startTest();
        try {
            h.run();
            Assert.fail('Running outside a trigger context must throw');
        } catch (TriggerHandler.TriggerHandlerException e) {
            // Assert
            Assert.isTrue(e.getMessage().contains('outside of trigger'),
                'Exception must mention that handler was called outside of trigger');
        }
        Test.stopTest();
    }

    @IsTest
    static void run_NullContext_ThrowsException() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Null Ctx') })
            .withContext(null);

        // Act
        Test.startTest();
        try {
            h.run();
            Assert.fail('Null trigger context must throw');
        } catch (TriggerHandler.TriggerHandlerException e) {
            // Assert
            Assert.isTrue(e.getMessage().contains('withContext'),
                'Exception must hint at using withContext to set context');
        }
        Test.stopTest();
    }

    // ──────────────────────────────────────────────
    //  andFinally tests
    // ──────────────────────────────────────────────

    @IsTest
    static void andFinally_BeforeInsertContext_IsCalled() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Final') })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must be called for BEFORE_INSERT');
    }

    @IsTest
    static void andFinally_BeforeUpdateContext_IsCalled() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Final') })
            .withContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must be called for BEFORE_UPDATE');
    }

    @IsTest
    static void andFinally_BeforeDeleteContext_IsCalled() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Final') })
            .withContext(System.TriggerOperation.BEFORE_DELETE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must be called for BEFORE_DELETE');
    }

    @IsTest
    static void andFinally_AfterInsertContext_IsCalled() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Final') })
            .withContext(System.TriggerOperation.AFTER_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must be called for AFTER_INSERT');
    }

    @IsTest
    static void andFinally_AfterUpdateContext_IsCalled() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Final') })
            .withContext(System.TriggerOperation.AFTER_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must be called for AFTER_UPDATE');
    }

    @IsTest
    static void andFinally_AfterDeleteContext_IsCalled() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Final') })
            .withContext(System.TriggerOperation.AFTER_DELETE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must be called for AFTER_DELETE');
    }

    @IsTest
    static void andFinally_AfterUndeleteContext_IsCalled() {
        // Arrange
        TriggerHandler.clearAll();
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Final') })
            .withContext(System.TriggerOperation.AFTER_UNDELETE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must be called for AFTER_UNDELETE');
    }

    @IsTest
    static void andFinally_DispatchThrows_StillExecutes() {
        // Arrange
        ThrowingHandler h = new ThrowingHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Throws') })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        try {
            h.run();
            Assert.fail('Dispatch exception must propagate after andFinally runs');
        } catch (TriggerHandler.TriggerHandlerException e) {
            // Assert
            Assert.areEqual('boom', e.getMessage(), 'Original exception message must be preserved');
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'andFinally must run even when the dispatched method throws');
    }

    // ──────────────────────────────────────────────
    //  Track limits test
    // ──────────────────────────────────────────────

    @IsTest
    static void run_TrackLimitsEnabled_InvokesLogLimits() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Limits') })
            .trackLimits()
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(h.andFinallyCalled, 'Handler must complete without error');
        Assert.isTrue(h.limitsLogged, 'trackLimits must invoke the overridable logLimits method');
    }

    // ──────────────────────────────────────────────
    //  fromTrigger tests
    // ──────────────────────────────────────────────

    @IsTest
    static void fromTrigger_OutsideTriggerContext_IsChainableWithNullRecords() {
        // Arrange
        TestHandler h = new TestHandler();

        // Act
        Test.startTest();
        TriggerHandler result = h.fromTrigger();
        h.withContext(System.TriggerOperation.BEFORE_INSERT).run();
        Test.stopTest();

        // Assert
        Assert.isTrue(result === h, 'fromTrigger must be chainable');
        Assert.areEqual('beforeInsert', h.invokedMethod, 'Handler must still dispatch after fromTrigger');
        Assert.isNull(h.capturedNew, 'Record collections must be null when run outside real trigger context');
    }

    // ──────────────────────────────────────────────
    //  Diff helper tests
    // ──────────────────────────────────────────────

    @IsTest
    static void hasChanged_FieldValueDiffers_ReturnsTrue() {
        // Arrange
        Id rid = fakeId(1);
        Account newRec = new Account(Id = rid, Name = 'New', Phone = '111');
        Account oldRec = new Account(Id = rid, Name = 'Old', Phone = '111');
        DiffHandler h = new DiffHandler();
        h.withNew(new List<SObject>{ newRec })
            .withOldMap(new Map<Id, SObject>{ rid => oldRec })
            .withContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, h.changedNames.size(), 'changedRecords must return records where Name differs');
        Assert.isTrue(h.nameChanged, 'hasChanged must detect single-field change');
        Assert.isTrue(h.nameOrPhoneChanged, 'Multi-field hasChanged must be true when any field changed');
        Assert.areEqual('Old', (String) h.capturedOldFirst.get(Account.Name),
            'getOld must return the previous version of the record');
    }

    @IsTest
    static void hasChanged_SameFieldValues_ReturnsFalse() {
        // Arrange
        Id rid = fakeId(1);
        Account newRec = new Account(Id = rid, Name = 'Same', Phone = '111');
        Account oldRec = new Account(Id = rid, Name = 'Same', Phone = '111');
        DiffHandler h = new DiffHandler();
        h.withNew(new List<SObject>{ newRec })
            .withOldMap(new Map<Id, SObject>{ rid => oldRec })
            .withContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(0, h.changedNames.size(), 'changedRecords must return empty when no field changed');
        Assert.isFalse(h.nameChanged, 'hasChanged must return false when field value is unchanged');
        Assert.isFalse(h.nameOrPhoneChanged, 'Multi-field hasChanged must be false when no field changed');
    }

    @IsTest
    static void hasChanged_NoOldMap_ReturnsFalseWithNullOld() {
        // Arrange
        DiffHandler h = new DiffHandler();
        h.withNew(new List<SObject>{ new Account(Id = fakeId(1), Name = 'X') })
            .withContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(0, h.changedNames.size(), 'changedRecords must return empty when oldMap is absent');
        Assert.isFalse(h.nameChanged, 'hasChanged must return false without oldMap');
        Assert.isNull(h.capturedOldFirst, 'getOld must return null without oldMap');
    }

    // ──────────────────────────────────────────────
    //  Instance bypass tests
    // ──────────────────────────────────────────────

    @IsTest
    static void bypassIf_ConditionTrue_SkipsDispatch() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Skip') })
            .bypassIf(true)
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.isNull(h.invokedMethod, 'bypassIf(true) must skip dispatch');
        Assert.isFalse(h.andFinallyCalled, 'bypassIf(true) must skip andFinally');
    }

    @IsTest
    static void bypassIf_ConditionFalse_RunsNormally() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Run') })
            .bypassIf(false)
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('beforeInsert', h.invokedMethod, 'bypassIf(false) must run normally');
    }

    @IsTest
    static void bypassIfPermission_MissingPermission_RunsNormally() {
        // Arrange
        TestHandler h = new TestHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Perm') })
            .bypassIfPermission('Nonexistent_Custom_Permission_XYZ')
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        h.run();
        Test.stopTest();

        // Assert
        Assert.areEqual('beforeInsert', h.invokedMethod,
            'Missing custom permission must not bypass the handler');
    }

    // ──────────────────────────────────────────────
    //  processOnce (idempotency) tests
    // ──────────────────────────────────────────────

    @IsTest
    static void processOnce_SameRecordsReEntered_SkipsProcessed() {
        // Arrange
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
        CountingHandler second = new CountingHandler();
        second.withNew(new List<SObject>{
                new Account(Id = idA, Name = 'A2'),
                new Account(Id = idB, Name = 'B2')
            })
            .processOnce()
            .withContext(System.TriggerOperation.AFTER_UPDATE);

        // Act
        Test.startTest();
        second.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(2, first.processedCount, 'First run must process both records');
        Assert.areEqual(0, second.processedCount, 'Re-entry must skip already-processed records');
    }

    @IsTest
    static void processOnce_MixOfOldAndNewRecords_ProcessesOnlyNew() {
        // Arrange
        TriggerHandler.clearAll();
        Id idA = fakeId(1);
        Id idB = fakeId(2);
        CountingHandler first = new CountingHandler();
        first.withNew(new List<SObject>{ new Account(Id = idA, Name = 'A') })
            .processOnce()
            .withContext(System.TriggerOperation.AFTER_UPDATE)
            .run();
        CountingHandler second = new CountingHandler();
        second.withNew(new List<SObject>{
                new Account(Id = idA, Name = 'A'),
                new Account(Id = idB, Name = 'B')
            })
            .processOnce()
            .withContext(System.TriggerOperation.AFTER_UPDATE);

        // Act
        Test.startTest();
        second.run();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, second.processedCount, 'Only the previously unseen record must be processed');
        Assert.areEqual(idB, second.lastProcessed[0].Id, 'The remaining processed record must be B');
    }

    // ──────────────────────────────────────────────
    //  Transaction state bag tests
    // ──────────────────────────────────────────────

    @IsTest
    static void putState_WrittenByOneHandler_ReadableByAnother() {
        // Arrange
        TriggerHandler.clearAll();
        Id rid = fakeId(1);
        StateWriterHandler writer = new StateWriterHandler();
        writer.withNew(new List<SObject>{ new Account(Id = rid, Name = 'W') })
            .withOldMap(new Map<Id, SObject>{ rid => new Account(Id = rid, Name = 'Old') })
            .withContext(System.TriggerOperation.BEFORE_UPDATE)
            .run();
        StateReaderHandler reader = new StateReaderHandler();
        reader.withNew(new List<SObject>{ new Account(Id = rid, Name = 'W') })
            .withContext(System.TriggerOperation.AFTER_UPDATE);

        // Act
        Test.startTest();
        reader.run();
        Test.stopTest();

        // Assert
        Assert.isTrue(reader.sawState, 'State written by an earlier handler must be visible to later handlers');
        Assert.areEqual(42, (Integer) reader.readValue, 'State value must match what was written');
    }

    @IsTest
    static void clearAll_AfterStatePut_WipesStateBag() {
        // Arrange
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
            .withContext(System.TriggerOperation.AFTER_UPDATE);

        // Act
        Test.startTest();
        reader.run();
        Test.stopTest();

        // Assert
        Assert.isFalse(reader.sawState, 'clearAll must wipe the transaction state bag');
    }

    // ──────────────────────────────────────────────
    //  onError hook tests
    // ──────────────────────────────────────────────

    @IsTest
    static void onError_DispatchThrows_InvokesHookThenRethrows() {
        // Arrange
        ErrorHookHandler h = new ErrorHookHandler();
        h.withNew(new List<SObject>{ new Account(Name = 'Err') })
            .withContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        try {
            h.run();
            Assert.fail('Exception must propagate after onError hook runs');
        } catch (TriggerHandler.TriggerHandlerException e) {
            // Assert
            Assert.areEqual('kaboom', e.getMessage(), 'Original exception message must be preserved');
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(h.onErrorCalled, 'onError hook must be invoked when dispatch throws');
        Assert.areEqual('kaboom', h.capturedMessage, 'onError must receive the original exception message');
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    private static Id fakeId(Integer seed) {
        return (Id) ('001' + String.valueOf(seed).leftPad(12, '0'));
    }
}
