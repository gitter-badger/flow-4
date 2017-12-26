module flow.core.aspects.store;

private import core.time;
private import flow.core.data;
private import flow.core.gears;
private import flow.core.util;

class StoringAspect : Data {
    mixin data;

    mixin field!(Duration, "delay");
    mixin field!(size_t, "last");
    mixin field!(bool, "lastStored");
}

class CheckStoreTick : Tick {
    override void run() {
        auto a = this.aspect!StoringAspect;

        if(a.delay != Duration.init || this.count == size_t.init) {
            auto cnt = this.count;
            //import std.stdio:writeln;writeln(a.last);
            
            if(cnt > a.last + (a.lastStored ? 2 : 1)) {
                this.invoke(fqn!EntityStoreSystemTick);
                a.lastStored = true;
            } else a.lastStored = false;

            a.last = cnt;
            this.invoke(fqn!CheckStoreTick, a.delay);
        } // if delay is 0 or not in control stop
    }
}

void addStoringAspect(EntityMeta em, Duration d = 1.seconds) {
    import std.uuid : UUID;
    
    auto a = new StoringAspect; em.aspects ~= a;
    a.delay = d;
    auto tm = em.addTick(fqn!CheckStoreTick, null, UUID.init, true);
}

unittest { test.header("aspects.store: in control");
    import core.thread;
    import flow.core.util;
    import std.file : exists, remove;
    import std.path : buildPath;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.store.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("controlling");
    em.addStoringAspect(2.msecs);

    // just for executing something else
    auto ta = new TestSendingAspect; em.aspects ~= ta;
    ta.dstEntity = "receiving";
    ta.dstSpace = spcDomain;
    em.addTick(fqn!UnicastSendingTestTick);

    auto spc = proc.add(sm);
    auto target = spc.get("controlling").target.buildPath("controlling");
    if(target.exists) target.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    assert(target.exists, "entity wasn't stored");

    spc.freeze();
test.footer(); }

unittest { test.header("aspects.store: not in control");
    import core.thread;
    import flow.core.util;
    import std.file : exists, remove;
    import std.path : buildPath;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.freeze.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("controlling");
    auto a = new StoringAspect; em.aspects ~= a;
    a.delay = 2.msecs;
    auto tm = em.addTick(fqn!CheckStoreTick);

    // just for executing something else
    auto ta = new TestSendingAspect; em.aspects ~= ta;
    ta.dstEntity = "receiving";
    ta.dstSpace = spcDomain;
    em.addTick(fqn!UnicastSendingTestTick);

    auto spc = proc.add(sm);
    auto target = spc.get("controlling").target.buildPath("controlling");
    if(target.exists) target.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    assert(!target.exists, "entity stored even tick wasn't in control");

    spc.freeze();
test.footer(); }