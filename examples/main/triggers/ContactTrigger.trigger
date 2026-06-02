trigger ContactTrigger on Contact (before update, after update) {
    new ContactHandler()
        .withNew(Trigger.new)
        .withOld(Trigger.old)
        .withOldMap((Map<Id, SObject>) Trigger.oldMap)
        .withNewMap((Map<Id, SObject>) Trigger.newMap)
        .trackLimits()
        .run();
}
