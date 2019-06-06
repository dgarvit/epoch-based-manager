module LockFreeQueue {

  use LocalAtomics;

  class LockFreeQueue {
    type objType;
    var _head : LocalAtomicObject(objType);
    var _tail : LocalAtomicObject(objType);

    proc init(type objType) {
      this.objType = objType;
      this.complete();
      var _node = new objType(0);
      _head.write(_node);
      _tail.write(_node);
    }

    proc enqueue(newObj : objType) {
      while (true) {
        var curr_tail = _tail.readABA();
        var next = curr_tail.next.readABA();
        if (next.getObject() == nil) {
          if (curr_tail.next.compareExchangeABA(next, newObj)) {
            _tail.compareExchangeABA(curr_tail, newObj);
            break;
          }
        }
        else {
          _tail.compareExchangeABA(curr_tail, next.getObject());
        }
      }
    }
  }

  class node {
    var val : int;
    var next : LocalAtomicObject(unmanaged node);

    proc init(val : int) {
      this.val = val;
    }
  }
}
