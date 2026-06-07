/**
 * Copyright (c) 2026 Ehsan Korhani
 * SPDX-License-Identifier: MIT
 *
 * @author Ehsan Korhani
 * @version 1.0.0
 */
public interface IUnitOfWork {
    IUnitOfWork registerNew(SObject record);
    IUnitOfWork registerNew(List<SObject> records);
    IUnitOfWork registerDirty(SObject record);
    IUnitOfWork registerDirty(List<SObject> records);
    IUnitOfWork registerDeleted(SObject record);
    IUnitOfWork registerDeleted(List<SObject> records);
    IUnitOfWork registerUpsert(SObject record, Schema.SObjectField externalIdField);
    IUnitOfWork registerPublish(SObject platformEvent);
    IUnitOfWork withParent(Schema.SObjectField lookupField, SObject parentRecord);
    IUnitOfWork registerRelationship(SObject childRecord, Schema.SObjectField lookupField, SObject parentRecord);
    IUnitOfWork asUserMode();
    IUnitOfWork asSystemMode();
    IUnitOfWork allOrNone(Boolean value);
    IUnitOfWork withConcurrencyCheck();
    IUnitOfWork onCommitSuccess(IUnitOfWorkAction action);
    void commitWork();
}
