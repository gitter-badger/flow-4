module flow.core.gears.engine;

private import flow.core.data;
private import flow.core.gears.data;
private import flow.core.gears.proc;
private import flow.core.util;
private import std.uuid;

// https://d.godbolt.org/

enum SystemState {
    Frozen,
    Ticking
}

/// represents a definded change in systems information
abstract class Tick {
    private import core.time : Duration;
    private import flow.core.data : Data;
    private import std.datetime.systime : SysTime;

    private TickMeta meta;
    private Entity entity;
    
    private Job job;

    private Throwable thr;

    protected @property TickInfo info() {return this.meta.info !is null ? this.meta.info.clone : null;}
    protected @property Signal trigger() {return this.meta.trigger !is null ? this.meta.trigger.clone : null;}
    protected @property TickInfo previous() {return this.meta.previous !is null ? this.meta.previous.clone : null;}
    protected @property Data data() {return this.meta.data;}
    protected @property size_t count() {return this.meta.control ? this.entity.count : size_t.init;}

    /** context of hosting entity
    warning you have to sync it as reader when accessing it reading
    and as writer when accessing it writing */
    protected T aspect(T)(size_t i = 0) if(is(T:Data)) {return this.entity.get!T(i);}

    /// check if execution of tick is accepted
    @property bool accept() {return true;}

    /// predicted costs of tick (default=0)
    @property size_t costs() {return 0;}

    /// algorithm implementation of tick
    void run() {}

    /// exception handling implementation of tick
    void error(Throwable thr) {
        throw thr;
    }

    /// execute tick meant to be called by processor
    private void exec() {
        import std.datetime.systime : Clock;
        this.entity.count++;

        // run tick
        Log.msg(LL.FDebug, this.logPrefix~"running tick", this.meta);
        this.run();
        Log.msg(LL.FDebug, this.logPrefix~"finished tick", this.meta);
        
        // if everything was successful cleanup and process next
        this.meta.time = Clock.currStdTime;
        this.entity.put(this);

        // deregistering
        this.entity.execLock.reader.unlock();
    }

    private void catchError(Throwable thr) {
        Log.msg(LL.Info, this.logPrefix~"handling error", thr, this.meta);

        this.thr = thr;

        this.job = Job(&this.runError, &this.fatal);
        this.entity.space.proc.run(&this.job);
    }

    private void runError() {
        import std.datetime.systime : Clock;
        this.error(this.thr);

        Log.msg(LL.FDebug, this.logPrefix~"finished handling error", this.meta);

        // if everything was successful cleanup
        this.meta.time = Clock.currStdTime;
        this.entity.put(this);

        // deregistering
        this.entity.execLock.reader.unlock();
    }

    private void fatal(Throwable thr) {
        import std.datetime.systime : Clock;
        this.thr = thr;

        // if even handling exception failes notify that an error occured
        Log.msg(LL.Error, this.logPrefix~"handling error failed", thr);
        
        this.entity.damage(thr); // BOOM BOOM BOOM

        this.meta.time = Clock.currStdTime; // set endtime for informing pool
        this.entity.put(this);

        // deregistering
        this.entity.execLock.reader.unlock();
    }
    
    /// invoke tick
    protected bool invoke(string tick, Data data = null) {
        return this.invoke(tick, Duration.init, data);
    }

    /// invoke tick with delay
    protected bool invoke(string tick, SysTime schedule, Data data = null) {
        import std.datetime.systime : Clock;

        auto delay = schedule - Clock.currTime;

        if(delay.total!"hnsecs" > 0)
            return this.invoke(tick, delay, data);
        else
            return this.invoke(tick, data);
    }

    /// invoke tick with delay
    protected bool invoke(string tick, Duration delay, Data data = null) {
        import flow.core.gears.error : TickException;
        import std.datetime.systime : Clock;

        auto stdTime = Clock.currStdTime;
        if(this.meta.control || (tick != fqn!EntityFreezeSystemTick && tick != fqn!EntityStoreSystemTick)) {
            auto m = tick.createTickMeta(this.meta.info.group);

            // if this tick has control, pass it
            if(this.meta.control)
                m.control = true;

            m.time = stdTime + delay.total!"hnsecs";
            m.trigger = this.meta.trigger;
            m.previous = this.meta.info;
            m.data = data;

            bool a; { // check if there exists a tick for given meta and if it accepts the request
                auto t = this.entity.pop(m);
                scope(exit)
                    this.entity.put(t);
                a = t !is null && t.accept;
            }

            if(a) {
                this.entity.invoke(m);
                return true;
            } else return false;
        } else throw new TickException("tick is not in control");
    }

    /// gets the entity controller of a given entity located in common space
    protected EntityController get(EntityPtr entity) {
        import flow.core.gears.error : TickException;

        if(entity.space != this.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be controlled");
        else return this.get(entity.id);
    }

    private EntityController get(string e) {
        import flow.core.gears.error : TickException;

        if(this.meta.control) {
            if(this.entity.meta.ptr.id == e)
                throw new TickException("entity cannot controll itself using a controller only using system ticks");
            else return this.entity.space.get(e);
        } else throw new TickException("tick is not in control");
    }

    /// spawns a new entity in common space
    protected EntityController spawn(EntityMeta entity) {
        import flow.core.gears.error : TickException;

        if(this.meta.control)
            return this.entity.space.spawn(entity);
        else throw new TickException("tick is not in control");
    }

    /// kills a given entity in common space
    protected void kill(EntityPtr ptr) {
        import flow.core.gears.error : TickException;
        
        if(this.meta.control) {
            if(ptr.space != this.entity.space.meta.id)
                throw new TickException("an entity not belonging to own space cannot be killed");
            this.kill(ptr.id);
        } else throw new TickException("tick is not in control");
    }

    private void kill(string e) {
        import flow.core.gears.error : TickException;
        
        if(this.meta.control) {
            if(this.entity.meta.ptr.addr == e)
                throw new TickException("entity cannot kill itself");
            else
                this.entity.space.kill(e);
        } else throw new TickException("tick is not in control");
    }

    /// spawns a new entity in common space
    protected UUID attach(JunctionMeta junction) {
        import flow.core.gears.error : TickException;

        if(this.meta.control)
            return this.entity.space.attach(junction);
        else throw new TickException("tick is not in control");
    }

    protected void detach(UUID jid) {
        import flow.core.gears.error : TickException;
        
        if(this.meta.control) {
            this.entity.space.detach(jid);
        } else throw new TickException("tick is not in control");
    }

    /// registers a receptor for signal which invokes a tick
    protected void register(string signal, string tick) {
        import flow.core.gears.error : TickException;
        import flow.core.data : createData;
        
        auto s = createData(signal).as!Signal;
        if(s is null || createData(tick) is null)
            throw new TickException("can only register receptors for valid signals and ticks");

        this.entity.register(signal, tick);
    }

    /// deregisters an receptor for signal invoking tick
    protected void deregister(string signal, string tick) {
        this.entity.deregister(signal, tick);
    }

    /// send an unicast signal to a destination
    protected bool send(Unicast s, string entity, string space, UUID group = UUID.init) {
        auto eptr = new EntityPtr;
        eptr.id = entity;
        eptr.space = space;
        return this.send(s, eptr, group);
    }

    /// send an unicast signal to a destination
    protected bool send(Unicast s, EntityPtr e = null, UUID group = UUID.init) {
        import flow.core.gears.error : TickException;
        
        if(s is null)
            throw new TickException("cannot sand an empty unicast");

        if(e !is null) s.dst = e;

        if(s.dst is null || s.dst.id == string.init || s.dst.space == string.init)
            throw new TickException("unicast signal needs a valid destination(dst)");

        if(s.group == UUID.init)
            s.group = group == UUID.init ? this.meta.info.group : group;

        return this.entity.send(s);
    }

    /// send an anycast signal to spaces matching space pattern
    protected bool send(Anycast s, string dst = string.init, UUID group = UUID.init) {
        import flow.core.gears.error : TickException;
        
        if(dst != string.init) s.dst = dst;

        if(s.dst == string.init)
            throw new TickException("anycast signal needs a space pattern");

        if(s.group == UUID.init)
            s.group = group == UUID.init ? this.meta.info.group : group;

        return this.entity.send(s);
    }

    /// send an anycast signal to spaces matching space pattern
    protected bool send(Multicast s, string dst = string.init, UUID group = UUID.init) {
        import flow.core.gears.error : TickException;
        
        if(dst != string.init) s.dst = dst;

        if(s.dst == string.init)
            throw new TickException("multicast signal needs a space pattern");

        if(s.group == UUID.init)
            s.group = group == UUID.init ? this.meta.info.group : group;

        return this.entity.send(s);
    }

    package void dispose() {
        this.destroy;
    }
}

final class EntityFreezeSystemTick : Tick {}
final class EntityStoreSystemTick : Tick {}
final class SpaceFreezeSystemTick : Tick {}
final class SpaceStoreSystemTick : Tick {}

/// gets the prefix string of ticks for logging
string logPrefix(Tick t) {
    import std.conv : to;
    return "tick@entity("~t.entity.meta.ptr.addr~"): ";
}

/// gets the prefix string of junctions for logging
string logPrefix(Channel c) {
    import std.conv : to;
    return "channel("~c.own.meta.id.to!string~"->"~c.dst~"): ";
}

/// gets the prefix string of junctions for logging
string logPrefix(Junction j) {
    import std.conv : to;
    return "junction("~j.meta.id.to!string~"): ";
}

/// gets the prefix string of junctions for logging
string logPrefix(Space s) {
    import std.conv : to;
    return "space("~s.meta.id.to!string~"): ";
}

private TickMeta createTickMeta(string type, UUID group = UUID.init) {
    import flow.core.gears.data : TickMeta, TickInfo;
    import std.uuid : randomUUID;

    auto m = new TickMeta;
    m.info = new TickInfo;
    m.info.id = randomUUID;
    m.info.type = type;
    m.info.group = group == UUID.init ? randomUUID : group;

    return m;
}

/// hosts an entity construct
private class Entity : StateMachine!SystemState {
    private import core.sync.mutex : Mutex;
    private import core.sync.rwmutex : ReadWriteMutex;
    private import flow.core.data;
    
