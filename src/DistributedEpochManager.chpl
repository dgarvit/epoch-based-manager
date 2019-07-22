module DistributedEpochManager {
  
  use EpochManager;
  
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
    var is_setting_locale_epoch : atomic bool;
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

  var manager = new DistributedEpochManager();
  coforall loc in Locales do on loc {
    /*coforall i in 0..here.id {
      var tok = manager.register();
      writeln(tok.id);
      tok.unregister();
    }*/
    writeln(manager.locale_epoch);
    writeln();
  }
}
