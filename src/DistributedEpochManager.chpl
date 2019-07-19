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
    var manager : unmanaged EpochManager();
    proc init() {
      manager = new unmanaged EpochManager();
      this.complete();
      this.pid = _newPrivatizedClass(this);
    }
    proc init(other, privatizedData) { 
      manager = new unmanaged EpochManager();
      this.complete();
      this.pid = privatizedData;
    }
    proc dsiPrivatize(privatizedData) { return new unmanaged DistributedEpochManagerImpl(this, pid); }
    proc dsiGetPrivatizeData() { return pid; }
    inline proc getPrivatizedInstance() { return chpl_getPrivatizedCopy(this.type, pid); } // Bonus...
    forwarding manager;
  }

  class C {
    var x : int;

    proc deinit() {
      writeln(x:string + " reclaimed.");
    }
  }

  var manager = new DistributedEpochManager();
  coforall loc in Locales do on loc {
    // writeln(loc);
    // writeln(manager.manager);
    coforall i in 1..10 {
      var tok = manager.register();
      var b = new unmanaged C(i);
      tok.pin();
      tok.try_reclaim();
      tok.delete_obj(b);
      manager.unregister(tok);
    }
    manager.try_reclaim();
    // delete manager;
  }
}
