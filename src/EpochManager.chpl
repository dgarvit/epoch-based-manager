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
    proc try_advance() : bool {
      if (is_setting_epoch.testAndSet()) then
        return false;
      var epoch = global_epoch.read();
      for tok in allocated_list {
        var local_epoch = tok.local_epoch.read();
        if (local_epoch > 0 && local_epoch != epoch) {
          is_setting_epoch.clear();
          return false;
        }
      }

      // Advance the global epoch
      global_epoch.write((epoch % EBR_EPOCHS) + 1);
      is_setting_epoch.clear();
      return true;
    }

    // Return epoch which is safe to be reclaimed
    proc gc_epoch() : uint {
      var epoch = global_epoch.read() : int;
      var ebr_epochs = EBR_EPOCHS : int;

      // It is safe to reclaim from e-2 epoch
      return ((ebr_epochs + (epoch-3) % ebr_epochs):uint % EBR_EPOCHS) + 1;
    }

    proc delete_obj(tok : unmanaged _token, x : unmanaged object) {
      var globalEpoch = global_epoch.read();
      limbo_list[globalEpoch].enqueue(x);
    }
/*
    proc try_reclaim() {
      var count = EBR_EPOCHS;

      // if nothing to reclaim, try the next epoch, but loop only for one
      // full cycle
      while (count) {
        count = count - 1;
        if (!try_advance()) {
          return;
        }

        var reclaim_epoch = this.gc_epoch();
        var x = limbo_list[reclaim_epoch].dequeue();
        while (x != nil) {
          delete x;
        }

        var staging_epoch = global_epoch.read();
        if (epoch_list[staging_epoch] != nil) {
          writeln("Error: List not empty.");
          //exit();
        }

        while limbo_list_lock.testAndSet() {
          chpl_task_yield();
        }
        epoch_list[staging_epoch] = limbo_list;
        limbo_list = nil;
        limbo_list_lock.clear();

        var gc_list = epoch_list[staging_epoch];
        if (gc_list != nil) {
          _reclaim(gc_list);
          epoch_list[staging_epoch] = nil;
          break;
        }
      }
    }

    proc _reclaim(inout gc_list : unmanaged _deletable) {
      while (gc_list != nil) {
        var x = gc_list;
        gc_list = gc_list.next;
        delete x.p;
        delete x;
      }
    }*/
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
  }

  class C {
    var x : int;
  }

  // var a = new unmanaged LockFreeQueue(unmanaged _deletable);
  // coforall i in 1..10 {
  //   var b = new unmanaged C(i);
  //   var c = new unmanaged _deletable(b);
  //   a.enqueue(c);
  // }

  // writeln(a);

  var a = new unmanaged EpochManager();
  coforall i in 1..10 {
    var tok = a.register();
    var b = new unmanaged C(i);
    /*tok.pin();
    writeln(tok.id:string + " " + tok.local_epoch.read():string);
    tok.unpin();
    writeln(tok.id:string + " " + tok.local_epoch.read():string);*/
    tok.delete_obj(b);
    a.unregister(tok);
  }
  writeln(a.limbo_list[1]);
  // writeln(a);
  /*coforall i in 1..20 {
    var tok = a.register();
    a.pin(tok);
    if (a.try_advance()) {
      writeln("Advanced. " + a.global_epoch.read():string);
      for ii in a.allocated_list {
    writeln("Allocated List : " + ii:string);
  }
    }
    else {
      writeln("Cannot advance. " + a.global_epoch.read():string);
    }
    a.unregister(tok);
  }*/
  /*for i in a.allocated_list {
    writeln("Allocated List : " + i:string);
  }
  writeln();
  for i in a.free_list {
    writeln("Free list : " + i:string);
  }*/
}
