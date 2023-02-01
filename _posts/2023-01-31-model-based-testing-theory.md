---
layout: post
title: 'Efficient and Flexible Model-Based Testing'
tags: testing formal_methods
author: Alex Weisberger
---

In [Property-Based Testing Against a Model of a Web Application]({% post_url 2022-08-11-model-based-testing %}), we built a web application and tested it against an executable reference model. The model-based test in that post checks sequences of actions against a global system state, which is simple to explain and implement, but is unsuitable for testing practical applications in their entirety. To test the diverse applications that arise in practice, as well as test more surface area of a single application, we'll need a more efficient and flexible approach.

In that post, I promised that we'd dive deeper into the theory of model-based testing. To upgrade our testing strategy, we'll look at the theoretical concepts of _refinement mappings_[^fn1] and _auxiliary variables_[^fn2], and add in a couple of tweaks based on the specific context of testing. All of this will get applied to a real test of a full-stack application.



# A Quick Recap of Actions

Understanding the notion of "action" is essential for building our upgraded model-based testing strategy. When we say "action," we mean something very specific: a transition in a state machine / state transition system, whichever name you prefer. It might be helpful to think of it from a code perspective:

~~~
class Counter {
  count: number = 0;

  constructor(count: number) {
    this.count = count;
  }

  increment() {
    this.count += 1;
  }

  decrement() {
    this.count -= 1;
  }
}

let counter = new Counter();
counter.increment();
counter.decrement();
~~~
{: .language-typescript}

`count` is the state variable, and `increment` and `decrement` are _actions_ which transition the variable to a new state. Imagine the value of `count` after each of these actions.

The presence of a class has nothing to do with this being an object-oriented concept by the way, it's just that classes are a convenient wrapper around a set of stateful variables and operations on them, and thus they are a good representation of a state machine. We could just as easily write:

~~~
let count = 0;

function increment(count: number): number {
  return count + 1;
}

function decrement(count: number): number {
  return count - 1;
}

count = increment(count);
count = decrement(count);
~~~
{: .language-typescript}

These are behaviorally equivalent, which we can convince ourselves of by again imagining the value of the `count` state variable after each action. The pattern that we use to talk about state machines is superficial, and has nothing to do with how to structure programs in the large. Don't let the pattern get in the way of the underlying concepts: all we need are states and transitions between them, and we call these transitions "actions." 

In an interactive application, actions are generally initiated by the user by clicking on or tapping UI elements. The system itself can trigger actions, for example via cron jobs. Even external systems can trigger actions in the system by calling web APIs.

Actions are what allow an application to move through different states over time.

# A Preview of Our Destination

The end goal is to convert our existing [model-based test]({% post_url 2022-08-11-model-based-testing %}) into one that's more efficient and allows us to check more interesting properties. To do that, we're going to end up with something that looks like this:

~~~
type DeleteRecurringTransactionState = {
  recurringTransactions: RecurringTransaction[];
  id: number;
  db: DBState;
}

class Impl {
  db: DBState;
  client: Client;

  aux: AuxiliaryVariables;

  constructor(db: DBState, client: Client, aux: AuxiliaryVariables) {
    this.db = db;
    this.client = client;
    this.aux = aux;
  }

  async deleteRecurringTransaction(id: number) {
    await this.client.deleteRecurringTransaction(id);
    this.aux.clientModel.deleteRecurringTransaction(id);
  }

  ...
}

type AuxiliaryVariables = {
  clientModel: Budget;
}

function refinementMapping(impl: Impl): Budget {
  let budget = new Budget();
  budget.error = impl.client.error;

  budget.recurringTransactions = [...impl.db.recurring_transactions];
  budget.scheduledTransactions = [...impl.client.scheduledTransactions];

  return budget;
}

