/* Documentation for EpochManager */
module EpochManager {

  class EpochManager {
    const EBR_EPOCHS : uint = 3;
    var global_epoch : atomic uint;
    var allocated_list : unmanaged _token;
    var limbo_list: unmanaged LinkedList(unmanaged _deletable);
    var epoch_list : [1..EBR_EPOCHS] unmanaged _deletable;
  }

  class _token {
    var prev : _token;
    var next : _token;

    var local_epoch : atomic uint;
  }

  class _deletable {    
    type objType;
    var p: objType;
  }
}
