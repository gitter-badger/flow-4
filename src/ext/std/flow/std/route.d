module flow.std.route;

private import flow.core;

/// transports a previous signal
class RoutedSignal : Unicast { mixin _data;
    @field Signal signal;
}