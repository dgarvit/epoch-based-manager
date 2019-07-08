module RecycleLockFreeQueue {

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
    // Flag to set if objects held in the queue are to be deleted or not.
    // By default initialised to true.
    const delete_val : bool;

    proc init(type objType) {
      this.objType = objType;
      delete_val = true;
      this.complete();
      var _node = new unmanaged node(objType);
      _head.write(_node);
      _tail.write(_node);
    }

    proc init(type objType, delete_val : bool) {
      this.objType = objType;
      this.delete_val = delete_val;
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
          return n;
        }
        var newTop = n.freeListNext;
      } while (!_freeListHead.compareExchangeABA(oldTop, newTop));
      n.next.write(nil);
      n.freeListNext = nil;
      return n;
    }

    proc enqueue(newObj : objType) {
      var n = recycle_node();
      n.val = newObj;

      // Now enqueue
      while (true) {
        var tail = _tail.readABA();
        var next = tail.next.readABA();
        var next_node = next.getObject();
        var curr_tail = _tail.readABA();
        if (tail == curr_tail) {
          if (next_node == nil) {
            if (curr_tail.next.compareExchangeABA(next, n)) {
              _tail.compareExchangeABA(curr_tail, n);
              break;
            }
          }
          else {
            _tail.compareExchangeABA(curr_tail, next_node);
          }
        }
      }
    }

    proc dequeue() : (bool, objType) {
      while (true) {
        var head = _head.readABA();
        var head_node = head.getObject();
        var curr_tail = _tail.readABA();
        var tail_node = curr_tail.getObject();
        var next = head.next.readABA();
        var next_node = next.getObject();
        var curr_head = _head.readABA();

        if (head == curr_head) {
          if (head_node == tail_node) {
            if (next_node == nil) {
              var ret_val : objType;
              return (false, ret_val);
            }
            _tail.compareExchangeABA(curr_tail, next_node);
          }
          else {
            var ret_val = next_node.val;
            if (_head.compareExchangeABA(curr_head, next_node)) {
              retire_node(head_node);
              return (true, ret_val);
            }
          }
        }
      }

      var ret_val : objType;
      return (false, ret_val);
    }

    // TODO: Reclaim retired nodes after a while
    proc retire_node(nextObj : unmanaged node(objType)) {
    var val : objType;
    nextObj.val = val;
      do {
        var oldTop = _freeListHead.readABA();
        nextObj.freeListNext = oldTop.getObject();
      } while (!_freeListHead.compareExchangeABA(oldTop, nextObj));
    }
  }

  config const InitialQueueSize = 1024 * 1024;
  config const OperationsPerThread = 1024 * 1024;

  use Time;
  use Memory;

  proc main() {
    var lfq = new unmanaged LockFreeQueue(int);
    var timer = new Timer();

    // Fill the queue and warm up the cache.
    timer.start();
    forall i in 1..InitialQueueSize do lfq.enqueue(i);
    timer.stop();
    writeln("Queue was initialized to a size of ", InitialQueueSize, " in ", timer.elapsed());
    timer.clear();

    timer.start();
    coforall tid in 1..here.maxTaskPar {
      // Even tasks handle enqueue, odd tasks handle dequeue...
      if tid % 2 == 0 {
        for i in 1..OperationsPerThread do lfq.enqueue(i);
      } else {
        for i in 1..OperationsPerThread do lfq.dequeue();
      }
    }
    timer.stop();
    writeln("Performed ", OperationsPerThread, " operations per task with ", here.maxTaskPar, " tasks for a total of ", here.maxTaskPar * OperationsPerThread, " operations in a total of ", timer.elapsed(), "s");
  }
}
