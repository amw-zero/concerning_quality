---
layout: post
title: 'Quality and Complexity: A Case Study of the Bowling Game Kata'
tags: complexity
author: Alex Weisberger
---

Many people (myself included) have a nagging sense that quality and complexity are unavoidably connected. Though we've never been able to outright prove it, it seems obvious: we can't possibly hope to control what we don't understand. The more complex a piece of software is, the harder it must be to comprehend, verify, and ultimately modify. We collapse almost anything we don't like about software into the concept of "complexity," but what does it truly mean to be complex?



# Interviewing and the Bowling Game Kata

I once worked at a company that consistently hired software engineers, and I was in the rotation for conducting interviews. One exercise that we frequently used was the Bowling Game kata, where we walked the candidate through implementing the scoring rules of bowling. It led to surprisingly rich interviews because we added requirements incrementally via introducing new test cases to pass, and what works for the first few edge cases invariably breaks down as more cases get added. It isn't the worst proxy for "everyday" software development - most people aren't bowling experts, and even if they have passing familiarity with the basics of spares and strikes, their solution buckles once we get into the idiosyncracies of the last frame or rolling multiple strikes in a row. It's fairly similar to getting new requirements as a project continues to grow, at least that's the idea.

I've done this particular exercise with on the order of 100 people of various levels of experience, and a pretty undeniable pattern emerged - there's a very distinct turning point in the exercise that people keep hitting. I became fascinated with this turning point, because it happened so extremely predictably that I couldn't help but think that it pointed to some universal truth about program complexity and / or the upper limit on human cognitive ability.

Here's what I mean:

~~~
class TenpinStateful {
  totalScore: number;
  previousRoll: number;
  spareOccurred: boolean;

  constructor() {
    this.totalScore = 0;
    this.previousRoll = 0;
    this.spareOccurred = false;
  }

  roll(pins) {
    this.totalScore += pins;
    if (this.spareOccurred) {
      this.totalScore += pins;
    }
    this.spareOccurred = this.previousRoll + pins === 10;
    this.previousRoll = pins;
  }

  score() {
    return this.totalScore;
  }
}

let tenpin = new TenpinStateful();

tenpin.roll(6);
tenpin.roll(4);  // Roll a spare

tenpin.roll(3);  // spare bonus roll, counted twice
tenpin.roll(2);

tenpin.score();
 // 18, the spare bonus gets correctly applied
~~~
{: .language-typescript}

Once we start talking about the scoring rules for spares, the candidate commonly adds some kind of state variable like `spareOccurred`, and the edge cases immediately start to appear. We are generally able to work through them at this point, even though bugs can occur here as well. For example it's very common to forget to set `spareOccurred` back to false after a spare does occur, which must be done to prevent all subsequent frames from getting spare bonuses that didn't occur in them. More importantly this strategy makes implementing strikes incredibly difficult later on.

Some people are just naturally intelligent and can push through all this complexity. I have seen such people get to the end of the exercise with this approach, but it's very rare. Most regress to playing whack-a-mole where one test case gets fixed but another breaks. In both cases, either way, this version becomes more difficult to extend and handle new requirements. Remember - the point of the exercise isn't to implement all of the rules in one sitting, it's to build incrementally and adapt to change.

The people who do the best on this exercise quickly notice that keeping track of state is going to be difficult and switch strategies to something like the following:

~~~
class TenpinArray {
  rolls: number[];

  constructor() {
    this.rolls = [];
  }

  roll(pins) {
    this.rolls.push(pins);
  }

  score() {
    let totalScore = 0;
    for (let frameIndex = 0; frameIndex < this.rolls.length - 1;) {
      const [firstRoll, secondRoll] = 
        this.rolls.slice(
          frameIndex, frameIndex + 2
        );

      totalScore += firstRoll;
      totalScore += secondRoll;

      if (firstRoll + secondRoll === 10) {
        totalScore += this.rolls[frameIndex + 2];
      }

      frameIndex += 2;
    };

    return totalScore;
  }
}

let tenpin = new TenpinArray();

tenpin.roll(6);
tenpin.roll(4); // Roll a spare

tenpin.roll(3); // spare bonus roll, counted twice
tenpin.roll(2); 

tenpin.score();
 // 18, the spare bonus gets correctly applied
~~~
{: .language-typescript}

Here, instead of keeping track of state and adding to the `totalScore` every time a roll occurs, the rolls just get pushed into an array. The `score` method can then look to "future" rolls to apply the spare bonus using array indices. They're different approaches, sure, but it's not clear to me why extending the second one feels almost universally easier than the first. In fact, while the first solution might not be overly inspiring, the second one almost definitely will make most programmer's balk - a `for` loop? Incrementing the loop index by more than one on each iteration? Array index manipulation? Mutability? This goes against many modern trends such as preferring a functional programming style whenever possible. Invariably, though, the second solution is easier to extend, and I don't mean this in a hypothetical sense. I mean I've watched it happen dozens of times.

