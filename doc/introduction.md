# Introduction
You will learn how to initialize and use the basic components in a static environment.
For this you'll need to create a D executable which is linked against lib/libflow-core.so.

This scenario tests the signal passing through a junction.

[SOURCECODE](src/introduction/main.d)

## Neccessary imports
```D
import flow.core;   // runtime of flow
```

## Data of entities
They are kind of memory of entities.
There is the config which is meant to store configuration data.
And there is the context meant to store runtime information.
However this separation is just pro forma.
While our first entity notes if it was successfully sending the casts,
our second one notes if it got them.
```D
// you can inherit other data types
/// aspect of a sending entity
class TestSendingAspect : Data {
    // mixing data functinality
    /* this is also required when inheriting
    from a custom data type */
    mixin _data;

    // creates a field "dstEntity" of string type
    /// this ist some field documentation
    /// <-- NOTICE
    /// id of destination entity of the signals to send
    @field string dstEntity;

    /** This is some more field documentation */
    /** <--
            NOTICE
                   --> */
    /** domain of the space hosting destined entity
    at the other side of the junction */
    @field string dstSpace;

    /* creates an array "foo" of string[] type
    however is is not required for this certain scenario */
    /// for sure you should document the array too
    @field string[] foo;

    /** here sender nots if
    the unicast was confirmed */
    @field bool unicast;

    /** ... */
    @field bool anycast;

    /** ... */
    @field bool multicast;
}

// receipting entity has no configuration

/// aspect of a receipting entity
class TestReceiptingAspect : Data { mixin _data;
    /** used by receipting entity
    to store the receipted unicast */
    @field Unicast unicast;

    /** ... */
    @field Anycast anycast;
    
    /** ... */
    @field Multicast multicast;
}
```

## Signals
They do not contain any custom data for this scenario.
There is one signal for each signal type.
```D
/** type of the unicast signal to use
derrives from a certain signal type */
class TestUnicast : Unicast {
    // still required since a signal is data
    mixin _data;
}

/** ... */
class TestAnycast : Anycast { mixin _data; }

/** ... */
class TestMulticast : Multicast { mixin _data; }
```

## Ticks
Half of this ticks are defining the change of a "confirmed..." field on an entities information,
the other half are defining the change of a "got..." field on an entities information.
```D
/** tick defining the change of setting TestSendingAspect.unicast = true
and what needs to happen for this change aplly */
class UnicastSendingTestTick : Tick { // only derriving from Tick
    /** checks if the entity can accept the signal.
    - to synchronize in here is a pretty bad idea
    - exceptions are returning false and a log entry
    - however not required for this scenario */
    override bool accept() {return true;}

    /** since tick functionality itself could also crash.
    if a crash should cause entity to get damaged and freezed,
    just do not override it(super.error is doing what you see here.
    otherwise override it to catch the throwable */
    override void error(Throwable thr) {throw thr;}

    /** assigns space to deliver an unicast to configured entity in its space.
    it notes if signal was accepted into aspect.unicast */
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
            Thread.sleep(5.msecs);
        }
    }
}

/** ... */
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
            Thread.sleep(5.msecs);
        }
    }
}

/** ... */
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
            Thread.sleep(5.msecs);
        }
    }
}

/** stores triggering signal into aspect's information TestReceiptingAspect */
class UnicastReceiptingTestTick : Tick {
    override void run() {
        auto asp = this.aspect!TestReceiptingAspect;
        asp.unicast = this.trigger.as!Unicast;
    }
}

/** ... */
class AnycastReceiptingTestTick : Tick {
    override void run() {
        auto asp = this.aspect!TestReceiptingAspect;
        asp.anycast = this.trigger.as!Anycast;
    }
}

/** ... */
class MulticastReceiptingTestTick : Tick {
    override void run() {
        auto asp = this.aspect!TestReceiptingAspect;
        asp.multicast = this.trigger.as!Multicast;
    }
}
```

## Main
This is the content of the main function/the executables entry point.
First it creates the systems order using helper functions, then kickstart it.
After everything happened it stops and gets out the information.
Then is checked for correctness.

This functionality generates just data which can get and usually is serialized.
It is the same kind of data which falls out at the end.
That means if you got a system you can freeze it, snapshot it, end the process
and restart everything again. It will continue where it got frozen.

```D
void main() {
    import core.thread : Thread;
    import core.time;
    import std.uuid;

    // creates a process which hosts our spaces
    auto proc = new Process;
    // the process should be destroyed when exiting scope
    scope(exit) proc.dispose();

    // defines domains for our spaces
    /// sender hosting space's domain
    auto sDomain = "ss.test.doc.flow";
    /// receiver hosting space's domain
    auto rDomain = "rr.test.doc.flow";

    /* defines an id for an in process
    junction spaces can use to communicate */
    auto junctionId = randomUUID;

    /* generates meta data for our
    first space hosting sending entity */
    auto ssm = createSpace(sDomain); { // the own scope is just for readability
        /* adds the entity "sending" having
        a sending aspect */
        auto ems = ssm.addEntity("sending"); {
            // adds sending aspect
            auto asp = new TestSendingAspect; ems.aspects ~= asp;
            /* sets the destination of the signals */
            asp.dstEntity = "receiving";
            asp.dstSpace = rDomain;

            /* when entity starts ticking
            what implies that it is not freezed anymore
            it will execute this three ticks */
            ems.addTick(fqn!UnicastSendingTestTick);
            ems.addTick(fqn!AnycastSendingTestTick);
            ems.addTick(fqn!MulticastSendingTestTick);
        }

        /* attaches first space to junction */
        ssm.addInProcJunction(junctionId);
    }
    
    /* generates meta data for our
    second space hosting receipting entity */
    auto rsm = createSpace(rDomain);
    auto emr = rsm.addEntity("receiving"); {
        // adding receipting aspect
        emr.aspects ~= new TestReceiptingAspect;
        /* when entity receipts a signal Test***cast
        it triggers a tick of type ***castReceiptingTestTick */
        emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceiptingTestTick);
        emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceiptingTestTick);
        emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceiptingTestTick);
    }
    rsm.addInProcJunction(junctionId);

    // created spaces now are added to a process
    auto sSpc = proc.add(ssm);
    auto rSpc = proc.add(rsm);

    /* start processing spaces/make them ticking.
    receipient before sender since
    recipient must be up when sender starts ticking */
    rSpc.tick();
    sSpc.tick();

    // wait 10 miliseconds it to finish
    // (it could wait for one or more spaces to freeze)
    Thread.sleep(50.msecs);

    // causes the processes to freeze
    rSpc.freeze();
    sSpc.freeze();

    // snapshots/pictures our spaces information
    auto nssm = sSpc.snap();
    auto nrsm = rSpc.snap();

    // checks if all got their testsignal
    auto rAsp = nrsm.entities[0].aspects[0].as!TestReceiptingAspect;
    assert(rAsp.unicast !is null, "didn't get test unicast");
    assert(rAsp.anycast !is null, "didn't get test anycast");
    assert(rAsp.multicast !is null, "didn't get test multicast");

    // checks if all got a confirmation for their testsignal
    auto sAsp = nssm.entities[0].aspects[0].as!TestSendingAspect;
    assert(sAsp.unicast, "didn't confirm test unicast");
    assert(sAsp.anycast, "didn't confirm test anycast");
    assert(sAsp.as!TestSendingAspect.multicast, "didn't confirm test multicast");
}
```