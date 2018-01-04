module flow.core.ipc.nanomsg.mesh;

private import core.stdc.errno;
version(Windows) immutable ETIMEDOUT = 138;
//version(Windows) import core.sys.windows.winsock2;
private import core.thread;
private import flow.core;

extern(C)
{
    @nogc:
    void nn_err_abort();
    int nn_err_errno();
    const(char)* nn_err_strerror(int errnum);
}

class NanoMsgConnectorMeta : MeshConnectorMeta { mixin _data;
    @field size_t retry;
    /// just a dirty hack in msecs, connect should wait until socket is actually connected
    @field long wait;
    @field string listen;
    @field string subListen;
    @field string subAddr;
    @field ulong threads;
}

private struct NanoMsgDest {
    import msgpack : nonPacked;

    @nonPacked int ep = -1;

    string subAddr;

    this(string sA) {subAddr = sA;}
}

class NanoMsgConnector : MeshConnector {
    private import core.sync.mutex : Mutex;
    private import core.sync.rwmutex : ReadWriteMutex;
    private import deimos.nanomsg.nn;
    private import deimos.nanomsg.bus;
    private import deimos.nanomsg.pubsub;

    private int busSock;
    private int pubSock;
    private int subSock;

    private ReadWriteMutex recvLock;
    private Mutex sendBusLock, sendPubLock;

    private bool canRecv;

    private NanoMsgDest[ubyte[IDLENGTH]] dests;

    override @property NanoMsgConnectorMeta meta() {return super.meta.as!NanoMsgConnectorMeta;}

    private ubyte[] _info;
    override protected @property ubyte[] info() {return this._info;}

    /// ctor
    this() {
        this.recvLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.sendBusLock = new Mutex;
        this.sendPubLock = new Mutex;
        super();
    }
    
