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

    proc recycle_node() : unmanaged node(objType) {
      var oldTop : ABA(unmanaged node(objType));
      do {
        oldTop = _freeListHead.readABA();
        if (oldTop.getObject() == nil) {
          var n = new unmanaged node(objType);
          writeln("new allocated: " + n:string);
          return n;
        }
        var newTop = oldTop.freeListNext;
      } while (!_freeListHead.compareExchangeABA(oldTop, newTop));
      var n = oldTop.getObject();
      n.next.write(nil);
      n.freeListNext = nil;
      writeln("Recycled: " + n:string);
      return n;
    }

    proc enqueue(newObj : objType) {
      var n = recycle_node();
      n.val = newObj;

      // Now enqueue
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
            var nextObj = curr_head.getObject();
            retire_node(nextObj);        
            return next.getObject().val;
          }
        }
      }
      return nil;
    }

    proc retire_node(nextObj : unmanaged node(objType)) {
      do {
        var oldTop = _freeListHead.readABA();
        nextObj.freeListNext = oldTop.getObject();
      } while (!_freeListHead.compareExchangeABA(oldTop, nextObj));
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

  class C {
    var x : int;
  }

  var a = new unmanaged LockFreeQueue(unmanaged C);
  coforall i in 1..10 {
    var b = new unmanaged C(i);
    a.enqueue(b);
  }

  coforall i in 1..12 {
    writeln(a.dequeue());
  }

  coforall i in 11..20 {
    var b = new unmanaged C(i);
    a.enqueue(b);
    writeln(a.dequeue());
  }
  writeln();
}
