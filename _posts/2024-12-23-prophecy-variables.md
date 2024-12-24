---
layout: post
title: 'Controlling Nondeterminism in Model-Based Tests with Prophecy Variables'
tags: testing refinement
author: Alex Weisberger
---

We have to constantly wrestle with nondeterminism in tests. Model-based tests present unique challenges in dealing with it, since the model must support the implementation's nondeterministic behavior without leading to flaky failures. In traditional example-based tests, nondeterminism is often controlled by adding stubs, but it's not immediately clear how to apply this in a model-based context where tests are generated. We'll look to the theory of refinement mappings for a solution.


<hr>
In model-based testing, we construct a model of the system and use it as an executable specification in tests. One of the main benefits of doing this is that we end up with a highly-simplified description of the system's behavior, bereft of low-level details like network protocols, serialization, concurrency, asynchronicity, disk drives, operating system processes, etc. The implementation, however, has all of these things, and is beholden to their semantics.

This generally means that model states are not equivalent to implementation states, and are thus not directly comparable. This is fine, [because we can define a refinement mapping between them]({% post_url 2023-01-31-model-based-testing-theory %}) and carry on. Nondeterminism complicates this mapping though.

Let's look at a concrete example. Here's a model of an authentication system, that allows for the creation of new users:

```typescript
type User = {
    id: number;
    username: string;
    password: string;
}

type CreateUser = {
    username: string;
    password: string;
}

type AuthError = 'username_exists';

class Auth {
    users: User[] = [];
    error: AuthError | null = null;

    createUser(toCreate: CreateUser) {
        if (this.users.some(u => u.username === toCreate.username)) {
            this.error = 'username_exists';
            return;
        }

        const user: User = {
            username: toCreate.username,
            password: toCreate.password
        }

        this.users.push(user);
    }
}
```

In this model, we have a set of Users that we can add to, or in doing so there might be an error if the username is already taken. This error is a domain error, related to the logic of authentication, so it's essential to include in the model.

Not all errors are alike. In a real implementation, we're going to have timeouts set on the web request as well as database statements. Timeouts are unrelated to the domain of authentication, and they also happen to be non-deterministic: for the same inputs, a timeout may or may not occur based on system load. It's not obvious what to do about this, but if we do nothing, two problems arise:

1. A timeout in the test could lead to a flaky test failure.
2. We don't sufficiently test the timeout-handling codepath.

These need to be addressed.

# Handling Implementation-Level Errors in a Model

What does a timeout in the implementation mean in terms of the model? There's two main interpretations:

1. It corresponds to a no-op in the model (aka a stutter step).
2. It maps to some separate error value in the model.

Either one isn't more correct than the other, but be aware that allowing for stutter steps leads to potential false positive passing tests. If a timeout occurs in the `createUser` operation, no new users will be added to the set of all users, but the test will still pass because we chose to allow for equal initial and final states. Stutter steps are necessary in theory, but we should be careful when allowing for them in tests otherwise our test suite will pass on a run where 100% of calls to `createUser` time out.

There are ways of mitigating the risk of vacuously passing tests. For example, we could make a statistical correctness statement: the test only passes if no more than 10% of `createUser` operations time out. This is more of a statement about _reliability_ though, and not a statement about functional behavior. I think it's best to keep functional behavior tests in the domain of logical time, and to instead use observability tools for collecting reliability metrics.

For functional testing, there's a better way that avoids statistical correctness statements. It just involves predicting the future.

# Tests, Oracles, and Prophecy

A brief philosophical aside. Tests are almost entirely about seeing into the future. By simply writing down the expected outputs of an operation, that means that we know what they should be ahead of time. We are the so called test oracle. In model-based testing, we instead delegate this prediction to the model: the model is the oracle.

There's a very well-known solution to the problem of predicting the future of a nondeterministic operation in a test: test doubles. Stubs in particular are commonly used to control things like timeouts. Say we have a client-server implementation of our `Auth` module. We'd likely make client-side network requests through an interface and use stubs in our tests to control the code path taken:


