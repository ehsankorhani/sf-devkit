/**
 * Copyright (c) 2026 Ehsan Korhani
 * SPDX-License-Identifier: MIT
 *
 * @author Ehsan Korhani
 * @version 1.0.0
 */
public inherited sharing class UnitOfWork implements IUnitOfWork {
    
    private class UOWRecord {
        public SObject record;
        public OperationType opType;
        public Schema.SObjectField externalIdField; 
        public List<UOWRelationship> parentRelationships = new List<UOWRelationship>();
        public Integer level = -1; 
        
        public UOWRecord(SObject record, OperationType opType) {
            this.record = record;
            this.opType = opType;
        }
    }
    
    private class UOWRelationship {
        public Schema.SObjectField lookupField;
        public SObject parentRecord;
        
        public UOWRelationship(Schema.SObjectField lookupField, SObject parentRecord) {
            this.lookupField = lookupField;
            this.parentRecord = parentRecord;
        }
    }
    
    public enum OperationType { INSERT_OP, UPDATE_OP, DELETE_OP, UPSERT_OP }
    
    private List<UOWRecord> registeredRecords = new List<UOWRecord>();
    private UOWRecord lastRegisteredRecord;
    
    private AccessLevel dmlAccessLevel = AccessLevel.USER_MODE;
    private Boolean allOrNoneFlag = true;
    private Boolean concurrencyCheck = false;
    private List<IUnitOfWorkAction> postCommitActions = new List<IUnitOfWorkAction>();
    private List<SObject> platformEvents = new List<SObject>();
    private IUnitOfWorkDML dml;
    
    public UnitOfWork() {
        this.dml = new DefaultDML();
    }
    
    @TestVisible
    private UnitOfWork(IUnitOfWorkDML dml) {
        this.dml = dml;
    }
    
    public IUnitOfWork asUserMode() {
        this.dmlAccessLevel = AccessLevel.USER_MODE;
        return this;
    }
    
    public IUnitOfWork asSystemMode() {
        this.dmlAccessLevel = AccessLevel.SYSTEM_MODE;
        return this;
    }
    
    public IUnitOfWork allOrNone(Boolean value) {
        this.allOrNoneFlag = value == null ? true : value;
        return this;
    }
    
    public IUnitOfWork withConcurrencyCheck() {
        this.concurrencyCheck = true;
        return this;
    }
    
    public IUnitOfWork registerNew(SObject record) {
        return register(record, OperationType.INSERT_OP, null);
    }
    
    public IUnitOfWork registerNew(List<SObject> records) {
        if (records != null) {
            for (SObject record : records) {
                register(record, OperationType.INSERT_OP, null);
            }
        }
        return this;
    }
    
    public IUnitOfWork registerDirty(SObject record) {
        return register(record, OperationType.UPDATE_OP, null);
    }
    
    public IUnitOfWork registerDirty(List<SObject> records) {
        if (records != null) {
            for (SObject record : records) {
                register(record, OperationType.UPDATE_OP, null);
            }
        }
        return this;
    }
    
    public IUnitOfWork registerDeleted(SObject record) {
        return register(record, OperationType.DELETE_OP, null);
    }
    
    public IUnitOfWork registerDeleted(List<SObject> records) {
        if (records != null) {
            for (SObject record : records) {
                register(record, OperationType.DELETE_OP, null);
            }
        }
        return this;
    }
    
    public IUnitOfWork registerUpsert(SObject record, Schema.SObjectField externalIdField) {
        return register(record, OperationType.UPSERT_OP, externalIdField);
    }
    
    public IUnitOfWork registerPublish(SObject platformEvent) {
        if (platformEvent == null) throw new IllegalArgumentException('Platform event cannot be null');
        this.platformEvents.add(platformEvent);
        return this;
    }
    
    private IUnitOfWork register(SObject record, OperationType opType, Schema.SObjectField externalIdField) {
        if (record == null) throw new IllegalArgumentException('Record cannot be null');
        
        UOWRecord existing = findRegistered(record, opType);
        if (existing != null) {
            if (externalIdField != null) existing.externalIdField = externalIdField;
            this.lastRegisteredRecord = existing;
            return this;
        }
        
        UOWRecord uowRec = new UOWRecord(record, opType);
        uowRec.externalIdField = externalIdField;
        this.registeredRecords.add(uowRec);
        this.lastRegisteredRecord = uowRec;
        return this;
    }
    
    public IUnitOfWork withParent(Schema.SObjectField lookupField, SObject parentRecord) {
        if (this.lastRegisteredRecord == null) {
            throw new IllegalStateException('No record registered to attach parent to. Call registerNew/Dirty first.');
        }
        if (lookupField == null || parentRecord == null) {
            throw new IllegalArgumentException('Lookup field and parent record must be provided.');
        }
        this.lastRegisteredRecord.parentRelationships.add(new UOWRelationship(lookupField, parentRecord));
        return this;
    }
    
    public IUnitOfWork registerRelationship(SObject childRecord, Schema.SObjectField lookupField, SObject parentRecord) {
        if (childRecord == null || lookupField == null || parentRecord == null) {
            throw new IllegalArgumentException('Child record, lookup field, and parent record must be provided.');
        }
        UOWRecord childWrapper = findRegistered(childRecord);
        if (childWrapper == null) {
            throw new IllegalStateException('Child record must be registered before defining a relationship.');
        }
        childWrapper.parentRelationships.add(new UOWRelationship(lookupField, parentRecord));
        return this;
    }
    
    private UOWRecord findRegistered(SObject record) {
        for (UOWRecord rec : registeredRecords) {
            if (rec.record === record) return rec;
        }
        return null;
    }
    
    private UOWRecord findRegistered(SObject record, OperationType opType) {
        for (UOWRecord rec : registeredRecords) {
            if (rec.opType == opType && rec.record === record) return rec;
        }
        return null;
    }
    
    public IUnitOfWork onCommitSuccess(IUnitOfWorkAction action) {
        if (action != null) {
            this.postCommitActions.add(action);
        }
        return this;
    }
    
    public void commitWork() {
        Savepoint sp = Database.setSavepoint();
        try {
            executeInserts();
            executeUpdates();
            executeUpserts();
            executeDeletes();
            publishEvents();
            
            for (IUnitOfWorkAction action : postCommitActions) {
                action.execute();
            }
            
            clearState();
        } catch (Exception e) {
            Database.rollback(sp);
            throw new UnitOfWorkException(e.getMessage(), e);
        }
    }
    
    private void clearState() {
        this.registeredRecords.clear();
        this.postCommitActions.clear();
        this.platformEvents.clear();
        this.lastRegisteredRecord = null;
    }
    
    private void executeInserts() {
        List<UOWRecord> inserts = new List<UOWRecord>();
        
        for (UOWRecord rec : registeredRecords) {
            if (rec.opType == OperationType.INSERT_OP) {
                inserts.add(rec);
            }
        }
        
        if (inserts.isEmpty()) return;
        
        Integer currentLevel = 0;
        Boolean resolvedAny = true;
        
        while (resolvedAny) {
            resolvedAny = false;
            for (UOWRecord rec : inserts) {
                if (rec.level != -1) continue; 
                
                Boolean allParentsResolved = true;
                for (UOWRelationship rel : rec.parentRelationships) {
                    UOWRecord parentWrapper = findInsert(inserts, rel.parentRecord);
                    if (parentWrapper != null && (parentWrapper.level == -1 || parentWrapper.level >= currentLevel)) {
                        allParentsResolved = false;
                        break;
                    }
                }
                
                if (allParentsResolved) {
                    rec.level = currentLevel;
                    resolvedAny = true;
                }
            }
            if (resolvedAny) {
                currentLevel++;
            }
        }
        
        for (UOWRecord rec : inserts) {
            if (rec.level == -1) {
                throw new IllegalStateException('Circular dependency detected among records to insert.');
            }
        }
        
        for (Integer i = 0; i < currentLevel; i++) {
            Map<Schema.SObjectType, List<SObject>> sObjectsByType = new Map<Schema.SObjectType, List<SObject>>();
            
            for (UOWRecord rec : inserts) {
                if (rec.level == i) {
                    resolveParents(rec);
                    
                    Schema.SObjectType sType = rec.record.getSObjectType();
                    if (!sObjectsByType.containsKey(sType)) {
                        sObjectsByType.put(sType, new List<SObject>());
                    }
                    sObjectsByType.get(sType).add(rec.record);
                }
            }
            
            for (Schema.SObjectType sType : sObjectsByType.keySet()) {
                dml.doInsert(sObjectsByType.get(sType), allOrNoneFlag, dmlAccessLevel);
            }
        }
    }
    
    private void executeUpdates() {
        Map<Schema.SObjectType, List<SObject>> sObjectsByType = new Map<Schema.SObjectType, List<SObject>>();
        for (UOWRecord rec : registeredRecords) {
            if (rec.opType == OperationType.UPDATE_OP) {
                resolveParents(rec);
                Schema.SObjectType sType = rec.record.getSObjectType();
                if (!sObjectsByType.containsKey(sType)) {
                    sObjectsByType.put(sType, new List<SObject>());
                }
                sObjectsByType.get(sType).add(rec.record);
            }
        }
        
        if (sObjectsByType.isEmpty()) return;
        
        if (concurrencyCheck) {
            assertNoStaleRecords(sObjectsByType);
        }
        
        for (Schema.SObjectType sType : sObjectsByType.keySet()) {
            dml.doUpdate(sObjectsByType.get(sType), allOrNoneFlag, dmlAccessLevel);
        }
    }
    
    private void executeUpserts() {
        Map<String, List<SObject>> recordsByKey = new Map<String, List<SObject>>();
        Map<String, Schema.SObjectField> fieldByKey = new Map<String, Schema.SObjectField>();
        
        for (UOWRecord rec : registeredRecords) {
            if (rec.opType == OperationType.UPSERT_OP) {
                resolveParents(rec);
                
                String key = String.valueOf(rec.record.getSObjectType()) + '-' + String.valueOf(rec.externalIdField);
                if (!recordsByKey.containsKey(key)) {
                    recordsByKey.put(key, new List<SObject>());
                    fieldByKey.put(key, rec.externalIdField);
                }
                recordsByKey.get(key).add(rec.record);
            }
        }
        for (String key : recordsByKey.keySet()) {
            dml.doUpsert(recordsByKey.get(key), fieldByKey.get(key), allOrNoneFlag, dmlAccessLevel);
        }
    }
    
    private void executeDeletes() {
        Map<Schema.SObjectType, List<SObject>> sObjectsByType = new Map<Schema.SObjectType, List<SObject>>();
        List<Schema.SObjectType> typeOrder = new List<Schema.SObjectType>();
        
        for (Integer i = registeredRecords.size() - 1; i >= 0; i--) {
            UOWRecord rec = registeredRecords[i];
            if (rec.opType == OperationType.DELETE_OP) {
                Schema.SObjectType sType = rec.record.getSObjectType();
                if (!sObjectsByType.containsKey(sType)) {
                    sObjectsByType.put(sType, new List<SObject>());
                    typeOrder.add(sType);
                }
                sObjectsByType.get(sType).add(rec.record);
            }
        }
        
        for (Schema.SObjectType sType : typeOrder) {
            dml.doDelete(sObjectsByType.get(sType), allOrNoneFlag, dmlAccessLevel);
        }
    }
    
    private UOWRecord findInsert(List<UOWRecord> inserts, SObject parentRecord) {
        for (UOWRecord rec : inserts) {
            if (rec.record === parentRecord) return rec;
        }
        return null;
    }
    
    private void resolveParents(UOWRecord rec) {
        for (UOWRelationship rel : rec.parentRelationships) {
            if (rel.parentRecord.Id != null) {
                rec.record.put(rel.lookupField, rel.parentRecord.Id);
            }
        }
    }
    
    private void assertNoStaleRecords(Map<Schema.SObjectType, List<SObject>> sObjectsByType) {
        for (Schema.SObjectType sType : sObjectsByType.keySet()) {
            Map<Id, SObject> byId = new Map<Id, SObject>();
            for (SObject record : sObjectsByType.get(sType)) {
                if (record.Id != null) byId.put(record.Id, record);
            }
            if (byId.isEmpty()) continue;
            
            Set<Id> ids = byId.keySet();
            String query = 'SELECT Id, LastModifiedDate FROM ' + sType.getDescribe().getName() + ' WHERE Id IN :ids';
            for (SObject dbRecord : Database.query(query, dmlAccessLevel)) {
                Datetime dbModified = (Datetime) dbRecord.get('LastModifiedDate');
                SObject inMemory = byId.get((Id) dbRecord.get('Id'));
                Datetime memModified = (Datetime) inMemory.get('LastModifiedDate');
                if (memModified != null && dbModified != null && dbModified > memModified) {
                    throw new UnitOfWorkException(
                        'Stale record detected (' + dbRecord.get('Id') + '). It was modified after being loaded; reload before updating.'
                    );
                }
            }
        }
    }
    
    private void publishEvents() {
        if (!platformEvents.isEmpty()) {
            EventBus.publish(platformEvents);
        }
    }
    
    private class DefaultDML implements IUnitOfWorkDML {
        public void doInsert(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            Database.insert(records, allOrNone, accessLevel);
        }
        public void doUpdate(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            Database.update(records, allOrNone, accessLevel);
        }
        public void doDelete(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel) {
            Database.delete(records, allOrNone, accessLevel);
        }
        public void doUpsert(List<SObject> records, Schema.SObjectField externalIdField, Boolean allOrNone, AccessLevel accessLevel) {
            Database.upsert(records, externalIdField, allOrNone, accessLevel);
        }
    }
    
    public class IllegalStateException extends Exception {}
    public class UnitOfWorkException extends Exception {}
}
