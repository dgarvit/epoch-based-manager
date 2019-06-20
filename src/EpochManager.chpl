/* Documentation for EpochManager */
module EpochManager {

  use LockFreeLinkedList;
  use LockFreeQueue;

  class EpochManager {
    const EBR_EPOCHS : uint = 3;
    const INACTIVE : uint = 0;
    var global_epoch : atomic uint;
    var is_setting_epoch : atomic bool;
    var allocated_list : unmanaged LockFreeLinkedList(unmanaged _token);
    var free_list : unmanaged LockFreeQueue(unmanaged _token);
    var limbo_list : [1..EBR_EPOCHS] unmanaged LockFreeQueue(unmanaged object);
    var id_counter : atomic uint;

    proc init() {
      allocated_list = new unmanaged LockFreeLinkedList(unmanaged _token);
      free_list = new unmanaged LockFreeQueue(unmanaged _token);
      this.complete();
      global_epoch.write(1);
      limbo_list = new unmanaged LockFreeQueue(unmanaged object);
    }

    proc register() : unmanaged _token { // Should be called only once
      var tok = free_list.dequeue();
      if (tok == nil) {
        tok = new unmanaged _token(id_counter.fetchAdd(1), this:unmanaged);
        allocated_list.append(tok);
      }
      return tok;
    }

    proc unregister(tok: unmanaged _token) {
      tok.local_epoch.write(INACTIVE);
      free_list.enqueue(tok);
    }

    proc pin(tok: unmanaged _token) {
      // An inactive task has local_epoch set to 0. A value other than 0
      // implies active task
      tok.local_epoch.write(global_epoch.read());
    }

    proc unpin(tok: unmanaged _token) {
      tok.local_epoch.write(INACTIVE);
    }

    // Attempt to announce a new epoch
    proc try_advance() : uint {
      // Set a flag to let other tasks know that a task is already
      // trying to advance the global epoch
      if (is_setting_epoch.testAndSet()) then
        return 0;
      var epoch = global_epoch.read();
      for tok in allocated_list {
        var local_epoch = tok.local_epoch.read();
        if (local_epoch > 0 && local_epoch != epoch) {
          is_setting_epoch.clear();
          return 0;
        }
      }

      // Advance the global epoch
      epoch = (epoch % EBR_EPOCHS) + 1;
      global_epoch.write(epoch);
      is_setting_epoch.clear();

      // Return epoch which is safe to be reclaimed. It is safe to
      // reclaim from e-2 epoch
      select epoch {
        when 1 do return EBR_EPOCHS - 1;
        when 2 do return EBR_EPOCHS;
        otherwise do return epoch - 2;
      }
    }

    proc delete_obj(tok : unmanaged _token, x : unmanaged object) {
      var globalEpoch = global_epoch.read();
      limbo_list[globalEpoch].enqueue(x);
    }

    proc try_reclaim() {
      var count = EBR_EPOCHS;

      // if nothing to reclaim, try the next epoch, but loop only for one
      // full cycle
      while (count) {
        count = count - 1;
        var reclaim_epoch = try_advance();
        if (reclaim_epoch == 0) then
          // try_advance failed
          return;

        var reclaim_limbo_list = limbo_list[reclaim_epoch];
        var x = reclaim_limbo_list.dequeue();
        while (x != nil) {
          delete x;
          x = reclaim_limbo_list.dequeue();
        }
      }
    }
  }

  class _token {
    var local_epoch : atomic uint;
    const id : uint;
    var manager : unmanaged EpochManager;

    proc init(x : uint, manager : unmanaged EpochManager) {
      id = x;
      this.manager = manager;
    }

    proc pin() {
      manager.pin(this:unmanaged);
    }

    proc unpin() {
      manager.unpin(this:unmanaged);
    }

    proc delete_obj(x) {
      manager.delete_obj(this:unmanaged, x);
    }

    proc try_reclaim() {
      manager.try_reclaim();
    }
  }

  class C {
    var x : int;
    proc deinit() {
      writeln("Deinit: " + this:string);
    }
  }

  var a = new unmanaged EpochManager();
  coforall i in 1..10 {
    var tok = a.register();
    var b = new unmanaged C(i);
    tok.pin();
    tok.try_reclaim();
    tok.delete_obj(b);
    a.unregister(tok);
  }
  a.try_reclaim();
}
