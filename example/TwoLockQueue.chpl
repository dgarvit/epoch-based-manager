module TwoLockQueue {

  class node {
    type eltType;
    var val : eltType;
    var next : unmanaged node(eltType);

    proc init(val : ?eltType) {
      this.eltType = eltType;
      this.val = val;
    }

    proc init(type eltType) {
      this.eltType = eltType;
    }
  }

  pragma "no doc"
  pragma "default intent is ref"
  record Lock {
    var _lock : chpl__processorAtomicType(bool);

    inline proc acquire() {
      on this do local {
        if _lock.testAndSet() == true { 
          while _lock.read() == true || _lock.testAndSet() == true {
            chpl_task_yield();
          }
        }
      }
    }

    inline proc release() {
      on this do local do _lock.clear();
    }
  }

  class TwoLockQueue {
    type objType;
    var _head : unmanaged node(objType);
    var _tail : unmanaged node(objType);

    var h_lock : Lock;
    var t_lock : Lock;

    proc init(type objType) {
      this.objType = objType;
      var _node = new unmanaged node(objType);
      _head = _node;
      _tail = _node;
    }

    proc enqueue(newObj : objType) {
      var n = new unmanaged node(newObj);
      t_lock.acquire();
      _tail.next = n;
      _tail = n;
      t_lock.release();
    }

    proc dequeue() : (bool, objType) {
      h_lock.acquire();
      var n = _head;
      var new_head = n.next;
      if (new_head == nil) {
        h_lock.release();
        var retval : objType;
        return (false, retval);
      }
      var retval = new_head.val;
      delete _head;
      _head = new_head;
      h_lock.release();
      return (true, retval);
    }
  }

  config const InitialQueueSize = 1024 * 1024;
  config const OperationsPerThread = 1024 * 1024;

  use Time;
  use Memory;

  proc main() {
    var tlq = new unmanaged TwoLockQueue(int);
    var timer = new Timer();

    // Fill the queue and warm up the cache.
    timer.start();
    forall i in 1..InitialQueueSize do tlq.enqueue(i);
    timer.stop();
    writeln("Queue was initialized to a size of ", InitialQueueSize, " in ", timer.elapsed());
    timer.clear();

    timer.start();
    coforall tid in 1..here.maxTaskPar {
      // Even tasks handle enqueue, odd tasks handle dequeue...
      if tid % 2 == 0 {
        for i in 1..OperationsPerThread do tlq.enqueue(i);
      } else {
        for i in 1..OperationsPerThread do tlq.dequeue();
      }
    }
    timer.stop();
    writeln("Performed ", OperationsPerThread, " operations per task with ", here.maxTaskPar, " tasks for a total of ", here.maxTaskPar * OperationsPerThread, " operations in a total of ", timer.elapsed(), "s");
  }
}