    Mutex _poolLock;
    Tick[][string] _pool;
    size_t count;

    ReadWriteMutex execLock; // counting tick executions
    ReadWriteMutex opLock; // counting async operations
     
    Space space;
    EntityMeta meta;
    EntityController control;

    Data[][TypeInfo] aspects;

    this(Space s, EntityMeta m) {
        super();

        this.execLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.opLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        this._poolLock = new Mutex;
        m.ptr.space = s.meta.id;
        this.meta = m;
        this.space = s;

        foreach(ref c; m.aspects)
            this.aspects[typeid(c)] ~= c;

        this.control = new EntityController(this);
    }

    Tick pop(TickMeta m) {
        import core.time : seconds;
        import std.datetime.systime : Clock;
        import std.range : empty, front, popFront;
        if(m !is null && m.info !is null) {
            synchronized(this._poolLock) {
                Tick t;
                if(m.info.type in this._pool
                && !this._pool[m.info.type].empty) { // clean up and then take first
                    while(_pool[m.info.type].length > 1
                    && _pool[m.info.type].front.meta.time + 1.seconds.total!"hnsecs" < Clock.currStdTime) {
                        this._pool[m.info.type].front.dispose();
                        this._pool[m.info.type].popFront;
                    }
                    
                    t = this._pool[m.info.type].front;
                    this._pool[m.info.type].popFront;
                } else { // create one which is added when released
                    t = Object.factory(m.info.type).as!Tick;
                    t.entity = this;
                }
                
                if(t !is null) {
                    t.meta = m;
                    t.meta.info.entity = this.meta.ptr.clone;

                    return t;
                }
            }
        }
        
        return null;
    }

    void put(Tick t) {
        synchronized(this._poolLock) {
            if(t.meta.info.type !in this._pool)
                this._pool[t.meta.info.type] = (Tick[]).init;
            
            this._pool[t.meta.info.type] ~= t;
        }
    }

    private void invoke(TickMeta next) {
        import std.parallelism : taskPool, task;

        this.opLock.reader.lock();
        taskPool.put(task((TickMeta nm){
            scope(exit) 
                this.opLock.reader.unlock();
            
            synchronized(this.lock.reader) { 
                if(this.state == SystemState.Ticking) {
                    // create a new tick of given type or notify failing and stop
                    switch(nm.info.type) {
                        case fqn!EntityFreezeSystemTick:
                            auto control = nm.control;
                            if(control)
                                this.freezeAsync(); // async for avoiding deadlock
                            break;
                        case fqn!EntityStoreSystemTick:
                            auto control = nm.control;
                            if(control)
                                this.storeAsync(); // async for avoiding deadlock
                            break;
                        case fqn!SpaceFreezeSystemTick:
                            auto control = nm.control;
                            if(control)
                                this.spaceFreezeAsync(); // async for avoiding deadlock
                            break;
                        case fqn!SpaceStoreSystemTick:
                            auto control = nm.control;
                            if(control)
                                this.spaceStoreAsync(); // async for avoiding deadlock
                            break;
                        default:
                            this.exec(this.pop(nm));
                            break;
                    }
                } else {
                    this.meta.ticks ~= nm;
                }
            }
        }, next));
    }

    void exec(Tick tick) {
        import std.parallelism : taskPool, task;

        this.opLock.reader.lock();
        taskPool.put(task((Tick t){
            scope(exit)
                this.opLock.reader.unlock();

            // registering an execution on entity
            this.execLock.reader.lock();

            t.job = Job(&t.exec, &t.catchError, t.meta.time);
            this.space.proc.run(&t.job);
        }, tick));
    }

    void dispose() {
        import core.thread : Thread;
        import core.time : msecs;

        if(this.state == SystemState.Ticking)
            this.freeze();

        // waiting for all internal operations to finish
        synchronized(this.opLock.writer)        
            this.destroy;
    }

    /// makes entity tick
    void tick() {
        if(this.state != SystemState.Ticking)
            this.state = SystemState.Ticking;
    }

    /// meakes entity freeze
    void freeze() {
        if(this.state != SystemState.Frozen)
            this.state = SystemState.Frozen;
    }

    void freezeAsync() {
        import std.parallelism : taskPool, task;

        this.opLock.reader.lock();
        taskPool.put(task((){
            scope(exit)
                this.opLock.reader.unlock();
            this.freeze();
        }));
    }

    void spaceFreezeAsync() {
        import std.parallelism : taskPool, task;

        this.opLock.reader.lock();
        taskPool.put(task((){
            scope(exit)
                this.opLock.reader.unlock();
            this.space.freeze();
        }));
    }

    // stores actual entity meta to disk
    void store() {
        import std.file : mkdirRecurse, write;
        import std.path : buildPath;
        import std.process : environment;
        bool wasFrozen;
        if(this.state != SystemState.Frozen) { // freeze if necessary
            this.freeze();
            wasFrozen = false;
        } else wasFrozen = true;

        auto t = this.target;
        t.mkdirRecurse;
        t = t.buildPath(this.meta.ptr.id);
        t.write(this.meta.bin);

        if(!wasFrozen) // bring up if neccessary
            this.tick();
    }

    void wipe() {
        import std.file : remove, exists;
        import std.path : buildPath;

        this.ensureState(SystemState.Frozen);

        auto t = this.target.buildPath(this.meta.ptr.id);
        if(t.exists) t.remove;
    }

    void storeAsync() {
        import std.parallelism : taskPool, task;

        this.opLock.reader.lock();
        taskPool.put(task((){
            scope(exit)
                this.opLock.reader.unlock();
            this.store();
        }));
    }

