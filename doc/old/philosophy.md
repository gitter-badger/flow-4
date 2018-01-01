# Philosophy

To understand the aim of this project, it is necessary to first think about your perspective.

## Introduction
As a very curious person, I used to take a peek into many topics. A few of this topics were the chaos theory, attractors, non-linear systems and fractals.

### Simulation Studio
For a better understanding of the behaviour of interaction driven non-linear systems, I created a software called [Simulation Studio](http://ss.ralphs-tech.com/). This software aims to allow you to define a nonlinear system consisting of multiple subsystems of different types. This subsystems can interact with each other in a way you can define. The non-linear system then can be integrated over time while you have the possibility to visualize the data generated.

### Experiments
With this tool at hand I begun to play around with certain things like the gravitational theory and attractors. 

#### The tree
But the really interesting experiment whose implications I begun to understand only a lot of time later was the idea to analyze whats necessary for a non-linear system integrated over time to generate fractal order.

So I played a bit around and came to a system consisting of four types of subsystems which transit from one into another having 1100 instances of the one initial type and 1 instance of another initial type acting as root interacting with each other (for details see [Fractal-3D](https://github.com/RalphBariz/RalphsDotNet/raw/SimulationStudio-v1.12/Apps.SimulationStudio/RalphsDotNet.Apps.SimulationStudio/Sample/Fractal%20-%203D.sdb)):

![](https://github.com/RalphBariz/flow/raw/master/doc/image/phil/2016-08-17%2016_08_01-Simulation%20Studio.png)

#### The synergy
How already mentioned, I wasn't able to see all the implications at that time. What I realized in that moment was that natural fractals may not be generated how usualy assumed by sequential but by parallel iteration.

Much later when I returned to that topic (and obviously understood a few things in the meantime) I realized that whatever is going on there is not just what I defined at creating that system. I had to admit, that I found some kind of functional attractor containing much more substance than just the code I wrote. I found a synergy, one of many meaningful differential solutions to the problem I defined by this four system types and their distribution. For sure, there should be much more meaningless than meaningful solutions to this problem.

What if one could translate this into a programing paradigm so a programmer can try to code solutions for such a non-linear problem? What would be the possibilities? Why isn't doing anyone yet?

## The perspective problem
When thinking about these questions I recognized, that this way of thinking is just not possible using the way we are common to see the world. So I had to find a formulation for the necessary transformation of perspective.

### Top-down perspective
The most representative question related to this perspective is a very familiar one: "What does it consist of?"
I can ask this question for almost anything man made and get a consistent answer leading me to the ability to reproduce it.
It is no secret, that science is asking this question for beeings created by nature since a very long time but failing at reproducing them in their entirety. They are simply not getting a consistent answer.

We humans use to see things we want to analyze or produce as something casted consisting of coherent parts. We say we want to build a car and think about what components we need. If you look at almost anything made by man you will find this perspectives imprints. The consequences of the usage of this perspective like obviously designed geometries, coherent parts, limited complexity and many more. You simply see its very special and static nature. For most tasks we are used to this perspective. Often we are even not able to imagine there could be another. It is good enough for achieving the most things of our actual world. Everything has to be the precise sum of its parts.

### Bottom-up perspective
An adequate representative question to this perspective would be: "What is happening?"

As soon as you look at anything created by nature you will realize, that the top-down perspective simply doesn't allow you to understand the nature of most things we face in this world. It simply doesn't fit. To understand these phenomenas you have to switch your perspective. You need to begin understanding that there are smaller entities standing mostly for their own interacting with other entities of the same or a different nature. In opposite to the *Top-down* scheme the focus lies at the function, the interactions. This interactions are creating persisting meaningful solutions to non-linear problems whereas meaningless are simply disappearing. This results in things beeing not only more than the sum of their parts but also highly dynamic, scale- and reusable. Randomly cut down a tree and in most cases it will still function. Randomly cut down a car and in most cases it will not function anymore. Thats the consequence of the perspective used at creation.

## The functionality flow problem
### "Classic" programming paradigms
In software development we are common to produce things
wich are just doing something most time exactly specified before(big picture).
I never saw a developer thinking about functionality flow
and/or causality(except when hunting bugs caused by unwanted synergies).
The reason I see is exactly the same perspective problem as mentioned before.
There is something which should fullfill a certain task,
"lets think about what we need to accomplish it".
We look from the top down trying to estimate what parts we need.

This leads to something like:

![](https://github.com/RalphBariz/flow/raw/master/doc/image/phil/classic_ff.png)

This way it is hard to guarantee a continous, stable and constant flow of functionality.

### Organic programming
From a bottom-up perspective it looks very different.
Here you have to think about causality and effect at a very low level of task implementation.
You've got small pieces of functionality causing activities in a system
interacting with other systems and therefore activating also them.
There is no big picture you could hunt, you actually need to draw one while coding.
You have to focus at functional **entiti**es and **organ**s doing things in a way you can and should see isolated.
Therefore you get an overwhelming amount of possibilities to let entities/organs interact and have to aim the right one.
Your mind has to controll possibility and force causality by reason.

On the practical side you get a few benefits.
* Probably strong additive usage of non abstract imagination abilities and short term memory.
* Intuitive coding is not only possible but the way to go.
* Natural controlled loops without using anything like while, for and similar.
* Dynamic flows(strings of functionality) while avoiding monstrous hierarchies.
* Automatic threading by concept.
* Usage of all CPUs and all their cores by concept.
* Near homogenous load balancing by concept.
![](https://github.com/RalphBariz/flow/raw/master/doc/image/phil/organic_ff.png)

In the case of FLOW organic programming means to code a solution to a signal driven non linear system (different to the already mentioned interaction driven non linear system). The main difference is the layer of execution. While an interaction driven nls is ideal for creating a media, a signal driven nls requires such a media. Signallig is abstracted interaction.
For creating interaction driven nls communicating with the swarm, flow includes an IdNls **alien** entity capable of running such a nls on OpenCL accelerators (usually modern GPUs) which is meant to be the successor of the Simulation Studio.


**Albert Einstein once said, “Imagination is more important than knowledge. For knowledge is limited to all we now know and understand, while imagination embraces the entire world, and all there ever will be to know and understand.”**

Continue to [Specification](https://github.com/RalphBariz/flow/blob/master/doc/specification.md)
