module TwoLockQueue {

  use EpochManager;

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

  class TokenWrapper {
    var _tok : unmanaged _token;
    
    proc init(_tok : unmanaged _token) {
      this._tok = _tok;
    }

    proc deinit() {
      _tok.unregister();
    }
    
    forwarding _tok;
  }

  class TwoLockQueue {
    type objType;
    var _head : unmanaged node(objType);
    var _tail : unmanaged node(objType);
    var _manager = new owned EpochManager();

    var h_lock : atomic bool;
    var t_lock : atomic bool;

    proc init(type objType) {
      this.objType = objType;
      var _node = new unmanaged node(objType);
      _head = _node;
      _tail = _node;
    }

    proc getToken() {
      return new owned TokenWrapper(_manager.register());
    }

    proc enqueue(newObj : objType, tok) {
      var n = new unmanaged node(newObj);
      while t_lock.testAndSet() {
        chpl_task_yield();
      }
      tok.pin();
      _tail.next = n;
      _tail = n;
      t_lock.clear();
      tok.unpin();
    }

    proc dequeue(tok) : (bool, objType) {
      while h_lock.testAndSet() {
        chpl_task_yield();
      }
      tok.pin();
      var n = _head;
      var new_head = n.next;
      if (new_head == nil) {
        h_lock.clear();
        var retval : objType;
        return (false, retval);
      }
      var retval = new_head.val;
      tok.delete_obj(_head);
      _head = new_head;
      h_lock.clear();
      tok.unpin();
      return (true, retval);
    }
  }

  config const InitialQueueSize = 1024 * 1024;
  config const OperationsPerThread = 1024 * 1024;

  use Time;

  proc main() {
    var tlq = new unmanaged TwoLockQueue(int);
    var timer = new Timer();

    // Fill the queue and warm up the cache.
    timer.start();
    forall i in 1..10 with (var tok = tlq.getToken()) do tlq.enqueue(i, tok);
    timer.stop();
    writeln("Queue was initialized to a size of ", InitialQueueSize, " in ", timer.elapsed());
    timer.clear();

    timer.start();
    coforall tid in 1..here.maxTaskPar {
      var tok = tlq.getToken();
      // Even tasks handle enqueue, odd tasks handle dequeue...
      if tid % 2 == 0 {
        for i in 1..OperationsPerThread do tlq.enqueue(i, tok);
      } else {
        for i in 1..OperationsPerThread do tlq.dequeue(tok);
      }
    }
    timer.stop();
    writeln("Performed ", OperationsPerThread, " operations per task with ", here.maxTaskPar, " tasks for a total of ", here.maxTaskPar * OperationsPerThread, " operations in a total of ", timer.elapsed(), "s");
  }
}