    void spaceStoreAsync() {
        import std.parallelism : taskPool, task;

        this.opLock.reader.lock();
        taskPool.put(task((){
            scope(exit)
                this.opLock.reader.unlock();
            this.space.store();
        }));
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                return o == SystemState.Frozen;
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                this.onTicking();
                break;
            case SystemState.Frozen:
                if(this.meta !is null)
                    this.onFrozen();
                break;
            default:
                break;
        }
    }

    private void onTicking() {
        import std.algorithm.iteration;

        synchronized(this.meta.writer) {
            // invoking OnTicking ticks
            foreach(e; this.meta.events.filter!(e => e.type == EventType.OnTicking)) {
                auto t = this.pop(e.tick.createTickMeta());

                // if its meant to get control, give it
                if(e.control)
                    t.meta.control = true;

                if(t.accept)
                    this.exec(t);
            }       

            // creating and starting all frozen ticks
            foreach(tm; this.meta.ticks)
                this.exec(this.pop(tm));

            // all frozen ticks are ticking -> empty store
            this.meta.ticks = TickMeta[].init;
        }
    }

    private void onFrozen() {
        import core.memory : GC;
        import core.thread : Thread;
        import core.time : msecs;
        import std.algorithm.iteration : filter;
        import std.range : empty;

        synchronized(this.meta.writer) {
            // invoking OnFreezing ticks
            foreach(e; this.meta.events.filter!(e => e.type == EventType.OnFreezing)) {
                auto t = this.pop(e.tick.createTickMeta());

                // if its meant to get control, give it
                if(e.control)
                    t.meta.control = true;

                if(t.accept)
                    this.exec(t);
            } 
        }

        // waiting for all ticks to finish
        synchronized(this.execLock.writer) {}
    }

    @property string target() {
        import std.file : exists;
        import std.path : expandTilde, buildPath;

        string t;
        version(Posix) {
            auto varT = "/var/lib/flow";
            t = (varT.exists
                ? varT
                : t = "~/.local/share/flow")
                .expandTilde;
        }
        version(Windows) {
            t = environment.get("APPDATA");
        }
        t = t.buildPath(this.space.meta.id);

        return t;
    }

    void damage(Throwable thr) {
        synchronized(this.meta.writer)
            this.meta.damages ~= thr.damage;

        // entity cannot operate in damaged state
        this.freezeAsync(); // async for avoiding deadlock
    }

    /// adds data to context and returns its typed index
    size_t add(Data d) {
        import std.algorithm.searching;
        if(d !is null) synchronized(this.meta.writer)
            if(!this.meta.aspects.any!((x)=>x is d)) {
                    this.meta.aspects ~= d;
                    this.aspects[typeid(d)] ~= d;
                    foreach_reverse(i, c; this.aspects[typeid(d)])
                        if(c is d) return i;
                }
        
        return -1;
    }

    /// removes data from context
    void remove(Data d) {
        import std.algorithm.searching;
        import std.algorithm.mutation;
        if(d !is null) synchronized(this.meta.writer)
            if(this.meta.aspects.any!((x)=>x is d)) {
                    // removing it from context cache
                    TypeInfo ft = typeid(d);
                    if(ft in this.aspects)
                        foreach_reverse(i, c; this.aspects[ft])
                            if(c is d) {
                                this.aspects[ft].remove(i);
                                break;
                            }

                    // removing it from context
                    foreach_reverse(i, c; this.meta.aspects)
                        if(c is d) {
                            this.meta.aspects.remove(i);
                            break;
                        }
                }
    }

    /// gets data by type and index from context
    T get(T)(size_t i = 0) {
        synchronized(this.meta.reader) {
            if(typeid(T) in this.aspects)
                if(this.aspects[typeid(T)].length > i)
                    return this.aspects[typeid(T)][i].as!T;
        }
        
        return null;
    }

    /// registers a receptor if not registered
    void register(string s, string t) {
        synchronized(this.meta.writer) {
            foreach(r; this.meta.receptors)
                if(r.signal == s && r.tick == t)
                    return; // nothing to do

            auto r = new Receptor;
            r.signal = s;
            r.tick = t;
            this.meta.receptors ~= r; 
        }
    }

    /// deregisters a receptor if registerd
    void deregister(string s, string t) {
        import std.algorithm.mutation : remove;

        synchronized(this.meta.writer) {
            foreach(i, r; this.meta.receptors) {
                if(r.signal == s && r.tick == t) {
                    this.meta.receptors.remove(i);
                    break;
                }
            }
        }
    }

    /// registers an event if not registered
    void register(EventType et, string t) {
        synchronized(this.meta.writer) {
            foreach(e; this.meta.events)
                if(e.type == et && e.tick == t)
                    return; // nothing to do

            auto e = new Event;
            e.type = et;
            e.tick = t;
            this.meta.events ~= e;
        }
    }

    /// deregisters an event if registerd
    void deregister(EventType et, string t) {
        import std.algorithm.mutation : remove;

        synchronized(this.meta.writer) {
            foreach(i, e; this.meta.events) {
                if(e.type == et && e.tick == t) {
                    this.meta.events.remove(i);
                    break;
                }
            }
        }
    }

    /// receipts a signal
    bool receipt(Signal s) {
        auto ret = false;
        TickMeta[] ticks;
        synchronized(this.meta.reader) {
            // looping all registered receptors
            foreach(r; this.meta.receptors) {
                if(s.dataType == r.signal) {
                    // creating given tick
                    auto tm = r.tick.createTickMeta(s.group);
                    bool a; { // check if there exists a tick for given meta and if it accepts the request
                        auto t = this.pop(tm);
                        scope(exit)
                            this.put(t);
                        a = t !is null && t.accept;
                    }

                    if(a) {
                        // if its meant to get control, give it
                        if(r.control)
                            tm.control = true;
                            
                        tm.trigger = s;
                        ticks ~= tm;
                    }
                }
            }
        }

        foreach(tm; ticks) {
            this.invoke(tm);
            ret = true;
        }
        
        return ret;
    }

    /// send an unicast signal into own space
    bool send(Unicast s) {
        import flow.core.gears.error : EntityException;

        synchronized(this.meta.reader) {
            if(s.dst == this.meta.ptr)
                new EntityException("entity cannot send signals to itself, just invoke a tick");

            // ensure correct source entity pointer
            s.src = this.meta.ptr;
        }

        return this.space.send(s);
    }

    /// send an anycast signal into own space
    bool send(Anycast s) {
        synchronized(this.meta.reader)
            // ensure correct source entity pointer
            s.src = this.meta.ptr;

        return this.space.send(s);
    }

    /// send an multicast signal into own space
    bool send(Multicast s) {
        synchronized(this.meta.reader)
            // ensure correct source entity pointer
            s.src = this.meta.ptr;

        return this.space.send(s);
    }

    /** creates a snapshot of entity(deep clone)
    if entity is not in frozen state an exception is thrown */
    EntityMeta snap() {
        synchronized(this.meta.reader) {
            this.ensureState(SystemState.Frozen);
            // if someone snaps using this function, it is another entity. it will only get a deep clone.
            return this.meta.clone;
        }
    }
}

private Damage damage(Throwable thr) {
    import std.conv : to;

    auto dmg = new Damage;
    dmg.msg = thr.file~":"~thr.line.to!string~" "~thr.msg;
    dmg.type = fqn!(typeof(thr));

    if(thr.as!FlowException !is null)
        dmg.data = thr.as!FlowException.data;

    return dmg;
}

/// gets the string address of an entity
string addr(EntityPtr e) {
    return e.id~"@"~e.space;
}

/// controlls an entity
class EntityController {
    private import core.time : Duration;
    private import flow.core.data : Data;
    private import std.datetime.systime : SysTime;

    private Entity _entity;