Deno.test("deleteRecurringTransaction", async (t) => {  
  let state = <generate test state>;

  await fc.assert(
    fc.asyncProperty(state, async (state: DeleteRecurringTransactionState) => {
      let client = new Client();
      client.recurringTransactions = state.recurringTransactions;

      let clientModel = new Budget();
      clientModel.recurringTransactions = state.recurringTransactions;

      let impl = new Impl(state.db, client, { clientModel });
      let model = refinementMapping(impl);

      const cresp = await client.setup(state.db);
      await cresp.arrayBuffer();

      await impl.deleteRecurringTransaction(state.id);
      model.deleteRecurringTransaction(state.id);

      impl.db.recurring_transactions = await client.dbstate();

      let mappedModel = refinementMapping(impl);

      await checkRefinementMapping(mappedModel, model, t);
      await checkImplActionProperties(impl, t);

      await client.teardown();
    }),
    { numRuns: 10, endOnFailure: true }
  );
});
~~~
{: .language-typescript}

There's no way to evaluate if this is a good test or even what exactly it's testing for without understanding some theory. But all of this theory is in service of testing a real, functional single-page web application.

# Correctness as Equivalent Behavior of Action Sequences

We have to start all the way at the beginning and define what it really means for an implementation to be correct with respect to a model. Action sequences are a good choice for this, because they're simple to understand. Using our `increment` and `decrement` functions from above, an example action sequence would be:

~~~
type Action = "increment" | "decrement";

// Combine individual actions into a single top-level action
function counterAction(counter: number, action: Action): number {
  switch (action) {
    case "increment":
      return increment(counter);
    case "decrement":
      return decrement(counter);
  }
}

type ActionFunc<S, A> = (state: S, action: A) => S;

// Generic action sequence evaluation function
function execute<S, A>(actionFunc: ActionFunc<S, A>, init: S, actions: A[]): S {
  let result = init;
  for (const action of actions) {
    result = actionFunc(result, action);
  }

  return result;
}

let counter = 0;
execute(counterAction, counter, ["increment", "increment", "decrement", "increment"]);
~~~
{: .language-typescript}


An action sequence is one particular path through a system. Here, we incremented the counter twice, decremented once, and ended with another increment. These are some more valid action sequences:

* ["increment"]
* []
* ["increment", "decrement", "decrement", "decrement"]
* ["decrement"]
* ["decrement", "increment", "increment", "decrement" "decrement", "increment", "increment"]

How many possible sequences of actions are there for our simple counter system? 1,000? 500,000,000? Unfortunately, the answer is infinity, and that's true of all interactive systems. That's one reason why testing and verification is hard.

Even though they are infinite, it's very natural to express the correctness of a model-based system in terms of action sequences using universal quantification, aka "for all" statements:

```
** Holistic correctness statement **:

For all initial states 's',
  all sequences of actions 'acts',
  a top-level action function 'impl',
  and a top-level action function 'model':
  
  execute(impl, s, acts) = execute(model, s, acts)
```

Less formally: no matter what seqeunce of actions you take in the implementation, nor what state it starts in, it should always agree with the model. The key words being "no matter what" and "always" - this should be true of all actions, in any order, from any starting state, ever. In other words, this statement is _complete_, and we'll refer to it as "the holistic correctness statement." It's important to keep this statement in mind, since **this is our definition of correctness and our end goal**, and any optimization that we do always has to tie back to it. (Note: this is also a classic way of expressing [refinement]({% post_url 2021-11-26-refinement %})).

As we hinted at in the introduction, there are some very unfortunate things about this holistic correctness statement in a practical testing context. First is the `actions` variable. A real application accepts an infinite stream of actions. Even though we limit our test to finite sequences, combinatorics is just not on our side, with the number of k-length sequences of n actions equaling n^k - a dreadful exponential growth curve. That means that as the number of actions in the systems grows, and as we test longer sequences, the number of possible interleavings of actions grows exponentially. Whatever subset of sequences our test generates is an infinitesimal portion of them all.

Next is the `s` variable. This is the _entire_ state of the system, and unless we're building a counter application with a single integer variable it's way too much data to generate in a test.

A third problem is that `s` is used in both of the model and implementation, which means that they both have to have the same state type. This very rarely works, because the whole point of separating the model and implementation is that the implementation is complex and will have additional state to deal with that. States are often compatible in practice.

