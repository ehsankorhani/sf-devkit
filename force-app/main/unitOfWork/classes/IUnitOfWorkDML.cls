/**
 * Copyright (c) 2026 Ehsan Korhani
 * SPDX-License-Identifier: MIT
 *
 * @author Ehsan Korhani
 * @version 1.0.0
 */
public interface IUnitOfWorkDML {
    void doInsert(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel);
    void doUpdate(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel);
    void doDelete(List<SObject> records, Boolean allOrNone, AccessLevel accessLevel);
    void doUpsert(List<SObject> records, Schema.SObjectField externalIdField, Boolean allOrNone, AccessLevel accessLevel);
}
