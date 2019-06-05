/*
 * Obtained from https://github.com/LouisJenkinsCS/Chapel-Atomic-Objects/blob/master/LocalAtomics.chpl
 */

module LocalAtomics {
  /*
     Planned usage:
     var head : LocalAtomicObject(unmanaged Node(int));
  // Adding a new node...
  head.write(new unmanaged Node(int)); // Need 'write(objType)'
  */

  extern {
    #include <stdint.h>
    #include <stdio.h>
    #include <stdlib.h>

    struct uint128 {
      uint64_t lo;
      uint64_t hi;
    };

    typedef struct uint128 uint128_t;
    static inline int cas128bit(void *srcvp, void *cmpvp, void *withvp) {
      uint128_t __attribute__ ((aligned (16))) cmp_val = * (uint128_t *) cmpvp;
      uint128_t __attribute__ ((aligned (16))) with_val = * (uint128_t *) withvp;      
      uint128_t *src = srcvp;
      uint128_t *cmp = &cmp_val;
      uint128_t *with = &with_val;
      char result;

      __asm__ __volatile__ ("lock; cmpxchg16b (%6);"
          "setz %7; "
          : "=a" (cmp->lo),
          "=d" (cmp->hi)
          : "0" (cmp->lo),
          "1" (cmp->hi),
          "b" (with->lo),
          "c" (with->hi),
          "r" (src),
          "m" (result)
          : "cc", "memory");
      *(uint128_t *) cmpvp = cmp_val;
      return result;
    }

    static inline void write128bit(void *srcvp, void *valvp) {
      uint128_t __attribute__ ((aligned (16))) with_val = * (uint128_t *) valvp;
      uint128_t __attribute__ ((aligned (16))) cmp_val = * (uint128_t *) srcvp;
      uint128_t *src = srcvp;
      uint128_t *cmp = &cmp_val;
      uint128_t *with = &with_val;
      char successful = 0;

      while (!successful) {
        __asm__ __volatile__ ("lock; cmpxchg16b (%6);"
            "setz %7; "
            : "=a" (cmp->lo),
            "=d" (cmp->hi)
            : "0" (cmp->lo),
            "1" (cmp->hi),
            "b" (with->lo),
            "c" (with->hi),
            "r" (src),
            "m" (successful)
            : "cc", "memory");
      }
    }

    static inline void read128bit(void *srcvp, void *dstvp) {
      uint128_t __attribute__ ((aligned (16))) src_val = * (uint128_t *) srcvp;
      uint128_t __attribute__ ((aligned (16))) cmp_val = src_val;
      uint128_t __attribute__ ((aligned (16))) with_val = src_val;
      uint128_t *src = srcvp;
      uint128_t *cmp = &cmp_val;
      uint128_t *with = &with_val;
      char result;

      __asm__ __volatile__ ("lock; cmpxchg16b (%6);"
          "setz %7; "
          : "=a" (cmp->lo),
          "=d" (cmp->hi)
          : "0" (cmp->lo),
          "1" (cmp->hi),
          "b" (with->lo),
          "c" (with->hi),
          "r" (src),
          "m" (result)
          : "cc", "memory");

      *(uint128_t *)dstvp = cmp_val;
    }
  }

  extern type atomic_uint_least64_t;
   

  /*
    Wrapper for an object protected by an ABA counter. This type forwards to the object
    represented by its underlying pointer and hence can be used as if it were the object
    itself, via 'forwarding'. This type should not be created by the user, and instead
    should be created by LocalAtomicObject. The object protected by this ABA wrapper can
    be extracted via 'getObject'
  */
  record ABA {
    type objType;
    // Runtime version of atomics so that we can read these without overhead
    var _ABA_ptr : atomic uint(64);
    var _ABA_cnt : atomic uint(64);

    proc init(type objType, ptr : uint(64), cnt : uint(64)) {
      this.objType = objType;
      this.complete();
      this._ABA_ptr.write(ptr);
      this._ABA_cnt.write(cnt);
    }

    proc init(type objType, ptr : uint(64)) {
      this.objType = objType;
      this.complete();
      this._ABA_ptr.write(ptr);
    }

    proc init(type objType) {
      this.objType = objType;
    }

    inline proc getObject() {
      var ptr = this._ABA_ptr;
      return __primitive("cast", objType, this._ABA_ptr.read());
    }
    
    inline proc getABACounter() {
      return this._ABA_cnt.read();
    }
    

    proc readWriteThis(f) {
      f <~> "ptr: " <~> getObject() <~> ", cnt: " <~> getABACounter();
    }

    forwarding getObject();
  }

  record LocalAtomicObject {
    type objType;
    var atomicVar : c_ptr(ABA(objType));