The last straw is that sometimes, you don't even have the state variables that you need to check for correctness. This sounds weird, but it's well known that specifications often have to be augmented with "invisible" variables so that certain properties can be shown to hold.

Each of these problems eventually arises when you try to use model-based testing, and we need some extra machinery to solve them.

# Single Transitions and Compatible States with Refinement Mappings

Refinement mappings solve problems 1 and 3, and somewhat magically still also imply the truth of the holistic correctness statement. Meaning that, if we test for a proper refinement mapping, then it's also true that the implementation correctly implements the model in all possible usage scenarios.

A refinement mapping is just a function with a couple of special rules, some of which are out of scope for this post. The first rule is that the function is from the implementation state to the model state, e.g. in our preview of the budget app test we can see that the refinement mapping maps the `Impl` implementation state type to the `Budget` model type:

~~~
function refinementMapping(impl: Impl): Budget {
  ...
}
~~~
{: .language-typescript}

The goal here is to be able to compare the implementation to the model, and if they have different state types we need to translate states in the implementation's state space to ones in the model's. On top of this, the most relevant other rule for a valid refinement mapping is that, for all implementation states and actions, the action is equivalent to the model action with the refinement mapping applied in the appropriate places. In logic pseudocode; 

```
** Correctness via Refinement Mapping ** 
For all initial states 's',
  all implementation states 's',
  all implementation action functions 'impl',
  all model actions 'model'
  and a refinement mapping 'rm':

  rm(impl(s)) = model(rm(s))
```

The intuition for why it works is that, if every single-step action in the implementation agrees with the same action taken in the model, then chaining multiple actions into sequences should preserve that equivalence. This is an example of an inductive argument. The refinement mapping function can be defined in many different ways depending on how we want to relate the two state types, which gives our new correctness statement an important caveat: we consider the system correct _under the provided refinement mapping_. This is the price we pay for dealing with state incompatibilities.

In our budget app test, the refinement mapping is defined as follows:

~~~
function refinementMapping(impl: Impl): Budget {
  let budget = new Budget();
  budget.error = impl.client.error;

  budget.recurringTransactions = [...impl.db.recurring_transactions];
  budget.scheduledTransactions = [...impl.client.scheduledTransactions];

  return budget;
}
~~~
{: .language-typescript}

The `Impl` implementation type has both database (`impl.db`) and client states (`impl.client`), reflecting the independent states in a client-server application. In this system, only recurring transactions are persisted, and scheduled transactions are derived data. Because of this, the implementation's recurring transactions in the database map to the model's recurring transactions, whereas the implementation's scheduled transactions in the client map to the model's scheduled transactions. Any error in the client maps to an error in the model. Notably, this is talking about _system_ errors, i.e. errors / results in the domain logic. The model has no notion of networking, so networking errors can be stored separately, but they don't map to any model state[^fn3].

The meat of the test is where we compare single actions, and in order to do this we make the states compatible by applying the refinement mapping:
~~~
...

let impl = new Impl(state.db, client, { clientModel });
let model = refinementMapping(impl);

...

// Run the action in the implementation and the model
await impl.deleteRecurringTransaction(state.id);
model.deleteRecurringTransaction(state.id);

...

let mappedModel = refinementMapping(impl);

await checkRefinementMapping(mappedModel, model, t);
~~~
{: .language-typescript}

The combination of comparing single transitions and converting between implementation and model state types is an efficiency and flexibility win. We've gone from potentially long sequences of actions to comparing simple function calls, we only need to generate a single state value per test iteration, _and_ we can compare the states of the implementation and model even if they aren't the same type.

It's great progress, but we can do even better.

# From Global to Local State

The `s` variable in our new iteration of the correctness statement is still the global state, but an observation comes to mind: how much of the global state is necessary for each action? There's no equation which answers this question directly, but intuitively, an action will only ever operate on a small subset of the global state, leaving the rest unchanged. We can then just ignore that superfluous state and think of the action as operating on its own, local state. This is not related to refinement mapping, or any other theory that I know of (thought it might relate to one that I don't know of), but ends up being a very useful optimization in practice.

