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

class SpaceFreezeRequest : Unicast { mixin _data; }

class SpaceFreezeTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!SpaceFreezeRequest;

        // only if signal source is trusted
        if(s !is null && a.trusts(s.src)) {
            this.invoke(fqn!SpaceFreezeSystemTick);
        }
    }
}

class SpaceStoreRequest : Unicast { mixin _data; }

class SpaceStoreTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!SpaceStoreRequest;

        // only if signal source is trusted
        if(s !is null && a.trusts(this.trigger.src)) {
            this.invoke(fqn!SpaceStoreSystemTick);
        }
    }
}

class EntitySpawnRequest : Unicast { mixin _data;
    @field EntityMeta data;
}

class EntitySpawnTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntitySpawnRequest;

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
        auto s = this.trigger.as!EntitySpawnRequest;

        if(s.data !is null)
            this.invoke(a.entitySpawnAnalyzer != string.init
                ? a.entitySpawnAnalyzer
                : fqn!AcceptEntitySpawnTick);
        else
            this.invoke(fqn!RefusedEntitySpawnTick);
    }
}

class RefusedEntitySpawnInfo : Unicast { mixin _data;
    @field string reason;
}

class RefusedEntitySpawnTick : Tick {
    override void run() {
        import std.algorithm.iteration : filter;

        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntitySpawnRequest;
        auto i = new RefusedEntitySpawnInfo;

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

class EntitySpawnedInfo : Unicast { mixin _data; }

class AcceptEntitySpawnTick : Tick {
    override void run() {
        auto s = this.trigger.as!EntitySpawnRequest;

        try {
            this.spawn(s.data);
        } catch(TickException exc) {
            auto i = new RefusedEntitySpawnInfo;
            i.reason = exc.msg;
            this.send(i, s.src);
        }
        this.send(new EntitySpawnedInfo, s.src);
    }
}

class EntityKillRequest : Unicast { mixin _data;
    @field EntityPtr ptr;
}

class RefusedEntityKillInfo : Unicast { mixin _data;
    @field string reason;
}

class EntityKilledInfo : Unicast { mixin _data; }

class EntityKillTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityKillRequest;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.kill(s.ptr);
                    this.send(new EntityKilledInfo, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityKillInfo;
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityKillInfo;
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class JunctionAttachRequest : Unicast { mixin _data;
    @field JunctionMeta data;
}

class JunctionAttachTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!JunctionAttachRequest;

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
        auto s = this.trigger.as!JunctionAttachRequest;

        if(s.data !is null)
            this.invoke(a.junctionAttachAnalyzer != string.init
                ? a.junctionAttachAnalyzer
                : fqn!AcceptJunctionAttachTick);
        else
            this.invoke(fqn!RefusedJunctionAttachTick);
    }
}

class RefusedJunctionAttachInfo : Unicast { mixin _data;
    @field string reason;
}

class RefusedJunctionAttachTick : Tick {
    override void run() {
        import std.algorithm.iteration : filter;

        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!JunctionAttachRequest;
        auto i = new RefusedJunctionAttachInfo;

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

class JunctionAttachedInfo : Unicast { mixin _data; }

class AcceptJunctionAttachTick : Tick {
    override void run() {
        auto s = this.trigger.as!JunctionAttachRequest;

        try {
            this.attach(s.data);
        } catch(TickException exc) {
            auto i = new RefusedJunctionAttachInfo;
            i.reason = exc.msg;
            this.send(i, s.src);
        }
        this.send(new JunctionAttachedInfo, s.src);
    }
}

class JunctionDetachRequest : Unicast { mixin _data;
    private import std.uuid : UUID;

    @field UUID id;
}

class RefusedJunctionDetachInfo : Unicast { mixin _data;
    @field string reason;
}

class JunctionDetachedInfo : Unicast { mixin _data; }

class JunctionDetachTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!JunctionDetachRequest;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.detach(s.id);
                    this.send(new JunctionDetachedInfo, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedJunctionDetachInfo;
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedJunctionDetachInfo;
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityMetricsRequest : Unicast { mixin _data;
    @field EntityPtr ptr;
}

class RefusedEntityMetricsInfo : Unicast { mixin _data;
    @field string reason;
}

class EntityMetricsInfo : Unicast { mixin _data;
    @field SystemState state;
    @field size_t count;
    @field string fsmeta;
    @field string fsroot;
    @field Damage[] damages;
}

class EntityMetricsTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityMetricsRequest;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    auto ctrl = this.get(s.ptr);
                    auto i = new EntityMetricsInfo;
                    i.state = ctrl.state;
                    i.count = ctrl.count;
                    i.fsmeta = ctrl.fsmeta;
                    i.fsroot = ctrl.fsroot;
                    i.damages = ctrl.damages;
                    this.send(i, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityMetricsInfo;
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityMetricsInfo;
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityTickRequest : Unicast { mixin _data;
    @field EntityPtr ptr;
}

class RefusedEntityTickInfo : Unicast { mixin _data;
    @field string reason;
}

class EntityTickingInfo : Unicast { mixin _data; }

class EntityTickTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityTickRequest;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.get(s.ptr).tick();
                    this.send(new EntityTickingInfo, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityTickInfo;
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityTickInfo;
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityFreezeRequest : Unicast { mixin _data;
    @field EntityPtr ptr;
}

class RefusedEntityFreezeInfo : Unicast { mixin _data;
    @field string reason;
}

class EntityFrozenInfo : Unicast { mixin _data; }

class EntityFreezeTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityFreezeRequest;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.get(s.ptr).freeze();
                    this.send(new EntityFrozenInfo, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityFreezeInfo;
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityFreezeInfo;
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntityStoreRequest : Unicast { mixin _data;
    @field EntityPtr ptr;
}

class RefusedEntityStoreInfo : Unicast { mixin _data;
    @field string reason;
}

class EntityStoredInfo : Unicast { mixin _data; }

class EntityStoreTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntityStoreRequest;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    this.get(s.ptr).store();
                    this.send(new EntityStoredInfo, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntityStoreInfo;
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntityStoreInfo;
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

class EntitySnapRequest : Unicast { mixin _data;
    @field EntityPtr ptr;
}

class RefusedEntitySnapInfo : Unicast { mixin _data;
    @field string reason;
}

class EntitySnapInfo : Unicast { mixin _data;
    @field EntityMeta data;
}

class EntitySnapTick : Tick {
    override void run() {
        auto a = this.aspect!ControllingAspect;
        auto s = this.trigger.as!EntitySnapRequest;

        if(s !is null) {
            // only if signal source is trusted
            if(a.trusts(s.src)) {
                try {
                    auto e = this.get(s.ptr);
                    e.freeze();
                    auto i = new EntitySnapInfo;
                    i.data = e.snap();
                    e.tick();
                    this.send(i, s.src);
                } catch(TickException exc) {
                    auto i = new RefusedEntitySnapInfo;
                    i.reason = exc.msg;
                    this.send(i, s.src);
                }
            } else {
                auto i = new RefusedEntitySnapInfo;
                i.reason = "source is not trusted";
                this.send(i, s.src);
            }
        }
    }
}

void addControllingAspect(EntityMeta em,
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
    em.addReceptor(fqn!SpaceFreezeRequest, fqn!SpaceFreezeTick, true);
    em.addReceptor(fqn!SpaceStoreRequest, fqn!SpaceStoreTick, true);
    em.addReceptor(fqn!EntitySpawnRequest, fqn!EntitySpawnTick, true);
    em.addReceptor(fqn!EntityKillRequest, fqn!EntityKillTick, true);
    em.addReceptor(fqn!JunctionAttachRequest, fqn!JunctionAttachTick, true);
    em.addReceptor(fqn!JunctionDetachRequest, fqn!JunctionDetachTick, true);
    em.addReceptor(fqn!EntityMetricsRequest, fqn!EntityMetricsTick, true);
    em.addReceptor(fqn!EntityTickRequest, fqn!EntityTickTick, true);
    em.addReceptor(fqn!EntityFreezeRequest, fqn!EntityFreezeTick, true);
    em.addReceptor(fqn!EntityStoreRequest, fqn!EntityStoreTick, true);
    em.addReceptor(fqn!EntitySnapRequest, fqn!EntitySnapTick, true);
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
    tca.signal = new SpaceFreezeRequest;
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
    tca.signal = new SpaceFreezeRequest;
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
    tca.signal = new SpaceStoreRequest;
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
    tca.signal = new SpaceStoreRequest;
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
    tca.signal = new EntitySpawnRequest;
    tca.signal.as!EntitySpawnRequest.data = createEntity("spawned");
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntitySpawnedInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySpawnInfo, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("spawned") !is null, "entity wasn't spawned");
    assert(ra.response.as!RefusedEntitySpawnInfo is null, "spawn was refused");
    assert(ra.response.as!EntitySpawnedInfo !is null, "spawn wasn't confirmed");
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
    tca.signal = new EntitySpawnRequest;
    tca.signal.as!EntitySpawnRequest.data = createEntity("spawned");
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntitySpawnedInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySpawnInfo, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("spawned") is null, "entity spawned even requester wasn't trusted");
    assert(ra.response.as!EntitySpawnedInfo is null, "spawn was confirmed");
    assert(ra.response.as!RefusedEntitySpawnInfo !is null, "spawn wasn't refused");
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
    tca.signal = new EntityKillRequest;
    tca.signal.as!EntityKillRequest.ptr = kem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntityKilledInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityKillInfo, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("killing") is null, "entity wasn't killed");
    assert(ra.response.as!RefusedEntityKillInfo is null, "kill was refused");
    assert(ra.response.as!EntityKilledInfo !is null, "kill wasn't confirmed");
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
    tca.signal = new EntityKillRequest;
    tca.signal.as!EntityKillRequest.ptr = kem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!EntityKilledInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityKillInfo, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(spc.get("killing") !is null, "entity killed even requester wasn't trusted");
    assert(ra.response.as!EntityKilledInfo is null, "kill was confirmed");
    assert(ra.response.as!RefusedEntityKillInfo !is null, "kill wasn't refused");
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
    tca.signal = new JunctionAttachRequest;
    tca.signal.as!JunctionAttachRequest.data = sm.createInProcJunction(randomUUID);
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!JunctionAttachedInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedJunctionAttachInfo, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    auto nsm = spc.snap;
    assert(!nsm.junctions.empty, "junction wasn't attached");
    assert(ra.response.as!JunctionAttachedInfo !is null, "junction attach wasn't confirmed");
    assert(ra.response.as!RefusedJunctionAttachInfo is null, "junction attach was refused");
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
    tca.signal = new JunctionAttachRequest;
    tca.signal.as!JunctionAttachRequest.data = sm.createInProcJunction(randomUUID);
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!JunctionAttachedInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedJunctionAttachInfo, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    auto nsm = spc.snap;
    assert(nsm.junctions.empty, "junction was attached");
    assert(ra.response.as!RefusedJunctionAttachInfo !is null, "junction attach wasn't refused");
    assert(ra.response.as!JunctionAttachedInfo is null, "junction attach was confirmed");
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
    tca.signal = new JunctionDetachRequest;
    tca.signal.as!JunctionDetachRequest.id = jm.id;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);
    rem.addReceptor(fqn!JunctionDetachedInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedJunctionDetachInfo, fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    auto nsm = spc.snap;
    assert(nsm.junctions.empty, "junction wasn't detached");
    assert(ra.response.as!JunctionDetachedInfo !is null, "junction detach wasn't confirmed");
    assert(ra.response.as!RefusedJunctionDetachInfo is null, "junction detach was refused");
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
    rem.addReceptor(fqn!EntityMetricsInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityMetricsInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityMetricsRequest;
    tca.signal.as!EntityMetricsRequest.ptr = rem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityMetricsInfo is null, "entity metrics were refused");
    assert(ra.response.as!EntityMetricsInfo !is null, "entity metrics were not delivered");
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
    rem.addReceptor(fqn!EntityMetricsInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityMetricsInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityMetricsRequest;
    tca.signal.as!EntityMetricsRequest.ptr = rem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityMetricsInfo is null, "entity metrics delivered");
    assert(ra.response.as!RefusedEntityMetricsInfo !is null, "entity metrics were not refused");
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
    rem.addReceptor(fqn!EntityTickingInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityTickInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityTickRequest;
    tca.signal.as!EntityTickRequest.ptr = tem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();
    spc.get("ticking").freeze();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityTickInfo is null, "tick was refused");
    assert(ra.response.as!EntityTickingInfo !is null, "tick wasn't confirmed");
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
    rem.addReceptor(fqn!EntityTickingInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityTickInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityTickRequest;
    tca.signal.as!EntityTickRequest.ptr = tem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();
    spc.get("ticking").freeze();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityTickingInfo is null, "tick was confirmed");
    assert(ra.response.as!RefusedEntityTickInfo !is null, "tick wasn't refused");
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
    rem.addReceptor(fqn!EntityFrozenInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityFreezeInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityFreezeRequest;
    tca.signal.as!EntityFreezeRequest.ptr = fem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityFreezeInfo is null, "freeze was refused");
    assert(ra.response.as!EntityFrozenInfo !is null, "freeze wasn't confirmed");
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
    rem.addReceptor(fqn!EntityFrozenInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityFreezeInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityFreezeRequest;
    tca.signal.as!EntityFreezeRequest.ptr = fem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityFrozenInfo is null, "freeze was confirmed");
    assert(ra.response.as!RefusedEntityFreezeInfo !is null, "freeze wasn't refused");
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
    rem.addReceptor(fqn!EntityStoredInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityStoreInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityStoreRequest;
    tca.signal.as!EntityStoreRequest.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("storing").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntityStoreInfo is null, "store was refused");
    assert(ra.response.as!EntityStoredInfo !is null, "store wasn't confirmed");
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
    rem.addReceptor(fqn!EntityStoredInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntityStoreInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntityStoreRequest;
    tca.signal.as!EntityStoreRequest.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    auto fsmeta = spc.get("storing").fsmeta;
    if(fsmeta.exists) fsmeta.remove;
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntityStoredInfo is null, "freeze was confirmed");
    assert(ra.response.as!RefusedEntityStoreInfo !is null, "freeze wasn't refused");
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
    rem.addReceptor(fqn!EntitySnapInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySnapInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntitySnapRequest;
    tca.signal.as!EntitySnapRequest.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!RefusedEntitySnapInfo is null, "snap was refused");
    assert(ra.response.as!EntitySnapInfo !is null, "snap wasn't confirmed");
    assert(ra.response.as!EntitySnapInfo.data !is null, "snap wasn't in response");
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
    rem.addReceptor(fqn!EntitySnapInfo, fqn!TestControllerTick);
    rem.addReceptor(fqn!RefusedEntitySnapInfo, fqn!TestControllerTick);

    auto tca = new TestControllerAspect;
    tca.signal = new EntitySnapRequest;
    tca.signal.as!EntitySnapRequest.ptr = sem.ptr;
    tca.controller = cem.ptr;
    rem.aspects ~= tca;
    rem.addTick(fqn!TestControllerTick);

    auto spc = proc.add(sm);
    spc.tick();

    Thread.sleep(50.msecs);

    auto ra = spc.get("requesting").aspects[0].as!TestControllerAspect;
    assert(ra.response.as!EntitySnapInfo is null, "snap was confirmed");
    assert(ra.response.as!RefusedEntitySnapInfo !is null, "snap wasn't refused");
test.footer(); }