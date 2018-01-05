module flow.service.aspects.process;

private import core.time;
private import core.sync.mutex;
private import flow.core.data;
private import flow.core.gears;
private import flow.core.util;

class ProcessAspect : Data { mixin _data;
    private Mutex todoLock, doneLock;

    @field Duration pollDelay;

    @field Req[] todoQueue;
    @field Rep[] doneQueue;
}

class UnknownRep : Rep { mixin _rep; }

class ShutdownReq : Req { mixin _req; }

class ShutdownRep : Rep { mixin _rep; }

class SpaceLsReq : Req { mixin _req; }

class SpaceAddReq : Req { mixin _req;
    @field string id;
    @field ulong pipes;
    @field SpaceMeta meta;

    @field bool tick;
}

class SpaceTickReq : Req { mixin _req;
    @field string id;
}

class SpaceFreezeReq : Req { mixin _req;
    @field string id;
}

class SpaceDelReq : Req { mixin _req;
    @field string id;
}

private void pushTodo(Req j, ProcessAspect a) {
    synchronized(a.todoLock)
        a.todoQueue ~= j;
}

private void pushDone(Rep j, ProcessAspect a) {
    synchronized(a.doneLock)
        a.doneQueue ~= j;
}

private Req popTodo(ProcessAspect a) {
    import std.range : empty, front, popFront;

    if(a.todoLock !is null) {
        Req j;
        synchronized(a.todoLock)
            if(!a.todoQueue.empty) {
                j = a.todoQueue.front;
                a.todoQueue.popFront;
            }
        return j;
    } else return null;
}

private Rep popDone(ProcessAspect a) {
    import std.range : empty, front, popFront;

    Rep j;
    synchronized(a.doneLock)
        if(!a.doneQueue.empty) {
            j = a.doneQueue.front;
            a.doneQueue.popFront;
        }
    return j;
}

class ShutdownTick : Tick {
    override void run() {
        this.invoke(fqn!SpaceFreezeSystemTick);
    }
}

class TodoTick : Tick {
    override void run() {
        auto a = this.aspect!ProcessAspect;
        auto t = this.trigger.as!Req;

        pushTodo(t, a);
    }
}

class UpTick : Tick {
    override void run() {
        import core.sync.mutex : Mutex;

        auto a = this.aspect!ProcessAspect;
        a.todoLock = new Mutex; a.doneLock = new Mutex;

        // start up poller
        this.invoke(fqn!DonePoll);
    }
}

class DonePoll : Tick {
    override void run() {
        auto a = this.aspect!ProcessAspect;

        auto r = popDone(a);
        if(r !is null) {
            this.send(r, r.req.src);
            this.invoke(fqn!DonePoll);
        } else this.invoke(fqn!DonePoll, a.pollDelay);
    }
}

ProcessAspect addProcessAspect(EntityMeta em, Duration pD = 10.msecs) {    
    auto a = new ProcessAspect; em.aspects ~= a;
    a.pollDelay = pD;
    em.addEvent(EventType.OnTicking, fqn!UpTick);
    em.addReceptor(fqn!ShutdownReq, fqn!ShutdownTick, true);
    em.addReceptor(fqn!SpaceLsReq, fqn!TodoTick);
    em.addReceptor(fqn!SpaceAddReq, fqn!TodoTick);
    em.addReceptor(fqn!SpaceTickReq, fqn!TodoTick);
    em.addReceptor(fqn!SpaceFreezeReq, fqn!TodoTick);
    em.addReceptor(fqn!SpaceDelReq, fqn!TodoTick);

    return a;
}

private bool shouldShutdown;

void control(Process proc, JunctionMeta[] junc, string id = "process", string name = "control", Duration pD = 10.msecs) {
    import core.thread : Thread;

    auto sm = createSpace(id);
    sm.junctions ~= junc;
    auto em = sm.addEntity(name);
    auto a = em.addProcessAspect(pD);

    auto spc = proc.add(sm);
    spc.tick();

    while(spc.state == SystemState.Ticking) {
        auto todo = popTodo(a);
        if(todo !is null)
            pushDone(handle(todo), a);
        else if(shouldShutdown)
            spc.freeze();
        else
            Thread.sleep(pD);
    }
}

void shutdown() {
    Log.msg(LL.Message, "shutting down");
    shouldShutdown = true;
}

private Rep handle(Req s) {
    switch(s.dataType) {
        case fqn!ShutdownReq:
            shutdown();
            return new ShutdownRep(s);
        default:
            return new UnknownRep(s);
    }
}

class ControlAspect : Data { mixin _data;
    @field long timeout;
    @field string space;
    @field string entity;
    @field Req request;
    @field Rep reply;
}

class RequestTick : Tick {
    override void run() {
        import core.thread : Thread;
        import std.datetime.systime : Clock;

        auto a = this.aspect!ControlAspect;
        
        auto time = Clock.currStdTime;
        bool ret;
        do {
            ret = this.send(a.request, a.entity, a.space);
            if(!ret && time + a.timeout >= Clock.currStdTime)
                Thread.sleep(10.msecs);
        } while(!ret && time + a.timeout >= Clock.currStdTime);

        if(!ret)
            Log.msg(LL.Error, "timed out trying to contact flow service controller");

        // when shutting down it'll never answer so don't wait
        if(!ret || a.request.as!ShutdownReq !is null)
            this.invoke(fqn!SpaceFreezeSystemTick);
    }
}

class ReqponseTick : Tick {
    override void run() {
        auto a = this.aspect!ControlAspect;
        auto t = this.trigger.as!Rep;

        a.reply = t;
        this.invoke(fqn!SpaceFreezeSystemTick);
    }
}

ControlAspect addControlAspect(EntityMeta em, Req req, string id, string name) {
    import core.time : seconds;

    auto a = new ControlAspect; em.aspects ~= a;
    a.timeout = 120.seconds.total!"hnsecs";
    a.space = id;
    a.entity = name;
    a.request = req;
    em.addEvent(EventType.OnTicking, fqn!RequestTick, true);
    em.addReceptor(fqn!UnknownRep, fqn!ReqponseTick, true);
    em.addReceptor(fqn!ShutdownRep, fqn!ReqponseTick, true);

    return a;
}

Rep request(Req req, JunctionMeta junc, string id = "process", string name = "control") {
    import core.thread : Thread;
    import std.conv : to;
    import std.uuid : randomUUID;

    auto proc = new Process;
    auto sm = createSpace(randomUUID.to!string~"."~id);
    sm.junctions ~= junc;
    auto em = sm.addEntity(name);
    auto a = em.addControlAspect(req, id, name);

    auto spc = proc.add(sm);
    spc.tick();
    
    while(spc.state == SystemState.Ticking)
        Thread.sleep(10.msecs);

    proc.dispose();

    return a.reply;
}