    /// deep clone of entity pointer of controlled entity
    @property EntityPtr entity() {return this._entity.meta.ptr.clone;}

    /// state of entity
    @property SystemState state() {return this._entity.state;}

    /// tick counter of entity
    @property size_t count() {return this._entity.count;}

    /// target path for entity storing
    @property string target() {return this._entity.target;}

    /// deep clone of entity context
    @property Data[] aspects() {return this._entity.meta.aspects;}

    /// deep clone of entity context
    @property Damage[] damages() {return this._entity.meta.damages;}

    private this(Entity e) {
        this._entity = e;
    }

    /// snapshots entity (only working when entity is frozen)
    EntityMeta snap() {
        return this._entity.snap();
    }
    
    /// makes entity storing
    void store() {
        this._entity.store();
    }
    
    /// makes entity freezing
    void freeze() {
        this._entity.freeze();
    }

    /// makes entity ticking
    void tick() {
        this._entity.tick();
    }
    
    /// invoke tick
    bool invoke(string tick, Data data = null, UUID group = UUID.init, bool control = false) {
        return this.invoke(tick, Duration.init, data, group);
    }

    /// invoke tick with delay
    bool invoke(string tick, SysTime schedule, Data data = null, UUID group = UUID.init, bool control = false) {
        import std.datetime.systime : Clock;

        auto delay = schedule - Clock.currTime;

        if(delay.total!"hnsecs" > 0)
            return this.invoke(tick, delay, data, group, control);
        else
            return this.invoke(tick, data, group, control);
    }

    /// invoke tick with delay
    bool invoke(string tick, Duration delay, Data data = null, UUID group = UUID.init, bool control = false) {
        import flow.core.gears.error : TickException;
        import std.datetime.systime : Clock;

        auto stdTime = Clock.currStdTime;
        auto m = tick.createTickMeta(group);
        m.control = control;

        m.time = stdTime + delay.total!"hnsecs";
        m.data = data;

        bool a; { // check if there exists a tick for given meta and if it accepts the request
            auto t = this._entity.pop(m);
            scope(exit)
                this._entity.put(t);
            a = t !is null && t.accept;
        }

        if(a) {
            this._entity.invoke(m);
            return true;
        } else return false;
    }

    /// registers a receptor for signal which invokes a tick
    protected void register(string signal, string tick) {
        import flow.core.gears.error : TickException;
        import flow.core.data : createData;
        
        auto s = createData(signal).as!Signal;
        if(s is null || createData(tick) is null)
            throw new TickException("can only register receptors for valid signals and ticks");

        this._entity.register(signal, tick);
    }

    /// deregisters an receptor for signal invoking tick
    protected void deregister(string signal, string tick) {
        this._entity.deregister(signal, tick);
    }

    /// send an unicast signal to a destination
    protected bool send(Unicast s, string entity, string space, UUID group = UUID.init) {
        auto eptr = new EntityPtr;
        eptr.id = entity;
        eptr.space = space;
        return this.send(s, eptr, group);
    }

    /// send an unicast signal to a destination
    protected bool send(Unicast s, EntityPtr e = null, UUID group = UUID.init) {
        import flow.core.gears.error : TickException;
        import std.uuid : randomUUID;
        
        if(s is null)
            throw new TickException("cannot sand an empty unicast");

        if(e !is null) s.dst = e;

        if(s.dst is null || s.dst.id == string.init || s.dst.space == string.init)
            throw new TickException("unicast signal needs a valid destination(dst)");

        if(s.group == UUID.init)
            s.group = group == UUID.init ? randomUUID : group;

        return this._entity.send(s);
    }

    /// send an anycast signal to spaces matching space pattern
    protected bool send(Anycast s, string dst = string.init, UUID group = UUID.init) {
        import flow.core.gears.error : TickException;
        import std.uuid : randomUUID;
        
        if(dst != string.init) s.dst = dst;

        if(s.dst == string.init)
            throw new TickException("anycast signal needs a space pattern");

        if(s.group == UUID.init)
            s.group = group == UUID.init ? randomUUID : group;

        return this._entity.send(s);
    }

    /// send an anycast signal to spaces matching space pattern
    protected bool send(Multicast s, string dst = string.init, UUID group = UUID.init) {
        import flow.core.gears.error : TickException;
        import std.uuid : randomUUID;
        
        if(dst != string.init) s.dst = dst;

        if(s.dst == string.init)
            throw new TickException("multicast signal needs a space pattern");

        if(s.group == UUID.init)
            s.group = group == UUID.init ? randomUUID : group;

        return this._entity.send(s);
    }
}

enum JunctionState {
    Detached,
    Attached
}

abstract class Channel {
    private string _dst;
    private Junction _own;
    private JunctionInfo _other;
    private bool _verified; // just telling that handshake was done not if it was successful

    protected @property Junction own() {return this._own;}
    abstract @property ubyte[] auth();

    @property string dst() {return this._dst;}
    @property JunctionInfo other() {return this._other;}
    
    this(string dst, Junction own) {        
        this._dst = dst;
        this._own = own;
    }

    private void ensureHandshake() {
        synchronized if(!this._verified)
            this.handshake();
    }

    final void handshake() {
        import std.range : empty, front;

        // establish channel only if both side verifies
        if(this.reqVerify()) {
            // authentication was accepted so authenticate the peer
            if(this.verify()) {
                Log.msg(LL.Message, this.own.logPrefix~"handshake between \""~this.own.meta.info.space~"\" and \""~this.dst~"\" succeeded");
            } else {
                Log.msg(LL.Message, this.own.logPrefix~"handshake between \""~this.own.meta.info.space~"\" and \""~this.dst~"\" failed");
            }
        }

        this._verified = true;
    }

    final bool verify() {
        import flow.core.data : unbin, unpack;
        import std.range : empty, front;
        
        auto auth = this.auth.dup;
        auto sig = auth.unpack;
        auto infoData = auth.unpack;
        auto info = infoData.unbin!JunctionInfo;

        if(sig !is null)
            this.own.crypto.add(this._dst, info.crt);
        /* if without signature it might be fake,
        ensure that noone could think its trustworthy */
        else info.crt = string.init;

        // if peer signed then there has to be a crt there too
        auto sigOk = sig !is null && this.own.crypto.verify(infoData, sig, this._dst);
        auto checkOk = !info.crt.empty && this.own.crypto.check(info.space);

        auto r = false;
        if((sig is null || sigOk) && (!this.own.meta.info.checking || checkOk)){
            this._other = info;
            r = true;
        } else this.own.crypto.remove(this._dst);

        this._verified = true;
        
        return r;
    }

    final bool pull(/*w/o ref*/ ubyte[] pkg) {
        import flow.core.data : unbin, unpack;

        if(this._other !is null) {// only if verified
            if(this._other.crt !is null) {
                if(this._other.encrypting) {// decrypt it
                    auto data = this.own.crypto.decrypt(pkg, this._dst);
                    auto s = data.unbin!Signal;
                    return this.own.pull(s, this._other);
                }
                else {// fisrt check signature
                    auto sig = pkg.unpack;
                    return this.own.crypto.verify(pkg, sig, this._dst)
                        && this.own.pull(pkg.unbin!Signal, this._other);
                }
            } else return this.own.pull(pkg.unbin!Signal, this._other);
        } else return false;
    }

    private final bool push(Signal s) {
        import flow.core.data : bin, pack;

        if(this._other !is null) { // only if verified
            auto pkg = s.bin;
            if(this.own.meta.key !is null) {
                if(this.own.meta.info.encrypting) {// encrypt for dst
                    auto crypt = this.own.crypto.encrypt(pkg, this._dst);
                    return this.transport(crypt);
                } else {// sign
                    auto sig = this.own.crypto.sign(pkg);
                    auto signed = sig.pack~pkg;
                    return this.transport(signed);
                }
            } else return this.transport(pkg);
        } else return false;
    }

    /// request authentication
    abstract protected bool reqVerify();

