## The Most Critical Problem: Mailbox Data Race

From the spec, section **5.5.8 Mailbox** — this is the single most dangerous unsolved problem in the entire design.

---

### The Race

```zig
// deliver() — called from dist receiver task (potentially different OS thread)
pub fn deliver(self: *Mailbox, msg: Term) !void {
    try self.queue.writeItem(msg);  // ← writes to shared queue
    self.event.set();
}

// receive() — called from actor task
pub fn receive(self: *Mailbox, io: std.Io) !Term {
    while (self.queue.count == 0) {  // ← reads shared queue
        try self.event.wait(io);
        self.event.reset();
    }
    return self.queue.readItem().?;  // ← reads shared queue
}
```

`std.fifo.LinearFifo` has **zero thread-safety guarantees**. When `std.Io.Threaded` backend is used, `deliver()` and `receive()` can run on different OS threads simultaneously — this is an **undefined behavior data race**, not just a logic bug.

---

### Why It's Subtle

Under `std.Io` single-threaded evented backend — the race is **invisible**. Tasks are cooperative, so `deliver()` and `receive()` never truly interleave. Every test in section 16 will pass. It only explodes when the caller passes a threaded `Io` backend.

The spec even says in 5.5.2:

> _"The caller decides the execution backend. zbeam itself is backend-agnostic."_

But the Mailbox implementation **silently assumes** cooperative single-threaded execution. That contract is nowhere enforced.

---

### Secondary Race: Lost Wakeup on `reset()`

```
Timeline:
1. actor:    queue.count == 0 → TRUE, enters while
2. receiver: writeItem(msg1) → event.set()
3. receiver: writeItem(msg2) → event.set()  ← no-op, already set
4. actor:    event.wait(io)  → returns immediately
5. actor:    event.reset()   ← CLEARS the event
6. receiver: writeItem(msg3) → event.set()  ← fine, sets again
                                              BUT:
7. actor:    queue.count == 3 → exits while, reads msg1
8. actor:    calls receive() again
9. actor:    queue.count == 2 → exits while, reads msg2
10. actor:   calls receive() again
11. actor:   queue.count == 1 → exits while, reads msg3 ✓
```

This scenario is safe. But under concurrent access, step 5 (`reset()`) racing with step 6 (`set()`) on a non-atomic event creates undefined ordering.

---

### The Fix

```zig
pub const Mailbox = struct {
    queue: std.fifo.LinearFifo(Term, .Dynamic),
    event: std.Io.Event,
    mutex: std.Thread.Mutex,  // ADD THIS

    pub fn deliver(self: *Mailbox, msg: Term) !void {
        self.mutex.lock();
        try self.queue.writeItem(msg);
        self.mutex.unlock();
        self.event.set();  // set AFTER unlock — event signals, not guards data
    }

    pub fn receive(self: *Mailbox, io: std.Io) !Term {
        while (true) {
            self.mutex.lock();
            if (self.queue.count > 0) {
                const msg = self.queue.readItem().?;
                self.mutex.unlock();
                return msg;
            }
            self.mutex.unlock();
            // wait OUTSIDE the lock — avoids deadlock with deliver()
            try self.event.wait(io);
            self.event.reset();
        }
    }
};
```

---

### Why This Problem Over All Others

The spec has other real issues — `expireStale` on the `FragmentReassembler` is a skeleton with no implementation (memory leak on dropped connections), `unregisterPid` in Registry is O(n) scan on every actor exit, and `AtomTable` has a global mutex on every intern — but none of those cause **silent undefined behavior**. They're performance or correctness bugs. The mailbox race causes **memory corruption** in a valid, documented usage pattern that the spec explicitly allows.

# Fix

Your analysis is correct, and the fix is sound. One thing worth calling out explicitly though — your fix silently inherits an assumption that `std.Io.Event.set()` is itself atomic across OS threads. That assumption is almost certainly true (it'd be a broken primitive otherwise), but the spec never states it, and your fix's correctness depends on it.

The other thing worth noting: your `event.reset()` placement is correct but for a non-obvious reason. You reset *after* `event.wait()` returns, *outside* the lock. This means there's a window:

```
actor:    mutex.unlock()
actor:    event.wait(io) → returns (event was set)
deliver:  writeItem(msg_B) → event.set()   ← fires in the window
actor:    event.reset()                     ← clears the event deliver just set
actor:    mutex.lock() → queue.count == 2 → reads msg_A, returns
```

Msg_B is still in the queue, but the event is now cleared. Next `receive()` call: locks, finds `count == 1`, reads msg_B directly — never hits `event.wait()`. Safe, because the `while(true)` + lock-then-check loop drains the queue without requiring the event to fire again.

This is the correct pattern exactly because you check queue state *under the lock* before waiting, not after. The event is a wakeup hint, not a count.

The fixed struct with that explicit comment:

```zig
pub const Mailbox = struct {
    queue: std.fifo.LinearFifo(Term, .Dynamic),
    // std.Io.Event.set() MUST be safe to call from any OS thread.
    // This holds for all std.Io backends in Zig 0.16 — it is load-bearing.
    event: std.Io.Event,
    mutex: std.Thread.Mutex,

    pub fn deliver(self: *Mailbox, msg: Term) !void {
        self.mutex.lock();
        try self.queue.writeItem(msg);
        self.mutex.unlock();
        // set() fires AFTER unlock intentionally —
        // event signals presence, mutex guards the data.
        // Reversing this order would allow receive() to wake,
        // lock, find count==0, and go back to sleep — a lost wakeup.
        self.event.set();
    }

    pub fn receive(self: *Mailbox, io: std.Io) !Term {
        while (true) {
            self.mutex.lock();
            if (self.queue.count > 0) {
                const msg = self.queue.readItem().?;
                self.mutex.unlock();
                return msg;
            }
            self.mutex.unlock();

            // Wait outside the lock — holding mutex here would deadlock
            // with deliver(), which locks before set().
            // Spurious wakeups are safe: the while(true) + lock-then-check
            // handles them without requiring the event to be an exact count.
            try self.event.wait(io);
            self.event.reset();
        }
    }
};
```

Your secondary point about `expireStale` being a skeleton is the next real correctness issue after this one — a connection that dies mid-reassembly leaks every in-flight `Assembly` buffer indefinitely. But you're right that it's a resource leak, not UB. The mailbox race is the only one that corrupts memory in a documented, explicitly-supported usage pattern.