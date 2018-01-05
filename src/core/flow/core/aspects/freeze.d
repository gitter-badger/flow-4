module flow.core.aspects.freeze;

private import core.time;
private import flow.core.data;
private import flow.core.gears;
private import flow.core.util;

class FreezingAspect : Data { mixin _data;
    @field Duration delay;
    @field ulong last;
}

class CheckFreezeTick : Tick {
    override void run() {
        auto a = this.aspect!FreezingAspect;

        if(a.delay != Duration.init || this.count == size_t.init) {
            auto cnt = this.count;
            
            if(cnt == a.last + 1)
                this.invoke(fqn!EntityFreezeSystemTick);

            a.last = cnt;
            this.invoke(fqn!CheckFreezeTick, a.delay);
        } // if delay is 0 or not in control stop
    }
}

FreezingAspect addFreezingAspect(EntityMeta em, Duration d = 1.seconds) {
    import std.uuid : UUID;
    
    auto a = new FreezingAspect; em.aspects ~= a;
    a.delay = d;
    auto tm = em.addTick(fqn!CheckFreezeTick, null, UUID.init, true);
    
    return a;
}

unittest { test.header("aspects.freeze: in control");
    import core.thread;
    import flow.core.util;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.freeze.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("controlling");
    em.addFreezingAspect(2.msecs);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(10.msecs);

    assert(spc.get("controlling").state == SystemState.Frozen, "entity didn't freeze");

    spc.freeze();
test.footer(); }

unittest { test.header("aspects.freeze: not in control");
    import core.thread;
    import flow.core.util;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.freeze.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("controlling");
    auto a = new FreezingAspect; em.aspects ~= a;
    a.delay = 2.msecs;
    auto tm = em.addTick(fqn!CheckFreezeTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(10.msecs);

    assert(spc.get("controlling").state == SystemState.Ticking, "entity freezed even tick wasn't in control");

    spc.freeze();
test.footer(); }