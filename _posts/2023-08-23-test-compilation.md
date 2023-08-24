---
layout: post
title: 'Compiling a Test Suite'
tags: testing formal_methods plt
author: Alex Weisberger
---

When I first stumbled upon certifying compilation[^fn1], I was absolutely awestruck. I thought a compiler was a very specific thing, a translator from source to target language. But a certifying compiler goes further: it also proves its own correctness. My motto has become ["most tests should be generated"]({% post_url 2023-07-02-generated-tests %}), so this immediately seemed like a promising approach to my goal of improving the generative testing of interactive applications. It wasn't immediately clear how exactly to incorporate this into that context, but after a little experimentation I now have a prototype of what it might look like.


First, rather than describe the theory, let me show you what the workflow of certifying compilation looks like. Imagine invoking a command like this:

```plaintext
certc source.cc -o myprogram -p proof
```

`certc` compiles the source file into an executable, like every other compiler, but in addition it outputs this `proof` file. Imagine that you can open up this file, and from its contents be convinced that the compilation run contained zero bugs, and the output `myprogram` is a perfect translation of `source.cc`[^fn2]. The compilation run is _certified_ by this proof. Such compilers are sometimes referred to as _self-certifying_ for this reason - they produce their own proof of correctness.

We know that proofs are hard though, and for most of us tests are sufficient. So what if instead, we had this workflow:

```plaintext
certc source.cc -o myprogram -t test
./test
```

Instead of generating a proof, we now generate a test suite, and instead of opening it up to inspect it, we run it. If it passes, we're still convinced that the compilation run was correct. Visually, certifying compilation just adds one more output artifact to a compilation run, which we can call a "checker," and looks something like this:

<div style="display:flex;justify-content:center">
<script type="text/typogram">
                       .--------------.
     .---------------->|    Checker   |
     |                 .--------------.
     |
     |
.----------.             .-----------.
|  Source  |------------>|   Target  |
.----------.             .-----------.

</script> 
</div>

# From Programs to Applications

At this point, this doesn't look very applicable to something like a web application, and I'm mostly interested in testing interactive distributed applications. The idea of compiling a source model into a full-fledged web app is farfetched to say the least. I actually tried going down that path for a bit, and I can confirm: it is hard. It's definitely an interesting research area, but for now let me pitch an alternative workflow that's still based on the mental model of certifying compilation.

What if we assume that our target application is something that we hand-modify out of band, and we just generate the checker for it, i.e.:

```plaintext
certc model -c test
./test
```

And visually:

<div style="display:flex;justify-content:center">
<script type="text/typogram">
                       .--------------.
     .---------------->|    Checker   |
     |                 .--------------.
     |
     |
.----------.             .-----------.
|  Model   | - - - - - ->|    App    |
.----------.             .-----------.

</script> 
</div>

In this workflow, we hand-develop the implementation application as we do normally, but we still generate the checker from a model. This puts us under the umbrella of model-based testing, but we're going to look at the proof techniques that a certifying compiler uses as inspiration for how we should generate the correctness tests. Because of this difference, I'd call this paradigm "certifying specification."

What's nice about this is that it slots right in to existing workflows. We can even TDD with this if we're so inclined, by first changing logic in the model and then generating the failing tests before implementing them. Workflow-wise, it's simple enough to work.

# Writing a Model

Since the checker generation depends on the existence of a model, we should first talk about how to write one. The first question to ask is: should we use an existing language or a new language to write models in? I really try to avoid thinking about or suggesting the introduction of new languages into the ecosystem. But, the question has to be asked, because using an existing language has a lot of tradeoffs with respect to specification:

* Existing languages have no notion of system structure, i.e. how do we distinguish system state vs. local variables? How do we distinguish system actions vs. local mutation? How do we parse an arbitrary program and get relevant information out of it to help with test generation?
* Programming languages are meant for programming. There are aspects of specification that require other language features, such as the ability to express logical properties and the ability to control aspects of test generation.
* Programming languages have additional features that aren't necessary in a modeling context. For example, a model has no need for filesystem operations or networking. 

These can be overcome by creating an embedded DSL within an existing language to restrict the structure of models, but embedded DSLs have their own set of tradeoffs[^fn3].

