module LockFreeStack {

  use LocalAtomics;

  class LockFreeStack {
    type objType;
    var _top : LocalAtomicObject(objType);

    proc init(type objType) {
      this.objType = objType;
    }

    proc push(newObj : objType) {
      do {
        var oldTop = _top.readABA();
        newObj.next = oldTop.getObject();
      } while (!_top.compareExchangeABA(oldTop, newObj));
    }

    proc pop() : objType {
      var oldTop : ABA(objType);
      do {
        oldTop = _top.readABA();
        if (oldTop.getObject() == nil) then
          return nil;
        var newTop = oldTop.next;
      } while (!_top.compareExchangeABA(oldTop, newTop));
      return oldTop.getObject();
    }

    proc top() : objType {
      return _top.read();
    }

    proc deinit() {
      var head = top();
      while (head != nil) {
        var next = head.next;
        delete head;
        head = next;
      }
    }
  }

  class node {
    var val : int;
    var next : unmanaged node;

    proc init(val : int) {
      this.val = val;
      next = nil;
    }
  }
}
