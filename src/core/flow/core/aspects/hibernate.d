module flow.core.aspects.hibernate;

private import core.time;
private import flow.core.data;
private import flow.core.gears;
private import flow.core.util;

class HibernatingAspect : Data { mixin _data;
    @field Duration delay;
    @field size_t last;
}

class CheckHibernateTick : Tick {
    override void run() {
        auto a = this.aspect!HibernatingAspect;

        if(a.delay != Duration.init || this.count == size_t.init) {
            auto cnt = this.count;
            
            if(cnt == a.last + 1) {
                this.invoke(fqn!EntityHibernateSystemTick);
                a.last = 0; // at freezing counter persists, here it is resetted
            } else {
                a.last = cnt;
                this.invoke(fqn!CheckHibernateTick, a.delay);
            }
        } // if delay is 0 or not in control stop
    }
}

void addHibernatingAspect(EntityMeta em, Duration d = 1.seconds) {
    import std.uuid : UUID;
    
    auto a = new HibernatingAspect; em.aspects ~= a;
    a.delay = d;
    auto tm = em.addTick(fqn!CheckHibernateTick, null, UUID.init, true);
}

unittest { test.header("aspects.hibernate: in control");
    import core.thread;
    import flow.core.util;
    import std.file : exists, remove;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.hibernate.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("controlling");
    em.addHibernatingAspect(2.msecs);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("controlling").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(20.msecs);

    assert(spc.get("controlling") is null, "entity didn't hibernate");
    assert(fsmeta.exists, "entity wasn't stored");

    spc.freeze();
test.footer(); }

unittest { test.header("aspects.hibernate: not in control");
    import core.thread;
    import flow.core.util;
    import std.file : exists, remove;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.hibernate.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("controlling");
    auto a = new HibernatingAspect; em.aspects ~= a;
    a.delay = 2.msecs;
    auto tm = em.addTick(fqn!CheckHibernateTick);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("controlling").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(20.msecs);

    assert(spc.get("controlling") !is null && spc.get("controlling").state != SystemState.Frozen, "entity hibernated or froze even tick wasn't in control");
    assert(!fsmeta.exists, "entity stored even tick wasn't in control");

    spc.freeze();
test.footer(); }