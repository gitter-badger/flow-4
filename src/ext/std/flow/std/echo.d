module flow.std.echo;

private import flow.core;

/// echo request to n entities
class Ping : Multicast { mixin _data; }

/// echo request to 1 entity
class UPing : Unicast { mixin _data; }

/// echo response
class Pong : Unicast { mixin _data;
    @field EntityPtr ptr;
    @field string[] signals;
}