    /// transports signal through channel
    abstract protected bool transport(ref ubyte[] p);

    /// clean up called in destructor
    protected void dispose() {
        this.destroy;
    }
}

/// allows signals from one space to get shipped to other spaces
abstract class Junction : StateMachine!JunctionState {
    private import std.parallelism : taskPool, task;
    private import flow.core.crypt;

    private JunctionMeta _meta;
    private Space _space;
    private string[] destinations;
    private Crypto crypto;
    private ubyte[] _auth;

    protected @property JunctionMeta meta() {return this._meta;}
    @property string space() {return this._space.meta.id;}

    @property ubyte[] auth() {
        if(this._auth is null) {
            import flow.core.data : pack;
            import flow.core.data : bin;

            auto info = this.meta.info.bin;
            ubyte[] sig;
            if(this.meta.key != string.init)
                sig = this.crypto.sign(info);
            // indicate it's signed, append signature and data
            this._auth = sig.pack~info.pack;
        }

        return this._auth;
    }

    /// ctor
    this() {
        super();
    }
    
    void dispose() {
        if(this.state != JunctionState.Attached)
            this.detach();
        
        this.destroy;
    }

    private bool initCrypto() {
        if(this._meta.key !is null)
            this.crypto = new Crypto(this.meta.info.space, this.meta.key, this.meta.info.crt, this.meta.info.cipher, this.meta.info.hash);
        return true;
    }

    private void deinitCrypto() {
        import core.memory : GC;
        if(this._meta.key !is null && this.crypto !is null) {
            this.crypto.dispose(); GC.free(&this.crypto); this.crypto = null;
        }
    }

    private void attach() {
        this.state = JunctionState.Attached;
    }

    private void detach() {
        this.state = JunctionState.Detached;
    }

    override protected final bool onStateChanging(JunctionState o, JunctionState n) {
        switch(n) {
            case JunctionState.Attached:
                return o == JunctionState.Detached && this.initCrypto() && this.up();
            case JunctionState.Detached:
                return o == JunctionState.Attached;
            default: return false;
        }
    }

    override protected final void onStateChanged(JunctionState o, JunctionState n) {
        switch(n) {
            case JunctionState.Detached:
            if(this.meta) {
                this.down();
                this.deinitCrypto();
            }
            break;
            default: break;
        }
    }

    /** returns all known spaces, wilcards can work only for theese
    dynamic junctions might return string[].init
    and therefore do not support wildcards but only certain destinations */
    protected abstract @property string[] list();

    /// attaches to junction
    protected abstract bool up();

    /// detaches from junction
    protected abstract void down();

    /// returns a transport channel to target space
    protected abstract Channel get(string dst);

    /// pushes a signal through a channel
    private bool push(Signal s, Channel c) {
        import flow.core.data : bin;
        
        c.ensureHandshake();

        // channel init might have failed, do not segfault because of that
        if(c.other !is null) {
            synchronized(this.lock.reader)
                if(s.allowed(this.meta.info, c.other)) {
                    // it gets done async returns true
                    if(this.meta.info.indifferent) {
                        taskPool.put(task(&c.push, s));
                        return true;
                    } else {
                        return c.push(s);
                    }
                } else return false;
        } return false;
    }

    /// pulls a signal from a channel
    private bool pull(Signal s, JunctionInfo src) {
        import flow.core.data : unbin;

        if(s.allowed(src, this.meta.info)) {
            /* do not allow measuring of runtimes timings
            ==> make the call async and dada */
            if(this.meta.info.hiding) {
                taskPool.put(task(&this.route, s));
                return true;
            } else
                return this.route(s);
        } else return false;
    }

    /// ship an unicast through the junction
    private bool ship(Unicast s) {
        synchronized(this.lock.reader) {
            auto c = this.get(s.dst.space);
            if(c !is null)
                return this.push(s, c);
        }

        return false;
    }

    /// ship an anycast through the junction
    private bool ship(Anycast s) {        
        synchronized(this.lock.reader)
            if(s.dst != this.meta.info.space) {
                auto c = this.get(s.dst);
                if(c !is null)
                    return this.push(s, c);
                else foreach(j; this.list) {
                    c = this.get(j);
                    return c !is null ? this.push(s, c) : false;
                }
            }
                    
        return false;
    }

    /// ship a multicast through the junction
    private bool ship(Multicast s) {
        auto ret = false;
        synchronized(this.lock.reader)
            if(s.dst != this.meta.info.space) {
                auto c = this.get(s.dst);
                if(c !is null)
                    ret = this.push(s, c) || ret;
                else foreach(j; this.list) {
                    c = this.get(j);
                    ret = (c !is null ? this.push(s, c) : false) || ret;
                }
            }

        return ret;
    }

    private bool route(Signal s) {
        if(s.as!Unicast !is null)
            return this._space.route(s.as!Unicast, this.meta.level);
        else if(s.as!Anycast !is null)
            return this._space.route(s.as!Anycast, this.meta.level);
        else if(s.as!Multicast !is null)
            return this._space.route(s.as!Multicast, this.meta.level);
        else {
            Log.msg(LL.Warning, this.logPrefix~"should route unsupported signal -> refused", s);
            return false;
        }
    }
}

/// evaluates if signal is allowed in that config
bool allowed(Signal s, JunctionInfo snd, JunctionInfo recv) {
    if(s.as!Unicast !is null)
        return s.as!Unicast.dst.space == recv.space;
    else if(s.as!Anycast !is null)
        return !snd.indifferent && !recv.hiding && !recv.introvert && recv.space.matches(s.as!Anycast.dst);
    else if(s.as!Multicast !is null)
        return !recv.introvert && recv.space.matches(s.as!Multicast.dst);
    else return false;
}

bool matches(string id, string pattern) {
    import std.array : array;
    import std.range : split, retro, back;

    if(pattern.containsWildcard) {
        auto ip = id.split(".").retro.array;
        auto pp = pattern.split(".").retro.array;

        if(pp.length == ip.length || (pp.length < ip.length && pp.back == "*")) {
            foreach(i, p; pp) {
                if(!(p == ip[i] || (p == "*")))
                    return false;
            }

            return true;
        }
        else return false;
    } else
        return id == pattern;
}

private bool containsWildcard(string dst) {
    import std.algorithm.searching : canFind;

    return dst.canFind("*");
}

unittest { test.header("gears.engine: wildcards checker");
    assert("*".containsWildcard);
    assert(!"a".containsWildcard);
    assert("*.aa.bb".containsWildcard);
    assert("aa.*.bb".containsWildcard);
    assert("aa.bb.*".containsWildcard);
    assert(!"aa.bb.cc".containsWildcard);
test.footer(); }

unittest { test.header("gears.engine: domain matching");    
    assert(matches("a.b.c", "a.b.c"), "1:1 matching failed");
    assert(matches("a.b.c", "a.b.*"), "first level * matching failed");
    assert(matches("a.b.c", "a.*.c"), "second level * matching failed");
    assert(matches("a.b.c", "*.b.c"), "third level * matching failed");
test.footer(); }

/// hosts a space which can host n entities
class Space : StateMachine!SystemState {
    private import core.time : Duration;
    private import std.uuid : UUID;

    private SpaceMeta meta;
    private Process process;
    private Processor proc;

    private Junction[UUID] junctions;
    private Entity[string] entities;

    private this(Process p, SpaceMeta m) {
        this.meta = m;
        this.process = p;

        super();
    }

    void dispose() {
        import core.memory : GC;
        if(this.state == SystemState.Ticking)
            this.freeze();

        foreach(i, j; this.junctions) {
            j.detach();
            j.dispose(); GC.free(&j);
        }

        foreach(k, e; this.entities) {
            e.dispose(); GC.free(&e);
        }

        this.proc.stop();

        this.destroy;
    }

    /// makes space and all of its content freezing
    void freeze() {
        if(this.state != SystemState.Frozen)
            this.state = SystemState.Frozen;
    }

