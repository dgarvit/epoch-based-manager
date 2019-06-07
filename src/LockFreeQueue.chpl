module LockFreeQueue {

  use LocalAtomics;

  class node {
    type eltType;
    var val : eltType;
    var next : LocalAtomicObject(unmanaged node(eltType));

    proc init(val : ?eltType) {
      this.eltType = eltType;
      this.val = val;
    }

    proc init(type eltType) {
      this.eltType = eltType;
      val = nil;
    }
  }

  class LockFreeQueue {
    type objType;
    var _head : LocalAtomicObject(unmanaged node(objType));
    var _tail : LocalAtomicObject(unmanaged node(objType));

    proc init(type objType) {
      this.objType = objType;
      this.complete();
      var _node = new unmanaged node(objType);
      _head.write(_node);
      _tail.write(_node);
    }

    proc enqueue(newObj : objType) {
      var n = new unmanaged node(newObj);
      while (true) {
        var curr_tail = _tail.readABA();
        var next = curr_tail.next.readABA();
        if (next.getObject() == nil) {
          if (curr_tail.next.compareExchangeABA(next, n)) {
            _tail.compareExchangeABA(curr_tail, n);
            break;
          }
        }
        else {
          _tail.compareExchangeABA(curr_tail, next.getObject());
        }
      }
    }

    proc dequeue() : objType {
      while (true) {
        var curr_head = _head.readABA();
        var curr_tail = _tail.readABA();
        var next = curr_head.next.readABA();
        if (_head.read() == _tail.read()) {
          if (next.getObject() == nil) then
            return nil;
          _tail.compareExchangeABA(curr_tail, next.getObject());
        }
        else {
          if (_head.compareExchangeABA(curr_head, next.getObject())) then
            return next.getObject().val;
        }
      }
      return nil;
    }

    proc deinit() {
      var ptr = _head.read();
      while (ptr != nil) {
        _head = ptr.next;
        delete ptr.val;
        delete ptr;
        ptr = _head.read();
      }
    }

    proc peek() : objType {
      return _head.read().next.read().val;
    }
  }
}
