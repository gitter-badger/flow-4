module flow.core.gears.mesh;

private import core.atomic;
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

        super.dispose();
    }
    
    override protected bool reqVerify() {
        import std.conv : to;
        auto msgId = MsgData.getNewId;
        debug Log.msg(LL.Debug, this, "request verification("~msgId.to!string~")");

        return this.own.confirmedSend(MsgData(this.id, this.own.id,
            MsgCode.Verify, msgId), this);
    }

    override protected bool transport(ref ubyte[] pkg) {
        import std.conv : to;
        auto msgId = MsgData.getNewId;
        debug Log.msg(LL.Debug, this, "transport("~msgId.to!string~")");

        return this.own.confirmedSend(MsgData(this.id, this.own.id, 
            MsgCode.Signal, msgId, pkg), this);
    }
}

abstract class MeshConnector : ILogable {
    private MeshJunction _junction;

    final @property ubyte[IDLENGTH] sysId() {return this._junction.sysId;}
    final @property ubyte[IDLENGTH] id() {return this._junction.id;}
    final @property string addr() {return this._junction.meta.info.as!MeshJunctionInfo.addr;}
    final @property JunctionInfo junction() {return this._junction.meta.info.snap;}
    final @property Processor proc() {return this._junction.proc;}
    final @property Operator ops() {return this._junction.ops;}

    @property MeshConnectorMeta meta() {return this._junction.meta.conn;}

    @property string logPrefix() {
        import std.conv : to;
        import std.digest : toHexString;
        return "connector("~this.id.toHexString.to!string~")";
    }

    protected abstract @property ubyte[] info();

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

    protected void handle(MsgData msg) {this._junction.handle(msg);}
}

private class MeshJunction : Junction {
    private import core.sync.mutex : Mutex;
    private import core.sync.rwmutex : ReadWriteMutex;
    
    private ubyte[IDLENGTH] sysId;
    private ubyte[IDLENGTH] id;

    private bool[ulong] acks;

    private ContextMutex!(ubyte[IDLENGTH]) pLock;
    private ReadWriteMutex cLock;
    private MeshChannel[ubyte[IDLENGTH]] channels;

    private MeshConnector conn;

    private Processor _proc;
    private Operator _ops;

    final @property Processor proc() {return this._proc;}
    final @property Operator ops() {return this._ops;}

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
        this.pLock = new ContextMutex!(ubyte[IDLENGTH]);
        this.cLock = new ReadWriteMutex();
        this._ops = new Operator;
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

            Log.msg(LL.Message, this, this.meta.info.space~" joined mesh as "~this.id.toHexString.to!string);

            // ping
            this.sendPing();
            
