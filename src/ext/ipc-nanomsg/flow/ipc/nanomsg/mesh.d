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
}

private struct NanoMsgDest {
    private import core.sync.mutex : Mutex;
    private import msgpack : nonPacked;

    @nonPacked Mutex pushLock;
    @nonPacked int pushSock = -1; // outbound

    string subAddr;

    this(string sA) {subAddr = sA;}
}

class NanoMsgConnector : MeshConnector {
    private import core.sync.mutex : Mutex;
    private import core.sync.rwmutex : ReadWriteMutex;
    private import deimos.nanomsg.nn;
    private import deimos.nanomsg.bus;
    private import deimos.nanomsg.pipeline;

    private int busSock;
    private int pullSock; // inbound

    private ReadWriteMutex recvLock;
    private Mutex sendBusLock;

    private bool canRecv;

    private NanoMsgDest[ubyte[IDLENGTH]] dests;

    override @property NanoMsgConnectorMeta meta() {return super.meta.as!NanoMsgConnectorMeta;}

    private ubyte[] _info;
    override protected @property ubyte[] info() {return this._info;}

    /// ctor
    this() {
        /*
        t.job = Job(&t.exec, &t.catchError, t.meta.time);
            this.space.proc.run(&t.job);
        */

        this.recvLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.sendBusLock = new Mutex;
        super();
    }
    
    override protected bool create() {
        import msgpack : pack;
        import std.conv : to;
        import std.digest : toHexString;

        auto info = NanoMsgDest(this.meta.subAddr);

        this._info = info.pack;

        try {
            return this.initSocks();
        } catch(Throwable thr) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") creating failed", thr);
            return false;
        }
    }

    protected override void dispose() {
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

        foreach(d; this.dests)
            this.close(d.pushSock);
        this.close(this.pullSock);
        this.close(this.busSock);
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

        this.pullSock = nn_socket(AF_SP, NN_PULL);
        if(this.pullSock < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") creating pull failed: "~nn_err_strerror (errno).to!string);
            return false;
        } else
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") created pull "~this.pullSock.to!string);

        if(nn_setsockopt(this.pullSock, NN_SOL_SOCKET, NN_RCVTIMEO, &timeout, timeout.sizeof) < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") setting pull timeout failed: "~nn_err_strerror (errno).to!string);
            return false;
        }

        if(!this.createPush()) return false;

        Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") initialized");
        return true;
    }

    private bool createPush() {
        import std.conv : to;
        import std.digest : toHexString;

        foreach(i, d; this.dests) {
            d.pushLock = new Mutex;
            d.pushSock = this.connectPush(d.subAddr);
        }

        return true;
    }

    private int connectPush(string push) {
        import std.conv : to;
        import std.digest : toHexString;
        import std.string : toStringz;

        auto pushSock = nn_socket(AF_SP, NN_PUSH);
        if(pushSock < 0) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") creating push failed: "~nn_err_strerror (errno).to!string);
        } else {
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") created push "~pushSock.to!string);

            int ep;
            for(size_t i = 0; i < this.meta.retry+1; i++) {
                ep = nn_connect(pushSock, push.toStringz);
                if(ep >= 0)
                    break;
                else
                    Thread.sleep(5.msecs);
            }

            if(ep < 0) {
                Log.msg(LL.Info, "nanomsg("~this.id.toHexString.to!string~") connecting to push failed: "~nn_err_strerror (errno).to!string);
                this.close(pushSock);
                pushSock = -1;
            } else
                Log.msg(LL.Message, "nanomsg("~this.id.toHexString.to!string~") connected to push "~push~" as endpoint "~ep.to!string);
        }


        if(pushSock >= 0 && this.meta.wait > 0)
            Thread.sleep(this.meta.wait.msecs);

        return pushSock;
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

        if(nn_bind(this.pullSock, this.meta.subListen.toStringz) < 0) {
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

    private Thread recvBusThread, recvPullThread;
    private void recv() {
        this.canRecv = true;

        this.recvBusThread = new Thread({
            while(this.canRecv && this.recvLock.reader.tryLock()) {
                this.recv(this.busSock, (pkg) {
                    scope(exit) 
                        this.recvLock.reader.unlock();
                    this.handle(pkg);
                }, &this.recvLock.reader.unlock);
            }
        }).start();

        this.recvPullThread = new Thread({
            while(this.canRecv && this.recvLock.reader.tryLock()) {
                this.recv(this.pullSock, (pkg) {
                    scope(exit) 
                        this.recvLock.reader.unlock();
                    this.handle(pkg);
                }, &this.recvLock.reader.unlock);
            }
        }).start();
    }

    private void handle(ubyte[] pkg) {
        import msgpack : unpack;
        import std.conv : to;
        import std.digest : toHexString;

        MsgData msg;
        try {msg = pkg.unpack!MsgData;}
        catch(Throwable thr) {
            Log.msg(LL.Error, "nanomsg("~this.id.toHexString.to!string~") deserializing message failed", thr);
        }
        debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") recv("~msg.id.to!string~", "~msg.code.to!string~") from "~msg.src.toHexString.to!string);
        super.handle(msg);
    }

    private void recv(int sock, void delegate(ubyte[]) f, void delegate() err) {
        import std.conv : to;
        import std.digest : toHexString;
        import std.parallelism : taskPool, task;

        void* buf;
        int rc = nn_recv (sock, &buf, NN_MSG, 0);

        // somewhere a deadlock? check it err() is executed on all alternative paths
        if(rc >= 0) {
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") recv "~rc.to!string~" bytes via "~sock.to!string);
            scope(exit) nn_freemsg (buf);
            auto pkg = buf.as!(ubyte*)[0..rc].as!(ubyte[]).dup;
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
        if(msg.dst == this.sysId || msg.dst !in this.dests || this.dests[msg.dst].pushSock < 0) synchronized(this.sendBusLock) {
            debug Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") sending("~msg.id.to!string~", "~msg.code.to!string~") to "~msg.dst.toHexString.to!string~" via "~this.busSock.to!string);
            auto pkg = msg.pack;
            r = nn_send (this.busSock, pkg.ptr, pkg.length, 0) == pkg.length;
        } else {
            auto d = this.dests[msg.dst];
            synchronized(d.pushLock) {
                debug 
                    Log.msg(LL.Debug, "nanomsg("~this.id.toHexString.to!string~") sending("~msg.id.to!string~", "~msg.code.to!string~") to "~msg.dst.toHexString.to!string~" via "~d.pushSock.to!string);
                auto pkg = msg.pack;
                r = nn_send (d.pushSock, pkg.ptr, pkg.length, 0) == pkg.length;
            }
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
        d.pushLock = new Mutex;
        d.pushSock = this.connectPush(d.subAddr);
        this.dests[dst] = d;
    }

    protected override void remove(ubyte[IDLENGTH] dst) {
        if(dst in this.dests) {
            this.close(this.dests[dst].pushSock);
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
    conn1.subListen = "inproc://j1pull";
    conn1.subAddr = "inproc://j1pull";
    /* just a dirty hack in msecs, connect should wait until socket is actually connected
    for localhost 1 msec should be enough, for network comm it might require more */
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
    conn2.subListen = "inproc://j2pull";
    conn2.subAddr = "inproc://j2pull";
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
    sm1.addMeshJunction(junctionId, "tcp://127.0.0.1:60000", [], conn1, 100);

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
    sm2.addMeshJunction(junctionId, "tcp://127.0.0.1:60010", ["tcp://127.0.0.1:60000"], conn2, 100);
    
    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(500.msecs);

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