```typescript
type User { ... }
type AuthSystemError = 'timeout';
type AuthError = 'username_exists';
type AuthServerResponse = User | AuthError | AuthSystemError;

interface AuthServer {
  createUser(toCreate: CreateUser): AuthServerResponse;
}

class AuthClient {
    users: User[] = [];
    server: AuthServer;
    error: string | null = null;

    constructor(server: AuthServer) {
      this.server = server;
    }

    createUser(toCreate: CreateUser) {
      const resp = this.server.createUser(toCreate);
      if (resp === 'timeout') {
        this.error = 'There was a problem creating the user. Please try again or contact support.';
      } else if (resp === 'username_exists') {
        this.error = 'That username is already taken. Please choose another.';
      } else {
        this.users.push(resp);
      }
    }
}

// test file:
class AuthServerTimeout implements AuthServer {
  createUser(toCreate: CreateUser): AuthServerResponse {
    return 'timeout';
  }
}

describe('Timeout behavior', () => {
  it('displays a timeout message when the request times out', () => {
    const auth = new AuthClient(new AuthServerTimeout());
    auth.createUser({ username: 'user', password: 'pass' });

    expect(auth.error).toEqual('There was a problem creating the user. Please try again or contact support.');
  });
});
```

This pattern is ingrained in our muscle memory, but it's actually quite interesting from the perspective of oracles and predicting the future. The simple `AuthClient` has code paths that are not ergonomic to trigger in a test (we like to avoid the use of `sleep` anywhere in tests, and otherwise the timeout will be dependent on nondeterministic system load). So instead of triggering the scenario that leads to a timeout, we simply setup the code in a way that guarantees the timeout code path is taken. In effect, we tell the code under test what its own destiny is, and use that to be able to create a dependable, deterministic assertion in the test.

From the test-writers point of view, this is a simple technique, but from the code's point of view, it's as if we're showing it a prophecy of its life ahead of time. We are an oracle indeed!

In model-based tests, we don't create individual test cases, so we need a way to generate different stub configurations if we want to test a timeout code path. Once we put it that way, the answer is simple: just generate a variable that we can use to dynamically configure stubs. Because this variable predicts future execution, we call it a _prophecy variable_.  For this, we can name it `isTimeout`, and go from there. First we extend the model to be aware of this variable:

```typescript
class Auth {
  // ...
  error: AuthError | AuthSystemError | null = null;

  createUser(toCreate: CreateUser, isTimeout: boolean) {
    if (isTimeout) {
      this.error = 'timeout';
      return;
    }

    // ...
  }
}
```

This avoids the stutter-step issue from before. We elevate the system-level error to the model level, and we make it so that  timeout error only occurs when `isTimeout` tells it to. This is how we can be sure that unintended timeouts aren't happening in the tests. Then, the implementation:

```typescript
class AuthServerImpl {
    users: User[] = [];

    createUser(toCreate: CreateUser): AuthServerResponse {
      // real networking / server impl
    }
}

class Client {
    users: User[] = [];
    error: AuthError | null = null;
    implError: AuthSystemError | null = null;
    
    server: AuthServer;

    constructor(server: AuthServer) {
      this.server = server;
    }

    createUser(toCreate: CreateUser) {
      const result = this.server.createUser(toCreate);
      if (result === 'timeout') {
        this.implError = result;
        return;
      }

      if (result === 'username_exists') {
        this.error = result;
        return;
      }

      this.users.push(result);
    }
}
```

And here's what the model-based test would look like:

```typescript
const genToCreate = () => fc.record({
  username: fc.string(),
  password: fc.string()
});

const genUser = () => fc.record({
  id: fc.integer(),
  username: fc.string(),
  password: fc.string()
});

const genUsers = () => fc.array(genUser());

const genProphecy = () => fc.boolean();

const externalAuthState = (auth: Auth): AuthState => {
  return {
    users: auth.users,
    error: auth.error
  }
}

const externalClientState = (client: Client): ClientState => {
  return {
    users: client.users,
    error: client.error,
    implError: client.implError,
  }
}

const refinementMapping = (isTimeout: boolean, implState: ClientState): AuthState => {
  return {
    users: implState.users,
    error: isTimeout? implState.implError : implState.error,
  }
}

describe('Prophecy-aware Auth test', () => {
  it('should correspond to the model', () => {
    fc.assert(
      fc.property(genUsers(), genToCreate(), genProphecy(), (users, toCreate, isTimeout) => {
        const auth = new Auth();
        auth.users = [...users];

        let server: AuthServer;
        if (isTimeout) {
          server = new AuthServerTimeout();
        } else {
          const realServer = new AuthServerImpl();
          server = realServer;
        }
        const client = new Client(server);
        client.users = [...users];

        auth.createUser(toCreate, isTimeout);
        client.createUser(toCreate);

        const authState = externalAuthState(auth);
        const mappedState = refinementMapping(isTimeout, externalClientState(client));
        expect(mappedState).toEqual(authState);
      }),
      { endOnFailure: true, numRuns: 10000}
    );
  });
  });
```

