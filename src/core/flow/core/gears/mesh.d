module flow.core.gears.mesh;

private import core.thread;
private import flow.core.data;
private import flow.core.gears.data;
private import flow.core.gears.engine;
private import flow.core.util;
private import std.array;
private import std.string;
private import std.uuid;

immutable IDLENGTH = 16;

enum MsgCode : ubyte {
    Ack = 0,
    Cfrm = 1,
    Ping = 2,
    Info = 3,
    SignOff = 4,
    Verify = ubyte.max-1,
    Signal = ubyte.max
}

struct InfoData {
    string space;
    string addr;
    ubyte[] info;
    ubyte[] auth;
}

struct MsgData {
    import msgpack : nonPacked;
    @nonPacked shared static ulong lastId;

    @nonPacked static ulong getNewId() {
        import core.atomic : atomicOp;
        return atomicOp!"+="(lastId, 1);
    }

    @nonPacked Throwable error;

    ubyte[IDLENGTH] dst;
    ubyte[IDLENGTH] src;
    MsgCode code;
    ulong id;
    ubyte[] data;

    this(ubyte[] t, ubyte[] s, MsgCode c, ulong i = getNewId, ubyte[] d = null) {
        dst = t;
        src = s;
        code = c;
        id = i;
        data = d;
    }
}

private class MeshChannel : Channel {
    private import core.sync.mutex : Mutex;
    ubyte[IDLENGTH] id;
    private ubyte[] _auth;

    private ubyte[] info;
    private bool passive;
    
    Mutex cfrmLock;
    bool[ulong] awaitCfrm;
    bool[ulong] cfrms;

    override @property MeshJunction own() {
        return super.own.as!MeshJunction;
    }
    
    override @property MeshJunctionInfo other() {
        return super.other.as!MeshJunctionInfo;
    }

    override @property ubyte[] auth() {return this._auth;}

    this(string dst, MeshJunction own, ubyte[] info, ubyte[] auth) {
        import std.digest.md : md5Of;

        this.cfrmLock = new Mutex;
        this.id[0..IDLENGTH] = dst.md5Of.dup;
        this._auth = auth;
        this.info = info;

        super(dst, own);
    }

    override protected void dispose() {
        while(this.awaitCfrm.length > 0)
            Thread.sleep(5.msecs);
    }
    
    override protected bool reqVerify() {
        import std.conv : to;
        
        auto msgId = MsgData.getNewId;
        debug Log.msg(LL.Debug, this.logPrefix~"request verification("~msgId.to!string~")");
        return this.own.confirmedSend(MsgData(this.id, this.own.id,
            MsgCode.Verify, msgId), this);
    }

    override protected bool transport(ref ubyte[] pkg) {
        import std.conv : to;

        auto msgId = MsgData.getNewId;
        debug Log.msg(LL.Debug, this.logPrefix~"transport("~msgId.to!string~")");
        return this.own.confirmedSend(MsgData(this.id, this.own.id, 
            MsgCode.Signal, msgId, pkg), this);
    }
}

abstract class MeshConnector {
    private MeshJunction _junction;
    @property ubyte[IDLENGTH] sysId() {return this._junction.sysId;}
    @property ubyte[IDLENGTH] id() {return this._junction.id;}
    @property MeshConnectorMeta meta() {return this._junction.meta.conn;}
    @property string addr() {return this._junction.meta.info.as!MeshJunctionInfo.addr;}

    protected abstract @property ubyte[] info();

    this() {}

    protected abstract bool create();

    protected void dispose() {
        this.destroy;
    }

    protected abstract bool listen();
    protected abstract void unlisten();

    protected abstract bool connect(string addr);

    protected abstract bool send(MsgData msg);

    protected abstract void add(ubyte[IDLENGTH] dst, ubyte[] info);
    protected abstract void remove(ubyte[IDLENGTH] dst);

    protected void proc(MsgData msg) {this._junction.proc(msg);}
}

private class MeshJunction : Junction {
    private import core.sync.mutex : Mutex;
    private import core.sync.rwmutex : ReadWriteMutex;
    
    private ubyte[IDLENGTH] sysId;
    private ubyte[IDLENGTH] id;

    private Mutex ackLock;
    private bool[ulong] awaitAck;
    private bool[ulong] acks;

    private ReadWriteMutex cLock;
    private MeshChannel[ubyte[IDLENGTH]] channels;

    private MeshConnector conn;

    override @property MeshJunctionMeta meta() {
        return super.meta.as!MeshJunctionMeta;
    }

