module flow.core.aspects.stdio;

private import core.time : Duration, msecs;
private import flow.core;

class StdioAspect : Data { mixin _data;
    private import core.sync.mutex : Mutex;
    private import core.thread : Thread;

    private Mutex todoOutLock, todoInLock, doneOutLock, doneInLock;

    private bool canWork;
    private Thread worker;

    @field Duration inactiveSleep;
    @field Duration pollDelay;

    @field OutJob[] todoOutQueue;
    @field InJob[] todoInQueue;
    @field InJob[] doneInQueue;
}

class OutJob : Data { mixin _data;
    @field Signal trigger;
    @field string msg;
}

class InJob : Data { mixin _data;
    @field Signal trigger;
    @field string msg;
    @field string input;
}

void pushTodo(T)(T j, StdioAspect a) if(is(T == OutJob) || is(T == InJob)) {
    synchronized(is(T == OutJob) ? a.todoOutLock : a.todoInLock)
        static if(is(T == OutJob)) a.todoOutQueue ~= j;
        else a.todoInQueue ~= j;
}

void pushDone(T)(T j, StdioAspect a) if(is(T == InJob)) {
    synchronized(a.todoInLock)
        a.todoInQueue ~= j;
}

T popTodo(T)(StdioAspect a) if(is(T == OutJob) || is(T == InJob)) {
    import std.range : empty, front, popFront;

    T j;
    synchronized(is(T == OutJob) ? a.todoOutLock : a.todoInLock)
        if(!(is(T == OutJob) ? a.todoOutQueue.empty : a.todoInQueue.empty)) {
            static if(is(T == OutJob)) {
                j = a.todoOutQueue.front;
                a.todoOutQueue.popFront;
            } else {
                j = a.todoInQueue.front;
                a.todoInQueue.popFront;
            }
        }
    return j;
}

T popDone(T)(StdioAspect a) if(is(T == InJob)) {
    import std.range : empty, front, popFront;

    T j;
    synchronized(a.doneInLock)
        if(!a.doneInQueue.empty) {
            j = a.doneInQueue.front;
            a.doneInQueue.popFront;
        }
    return j;
}

private bool work(T)(StdioAspect a) if(is(T == OutJob) || is(T == InJob)) {
    import std.stdio : writeln, write, readln;

    auto any = false;
    T j;
    do {
        j = popTodo!T(a);

        if(j !is null) {
            any = true;

            if(j.msg != string.init)
                writeln(">> ", j.msg);

            static if(is(T == InJob)) {
                write("<< ");
                j.input = readln;
                pushDone(j, a);
            }
        }
    } while(j !is null);

    return any;
}

private void worker(StdioAspect a) {
    import core.thread : Thread;

    while(a.canWork)
        // if none of both done anything, sleep a bit
        if(!work!OutJob(a) && !work!InJob(a))
            Thread.sleep(a.inactiveSleep);

    a.worker = null;
}

class UpTick : Tick {
    override void run() {
        import core.sync.mutex : Mutex;
        import core.thread : Thread;

        auto a = this.aspect!StdioAspect;
        a.todoOutLock = new Mutex; a.todoInLock = new Mutex;
        a.doneOutLock = new Mutex; a.doneInLock = new Mutex;
        a.canWork = true;
        a.worker = new Thread({worker(a);});

        // start up poller
        this.invoke(fqn!DonePoll);
    }
}

class DownTick : Tick {
    override void run() {
        auto a = this.aspect!StdioAspect;
        a.canWork = false;

        // wait for io thread to end
        a.worker.join();
    }
}

class OutReq : Unicast { mixin _unicast;
    @field string msg;
}

class AnyOutReq : Anycast { mixin _anycast;
    @field string msg;
}

class MultiOutReq : Multicast { mixin _multicast;
    @field string msg;
}

class InReq : Unicast { mixin _unicast;
    @field string msg;
}

class AnyInReq : Anycast { mixin _anycast;
    @field string msg;
}

class MultiInReq : Multicast { mixin _multicast;
    @field string msg;
}

class EnqueueJob : Tick {
    override void run() {
        auto a = this.aspect!StdioAspect;
        auto t = this.trigger;

        if(t.as!OutReq !is null || t.as!AnyOutReq !is null || t.as!MultiOutReq !is null) {
            auto j = new OutJob;
            j.trigger = t;

            if(t.as!OutReq !is null) j.msg = t.as!OutReq.msg;
            else if(t.as!AnyOutReq !is null) j.msg = t.as!AnyOutReq.msg;
            else if(t.as!MultiOutReq !is null) j.msg = t.as!MultiOutReq.msg;

            pushTodo(j, a);
        } else if(t.as!InReq !is null || t.as!AnyInReq !is null || t.as!MultiInReq !is null) {
            auto j = new InJob;
            j.trigger = t;

            if(t.as!InReq !is null) j.msg = t.as!InReq.msg;
            else if(t.as!AnyInReq !is null) j.msg = t.as!AnyInReq.msg;
            else if(t.as!MultiInReq !is null) j.msg = t.as!MultiInReq.msg;
            
            pushTodo(j, a);
        }
    }
}

class InResponse : Unicast { mixin _unicast;
    @field Signal trigger;
    @field string input;
}

InResponse popResponse(T)(StdioAspect a) if(is(T == InJob)) {
    static if(is(T == InJob))
        alias R = InResponse;

    auto j = popDone!T(a);
    if(j !is null) {
        auto r = new R;
        r.trigger = j.trigger;
        r.input = j.input;
        return r;
    } else return null;
}

class DonePoll : Tick {
    override void run() {
        auto a = this.aspect!StdioAspect;

        auto r = popResponse!(InJob)(a);
        if(r !is null) {
            this.send(r, r.trigger.src);
            this.invoke(fqn!DonePoll);
        } else this.invoke(fqn!DonePoll, a.pollDelay);
    }
}

StdioAspect addStdioAspect(EntityMeta em, Duration iS = 10.msecs, Duration pD = 10.msecs) {
    import std.uuid : UUID;
    
    auto a = new StdioAspect; em.aspects ~= a;
    a.inactiveSleep = iS;
    a.pollDelay = pD;
    em.addEvent(EventType.OnTicking, fqn!UpTick);
    em.addEvent(EventType.OnFreezing, fqn!DownTick);
    
    return a;
}