We use `isTimeout` to choose which `AuthServer` implementation to use, and we compare the now-prophecy-aware implementation to the model. To compare the different state values, we do a little bit of bookkeeping, first by projecting each object to an "external" state which omits any implementation details. We also create a `refinementMapping` function which maps implementation states to model states. The refinement mapping is also aware of the `isTimeout` variable, and uses that to make sure we only elevate the implementation error to the model when it is prophesied.

Now, we have a pattern for building property-based tests that can account for nondeterministic errors. 

# A Brief Note on The Theory of Prophecy Variables

Prophecy variables are much more powerful than simple stubs in example-based tests, but I can't but help notice the practical similarity between them. They were introduced in the paper [The Existence of Refinement Mappings](https://pdf.sciencedirectassets.com/271538/1-s2.0-S0304397500X02873/1-s2.0-030439759190224P/main.pdf?X-Amz-Security-Token=IQoJb3JpZ2luX2VjEBQaCXVzLWVhc3QtMSJHMEUCIQD%2BBLlExS4dmhBZPzTgmVAoPQjqARHVn12RhMRMoUfqCAIgJbSyIbWbqun%2Fzg2z7obtZ59EZg6ezZdKfTOTQuBAXmYquwUI3P%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FARAFGgwwNTkwMDM1NDY4NjUiDMuLkQag4yi1ilbtBiqPBZrCA7WT87lx1Y6Mf4DkO1ch8rhes0DvkLxWJqX8R3j43Pyl2Olt2FBVvsmJfJPV7CGXXVqB307Qn7AXpskbr1konRFi6fHcSXd247S1qFNONVWffdR5Z2Uz8AVDkDYos0nyNVKsL%2B7Ev3eqF3VWdaYS8lpHfNwJkSZdOXmEIQ2rvajiwIFu2JCoo0JdOqutSR6Sf94ILpjy8mkmLBbJdybaObPn%2FHcBSl549PqEVVuxDvJyEr0vwei%2Bhl0ngiQT2Hbmzq5V3QWw7IxMzvRTDEhyLxm3KecyoRaNi4%2Bz4ujFGVjH0A0g88B56a5OrfjR7SkYMkAZs4Gb7dtPt6tzrTXNPZuA0R1YoxBFzsHMIXM%2FZgBpAG9yJ8MWeP%2F61lG3S08o1snsval%2BPoDbAgkga22RPDlPeyQnHRSL9%2F0rXh5oAbXIOX9M%2FwRlSqyKkcjyUwTaexa7R2qzeS76uECr9EVQZ0lPGFhawt363Bn0ozk8OF6%2BBxRRvE0qBYXAgq0sEGb3csj8p6FlNKZ7UTHLClN9QddmqrXg1yURHrIveoBiQ2WrS3lKfEMAyre5cFi7yaYHXZEidyVY7hZMBrCPCFUef1He9uIh1aC0rfBAL7LCBLYo0Rz2LRRT650IaK%2FDAzVFMbku0bJeLhrqKmNXntyqYSYEVMC6WkMJ4AIda61eFQgEm8x239eoWIoHiGE2N93QmHY4Z1LiaohdnsiMsXiwLmdz45qQMOvHy%2BzoU3AbMnI1KY4k8UjRL%2FuC303nk8eUs7pjrLzRJY8pSAKK9v5311tg%2F1jYnCeoax6daTsazgl8cP9NtLMTf6LCCkZqoQdEYzEkwVzyQ0a9HGqWz6i3017fw%2FXbR8uqOz8x0QQw0OimuwY6sQEBLik2N00q8xavkw2mRr%2BGTNafaoIuTpHt%2FBu2HLGPb2NwLDWDTUWDjuj9A%2FWN1tFG7HL%2FlU4sD4sPcwRJwZAUkm4aNqyBNJddQiZzPXo9V640IbswUVPcDk8zN4ILDRuSb7TKqKkyMs0KwMvPaZY0r6NOe6E8sOD3ZLsT7T5t9XRWuS8uEbpt5uDOj0KVGO9lF5vwIMcpL1uYhuz8RNzYhVw%2FiVNb%2FAcZvyqNcXlhfc8%3D&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20241223T194402Z&X-Amz-SignedHeaders=host&X-Amz-Expires=300&X-Amz-Credential=ASIAQ3PHCVTYSDYZAUMU%2F20241223%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Signature=9b7b0f8cf3372c1c2573f3a00b58371fec5ffe819c2785514f70667158d3db09&hash=970922d7eed44e51e9c8084829e6c19241d4551fa00175b640cf16a58648c71b&host=68042c943591013ac2b2430a89b270f6af2c76d8dfd086a07176afe7c76c2c61&pii=030439759190224P&tid=spdf-8f7ba5e4-2f0f-4b0a-8139-fab3ae67cd33&sid=86cccb5f88e9a045366b20d6625a7c20af4cgxrqa&type=client&tsoh=d3d3LnNjaWVuY2VkaXJlY3QuY29t&ua=0f155d0955060b56575e00&rr=8f6ad811eb928ca5&cc=us) to solve the theoretical problem of proving refinement between specifications with nondeterminism. The paper showed that there are programs where proving the refinement of their specification is impossible due to nondeterminism. Not only do prophecy variables solve that problem, they also lead to a _complete_ solution to the problem. The main result in the paper is that we can find a suitable refinement mapping for _any_ program to any specification, as long as we are able to add history and prophecy variables to the refinement mapping in a way that doesn't alter the observable behavior of either the program or the spec.

