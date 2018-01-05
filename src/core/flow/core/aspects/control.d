module flow.core.aspects.control;

private import flow.core.data;
private import flow.core.gears;
private import flow.core.util;

class EntitySpawnRefuseReason : Data { mixin _data;

    @field string tick;
    @field string reason;
}

// to protect aspect you wouldn't want to combine it with other aspects
class ControllingAspect : Data { mixin _data;

    @field EntityPtr[] trusted;

    @field string entitySpawnAnalyzer;
    @field EntitySpawnRefuseReason[] entitySpawnRefuseReasons;

    @field string junctionAttachAnalyzer;
    @field EntitySpawnRefuseReason[] junctionAttachRefuseReasons;
}

bool trusts(ControllingAspect a, EntityPtr e) {
    import std.algorithm.searching : any;
    
    return a.trusted.any!((t) => t == e);
}

class SpaceFreezeReq : Req { mixin _req; }

class SpaceFreezeTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!SpaceFreezeReq;

        // only if signal source is trusted
        if(s !is null && a.trusts(s.src)) {
            this.invoke(fqn!SpaceFreezeSystemTick);
        }
    }
}

class SpaceStoreReq : Req { mixin _req; }

class SpaceStoreTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!SpaceStoreReq;

        // only if signal source is trusted
        if(s !is null && a.trusts(this.trigger.src)) {
            this.invoke(fqn!SpaceStoreSystemTick);
        }
    }
}

class EntitySpawnReq : Req { mixin _req;
    @field EntityMeta data;
}

class EntitySpawnTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntitySpawnReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src))
                this.invoke(fqn!NullEntitySpawnAnalyzeTick);
            else this.invoke(fqn!RefusedEntitySpawnTick);
        }
    }
}

class NullEntitySpawnAnalyzeTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntitySpawnReq;

        if(s.data !is null)
            this.invoke(a.entitySpawnAnalyzer != string.init
                ? a.entitySpawnAnalyzer
                : fqn!AcceptEntitySpawnTick);
        else
            this.invoke(fqn!RefusedEntitySpawnTick);
    }
}

class RefusedEntitySpawnRep : Rep { mixin _rep;
    @field string reason;
}

class RefusedEntitySpawnTick : Tick {
    override void run() {
        import std.algorithm.iteration : filter;

        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntitySpawnReq;
        auto i = new RefusedEntitySpawnRep(s);

        switch(this.previous.type) {
            case fqn!EntitySpawnTick:
                i.reason = "source is not trusted";
                break;
            case fqn!NullEntitySpawnAnalyzeTick:
                i.reason = "invalid metadata";
                break;
            default:
                auto r = a.entitySpawnRefuseReasons.filter!((r) => r.tick == this.previous.type);
                if(r.empty)
                    i.reason = this.previous.type;
                else i.reason = r.front.reason;
        }

        this.send(i, s.src);
    }
}

class EntitySpawnedRep : Rep { mixin _rep; }

class AcceptEntitySpawnTick : Tick {
    override void run() {
        auto s = this.trigger.as!EntitySpawnReq;

        try {
            this.spawn(s.data);
        } catch(TickException exc) {
            auto i = new RefusedEntitySpawnRep(s);
            i.reason = exc.msg;
            this.send(i, s.src);
        }
        this.send(new EntitySpawnedRep(s), s.src);
    }
}

class EntityKillReq : Req { mixin _req;
    @field EntityPtr ptr;
}

class RefusedEntityKillRep : Rep { mixin _rep;
    @field string reason;
}

class EntityKilledRep : Rep { mixin _rep; }

class EntityKillTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityKillReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.kill(s.ptr);
                    this.send(new EntityKilledRep(s), s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityKillRep(s);
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityKillRep(s);
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class JunctionAttachReq : Req { mixin _req;
    @field JunctionMeta data;
}

class JunctionAttachTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!JunctionAttachReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src))
                this.invoke(fqn!NullJunctionAttachAnalyzeTick);
            else this.invoke(fqn!RefusedJunctionAttachTick);
        }
    }
}

class NullJunctionAttachAnalyzeTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!JunctionAttachReq;

        if(s.data !is null)
            this.invoke(a.junctionAttachAnalyzer != string.init
                ? a.junctionAttachAnalyzer
                : fqn!AcceptJunctionAttachTick);
        else
            this.invoke(fqn!RefusedJunctionAttachTick);
    }
}