    override protected bool create() {
        import msgpack : pack;
        import std.conv : to;
        import std.digest : toHexString;

        auto info = NanoMsgDest(this.meta.subAddr);

        this._info = info.pack;

        // ensure it can receive something
        if(this.meta.threads < 1)
            this.meta.threads = 1;

        try {
            return this.initSocks();
        } catch(Throwable thr) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") creating failed", thr);
            return false;
        }
    }

    protected override void dispose() {
        synchronized(this.recvLock.writer)
            this.canRecv = false;

        this.close(this.pubSock);
        this.close(this.subSock);
        this.close(this.busSock);

        super.dispose();
    }

    protected override bool listen() {
        import std.conv : to;
        import std.digest : toHexString;

        this.recv();
        auto r = this.bind();

        if(r) Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") bound successfully");
        return r;
    }

    protected override void unlisten() {
        synchronized(this.recvLock.writer)
            this.canRecv = false;
    }

    private bool initSocks() {
        import std.conv : to;
        import std.digest : toHexString;

        auto timeout = 50;

        this.busSock = nn_socket(AF_SP, NN_BUS);
        if(this.busSock < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") creating bus failed: "~nn_err_strerror (errno).to!string);
            return false;
        } else
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") created bus "~this.busSock.to!string);

        if(nn_setsockopt(this.busSock, NN_SOL_SOCKET, NN_RCVTIMEO, &timeout, timeout.sizeof) < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") setting bus timeout failed: "~nn_err_strerror (errno).to!string);
            return false;
        }

        if(!this.createPub()) return false;

        this.subSock = nn_socket(AF_SP, NN_SUB);
        if(this.subSock < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") creating subscriber failed: "~nn_err_strerror (errno).to!string);
            return false;
        } else
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") created subscriber "~this.subSock.to!string);

        if(nn_setsockopt(this.subSock, NN_SUB, NN_SUB_SUBSCRIBE, this.id.ptr, this.id.length) < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") setting sub failed: "~nn_err_strerror (errno).to!string);
            return false;
        }

        if(nn_setsockopt(this.subSock, NN_SOL_SOCKET, NN_RCVTIMEO, &timeout, timeout.sizeof) < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") setting sub timeout failed: "~nn_err_strerror (errno).to!string);
            return false;
        }

        Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") initialized");
        return true;
    }

    private bool createPub() {
        import std.conv : to;
        import std.digest : toHexString;

        this.pubSock = nn_socket(AF_SP, NN_PUB);
        if(this.pubSock < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") creating publisher failed: "~nn_err_strerror (errno).to!string);
            return false;
        } else
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") created publisher "~this.pubSock.to!string);

        foreach(i, d; this.dests)
            d.ep = this.connectPub(d.subAddr);

        return true;
    }

    private int connectPub(string sub) {
        import std.conv : to;
        import std.digest : toHexString;
        import std.string : toStringz;

        int ep;
        for(size_t i = 0; i < this.meta.retry+1; i++) {
            ep = nn_connect(this.pubSock, sub.toStringz);
            if(ep >= 0)
                break;
            else
                Thread.sleep(5.msecs);
        }

        if(ep < 0)
            Log.msg(LL.Info, "nanomsg("~this.id.toHexString.to!string~") connecting to sub failed: "~nn_err_strerror (errno).to!string);
        else
            Log.msg(LL.Message, "nanomsg("~this.id.toHexString.to!string~") connected to sub "~sub~" as endpoint "~ep.to!string);

        if(this.meta.wait > 0)
            Thread.sleep(this.meta.wait.msecs);

        return ep;
    }

    private bool bind() {
        import std.conv : to;
        import std.digest : toHexString;
        import std.string : toStringz;

        if(nn_bind(this.busSock, this.meta.listen.toStringz) < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") binding bus failed: "~nn_err_strerror (errno).to!string);
            return false;
        } else
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") listening to bus "~this.meta.listen);

        if(nn_bind(this.subSock, this.meta.subListen.toStringz) < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") binding sub failed: "~nn_err_strerror (errno).to!string);
            return false;
        } else
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") listening to sub "~this.meta.subListen);

        return true;
    }

    private void close(int sock) {
        import std.conv : to;
        import std.digest : toHexString;

        int rc;
        while(rc != 0 && errno != EBADF && errno != EINVAL && errno != ETERM)
            rc = nn_close(sock);
        if(rc != 0)
            Log.msg(LL.Warning, "nanomsg("~this.id.toHexString.to!string~") closing socket failed: "~nn_err_strerror (errno).to!string);
    }

    protected override bool connect(string addr) {
        import std.algorithm.searching : any;
        import std.conv : to;
        import std.digest : toHexString;
        import std.string : toStringz;

        if(addr != this.addr) {
            int ep;
            for(size_t i = 0; i < this.meta.retry+1; i++) {
                ep = nn_connect(this.busSock, addr.toStringz);
                if(ep >= 0)
                    break;
                else
                    Thread.sleep(5.msecs);
            }

            if(ep < 0) {
                Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") connecting to bus failed: "~nn_err_strerror (errno).to!string);
                return false;
            } else
                Log.msg(LL.Message, "nanomsg("~this.id.toHexString.to!string~") connected to bus "~addr~" as endpoint "~ep.to!string);
        }
        
        if(this.meta.wait > 0)
            Thread.sleep(this.meta.wait.msecs);

        return true;
    }

    private void recv() {
        this.canRecv = true;

        // spawn n threads listening to sys channel
        for(size_t i = 0; i < this.meta.threads; i++) {
            new Thread({
                auto l = new Mutex;
                while(this.canRecv && this.recvLock.reader.tryLock()) {
                    this.recv(this.busSock, 0, l, (pkg) {
                        scope(exit) 
                            this.recvLock.reader.unlock();
                        this.proc(pkg);
                    }, &this.recvLock.reader.unlock);
                }
            }).start();

            new Thread({
                auto l = new Mutex;
                while(this.canRecv && this.recvLock.reader.tryLock()) {
                    this.recv(this.subSock, IDLENGTH, l, (pkg) {
                        scope(exit) 
                            this.recvLock.reader.unlock();
                        this.proc(pkg);
                    }, &this.recvLock.reader.unlock);
                }
            }).start();
        }
    }

    private void proc(ubyte[] pkg) {
        import msgpack : unpack;
        import std.conv : to;
        import std.digest : toHexString;

        MsgData msg;
        try {msg = pkg.unpack!MsgData;}
        catch(Throwable thr) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") deserializing message failed", thr);
        }
        debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") recv("~msg.id.to!string~", "~msg.code.to!string~") from "~msg.src.toHexString.to!string);
        super.proc(msg);
    }

    private void recv(int sock, size_t trim, Mutex l, void delegate(ubyte[]) f, void delegate() err) {
        import std.conv : to;
        import std.digest : toHexString;
        import std.parallelism : taskPool, task;

        void* buf;
        int rc;
        synchronized(l)
            rc = nn_recv (sock, &buf, NN_MSG, 0);

        // somewhere a deadlock? check it err() is executed on all alternative paths
        if(rc >= 0) {
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") recv "~(rc-trim).to!string~" bytes via "~sock.to!string);
            scope(exit) nn_freemsg (buf);
            auto pkg = buf.as!(ubyte*)[trim..rc].as!(ubyte[]).dup;
            taskPool.put(task(f, pkg));
        } else {
            if(errno != ETIMEDOUT)
                Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") recv failed: "~nn_err_strerror (errno).to!string~"["~errno.to!string~"]");
            err();
        }
    }

    protected override bool send(MsgData msg) {
        import msgpack : pack;
        import std.conv : to;
        import std.digest : toHexString;
        
        auto r = false;
        // if there is no channel or channel requires passive connection
        if(msg.dst == this.sysId || msg.dst !in this.dests || this.dests[msg.dst].ep < 0) synchronized(this.sendBusLock) {
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") sending("~msg.id.to!string~", "~msg.code.to!string~") to "~msg.dst.toHexString.to!string~" via "~this.busSock.to!string);
            auto pkg = msg.pack;
            r = nn_send (this.busSock, pkg.ptr, pkg.length, 0) == pkg.length;
        } else synchronized(this.sendPubLock) {
            debug 
                Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") sending("~msg.id.to!string~", "~msg.code.to!string~") to "~msg.dst.toHexString.to!string~" via "~this.pubSock.to!string);
            auto pkg = msg.dst~msg.pack;
            r = nn_send (this.pubSock, pkg.ptr, pkg.length, 0) == pkg.length;
        }

        if(r) {
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") sent("~msg.id.to!string~", "~msg.code.to!string~") to "~msg.dst.toHexString.to!string);
            return true;
        } else {
            Log.msg(LL.Warning, "nanomsg("~this.id.toHexString.to!string~") send("~msg.id.to!string~") failed: "~nn_err_strerror (errno).to!string);
            return false;
        }
    }

    protected override void add(ubyte[IDLENGTH] dst, ubyte[] info) {
        import msgpack : unpack;
        auto d = info.unpack!NanoMsgDest;
        d.ep = this.connectPub(d.subAddr);
        this.dests[dst] = d;
    }

    protected override void remove(ubyte[IDLENGTH] dst) {
        if(dst in this.dests) {
            nn_shutdown(this.pubSock, this.dests[dst].ep);
            this.dests.remove(dst);
        }
    }
}

