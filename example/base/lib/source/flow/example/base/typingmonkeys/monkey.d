module flow.example.base.typingmonkeys.monkey;
import flow.example.base.typingmonkeys.signals;

import flow.base.blocks, flow.base.data, flow.base.dev;

enum MonkeyEmotionalState {
    Calm,
    Happy,
    Dissapointed
}

/** ticks inside an entity can interact with each other
using a context the entity provides.
* basically its the memory of the entity.
* you can implement anything derriving from Object,
but you should stay with a data objects in most cases
* The monkey needs to know just two things
one for measuring its performance for us
and one to know how it feels */
class MonkeyContext : Data {
	mixin data;

    mixin field!(ulong, "counter");
    mixin field!(MonkeyEmotionalState, "state");
}


// what can the monkey do and how?
/** it should type
a tick has a [name] and defines an [algorithm].
the algorithm takes an [entity],
a [ticker] to control the internal flow */
class Write : Tick {
    mixin tick;

    override void run() {
        /* some imports necessary
        for the d and phobos functionality used */
        import std.random, std.conv;

        /* sadly at the moment the context has
        to be casted to its type or interface */
        auto c = this.context.as!MonkeyContext;

        /* when the monkey gets happy it is distracted
        and when dissapointed it is restive
        so it only types when its calm */
        if(c.state == MonkeyEmotionalState.Calm) {
            byte[] arr;

            // get 4kb data from urandom
            for(auto i = 0; i < 1024*4; i++)
                arr ~= uniform(0, 255).as!byte;
            
            // create multicast
            auto s = new HebrewText;
            s.data = new HebrewPage;
            s.data.text = arr;
            s.data.author = this.entity.ptr;
            // send multicast
            this.send(s);

            // note the new page (++ sadly is not working yet)
            c.counter = c.counter + 1;

            // just something for us to see
            this.msg(DL.Debug, "amount of typed pages: "~c.counter.to!string);
            
            // tell the ticker to repeat this tick (natural while loop)
            this.repeat();
        }
    }
}

/** this one is pretty simple */
class GetCandy : Tick {
	mixin tick;

	override void run() {
        auto c = this.context.as!MonkeyContext;

        c.state = MonkeyEmotionalState.Happy;

        this.send(new ShowCandy);

        // just something for us to see
        this.msg(DL.Debug, "got happy");
    }
}

/** this one too */
class SeeCandy : Tick {
	mixin tick;

	override void run() {
        if(!this.signal.source.identWith(this.entity.ptr)) {
            auto c = this.context.as!MonkeyContext;

            c.state = MonkeyEmotionalState.Dissapointed;

            // just something for us to see
            this.msg(DL.Debug, "got dissapointed");
        }
    }
}

/** finally we define what a monkey is.
what it listens to and how it reacts
* so there is one main sequential tick string
* and two just setting something */
class Monkey : Entity {
    mixin entity;

    mixin listen!(
        // type id of a candy
        fqn!Candy,
        // it gets happy
        fqn!GetCandy
    );

    mixin listen!(
        // type of "any monkey shows it candy"
        fqn!ShowCandy,
        // if it is not seeing the own candy it gets dissapointed
        fqn!SeeCandy
    );
}