class RefusedJunctionAttachRep : Rep { mixin _rep;
    @field string reason;
}

class RefusedJunctionAttachTick : Tick {
    override void run() {
        import std.algorithm.iteration : filter;

        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!JunctionAttachReq;
        auto i = new RefusedJunctionAttachRep(s);

        switch(this.previous.type) {
            case fqn!JunctionAttachTick:
                i.reason = "source is not trusted";
                break;
            case fqn!NullJunctionAttachAnalyzeTick:
                i.reason = "invalid metadata";
                break;
            default:
                auto r = a.junctionAttachRefuseReasons.filter!((r) => r.tick == this.previous.type);
                if(r.empty)
                    i.reason = this.previous.type;
                else i.reason = r.front.reason;
        }

        this.send(i, s.src);
    }
}

class JunctionAttachedRep : Rep { mixin _rep; }

class AcceptJunctionAttachTick : Tick {
    override void run() {
        auto s = this.trigger.as!JunctionAttachReq;

        try {
            this.attach(s.data);
        } catch(TickException exc) {
            auto i = new RefusedJunctionAttachRep(s);
            i.reason = exc.msg;
            this.send(i, s.src);
        }
        this.send(new JunctionAttachedRep(s), s.src);
    }
}

class JunctionDetachReq : Req { mixin _req;
    private import std.uuid : UUID;

    @field UUID id;
}

class RefusedJunctionDetachRep : Rep { mixin _rep;
    @field string reason;
}

class JunctionDetachedRep : Rep { mixin _rep; }

class JunctionDetachTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!JunctionDetachReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.detach(s.id);
                    this.send(new JunctionDetachedRep(s), s.src);
                } catch(TickException exc) {
                    auto i = new RefusedJunctionDetachRep(s);
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedJunctionDetachRep(s);
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityMetricsReq : Req { mixin _req;
    @field EntityPtr ptr;
}

class RefusedEntityMetricsRep : Rep { mixin _rep;
    @field string reason;
}

class EntityMetricsRep : Rep { mixin _rep;
    @field SystemState state;
    @field ulong count;
    @field string fsmeta;
    @field string fsroot;
    @field Damage[] damages;
}

class EntityMetricsTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityMetricsReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    auto ctrl = this.get(s.ptr);
                    auto i = new EntityMetricsRep(s);
                    i.state = ctrl.state;
                    i.count = ctrl.count;
                    i.fsmeta = ctrl.fsmeta;
                    i.fsroot = ctrl.fsroot;
                    i.damages = ctrl.damages;
                    this.send(i, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityMetricsRep(s);
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityMetricsRep(s);
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityTickReq : Req { mixin _req;
    @field EntityPtr ptr;
}

class RefusedEntityTickRep : Rep { mixin _rep;
    @field string reason;
}

class EntityTickingRep : Rep { mixin _rep; }

class EntityTickTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityTickReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.get(s.ptr).tick();
                    this.send(new EntityTickingRep(s), s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityTickRep(s);
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityTickRep(s);
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityFreezeReq : Req { mixin _req;
    @field EntityPtr ptr;
}

class RefusedEntityFreezeRep : Rep { mixin _rep;
    @field string reason;
}

class EntityFrozenRep : Rep { mixin _rep; }

class EntityFreezeTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityFreezeReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.get(s.ptr).freeze();
                    this.send(new EntityFrozenRep(s), s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityFreezeRep(s);
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityFreezeRep(s);
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityStoreReq : Req { mixin _req;
    @field EntityPtr ptr;
}

class RefusedEntityStoreRep : Rep { mixin _rep;
    @field string reason;
}

class EntityStoredRep : Rep { mixin _rep; }

class EntityStoreTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityStoreReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.get(s.ptr).store();
                    this.send(new EntityStoredRep(s), s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityStoreRep(s);
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityStoreRep(s);
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntitySnapReq : Req { mixin _req;
    @field EntityPtr ptr;
}

class RefusedEntitySnapRep : Rep { mixin _rep;
    @field string reason;
}

class EntitySnapRep : Rep { mixin _rep;
    @field EntityMeta data;
}

class EntitySnapTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntitySnapReq;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    auto e = this.get(s.ptr);
                    e.freeze();
                    auto i = new EntitySnapRep(s);
                    i.data = e.snap();
                    e.tick();
                    this.send(i, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntitySnapRep(s);
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntitySnapRep(s);
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

ControllingAspect addControllingAspect(EntityMeta em,
    EntityPtr[] trusted,
    string entitySpawnAnalyzer = string.init,
    EntitySpawnRefuseReason[] entitySpawnRefuseReasons = null,
    string junctionAttachAnalyzer = string.init,
    EntitySpawnRefuseReason[] junctionAttachRefuseReasons = null
) {
    auto a = new ControllingAspect; em.aspects ~= a;
    a.trusted = trusted;
    a.entitySpawnAnalyzer = entitySpawnAnalyzer;
    a.entitySpawnRefuseReasons = entitySpawnRefuseReasons;
    a.junctionAttachAnalyzer = junctionAttachAnalyzer;
    a.junctionAttachRefuseReasons = junctionAttachRefuseReasons;
    em.addReceptor(fqn!SpaceFreezeReq, fqn!SpaceFreezeTick, true);
    em.addReceptor(fqn!SpaceStoreReq, fqn!SpaceStoreTick, true);
    em.addReceptor(fqn!EntitySpawnReq, fqn!EntitySpawnTick, true);
    em.addReceptor(fqn!EntityKillReq, fqn!EntityKillTick, true);
    em.addReceptor(fqn!JunctionAttachReq, fqn!JunctionAttachTick, true);
    em.addReceptor(fqn!JunctionDetachReq, fqn!JunctionDetachTick, true);
    em.addReceptor(fqn!EntityMetricsReq, fqn!EntityMetricsTick, true);
    em.addReceptor(fqn!EntityTickReq, fqn!EntityTickTick, true);
    em.addReceptor(fqn!EntityFreezeReq, fqn!EntityFreezeTick, true);
    em.addReceptor(fqn!EntityStoreReq, fqn!EntityStoreTick, true);
    em.addReceptor(fqn!EntitySnapReq, fqn!EntitySnapTick, true);

    return a;
}

version(unittest) {
    class TestControllerAspect : Data { mixin _data;
        @field Unicast signal;
        @field EntityPtr controller;
        @field Data response;
    }

    class TestControllerTick : Tick {
        override void run() {
            auto a = this.aspect!TestControllerAspect;

            if(this.trigger is null)
                this.send(a.signal, a.controller);
            else if(this.trigger !is null)
                a.response = this.trigger;
        }
    }
}

unittest { test.header("aspects.control: freeze space; trusted sender");
    import core.thread;
    import flow.core.util;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);

    auto tca = new TestControllerAspect;
    tca.signal = new SpaceFreezeReq;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    assert(spc.state == SystemState.Frozen, "space didn't freeze");
test.footer(); }

unittest { test.header("aspects.control: freeze space; untrusted sender");
    import core.thread;
    import flow.core.util;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted

    auto tca = new TestControllerAspect;
    tca.signal = new SpaceFreezeReq;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    assert(spc.state != SystemState.Frozen, "space froze even requester isn't trusted");
test.footer(); }

unittest { test.header("aspects.control: store space; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);

    auto tca = new TestControllerAspect;
    tca.signal = new SpaceStoreReq;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("requesting").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    assert(fsmeta.exists, "space wasn't stored");
test.footer(); }

unittest { test.header("aspects.control: store space; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted

    auto tca = new TestControllerAspect;
    tca.signal = new SpaceStoreReq;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("requesting").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    assert(!fsmeta.exists, "space stored even requester wasn't trusted");
test.footer(); }

unittest { test.header("aspects.control: spawn entity; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);

    auto tca = new TestControllerAspect;
    tca.signal = new EntitySpawnReq;
    tca.signal.as!EntitySpawnReq.data = createEntity("spawned");
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntitySpawnedRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySpawnRep, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("spawned") !is null, "entity wasn't spawned");
    assert(ra.response.as!RefusedEntitySpawnRep is null, "spawn was refused");
    assert(ra.response.as!EntitySpawnedRep !is null, "spawn wasn't confirmed");
test.footer(); }

unittest { test.header("aspects.control: spawn entity; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted

    auto tca = new TestControllerAspect;
    tca.signal = new EntitySpawnReq;
    tca.signal.as!EntitySpawnReq.data = createEntity("spawned");
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntitySpawnedRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySpawnRep, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("spawned") is null, "entity spawned even requester wasn't trusted");
    assert(ra.response.as!EntitySpawnedRep is null, "spawn was confirmed");
    assert(ra.response.as!RefusedEntitySpawnRep !is null, "spawn wasn't refused");
test.footer(); }

unittest { test.header("aspects.control: kill entity; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto kem = sm.addEntity("killing");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityKillReq;
    tca.signal.as!EntityKillReq.ptr = kem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntityKilledRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityKillRep, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("killing") is null, "entity wasn't killed");
    assert(ra.response.as!RefusedEntityKillRep is null, "kill was refused");
    assert(ra.response.as!EntityKilledRep !is null, "kill wasn't confirmed");
test.footer(); }

unittest { test.header("aspects.control: kill entity; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto kem = sm.addEntity("killing");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted

    auto tca = new TestControllerAspect;
    tca.signal = new EntityKillReq;
    tca.signal.as!EntityKillReq.ptr = kem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntityKilledRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityKillRep, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("killing") !is null, "entity killed even requester wasn't trusted");
    assert(ra.response.as!EntityKilledRep is null, "kill was confirmed");
    assert(ra.response.as!RefusedEntityKillRep !is null, "kill wasn't refused");
test.footer(); }

unittest { test.header("aspects.control: attach junction; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;
    import std.range;
    import std.uuid;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);

    auto tca = new TestControllerAspect;
    tca.signal = new JunctionAttachReq;
    tca.signal.as!JunctionAttachReq.data = sm.createInProcJunction(randomUUID);
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!JunctionAttachedRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedJunctionAttachRep, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    auto nsm = spc.snap;
    assert(!nsm.junctions.empty, "junction wasn't attached");
    assert(ra.response.as!JunctionAttachedRep !is null, "junction attach wasn't confirmed");
    assert(ra.response.as!RefusedJunctionAttachRep is null, "junction attach was refused");
test.footer(); }

unittest { test.header("aspects.control: attach junction; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;
    import std.range;
    import std.uuid;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]);

    auto tca = new TestControllerAspect;
    tca.signal = new JunctionAttachReq;
    tca.signal.as!JunctionAttachReq.data = sm.createInProcJunction(randomUUID);
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!JunctionAttachedRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedJunctionAttachRep, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    auto nsm = spc.snap;
    assert(nsm.junctions.empty, "junction was attached");
    assert(ra.response.as!RefusedJunctionAttachRep !is null, "junction attach wasn't refused");
    assert(ra.response.as!JunctionAttachedRep is null, "junction attach was confirmed");
test.footer(); }

unittest { test.header("aspects.control: detach junction; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;
    import std.range;
    import std.uuid;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto jm = sm.addInProcJunction(randomUUID);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);

    auto tca = new TestControllerAspect;
    tca.signal = new JunctionDetachReq;
    tca.signal.as!JunctionDetachReq.id = jm.id;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!JunctionDetachedRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedJunctionDetachRep, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    auto nsm = spc.snap;
    assert(nsm.junctions.empty, "junction wasn't detached");
    assert(ra.response.as!JunctionDetachedRep !is null, "junction detach wasn't confirmed");
    assert(ra.response.as!RefusedJunctionDetachRep is null, "junction detach was refused");
test.footer(); }

unittest { test.header("aspects.control: entity metrics; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);
    rem.addReceptor(fqn!EntityMetricsRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityMetricsRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityMetricsReq;
    tca.signal.as!EntityMetricsReq.ptr = rem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityMetricsRep is null, "entity metrics were refused");
    assert(ra.response.as!EntityMetricsRep !is null, "entity metrics were not delivered");
test.footer(); }

unittest { test.header("aspects.control: entity metrics; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted
    rem.addReceptor(fqn!EntityMetricsRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityMetricsRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityMetricsReq;
    tca.signal.as!EntityMetricsReq.ptr = rem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityMetricsRep is null, "entity metrics delivered");
    assert(ra.response.as!RefusedEntityMetricsRep !is null, "entity metrics were not refused");
test.footer(); }

unittest { test.header("aspects.control: entity tick; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto tem = sm.addEntity("ticking");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);
    rem.addReceptor(fqn!EntityTickingRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityTickRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityTickReq;
    tca.signal.as!EntityTickReq.ptr = tem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();
    spc.get("ticking").freeze();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityTickRep is null, "tick was refused");
    assert(ra.response.as!EntityTickingRep !is null, "tick wasn't confirmed");
    assert(spc.get("ticking").state == SystemState.Ticking, "entity wasn't made ticking");
test.footer(); }

unittest { test.header("aspects.control: entity tick; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto tem = sm.addEntity("ticking");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted
    rem.addReceptor(fqn!EntityTickingRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityTickRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityTickReq;
    tca.signal.as!EntityTickReq.ptr = tem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();
    spc.get("ticking").freeze();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityTickingRep is null, "tick was confirmed");
    assert(ra.response.as!RefusedEntityTickRep !is null, "tick wasn't refused");
    assert(spc.get("ticking").state != SystemState.Ticking, "entity was made ticking");
test.footer(); }

unittest { test.header("aspects.control: entity freeze; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto fem = sm.addEntity("freezing");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);
    rem.addReceptor(fqn!EntityFrozenRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityFreezeRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityFreezeReq;
    tca.signal.as!EntityFreezeReq.ptr = fem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityFreezeRep is null, "freeze was refused");
    assert(ra.response.as!EntityFrozenRep !is null, "freeze wasn't confirmed");
    assert(spc.get("freezing").state == SystemState.Frozen, "entity wasn't frozen");
test.footer(); }

unittest { test.header("aspects.control: entity freeze; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto fem = sm.addEntity("freezing");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted
    rem.addReceptor(fqn!EntityFrozenRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityFreezeRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityFreezeReq;
    tca.signal.as!EntityFreezeReq.ptr = fem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityFrozenRep is null, "freeze was confirmed");
    assert(ra.response.as!RefusedEntityFreezeRep !is null, "freeze wasn't refused");
    assert(spc.get("freezing").state != SystemState.Frozen, "entity was frozen");
test.footer(); }

unittest { test.header("aspects.control: entity store; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto sem = sm.addEntity("storing");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);
    rem.addReceptor(fqn!EntityStoredRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityStoreRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityStoreReq;
    tca.signal.as!EntityStoreReq.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("storing").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityStoreRep is null, "store was refused");
    assert(ra.response.as!EntityStoredRep !is null, "store wasn't confirmed");
    assert(fsmeta.exists, "entity wasn't stored");
test.footer(); }

unittest { test.header("aspects.control: entity store; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto sem = sm.addEntity("storing");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted
    rem.addReceptor(fqn!EntityStoredRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityStoreRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityStoreReq;
    tca.signal.as!EntityStoreReq.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("storing").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityStoredRep is null, "freeze was confirmed");
    assert(ra.response.as!RefusedEntityStoreRep !is null, "freeze wasn't refused");
    assert(!fsmeta.exists, "entity was stored");
test.footer(); }

unittest { test.header("aspects.control: entity snap; trusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto sem = sm.addEntity("snapping");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([rem.ptr]);
    rem.addReceptor(fqn!EntitySnapRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySnapRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntitySnapReq;
    tca.signal.as!EntitySnapReq.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntitySnapRep is null, "snap was refused");
    assert(ra.response.as!EntitySnapRep !is null, "snap wasn't confirmed");
    assert(ra.response.as!EntitySnapRep.data !is null, "snap wasn't in response");
test.footer(); }

unittest { test.header("aspects.control: entity snap; untrusted sender");
    import core.thread;
    import flow.core.util;
    import std.path, std.file;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    auto spcDomain = "spc.test.control.aspects.core.flow";

    auto sm = createSpace(spcDomain);
    auto cem = sm.addEntity("controlling");
    auto sem = sm.addEntity("snapping");
    auto rem = sm.addEntity("requesting");
    cem.addControllingAspect([]); // << no trusted
    rem.addReceptor(fqn!EntitySnapRep, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySnapRep, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntitySnapReq;
    tca.signal.as!EntitySnapReq.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntitySnapRep is null, "snap was confirmed");
    assert(ra.response.as!RefusedEntitySnapRep !is null, "snap wasn't refused");
test.footer(); }