    override @property string[] list() {
        import std.array : array;
        import std.algorithm.iteration : map;
        synchronized(this.cLock.reader)
            return this.channels.values.map!((c)=>c.dst).array;
    }

    /// ctor
    this() {
        this.ackLock = new Mutex;
        this.cLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        super();
    }

    private bool connect() {
        import std.algorithm.mutation : remove;
        import std.conv : to;
        import std.digest : toHexString;

        try {

            // ensure an acInterval to avoid sleep(0)
            if(this.meta.ackInterval < 1)
                this.meta.ackInterval = 1;

            // connect to others
            ulong[] failed;
            foreach(i, k; this.meta.known)
                if(!this.conn.connect(k))
                    failed ~= i;
            
            // remove failed ones (they get added again as soon as they connect)
            foreach_reverse(f; failed)
                this.meta.known = this.meta.known.remove(f);

            Log.msg(LL.Message, this.logPrefix~this.meta.info.space~" connected to mesh as "~this.id.toHexString.to!string);

            // ping
            this.sendPing();
            
            return true;
        } catch(Throwable thr) {
            debug Log.msg(LL.Error, this.logPrefix~"connecting to mesh failed", thr);
            return false;
        }
    }

    private void contact(string addr) {
        import std.algorithm.searching : any;
        // if not already known connect to node and add if successful
        if(!this.meta.known.any!((k)=>k==addr))
            if(this.conn.connect(addr))
                this.meta.known ~= addr;
    }

    private void sendAck(MsgData msg) {
        this.conn.send(MsgData(msg.src, this.id,
            MsgCode.Ack,
            msg.id));
    }

    private void sendCfrm(MsgData msg, bool accepted, MeshChannel c) {
        import std.conv : to;
        debug {
            if(accepted)
                Log.msg(LL.Debug, this.logPrefix~"accepting("~msg.id.to!string~")");
            else
                Log.msg(LL.Debug, this.logPrefix~"refusing("~msg.id.to!string~")");
        }
        this.ensuredSend(MsgData(msg.src, this.id, MsgCode.Cfrm, msg.id,
            [accepted ? 1 : 0]));
    }

    private void sendPing() {
        import msgpack : pack;
        auto addr = this.meta.info.as!MeshJunctionInfo.addr;
        this.conn.send(MsgData(this.sysId, this.id, MsgCode.Ping, MsgData.getNewId, addr.pack));
    }

    private void sendInfo(ubyte[IDLENGTH] dst, ulong id = MsgData.getNewId) {
        import msgpack : pack;
        InfoData d;
        d.space = this.meta.info.space;
        d.addr = this.meta.info.as!MeshJunctionInfo.addr;
        d.info = this.conn.info;
        d.auth = this.auth;
        this.ensuredSend(MsgData(dst, this.id, MsgCode.Info, id, d.pack));
    }

    private bool ensuredSend(MsgData msg) {
        import core.time : msecs;
        import std.conv : to;
        import std.datetime.systime : Clock;

        /*auto timeout = this.meta.as!MeshJunctionMeta.ackTimeout;
        if(timeout > 0) {
            synchronized(this.ackLock)
                this.awaitAck[msg.id] = true;
            scope(exit)
                this.awaitAck.remove(msg.id);

            auto interval = this.meta.as!MeshJunctionMeta.ackInterval;
            auto time = Clock.currStdTime;
            while(msg.id !in this.acks && time + timeout.msecs.total!"hnsecs" > Clock.currStdTime) {
                this.conn.send(msg);
                Thread.sleep(interval.msecs);
            }
            
            debug Log.msg(LL.Debug, this.logPrefix~"waited "~(Clock.currStdTime-time).to!string~" hnsecs for ack("~msg.id.to!string~")");

            synchronized(this.ackLock)
                if(msg.id in this.acks) {
                    scope(exit) this.acks.remove(msg.id);
                    return this.acks[msg.id];
                } else return false;
        } else*/
            return this.conn.send(msg);
    }

