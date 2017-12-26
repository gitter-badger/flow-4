module flow.core.gears.error;

private import flow.core.util.error;

/// error thrown when a process is in a dying situation
class ProcessError : FlowError {mixin error;}

/// exception indicating something went wrong in tick
class TickException : FlowException {mixin exception;}

/// exception indicating something went wrong in entity
class EntityException : FlowException {mixin exception;}

/// exception indicating something went wrong in space
class SpaceException : FlowException {mixin exception;}

/// exception indicating something went wrong in process
class ProcessException : FlowException {mixin exception;}

/// exception indicating something went wrong in junction
class JunctionException : FlowException {mixin exception;}

/// exception indicating something went wrong in junction
class ChannelException : FlowException {mixin exception;}