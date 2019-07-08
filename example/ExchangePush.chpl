module ExchangePush {
  use LocalAtomics;

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

  class ExchangePush {
    type objType;
    var _head : LocalAtomicObject(unmanaged node(objType));

    proc init(type objType) {
      this.objType = objType;
    }

    proc push(obj : unmanaged objType) {
      var n = new unmanaged node(obj);
      var oldHead = _head.exchange(n);
      n.next = oldHead;
    }
  }

  config const InitialQueueSize = 1024 * 1024;
  config const OperationsPerThread = 1024 * 1024;

  use Time;
  use Memory;

  proc main() {
    var ep = new unmanaged ExchangePush(int);
    var timer = new Timer();

    // Fill the queue and warm up the cache.
    timer.start();
    forall i in 1..InitialQueueSize do ep.push(i);
    timer.stop();
    writeln("Queue was initialized to a size of ", InitialQueueSize, " in ", timer.elapsed());
    timer.clear();

    timer.start();
    coforall tid in 1..here.maxTaskPar {
      for i in 1..OperationsPerThread do ep.push(i);
    }
    timer.stop();
    writeln("Performed ", OperationsPerThread, " operations per task with ", here.maxTaskPar, " tasks for a total of ", here.maxTaskPar * OperationsPerThread, " operations in a total of ", timer.elapsed(), "s");
  }
}
