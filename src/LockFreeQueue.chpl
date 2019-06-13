/**
 * Based on Michael Scott Queue.
 */
module LockFreeQueue {

  use LocalAtomics;

  class node {
    type eltType;
    var val : eltType;
    var next : LocalAtomicObject(unmanaged node(eltType));
    var freeListNext : unmanaged node(eltType);

    proc init(val : ?eltType) {
      this.eltType = eltType;
      this.val = val;
    }

    proc init(type eltType) {
      this.eltType = eltType;
    }
  }

  class LockFreeQueue {
    type objType;
    var _head : LocalAtomicObject(unmanaged node(objType));
    var _tail : LocalAtomicObject(unmanaged node(objType));
    var _freeListHead : LocalAtomicObject(unmanaged node(objType));

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
        if (curr_head.getObject() == curr_tail.getObject()) {
          if (next.getObject() == nil) then
            return nil;
          _tail.compareExchangeABA(curr_tail, next.getObject());
        }
        else {
          if (_head.compareExchangeABA(curr_head, next.getObject())) {
            var nextObj = next.getObject();

            // Push the node to freelist
            do {
              var oldTop = _freeListHead.readABA();
              nextObj.freeListNext = oldTop.getObject();
            } while (!_freeListHead.compareExchangeABA(oldTop, nextObj));

            return nextObj.val;
          }
        }
      }
      return nil;
    }

    iter these() : objType {
      var ptr = _head.read().next.read();
      while (ptr != nil) {
        yield ptr.val;
        ptr = ptr.next.read();
      }
    }

    proc peek() : objType {
      var actual_head = _head.read().next.read();
      if (actual_head != nil) then
        return actual_head.val;
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
  }
}
