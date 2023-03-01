---
layout: post
title: 'Logical Time and Deterministic Execution'
tags: plt formal_methods philosophy
author: Alex Weisberger
---

Recently, Tomorrow Corporation released [this video of their in-house tech stack](https://www.youtube.com/watch?v=72y2EC5fkcE) doing some truly awesome time-travel debugging of a production-quality game. You should watch this video, even if you don't read this post, because the workflow that they've created is really inspiring. The creator kept bringing up the fact that the reason their tools can do this is that they have determinism baked into them at the very foundational levels. You simply can't bolt this on at higher levels in the stack.

This got me thinking - not only do we rarely have this level of control in our projects, but I think it's rare to even understand how determinism is possible in modern systems that are interactive, concurrent, and distributed. If we don't understand this, we can't ever move our tools toward determinism, which I think is a very good idea. It turns out that even if we can't predict exactly how a program will execute in a _specific_ run, we can still model and reason about it deterministically. This is a prerequisite for most formal methods, and while I understand that formal methods aren't everyone's cup of tea, this is the number one thing that I wish more people understood. So today, we won't be talking about testing or verifying anything, we'll just be looking to better understand software in general by diving into logical time and how it enables deterministic reasoning.


# User Interaction and Non-Deterministic Choice

Talk of non-determinism can get very abstract very quickly, but there is a practical manifestation that we've all observed even if we didn't know the term: _non-deterministic choice_. An application with a user interface is a classic example of a system with non-deterministic choice - no one can predict the order that a user will click through the interface, and the user is free to make any choice that's visible and enabled.

We'll introduce an example to get more specific, and it's important to _always_ use [TodoMVC](https://todomvc.com/) as the interactive application example[^fn1] (here's [one of the implementations](https://todomvc.com/examples/js_of_ocaml/) if you want to click around). In TodoMVC, we can add new named to-do items and then mark them as completed. We can also remove a to-do without marking it as completed. Like all interactive applications, we can do this in any order though, and these are all valid sequences of actions:

1.
* Add to-do named "t1"
* Mark "t1" as completed

2.
* Add to-do named "t1"
* Remove "t1"
* Add to-do named "t2" 
* Mark "t1" as completed

3.
* Add to-do named "t1"
* Mark "t1" as completed
* Add to-do named "t2"
* Mark "t2" as completed
* Add to-do named "t3"
* Add to-do named "t4"
* Add to-do named "t5"
* Remove "t3
* Add to-do named "t6"
* Add to-do named "t7"
* Remove "t4"
* Add to-do named "t8"
* Add to-do named "t9"
* Mark "t6" as completed

We can visualize this non-determinism with a state graph:

<img src="/assets/TodoMVCStates2.png"/>
<div style="display: flex; justify-content: center;">
  <img src="/assets/TodoMVCLegend2.png" style="width:64%"/>
</div>

A non-deterministic choice exists when more than one transition arrow flows away from a given state. It means that all of them are valid choices that can occur in separate executions, but one has to _somehow_ be chosen to proceed through the state graph. An interactive application lets the user decide via the UI, but as we'll see later, there are other things that can make choices. Functionally, it doesn't matter who does the choosing.

A quick aside: this is the complete behavior up to a bound of 2 to-dos. Physical space constraints aside, the full state graph of TodoMVC is theoretically infinite, because you can always add a to-do with a new name. Visualizing infinite bubbles is painful for everyone involved, so we place a constraint on the model along the lines of "there are only two to-dos in the entire universe." This is a silly constraint, but it helps us visualize the state space in a manageable way. Bounded models also help with [making properties checkable](https://en.wikipedia.org/wiki/Model_checking#Techniques), but we're not talking about that today because we're not actually doing formal methods!


Let's look at an example run through the program by picking specific choices. We'll start at the gray initial state, add two to-dos named "t1" and "t2", and then we'll complete them both. Here's that path in red:

<img src="/assets/determinism/TodoMVCPath1.svg"/>

We can get to the same final state a different way, by adding to-do "t2", completing it, then adding to-do "t1" and completing it:

<img src="/assets/determinism/TodoMVCPath2.svg"/>

We all know how software works intuitively, but seeing these runs against the full state graph hints at a couple of precise definitions: software behavior is simply a sequence of states, and a program is a set of allowable behaviors. It also gives us our first step towards determinism. When a non-deterministic choice exists, we don't know which path will be taken in a specific program run, but we do know what all of the possible runs are. Each of those runs is a totally deterministic behavior.

Said another way, a non-deterministic choice becomes deterministic when we pick one.

For fun, here's the state graph of TodoMVC with 5 to-dos:

<img src ="/assets/determinism/TodoMVCBigStates.svg" />

Determinism isn't necessarily easy.

# Concurrency

Concurrency is another notorious source of non-determinism, but let's define why. Imagine we have N network requests that start in an idle state, begin fetching some data, and eventually complete. Continuing to keep our bounds small, let's start with N = 2:

<img src="/assets/determinism/RequestsFont.svg" />
<div style="display: flex; justify-content: center;">
  <img src="/assets/determinism/RequestsLegend.svg" />
</div>

In every state, we can either initiate an uninitiated request or an in-progress request can complete. It's possible for different requests to complete in different orders too, e.g. request 0 can complete first:

<img src="/assets/determinism/Requests-Req0.svg" />

And request 1 can also complete first, even if request 0 was initiated before it:

<img src="/assets/determinism/Requests-Req1.svg" />

The order that requests complete is a non-deterministic choice, which we've already seen, but there's a major difference from the TodoMVC example: the OS or language runtime determines the choice, not a user. This is one reason why concurrency is a constant thorn in the side, and feels much more complex than the non-determinism of user interfaces. We literally don't have control over the order of operations. 

In the same way as the choices in the user interface, though, we just have to account for all of their combinations, and then we can know which orders of execution are possible. Another way to think about this is that if a race is possible, both sides of the race will always eventually occur, and we have to plan for both cases.

Because N = 2 is no fun, here's N = 5 (i.e. 5 concurrent requests) which has 639 distinct states:

<img src="/assets/determinism/Requests-Req5.svg" />

I'm sure a mutex will make this more manageable.

# Logical Time, Time-Travel, and Beyond

Both state graphs show the set of all behaviors for the given system, and they do this by showing _logical_ time, in contrast to physical time. A user might wait 17 years before selecting a transition in a UI, or an OS scheduler might pick one thread to execute while another waits for I/O. The real-world execution of a program runs in physical time, but our state graphs are only concerned with abstract states and transitions between them. And good thing for that - it would be awkward to have to wait 17 years to understand the possible behaviors of TodoMVC.

Beyond helping us understand the complete picture of all of the different interleavings of transitions, logical time is also what enables time-travel debugging. We can't logically move through a system until it's been properly decomposed into states and the steps between them. This in itself is a design space - how much of the system state do we store vs. derive? How much additional state do we add to make things possible like searching for states by timestamp?

All we need for logical time are states and transitions between them, i.e. logical time is inherently tied to state machines / transition systems. In fact, a time-travel debugger can pretty much be seen as a user interface for a state machine. But most importantly, this mental model allows us to have a totally deterministic view of the behavior of a complex system. That in turn enables powerful features like time-travel debugging.

To take advantage of logical time, this model has to be built into an application somehow. Because our tools generally don't have any notion of determinism, you often see this with language-layer patterns like Redux or the Elm Architecture, or architecture-level patterns like event sourcing. All of those patterns reduce nicely down to the sequential state machine model presented here, but they're up to the application developer to implement. The question that the Tomorrow Corporation demo asks is: what do we get if our tools did this for us without any additional effort?

Imagine not needing to have to add sleeps / retries to tests of asynchronous behavior. Or imagine a tool that identified concurrent code and showed us the different interleavings that we might have otherwise been unaware of, and allowed us to step through and try each of them out. I'm not a Nix user (yet), but others are already imagining a world with deterministic package management. Non-determinism is fundamentally at odds with human brains it seems like, so I for one would love to see more determinism in any tool that I use.

To get there, we'll have to understand and implement logical time.

# Outro

I have no idea how the tools at Tomorrow Corporation are implemented, but I respect their commitment to determinism. Non-determinism is a part of life, but to have full control over a system it's essential to view it through the deterministic lens of logical time. Because of things like concurrency which often rely on OS or language features that we can't directly interact with, this can be difficult, but that video shows that there's tremendous value in baking determinism further down into our foundational tools.

The main thing I wanted to share in this post was a specific mental model. Sequential state machines are a tried and true model with deterministic properties, and they've legitimately changed how I look at software. In this model, a program is a set of behaviors, where each behavior is a sequence of states. It's hard to imagine reducing programming down to a simpler explanation than that, and that clarity is necessary for wrangling complexity.

The images in this post were generated from [TLA+ specs](https://learntla.com/), which I won't really explain, but hopefully they show that it doesn't take a ton of effort to write simple models. TLA+ is a logic and tool which has this mental model at its foundation. I can't recommend learning and using it enough. Its companion model checker makes the act of modeling tactile, and you can get machine feedback on your models vs. getting stuck in state-machine quicksand. The state graph visualizer is also very handy sometimes, though as was shown here is more useful when the bounds of the model are small.

Here's the spec for TodoMVC:

```
------------------------------ MODULE TodoMVC ------------------------------
VARIABLES todos, completedTodos

Todos == {"t1", "t2"}

Init == todos = {} /\ completedTodos = {}

RemainingTodos == Todos \ todos

IncompleteTodos == todos \ completedTodos

AddTodo == \E t \in RemainingTodos: todos' = todos \union {t} /\ UNCHANGED completedTodos

CompleteTodo == \E t \in IncompleteTodos: completedTodos' = completedTodos \union {t} /\ UNCHANGED todos

RemoveTodo == \E t \in todos: todos' = todos \ {t} /\ completedTodos' = completedTodos \ {t}

Next == AddTodo \/ CompleteTodo \/ RemoveTodo

=============================================================================
```

And here's the spec for the concurrency example:

```
---------------------------- MODULE Concurrency ----------------------------
EXTENDS Integers

VARIABLES requests

Requests == 0..2

Init == requests = [r \in Requests |-> "idle"]

SendRequest(r) == requests' = [requests EXCEPT ![r] = "fetching"]

RecvResponse(r) == requests' = [requests EXCEPT ![r] = "done"]

SendReq == \E r \in Requests: requests[r] = "idle" /\ SendRequest(r)

RecvResp == \E r \in Requests: requests[r] = "fetching" /\ RecvResponse(r)

Terminate == \A r \in Requests: requests[r] = "done" /\ UNCHANGED requests

Next == SendReq \/ RecvResp

=============================================================================
```

Even if you never use TLA+, the mental model presented here can help understand software at a more fundamental level. Kudos to the Tomorrow Corporation team for an inspiring set of tools that I hope pushes people to think about determinism more.

<hr>

[^fn1]: \s, but it actually is a good learning tool and proxy for most interactive applications
