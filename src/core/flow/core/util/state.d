module flow.core.util.state;

private import flow.core.util.error;
version(unittest) private static import test = flow.core.util.test;
private import std.traits;

/// thrown when state machine detects an invalid state for operation
class InvalidStateException : FlowException {mixin exception;}

/// thrown when state machine refuses switch to given state
class StateRefusedException : FlowException {mixin exception;}

/// state machine mixin template
abstract class StateMachine(T) if (isScalarType!T) {
    private import core.sync.rwmutex : ReadWriteMutex;

    private ReadWriteMutex _lock;
    /*protected */@property ReadWriteMutex lock(){return this._lock;}
    private T _state;

    /// actual state
    @property T state() {
        // no lock required since primitives are synced by D
        return this._state;
    }

    protected @property void state(T value) {
        auto allowed = false;
        T oldState;
        Exception error;
        synchronized(this.lock.writer) {
            if(this._state == value)
                return; // already in state, do nothing
            else {
                try {
                    allowed = this.onStateChanging(this._state, value);
                } catch(Exception exc) {
                    error = exc;
                }

                if(allowed) {
                    oldState = this._state;
                    this._state = value;
                }
            }
        }

        if(allowed)
            this.onStateChanged(oldState, this._state);
        else
            throw new StateRefusedException(string.init, null, [error]);
    }

    protected this() {
        this._lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        this.onStateChanged(this.state, this.state);
    }

    protected void ensureState(T requiredState) {
        synchronized(this.lock.reader)
            // no lock required since primitives are synced by D
            if(this._state != requiredState)
                throw new InvalidStateException();
    }

    // TODO replace ensure state or overloadings with template
    protected void ensureStateOr(T state1, T state2) {
        synchronized(this.lock.reader) {
            auto state = this._state;
            if(state != state1 && state != state2)
                throw new InvalidStateException();
        }
    }

    protected void ensureStateOr(T state1, T state2, T state3) {
        synchronized(this.lock.reader) {
            auto state = this._state;
            if(state != state1 && state != state2 && state != state3)
                throw new InvalidStateException();
        }
    }

    protected void ensureStateOr(T state1, T state2, T state3, T state4) {
        synchronized(this.lock.reader) {
            auto state = this._state;
            if(state != state1 && state != state2 && state != state3 && state != state4)
                throw new InvalidStateException();
        }
    }

    protected bool onStateChanging(T oldState, T newState) {return true;}
    protected void onStateChanged(T oldState, T newState) {}
}

version(unittest) {
    enum TestState {
        State1,
        State2,
        State3
    }

    class TestStateMachine : StateMachine!TestState {
        int x;
        bool state1Set, state2Set, state3Set;

        override protected bool onStateChanging(TestState oldState, TestState newState) {
            switch(newState) {
                case TestState.State2:
                    return oldState == TestState.State1;
                case TestState.State3:
                    return canSwitchToState3();
                default: return false;
            }
        }

        override protected void onStateChanged(TestState oldState, TestState newState) {
            switch(newState) {
                case TestState.State1:
                    this.onState1();
                    break;
                case TestState.State2:
                    this.onState2();
                    break;
                case TestState.State3:
                    this.onState3();
                    break;
                default: break;
            }
        }

        void onState1() {
            this.state1Set = true;
        }

        void onState2() {
            this.state2Set = true;
        }

        void onState3() {
            this.state3Set = true;
        }

        bool canSwitchToState3() {
            return x > 4;
        }

        bool checkState(TestState s) {
            try {
                this.ensureState(s);
                return true;
            } catch(InvalidStateException ex) {
                return false;
            }
        }

        bool checkIllegalState(TestState s) {
            try {
                this.ensureState(s);
                return false;
            } catch(InvalidStateException ex) {
                return true;
            }
        }

        bool checkSwitch(TestState s) {
            try {
                this.state = s;
                return true;
            } catch(StateRefusedException ex) {
                return false;
            }
        }

        bool checkIllegalSwitch(TestState s) {
            try {
                this.state = s;
                return false;
            } catch(StateRefusedException ex) {
                return true;
            }
        }
    }
}

unittest { test.header("util.state: state machine");
    auto t = new TestStateMachine;
    assert(t.state1Set, "initial state change wasn't executed");
    
    // t is now in state1
    assert(t.checkIllegalState(TestState.State2), "illegal state check didn't cause expected exception");
    assert(t.checkIllegalState(TestState.State3), "illegal state check didn't cause expected exception");
    assert(t.checkState(TestState.State1), "couldn't check for valid state");

    assert(t.checkSwitch(TestState.State1), "equal state switch should just pass siltent and do nothing");
    assert(t.checkIllegalSwitch(TestState.State3), "could switch state even its forbidden");

    // switching t to state2
    assert(t.checkSwitch(TestState.State2), "could not switch state even it should be possible");
    assert(t.state2Set, "state change wasn't executed");

    assert(t.checkIllegalState(TestState.State1), "illegal state check didn't cause expected exception");
    assert(t.checkIllegalState(TestState.State3), "illegal state check didn't cause expected exception");
    assert(t.checkState(TestState.State2), "couldn't check for valid state");

    assert(t.checkIllegalSwitch(TestState.State1), "could switch state even its forbidden");
    assert(t.checkSwitch(TestState.State2), "equal state switch should just pass siltent and do nothing");
    assert(t.checkIllegalSwitch(TestState.State3), "could switch state even its requirement is not met");

    // switching to state3
    t.x = 5; assert(t.checkSwitch(TestState.State3), "could not switch state even it should be possible"); 
    assert(t.state2Set, "state change wasn't executed");

    assert(t.checkIllegalState(TestState.State1), "illegal state check didn't cause expected exception");
    assert(t.checkIllegalState(TestState.State2), "illegal state check didn't cause expected exception");
    assert(t.checkState(TestState.State3), "couldn't check for valid state");
test.footer(); }