    private bool confirmedSend(MsgData msg, MeshChannel c) {
        import core.time : msecs;
        import std.conv : to;
        import std.datetime.systime : Clock;

        if(!this.meta.info.indifferent) {
            // channel should persist until answer came or timeout
            synchronized(this.cLock.reader) {
                synchronized(c.cfrmLock)
                    c.awaitCfrm[msg.id] = true;
                scope(exit)
                    c.awaitCfrm.remove(msg.id);
                
                auto timeout = this.meta.as!MeshJunctionMeta.timeout;
                auto time = Clock.currStdTime;
                if(!this.ensuredSend(msg)) return false;
                
                while(msg.id !in c.cfrms && time + timeout.msecs.total!"hnsecs" > Clock.currStdTime)
                    Thread.sleep(5.msecs);
                
                debug Log.msg(LL.Debug, c.logPrefix~"waited "~(Clock.currStdTime-time).to!string~" hnsecs for answer("~msg.id.to!string~")");

                synchronized(c.cfrmLock)
                    if(msg.id in c.cfrms) {
                        scope(exit) c.cfrms.remove(msg.id);
                        return c.cfrms[msg.id];
                    } else return false;
            }
        } else
            return this.ensuredSend(msg);
    }

    private void proc(MsgData msg) {
        import std.conv : to;
        // process signal only if its for me
        if(msg.dst == this.sysId || msg.dst == this.id) {
            try {
                switch(msg.code) {
                    case MsgCode.Ack:
                    this.onAck(msg);
                        break;
                    case MsgCode.Ping:
                        this.onPing(msg);
                        break;
                    case MsgCode.Info:
                        this.onInfo(msg);
                        break;
                    case MsgCode.SignOff:
                        this.onSignOff(msg);
                        break;
                    case MsgCode.Verify:
                        this.onVerify(msg);
                        break;
                    case MsgCode.Signal:
                        this.onSignal(msg);
                        break;
                    case MsgCode.Cfrm:
                        this.onCfrm(msg);
                        break;
                    default:
                        this.onDefault(msg);
                        break;
                }
            } catch(Throwable thr) {
                Log.msg(LL.Error, this.logPrefix~"processing message", thr);
            }
        }
    }

    private void onAck(MsgData msg) {
        import std.conv : to;

        debug Log.msg(LL.Debug, this.logPrefix~"ack("~msg.id.to!string~") ");
            synchronized(this.ackLock) if(msg.id in this.awaitAck)
                this.acks[msg.id] = true;
    }

