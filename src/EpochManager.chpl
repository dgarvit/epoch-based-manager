/* Documentation for EpochManager */
module EpochManager {

  class EpochManager {
    const EBR_EPOCHS : uint = 3;
    var global_epoch : atomic uint;
    var allocated_list : unmanaged _token;
    var allocated_list_lock : atomic bool;
    var limbo_list: unmanaged _deletable;
    var epoch_list : [1..EBR_EPOCHS] unmanaged _deletable;

    proc init() {
      allocated_list = nil;
      limbo_list = nil;
      this.complete();
      global_epoch.write(1);
      for i in [1..EBR_EPOCHS] do
        epoch_list[i] = nil;
    }

    proc register() : _token{ // Should be called only once
      while allocated_list_lock.testAndSet() {
        chpl_task_yield(); // yield processor
      }
      var tok = new unmanaged _token();
      tok.prev = nil;
      tok.next = allocated_list;
      //allocated_list.prev = tok; // Deference nil error on runtime
      allocated_list = tok;
      allocated_list_lock.clear();

      return tok;
    }
  }

  class _token {
    var prev : _token;
    var next : _token;

    var local_epoch : atomic uint;

    proc init() {
      prev = nil;
      next = nil;
    }
  }

  class _deletable {
    var p: unmanaged object;

    var next : _deletable;
  }

}