For example, consider an oddly-specific system for point translation:

~~~
type Point = {
  x: number;
  y: number;
}

function translateX(point: Point, delta: number): Point {
  const result = { ...point };
  result.x += delta;

  return result;
}

function translateY(point: Point, delta: number): Point {
  const result = { ...point };
  result.y += delta;

  return result;
}
~~~
{: .language-typescript}

`translateX` and `translateY` are actions which operate on a `Point` type, but each only modifies a single part of the state - only `x` or `y` of the `Point`, but never both. Why, then, do we need to generate a full `Point` type in our test for comparing them? We can instead construct a new action function, say `translateOnlyX`, which only operates on the data that it actually modifies:

~~~
function translateOnlyX(x: number, delta: number): number {
  return x + delta;
}
~~~
{: .language-typescript}

In the model-based testing context, instead of comparing the functions at the global state level (`Point` in this case), we can compare the actions at the local level:

```
** Local Refinement Mapping Correctness Statement **

For all action functions 'impl',
  all action functions 'model',
  and all local states 'ls':
  
  rm(impl(ls)) = model(rm(ls))
```

Breaking out the action implementation in this way has no behavioral effect on the global-level `translateX` function, since `translateX` can easily be implemented in terms of `translateOnlyX`:

~~~
function translateX(point: Point, delta: number): Point {
  const result = { ...point };
  result.x = translateOnlyX(result.x, delta);

  return result;
}
~~~
{: .language-typescript}

And this is exactly what's going on in our upgraded budget test. In our excerpt, we're only focusing on the `deleteRecurringTransaction` action, and we generate a test state specific to this action:

~~~
type DeleteRecurringTransactionState = {
  recurringTransactions: RecurringTransaction[];
  id: number;
  db: DBState;
}
~~~
{: .language-typescript}

Deleting a recurring transaction doesn't interact in any way with the `scheduledTransactions` state variable in that application, so we can leave that out of the test state for this particular action.

The end result of this is that we can get global guarantees for the cost of local checking, i.e. we can use local states to still show the holistic correctness statement.

# One More Wrinkle

One last wrinkle presents itself for now - the notorious problem number 4. It may sound counterintuitive, but there are both refinement mappings and properties of our systems that are not expressible with the state variables of the system itself. Even if they are, they may be more naturally expressed by adding _auxiliary variables_. Auxiliary variables are additional variables that are added to a program (usually the implementation) that don't affect the behavior of the program, but can be used to state properties or aid in a refinement mapping to a model.

Auxiliary variables provide one solution to a problem in the budget app test, and for tests for client-server applications in general. Our implementation is the state component of a single-page application, and one implication of that is that the client and database state can become out of sync. Consider the following action sequence:

* The database starts with these recurring transactions: [rt1, rt2, and rt3].
* User 1 loads the home page - its client holds [rt1, rt2, rt3]
* User 2 deletes rt2 - its client now holds [rt1, rt3], and the database holds [rt1, rt3]
* User 1 adds a new recurring transaction, rt4 - its client holds [rt1, rt2, rt3, rt4] and the database holds [rt1, rt3, rt4].

At the end of these actions, the system has the following state:

User 1's client: [rt1, rt2, rt3, rt4]
User 2's client: [rt1, rt3]
The database: [rt1, rt3, rt4]

Again, there are a few different ways to go about either allowing or disallowing this behavior. One option is to just forbid differences in client values, but this would require a web socket to update all clients on each data write. While some applications actually do this (like chat applications), I would say that most don't. Instead, we have to allow diverging client states, but we still want to do that in a controlled manner.

Well, one solution to that is to add a separate model instance as an auxiliary variable to the implementation which tracks the source of truth of the state of the client alone. Then, whenever a write occurs, we double-write to the implementation and this client model. Again, there are many patterns for doing this, but I like wrapping the implementation (`Client` here) in a new class with the same interface that forwards actions to the relevant members, this way the structure of the test doesn't have to change:

