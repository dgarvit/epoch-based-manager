/* Documentation for EpochManager */
module EpochManager {

  class EpochManager {
    const EBR_EPOCHS : uint = 3;
    var global_epoch : atomic uint;
    var allocated_list : LinkedList(unmanaged _token);
    var allocated_list_lock : atomic bool;
    var limbo_list: unmanaged _deletable;
    var epoch_list : [1..EBR_EPOCHS] unmanaged _deletable;
    var id_counter : atomic uint;

    proc init() {
      allocated_list = new LinkedList(unmanaged _token);
      limbo_list = nil;
      this.complete();
      global_epoch.write(1);
      for i in [1..EBR_EPOCHS] do
        epoch_list[i] = nil;
    }

    proc register() : unmanaged _token { // Should be called only once
      while allocated_list_lock.testAndSet() {
        chpl_task_yield(); // yield processor
      }
      var tok = new unmanaged _token(id_counter.fetchAdd(1));
      allocated_list.append(tok);
      allocated_list_lock.clear();
      return tok;
    }

    proc unregister(tok: unmanaged _token) {
      while allocated_list_lock.testAndSet() {
        chpl_task_yield();
      }
      allocated_list.remove(tok);
      delete tok;
      allocated_list_lock.clear();
    }
  }

  class _token {
    var local_epoch : atomic uint;
    const id : uint;

    proc init(x : uint) {
      id = x;
    }
  }

  class _deletable {
    var p: unmanaged object;

    var next : _deletable;
  }
}
