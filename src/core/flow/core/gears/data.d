module flow.core.gears.data;

/*template getAAValueType(T) if (is(T : V[K], V, K)) { static if (is(T : V[K], V, K)) alias getAAValueType = V; }
string[int] aa;
pragma(msg, getAAValueType!(typeof(aa)));*/

private import flow.core.data.base;
private import flow.core.data.data;

/// data representing a signal
abstract class Signal : IdData { mixin _data;
    private import std.uuid : UUID;

    @field UUID group;
    @field EntityPtr src;
}

mixin template _unicast() { mixin _data; }

/// data representing an unicast
abstract class Unicast : Signal { mixin _data;
    @field EntityPtr dst;
}

mixin template _anycast() { mixin _data; }

/// data representing a anycast
abstract class Anycast : Signal { mixin _data;
    @field string dst;
}

mixin template _multicast() { mixin _data; }

/// data representing a multicast
abstract class Multicast : Signal { mixin _data;
    @field string dst;
}

mixin template _req() { mixin _data; }

abstract class Req : Unicast { mixin _unicast; }

mixin template _rep() { mixin _data;
    this() {super();}
    this(Req req) {super();}
}

abstract class Rep : Unicast { mixin _unicast;
    @field Req req;

    this() {}
    this(Req req) {this.req = req;}
}

class Damage : Data { mixin _data;
    @field string msg;
    @field string type;
    @field Data data;
}

/// metadata of a space
class SpaceMeta : Data { mixin _data;
    /// identifier of the space
    @field string id;
    
    /// amount of processing pipes for executing actuality
    @field ulong actPipes;
    
    /// amount of processing pipes for executing control
    @field ulong ctlPipes;

    /// junctions allow signals to get shipped across spaces
    @field JunctionMeta[] junctions;

    /// entities of space
    @field EntityMeta[] entities;
}

/// info of a junction
class JunctionInfo : Data { mixin _data;
    /// space of junction (set by space when creating junction)
    @field string space;

    /// public RSA certificate (set by junction)
    @field string crt;

    /** type of cipher to use for encryption
    default AES128
    available
    - AES128
    - AES256*/
    @field string cipher;

    /** type of cipher to use for encryption
    default MD5
    available
    - MD5
    - SHA
    - SHA256*/
    @field string hash;

    /// indicates if junction is checking peers with systems CA's
    /// NOTE: not supported yet
    @field bool checking;

    /// indicates if junction is encrypting outbound signals
    @field bool encrypting;

    /** this side of the junction does not inform sending side of acceptance
    therefore it keeps internals secret
    (cannot allow anycast) */
    @field bool hiding;

    /** send signals into junction and do not care about acceptance
    (cannot use anycast) */
    @field bool indifferent;

    /** refuse multicasts and anycasts passig through junction */
    @field bool introvert;
}

/// metadata of a junction
class JunctionMeta : IdData { mixin _data;
    @field JunctionInfo info;
    @field string type;
    @field ushort level;

    /// path to private RSA key (no key disables encryption and authentication)
    @field string key;
}

class MeshJunctionInfo : JunctionInfo { mixin _data;
    @field string addr;
}

class MeshConnectorMeta : Data { mixin _data;
    @field string type;
}

class MeshJunctionMeta : JunctionMeta { mixin _data;
    @field string[] known;
    @field ulong timeout;
    @field ulong ackTimeout;
    @field ulong ackInterval;
    @field ulong pipes;

    @field MeshConnectorMeta conn;
}

/// metadata of an entity
class EntityMeta : LockData { mixin _data;
    @field EntityPtr ptr;
    @field Data[] config;
    @field Data[] aspects;
    @field ushort level;
    @field Event[] events;
    @field Receptor[] receptors;

    @field TickMeta[] ticks;

    @field Damage[] damages;
}

/// referencing a specific entity 
class EntityPtr : Data { mixin _data;
    @field string id;
    @field string space;
}

/// type of events can occur in an entity
enum EventType {
    /** sending signals OnTicking leads to an InvalidStateException */
    OnTicking,
    OnFreezing
}

/// mapping a tick to an event
class Event : Data { mixin _data;
    @field EventType type;
    @field string tick;
    @field bool control;
}

/// metadata of a tick
public class TickMeta : Data { mixin _data;
    @field TickInfo info;
    @field bool control;
    @field Signal trigger;
    @field TickInfo previous;
    @field long time;
    @field Data data;
}

/// info of a tick
class TickInfo : IdData { mixin _data;
    private import std.uuid : UUID;

    @field EntityPtr entity;
    @field string type;
    @field UUID group;
}

/// mapping a tick to a signal
class Receptor : Data { mixin _data;
    @field string signal;
    @field string tick;
    @field bool control;
}

/// information about a file
class FileInfo : Data { mixin _data;
    @field EntityPtr host;
    @field string name;
    @field long accessTime;
    @field long modificationTime;
    @field ulong size;
}

/// configuration of process
class ProcessConfig : Data { mixin _data;
    /// amount of processing pipes for executing control
    @field ulong ctlPipes;

    /** processes root path in filesystem
    if not set or not accessible for
        * posix its ~/.local/share/flow
        * window its %APPDATA%\flow */
    @field string fsroot;
}