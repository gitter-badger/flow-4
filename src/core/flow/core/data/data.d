module flow.core.data.data;

private import flow.core.data.engine;

/// identifyable data
class IdData : Data { mixin _data;
    private import std.uuid : UUID;

    @field UUID id;
}