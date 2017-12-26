module flow.core.gears.data;

/*template getAAValueType(T) if (is(T : V[K], V, K)) { static if (is(T : V[K], V, K)) alias getAAValueType = V; }
string[int] aa;
pragma(msg, getAAValueType!(typeof(aa)));*/

private import flow.core.data.engine;
private import flow.core.data.data;

/// data representing a signal
abstract class Signal : IdData {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(UUID, "group");
    mixin field!(EntityPtr, "src");
}

/// data representing an unicast
class Unicast : Signal {
    mixin data;

    mixin field!(EntityPtr, "dst");
}

/// data representing a anycast
class Anycast : Signal {
    mixin data;

    mixin field!(string, "dst");
}

/// data representing a multicast
class Multicast : Signal {
    mixin data;

    mixin field!(string, "dst");
}

class Damage : Data {
    private import flow.core.data.engine : Data;

    mixin data;

    mixin field!(string, "msg");
    mixin field!(string, "type");
    mixin field!(Data, "data");
}

/// metadata of a space
class SpaceMeta : Data {
    mixin data;

    /// identifier of the space
    mixin field!(string, "id");
    
    /// amount of worker threads for executing ticks
    mixin field!(size_t, "worker");

    /// junctions allow signals to get shipped across spaces
    mixin field!(JunctionMeta[], "junctions");

    /// entities of space
    mixin field!(EntityMeta[], "entities");
}

/// info of a junction
class JunctionInfo : Data {
    mixin data;

    /// space of junction (set by space when creating junction)
    mixin field!(string, "space");

    /// public RSA certificate (set by junction)
    mixin field!(string, "crt");

    /** type of cipher to use for encryption
    default AES128
    available
    - AES128
    - AES256*/
    mixin field!(string, "cipher");

    /** type of cipher to use for encryption
    default MD5
    available
    - MD5
    - SHA
    - SHA256*/
    mixin field!(string, "hash");

    /// indicates if junction is checking peers with systems CA's
    /// NOTE: not supported yet
    mixin field!(bool, "checking");

    /// indicates if junction is encrypting outbound signals
    mixin field!(bool, "encrypting");

    /** this side of the junction does not inform sending side of acceptance
    therefore it keeps internals secret
    (cannot allow anycast) */
    mixin field!(bool, "hiding"); 

    /** send signals into junction and do not care about acceptance
    (cannot use anycast) */
    mixin field!(bool, "indifferent");

    /** refuse multicasts and anycasts passig through junction */
    mixin field!(bool, "introvert");
}

/// metadata of a junction
class JunctionMeta : IdData {
    mixin data;

    mixin field!(JunctionInfo, "info");
    mixin field!(string, "type");
    mixin field!(ushort, "level");

    /// path to private RSA key (no key disables encryption and authentication)
    mixin field!(string, "key");
}

class MeshJunctionInfo : JunctionInfo {
    mixin data;

    mixin field!(string, "addr");
}

class MeshConnectorMeta : Data {
    mixin data;

    mixin field!(string, "type");
}

class MeshJunctionMeta : JunctionMeta {
    import flow.core.data;

    mixin data;

    mixin field!(string[], "known");
    mixin field!(size_t, "timeout");
    mixin field!(size_t, "ackTimeout");
    mixin field!(size_t, "ackInterval");

    mixin field!(MeshConnectorMeta, "conn");
}

/// metadata of an entity
class EntityMeta : Data {
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin field!(Data[], "config");
    mixin field!(Data[], "aspects");
    mixin field!(ushort, "level");
    mixin field!(Event[], "events");
    mixin field!(Receptor[], "receptors");

    mixin field!(TickMeta[], "ticks");

    mixin field!(Damage[], "damages");
}

/// referencing a specific entity 
class EntityPtr : Data {
    mixin data;

    mixin field!(string, "id");
    mixin field!(string, "space");
}

/// type of events can occur in an entity
enum EventType {
    /** sending signals OnTicking leads to an InvalidStateException */
    OnTicking,
    OnFreezing
}

/// mapping a tick to an event
class Event : Data {
    mixin data;

    mixin field!(EventType, "type");
    mixin field!(string, "tick");
    mixin field!(bool, "control");
}

/// metadata of a tick
public class TickMeta : Data {
    mixin data;

    mixin field!(TickInfo, "info");
    mixin field!(bool, "control");
    mixin field!(Signal, "trigger");
    mixin field!(TickInfo, "previous");
    mixin field!(long, "time");
    mixin field!(Data, "data");
}

/// info of a tick
class TickInfo : IdData {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(string, "type");
    mixin field!(UUID, "group");
}

/// mapping a tick to a signal
class Receptor : Data {
    mixin data;

    mixin field!(string, "signal");
    mixin field!(string, "tick");
    mixin field!(bool, "control");
}