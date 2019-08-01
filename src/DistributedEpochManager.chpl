module DistributedEpochManager {

  use LockFreeLinkedList;
  use LockFreeQueue;
  use LimboList;

  pragma "always RVF"
  record DistributedEpochManager {
    var _pid : int;
    proc init() { this._pid = (new unmanaged DistributedEpochManagerImpl()).pid; }
    forwarding chpl_getPrivatizedCopy(unmanaged DistributedEpochManagerImpl, _pid);
  }

  class DistributedEpochManagerImpl {
    var pid : int;
    const EBR_EPOCHS : uint = 3;
    const INACTIVE : uint = 0;
    // Global Epoch which operates on locale epochs
    var global_epoch : unmanaged GlobalEpoch;
    
    // Locale Epoch which operates on task local epochs on each locale
    var locale_epoch : atomic uint;
    var active_tasks : atomic uint;
    var is_setting_epoch : atomic bool;
    var allocated_list : unmanaged LockFreeLinkedList(unmanaged _token);
    var free_list : unmanaged LockFreeQueue(unmanaged _token);
    var limbo_list : [1..EBR_EPOCHS] unmanaged LimboList();
    var id_counter : atomic uint;

    proc init() {
      this.global_epoch = new unmanaged GlobalEpoch(1:uint);
      allocated_list = new unmanaged LockFreeLinkedList(unmanaged _token);
      free_list = new unmanaged LockFreeQueue(unmanaged _token, false);
      this.complete();
      this.pid = _newPrivatizedClass(this);

      // Initialise the free list pool with here.maxTaskPar tokens
      forall i in 0..#here.maxTaskPar {
        var tok = new unmanaged _token(i:uint, this:unmanaged);
        allocated_list.append(tok);
        free_list.enqueue(tok);
      }
      locale_epoch.write(global_epoch.read());
      id_counter.write(here.maxTaskPar:uint);
      forall i in 1..EBR_EPOCHS do
        limbo_list[i] = new unmanaged LimboList();
    }

    proc init(other, privatizedData, global_epoch) {
      allocated_list = new unmanaged LockFreeLinkedList(unmanaged _token);
      free_list = new unmanaged LockFreeQueue(unmanaged _token, false);
      this.complete();
      this.global_epoch = global_epoch;

      // Initialise the free list pool with here.maxTaskPar tokens
      forall i in 0..#here.maxTaskPar {
        var tok = new unmanaged _token(i:uint, this:unmanaged);
        allocated_list.append(tok);
        free_list.enqueue(tok);
      }
      locale_epoch.write(global_epoch.read());
      id_counter.write(here.maxTaskPar:uint);
      forall i in 1..EBR_EPOCHS do
        limbo_list[i] = new unmanaged LimboList();
      this.pid = privatizedData;
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
      unpin(tok);
      free_list.enqueue(tok);
    }

    proc pin(tok: unmanaged _token) {
      // An inactive task has local_epoch set to 0. A value other than 0
      // implies active task
      if (tok.local_epoch.read() == INACTIVE) {
        active_tasks.add(1);
        tok.local_epoch.write(locale_epoch.read());
      }
    }

    proc getMinimumEpoch() : uint {
      if active_tasks.read() > 0 {
        var minEpoch = max(uint);
        for tok in allocated_list {
          var local_epoch = tok.local_epoch.read();
          if (local_epoch > 0) then
            minEpoch = min(minEpoch, local_epoch);
        }

        if (minEpoch != max(uint)) then return minEpoch;
      }

      return 0;
    }

    proc delete_obj(tok : unmanaged _token, x : unmanaged object) {
      var del_epoch = tok.local_epoch.read();
      if (del_epoch == 0) {
        writeln("Bad local epoch! Please pin! Using global epoch!");
        del_epoch = global_epoch.read();
      }
      limbo_list[del_epoch].push(x); // How to make sure the object gets pushed to its local limbo list?
    }

    // Return epoch which is safe to be reclaimed. It is safe to
    // reclaim from e-2 epoch
    proc getReclaimEpoch() : uint {
      const epoch = locale_epoch.read();
      select epoch {
        when 1 do return EBR_EPOCHS - 1;
        when 2 do return EBR_EPOCHS;
        otherwise do return epoch - 2;
      }
    }

    // Try to announce a new epoch. If successful, reclaim objects which are
    // safe to reclaim
    proc try_reclaim() : uint {
      if (is_setting_epoch.testAndSet()) then return;
      if (global_epoch.is_setting_epoch.testAndSet()) {
        is_setting_epoch.clear();
        return;
      };

      var minEpoch = max(uint);
      coforall loc in Locales with (min reduce minEpoch) do on loc {
        var _this = getPrivatizedInstance();
        var localeMinEpoch = _this.getMinimumEpoch();
        if localeMinEpoch != 0 then
          minEpoch = min(minEpoch, localeMinEpoch); // Is this safe? How about store all data in a data structure first?
      }
      const current_global_epoch = global_epoch.read();

      if minEpoch == current_global_epoch || minEpoch == max(uint) {
        const new_epoch = (current_global_epoch % EBR_EPOCHS) + 1;
        global_epoch.write(new_epoch);
        coforall loc in Locales do on loc {
          var _this = getPrivatizedInstance();
          _this.locale_epoch.write(new_epoch);

          const reclaim_epoch = _this.getReclaimEpoch();
          var reclaim_limbo_list = _this.limbo_list[reclaim_epoch];
          var head = reclaim_limbo_list.pop();

          while (head != nil) {
            var next = head.next;
            delete head.val;
            // reclaim_limbo_list.retire_node(head);
            delete head;
            head = next;
          }
        }
      }
      global_epoch.is_setting_epoch.clear();
      is_setting_epoch.clear();
    }

    proc unpin(tok: unmanaged _token) {
      if (tok.local_epoch.read() != INACTIVE) {
        active_tasks.sub(1);
        tok.local_epoch.write(INACTIVE);
      }
    }

    proc dsiPrivatize(privatizedData) {
      return new unmanaged DistributedEpochManagerImpl(this, pid, this.global_epoch);
    }
    
    proc dsiGetPrivatizeData() {
      return pid;
    }
    
    inline proc getPrivatizedInstance() {
      return chpl_getPrivatizedCopy(this.type, pid);
    }
  }

  class GlobalEpoch {
    var epoch : atomic uint;
    var is_setting_epoch : atomic bool;

    proc init(x : uint) {
      this.complete();
      epoch.write(x);
    }

    forwarding epoch;
  }

  class _token {
    var local_epoch : atomic uint;
    const id : uint;
    var manager : unmanaged DistributedEpochManagerImpl;

    proc init(x : uint, manager : unmanaged DistributedEpochManagerImpl) {
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
      writeln(x:string + " reclaimed.");
    }
  }

  config const OperationsPerThread = 1024 * 1024;

  var manager = new DistributedEpochManager();
  coforall loc in Locales do on loc {
    coforall tid in 1..here.maxTaskPar {
      var tok = manager.register();
      for i in 1..(OperationsPerThread*2) {
        if i%2 == 0 {
          var b = new unmanaged C(i);
          tok.pin();
          tok.delete_obj(b);
          tok.unpin();
        } else {
          manager.try_reclaim();
        }
      }
      tok.unregister();
    }
  }
  manager.try_reclaim();
  manager.try_reclaim();
  manager.try_reclaim();

  writeln("Done");
}