    private void onPing(MsgData msg) {
        import msgpack : unpack;
        import std.conv : to;
        import std.digest : toHexString;

        debug Log.msg(LL.Debug, this.logPrefix~"ping("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
        
        auto addr = msg.data.unpack!string;
        this.contact(addr);
        
        synchronized(this.cLock.reader)
            this.sendInfo(msg.src, msg.id);
    }

    private void onInfo(MsgData msg) {
        import msgpack : unpack;
        import std.conv : to;
        import std.digest : toHexString;
        
        auto src = msg.src;
        this.sendAck(msg); // send an ack

        // if there is no channel to this junction, create one
        auto d = msg.data.unpack!InfoData;
        synchronized(this.cLock.writer)
            if(msg.src !in this.channels) {
                this.contact(d.addr);
                debug Log.msg(LL.Debug, this.logPrefix~"info("~msg.id.to!string~") from "~d.space~" known as "~msg.src.toHexString.to!string);
                auto c = new MeshChannel(d.space, this, d.info, d.auth);
                this.register(c);
                this.sendInfo(msg.src, msg.id);
            }
    }

    /// if a node signs off deregister its channel
    private void onSignOff(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;
        
        debug Log.msg(LL.Debug, this.logPrefix~"signoff("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
        synchronized(this.cLock.writer)
            if(msg.src in this.channels)
                this.unregister(this.channels[msg.src]);
    }

    private void onVerify(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;
        
        this.sendAck(msg); // send an ack
        
        debug Log.msg(LL.Debug, this.logPrefix~"verify("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
        auto r = false; MeshChannel c;
        synchronized(this.cLock.reader) {
            if(msg.src in this.channels) {
                c = this.channels[msg.src];
                r = c.verify();
            }
        
            this.sendCfrm(msg, r, c);
        }
    }

    private void onSignal(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;
        
        this.sendAck(msg); // send an ack

        debug Log.msg(LL.Debug, this.logPrefix~"signal("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
        
        auto r = false; ubyte[] dst; MeshChannel c;
        synchronized(this.cLock.reader) {
            if(msg.src in this.channels) {
                debug Log.msg(LL.Debug, this.logPrefix~"channel found for pull("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
                c = this.channels[msg.src];
                r = c.pull(msg.data);
            } else
                debug Log.msg(LL.Debug, this.logPrefix~"channel not found for pull("~msg.id.to!string~") from "~msg.src.toHexString.to!string);

            this.sendCfrm(msg, r, c);
        }
    }

    private void onCfrm(MsgData msg) {
        import std.conv : to;

        this.sendAck(msg); // send an ack

        bool answer = msg.data[0] == 1;

        synchronized(this.cLock.reader) {
            debug Log.msg(LL.Debug, this.logPrefix~(answer ? "accepted" : "refused")~"("~msg.id.to!string~") ");
            if(msg.src in this.channels)
                synchronized(this.channels[msg.src].cfrmLock) if(msg.id in this.channels[msg.src].awaitCfrm)
                    this.channels[msg.src].cfrms[msg.id] = answer;
        }
    }

    private void onDefault(MsgData msg) {
        Log.msg(LL.Error, this.logPrefix~"unknown message received");
    }

    /// registers a channel passing junction
    private void register(MeshChannel c) {        
        this.conn.add(c.id, c.info);
        this.channels[c.id] = c;
    }
    
    /// unregister a channel passing junction
    private void unregister(MeshChannel c) {
        import core.memory : GC;

        this.channels.remove(c.id);
        this.conn.remove(c.id);
        c.dispose(); GC.free(&c);
    }

    override bool up() {
        import core.memory : GC;
        import std.conv : to;
        import std.digest : toHexString;
        import std.digest.md : md5Of;

        //this.sysId[0..IDLENGTH] = "".bin.md5Of.dup;
        this.id[0..IDLENGTH] = this.meta.info.space.md5Of.dup;
        this.conn = Object.factory(this.meta.conn.type).as!MeshConnector;
        if(this.conn !is null) {
            this.conn._junction = this;
            bool r = false;
            try {r = this.conn.create() && this.conn.listen() && this.connect();}
            catch(Throwable thr) {Log.msg(LL.Message, this.logPrefix~"connecting failed", thr);}
            if(r) {
                return true;
            } else {
                try {
                    this.conn.dispose(); GC.free(&this.conn);
                } catch(Throwable) {}
                this.conn = null;
            }
        }
            
        return false;
    }

    override void down() {
        import core.memory : GC;

        // unregister channels
        synchronized(this.cLock.writer)
            foreach(s, c; this.channels)
                this.unregister(c);

        try {
            this.conn.unlisten();

            // sign off first
            this.conn.send(MsgData(this.sysId, this.id,
                MsgCode.SignOff, MsgData.getNewId));
        
            this.conn.dispose(); GC.free(&this.conn);
            this.conn = null;
        }
        catch(Throwable thr) {
            Log.msg(LL.Message, this.logPrefix~"disconnecting failed");
        }
    }

    override Channel get(string dst) {
        import std.digest.md : md5Of;

        ubyte[IDLENGTH] dstId;
        dstId[0..IDLENGTH] = dst.md5Of.dup;
        synchronized(this.cLock.reader)
            if(dstId in this.channels)
                return this.channels[dstId];
        
        return null;
    }
}

class InProcessConnector : MeshConnector {
    private import core.sync.mutex : Mutex;
    private import core.sync.rwmutex : ReadWriteMutex;

    private __gshared static ReadWriteMutex lock;
    private __gshared static InProcessConnector[ubyte[IDLENGTH]][string] pool;
    private __gshared static MsgData[][ubyte[IDLENGTH]][string] queues;
    private __gshared static Mutex[ubyte[IDLENGTH]][string] queueLocks;

    shared static this() {
        lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    private ReadWriteMutex recvLock;

    private bool canRecv;

    override protected @property ubyte[] info() {return null;}

    /// ctor
    this() {
        this.recvLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        super();
    }
    
    override protected bool create() {return true;}

    protected override void dispose() {
        super.dispose();
    }

    protected override bool listen() {
        import std.conv : to;
        import std.digest : toHexString;

        synchronized(lock.writer) {
            pool[this.addr][this.id] = this;
            queues[this.addr][this.id] = null;
            queueLocks[this.addr][this.id] = new Mutex;
        }

        this.recv();
        return true;
    }

    protected override void unlisten() {
        synchronized(this.recvLock.writer)
            this.canRecv = false;

        synchronized(lock.writer) {
            pool[this.addr].remove(this.id);
            queues[this.addr].remove(this.id);
            queueLocks[this.addr].remove(this.id);
        }
    }

    protected override bool connect(string bus) {        
        return true;
    }

    private Thread recvThread;

    private void recv() {
        this.canRecv = true;

        this.recvThread = new Thread({
            while(this.canRecv && this.recvLock.reader.tryLock()) {
                auto f = (MsgData msg) {
                    scope(exit) 
                        this.recvLock.reader.unlock();
                    this.proc(msg);
                };
                this.recv(f, &this.recvLock.reader.unlock);
            }
        }).start();
    }

    private void recv(void delegate(MsgData) f, void delegate() err) {
        import std.parallelism : taskPool, task;
        import std.range : front, popFront, empty;

        MsgData msg;
        synchronized(lock.reader)
            synchronized(queueLocks[this.addr][this.id]) {
                if(!queues[this.addr][this.id].empty) {
                    msg = queues[this.addr][this.id].front;
                    queues[this.addr][this.id].popFront;
                    
                    if(this.id != msg.src) { // ignore from own
                        taskPool.put(task(f, msg));
                    } else err();
                } else {Thread.sleep(5.msecs); err();}
            }
    }

    protected override bool send(MsgData msg) {
        synchronized(lock.reader)
            try {
                if(msg.dst == this.sysId) {
                    foreach(i; queues[this.addr].keys)
                        synchronized(queueLocks[this.addr][i])
                            queues[this.addr][i] ~= msg;
                } else queues[this.addr][msg.dst] ~= msg;
                return true;
            } catch(Throwable thr) return false;
    }

    protected override void add(ubyte[IDLENGTH] dst, ubyte[] info) { }

    protected override void remove(ubyte[IDLENGTH] dst) { }
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addMeshJunction(
    SpaceMeta sm,
    UUID id,
    string addr,
    string[] known,
    MeshConnectorMeta conn,
    ulong timeout = 5000,
    ulong ackTimeout = 0,
    ulong ackInterval = 1,
    ushort level = 0,
    bool hiding = false,
    bool indifferent = false,
    bool introvert = false
) {
    import flow.core.util : as;
    
    auto jm = sm.addJunction(
        id,
        fqn!MeshJunctionMeta,
        fqn!MeshJunctionInfo,
        fqn!MeshJunction,
        level,
        hiding,
        indifferent,
        introvert
    );
    jm.info.as!MeshJunctionInfo.addr = addr;
    jm.as!MeshJunctionMeta.known = known;
    jm.as!MeshJunctionMeta.timeout = timeout;
    jm.as!MeshJunctionMeta.ackTimeout = ackTimeout;
    jm.as!MeshJunctionMeta.ackInterval = ackInterval;
    jm.as!MeshJunctionMeta.conn = conn;

    return jm;
}

/// creates metadata for an in process junction 
JunctionMeta createMeshJunction(
    SpaceMeta sm,
    UUID id,
    string addr,
    string[] known,
    MeshConnectorMeta conn,
    ulong timeout = 5000,
    ulong ackTimeout = 0,
    ulong ackInterval = 1,
    ushort level = 0,
    bool hiding = false,
    bool indifferent = false,
    bool introvert = false
) {
    import flow.core.util : as;
    
    auto jm = createJunction(
        id,
        fqn!MeshJunctionMeta,
        fqn!MeshJunctionInfo,
        fqn!MeshJunction,
        level,
        hiding,
        indifferent,
        introvert
    );
    jm.info.as!MeshJunctionInfo.addr = addr;
    jm.as!MeshJunctionMeta.known = known;
    jm.as!MeshJunctionMeta.timeout = timeout;
    jm.as!MeshJunctionMeta.ackTimeout = ackTimeout;
    jm.as!MeshJunctionMeta.ackInterval = ackInterval;
    jm.as!MeshJunctionMeta.conn = conn;

    return jm;
}

unittest { test.header("gears.mesh: fully enabled passing of signals via InProcessConnector");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    //Log.logLevel = LL.Debug;

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.wait = 3;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    auto conn1 = new MeshConnectorMeta;
    conn1.type = fqn!InProcessConnector;
    sm1.addMeshJunction(junctionId, "junction", [], conn1, 10);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    auto conn2 = new MeshConnectorMeta;
    conn2.type = fqn!InProcessConnector;
    sm2.addMeshJunction(junctionId, "junction", [], conn2, 10);
    
    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(100.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.unicast !is null, "didn't get test unicast");
    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.anycast !is null, "didn't get test anycast");
    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.multicast !is null, "didn't get test multicast");

    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.unicast, "didn't confirm test unicast");
    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.anycast, "didn't confirm test anycast");
    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.multicast, "didn't confirm test multicast");
test.footer(); }