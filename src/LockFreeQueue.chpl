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
      var n : unmanaged node(objType);
      do {
        oldTop = _freeListHead.readABA();
        n = oldTop.getObject();
        if (n == nil) {
          n = new unmanaged node(objType);
          writeln("new allocated: " + n:string);
          return n;
        }
        var newTop = n.freeListNext;
      } while (!_freeListHead.compareExchangeABA(oldTop, newTop));
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
        var head_node = curr_head.getObject();
        var curr_tail = _tail.readABA();
        var tail_node = curr_tail.getObject();
        var next = curr_head.next.readABA();
        var next_node = next.getObject();

        if (head_node == tail_node) {
          if (next_node == nil) then
            return nil;
          _tail.compareExchangeABA(curr_tail, next_node);
        }
        else {
          if (_head.compareExchangeABA(curr_head, next_node)) {
            retire_node(head_node);
            return next_node.val;
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
    writeln(a.dequeue());
  }

  coforall i in 11..20 {
    var b = new unmanaged C(i);
    a.enqueue(b);
    writeln(a.dequeue());
  }
  writeln();
}
