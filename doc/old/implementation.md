## About
For how to implement a flowing swarm I ask you to think about following gedankenexperiment [Infinite-Monkey-Theorem](https://de.wikipedia.org/wiki/Infinite-Monkey-Theorem) and imagine following scenario.
* there is a room full of monkeys,
* an overseer searching their texts for the bible (can search all the texts in parallel),
* an >0 amount of monkeys typing (random bytes) in hebrew
* unfortunately the overseer speaks only german(string) and therefore needs a translator
* and for sure the overseer rewards the monkey writing the bible

You may ask:
* What communication (signaling) happens here?
* What is the communicating **entity**?
* What signals causes what activity (**task**ing) in this scenario?

Therefore **tasks** can be induced by **signal**s into **entities**.

## Components
### Signaling
A signal is information transmitted into the swarm.

The following signaling schemes exist:
* **unicast** messages are directed to a single **destination**
* **multicast** messages are directed to a **domain** (leave domain empty for all)
* **anycast** messages are directed to a **domain** and accepted by exact one destination

### Data management
A signal is nothing but a piece of data with a special purpose.
At the moment data hierarchies can contain fields(1:1) and lists(1:n)

### Entity
An **entity** is **listen**ing into the swarm for signals, if it accepts the signal, a **task** is triggered inside an own thread called **tasker**.

### Tasking
A **task** is an atomic algorithm.
Such tasks can be executed as strings of pearls,
able to fork, to loop, etc.

There are also synchronized tasks (**stask**).
Synchronized tasks are meant to set a statemachine in a synchronized way.
It is guaranteed, that all listener are waiting for the **stask** to finish.
Never send signals from a synchronized task
except you can assure there wont happen a deadlock.
Otherwise send signals from a **next** normal task.

An internal flow is hosted by a **tasker**

**An internal flow is a subset of a full flow, a defined piece of causality.**

### Organs
Finally an **organ** is a **start** and **stop**able collection of entities with a specific configuration.
Since entities are kind of generic and should be always designed with a category of tasks in mind, the organ configures it proper for a specific task.

## Lets see
Most code is pretty simple. Its just a definition of the composition of the swarm(**entity**, **listen**) and of the signaling(**unicast**, **multicast**, **anycast**).
The **task** contains an algorithm.
* in [signals.d](https://github.com/RalphBariz/FLOW/blob/master/example/base/shared/source/flow/example/base/typingmonkeys/signals.d) you find declarations of signals used by more than one entity
* in [monkey.d](https://github.com/RalphBariz/FLOW/blob/master/example/base/shared/source/flow/example/base/typingmonkeys/monkey.d) you find signals, data, tasks and the entity of the monkey
* in [translator.d](https://github.com/RalphBariz/FLOW/blob/master/example/base/shared/source/flow/example/base/typingmonkeys/translator.d) you find signals, data, tasks and the entity of the translator
* in [overseer.d](https://github.com/RalphBariz/FLOW/blob/master/example/base/shared/source/flow/example/base/typingmonkeys/overseer.d) you find signals, data, tasks and the entity of the overseer
* in [typingmonkeys.d](https://github.com/RalphBariz/FLOW/blob/master/example/base/shared/source/flow/example/base/typingmonkeys/typingmonkeys.d) you find the organ casting the overseer, the translator and the monkeys
* in [test.d](https://github.com/RalphBariz/FLOW/blob/master/example/base/shared/source/flow/example/base/typingmonkeys/test.d) you find the usage of the organ and a few test only stuff(just ignore it)

**I hope you got a brief overview about what you can do with FLOW. The rest is up to your imagination.**
