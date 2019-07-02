/* Documentation for EpochManager */
module EpochManager {

  use LockFreeLinkedList;
  use LockFreeQueue;
  use LimboList;

  class EpochManager {
    const EBR_EPOCHS : uint = 3;
    const INACTIVE : uint = 0;
    var global_epoch : atomic uint;
    var is_setting_epoch : atomic bool;
    var allocated_list : unmanaged LockFreeLinkedList(unmanaged _token);
    var free_list : unmanaged LockFreeQueue(unmanaged _token);
    var limbo_list : [1..EBR_EPOCHS] unmanaged LimboList();
    var id_counter : atomic uint;

    proc init() {
      allocated_list = new unmanaged LockFreeLinkedList(unmanaged _token);
      free_list = new unmanaged LockFreeQueue(unmanaged _token, false);
      this.complete();

      // Initialise the free list pool with here.maxTaskPar tokens
      forall i in 0..#here.maxTaskPar {
        var tok = new unmanaged _token(i:uint, this:unmanaged);
        allocated_list.append(tok);
        free_list.enqueue(tok);
      }
      id_counter.write(here.maxTaskPar:uint);
      global_epoch.write(1);
      forall i in 1..EBR_EPOCHS do
        limbo_list[i] = new unmanaged LimboList();
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
      if (tok.local_epoch.read() == 0) then
        tok.local_epoch.write(global_epoch.read());
    }

    proc unpin(tok: unmanaged _token) {
      tok.local_epoch.write(INACTIVE);
    }

    // Attempt to announce a new epoch
    proc try_advance() : uint {
      var epoch = global_epoch.read();
      for tok in allocated_list {
        var local_epoch = tok.local_epoch.read();
        if (local_epoch > 0 && local_epoch != epoch) then
          return 0;
      }

      // Advance the global epoch
      epoch = (epoch % EBR_EPOCHS) + 1;
      global_epoch.write(epoch);

      // Return epoch which is safe to be reclaimed. It is safe to
      // reclaim from e-2 epoch
      select epoch {
        when 1 do return EBR_EPOCHS - 1;
        when 2 do return EBR_EPOCHS;
        otherwise do return epoch - 2;
      }
    }

    proc delete_obj(tok : unmanaged _token, x : unmanaged object) {
      var del_epoch = tok.local_epoch.read();
      if (del_epoch == 0) {
        writeln("Bad local epoch! Please pin! Using global epoch!");
        del_epoch = global_epoch.read();
      }
      limbo_list[del_epoch].push(x);
    }

    proc try_reclaim() {
      var count = EBR_EPOCHS;

      // if nothing to reclaim, try the next epoch, but loop only for one
      // full cycle
      while (count) {
        count = count - 1;

        // Set a flag to let other tasks know that a task is already
        // trying to reclaim
        if (is_setting_epoch.testAndSet()) {
          return;
        }
        var reclaim_epoch = try_advance();
        if (reclaim_epoch == 0) {
          // try_advance failed
          is_setting_epoch.clear();
          return;
        }

        var reclaim_limbo_list = limbo_list[reclaim_epoch];
        var head = reclaim_limbo_list.pop();
        is_setting_epoch.clear();

        while (head != nil) {
          var next = head.next;
          delete head.val;
          reclaim_limbo_list.retire_node(head);
          head = next;
        }
      }
    }

    proc deinit() {
      delete allocated_list;
      delete free_list;
      delete limbo_list;
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

    proc unregister() {
      manager.unregister(this:unmanaged);
    }
  }

  class C {
    var x : int;
    proc deinit() {
      writeln("Deinit: " + this:string);
    }
  }

  proc main() {
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
    delete a;
  }
}
