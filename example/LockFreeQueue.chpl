module LockFreeQueue {

  use EpochManager;
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

    proc enqueue(newObj : objType, tok : unmanaged _token) {
      var n = new unmanaged node(newObj);
      tok.pin();
      while (true) {
        var curr_tail = _tail.read();
        var next = curr_tail.next.read();
        if (next == nil) {
          if (curr_tail.next.compareExchange(next, n)) {
            _tail.compareExchange(curr_tail, n);
            break;
          }
        }
        else {
          _tail.compareExchange(curr_tail, next);
        }
      }
      tok.unpin();
    }

    proc dequeue(tok : unmanaged _token) : objType {
      tok.pin();
      while (true) {
        var curr_head = _head.read();
        var curr_tail = _tail.read();
        var next_node = curr_head.next.read();

        if (curr_head == curr_tail) {
          if (next_node == nil) {
            tok.unpin();
            return nil;
          }
          _tail.compareExchange(curr_tail, next_node);
        }
        else {
          var ret_val = next_node.val;
          if (_head.compareExchange(curr_head, next_node)) {
            tok.delete_obj(curr_head);
            tok.unpin();
            return ret_val;
          }
        }
      }

      tok.unpin();
      return nil;
    }

  }

  class C {
    var x : int;
  }

  proc main() {
    var a = new unmanaged LockFreeQueue(unmanaged C);
    var manager = new unmanaged EpochManager();
    coforall i in 1..10 {
      var tok = manager.register();
      var b = new unmanaged C(i);
      a.enqueue(b, tok);
      writeln(a.dequeue(tok));
      manager.unregister(tok);
    }

    coforall i in 11..20 {
      var tok = manager.register();
      if i%2 {
        var b = new unmanaged C(i);
        a.enqueue(b, tok);
      }
      else {
        writeln(a.dequeue(tok));
      }
      manager.unregister(tok);
    }

    coforall i in 21..30 {
      var tok = manager.register();
      var b = new unmanaged C(i);
      a.enqueue(b, tok);
      manager.unregister(tok);
    }

    coforall i in 31..40 {
      var tok = manager.register();
      writeln(a.dequeue(tok));
      manager.unregister(tok);
    }
  }
}
