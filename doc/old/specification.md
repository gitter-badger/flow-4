(~~scratched text is not implemented yet~~)

To understand the specification a shift away from the usual perspective is necessary. Therefor you should first read the [Philosophic manifest](https://github.com/RalphBariz/flow/blob/master/doc/philosophy.md).

## Swarm
A set of functional entities running on one or many connected devices represents a (heterogeneous)**swarm**.
~~Its composition can be automatically determined by a broadcasting system or, if broadcasting is not an option (internet, different subnets or a network hosting multiple swarms), by a listing service. As an alternative its composition can be explicitly defined by [entity](#Entity) configurations what makes sense for achieving a specific predefined solution.~~

![](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/swarm.png)

## Device
A **device** is a physical unit connected to a communication network or hosts a signle swarm.

## Domain
A **domain** is a logic category for signals and [entities](#Entity). Where does it belong to? A domain is required for addressing [entities](#Entity) listening for the same signal acting in different domains.

Example: The public transport(service) and their timetables(data objects) from different cities(domains).
You can search for public transport organizations of a cretain city or maybe for their timetables.

It is build of strings separated by '.' and opposing to web domains read from left to right.

Simply not passing sublevels will return the whole domain(example: existing domains "foo.bar.one" and "foo.bar.two" are matched by passing "foo.bar" or for easier machine generation "foo.bar.").
~~When addressing domains it is possible to use regex matches in form of "foo./b.*r[0-9]/.subfoo".~~

~~A more complex example may be:~~
* ~~Existing: "foo.123.bar.one.bla", "foo.123.bar.two.bla", "foo.223.bar.one.bla", "foo.224.bar.two.bla", "foo.223.bar.two.bli".~~
* ~~Search pattern: "foo./[0-9]23/.bar..bla".~~
* ~~Results: everything from "foo.123.bar.one.bla", "foo.123.bar.two.bla", "foo.223.bar.one.bla".~~
* ~~Explaination: as you can see "foo.224.bar.two.bla" is not matching "/[0-9]23/" and "foo.223.bar.two.bli" is not matching "bla"~~

## Data
Flow offers you the possibility to easily define **data** objects having certain characteristics . They can contain **field**s(1:1) and **list**s(1:n). Lists cannot be set but, you may **put** something in **remove** it again or completely **clear** its content. Data may be **clone**ed(deep cloning the hierarchies memory). You may also **get** and **set** fields or lists by their name and type informations.

## Signal
There are different signal types which are derrived from data.
All signals contain an **id** of type UUID.
All signals contain a **source** referencing to an entity.
* An **unicast** is a directed signal to a specific entity.
It contains **no domain** and a **destination** referencing to an entity.
A **send** is sucessful if the receiver is found and accepted the signal.
![](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/unicast.png)
* An **anycast** is choosing a receiver out of a set of possible ones.
It contains a **domain** nad **no destination**.
A **send** is sucessful if a receiver is found which accepted the signal.
![](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/anycast.png)
* A **multicast** is addressed to a domain of entities or broadcasting
(all entities) when domain stays empty.
Its fields are a **domain** and **no destination**.
A send is successful if there are listeners available.
Delivery assurance is up to the communication protocol.
![](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/multicast.png) [](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/broadcast.png)


In general, when you specify a data type at signals definition
it gets a field **data** and an unsigned integer **seq**uence
indicating the order of the data packets.
Think in prallel, no streaming necessary.

## Entity
An **entity** is a functional entity. A process on a device can host one or more entities.
Each entity has to be control and if necessary persistable by its process.

An entity **listen**s for certain signals triggering internaly activity.

![](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/entity.png)

There can be entities one or more but not exclusively of following natures. This has to be seen more as an ideology.
* **Systemic entity**: It provides functionality necessary for a swarm beein able to function in a cretain environment.
* **Observing entity**: It reacts on multicasts from the swarm but also interrupts of the hardware.
* **Servicing entity**: It serves the environment by listening to anycasts and generates signals in response.
* **Interfacing entity**: An interfacing entity provides an interface to others(including biological units) outside the swarm.

~~There are a few(one at the moment) predefined systemic entities:~~
* ~~**Listing service**: provides as the name says a listing service, so other entities can find each other in a communication network not supporting broadcasting.~~

All entities have an **id** of type UUID.

All entities have a domain. 

All entities have a scope:
* **Process**: the data object is only available to the process hosting the entity it was created in.
* **Global**: the data object can be synchronized to all processes hosting the swarm.

### Tasking
At developing software, we are common to code a functional flow executing code from across a hierarchy of functions and objects to acomplish **task**s. Honestly I think this kind of coding is overcomplicating things, inhibiting control and a stable functional flow.

Whereas the enities are supporting also classic implementation, I want to introduce an, at least for me, new way of thinking functionality.

Tasking entities provide the possibility of describing isolatable functionality as **task**s triggered by signals.
A task is started in a new thread called **tasker** and may lead to a following task running in the same tasker. It tries to provide a dynamic sequential flow of logically delimited functionality.

From each tasker new ones may be forked using a given task.

The synchronization is happening via private signals and an entity context which should be a data object so the entity is serializable and a pure statemachine.

Continue to [Implementation guide](https://github.com/RalphBariz/flow/blob/master/doc/implementation.md)
