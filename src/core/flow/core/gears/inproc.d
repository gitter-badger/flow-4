module flow.core.gears.inproc;

private import flow.core.data;
private import flow.core.gears.data;
private import flow.core.gears.engine;
private import flow.core.util;
private import std.uuid;

private class InProcessChannel : Channel {
    bool master;
    InProcessChannel peer;

    override @property InProcessJunction own() {
        import flow.core.util : as;
        return super.own.as!InProcessJunction;
    }

    override @property ubyte[] auth() {
        return this.peer.own.auth;
    }

    this(InProcessJunction own, InProcessJunction recv, InProcessChannel peer = null) {
        if(peer is null) {
            this.master = true;
            this.peer = new InProcessChannel(recv, own, this);
        } else
            this.peer = peer;
        
        super(recv.meta.info.space, own);
        
        own.register(this);
    }

    override protected void dispose() {
        super.dispose();
    }
    
    override protected bool reqVerify() {
        return this.peer.verify();
    }

    override protected bool transport(ref ubyte[] pkg) {
        import flow.core.util : as;

        return this.peer.pull(pkg);
    }
}

/// junction allowing direct signalling between spaces hosted in same process
class InProcessJunction : Junction {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import std.uuid : UUID;

    private static __gshared ReadWriteMutex pLock;
    private static shared InProcessJunction[string][UUID] pool;

    private ReadWriteMutex cLock;
    private InProcessChannel[string] channels;

    // make it visible to module
    override @property JunctionMeta meta() {
        return super.meta;
    }

    /// instances with the same id belong to the same junction
    @property UUID id() {return this.meta.id;}

    override @property string[] list() {
        synchronized(this.lock.reader)
            return pool[this.id].keys;
    }

    shared static this() {
        pLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    /// ctor
    this() {
        this.cLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        super();
    }

    /// registers a channel passing junction
    private void register(InProcessChannel c) {
        synchronized(pLock.reader)
            if(this.id in pool) // if is up
                this.channels[c.dst] = c;
    }
    
    /// unregister a channel passing junction
    private void unregister(InProcessChannel c) {
        import core.memory : GC;
        this.channels.remove(c.dst);
        c.dispose(); GC.free(&c);
    }

    override bool up() {
        import flow.core.util : as;

        auto spc = this.meta.info.space;
        synchronized(pLock)
            if(this.id !in pool || spc !in pool[this.id]) // if is down
                synchronized(this.cLock)
                    pool[this.id][spc] = this.as!(shared(InProcessJunction));

        return true;
    }

    override void down() {
        import core.memory : GC;
        synchronized(pLock) {
            synchronized(this.cLock)
                foreach(dst, c; this.channels)
                    if(c.master) this.unregister(c);

            auto spc = this.meta.info.space;
            if(this.id in pool)
                pool[this.id].remove(spc);
        }
    }

    override Channel get(string dst) {
        import flow.core.util : as;

        synchronized(pLock.reader)
            synchronized(this.lock.reader)
                synchronized(this.cLock.reader) {
                    if(dst in this.channels) {
                        if(dst in pool[this.id])
                            return this.channels[dst];
                        else this.unregister(this.channels[dst]);
                    }
                    else if(dst in pool[this.id]) {
                        return new InProcessChannel(
                            this.as!InProcessJunction,
                            pool[this.id][dst].as!InProcessJunction);
                    }
                }

        return null;
    }
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level = 0,
    bool hiding = false,
    bool indifferent = false,
    bool introvert = false
) {
    import flow.core.util : as;
    
    auto jm = sm.addJunction(
        id,
        fqn!JunctionMeta,
        fqn!JunctionInfo,
        fqn!InProcessJunction,
        level,
        hiding,
        indifferent,
        introvert
    );

    return jm;
}

/// creates metadata for an in process junction 
JunctionMeta createInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level = 0,
    bool hiding = false,
    bool indifferent = false,
    bool introvert = false
) {
    import flow.core.util : as;
    
    auto jm = createJunction(
        id,
        fqn!JunctionMeta,
        fqn!JunctionInfo,
        fqn!InProcessJunction,
        level,
        hiding,
        indifferent,
        introvert
    );

    return jm;
}