What is clear to me is this: some code is just actually more difficult to mentally execute. What other explanation is there? And, more importantly, what's difficult about it?

# The Two Forms of a Program

Ultimately, a computer program isn't a single thing, but two: its source code, and its runtime behavior. We analyze source code all the time. We can "find all by reference" and do holistic refactors via static analysis. We can produce its control flow graph, optimize, and compile it. Measurable complexity metrics are about code, e.g. cyclomatic complexity or ABC. You can't run a linter to find out the big O time complexity of your codebase.

The runtime behavior, however, is where the magic happens - where the program comes alive. But it is both generally more complex and harder to observe than source code. This isn't a baseless claim - a bowling program has to be able to handle all possible combinations of games, of which [there are ~5.73 x 10^18](https://clontz.org/blog/2012/12/19/how-many-distinct-outcomes-in-bowling/). That means that a bowling program has on the order of a quintillion indidivual runtime states, whereas Google has the largest codebase on Earth with a paltry 2 billion lines of code. I think it's safe to say most applications don't even make it to 1 million lines, making control flow graphs many orders of magnitude smaller than program state spaces in general.

Since source code is the interface for describing programs, though, pretty much all of our tools are focused on interacting with and observing code. Visualizing program behavior is an exercise left up to the poor human programmer's brain. Debuggers, for example, are based on a single execution of the program - you can see a stack trace up to a single point in time, but you can't see all of the _possible_ executions of a program, all of the different data states for all possible inputs, and how the program transitions through them. This is like trying to understand the solar system with a hobby telescope - the vantage point and power of the tool simply doesn't yield enough information about the subject.

