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
    var global_epoch : unmanaged GlobalEpoch;
    // var manager : unmanaged EpochManager();
    proc init() {
      // manager = new unmanaged EpochManager();
      this.global_epoch = new unmanaged GlobalEpoch();
      this.complete();
      this.pid = _newPrivatizedClass(this);
    }
    proc init(other, privatizedData, global_epoch) {
      // manager = new unmanaged EpochManager();
      this.complete();
      this.global_epoch = global_epoch;
      this.pid = privatizedData;
    }
    proc dsiPrivatize(privatizedData) { return new unmanaged DistributedEpochManagerImpl(this, pid, this.global_epoch); }
    proc dsiGetPrivatizeData() { return pid; }
    inline proc getPrivatizedInstance() { return chpl_getPrivatizedCopy(this.type, pid); }
    // forwarding manager;
  }

  class C {
    var x : int;

    proc deinit() {
      writeln(x:string + " reclaimed.");
    }
  }

  class GlobalEpoch {
    var epoch : atomic int;

    proc init() {
      this.complete();
      epoch.write(1);
    }

   forwarding epoch;
  }

  var manager = new DistributedEpochManager();
  coforall loc in Locales do on loc {
    writeln(manager.global_epoch.fetchAdd(1));
  }

  manager.global_epoch.write(99);
  coforall loc in Locales do on loc {
    writeln(manager.global_epoch);
  }
}