    /// makes space and all of its content ticking
    void tick() {
        if(this.state != SystemState.Ticking)
            this.state = SystemState.Ticking;
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                return (o == SystemState.Frozen);
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                this.onTicking();
                break;
            case SystemState.Frozen:
                if(this.proc is null)
                    this.onCreated();
                else
                    this.onFrozen();
                break;
            default: break;
        }
    }

    private void onCreated() {
        import flow.core.gears.error : SpaceException;

        // creating processor;
        // default is one core
        if(this.meta.worker < 1)
            this.meta.worker = 1;
        this.proc = new Processor(this.meta.worker);
        this.proc.start();

        // creating junctions
        foreach(jm; this.meta.junctions) {
            auto j = Object.factory(jm.type).as!Junction;
            if(jm.id == UUID.init) jm.id = randomUUID;
            jm.info.space = this.meta.id; // ensure junction knows correct space
            j._meta = jm;
            j._space = this;
            this.junctions[jm.id] = j;
            try {
                j.attach();
            } catch(Throwable thr) {
                Log.msg(LL.Error, this.logPrefix~"couldn't attach to junction");
            }
        }

        // creating entities
        foreach(em; this.meta.entities) {
            if(em.ptr.id in this.entities)
                throw new SpaceException("entity with addr \""~em.ptr.addr~"\" already exists");
            else {
                // ensure entity belonging to this space
                em.ptr.space = this.meta.id;

                Entity e = new Entity(this, em);
                this.entities[em.ptr.id] = e;
            }
        }
    }
    private void onTicking() {
        foreach(e; this.entities)
            e.tick();
    }

    private void onFrozen() {
        // freezing happens backwards
        foreach_reverse(e; this.entities.values)
            e.freeze();
    }

    /// snapshots whole space (deep clone)
    SpaceMeta snap() {
        if(this.state == SystemState.Ticking) {
            this.state = SystemState.Frozen;
            scope(exit) this.state = SystemState.Ticking;
        }

        synchronized(this.lock.reader)
            return this.meta.clone;
    }

    /// makes all of spaces content storing
    void store() {
        synchronized(this.lock.reader) {
            Entity[] frozen;
            foreach_reverse(e; this.entities.values)
                if(e.state == SystemState.Frozen) {
                    e.freeze();
                    frozen ~= e;
                }

            scope(exit) foreach_reverse(e; frozen)
                e.tick();
            
            foreach(e; this.entities.values)
                e.store();
        }
    }

    EntityController get(EntityPtr ptr) {
        return this.get(ptr.id);
    }

    /// gets a controller for an entity contained in space (null if not existing)
    EntityController get(string e) {
        synchronized(this.lock.reader)
            return (e in this.entities).as!bool ? this.entities[e].control : null;
    }

    /// spawns a new entity into space
    EntityController spawn(EntityMeta m) {
        import flow.core.gears.error : SpaceException;

        synchronized(this.lock.writer) {
            if(m.ptr.id in this.entities)
                throw new SpaceException("entity with addr \""~m.ptr.addr~"\" is already existing");
            else {
                // ensure entity belonging to this space
                m.ptr.space = this.meta.id;
                
                this.meta.entities ~= m;
                Entity e = new Entity(this, m);
                this.entities[m.ptr.id] = e;
                return e.control;
            }
        }
    }

    /// kills an existing entity in space
    void kill(string en) {
        import core.memory : GC;
        import flow.core.gears.error : SpaceException;

        synchronized(this.lock.writer) {
            if(en in this.entities) {
                auto e = this.entities[en];
                e.freeze(); e.wipe(); e.dispose(); GC.free(&e);
                this.entities.remove(en);
            } else throw new SpaceException("entity with addr \""~en~"\" is not existing");
        }
    }

    /// attaches space to new junction
    UUID attach(JunctionMeta jm) {
        import flow.core.gears.error : SpaceException;
        import std.conv : to;

        synchronized(this.lock.writer) {
            if(jm.id in this.junctions)
                throw new SpaceException("junction with id \""~jm.id.to!string~"\" is already existing");
            else {
                this.meta.junctions ~= jm;
                auto j = Object.factory(jm.type).as!Junction;
                if(jm.id == UUID.init) jm.id = randomUUID;
                jm.info.space = this.meta.id; // ensure junction knows correct space
                j._meta = jm;
                j._space = this;
                this.junctions[jm.id] = j;

                // only start if space is ticking
                if(this.state == SystemState.Ticking)
                    j.attach();

                return jm.id;
            }
        }
    }

    /// detaches space from junction
    void detach(UUID jid) {
        import core.memory : GC;
        import flow.core.gears.error : SpaceException;
        import std.algorithm.mutation : remove;
        import std.conv : to;

        synchronized(this.lock.writer) {
            if(jid in this.junctions) {
                auto j = this.junctions[jid];
                // only stop if space is ticking
                if(this.state == SystemState.Ticking)
                    j.detach();
                
                this.junctions.remove(jid);

                foreach_reverse(i, jm; this.meta.junctions) {
                    if(jm.id == jid)
                        this.meta.junctions = this.meta.junctions.remove(i);
                }
            } else throw new SpaceException("junction with id \""~jid.to!string~"\" is not existing");
        }
    }
    
    /// routes an unicast signal to receipting entities if its in this space
    private bool route(Unicast s, ushort level) {
        // if its a perfect match assuming process only accepted a signal for itself
        synchronized(this.lock.reader)
            if(this.state == SystemState.Ticking)
                if(s.dst.space == this.meta.id) {
                    foreach(e; this.entities.values) {
                        if(e.meta.level >= level) { // only accept if entities level is equal or higher the one of the junction
                            if(e.meta.ptr == s.dst)
                                return e.receipt(s);
                        }
                    }
                }
        
        return false;
    }

   
    /// routes an anycast signal to one receipting entity
    private bool route(Anycast s, ushort level) {
        // if its adressed to own space or parent using * wildcard or even none
        // in each case we do not want to regex search when ==
        synchronized(this.lock.reader) {
            if(this.state == SystemState.Ticking) {
                foreach(e; this.entities.values) {
                    if(e.meta.level >= level) { // only accept if entities level is equal or higher the one of the junction
                        if(e.receipt(s))
                            return true;
                    }
                }
            }
        }

        return false;
    }
    
    /// routes a multicast signal to receipting entities if its addressed to space
    private bool route(Multicast s, ushort level) {
        auto r = false;
        // if its adressed to own space or parent using * wildcard or even none
        // in each case we do not want to regex search when ==
        synchronized(this.lock.reader) {
            if(this.state == SystemState.Ticking) {
                foreach(e; this.entities.values) {
                    if(e.meta.level >= level) { // only accept if entities level is equal or higher the one of the junction
                        r = e.receipt(s) || r;
                    }
                }
            }
        }

        return r;
    }

    private bool send(Unicast s) {
        // ensure correct source space
        s.src.space = this.meta.id;

        auto isMe = s.dst.space == this.meta.id || this.meta.id.matches(s.dst.space);
        /* Only inside own space memory is shared,
        as soon as a signal is getting shiped to another space it is deep cloned */
        return isMe ? this.route(s, 0) : this.ship(s);
    }

    private bool send(Anycast s) {
        // ensure correct source space
        s.src.space = this.meta.id;

        auto isMe = s.dst == this.meta.id || this.meta.id.matches(s.dst);
        /* Only inside own space memory is shared,
        as soon as a signal is getting shiped to another space it is deep cloned */
        return isMe ? this.route(s, 0) : this.ship(s);
    }

    private bool send(Multicast s) {
        // ensure correct source space
        s.src.space = this.meta.id;

        auto isMe = s.dst == this.meta.id || this.meta.id.matches(s.dst);
        /* Only inside own space memory is shared,
        as soon as a signal is getting shiped to another space it is deep cloned */
        return isMe ? this.route(s, 0) : this.ship(s);
    }

    private bool ship(Unicast s) {
        foreach(i, j; this.junctions)
            if(j.ship(s)) return true;

        return false;
    }

    private bool ship(Anycast s) {
        foreach(i, j; this.junctions)
            if(j.ship(s))
                return true;

        return false;
    }

    private bool ship(Multicast s) {
        auto ret = false;
        foreach(i, j; this.junctions)
            ret = j.ship(s) || ret;

        return ret;
    }

    void join(Duration to = Duration.max) {
        import core.time : msecs;
        import core.thread : Thread;
        import std.datetime.systime : Clock;

        auto time = Clock.currStdTime;
        while(this.state != SystemState.Frozen || time + to.total!"hnsecs" < Clock.currStdTime)
            Thread.sleep(5.msecs);
    }
}

