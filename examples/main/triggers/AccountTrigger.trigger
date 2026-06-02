trigger AccountTrigger on Account (
    before insert,
    before update,
    before delete,
    after insert,
    after update
) {
    new AccountHandler().fromTrigger().maxLoops(5).run();
}