~~~
class Impl {
  db: DBState;
  client: Client;

  aux: AuxiliaryVariables;

  constructor(db: DBState, client: Client, aux: AuxiliaryVariables) {
    this.db = db;
    this.client = client;
    this.aux = aux;
  }

  async deleteRecurringTransaction(id: number) {
    await this.client.deleteRecurringTransaction(id);
    this.aux.clientModel.deleteRecurringTransaction(id);
  }

  ...
}
~~~
{: .language-typescript}

In the test excerpt, we see another assertion named `checkImplActionProperties`, and its defintion will now make sense:

~~~
async function checkImplActionProperties(impl: Impl, t: Deno.TestContext) {
  await t.step("loading is complete", () => assertEquals(impl.client.loading, false));

  await t.step("write-through cache: client state reflects client model", () => assertEquals(impl.client.recurringTransactions, impl.aux.clientModel.recurringTransactions));
}
~~~
{: .language-typescript}

After each action has been invoked, we check that the actual state of the client matches the state of the _client_ model, not the system model which is only aware of the database state. We also check that the loading variable in the client is false for good measure, ensuring that any spinners or other loading UI are hidden at the end of every action.

The key here is that, as long as they don't affect the behavior of the implementation, we can add any auxiliary variables we want for tracking _additional_ information. Once we have them, we can use them for test assertions, totally independent of the implementation that runs in production. They're test-only code.

I'm going to be honest - I can have too much fun with auxiliary variables, and that means that we should be careful with them. They are basically a cheat code, and can be used as an escape hatch to get out of all kinds of situations. That being said, they're sometimes the most elegant solution to a problem, and they're a key piece in making our test flexible towards many scenarios that arise in the future. If anything becomes difficult to assert on or express as a property, we can try and make them easier by adding new auxiliary variables.

# Recap

Alrighty. We went over four main problems and solutions to them:

1. Action sequences
2. Global state
3. State incompatibility
4. Expression inability

We introduced refinement mappings, which are functions from the implementation state to the model state, and which overcome both state incompatibility and avoid action sequences. We showed that by using action-local state we can avoid ever constructing global system state in the test. And we showed that if we ever have the inability to express a property about our system, we can always add auxiliary variables which don't affect the system behavior but track additional information that we can use in test assertions.

What we ended up with is a framework for writing model-based tests that is both efficient and flexible.

The linked papers have plenty of more theoretical background and examples for deeper dives on these topics.

# Thanks

Big thanks to [Hillel Wayne](https://www.hillelwayne.com) for having an in depth conversation about refinement with me, which influenced my thinking about how to best define the system state for a client-server application.

<hr>

[^fn1]: I recommend reading [this paper to get a handle on refinement mappings](https://www.microsoft.com/en-us/research/publication/the-existence-of-refinement-mappings/). Another name for this technique is _simulation_, which you can see an example of in [how seL4 proves that the implementation implements its functional specification](https://doclsf.de/papers/klein_sw_10.pdf). Both are the same ultimate idea - prove that one program implements another by showing that all single transitions in each implement each other.

[^fn2]: We'll expand on what auxiliary variables are throughout the post, but you can read more about them [here](https://lamport.azurewebsites.net/tla/hiding-and-refinement.pdf) and [here](https://lamport.azurewebsites.net/pubs/auxiliary.pdf).

[^fn3]: Errors that can be present in the implementation but not the model are an interesting topic. For example, if a network error in a request during the course of an action in the implementation, then it certainly won't complete the action in a way that implements the model. One option is to be liberal, and simply avoid comparing the model and implementation in this case. We didn't cover stuttering here, but models are allowed to stutter (transition to the current state) during implemenation steps, so an implementation error could be interpreted as a model stutter. The issue is, if the network error happens on every single action invocation, the implementation will never match the non-stuttering step of the model. The other option is to be harsh, and require that there are no network errors in tests, but still plan for them and allow them in production. This current version of this test chooses to be harsh. I'll let you know how that goes.