unittest { test.header("ipc.nanomsg.mesh: fully enabled passing of signals via inproc");
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
    a.wait = 5;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    auto conn1 = new NanoMsgConnectorMeta;
    conn1.type = fqn!NanoMsgConnector;
    conn1.listen = "inproc://j1bus";
    conn1.subListen = "inproc://j1sub";
    conn1.subAddr = "inproc://j1sub";
    conn1.threads = 2;
    sm1.addMeshJunction(junctionId, "inproc://j1bus", [], conn1, 10);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    auto conn2 = new NanoMsgConnectorMeta;
    conn2.type = fqn!NanoMsgConnector;
    conn2.listen = "inproc://j2bus";
    conn2.subListen = "inproc://j2sub";
    conn2.subAddr = "inproc://j2sub";
    conn2.threads = 2;
    sm2.addMeshJunction(junctionId, "inproc://j2bus", ["inproc://j1bus"], conn2, 10);
    
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

unittest { test.header("ipc.nanomsg.mesh: fully enabled passing of signals via tcp");
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
    a.wait = 100;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    auto conn1 = new NanoMsgConnectorMeta;
    conn1.type = fqn!NanoMsgConnector;
    conn1.listen = "tcp://*:60000";
    conn1.subListen = "tcp://*:60001";
    conn1.subAddr = "tcp://127.0.0.1:60001";
    /* just a dirty hack in msecs, connect should wait until socket is actually connected
    for localhost 1 msec should be enough, for network comm it might require more */
    conn1.wait = 1;
    conn1.retry = 2;
    conn1.threads = 1;
    sm1.addMeshJunction(junctionId, "tcp://127.0.0.1:60000", [], conn1, 300, 300, 30);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    auto conn2 = new NanoMsgConnectorMeta;
    conn2.type = fqn!NanoMsgConnector;
    conn2.listen = "tcp://*:60010";
    conn2.subListen = "tcp://*:60011";
    conn2.subAddr = "tcp://127.0.0.1:60011";
    conn2.wait = 1;
    conn2.retry = 2;
    conn2.threads = 1;
    sm2.addMeshJunction(junctionId, "tcp://127.0.0.1:60010", ["tcp://127.0.0.1:60000"], conn2, 200, 200, 20);
    
    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(300.msecs);

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