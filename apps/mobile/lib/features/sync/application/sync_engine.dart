abstract interface class SyncEngine {
  Future<void> run();
  Future<void> runAfterCurrent();
  Future<void> waitForIdle();
  Future<void> recoverInterruptedSync();
}