Such tools [do exist](https://en.wikipedia.org/wiki/Model_checking#Tools) though. My personal favorite at the moment is TLA+, and we can use it to reason about the runtime behavior of our two algorithms and even physically graph their runtime state spaces.

# A Tale of Two State Spaces

Since the magnitude of the state space of all of the possible games of bowling is a number with 18 zeros, we can't hope to visualize the entire thing. Of course, this is a large reason why analyses like this aren't common - the sheer scale is defeating. But, still, we have options. We can analyze a subset of the state space, a common approach in bounded model checking.

So, let's first think about our boundaries. We can analyze games where spares occur, since that's the main behavior we're interested in at this point. What if we limit the game to 2 frames (or a maximum of 4 rolls), and only allow roll values of 1, 4, and 6. This will allow games such as: [1, 1, 1, 4] and [6, 4, 1, 1]. A spare occurs in the second game, but not the first. We're just looking to get a sense of how the program behaves, so this should do the trick.

Using TLC, the TLA+ model checker, we can produce a state space graph for an algorithm that we specify. The only thing we need to know right now is that a purple rectangle represents an individual state of the program, e.g. one where `totalScore = 2`, `previousRoll = 1` and `spareOccurred = false`. The directed edges represent a transition between states, so a path through the graph represents a single run of the program with a single set of inputs - in our case, a single game of bowling. In its entirety, the graph represents all possible executions of the program, or all possible games of bowling. In our case, we've bounded the number and value of rolls, so we're only considering all possible games of bowling with rolls of only 1, 4, and 6 pins spanning 2 complete frames. This still may be enough to make a fruitful analysis, if we take stock in the [small scope hypothesis](https://en.wikipedia.org/wiki/Alloy_(specification_language)#The_Alloy_Analyzer).

First, let's zoom in and look at a portion of the state space of `TenpinStateful`:

<div style="display: flex">
  <img src="/assets/Tenpin143ZoomedIn.png" style=""/> 
</div>

The way to "read" a state graph like this is to start at the initial state (the fuschia colored one all the way to the left), and follow the arrows along a path. Each arrow represents a call to `tenpin.roll()`, the stateful method that changes the program state with each call. If we follow the straight line from the initial state to the terminal state to the right, we see the state space for the following run of the program, annotated to show the state space changes at each step (disregard the `numRolls` variable since that is just a simple way to bound our model to the desired number of rolls):

~~~
let tenpin = new TenpinArray();

    // Current state
    (previousRoll == 0, totalScore == 0, spareOccured == false)

tenpin.roll(4);

    // Current state
    (previousRoll == 4, totalScore == 4, spareOccured == false)

tenpin.roll(4);

    // Current state
    (previousRoll == 4, totalScore == 8, spareOccured == false)

tenpin.roll(4);

    // Current state
    (previousRoll == 4, totalScore == 12, spareOccured == false)

tenpin.roll(6); 

    // Current state
    (previousRoll == 4, totalScore == 18, spareOccured == true)

tenpin.score();

// 18 - just returns the current value of totalScore
~~~
{: .language-typescript}

Try and folow along through each state in the graph for this run of the program to build intuition about how program statements affect the state space. Again, the state graph is showing _all_ possible runs of our bounded model.

With that out of the way, let's look at a zoomed-out image of the entire state space:

<div style="display: flex">
  <img src="/assets/Tenpin143ZoomedOut.png" style="margin: auto; height: 800px;"/> 
</div>

(_State space graph of the `TenpinStateful` algorithm_)

It doesn't look particularly beautiful, but we don't really have a frame of reference either. So here is the generated state space for the second algorithm:

<div style="display: flex">
  <img src="/assets/TenpinArray143ZoomedOut.svg" style="margin: auto; height: 1500px;" />
</div>

(_State space graph of the `TenpinArray` algorithm_)

What we're looking at right now is the overall _structure_ of the state graphs. Sandi Metz calls this the ["squint test"](https://www.youtube.com/watch?v=8bZh5LMaSmE) when applied to code, and her point is that you can just tell when code is complex because the levels of nesting and random long lines jump out immediately when looking at its shape. 

With that in mind, the immediate word I'd use to describe the `TenpinStateful` algorithm's state space is: _tangly_. It looks like a ball of yarn. States can transition to multiple other states, certain states have multiple parents, and transition edges cross over each other like wayward spaghetti. In contrast, the `TenpinArray` state space seems more structured. First of all, it is a tree - every state has a single parent, and there is only one unique path between any two states. A portion of it also appears to be linear - once the algorithm hits a certain point, all of the remaining states progress in a straight line. When thinking about the implementation, this must be when `tenpin.roll()` is done being called, and `tenpin.score()` begins looping over the rolls and adding up the scores of each frame.

The squint test of the state space, admittedly not the most rigorous of analytical methods, goes to `TenpinArray`. the overall simpler solution based on real-world experience.

That's pretty interesting.

# Modularity, Local Reasoning, and Command Query Separation

A line is the quintessential simple concept. To be creative, you have to be "non-linear," and linear thinking is often labeled pejoratively. In the graph world, I think it's fair to say that the simplest possible directed graph is 1 -> 2 -> 3 -> ... -> n, where the graph progresses in a straight line. 


# Reading State Space Graphs

As promised, let's take a closer look at the state space graph by thinking about what exactly it is that it represents. Again, each purple rectangle is a program state, and directed edges between states mean that the program can transition between them. Here, the light purple / pink state all the way at the left of the graph is the initial state. A program can have many valid initial states, but for our purposes we're just going to use a single one. To "read" the state graph, you start at the initial state, and then traverse from state to state by following the edges between them. A single sequence of states represents a single execution of the program. 

For example, let's say we roll a game of [6, 4, 3, 2]. Here is a single execution of the program that would run for these rolls, along with the underlying program states, which in this case are just the current values of the instance variables of the class:

~~~
let tenpin = new TenpinStateful();

// Current state: totalScore = 0, previousRoll = 0, spareOcurred = false

tenpin.roll(6);

// Current state: totalScore = 6, previousRoll = 6, spareOcurred = false

tenpin.roll(4);

// Current state: totalScore = 10, previousRoll = 4, spareOcurred = true

tenpin.roll(3);

// Current state: totalScore = 16, previousRoll = 3, spareOcurred = false

tenpin.roll(2);

// Current state: totalScore = 18, previousRoll = 2, spareOcurred = false
~~~
{: .language-typescript}

Try and picture walking through the state space graph for games of the following rolls:

[1, 1, 1, 1]
[1, 4, 4, 4]
[6, 4, 6, 4]
[6, 6, 6, 6]

Now, you see why the entire state space graph is large - it represents all possible sequences of states that the program can be in. Even very simple source code, such as the small classes presented here, can produce astronomically large state spaces. It's no wonder that subtle bugs occur when a very specific sequence of states wasn't considered.

Thinking of programs in this way even gives us a very precise definition of what a bug is: a sequence of actions that results in an improper data state.

A path through the state graph corresponds  The entire state graph then shows _all_ possible executions of the program, i.e. in our case, all possible combinations of sequences of calls to `tenpin.roll()`.   

# 

This all just makes me think, there are clearly some state space structures that are simpler than others. For example, consider the navigation of a UI. The state space is actually huge - all of the state variables that control 

For example, here is an example of a common UI navigation:

(sidebar with pages, table rows open flyouts, modals, etc.)

Here is what the state space looks like:

Now, it is large, because the it represents all possible paths throughout the UI. But, I can't think of a time where i messed up 

This might be beecause the state changes are *disjoint* only one part of the state is changing at any one time, so it really can be reasoned about in isolation. In this case, are tests even really necessary? You know the navigation is going to work, so why bother?

This of course makes me think, what other structures ? Could / should we develop a library of state space patterns and study them so that we know 

# The Importance of Data Structure

The other reason why the array-based solution is simpler is that, it's simply a better data structure for the job. The first version has no data structure. It's simply a bunch of state booleans with and a `totalScore` accumulator. The second solution uses a data structure, the array, to more accurately model the domain. If you read the rules of bowling, the concept of looking ahead to score should jump out - they use the word "next." You can either influence the "next" rolls via state, or by capturing the data in a data structure that supports looking ahead.

# Command query separation

The second version has two distinct phases: build up the rolls array, then compute the score of that array of rolls. The handoff is data - the array of rolls. Because of that, we can safely reason about them separately. Which makes the query state space linear - it just loops over any given array. Pure function?

It always struck me as odd that [on Wikipedia, the entry for command query separation](https://en.wikipedia.org/wiki/Command%E2%80%93query_separation#Broader_impact_on_software_engineering) makes this claim with absolutely no attempt at a citation:

> CQS is considered by its adherents to have a simplifying effect on a program, making its states (via queries) and state changes (via commands) more comprehensible.

Sometimes intuition can be totally inaccurate, but sometimes it can also be spot on. I think this is the case where it's spot on, but maybe this is attributable to 

# Trees vs. graphs

Another interesting property of the second approach is that, even with the state-manipulating part of the algorithm, the state space is a tree. In the first, it is a directed acyclic graph. This is based pure intuition, but I would assume in general, from most to least complicated, we would have:

* Linear
* Tree
* DAG
* Directed cyclic graph

# Statecharts!

It also turns out that there is a way to compose state machines, and that is via statecharts. the main thing it provides is the notion of a tree of state machines, such that when one state machine is progressing, any outer ones are not. The main benefit here is **local reasoning**. 

# Will Functional Programming Save Us?

While this may seem like a non-sequitir, it's very interesting to think about state spaces in relation to functional programming. It's often touted that functional programming reduces bugs by its very nature. But again, have we ever truly empirically observed that?

When thinking about state spaces vs. source code, something really counterintuitive happens as well: many times, for the same algorithm, there's no difference in state space between a functional or imperative implementation. For example, here is the same algorithm in a purely functional implementation (ocaml):

let roll rolls pins = pins :: rolls
let score  = (rolls) = ;; impl

roll(6) |> roll(4) |> roll(3) |> roll(2) |> score

(remember, the |> operator is just syntactic sugar, and the expanded program would be:


score(roll(roll(roll(roll([], 6), 4), 3), 2 ))

This produces the exact same state space as the imperative typescript version. However, it's 
extremely unnatural to write a functional program of the first algorithm. Now, I'm not claiming that FP is our savior because of this one example, but, it is certainly interesting. I think the functional style also pushes you towards comman-query separation, separating the stateful and pure parts of an algorithm.

# In Summary

First of all, I would still use this exercise when interviewing. There is plenty written about it on the internet, but I think I only ever ran into 1 candidate who knew about it. If it's clear that they've already done the problem, I would just switch to a different one on the fly. Even if they've done it, I highly doubt they've memorized the edge cases to the point where it wouldn't still be interesting, especially as we make the solution even more robust.

I think there are some clear takeaways about the structure of programs though, just from this one exercise.

First is that, the structure of both the source code and the state space of a program contribute to its complexity, and just because one is simple does not mean the other is.

- Both the structure of the code and the structure of the state space contribute to program complexity
- Command query separation separates pure functions from state machines. State machines are inherently more complicated
- The choice of data structure is absolutely crucial, and can remove complexity. There is effectively no data structure in the first approach, just a bucket for the previous roll and a boolean flag to introduce more states to the state machine. The second approach uses an Array since looking ahead is pretty much implied by the domain rules - the score is phrased in terms of "next." You can either prepare for the future with complex state machinery, or - just have the future at your disposal!

I also may have raised more questions than I answered, and as usual I just wish there were more valuable emprical studies of software development out there.

# Leftover

The only real constraint of the exercise is that we stick to two APIs: a `roll(pins)` method which specifies how many pins were knocked down for a single roll, and a `score()` method which returns the total score of the game based on the calls to `roll` so far.


For example, the given Tenpin class here isn't _that_ complex from a CFG perspective. There's only two branches in the code, created by the single `if` statement.

In the first version, there is no separation between the state transitions and the scoring logic. In the second, command-query separation is present, and both the commmand and query part are simpler.

Also, in the second, 

After all, this is pretty much the definition of a bug: an unintended data state.

Remove: Hoare logic - yields takeaways?