            return true;
        } catch(Throwable thr) {
            debug Log.msg(LL.Error, this, "joining mesh failed", thr);
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

    private void sendCfrm(MsgData msg, bool accepted, MeshChannel c) {
        import std.conv : to;
        import std.digest : toHexString;
        
        debug {
            if(accepted)
                Log.msg(LL.Debug, this, "accepting("~msg.id.to!string~")");
            else
                Log.msg(LL.Debug, this, "refusing("~msg.id.to!string~")");
        }
        this.conn.send(MsgData(msg.src, this.id, MsgCode.Cfrm, msg.id,
            [accepted ? 1 : 0]));

        debug Log.msg(LL.Debug, this, "cfrm("~msg.id.to!string~") sent to "~msg.src.toHexString.to!string);
    }

    private void sendPing() {
        import msgpack : pack;
        import std.conv : to;
        
        auto addr = this.meta.info.as!MeshJunctionInfo.addr;
        auto msg = MsgData(this.sysId, this.id, MsgCode.Ping, MsgData.getNewId, addr.pack);
        this.conn.send(msg);

        debug Log.msg(LL.Debug, this, "ping("~msg.id.to!string~") sent");
    }

    private void sendInfo(ubyte[IDLENGTH] dst, ulong id = MsgData.getNewId) {
        import msgpack : pack;
        import std.conv : to;
        import std.digest : toHexString;

        InfoData d;
        d.space = this.meta.info.space;
        d.addr = this.meta.info.as!MeshJunctionInfo.addr;
        d.info = this.conn.info;
        d.auth = this.auth;
        auto msg = MsgData(dst, this.id, MsgCode.Info, id, d.pack);
        this.conn.send(msg);

        debug Log.msg(LL.Debug, this, "info("~msg.id.to!string~") sent to "~dst.toHexString.to!string);
    }

    private bool confirmedSend(MsgData msg, MeshChannel c) {
        import core.time : msecs;
        import std.conv : to;
        import std.datetime.systime : Clock;

        if(!this.meta.info.indifferent) {
            synchronized(c.cfrmLock)
                c.awaitCfrm[msg.id] = true;
            scope(exit)
                c.awaitCfrm.remove(msg.id);
            
            auto timeout = this.meta.as!MeshJunctionMeta.timeout;
            auto time = Clock.currStdTime;
            if(!this.conn.send(msg)) return false;
            
            bool arrived;
            do {
                synchronized(c.cfrmLock)
                    arrived = (msg.id in c.cfrms) ? true : false;
                if(!arrived)
                    Thread.sleep(5.msecs);
            } while(!arrived && time + timeout.msecs.total!"hnsecs" > Clock.currStdTime);
            
            debug Log.msg(LL.Debug, this, "waited "~(Clock.currStdTime-time).to!string~" hnsecs for answer("~msg.id.to!string~")");

            if(arrived) synchronized(c.cfrmLock) {                    
                scope(exit) c.cfrms.remove(msg.id);
                return c.cfrms[msg.id];
            } else {
                Log.msg(LL.Warning, this, "cfrm timeout("~msg.id.to!string~") ");
                return false;
            }
        } else
            return this.conn.send(msg);
    }

    private void handle(MsgData msg) {
        import std.conv : to;

        try {
            // handle message only if its for self
            if(msg.dst == this.sysId || msg.dst == this.id) {
                switch(msg.code) {
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
            }
        } catch(Throwable thr) {
            Log.msg(LL.Error, this, "processing message", thr);
        }
            
    }

    private void onPing(MsgData msg) {
        import msgpack : unpack;
        import std.conv : to;
        import std.digest : toHexString;

        synchronized(this.pLock.get(msg.src).reader) {
            debug Log.msg(LL.Debug, this, "ping("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
            
            auto addr = msg.data.unpack!string;
            this.contact(addr);

            this.sendInfo(msg.src, msg.id);
        }
    }

    private void onInfo(MsgData msg) {
        import msgpack : unpack;
        import std.conv : to;
        import std.digest : toHexString;

        synchronized(this.pLock.get(msg.src).reader) {
            auto d = msg.data.unpack!InfoData;

            this.ops.async(this.proc, {
                synchronized(this.pLock.get(msg.src).writer) {
                    if(this.state == JunctionState.Attached) {
                        synchronized(this.cLock.writer) {
                            if(msg.src in this.channels) {
                                debug Log.msg(LL.Debug, this, "info("~msg.id.to!string~") from "~d.space~" ignoerd, I know it already");
                            } else {
                                debug Log.msg(LL.Debug, this, "info("~msg.id.to!string~") from "~d.space~" known as "~msg.src.toHexString.to!string);
                                this.contact(d.addr);
                                auto c = new MeshChannel(d.space, this, d.info, d.auth);
                                this.register(c);
                                this.sendInfo(msg.src, msg.id);
                            }
                        }
                    } else {
                        debug Log.msg(LL.Debug, this, "info("~msg.id.to!string~") from "~d.space~" ignoerd, junction is detaching");
                    }
                }
            });
        }
    }

    /// if a node signs off unregister its channel
    private void onSignOff(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;
        
        this.ops.async(this.proc, {
            auto done = false;
            synchronized(this.pLock.get(msg.src).writer) {
                if(this.state == JunctionState.Attached) {
                    synchronized(this.cLock.writer) {
                        if(msg.src in this.channels) {
                            auto c = this.channels[msg.src];
                            debug Log.msg(LL.Debug, this, "signoff("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
                            this.unregister(c);
                            done = true;
                        } else {
                            debug Log.msg(LL.Debug, this, "signoff("~msg.id.to!string~") from "~msg.src.toHexString.to!string~" ignored, I don't know it");
                        }
                    }
                } else {
                    debug Log.msg(LL.Debug, this, "signoff("~msg.id.to!string~") from "~msg.src.toHexString.to!string~" ignored, junction is detaching");
                }
            }
            if(done) this.pLock.remove(msg.src); // it might not need that mutex anymore
        });
    }

    private void onVerify(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;
        
        synchronized(this.pLock.get(msg.src).reader) {
            MeshChannel c;
            synchronized(this.cLock.reader) {
                if(msg.src in this.channels) {
                    c = this.channels[msg.src];
                    c.ops.checkout();
                }
            }

            if(c !is null) {
                debug Log.msg(LL.Debug, this, "verify("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
                this.sendCfrm(msg, c.verify(), c);
            } else {
                debug Log.msg(LL.Debug, this, "verify("~msg.id.to!string~") from "~msg.src.toHexString.to!string~" ignored, I don't know it");
            }
        }
    }

    private void onSignal(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;

        synchronized(this.pLock.get(msg.src).reader) {
            MeshChannel c;
            synchronized(this.cLock.reader) {
                if(msg.src in this.channels) {
                    c = this.channels[msg.src];
                    c.ops.checkout();
                }
            }

            if(c !is null) {
                debug Log.msg(LL.Debug, this, "signal("~msg.id.to!string~") from "~msg.src.toHexString.to!string);
                this.sendCfrm(msg, c.pull(msg.data), c);
            } else {
                debug Log.msg(LL.Debug, this, "signal("~msg.id.to!string~") from "~msg.src.toHexString.to!string~" ignored, I don't know it");
            }
        }
    }

    private void onCfrm(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;

        // first class handler will not wait for lock
        synchronized(this.pLock.get(msg.src).reader) {
            bool answer = msg.data[0] == 1;

            synchronized(this.cLock.reader) {
                debug Log.msg(LL.Debug, this, "notified about "~(answer ? "accepted" : "refused")~"("~msg.id.to!string~")");
                if(msg.src in this.channels)
                    debug Log.msg(LL.Debug, this, (answer ? "accepted" : "refused")~"("~msg.id.to!string~") ");
                    synchronized(this.channels[msg.src].cfrmLock) if(msg.id in this.channels[msg.src].awaitCfrm)
                        this.channels[msg.src].cfrms[msg.id] = answer;
            }
        }
    }

    private void onDefault(MsgData msg) {
        import std.conv : to;
        import std.digest : toHexString;

        // first class handler will not wait for lock
        synchronized(this.pLock.get(msg.src).reader)
            Log.msg(LL.Error, this, "unknown("~msg.id.to!string~")");
    }

    /// registers a channel passing junction
    private void register(MeshChannel c) {
        import std.conv : to;
        import std.digest : toHexString;

        this.conn.add(c.id, c.info);
        this.channels[c.id] = c;
        debug Log.msg(LL.Debug, this, "registered("~c.id.toHexString.to!string~")");
    }
    
    /// unregister a channel passing junction
    private void unregister(MeshChannel c) {
        import core.memory : GC;
        import std.conv : to;
        import std.digest : toHexString;

        auto id = c.id;
        this.channels.remove(id);
        this.conn.remove(id);
        c.dispose(); GC.free(&c);

        debug Log.msg(LL.Debug, this, "unregistered("~id.toHexString.to!string~")");
    }

    override bool up() {
        import core.memory : GC;
        import std.conv : to;
        import std.digest : toHexString;
        import std.digest.md : md5Of;
        
        // creating processor;
        // default is one core
        if(this.meta.pipes < 1)
            this.meta.pipes = 1;
        this._proc = new Processor(this.meta.pipes);
        this.proc.start();

        //this.sysId[0..IDLENGTH] = "".bin.md5Of.dup;
        this.id[0..IDLENGTH] = this.meta.info.space.md5Of.dup;
        this.conn = Object.factory(this.meta.conn.type).as!MeshConnector;
        if(this.conn !is null) {
            this.conn._junction = this;
            bool r = false;
            try {r = this.conn.create() && this.conn.listen() && this.connect();}
            catch(Throwable thr) {Log.msg(LL.Message, this, "connecting failed", thr);}
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
            foreach(s, c; this.channels) {
                synchronized(this.pLock.get(c.id).writer)
                    this.unregister(c);
                this.pLock.remove(id); // it might not need that mutex anymore
            }

        this.ops.join();
        this.pLock.clear();

        try {
            this.conn.unlisten();

            // sign off first
            this.conn.send(MsgData(this.sysId, this.id,
                MsgCode.SignOff, MsgData.getNewId));
        
            this.conn.dispose(); GC.free(&this.conn);
            this.conn = null;
        }
        catch(Throwable thr) {
            Log.msg(LL.Message, this, "disconnecting failed");
        }

        this.proc.stop();
        this._proc = null;
    }

    override MeshChannel get(string dst) {
        import std.digest.md : md5Of;

        ubyte[IDLENGTH] dstId;
        dstId[0..IDLENGTH] = dst.md5Of.dup;
        synchronized(this.cLock.reader)
            if(dstId in this.channels)
                return this.channels[dstId];
        
        return null;
    }
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addMeshJunction(
    SpaceMeta sm,
    UUID id,
    string addr,
    string[] known,
    MeshConnectorMeta conn,
    ulong timeout = 5000,
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
    jm.as!MeshJunctionMeta.conn = conn;

    return jm;
}

/// creates metadata for an in process junction 
JunctionMeta createMeshJunction(
    UUID id,
    string addr,
    string[] known,
    MeshConnectorMeta conn,
    ulong timeout = 5000,
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
    jm.as!MeshJunctionMeta.conn = conn;

    return jm;
}