One other option is to use an existing specification language, like TLA+. TLA+ in particular is too powerful for us here - we really want to limit models to be _executable_ so that we can use their logic in the checker.

I think these are all viable approaches, but I also think that there are enough reasons to create a language that's purpose-built for this use case. I've been experimenting with one that I call [Sligh](https://github.com/amw-zero/sligh). Here's a model of a counter application in Sligh:

{% highlight sligh %}
record Counter:
  name: Id(String)
  value: Int
end

process CounterApp:
  counters: Set(Counter)
  favorites: Set(String)

  def GetCounters():
    counters
  end

  def CreateCounter(name: String):
    counters := counters.append(Counter.new(name, 0))
  end

  def Increment(name: String):
    def findCounter(counter: Counter):
      counter.name.equals(name)
    end

    def updateCounter(counter: Counter):
      Counter.new(counter.name, counter.value + 1)
    end

    counters := counters.update(findCounter, updateCounter)
  end

  def AddFavorite(name: String):
    favorites := favorites.append(name)
  end

  def DeleteFavorite(name: String):
    def findFavorite(favName: String):
      name.equals(favName)
    end

    favorites := favorites.delete(findFavorite)
  end
end
 
{% endhighlight %}

Sligh is not meant to be revolutionary in any way at the language level (in fact it aims to be much simpler than the average general purpose language), and hopefully the functionality is clear here. The main goal is that it supports enough analysis so that we can generate our model-based tests. The main notable syntactic features are the `:=` operator and the structure of the `process` definition. The `:=` operator denotes updates of the _system_ state, distinguished from any modification of local variables. The `CounterApp` app has a set of counters and a set of favorites as system state. Local variables exist, but mutations to those are implementation details and don't matter from the perspective of testing. Having a specific operator for the system state allows simple syntactic analysis to find state changes, which is essential for generating the certification test.

For example, in the `Increment` action, we know that the `counters` state variable is modified, and in the `AddFavorite` action the `favorites` state variable is modified. If no assignments occur on a state variable in the span of an action, then we know for sure that it's not modified in that action. This becomes very important later when we can exploit this to generate the minimum amount of test data necessary for a given test iteration.

Sligh processes also support nested `def`s which define system _actions_. System actions are the atomic ways that the system state can change, like adding or incrementing counters. For those conceptual user operations, we have corresponding `CreateCounter`, and `Increment` actions. This is what Sligh uses to determine which operations to generate tests for.

These syntactic restrictions lead to a very powerful semantic model of a system that's also statically analyzable - they effectively form a DSL for describing state machines.

# Compiling the Test Suite

A Sligh model doesn't get compiled into a test suite directly. To compile the above counter model, we'd run:

```plaintext
sligh counter.sl -w witness
```

which generates a "witness" file. This is a good time to talk a bit about the compiler internals and why that is.

It's common for certifying compilers to decouple per-program generated output from a separate checker that's written once. This makes the code generation phase of the compiler simpler, but also allows the checker to be written and audited independently. This is extra important since the checker is our definition of correctness for the whole application, and a misstatement there affects the guarantees our certification test gives us.

Here's the current checker that's in use:

{% highlight typescript %}
export function makeTest(
    actionName: string,
    stateType: "read" | "write",
    stateGen: any,
    implSetup: any,
    dbSetup: any,
    model: any,
    modelArg: any,
    clientModelArg: any,
    runImpl: any,
    expectations: any,
  ) {
    test(`Test local action simulation: ${actionName}`, async () => {
      let impl: StoreApi<ClientState>;
  
      await fc.assert(fc.asyncProperty(stateGen, async (state) => {
        impl = makeStore();        
  
        const clientState = implSetup(state);

        // Initialize client state
        impl.setState(clientState);

        // Initialize DB state
        await impl.getState().setDBState(dbSetup(state));

        // Run implementation action
        await runImpl(impl.getState(), state);

        // Run model action and assert
        switch (stateType) {
          case "write": {
            const clientModelResult = model(clientModelArg(state));
            for (const expectation of expectations) {
              const { modelExpectation, implExpectation } = expectation(clientModelResult, impl.getState());
    
              expect(implExpectation).toEqual(modelExpectation);
            }
            break;
          }
          case "read": {
            let modelResult = model(modelArg(state));
            for (const expectation of expectations) {
              const { modelExpectation, implExpectation } = expectation(modelResult, impl.getState());
    
              expect(implExpectation).toEqual(modelExpectation);
            }
            break;
          }
        }
      }).afterEach(async () => {
        // Cleanup DB state
        await impl.getState().teardownDBState();
      }), { endOnFailure: true, numRuns: 25 });
    });
  }
{% endhighlight %}

This looks similar to other [model-based tests]({% post_url 2023-01-31-model-based-testing-theory %}) we've built before in that it compares the output of the model and implementation for a given action at a given initial state. This test is parameterized though, and all of the input parameters for a given test come from the witness.

A "witness" in the certifying compilation world refers to data that's extracted from the source program during compilation. Here's the witness output for the `CreateCounter` action:

{% highlight typescript %}
interface Counter {
  name: string;
  value: number;
}

interface CreateCounterDBState {
  counters: Array<Counter>;
}

interface CreateCounterType {
  counters: Array<Counter>;
  name: string;
  db: CreateCounterDBState;
}

interface CreateCounterModelIn {
  name: string;
  counters: Array<Counter>;
}

let CreateCounterModel = (params: CreateCounterModelIn) => {
  let name = params.name;
  let counters = params.counters;
  counters = (() => {
    let a = [...counters];
    a.push({ name: name, value: 0 });
    return a;
  })();
  return { counters: counters };
};

// ...

{
  name: "CreateCounter",
  type: "write",
  stateGen: fc.record({
    counters: fc.uniqueArray(
      fc.record({ name: fc.string(), value: fc.integer() }),
      {
        selector: (e: any) => {
          return e.name;
        },
      }
    ),
    name: fc.string(),
    db: fc.record({
      counters: fc.uniqueArray(
        fc.record({ name: fc.string(), value: fc.integer() }),
        {
          selector: (e: any) => {
            return e.name;
          },
        }
      ),
    }),
  }),
  implSetup: (state: CreateCounterType) => {
    return { counters: state.counters };
  },
  dbSetup: (state: CreateCounterType) => {
    return { counters: state.db.counters, name: state.name };
  },
  model: CreateCounterModel,
  modelArg: (state: CreateCounterType) => {
    return { counters: state.db.counters, name: state.name };
  },
  clientModelArg: (state: CreateCounterType) => {
    return { counters: state.counters, name: state.name };
  },
  runImpl: (impl: ClientState, state: CreateCounterType) => {
    return impl.CreateCounter(state.name);
  },
  expectations: [
    (modelResult: CreateCounterModelOut, implState: ClientState) => {
      return {
        modelExpectation: { counters: modelResult.counters },
        implExpectation: { counters: implState.counters },
      };
    },
  ],
},

// ...

{% endhighlight %}

The details here are likely to change over time, but the key thing to notice is that all of this information is generated from the definition of `CreateCounter` in the model. Here's the `CreateCounter` definition again for reference:

{% highlight sligh %}
def CreateCounter(name: String):
  counters := counters.append(Counter.new(name, 0))
end
{% endhighlight %}

This action takes a `name` string as input, but it also modifies the `counters` state variable (which Sligh is able to detect because of the presence of the `:=` operator). From this, one of the things we generate is a type for all of the test's input data, `CreateCounterType`:

{% highlight typescript %}
interface CreateCounterType {
  counters: Array<Counter>;
  name: string;
  db: CreateCounterDBState;
}

{% endhighlight %}

And the `stateGen` property of the `witness` object gets a corresponding data generator for this type:

{% highlight typescript %}
fc.record({
  counters: fc.uniqueArray(
    fc.record({ name: fc.string(), value: fc.integer() }),
    {
      selector: (e: any) => {
        return e.name;
      },
    }
  ),
  name: fc.string(),
  db: fc.record({
    counters: fc.uniqueArray(
      fc.record({ name: fc.string(), value: fc.integer() }),
      {
        selector: (e: any) => {
          return e.name;
        },
      }
    ),
  }),
})
{% endhighlight %}

Also, note what this excludes. The test doesn't have to generate the `favorites` variable since it's not referenced or modified in the span of this particular action. The test for each action only has to generate the bare minimum amount of data it needs to function. And most importantly, this means we totally avoid creating any global system states. I think this will be the key to testing a larger application in this way.

Other than that, the other params are similarly extracted from the `CreateCounter` signature and code, providing overall assistance to the checker. I expect to be able to hone these witness definitions over time, but this works for now.

At this point it should be apparent that the compiler and checker both have to know about some very important system details. They need to know what language the test is written in. They need to know the pattern for executing actions on both the implementation and the model (here the implementation interface is a [Zustand](https://github.com/pmndrs/zustand) store meant to be embedded in a React app). They need to know what testing libraries are being used - here we're using [vitest](https://github.com/vitest-dev/vitest) and [fast-check](https://github.com/dubzzz/fast-check). And they need to be able to set up the state of external dependencies like the database, done here with calls to `impl.getState().setDBState` and `impl.getState().teardownDBState()`, which means that the server has to be able to help out with initializing data states.

Still, lots of the functionality is independent of these concerns, and my hope is to make the compiler extensible to different infrastructure and architectures via compiler backends. For now, sticking with this single architecture has supported the development of the prototype of this workflow.

Finally, the test gets wired up together in a single file runnable by the test runner:

{% highlight typescript %}
import { makeTest } from './maketest';
import { witness } from './witness';

for (const testCase of witness) {
    makeTest(
      testCase.name, 
      testCase.type as "read" | "write",
      testCase.stateGen, 
      testCase.implSetup, 
      testCase.dbSetup, 
      testCase.model, 
      testCase.modelArg, 
      testCase.clientModelArg,
      testCase.runImpl, 
      testCase.expectations
    );
  }
{% endhighlight %}

# Outro

Ok, I went into a lot of details about the internals of the Sligh compiler. But to reiterate, the developer workflow is just:

```plaintext
sligh counter.sl -w witness
./test
```

I'm using this on a working Next.js application, and workflow-wise it feels great. I'm excited to see what other challenges come up as the application grows.

I can't rightfully end the post without talking about a few tradeoffs. I can probably write a whole separate post about that, since this one is already quite long, but two big ones are worth mentioning now. First, because we're testing single state transitions, a test failure won't tell you how to actually reproduce the failure. It might take a series of very particular action invocations to arrive at the starting state of the simulation test, and it's not always clear if the specific state is likely or even legitimately possible in regular application usage. I have ideas there - similar to property-based testing failure minimization, it should be possible to search for action sequences that result in the failing initial state.

The second tradeoff is that data generation for property tests of a full application is non-trivial. Sligh is currently doing the bare minimum here, which is use type definitions to create data generators. I'm hoping the language can help out here though, and more intelligent generators might be able to be extracted from the model logic.

And lastly, I have to call out the awesome [Cogent](https://cogent.readthedocs.io/en/latest/) project one last time. So many of these ideas were inspired by the many publications from that project. Specifically, check out this paper: [The Cogent Case for Property-Based Testing](https://trustworthy.systems/publications/full_text/Chen_OKKH_17.pdf).

----

[^fn1]: I first heard about certifying compilation through a [talk on YouTube](https://www.youtube.com/watch?v=sJwcm_worfM) and [a corresponding paper](https://trustworthy.systems/publications/nicta_full_text/9425.pdf) (by Liam O’Connor, Zilin Chen, Christine Rizkallah, Sidney Amani, Japheth Lim, Toby Murray, Yutaka Nagashima, Thomas Sewell, and Gerwin Klein). These are about the [Cogent](https://cogent.readthedocs.io/en/latest/) language, which compiles from itself to C, but also generates a proof of its correctness in Isabelle.

[^fn2]: Any compiler-writer will tell you, compilers are [just as buggy](https://softwareengineering.stackexchange.com/a/53069) as other programs. This is why certifying compilation exists in the first place - to provide higher assurance about the correctness of a compiler.

[^fn3]: I once read [an interesting take about building embedded DSLs inside of an existing language](https://matklad.github.io/2021/02/14/for-the-love-of-macros.html#Domain-Specific-Languages) that influenced my thinking here. The takeaway: eDSLs are often not worth it.