/** hosts one or more spaces and allows to controll them
whatever happens on this level, it has to happen in main thread or an exception occurs */
class Process {  
    private import core.sync.rwmutex : ReadWriteMutex;
      
    private ReadWriteMutex lock;
    private Space[string] spaces;

    /// ctor
    this() {
        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    void dispose() {
        import core.memory : GC;
        foreach(k, s; this.spaces) {
            s.dispose(); GC.free(&s);
        }

        this.destroy;
    }

    /// ensure it is executed in main thread or not at all
    private void ensureThread() {
        import core.thread : thread_isMainThread;
        import flow.core.gears.error : ProcessError;

        if(!thread_isMainThread)
            throw new ProcessError("process can be only controlled by main thread");
    }

    /// add a space
    Space add(SpaceMeta s) {   
        import flow.core.gears.error : ProcessException;

        this.ensureThread();
        
        synchronized(this.lock.writer) {
            if(s.id in this.spaces)
                throw new ProcessException("space with id \""~s.id~"\" is already existing");
            else {
                auto space = new Space(this, s);
                this.spaces[s.id] = space;
                return space;
            }
        }
    }

    /// get an existing space or null
    Space get(string s) {
        this.ensureThread();
        
        synchronized(this.lock.reader)
            return (s in this.spaces).as!bool ? this.spaces[s] : null;
    }

    /// removes an existing space
    void remove(string sn) {
        import flow.core.gears.error : ProcessException;

        this.ensureThread();
        
        synchronized(this.lock.writer)
            if(sn in this.spaces) {
                auto s = this.spaces[sn];
                s.dispose();
                this.spaces.remove(sn);
            } else
                throw new ProcessException("space with id \""~sn~"\" is not existing");
    }
}

/// creates space metadata
SpaceMeta createSpace(string id, size_t worker = 1) {
    auto sm = new SpaceMeta;
    sm.id = id;
    sm.worker = worker;

    return sm;
}

/// creates entity metadata
EntityMeta createEntity(string id, ushort level = 0) {
    import flow.core.data : createData;

    auto em = new EntityMeta;
    em.ptr = new EntityPtr;
    em.ptr.id = id;
    em.level = level;

    return em;
}

/// creates entity metadata and appends it to a spaces metadata
EntityMeta addEntity(SpaceMeta sm, string id, ushort level = 0) {
    import flow.core.data : createData;
    auto em = id.createEntity(level);
    em.ptr.space = sm.id;
    sm.entities ~= em;

    return em;
}

/// adds an event mapping
void addEvent(EntityMeta em, EventType type, string tickType, bool control = false) {
    auto e = new Event;
    e.type = type;
    e.tick = tickType;
    e.control = control;

    em.events ~= e;
}

/// adds an receptor mapping
void addReceptor(EntityMeta em, string signalType, string tickType, bool control = false) {
    auto r = new Receptor;
    r.signal = signalType;
    r.tick = tickType;
    r.control = control;

    em.receptors ~= r;
}

/// creates tick metadata and appends it to an entities metadata
TickMeta addTick(EntityMeta em, string type, Data d = null, UUID group = randomUUID, bool control = false) {
    auto tm = new TickMeta;
    tm.info = new TickInfo;
    tm.info.id = randomUUID;
    tm.info.type = type;
    tm.info.entity = em.ptr.clone;
    tm.info.group = group;
    tm.data = d;
    tm.control = control;

    em.ticks ~= tm;

    return tm;
}

/// creates metadata for an junction and appends it to a space
JunctionMeta addJunction(
    SpaceMeta sm,
    UUID id,
    string metaType,
    string infoType,
    string junctionType,
    ushort level = 0,
    bool hiding = false,
    bool indifferent = false,
    bool introvert = false
) {
    auto jm = createJunction(id, metaType, infoType, junctionType, level, hiding, indifferent, introvert);
    sm.junctions ~= jm;
    return jm;
}

/// creates metadata for an junction and appends it to a space
JunctionMeta createJunction(
    UUID id,
    string metaType,
    string infoType,
    string junctionType,
    ushort level = 0,
    bool hiding = false,
    bool indifferent = false,
    bool introvert = false
) {
    import flow.core.data : createData;
    import flow.core.util : as;
    import std.uuid : UUID;
    
    auto jm = createData(metaType).as!JunctionMeta;
    jm.id = id;
    jm.info = createData(infoType).as!JunctionInfo;
    jm.type = junctionType;
    
    jm.level = level;
    jm.info.hiding = hiding;
    jm.info.indifferent = indifferent;
    jm.info.introvert = introvert;

    return jm;
}

/// imports for tests
version(unittest) {
    private import flow.core.gears.data;
    private import flow.core.data;
    private import flow.core.util;
}

/// casts for testing
version(unittest) {
    class TestUnicast : Unicast {
        mixin data;
    }

    class TestAnycast : Anycast {
        mixin data;
    }
    class TestMulticast : Multicast {
        mixin data;
    }
}

/// data of entities
version(unittest) {
    class TestEventingAspect : Data {
        mixin data;

        mixin field!(bool, "firedOnTicking");
        mixin field!(bool, "firedOnFreezing");
    }

    class TestDelayAspect : Data {
        private import core.time : Duration;
        private import std.datetime.systime : SysTime;

        mixin data;

        mixin field!(Duration, "delay");
        mixin field!(SysTime, "startTime");
        mixin field!(SysTime, "endTime");
    }

    class TestSendingAspect : Data {
        mixin data;

        mixin field!(long, "wait");
        mixin field!(string, "dstEntity");
        mixin field!(string, "dstSpace");

        mixin field!(bool, "unicast");
        mixin field!(bool, "anycast");
        mixin field!(bool, "multicast");
    }

    class TestReceivingAspect : Data {
        mixin data;

        mixin field!(Unicast, "unicast");
        mixin field!(Anycast, "anycast");
        mixin field!(Multicast, "multicast");
    }
}

/// ticks
version(unittest) {
    class ErrorTestTick : Tick {
        override void run() {
            import flow.core.gears.error : TickException;
            throw new TickException("test error");
        }

        override void error(Throwable thr) {
            this.invoke(fqn!ErrorHandlerErrorTestTick);
        }
    }

    class ErrorHandlerErrorTestTick : Tick {
        override void run() {
            import flow.core.gears.error : TickException;
            throw new TickException("test error");
        }

        override void error(Throwable thr) {
            import flow.core.gears.error : TickException;
            throw new TickException("test errororhandler error");
        }
    }

    class OnTickingEventTestTick : Tick {
        override void run() {
            auto a = this.aspect!TestEventingAspect;
            a.firedOnTicking = true;
        }
    }

    class OnFreezingEventTestTick : Tick {
        override void run() {
            auto a = this.aspect!TestEventingAspect;
            a.firedOnFreezing = true;
        }
    }

    class DelayTestTick : Tick {
        override void run() {
            import std.datetime.systime : Clock;

            auto a = this.aspect!TestDelayAspect;
            a.startTime = Clock.currTime;
            this.invoke(fqn!DelayedTestTick, a.delay);
        }
    }

    class DelayedTestTick : Tick {
        override void run() {
            import std.datetime.systime : Clock;

            auto endTime = Clock.currTime;

            auto a = this.aspect!TestDelayAspect;
            a.endTime = endTime;
        }
    }

    class UnicastSendingTestTick : Tick {
        override void run() {
            import core.thread : Thread;
            import core.time : msecs;
            auto a = this.aspect!TestSendingAspect;

            /* when communicating via junctions other
            peers net to get known what might take a time */
            for(auto i = 0; i < 5; i++) {
                if(this.send(new TestUnicast, a.dstEntity, a.dstSpace)) {
                    a.unicast = true;
                    break;
                }
                Thread.sleep(a.wait.msecs);
            }
        }
    }

    class AnycastSendingTestTick : Tick {
        override void run() {
            import core.thread : Thread;
            import core.time : msecs;
            auto a = this.aspect!TestSendingAspect;

            for(auto i = 0; i < 5; i++) {
                if(this.send(new TestAnycast, a.dstSpace)) {
                    a.anycast = true;
                    break;
                }
                Thread.sleep(a.wait.msecs);
            }
        }
    }

    class MulticastSendingTestTick : Tick {
        override void run() {
            import core.thread : Thread;
            import core.time : msecs;
            auto a = this.aspect!TestSendingAspect;

            for(auto i = 0; i < 5; i++) {
                if(this.send(new TestMulticast, a.dstSpace)) {
                    a.multicast = true;
                    break;
                }
                Thread.sleep(a.wait.msecs);
            }
        }
    }

    class UnicastReceivingTestTick : Tick {
        override void run() {
            auto a = this.aspect!TestReceivingAspect;
            a.unicast = this.trigger.as!Unicast;
        }
    }

    class AnycastReceivingTestTick : Tick {
        override void run() {
            auto a = this.aspect!TestReceivingAspect;
            a.anycast = this.trigger.as!Anycast;
        }
    }

    class MulticastReceivingTestTick : Tick {
        override void run() {
            auto a = this.aspect!TestReceivingAspect;
            a.multicast = this.trigger.as!Multicast;
        }
    }
}

unittest { test.header("gears.engine: events");    
    import core.thread;
    import flow.core.gears.data;
    import flow.core.util;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spcDomain = "spc.test.engine.ipc.flow";

    auto sm = createSpace(spcDomain);

    auto em = sm.addEntity("test");
    em.aspects ~= new TestEventingAspect;
    em.addEvent(EventType.OnTicking, fqn!OnTickingEventTestTick);
    em.addEvent(EventType.OnFreezing, fqn!OnFreezingEventTestTick);

    auto spc = proc.add(sm);

    spc.tick();

    Thread.sleep(10.msecs);

    spc.freeze();

    auto nsm = spc.snap();

    assert(nsm.entities[0].aspects[0].as!TestEventingAspect.firedOnTicking, "didn't get fired for OnTicking");
    assert(nsm.entities[0].aspects[0].as!TestEventingAspect.firedOnFreezing, "didn't get fired for OnFreezing");
test.footer(); }

unittest { test.header("gears.engine: first level error handling");
    import core.thread;
    import core.time;
    import flow.core.gears.data;
    import flow.core.gears.error;
    import flow.core.util;
    import std.range;   

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spcDomain = "spc.test.engine.ipc.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("test");
    em.addEvent(EventType.OnTicking, fqn!ErrorTestTick);

    auto spc = proc.add(sm);

    // do not trigger test runner by writing error messages to stdout
    auto origLL = Log.logLevel;
    Log.logLevel = LL.Message;
    spc.tick();

    Thread.sleep(10.msecs); // exceptionhandling takes quite a while
    Log.logLevel = origLL;

    assert(spc.get(em.ptr).state == SystemState.Frozen, "entity isn't frozen");
    assert(!spc.get(em.ptr).damages.empty, "entity isn't damaged");
    assert(spc.get(em.ptr).damages.length == 1, "entity has wrong amount of damages");
test.footer(); }

unittest { test.header("gears.engine: second level -> damage error handling");
    import core.thread;
    import core.time;
    import flow.core.gears.data;
    import flow.core.util;
    import std.range;
    

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spcDomain = "spc.test.engine.ipc.flow";

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("test");
    em.addTick(fqn!ErrorTestTick);

    auto spc = proc.add(sm);

    auto origLL = Log.logLevel;
    Log.logLevel = LL.Message;
    spc.tick();

    Thread.sleep(10.msecs); // exceptionhandling takes quite a while
    Log.logLevel = origLL;

    assert(spc.get(em.ptr).state == SystemState.Frozen, "entity isn't frozen");
    assert(!spc.get(em.ptr).damages.empty, "entity isn't damaged");
    assert(spc.get(em.ptr).damages.length == 1, "entity has wrong amount of damages");
test.footer(); }

unittest { test.header("gears.engine: delayed next");
    import core.thread;
    import flow.core.gears.data;
    import flow.core.util;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spcDomain = "spc.test.engine.ipc.flow";
    auto delay = 100.msecs;

    auto sm = createSpace(spcDomain);
    auto em = sm.addEntity("test");
    auto a = new TestDelayAspect; em.aspects ~= a;
    a.delay = delay;
    em.addEvent(EventType.OnTicking, fqn!DelayTestTick);

    auto spc = proc.add(sm);

    spc.tick();

    Thread.sleep(300.msecs);

    spc.freeze();

    auto nsm = spc.snap();

    auto measuredDelay = nsm.entities[0].aspects[0].as!TestDelayAspect.endTime - nsm.entities[0].aspects[0].as!TestDelayAspect.startTime;
    auto hnsecs = delay.total!"hnsecs";
    auto tolHnsecs = hnsecs * 1.05; // we allow +5% (5msecs) tolerance for passing the test
    auto measuredHnsecs = measuredDelay.total!"hnsecs";
    
    test.write("delayed ", measuredHnsecs, "hnsecs; allowed ", hnsecs, "hnsecs - ", tolHnsecs, "hnsecs");
    assert(hnsecs < measuredHnsecs , "delayed shorter than defined");
    assert(tolHnsecs >= measuredHnsecs, "delayed longer than allowed");
test.footer(); }

unittest { test.header("gears.engine: send and receipt of all signal types and pass their group");
    import core.thread;
    import flow.core.gears.data;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose();

    auto spcDomain = "spc.test.engine.ipc.flow";

    auto sm = createSpace(spcDomain);

    auto group = randomUUID;
    auto ems = sm.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.dstEntity = "receiving";
    a.dstSpace = spcDomain;

    ems.addTick(fqn!UnicastSendingTestTick, null, group);
    ems.addTick(fqn!AnycastSendingTestTick, null, group);
    ems.addTick(fqn!MulticastSendingTestTick, null, group);

    // first the receiving entity should come up
    // (order of entries in space equals order of starting ticking)
    auto emr = sm.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);

    auto spc = proc.add(sm);

    spc.tick();

    Thread.sleep(10.msecs);

    spc.freeze();

    auto nsm = spc.snap();

    auto rA = nsm.entities[1].aspects[0].as!TestReceivingAspect;
    assert(rA.unicast !is null, "didn't get test unicast");
    assert(rA.anycast !is null, "didn't get test anycast");
    assert(rA.multicast !is null, "didn't get test multicast");

    auto sA = nsm.entities[0].aspects[0].as!TestSendingAspect;
    assert(sA.unicast, "didn't confirm test unicast");
    assert(sA.anycast, "didn't confirm test anycast");
    assert(sA.multicast, "didn't confirm test multicast");

    assert(rA.unicast.group == group, "unicast didn't pass group");
    assert(rA.anycast.group == group, "anycast didn't pass group");
    assert(rA.multicast.group == group, "multicast didn't pass group");
test.footer();}

//unittest { test.header("engine: "); test.footer(); }
