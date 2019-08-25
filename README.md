# Epoch Based Memory Reclamation System

This repository hosts the Epoch Based Memory Reclamation System for the Chapel programming language. We present 1) `AtomicObjects`, a user-facing abstraction for performing atomics on arbitrary `unmanaged` objects, including objects which happen to be remote; 2) `LocalEpochManager` and `EpochManager`, a scalable shared-memory and distributed-memory implementation of epoch-based reclamation that enable concurrent-safe memory reclamation of objects arbitrary `unmanaged` objects; 3) `LockFreeQueue`, a shared-memory implementation of [Michael and Scott's Queue](https://apps.dtic.mil/docs/citations/ADA309412) using the `LocalEpochManager` which demonstrates its usage and acts as its own stand-alone data structure contribution; 4) `LockFreeStack`, a shared-memory implementation of Treiber Stack using the `LocalEpochManager`.

Documentation can be seen [here](https://dgarvit.github.io/Epoch-Manager/).

## GSoC Information

This project was made possible through the Google Summer of Code program, which allowed me the opportunity to develop new solutions in the area of distributed computing (PGAS in particular). I would also like to thank my mentors, Louis Jenkins ([**@LouisJenkinsCS**](https://github.com/LouisJenkinsCS)) and Michael Ferguson ([**@mppf**](https://github.com/mppf)). Finally, I would like to thank the Chapel project and Cray for providing me this learning opportunity and providing me access to Cray-XC50 cluster, which allowed us to benchmark the project.

## Issues, Pull Request and Discussion

Discussions can be seen [here](https://github.com/chapel-lang/chapel/issues/13690).
Pull Request can be found [here](https://github.com/chapel-lang/chapel/pull/13708).

I would like to mention a bug we discovered in chapel while working on the project, which is a bug in Forward Cycle Detection and Serial Loops. When `forwarding`, it seems that the compiler will detect a cycle when there is none. This only occurs in a serial loop (hence `for` not `forall`); as well, even more strangely, is that it only appears if you invoke two methods (or more) on the object being forwarded to. The bug however was non-critical for the project. [Link](https://github.com/chapel-lang/chapel/issues/13651).

### AtomicObjects

The `AtomicObjects` module is a tested package that provides the ability to perform atomic operations on arbitrary `unmanaged` objects. To circumvent the infamous ABA problem, we provide an `ABA` wrapper that contains both the object as well as an ABA counter; all atomic operations on an `ABA` counter is performed via Intel's `CMPXCHG16B` assembly  instruction. This is used to implement the `LocalEpochManager` and the distributed `EpochManager`.

### Epoch Manager

Epoch-Based Memory Reclamation, when decoupled with Read-Copy-Update, is a very powerful and the current state-of-the-art in research literature data structures, and is comparable to [other](https://www.sciencedirect.com/science/article/pii/S074373150700069X) styles of memory reclamation. Epoch-based memory reclamation offers the ability to both denote lifetimes via 'epochs', in which unlike hazard pointers or `shared` atomic reference counting, it is not restricted to controlling the lifetime of a single object at a time.

An epoch manager is intended to be restricted to a specific data structure, for example a non-blocking data structure. We offer both a shared-memory optimized variant, `LocalEpochManager`, as well as a global-view distributed variant `EpochManager` that makes use of privatization.

### LockFreeQueue

`LockFreeQueue` is an implementation of Michael & Scott's Queue in Chapel that makes use of the `LocalEpochManager` internally. To show the performance benefits of the `EpochManaged`, we present a small table that shows performance comparisons to the the "Epoch Managed MS-Queue", what is being presented here as a contribution; to the 'Two-Lock' variant of the Michael & Scott Queue that uses Test-And-Set loop and one which uses a Test-And-Test-And-Set loop, both being variants of spinlocks, and finally one recycling memory and using the `ABA` wrapper introduced in `AtomicObjects` module. 

Test          | Time
------------- | ------
Epoch Managed MS-Queue | 37.7992s
Two-Lock (TATAS) MS-Queue | 69.8408s
Two-Lock (TAS)  MS-Queue    | 148.661s
Recycled (ABA) MS-Queue     | 154.375s

The module will automatically try to reclaim after every so often, but also exposes the ability to explicit trigger a 'garbage collection' and forward the epoch.
