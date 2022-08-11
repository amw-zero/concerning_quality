---
layout: post
title: 'Property-Based Testing Against a Model of a Web Application'
tags: testing, formal_verification, lightweight_formal_verification
author: Alex Weisberger
---

The term "lightweight formal methods" is a bit of a contradiction, but the idea is that like everything else, formal methods exists on a spectrum. We don't have to prove each line of our entire application to use mathematical thinking to reason about our software. A great example of this is model-based testing, where we can automatically generate test cases for an implementation by first constructing a model of the system. This is a well-studied approach, but what rekindled my curiosity in it was Amazon's recent usage of it [to test parts of S3's functionality](https://www.cs.utexas.edu/~bornholt/papers/shardstore-sosp21.pdf), as well as seeing some recent activity around the [Quickstrom web application testing tool](https://quickstrom.io/).

If it hasn't been clear, I'm mostly interested in which aspects of formal methods we can [use "at work"](https://www.hillelwayne.com/post/using-formal-methods/) and on real projects. So what interests me about lightweight formal methods is that they generally have a built-in solution to [the verification gap]({% post_url 2022-07-12-verification-gap %}), meaning we can apply them to deployable code. Does the lightweight nature of model-based testing make it a viable approach for testing web applications? Let's first go into an example, and we'll tackle the underlying theory in a separate post.



# A Model of Functional Correctness

> It is our position that a solid product consists of a triple: a program, a functional specification, and a proof that the program meets the functional specification
>
> -Edsger W. Djikstra, [EWD1060-0](https://www.cs.utexas.edu/users/EWD/ewd10xx/EWD1060.PDF)

As always, testing and verification starts out with the surprisingly difficult question of: "what is our program supposed to do"? And as we talked about in [Refinement]({% post_url 2021-11-26-refinement %}), the answer to that question also depends on who you ask. But when you start to think about it, the really crazy thing is that the only way to know the answer to this question is by looking at the code - the code _is_ the source of truth for the behavior. 

Is this a good idea? Do we need to look at JSON serialization, database queries, caching layers, or other distributed system minutiae to figure out what is supposed to happen when a user clicks "submit" on some form? 

Model-based testing instead encourages us to create a high level model of our system, and to use it to test that the implementation conforms to the model. The model serves as a functional specification of the application that we can test the implementation against. Now Djikstra was no fan of testing, but if we relax the requirement of a full-blown proof we can arrive at a more lightweight definition of a "solid" product: a triple of a program, a model, and a property-based test that checks that the program conforms to the model. 

We'll talk about each of those in turn, but first let's get right into the modeling. We're going to build a personal finance application for tracking our recurring bills. All of the code referenced in this post is [available here](https://github.com/amw-zero/personal_finance_funcorrect).

~~~
export class Budget {
  recurringTransactions: RecurringTransaction[] = [];
  scheduledTransactions: ScheduledTransaction[] = [];
  error: string | null = null;

  ids: Record<string, number> = {};

  addRecurringTransaction(crt: CreateRecurringTransaction) {
    this.recurringTransactions.push(recurringTransactionFromCreate(this.genId("RecurringTransaction"), crt));
  }

  viewRecurringTransactions(): RecurringTransaction[] {
    return this.recurringTransactions;
  }

  viewScheduledTransactions(start: Date, end: Date) {
      let expanded = this.recurringTransactions.flatMap(rt => 
        expandRecurringTransaction(rt, start, end).map(d => (
          { date: dateStringFromDate(d), name: rt.name, amount: rt.amount }
        )));
      
      expanded.sort(compareScheduledTransactions);

      this.scheduledTransactions = expanded;
  }

  genId(type: string): number {
    if (this.ids[type]) {
      this.ids[type] += 1;

      return this.ids[type];
    }

    this.ids[type] = 1;

    return 1;
  }
}

~~~
{: .language-typescript}

First thing's first: we wrote our model in Typescript. There are many ways of creating model specifications with separate specification languages like TLA+ or Alloy, but in the Amazon paper above they went with implementing the model in the same language as the implementation. This makes writing the functional correctness test a lot simpler, as it can just reference the model and implementation directly.

A few other notes about this model. It's a class (`Budget`) which holds the state of the whole system. There are a few methods on it which influence the system state, and these are meant to model which user actions the user can take with the application. `addRecurringTransaction` is a basic CRUD operation - we just take the input data and store it in the system state. `viewScheduledTransactions` takes the current system state and "expands" the recurring transactions into the actual days that they'd occur based on their recurrence rules. For example we may pay rent monthly on the same day each month, but get our dog groomed every 3 weeks. The expansion logic is fairly nontrivial, especially since there's a lot of date-based math to achieve full correctness, as you can see in the [rrule library](https://github.com/jakubroztocil/rrule) which implements the iCalendar recurrence rule format. For now, we'll stay focused on the testing aspect vs. the actual domain logic, but feel free to browse the repo for [the full model](https://github.com/amw-zero/personal_finance_funcorrect/blob/main/personalfinance.ts).

One part that probably looks weird is our `genId` method which keeps track of global identifiers. We use this to assign a new ID for the Recurring Transactions that we create. This might seem like database logic, but I find that identifiers are actually a crucial part of any practical application. Either way, in order for the implementation to match the model state those identifiers will need to agree. There are certainly other ways to accomplish that, but this works for this example.

The main thing that I want to highlight here is how simple the model is. This is pure domain logic, and is probably as close to the essential complexity of the application that we can get. The full model is about 130 source-lines of code, including the type definitions of the system state. It's a very simple program because of the lack of web application details, and since this model will serve as the source of truth for the behavior of the application this simplicity is crucial. 

Now that we have a model of our behavior, let's first talk about what it would mean for an implementation to be correct with respect to this model.

# A Single Test for Conformance

The high level goal of a test for model conformance is to check that the implementation "does what the model does" in _all_ cases. So we'll introduce a `Client` object which is our entrypoint to the web app implementation. This object receives the same actions as the model, but calls into a web server to perform the action. That means that after all of the web requests, database queries, JSON serialization, etc., the end result of each of the actions in the model and implementation should be the same. 

To test for "all" cases, we'll use the [model-based testing capabilities of fast-check](https://github.com/dubzzz/fast-check/blob/main/packages/fast-check/documentation/Tips.md#model-based-testing-or-ui-test) to create large amounts of randomly generated sequences of these actions. As with all property-based tests, the random generation here is a proxy for checking all possibilities.

First we create a command object that runs the same action in both the model and the implementation:

~~~
class AddRecurringTransactionCommand implements fc.AsyncCommand<Budget, Client> {
  constructor(readonly crt: CreateRecurringTransaction) {}
  check = (m: Readonly<Budget>) => true;
  async run(b: Budget, c: Client): Promise<void> {
    b.addRecurringTransaction(this.crt);
    await c.addRecurringTransaction(this.crt);
  }
  toString = () => `addRecurringTransaction`;
}
~~~
{: .language-typescript}

Each command gets passed a `Budget` instance which we defined in the model, as well as the `Client` instance. We create similar command objects for the other system actions, and then we can wire them up into the full test. The test creates an array, `allCommands`, which holds all of these possible actions, and it uses `fast-check's` data generators to create the input data for each of the actions. `fast-check` takes in this array of commands and executes random sequences of them, and after each sequence is complete we can run some assertions that check that the model and implementation states are equal.

That's a bunch of info, but the full test is relatively small and looks like this:

~~~
const dateMin = new Date("1990-01-01T00:00:00.000Z");
const dateMax = new Date("1991-01-01T00:00:00.000Z");

Deno.test("functional correctness", async (t) => {
  let client = new Client();

  // 1. Data generators for all system action inputs
  const allCommands = [
    fc.record({ 
      name: fc.string(), 
      amount: fc.integer(), 
      recurrenceRule: fc.oneof(
        fc.record({ recurrenceType: fc.constant("monthly"), day: fc.integer({min: 0, max: 31}) }),
        fc.record({ 
          recurrenceType: fc.constant("weekly"), 
          day: fc.integer({min: 0, max: 31 }), 
          basis: fc.option(fc.date({min: dateMin, max: dateMax})), 
          interval: fc.option(fc.integer({min: 1, max: 20})) 
        })
      ) 
    }).map(crt => new AddRecurringTransactionCommand(crt)),
    fc.constant(new ViewRecurringTransactionsCommand()),
    fc.record({ 
      start: fc.date({min: dateMin, max: dateMax}),
      end: fc.date({min: dateMin, max: dateMax}), 
    }).map(({ start, end }) => new ViewScheduledTransactionsCommand(start, end)),
  ];

  await fc.assert(
    // 2. fc.commands generates random sequences of the actions defined in 1.
    fc.asyncProperty(fc.commands(allCommands, { size: "small" }), async (cmds) => {
      // 3. We're testing a web application with a database, so signal the start of the test case
      //    so that we can restore the system state at the end
      await client.setup();

      await t.step(`Executing scenario with ${cmds.commands.length} commands`, async (t) => {
        let model = new Budget();
        client = new Client();
  
        // 4. Run the list of commands in sequence by executing each command's `run` method
        const env = () => ({ model, real: client });
        await fc.asyncModelRun(env, cmds);
  
        // 5. Check that the model and implementation states are equivalent, and any additional 
        //    state in the Client has the expected value.
        await t.step("Checking invariants between model and implementation", async (t) => {
          await t.step("UI State", async (t) => {
            await t.step("loading", async () => {
              assertEquals(client.loading, false);
            })
            await t.step("error", async () => {
              assertEquals(client.error, model.error);
            });
          });

          await t.step("Recurring transactions are equal", async () => {
            assertEquals(client.recurringTransactions, model.recurringTransactions);
          });

          await t.step("Scheduled transactions are equal", async () => {
            assertEquals(client.scheduledTransactions, model.scheduledTransactions);
          });
        });

        // 6. Restore system state to its state before the test iteration
        await client.teardown();
      });
      console.log("\n")
    }),
    { numRuns: 100 }
  );
});
~~~
{: .language-typescript }

The actual test in the example repo has some added logging to show what's going on in each test case in more detail, and here's an example scenario that's generated:

```
  Executing scenario with 5 commands ...
------- output -------
  [Action] addRecurringTransaction
    {
      "name": "tCnRiS",
      "amount": 1518583647,
      "recurrenceRule": {
        "recurrenceType": "monthly",
        "day": 0
      }
    }
  [Action] addRecurringTransaction
    {
      "name": "",
      "amount": -1669970975,
      "recurrenceRule": {
        "recurrenceType": "weekly",
        "day": 3,
        "basis": "1990-06-08T17:55:25.769Z",
        "interval": 17
      }
    }
  [Action] addRecurringTransaction
    {
      "name": "xRL",
      "amount": -1400152232,
      "recurrenceRule": {
        "recurrenceType": "weekly",
        "day": 19,
        "basis": "1990-03-11T00:36:49.477Z",
        "interval": 10
      }
    }
  [Action] addRecurringTransaction
    {
      "name": "V/'/]dlYwp",
      "amount": -1711622850,
      "recurrenceRule": {
        "recurrenceType": "monthly",
        "day": 13
      }
    }
  [Action] viewScheduledTransactions start: Mon Mar 05 1990 17:36:42 GMT-0500 (Eastern Standard Time), end: Wed Sep 26 1990 12:25:40 GMT-0400 (Eastern Daylight Time)
----- output end -----
    Checking invariants between model and implementation ...
      UI State ...
        loading ... ok (3ms)
        error ... ok (2ms)
      ok (7ms)
      Recurring transactions are equal ... ok (2ms)
      Scheduled transactions are equal ... ok (3ms)
    ok (13ms)
  ok (78ms)
  ```

Here the test generated a scenario with 5 actions, where 4 recurring transactions were added in a row and then the corresponding scheduled transactions were viewed. All of the invariants are checked after that, and they all pass.

It's important to drive the point home that the variance in action sequences that the test can generate is immense, depending on how `fast-check` is conifgured. This is the main value proposition of property-based testing! In the above snippet, we're setting the number of scenarios to 100 (with `{ numRuns: 100 }`). The number of commands per scenario is also configurable. This test passes `{ size: 'small' }` to the `fc.commands` function, which generates sequences with lengths between 0 and 10. `fast-check` supports `medium`, `large` and `xlarge` sizes, which generate much longer lists of commands - `xlarge` generates sequences of up to 10,000 commands.

To get a sense for how long this takes, on my machine (an M1 Max Macbook), 100 small iterations took about 9 seconds to run, 1,000 small iterations took 1 minute and 45 seconds, and 100 medium iterations took 45 seconds. These are integration tests that go all the way from the client to a Postgres database, which brings us to our actual implementation.

# The Implementation

A couple of design decisions had to be made to enable model-based testing in this way. The first questsion is, what should `Client` be? In order to compare an implementation to the model, they have to have the same interface and hold comparable state. This application will have a React UI, so we could make `Client` something like a React class component supporting the same methods as the model, but almost all of the flaky tests I've ever encountered have been involving an actual UI. Instead, we'll go one layer below the React UI and have `Client` be a class which manages the state of the application and handles all networking with the API server. The model-based test is therefore not a full end to end test but starts at this layer, and we'll rely on a simple state-binding strategy to ensure that the `Client` state is always properly rendered in the UI. On top of that, the `Client` is statically typed, so that should also reduce the change of passing invalid date into it.

For the state binding, we'll use MobX. MobX plays very nicely with binding stateful classes to React's view state while having pretty minimal setup code. With the `Client` object and MobX handling the heavy lifting of the application's state management, the React UI is kept very thin, only forwarding user input to the `Client` and rendering its state. This is commonly called the [humble object pattern](http://xunitpatterns.com/Humble%20Object.html). To be clear, the React UI itself is left untested by the model-based test, but of course it can be tested separately if desired.

Here's an excerpt of the `Client` to get more concrete:

~~~
export class Client {
  recurringTransactions: RecurringTransaction[] = [];
  scheduledTransactions: ScheduledTransaction[] = [];

  loading: boolean = false;
  error: string | null = null;

  constructor(config: (c: Client) => void = () => {}) {
      config(this);
  }

 async addRecurringTransaction(crt: CreateRecurringTransaction) {
    this.updateLoading(true);

    let resp = await fetch(`${API_HOST}/recurring_transactions`, {
      method: "POST",
      body: serializeRecurringTransaction(crt),
      headers: {
        'Content-Type': "application/json",
      },
    });

    this.updateNewRecurringTransaction(await resp.json());
  }

  async setup() {
    return fetch(`${API_HOST}/setup`, {
      method: "POST",
    });
  }

  async teardown() {
    return fetch(`${API_HOST}/teardown`, {
      method: "POST",
    });
  }

  updateNewRecurringTransaction(json: RecurringTransactionResponse) {
    this.loading = false;
    switch (json.type) {
    case "recurring_transaction":
        this.recurringTransactions = [...this.recurringTransactions, normalizeRecurringTransaction(json)];
        break;
    case "error":
        this.error = json.message;
        break;
    default:
        console.log("Default was hit when updating new recurring transaction")
    };
  }
}
~~~
{: .language-typescript}

The choice of MobX influenced two main aspects of the `Client`. First, the constructor has to accept a `config` callback so the React app can setup MobX to mark its state as automatically observable. Second, any actual updates to the state of the `Client` have to take place in non-async functions - not adhering to this caused a warning in the browser console. Both of these were easy to work around.

That brings us to our API server. In this example, I went with Rails, but any server framework or library would do. The first interesting part of the server are the `setup` and `teardown` APIs which the test calls. These allow the server to clean up any database state created in each property iteration so that each iteration starts with fresh data and leads to a deterministic test case. Rails has the tried and true `database_cleaner` gem which takes care of most of this for us. All that we need to do is pick the appropriate cleaning strategy. Since the test spans multiple different endpoint requests, the proper strategy is the truncation strategy, which truncates only the tables that have been written to during the test when the `pre_count` option is set to true:

~~~
class TestController < ApplicationController
  def setup
    DatabaseCleaner.strategy = DatabaseCleaner::ActiveRecord::Truncation.new(pre_count: true)
    DatabaseCleaner.start
  end

  def teardown
    DatabaseCleaner.clean
  end
end
~~~
{: .language-ruby}

The next interesting thing is how we represent the recurrence rules in the database. In the model, they're represented as discriminated unions since that's the most natural way to model them, but SQL doesn't have any built in way to store them. There are various ways to do this, but let's just pick one and go for it. We'll just serialize the rule into a string and store that in the DB in the same table as the recurring transaction model. We can do this with the ActiveRecord attributes API and a custom type conversion:

~~~
class RecurringTransaction < ApplicationRecord
  attribute :recurrence_rule, RecurrenceRuleType.new
end

...

# Recurrence rules are stored as a string with format:
#   '<type>::attr1=v1;attr2=v2;...'
#
# The type represents the different rule types, e.g. Monthly and Weekly,
# and the list of attribute keys and values represent the data for each
# rule type.

class RecurrenceRuleType < ActiveRecord::Type::Value
  def resolve_rrule_type(type_str)
    case type_str
    when 'monthly'
      RecurrenceRule::Monthly
    when 'weekly'
      RecurrenceRule::Weekly
    else
      raise "Attempted to cast unknown recurrence rule type: #{type}"
    end
  end

  def cast(value)
    if value.is_a?(String) && value =~ /^weekly|monthly:/ 
      value_components = value.split('::')

      if value_components.length != 2
        raise "Recurrence rule DB strings must be of the format ''<type>:attr1=v1;attr2=v2;...'. Attempted to cast a string with #{value_components.length} components: #{value}" 
      end

      type, all_attrs = value_components

      attr_pairs = all_attrs.split(';')
      attrs = attr_pairs.each_with_object({}) do |attr_pair, attrs|
        k, v = attr_pair.split('=')
        if !v.nil?
          attrs[k] = v
        end
      end

      super(resolve_rrule_type(type).from_attrs(attrs))
    elsif value.is_a?(ActiveSupport::HashWithIndifferentAccess)
      attrs = value.except(:recurrence_type)

      super(resolve_rrule_type(value[:recurrence_type]).from_attrs(attrs))
    else
      super
    end
  end

  def serialize(value)
    if value.is_a?(RecurrenceRule::Monthly) || value.is_a?(RecurrenceRule::Weekly)
      attrs = value.db_serialize.to_a.map { |k, v| "#{k}=#{v}" }.join(";")
      case value
      when RecurrenceRule::Monthly
        super("monthly::#{attrs}")
      when RecurrenceRule::Weekly
        super("weekly::#{attrs}")
      end
    else
      super
    end
  end
end
~~~
{: .language-ruby}

The implementation is where most of the nitty gritty details show up because of the trifecta of networking, UI state binding, and database concerns. But once this is in place, the test has been very reliable, and we're free to change pretty major implementation details while keeping the test unchanged. 

The single functional correctness test was also invaluable for getting these details right.

# Would Anyone Ever Do This On a Real Web Application?

Well, it depends, but I think that it's less crazy than it may seem at first glance. The first thing that I want to talk about in this respect is the delta between the perceived high-level behavior of the application and the lower-level behavior in the application's architecture. I don't think it's crazy to say that in modern applications that delta is actually quite large, and my justification for that opinion is the amount of times I or one of my coworkers have said: "this application is just simple CRUD, and I have to write so much code to just move data around!" This is exacerbated if you're working with services - one simple action in terms of the model might involve communicating across multiple different services, compiling all of the data together before applying further processing and sending to the client. Now sure, libraries and frameworks exist to make operating within the architecture a little easier, but they don't get rid of the overhead entirely.

Why do complicated web architectures exist in the first place? Most if not all facets of web architecture boil down to some kind of optimization. Using a database is often a performance optimization, but also an optimization to ensure data integrity amongst concurrent accesses and modifications. There are many reasons to use services, but the main reasons are to optimize for modularity in the face of many teams or to optimize a small subset of the system's operational characteristics independent of the rest. Specific to this example, the changes to the `Client` object to play nicely with MobX are a result of React's declarative UI which is an optimization for developer cognitive load. The presence of optimizations are one of the best reasons to use a model, because the model captures the essence of the system, whereas the actual optimizations cloud that simple behavior. 

And like everything else, back in the 70s we were already thinking about this problem of optimization making verification more difficult and considering how to use models to make it simpler:

> I also claim that in order to prove by Floyd's method the correctness of a program A, in a case where data is represented unnaturally, perhaps for efficiency's sake, the easiest and most lucid approach is rather close to first designing a program B which is simulated by program A and which represents the data naturally, and then proving B correct.
> 
> [-Robin Milner, An Algebraic Definition of Simulation Between Programs 1971](https://www.ijcai.org/Proceedings/71/Papers/044.pdf)

That's right. Even proofs are easier when the logic being verified is simpler. Simplicity always wins in the end.

As far as cost of effort, the [aformentioned paper by Amazon](https://assets.amazon.science/77/5e/4a7c238f4ce890efdc325df83263/using-lightweight-formal-methods-to-validate-a-key-value-storage-node-in-amazon-s3-2.pdf) found that their reference models were just 1% of the size of the implementation code, and the overall model-based testing framework and actual test properties totaled 12% of the component's codebase. Contrast that with gigantic unit test suites that are often 2-3x the size of the production code! No test suite is free, and beyond the actual size of a test suite, I've also found that large unit test suites can lead to [TDD Ossification](https://matklad.github.io/2021/05/31/how-to-test.html). So, if the application behavior is relatively simple, but general distributed system complexity makes your implementation large and complex, models can be a big win and an actual cost saver with respect to the overall project code size and agility.

Even if it has benefits over traditional unit testing, I'd like to point out that model-based testing is fairly noncommital and doesn't prevent you from doing any other kinds of testing. For example, as the property-based test caught bugs in this example application, I used them to create regular example-based tests to be able to figure the issue with that specific scenario. If we know that certain scenarios are really important, we can easily add specific unit or integration tests for them, using all of the same tools and techniques that we use today. So model-based testing doesn't have to replace anything, but can rather complement your existing test suite. Such tests are in the repo in [a separate examples.ts test file](https://github.com/amw-zero/personal_finance_funcorrect/blob/main/examples.ts). Note how after just a few examples, this file is already ~400 lines of code, whereas the model-based test is only ~100.

Now to the tradeoffs. One often-cited benefit of fine-grained unit tests is that they provide very specific error messages when they fail so you know exactly where the error needs to be fixed. The model-based test basically gives you a binary message: correct, or not correct. To mitigate this, I added logs to all of the actions so that the full trace of behavior could be looked at after any failure. From there, we'd still need to figure out where in the codebase the actual error is. While I agree that specific error messages are a desirable property, I still think the benefit is oversold. In practice, it's not that difficult to narrow down to the problematic area of code in the span of a few web requests. But it's still worth calling out, and anything we could do to improve that I'm on board with.

Also, while the overall size of the test suite code might be reduced, the price we pay for that is the test runtime. No matter how many random tests get run, it won't be exhaustive, so the more we allow the property-based test to run the better. Luckily, property-based testing is an embarrassingly parallelizable problem since each property iteration is totally independent from the next. While it's still not free, we can simply run many invocations of the same test at the same time and cover more surface area in parallel. One other idea there is to decompose the single test for all commands into multiple different subsets of commands, where a subset of commands is picked related to individual feature areas. For example, as the personal finance application grows and we add something like authentication, we can test the auth flow separately from recurring transaction management.

Probably the biggest concern is misspecification. Since it's the source of truth, as the model grows and changes it's going to be hard to know when something was simply expressed incorrectly in the model, or when some important aspect of the model was lost. This is a very tricky problem in general, but I would also argue that it's also unavoidable and not solved by other approaches either. Since the model is executable, it can also be tested though, and testing an in-memory class is much simpler than testing a full distributed system. For example, it's much easier to check properties and invariants on the model since it is small. This is what Robin Milner was getting at in the above quote.

# Wrapping Up

Overall, even when considering the tradeoffs, this flavor of model-based testing seems to have a great cost-to-value ratio. To see the value of property-based testing in practice, check out the [example test cases](https://github.com/amw-zero/personal_finance_funcorrect/blob/main/examples.ts) that I got simply by taking failure traces from the model-based test and turning them into a single deterministic example. The flagship example of that the test caught a discrepancy when expanding recurring transactions in a range where a crossover to daylight savings time occurred. As much as I try to be vigilant, this is a test case I would have never written ahead of time! Any tool or methodology that actually points out unknown-unknowns is extremely compelling.

The performance also isn't as bad as you would think, and as we mentioned before this style of testing is very amenable to parallelization. We live in a world now where [Jepsen](https://jepsen.io/) regularly finds issues in real distributed systems products with property-based integration tests.

The React UI is also totally functional. Feel free to build the app and run it, and of course please report any bugs :)