    proc init(type objType) {
      if !isUnmanagedClass(objType) then compilerError("LocalAtomicObject must take a 'unmanaged' type, not ", objType : string);
      this.objType = objType;
      this.complete();
      var ptr : c_void_ptr;
      posix_memalign(c_ptrTo(ptr), 16, c_sizeof(ABA(objType)));
      this.atomicVar = ptr;
      c_memset(atomicVar, 0, c_sizeof(ABA(objType)));
    }

    proc init(type objType, defaultValue : objType) {
      if !isUnmanagedClass(objType) then compilerError("LocalAtomicObject must take a 'unmanaged' type, not ", objType : string);
      this.objType = objType;
      this.complete();
      localityCheck(defaultValue);
      var ptr : c_void_ptr;
      posix_memalign(c_ptrTo(ptr), 16, c_sizeof(ABA(objType)));
      this.atomicVar = ptr;
      c_memset(atomicVar, 0, c_sizeof(ABA(objType)));      
      this.atomicVar[0]._ABA_ptr.write(getAddr(defaultValue));
    }

    inline proc getAddrAndLocality(obj : objType) : (locale, uint(64)) {
      return (obj.locale, getAddr(obj));
    }

    inline proc getAddr(obj : objType) : uint(64) {
      return __primitive("cast", uint(64), __primitive("_wide_get_addr", obj));
    }

    inline proc localityCheck(objs...) {
      if boundsChecking && (|| reduce [obj in objs] obj.locale != this.locale) then
        halt("Locality check failed on ", for obj in objs do getAddrAndLocality(obj), " when expected to be hosted on ", this.locale);
    }

    proc readABA() : ABA(objType) {
      var dest : ABA(objType);
      read128bit(atomicVar, c_ptrTo(dest));
      return dest;
    }

    proc read() : objType {
      return __primitive("cast", objType, atomicVar[0].getObject());
    }

    proc compareExchange(expectedObj : objType, newObj : objType) : bool {
      localityCheck(expectedObj, newObj);
      return atomicVar[0]._ABA_ptr.compareExchange(getAddr(expectedObj), getAddr(newObj));
    }

    proc compareExchangeABA(expectedObj : ABA(objType), newObj : objType) : bool {
      localityCheck(newObj);
      var cmp = expectedObj;
      var val = new ABA(objType, getAddr(newObj), atomicVar[0].getABACounter() + 1);
      return cas128bit(atomicVar, c_ptrTo(cmp), c_ptrTo(val)) : bool;
    }
    
    proc compareExchangeABA(expectedObj : ABA(objType), newObj : ABA(objType)) : bool {
      compareExchangeABA(expectedObj, newObj.getObject());
    }

    proc write(newObj:objType) {
      localityCheck(newObj);
      atomicVar[0]._ABA_ptr.write(getAddr(newObj));
    }

    proc write(newObj:ABA(objType)) {
      write(newObj.getObject());
    }
    
    proc writeABA(newObj: ABA(objType)) {
      write128bit(atomicVar, c_ptrTo(newObj));
    }

    proc writeABA(newObj: objType) {
      writeABA(new ABA(objType, getAddr(objType), atomicVar[0].getABACounter() + 1));
    }

    inline proc exchange(newObj:objType) {
      compilerError("Exchange is not implemented yet!!!");
    }

    // handle wrong types
    inline proc write(newObj) {
      compilerError("Incompatible object type in LocalAtomicObject.write: ",
          newObj.type : string);
    }

    inline proc compareExchange(expectedObj, newObj) {
      compilerError("Incompatible object type in LocalAtomicObject.compareExchange: (",
          expectedObj.type : string, ",", newObj.type : string, ")");
    }

    inline proc exchange(newObj) {
      compilerError("Incompatible object type in LocalAtomicObject.exchange: ",
          newObj.type : string);
    }

    proc readWriteThis(f) {
      f <~> atomicVar[0];
    }
  }

  class C {
    var x : int;
  }
  
  proc main() {
    var x = new unmanaged C(1);
    var atomicObj = new LocalAtomicObject(unmanaged C);
    atomicObj.write(x);
    var y = atomicObj.read();
    writeln(atomicObj.read().type:string);
    writeln(y);
    var z = atomicObj.readABA();
    writeln(z.type : string);
    writeln(z);
    var w = new unmanaged C(2);
    writeln(atomicObj.compareExchange(x, z.getObject()));
    writeln(atomicObj.read());
    writeln(atomicObj.readABA());
    writeln(atomicObj.compareExchangeABA(z, w));
    writeln(atomicObj.read());
    writeln(atomicObj.readABA());
    writeln(atomicObj.compareExchange(w, x));
    writeln(atomicObj.read());
    writeln(atomicObj.readABA());
  }
}