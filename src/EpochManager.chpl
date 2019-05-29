/* Documentation for EpochManager */
module EpochManager {

  class EpochManager {
    const EBR_EPOCHS : uint = 3;
    var global_epoch : atomic uint;
    var allocated_list : unmanaged _token;
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
  }

  class _token {
    var prev : _token;
    var next : _token;

    var local_epoch : atomic uint;
  }

  class _deletable {
    var p: unmanaged object;

    var next : _deletable;
  }

  var a = new EpochManager();
  writeln(a);
}