unittest { test.header("gears.inproc: fully enabled passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    sm2.addInProcJunction(junctionId);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(50.msecs);

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

unittest { test.header("gears.inproc: hiding (not) passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId, 0, true, false, false);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    sm2.addInProcJunction(junctionId, 0, true, false, false);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(50.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // Since junctions hiding = true, anycast cannot work.
    // Multicast cannot be received since it has no receiver but should be confirmed
    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.unicast !is null, "didn't get test unicast");
    assert(!(nsm2.entities[0].aspects[0].as!TestReceivingAspect.anycast !is null), "got test anycast but shouldn't");
    assert(!(nsm2.entities[0].aspects[0].as!TestReceivingAspect.multicast !is null), "got test multicast but shouldn't");

    // Same for anycast. All other should get a confirmation which in this case tells it was send to destination space
    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.unicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].aspects[0].as!TestSendingAspect.anycast, "confirmed test anycast but shouldn't");
    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.multicast, "didn't confirm test multicast");
test.footer(); }

unittest { test.header("gears.inproc: indifferent (not) passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId, 0, false, true, false);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    sm2.addInProcJunction(junctionId, 0, false, true, false);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(50.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // Since junctions indifferent = true, anycast cannot work.
    // Multicast cannot be received since it has no receiver but should be confirmed
    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.unicast !is null, "didn't get test unicast");
    assert(!(nsm2.entities[0].aspects[0].as!TestReceivingAspect.anycast !is null), "got test anycast but shouldn't");
    assert(!(nsm2.entities[0].aspects[0].as!TestReceivingAspect.multicast !is null), "got test multicast but shouldn't");

    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.unicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].aspects[0].as!TestSendingAspect.anycast, "confirmed test anycast but shouldn't");
    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.multicast, "didn't confirm test multicast");
test.footer(); }

unittest { test.header("gears.inproc: introvert (not) passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId, 0, false, false, true);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    sm2.addInProcJunction(junctionId, 0, false, false, true);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(50.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // Since junctions indifferent = true, it is not accepting anything but the directed unicasts.
    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.unicast !is null, "didn't get test unicast");
    assert(!(nsm2.entities[0].aspects[0].as!TestReceivingAspect.anycast !is null), "got test anycast but shouldn't");
    assert(!(nsm2.entities[0].aspects[0].as!TestReceivingAspect.multicast !is null), "got test multicast but shouldn't");

    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.unicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].aspects[0].as!TestSendingAspect.anycast, "confirmed test anycast but shouldn't");
    assert(!nsm1.entities[0].aspects[0].as!TestSendingAspect.multicast, "confirmed test multicast but shouldn't");
test.footer(); }