That's true of test doubles: they don't alter the code under test, they just allow for specifying values ahead of time, which again is the key to dealing with nondeterminism in tests. Our usage of prophecy variables here differs slightly from the theoretical versions (we pass ours into the refinement mapping function rather than keeping the function as a pure mapping from implementation to model state, and we also use interfaces and stubs to modify the behavior rather than only limiting ourselves to state variables). Still, this departure is only surface-level, since we could map this all to the TLA+-style state framework if we wanted to. Using the idioms of the particular programming language we're in makes for a more practical experience.

For more info, there's a deeper dive into the theory of refinement mapping in [Efficient and Flexible Model-Based Testing]({% post_url 2023-01-31-model-based-testing-theory %}). And there's a whole paper dedicated to prophecy variables in [Prophecy Made Simple](https://lamport.azurewebsites.net/pubs/simple.pdf).

# Prophecy-Aware Dependencies and Modal Determinism

This will be the most ambitious part of the post. It begins with a statement: we should design our dependencies to be prophecy-aware.

Dependencies are a double-edged sword, especially infrastructure dependencies like a database. On the one hand, we get an incredible amount of power and reliability that would be impossible to implement on our own. On the other, we lose control, and are beholden to extremely fine-grained semantics that, among other things, make holistic testing difficult. I greatly believe in integration testing, especially against something like a database, because of such semantics that our applications come to depend on. I wrote about this in [Does Your Test Suite Account For Weak Transaction Isolation?]({% post_url 2023-12-31-txn-isolation-testing %}). Things like transaction isolation ultimately affect the correctness of our applications, so their absence from most application test suites is an unideal blind spot.

This absence is totally understandable though: testing for it is a pain, precisely due to the inability to control nondeterminism. To systems and infrastructure developers: please account for the testing of nondeterministic functionality in the design of your tools. All nondeterministic choices should be able to be controllable by parameters. This allows nondeterminism to be used where necessary (and it often is necessary and not just a mistake, e.g. for performance or concurrency), while also being able to be controlled in tests. There's definitely an upswing in projects thinking about this up front, notable examples being FoundationDB and TigerBeetle. I don't want to make light of it, because it can radically alter the design of a system. But, having controllable determinism will always be a good thing in my book.

However, in the meantime, most of our dependencies are not prophecy-aware, so we do need an approach for handling them as-is. For this, I think our best bet is to create wrapper fakes which model a given dependency. These models will need to be nondeterministic, since the implementation is, however we can design them to also be prophecy-aware and thus controllable in tests as well. Because such models have this dual behavior, I think of this as "modal determinism."

Let's continue with the example of transaction isolation in Postgres. And let's say that we first discovered weak transaction isolation and the Read Committed isolation level. We start to hone in on this being an issue, and we first write this test (against a real PG DB):

```sql
-- Create test schema
create table txn_iso (ival int);
insert into txn_iso (ival) values(1);
```

```typescript
import * as fc from 'fast-check';
import { Database, DBModelNondet } from './database';
import { PoolClient } from 'pg';

type Tuple = {column: string; value: any}[];

class Database {
    pool: pg.Pool;

    constructor() {
      this.pool = new Pool(/* connection info */);
    }

    async selectInClient(client: pg.PoolClient): Promise<Tuple[]> {
      const res = await client.query(`SELECT * FROM txn_iso`);
      return res.rows.map((row) => {
        return [{ column: 'ival', value: row['ival'] }];
      });
    }

    async update(val: number)  {
      const client = await this.pool.connect();

      await this.updateInClient(client, val);

      client.release();
    }

    async updateInClient(client: pg.PoolClient, val: number) {
      return client.query(`UPDATE txn_iso SET ival = $1`, [val]);
    }
}

const genUpdateVal = () => fc.integer({ min: 0, max: 10 });

const genTxnOrder = () => fc.uniqueArray(fc.integer({ min: 0, max: 2 }), {minLength: 3, maxLength: 3});

const initialVal = 1;

describe('Database nondeterministic transaction reads', () => {
  it('should return consistent reads', async () => {
    let db: Database;
    let c1: PoolClient;
    let c2: PoolClient;
    await fc.assert(
      fc.asyncProperty(
        genUpdateVal(),
        genTxnOrder(),
        async (val, txnOrder) => {
          db  = new Database();

          c1 = await db.pool.connect();
          c2 = await db.pool.connect(); 

          await c1.query('BEGIN');
          await c2.query('BEGIN');
          const prevRead = await db.selectInClient(c2);
          await db.updateInClient(c1, val);

          const operations = [c1.query('COMMIT'), c2.query('COMMIT'), db.selectInClient(c2)];
          let orderedOperations = [];
          let readIdx = txnOrder[2];
          for (let i = 0; i < txnOrder.length; i++) {
            orderedOperations[txnOrder[i]] = operations[i];
          }

          const results = await Promise.allSettled(orderedOperations);
          const read = results[readIdx];
          
          if (read.status === 'fulfilled') {
            expect(read.value).toEqual(prevRead);
          } else {
            fail('Read failed');
          }
      }).afterEach(async () => {
        await db.update(initialVal);

        c1.release();
        c2.release();

        await db.pool.end();
      }),
      { endOnFailure: true, numRuns: 100}
    )
  });
});
```

This test creates two DB connections, one of which is updating a value in the `txn_iso` table, and another which reads it multiple times. We expect that the multiple reads return the same value, but they don't. We also randomize the order of the commits of the transactions to exacerbate the issue, but even without that the test will fail nondeterminstically.

This is complex and surprising behavior, and we want to build a model of it so that we can deterministically control it in our application tests to get more realistic coverage. The key is recognizing that the model has to support this nondeterminism by returning _multiple_ possible values for select statements instead of just a single one. We can then create a model-based test that allows for any of the possible values to be returned in the implementation. This draws inspiration from the [nondeterministic seL4 specification](https://trustworthy.systems/publications/nicta_full_text/3087.pdf) which defines nondeterminism as transitioning between multiple allowable states.

We create the following model:

```typescript
type Tuple = {column: string; value: any}[];
type Relation = { name: string, data: Tuple[] };
type Transaction = {id: number, isDirty: boolean, prev: Relation[], next: Relation[]};

type DBState = {
  relations: Relation[];
  transactions: Transaction[];
};

class DBModelNondet {
  state: DBState[] = [];

  select(txnId: number, relation: string): Tuple[][] {
    return this.state.map((s) => {
      const dirtyTxn = s.transactions.find((txn) => txn.id === txnId && txn.isDirty);
      if (dirtyTxn) {
        return dirtyTxn.next.find((rel) => rel.name === relation)?.data ?? [];
      }

      return s.relations.find((rel) => rel.name === relation)?.data ?? []
    });
  }    
}
```

We model the database (`DBState`) as a list of `Relations`, where each `Relation` is itself a list of `Tuples`. We also model transactions as having an id, a previous list of relations, a next list of relations, as well as an `isDirty` flag which signals whether or not the transaction has written any data at this point in time. The `prev` list of relations tracks the snapshot of the DB state when the transaction was started, and `next` tracks the current state including any transaction-local modifications that haven't been committed yet.

We then store an _array_ of these `DBStates`, not just a single one. Because the database hides a nondeterministic choice from us (the order of operations of when concurrent connections are scheduled), we have to support multiple initial starting states in the model. This allows us to handle both cases of the race condition here: where connection `c1` is committed before and after the second read in `c2`.

Then, we write a simplified `select` model that executes within a specified transaction and returns all rows of a particular `relation`. For each current `state`, the select either returns tuples that have been modified in an in-progress transaction, or falls back to the committed state if the transaction hasn't modified anything. Because there can be multiple `states`, `select` is also nondeterministic and returns a list of `Tuple` lists.

This surprisingly simple model allows us to accurately model non-repeatable reads. We can use it to ensure it supports the nondeterminism caught in the previous test:

```typescript
describe('Database reads nondet model', () => {
  it('should return any of a set of allowable reads', async () => {
    let db: Database;
    let c1: PoolClient;
    let c2: PoolClient;

    await fc.assert(
      fc.asyncProperty(
        genUpdateVal(),
        genTxnOrder(),
        async (val, txnOrder) => {
          db  = new Database();
          const model = new DBModelNondet();

          c1 = await db.pool.connect();
          c2 = await db.pool.connect(); 

          await c1.query('BEGIN');
          await c2.query('BEGIN');
          await db.updateInClient(c1, val);

          model.state = [
            // State 1: write transaction has not been committed yet.
            {
              relations: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }],
              transactions: [
                { 
                  id: 1,
                  isDirty: false,
                  prev: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }],
                  next: [{ name: 'txn_iso', data: [[{ column: 'ival', value: val }]] }] 
                },
                {
                  id: 2,
                  isDirty: false,
                  prev: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }],
                  next: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }] 
                },
              ]
            },

            // State 2: write transaction has been committed
            {
              relations: [{ name: 'txn_iso', data: [[{ column: 'ival', value: val }]] }],
              transactions: [
                {
                  id: 2,
                  isDirty: false,
                  prev: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }],
                  next: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }]
                },
              ]
            }
          ];

          const operations = [c1.query('COMMIT'), c2.query('COMMIT'), db.selectInClient(c2)];
          let orderedOperations = [];
          let readIdx = txnOrder[2];
          for (let i = 0; i < txnOrder.length; i++) {
            orderedOperations[txnOrder[i]] = operations[i];
          }

          const results = await Promise.allSettled(orderedOperations);
          const modelResults = model.select(2, 'txn_iso');
          const read = results[readIdx];

          if (read.status === 'fulfilled') {
            // Check that DB state matches ANY model state
            expect(modelResults).toContainEqual(read.value);
          } else {
            fail('Read failed');
          }
      }).afterEach(async () => {
        await db.update(initialVal);

        c1.release();
        c2.release();

        await db.pool.end();
      }),
      { endOnFailure: true, numRuns: 100}
    )
  });
});
```

The race condition is explicitly modeled here in how we initialize `model.states.` Zooming in, the second state shows the state of the world after the write transaction has been committed: This manifests as the new written value (`val`) appearing in the committed `relations` state, and there only being one open transaction which hasn't modified any data:

```
{
  relations: [{ name: 'txn_iso', data: [[{ column: 'ival', value: val }]] }],
  transactions: [
    {
      id: 2,
      isDirty: false,
      prev: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }],
      next: [{ name: 'txn_iso', data: [[{ column: 'ival', value: initialVal }]] }]
    },
  ]
}
```

The other state has both transactions open, and the new value has not yet been written. Running this test passes against the test PG instance. We've accurately modeled the nondeterminism.

This is great, but doesn't help us in our application tests. To do that, we need to pick which value is correct. Because we know that `select` returns one result set for each nondeterministic initial state its configured with, we can accept a prophecy variable that picks a single one:

```
class DBModelProphecy {
    modelNondet: DBModelNondet = new DBModelNondet();

    select(txnId: number, relation: string, initialStateProphecy: number): Tuple[] {
        return this.modelNondet.select(txnId, relation)[initialStateProphecy];
    }
}
```

This allows a test to use the nondeterministic model in deterministic "mode," which will make sure that the application either handles both cases correctly, or leads to an implementation change. 

# In Closing

Nondeterminism has been a major thorn in my side when writing model-based tests for real applications. I think prophecy variables as presented here provide a clear pattern for dealing with it. There's a lot more to build out to have a production-grade model of a database like Postgres, but it's encouraging to see that the idea does work in principle. It's also really nice that the same technique can be applied to testing timeouts all the way to testing transaction isolation levels.

This all started from talking about the difficulty of property-based testing nondeterministic dependencies on [lobste.rs](https://lobste.rs) with Stevan, the author of [The sad state of propery-based testing libraries](https://stevana.github.io/the_sad_state_of_property-based_testing_libraries.html). I appreciate their views on the topic, you should read that post as well.