unittest { test.header("gears.inproc: fully enabled passing of signals over a only signing junction");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    auto j1 = sm1.addInProcJunction(junctionId);
    j1.key = "-----BEGIN PRIVATE KEY-----
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
HxBygz9UGefgaCHVpz8yIac4OSZPtQ==
-----END PRIVATE KEY-----";
    j1.info.crt = "-----BEGIN CERTIFICATE-----
MIIFeDCCA2CgAwIBAgIJALddqPgiNHmiMA0GCSqGSIb3DQEBCwUAMFExCzAJBgNV
BAYTAlVTMQ8wDQYDVQQIDAZEZW5pYWwxFDASBgNVBAcMC1NwcmluZ2ZpZWxkMQww
CgYDVQQKDANEaXMxDTALBgNVBAMMBHNlbGYwHhcNMTcxMjEwMTQwODMwWhcNMTgw
MTA5MTQwODMwWjBRMQswCQYDVQQGEwJVUzEPMA0GA1UECAwGRGVuaWFsMRQwEgYD
VQQHDAtTcHJpbmdmaWVsZDEMMAoGA1UECgwDRGlzMQ0wCwYDVQQDDARzZWxmMIIC
IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAts+9wWJWj7OOZw5qG7abhyga
ulkH7xLvXO4mhSg+rE4StI0r6dSE1tR+tPzzEjA2PZRvZd2wK2JuigBqn5SGUpJl
+58enMU++g9qbikD8hv57JPKcQb3235oBbPBlfp7cakR+kYLpCMjMwrAOz8gOYFm
4ZvQcmznoWhf8I8U8c1ph5ePH6bEfq+Gp5iUADFitlITFYI3j0hiKMWj06Qjm7kn
cWMz92mYuOM/l6APTyd2OeEvuCsHifmPRhJ60amSSXhMWt5jo1z/bmQfY/l7SdUQ
qqNbz035tf5ZW0Oz+ClWVJIchhav6K0uxqKDHZFf1ccZ/ZOZy3I7t1RFHqsvszMD
oOxGi2tGTmqtzwLKaKlvpD6SxDzYKk/11dWaDxyd/48aAZJ6wZ6rYgPvOVjOcZuS
zDwAm380uFo3iQKnMj4svKZpvJT3NDopmoExkTyViuJqRhNdgXf6V6YoezkWsJ4V
+TIVMIsNIC64jY+taPq/piSVm5/W+kxyNQ5+BoHp7e77aSlz9IKO3GWrIFxoPIhF
GpvUK1878lH6/qo5kUfXOQKem5Gog98xiUohKnDh0Q9lVsjg7bwputyFlIAXtH1h
e7cntgcpN1EnmnXxIyT/PLEg6iDn0/7k25fvqhcO+xEiuI/UUnQlcGCb6Kcia12l
nygIbvqL52+8VZttsvMCAwEAAaNTMFEwHQYDVR0OBBYEFLI0o0LT6C01zqhTirbX
+GJ5RHKsMB8GA1UdIwQYMBaAFLI0o0LT6C01zqhTirbX+GJ5RHKsMA8GA1UdEwEB
/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggIBABx+1Ba4sNdOA4KWEj8HuUHGhwnd
qex52fQzVdKirMDNNJKaUk+p0EePuz/wgTpBVCAhX/l5Kdns71UzVd1lJFG2fgLy
O8UV4GKFgeiF8//QfzNVY+CokvQEHuKu4ojTUI8n7oBMIVGs60tnTgGR4en07Ojh
lf8W3XwD8+VubE/VrIIBvH4UDtc7QtNHgGjTkB7XaBJF2ZPfJcjoB7Zboqb3IXz0
myIeJM9YMHVCwCdqGL9+8/9Nq5kzgatyYoMKdAFDWhceMIvlG9/GIMFhUUTwXepJ
Kh3aWAI1CrOjDHhirzZ+d65fNJEZmzv2lc5UknWmJJWSem1G5MXRzarx2vZIeVw2
eC7njugtNY5zZ4kxcxCKTiwBXS7rRhnS7rNXUxzp0i2u0AR/S/r0D+SG7q/YlWtW
UZ5iZf9oqJf/MmyFVNkvwHo/Nv0Ps7iqPIUaXxnim0hn6Wxpni+2SCh1Mpf9r8MZ
RQJDiISfGys+jDrAcOrlKvNLEOzDBDpDfaH7Z3tx3A9WdY+1IoclNNh1qie7r/GX
qLwGbSzrfB3+QYBQhguXWmC7MH+BwcgcNUVChlBYM+xwNwdKr4wb7YjbgBVIrQoh
thnjPSlqLCnOwD2z95HtA5vYK3QQqlvvRcQ8rCIg8Yc3SNSexfV1/ByErXSpbdBJ
f7REu8EKldYyWHIR
-----END CERTIFICATE-----";

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    auto j2 = sm2.addInProcJunction(junctionId);
    j2.key = "-----BEGIN PRIVATE KEY-----
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
Ci1ZywV5czGuFGBOcRpaSLtxsC3DSHE=
-----END PRIVATE KEY-----";
    j2.info.crt = "-----BEGIN CERTIFICATE-----
MIIFgjCCA2qgAwIBAgIBADANBgkqhkiG9w0BAQsFADBPMQswCQYDVQQGEwJVUzEP
MA0GA1UECAwGRGVuaWFsMRQwEgYDVQQHDAtTcHJpbmdmaWVsZDEMMAoGA1UECgwD
RGlzMQswCQYDVQQDDAJjYTAeFw0xNzEyMTAxNDA4MzFaFw0xODEyMTAxNDA4MzFa
MD0xCzAJBgNVBAYTAlVTMQ8wDQYDVQQIDAZEZW5pYWwxDDAKBgNVBAoMA0RpczEP
MA0GA1UEAwwGc2lnbmVkMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
5I92d1z3NE/O91mVCLvCEFPzL1OLhzA5/Fzbc4Zf9UcL3MLZBFyqypjV0R90dqd5
YtZ8m4yocUyw0x5E5k3HAfKAB2KNIE7kjopBgl1759pVL9kukjqCNaZxYTkKevdg
wHogVvUvEEoaQ14ZaPWy3uwC5qZbyr8eKpXEr3SwjgJQTuelQPCsZ0uy5wdwFlRT
BZ3JVdpIGcPHr8fAVkjeiVuCTGjysOg34VC3Sp6X51brGOaQ/zY2s8vKXxeZH1O/
qW6qZ+zVke4zjyIl6Hcj/XtobEA9za9wPlYbTjKSRJl1P9U6+qRwWaMMTaPFHbeX
AQ5jo/1ksbQNmvKtWMiLFoauM6k/ndXqGgoks1fjybQhurV3a7R9dbWjOjqTrgOq
XIPyORuWuIjUWbSJYhckHUUBTBu8XqL6EjSo6AF3My66PpRTA52QdjyMtYYfH8Sw
VnY13cwXLt+ZWBZQ59WwqUThY7WjHMosnKyqBq31zIi88yveFbqv8tMjkI/QHKGd
RqDK0ScJAgdjzoBDzVY0bttOfQcyj5oeGAwt2THW01GeWf0yWfm4ul1EcxIpNIVW
dlUdek20adScyRwrxtyhhIupd6xDE2V1ikDTEUDt/4+6m1t955ABCcAuHJRf9gT5
i5wnRJUCU4WXNsnQlVen1KAuz5CQFAYlNJe8X/nWbT8CAwEAAaN7MHkwCQYDVR0T
BAIwADAsBglghkgBhvhCAQ0EHxYdT3BlblNTTCBHZW5lcmF0ZWQgQ2VydGlmaWNh
dGUwHQYDVR0OBBYEFK1LqNbKpCaSAmuIv+zbBivjNvzqMB8GA1UdIwQYMBaAFLzS
Rti88fE1Y+iDL43gYxt5y6NPMA0GCSqGSIb3DQEBCwUAA4ICAQAs3N8+1cLBfG7C
ozB2+46PZ43kj+39Oo3GqRcigUa4nwdhX61dhQU09iKg1kaCzieFKI6jilXg5aTw
N62tEeyQSwQhNAc8G/XMQhTSAV2pCo6QbywZMTfqqXPH+DiH1X+etfrdBaG6YHlv
aFt7CO9A39UuVLoeWYbbCD3yoN4GrtFzvxWgaF0msy+Xde9GQVMXChrvPM+zVGF6
Sf5Wbdcv1CS7sHQ2aUknfQ1iae4CkL4NT4N64x+iFLQejDz7+Fp4d28Vrf+SpWDl
rvV4fVzSae8COpoP1VLXQ74vSpdcvDBlZ5FtxGVErGDPgugAmMTQgSWbLUWzadQC
oaky4WKr1nRtMbMSnVOYLGbzU6apvhWEskgJu4GkX3WUfaOihafG9S2LRGHC1ydX
Slqxn4NZDSagxN44UqXhYjw31Rf5WiWzUBCsFDFmBidlh6dg5hCXmnjHTkEFLcsE
88vSery9N3eApttWtE/k8r5xgE1kju0YclgoD7iiQi2HpKuByMGuKEAQDXQlUYH5
21J9+bZ8GQVozhzb4ysCewyNkCn5o/B3fHbK+4ahfNIXt6N1+htCuF6im9p0pw04
SmZvkIruvhoQ4eAWFTkqPbuepWGFSJlCzCko4926a0uBswdTaUj3bJfQD+xu9Eak
DuRfSEERdBHjYgvyYN3Q5tlWea/uvQ==
-----END CERTIFICATE-----";

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(200.msecs);

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

unittest { test.header("gears.inproc: fully enabled passing of signals over an encrypting junction");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    auto j1 = sm1.addInProcJunction(junctionId);
    j1.info.encrypting = true;
    j1.key = "-----BEGIN PRIVATE KEY-----
MIIJQgIBADANBgkqhkiG9w0BAQEFAASCCSwwggkoAgEAAoICAQC2z73BYlaPs45n
DmobtpuHKBq6WQfvEu9c7iaFKD6sThK0jSvp1ITW1H60/PMSMDY9lG9l3bArYm6K
AGqflIZSkmX7nx6cxT76D2puKQPyG/nsk8pxBvfbfmgFs8GV+ntxqRH6RgukIyMz
CsA7PyA5gWbhm9BybOehaF/wjxTxzWmHl48fpsR+r4anmJQAMWK2UhMVgjePSGIo
xaPTpCObuSdxYzP3aZi44z+XoA9PJ3Y54S+4KweJ+Y9GEnrRqZJJeExa3mOjXP9u
ZB9j+XtJ1RCqo1vPTfm1/llbQ7P4KVZUkhyGFq/orS7GooMdkV/Vxxn9k5nLcju3
VEUeqy+zMwOg7EaLa0ZOaq3PAspoqW+kPpLEPNgqT/XV1ZoPHJ3/jxoBknrBnqti
A+85WM5xm5LMPACbfzS4WjeJAqcyPiy8pmm8lPc0OimagTGRPJWK4mpGE12Bd/pX
pih7ORawnhX5MhUwiw0gLriNj61o+r+mJJWbn9b6THI1Dn4Ggent7vtpKXP0go7c
ZasgXGg8iEUam9QrXzvyUfr+qjmRR9c5Ap6bkaiD3zGJSiEqcOHRD2VWyODtvCm6
3IWUgBe0fWF7tye2Byk3USeadfEjJP88sSDqIOfT/uTbl++qFw77ESK4j9RSdCVw
YJvopyJrXaWfKAhu+ovnb7xVm22y8wIDAQABAoICAFdU7sWPgOKtWH4K+M28cpgi
pIIZPh0L4qV2b5h1HVubAHyYZD4UdFFcuhskK8qolYDdhEoZmatgHoZ2pHkPrwuL
PIT0At/JqsgyzRlLJsNmcgJ+p9tPBOEqhe8TbIuFWat2pUv2YmFLF+muXR7wjShr
lQZ6NR40wILvJcX51HufMabA1HK+bGhI2f7+eNWOwiVvGAbSalBct+faYuUcKJaf
4SPdzFmJbJgGl76LjES4CValKPLGO5fCTJuhAGNgqq3GdlOCof7M0omd8xEDgc5H
puqdl6J1EbHLjEx5D2Sh+sfz9QRpmieBdDMYN6LMbAfoUZY+CN6T98sgytRX2zTl
PBnVUGk+KqofQ+jWb3hw0M8r+G4f6G0Goec5kYMzkeADyqR2e3gtrOJfiV7gw5Ew
/IXePqSQdPqAosXgBBJ5RzkMvNLMzNb+n0Loi0N8Bzar9X0h6sDUcXM2dM6Iw7Iv
jIxZkgZiXilgm+GOPCeWXCzEvYptoUxK1Qab0hOznSm0s4A6lJHWl5+RDPltdNEq
SDzPDXrcKvqkQshHm18IRLLMG6cQe5VtL69+G73PAN7kQUcBof3r269KQKRyeNtU
m5Jr9HYfF99EXe29CB1BDJpz0S2oQNQyfzPcX8ldSNjd+gKsWL20Dv0WHMMAgn2+
gt+fCHYRJMARvVD1GUeBAoIBAQDlyMHfD0ZdnhPTrbjYW67da9CuJYx1D9h+ZU3t
GCCdtgCMM/lnho+T9GnZuElo9g0pDYNIoT4n2wlokhvPlo31p/XB2p4rLNd7osm+
SIOxvOrKmcFJMKMgMoNRl9+29tNV0spCoBze8X678WlAfm1Mh5mw7plBRlf5mnh7
f407eSWR1DYph92YkALFScfhPLEsll94mYqUE268NQpOFllHLqx1m6mKwt8Ma4/I
nCzdKq0JFYpr3MOxYtxLZa60tNOdn06ByhkHnWpL1E02NfnOV+weqcDe54cc4ztK
XZla0bz3LnmpjyIU2TGk6T24zntQtVlK1Rcv/BeQbHpoEF8DAoIBAQDLqxCf0wif
NJLRf0Bv5nnzMCUY2h21vWuh4tcIEGX3dN6u0a+WVR4+nM2b+QCqY0BmPcvSmHs1
2G7CTu2NhHh6J4rG8ZJQixupP5ljtuEycvLyhuK63oMYmqnYJWrkdQKTI8kAizhV
fpriXWoGIlfcoe3lSpXSFuG98sYVyO+QSVwOBjkANcaPH2iuxFzxMT8oUhQj1Ozs
NdXqYBl+8OSzNbBLFhYA/PLS7YMfogCpaT/IsJXRBVhn6gEGSF4AQ2Y1sIXIn4Bi
C06rqjh0ougcUj9EO45xRo1J/N1F2sJs340hv2KpeOHmoozcptnrw7Z6PcWSCdxw
XV4QMrEm6uFRAoIBAC4qcoENQZbnfpZFzeByMyS7V5bVZm3SfC2QzuI2ub7V5TBF
9PLOvyP7tBSRCPa0kJpR47GA68r4H+DJkhrX5beYQjDramHERZrKbvvy97qK+SUx
VPsOcYezflyzRbgtyPHyQr62CnbkUBEUhI/3lqAMkl1Q4quRpXU5isFNNCPhyCGP
YD5h1KylKllW5HilR/dsUswZFRWA/fuEMIjVxqQdhXqvhpWhZ0zIg3/LmNvqig9M
K55WIV8PPLFNQZd+yRFfA1fiMbss7kFD6ytcFs9VLNRQSLbAD45HPQ9I1NnBT9Td
moXtguxrYqT+U29A1Ne3R7RYMatrW5Shpsonl98CggEADWdHo80Gnzudge4G9pZL
Zka/2j/YfrJll/TOw/gYTc3CLe0cyh7165b0LRSZB52ail/8vvJMAYIp393D4nFa
YGejyW3yfBx7iIrn9Fj/vwszk+RunW+xXvgmv1PPEhPlRHuxabi/z1iSpt0Q8jBm
ad26Q0HCVF4vIwoMITjlEzDQvxeHvszLMXYWtJG1sCXWizfDnYwQv4bXeiIy61i9
JFIfNQHSFuSOsnTxES7fLkb/7Jw6b9QTOlt7D8fJb+j/m/7u/wIIN+uYlNGR/5MN
BXggM8RbnnbPK5RZl5RLAVFA/3yR6KdM7pm5/Xd5lft+UdMo4nCFsltiqlw7rlz8
0QKCAQEAki49Tp3AUxWRKRQSAlsrR59XaZGa+ahMMk4OBDjBqFxU2ce3+0VoRq0y
P7yXIDhaWelcmvTWXScMvshU1fR/+G98P5CJBJv+6++/0EHw7yfvLOH9MmiUAqTi
wez1+2zy5aNYRfEGtTPyZNhXjZLHNyoUFBPpDNjquAk9lui6gPfkzm4rkUgrkt2G
r7GV/zezeHgziq5SMMJ4LxfEXK9jZjedIctte8USbeI5OvOzpa3Q653xyt8Mqovv
WDWTC7bOqY/Cm/IGZdFI3sBIx4/pOkxG8Hd27goE3P/WEDIqWn9IO4MBnKFAU5Ja
HxBygz9UGefgaCHVpz8yIac4OSZPtQ==
-----END PRIVATE KEY-----";
    j1.info.crt = "-----BEGIN CERTIFICATE-----
MIIFeDCCA2CgAwIBAgIJALddqPgiNHmiMA0GCSqGSIb3DQEBCwUAMFExCzAJBgNV
BAYTAlVTMQ8wDQYDVQQIDAZEZW5pYWwxFDASBgNVBAcMC1NwcmluZ2ZpZWxkMQww
CgYDVQQKDANEaXMxDTALBgNVBAMMBHNlbGYwHhcNMTcxMjEwMTQwODMwWhcNMTgw
MTA5MTQwODMwWjBRMQswCQYDVQQGEwJVUzEPMA0GA1UECAwGRGVuaWFsMRQwEgYD
VQQHDAtTcHJpbmdmaWVsZDEMMAoGA1UECgwDRGlzMQ0wCwYDVQQDDARzZWxmMIIC
IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAts+9wWJWj7OOZw5qG7abhyga
ulkH7xLvXO4mhSg+rE4StI0r6dSE1tR+tPzzEjA2PZRvZd2wK2JuigBqn5SGUpJl
+58enMU++g9qbikD8hv57JPKcQb3235oBbPBlfp7cakR+kYLpCMjMwrAOz8gOYFm
4ZvQcmznoWhf8I8U8c1ph5ePH6bEfq+Gp5iUADFitlITFYI3j0hiKMWj06Qjm7kn
cWMz92mYuOM/l6APTyd2OeEvuCsHifmPRhJ60amSSXhMWt5jo1z/bmQfY/l7SdUQ
qqNbz035tf5ZW0Oz+ClWVJIchhav6K0uxqKDHZFf1ccZ/ZOZy3I7t1RFHqsvszMD
oOxGi2tGTmqtzwLKaKlvpD6SxDzYKk/11dWaDxyd/48aAZJ6wZ6rYgPvOVjOcZuS
zDwAm380uFo3iQKnMj4svKZpvJT3NDopmoExkTyViuJqRhNdgXf6V6YoezkWsJ4V
+TIVMIsNIC64jY+taPq/piSVm5/W+kxyNQ5+BoHp7e77aSlz9IKO3GWrIFxoPIhF
GpvUK1878lH6/qo5kUfXOQKem5Gog98xiUohKnDh0Q9lVsjg7bwputyFlIAXtH1h
e7cntgcpN1EnmnXxIyT/PLEg6iDn0/7k25fvqhcO+xEiuI/UUnQlcGCb6Kcia12l
nygIbvqL52+8VZttsvMCAwEAAaNTMFEwHQYDVR0OBBYEFLI0o0LT6C01zqhTirbX
+GJ5RHKsMB8GA1UdIwQYMBaAFLI0o0LT6C01zqhTirbX+GJ5RHKsMA8GA1UdEwEB
/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggIBABx+1Ba4sNdOA4KWEj8HuUHGhwnd
qex52fQzVdKirMDNNJKaUk+p0EePuz/wgTpBVCAhX/l5Kdns71UzVd1lJFG2fgLy
O8UV4GKFgeiF8//QfzNVY+CokvQEHuKu4ojTUI8n7oBMIVGs60tnTgGR4en07Ojh
lf8W3XwD8+VubE/VrIIBvH4UDtc7QtNHgGjTkB7XaBJF2ZPfJcjoB7Zboqb3IXz0
myIeJM9YMHVCwCdqGL9+8/9Nq5kzgatyYoMKdAFDWhceMIvlG9/GIMFhUUTwXepJ
Kh3aWAI1CrOjDHhirzZ+d65fNJEZmzv2lc5UknWmJJWSem1G5MXRzarx2vZIeVw2
eC7njugtNY5zZ4kxcxCKTiwBXS7rRhnS7rNXUxzp0i2u0AR/S/r0D+SG7q/YlWtW
UZ5iZf9oqJf/MmyFVNkvwHo/Nv0Ps7iqPIUaXxnim0hn6Wxpni+2SCh1Mpf9r8MZ
RQJDiISfGys+jDrAcOrlKvNLEOzDBDpDfaH7Z3tx3A9WdY+1IoclNNh1qie7r/GX
qLwGbSzrfB3+QYBQhguXWmC7MH+BwcgcNUVChlBYM+xwNwdKr4wb7YjbgBVIrQoh
thnjPSlqLCnOwD2z95HtA5vYK3QQqlvvRcQ8rCIg8Yc3SNSexfV1/ByErXSpbdBJ
f7REu8EKldYyWHIR
-----END CERTIFICATE-----";

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    auto j2 = sm2.addInProcJunction(junctionId);
    j2.info.encrypting = true;
    j2.key = "-----BEGIN PRIVATE KEY-----
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
Ci1ZywV5czGuFGBOcRpaSLtxsC3DSHE=
-----END PRIVATE KEY-----";
    j2.info.crt = "-----BEGIN CERTIFICATE-----
MIIFgjCCA2qgAwIBAgIBADANBgkqhkiG9w0BAQsFADBPMQswCQYDVQQGEwJVUzEP
MA0GA1UECAwGRGVuaWFsMRQwEgYDVQQHDAtTcHJpbmdmaWVsZDEMMAoGA1UECgwD
RGlzMQswCQYDVQQDDAJjYTAeFw0xNzEyMTAxNDA4MzFaFw0xODEyMTAxNDA4MzFa
MD0xCzAJBgNVBAYTAlVTMQ8wDQYDVQQIDAZEZW5pYWwxDDAKBgNVBAoMA0RpczEP
MA0GA1UEAwwGc2lnbmVkMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
5I92d1z3NE/O91mVCLvCEFPzL1OLhzA5/Fzbc4Zf9UcL3MLZBFyqypjV0R90dqd5
YtZ8m4yocUyw0x5E5k3HAfKAB2KNIE7kjopBgl1759pVL9kukjqCNaZxYTkKevdg
wHogVvUvEEoaQ14ZaPWy3uwC5qZbyr8eKpXEr3SwjgJQTuelQPCsZ0uy5wdwFlRT
BZ3JVdpIGcPHr8fAVkjeiVuCTGjysOg34VC3Sp6X51brGOaQ/zY2s8vKXxeZH1O/
qW6qZ+zVke4zjyIl6Hcj/XtobEA9za9wPlYbTjKSRJl1P9U6+qRwWaMMTaPFHbeX
AQ5jo/1ksbQNmvKtWMiLFoauM6k/ndXqGgoks1fjybQhurV3a7R9dbWjOjqTrgOq
XIPyORuWuIjUWbSJYhckHUUBTBu8XqL6EjSo6AF3My66PpRTA52QdjyMtYYfH8Sw
VnY13cwXLt+ZWBZQ59WwqUThY7WjHMosnKyqBq31zIi88yveFbqv8tMjkI/QHKGd
RqDK0ScJAgdjzoBDzVY0bttOfQcyj5oeGAwt2THW01GeWf0yWfm4ul1EcxIpNIVW
dlUdek20adScyRwrxtyhhIupd6xDE2V1ikDTEUDt/4+6m1t955ABCcAuHJRf9gT5
i5wnRJUCU4WXNsnQlVen1KAuz5CQFAYlNJe8X/nWbT8CAwEAAaN7MHkwCQYDVR0T
BAIwADAsBglghkgBhvhCAQ0EHxYdT3BlblNTTCBHZW5lcmF0ZWQgQ2VydGlmaWNh
dGUwHQYDVR0OBBYEFK1LqNbKpCaSAmuIv+zbBivjNvzqMB8GA1UdIwQYMBaAFLzS
Rti88fE1Y+iDL43gYxt5y6NPMA0GCSqGSIb3DQEBCwUAA4ICAQAs3N8+1cLBfG7C
ozB2+46PZ43kj+39Oo3GqRcigUa4nwdhX61dhQU09iKg1kaCzieFKI6jilXg5aTw
N62tEeyQSwQhNAc8G/XMQhTSAV2pCo6QbywZMTfqqXPH+DiH1X+etfrdBaG6YHlv
aFt7CO9A39UuVLoeWYbbCD3yoN4GrtFzvxWgaF0msy+Xde9GQVMXChrvPM+zVGF6
Sf5Wbdcv1CS7sHQ2aUknfQ1iae4CkL4NT4N64x+iFLQejDz7+Fp4d28Vrf+SpWDl
rvV4fVzSae8COpoP1VLXQ74vSpdcvDBlZ5FtxGVErGDPgugAmMTQgSWbLUWzadQC
oaky4WKr1nRtMbMSnVOYLGbzU6apvhWEskgJu4GkX3WUfaOihafG9S2LRGHC1ydX
Slqxn4NZDSagxN44UqXhYjw31Rf5WiWzUBCsFDFmBidlh6dg5hCXmnjHTkEFLcsE
88vSery9N3eApttWtE/k8r5xgE1kju0YclgoD7iiQi2HpKuByMGuKEAQDXQlUYH5
21J9+bZ8GQVozhzb4ysCewyNkCn5o/B3fHbK+4ahfNIXt6N1+htCuF6im9p0pw04
SmZvkIruvhoQ4eAWFTkqPbuepWGFSJlCzCko4926a0uBswdTaUj3bJfQD+xu9Eak
DuRfSEERdBHjYgvyYN3Q5tlWea/uvQ==
-----END CERTIFICATE-----";

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