---
layout: post
title: 'Does Your Test Suite Account For Weak Transaction Isolation?'
tags: testing databases
author: Alex Weisberger
---

Transaction isolation is the kind of thing that you learn about and it fills you with fear. Specifically, there are _weak_ transaction isolation levels which allow some fairly unexpected behavior. Tools like Jepsen are used to test the general isolation guarantees of databases, but it's pretty uncommon to check the application layer for issues related to isolation anomalies. These anomalies can impact actual domain logic, so it's important to understand them as well as how we can test them.


# What is Weak Transaction Isolation?

Transaction isolation means that concurrent transactions against a database will be independent of one another. It's the "I" in ACID. Unfortunately, "independence" in this context is a spectrum, and there are actually different isolation levels that are supported, each with subtly different behavior.

Here's a quick example script which makes concurrent queries against a database (Postgres):

```sql
create table txn_iso (ival int);
insert into txn_iso (ival) values(1);
```

```typescript
import { Pool, Transaction } from 'https://deno.land/x/postgres/mod.ts';

const pool = new Pool({
  user: 'postgres',
  hostname: 'localhost',
  database: 'postgres',
  port: 5433,
  password: 'test1234',
}, 10);

async function runQuery(
  txn: Transaction,
  query: string,
  args: (string | number)[],
  beforeMsg: string,
  afterMsg: (result: any) => string
) {
  console.log(beforeMsg);
  const result = await txn.queryObject(query, args);
  console.log(afterMsg(result));
}

async function readTransaction() {
  const query = 'select ival from txn_iso';
  const printResult = (result: any) => `Read result: ${result.rows[0].ival}`;

  const client = await pool.connect();
  const txn = client.createTransaction();

  await txn.begin();

  await runQuery(txn, query, [], 'Executing first read...',  printResult);

  // Wait for concurrent write to occur
  await new Promise(resolve => setTimeout(resolve, 2000));

  await runQuery(txn, query, [], 'Executing second read...', printResult);

  await txn.commit();

  await client.release();
}

async function writeTransaction() {
  await new Promise(resolve => setTimeout(resolve, 1000));
  const client = await pool.connect();
  const txn = client.createTransaction();

  await txn.begin();

  const updateVal = Math.floor(Math.random() * 1000);
  const updateMsgBefore = `Updating ival to ${updateVal}...`;
  const query = 'update txn_iso set ival = $1';
  await runQuery(txn, query, [updateVal], updateMsgBefore, () => 'ival updated');

  await txn.commit();

  await client.release();
}

await Promise.allSettled([readTransaction(), writeTransaction()]);
```

This script executes two transactions concurrently: one that reads the `txn_iso.ival` column two different times, and another which modifies the value of that column. There's some sleeps sprinkled in so that the second read occurs after the write. The question is: do both reads return the same value?

In Postgres, with the default transaction isolation level set, the answer is surprisingly no. This is an example output of running the script:

```plaintext
Executing first read...
Read result: 839
Updating ival to 79...
ival updated
Executing second read...
Read result: 79
```

The first read will return the value of the column at the time that the read transaction begins, but the second read will return the value that was updated by the concurrent write transaction. That's because the default level is Read Committed, which allows non-repeatable reads. A non-repeatable read means that in the span of the same transaction, queries to the same column may return different results! This isn't unique to Postgres either - Read Committed is the default isolation level in Oracle and SQL Server as well[^fn1].

This is surprising to a lot of people, and rightfully so, since it seems to go against the very definition of what a transaction is. But that's because Read Committed is a _weak_ transaction isolation level. Weak isolation means that transactions aren't truly independent from one another, and the effects of one concurrent transaction can be seen in another. There's 4 isolation levels defined by the ANSI SQL standard[^fn2]. All but Serializable, which is the strictest, are weak and allow some kind of interference between transactions.

Hopefully it's clear why this is an issue. If you have an important column value, say a user's account balance, you might query multiple different values in the same transaction which will surely result in a domain logic bug. Will our test suites catch such bugs? That depends how we set up the tests.

# Simulating Concurrent Connections

The difficulty with coming up with tests that expose transaction isolation anomalies is that the test has to simulate multiple concurrent connections. Test cases almost always have the implicit assumption that they're being executed by a single user, and isolation anomalies don't show up in that scenario.

As an example, here's some oversimplified code for making outbound transfers from an account with overdraft protection:

```typescript
interface BalanceRepository {
  getBalance(txn: Transaction): Promise<number>;
  updateBalance(txn: Transaction, amount: number): Promise<void>;
}

async function checkOverdraftProtection(txn: Transaction, balanceRepo: BalanceRepository, amount: number) {
  const balance =  await balanceRepo.getBalance(txn);
  if (balance >= amount) {
    return;
  }

  balanceRepo.updateBalance(txn, balance + 100);
}

async function applyFundTransfer(txn: Transaction, balanceRepo: BalanceRepository, amount: number) {
  const balance = await balanceRepo.getBalance(txn);
  if (balance < amount) {
    console.error("Insufficient funds");
    return;
  }

  await balanceRepo.updateBalance(txn, balance - amount);
}

async function transferFunds(balanceRepo: BalanceRepository, amount: number) {
  const client = await pool.connect();
  const txn = client.createTransaction();

  await txn.begin();

  await checkOverdraftProtection(txn, balanceRepo, amount);
  await applyFundTransfer(txn, balanceRepo, amount);
  
  await txn.commit();

  await client.release();
}

const protectedBalanceRepo = {
  balance: 90,
  async getBalance(txn: Transaction) {
    return this.balance;
  },
  async updateBalance(txn: Transaction, amount: number) {
    this.balance = amount;
  }
}

await transferFunds(protectedBalanceRepo, 100);
console.assert(protectedBalanceRepo.balance === 90);
```

The main logic that we want to test is that overdraft protection adds additional funds when there's not enough to cover a transfer, and that the final balance is correct. To test this, we're placing all queries behind a `BalanceRepository` interface and creating a `protectedBalanceRepo` which starts out with insufficient funds but updates the balance based on overdraft protection.

This is the operation from the perspective of a single user and thus a single DB connection, so the insufficient funds error won't get hit. As we saw with the Read Committed example though, another concurrent transaction can affect a value that's read multiple times. So one way to simulate a concurrent transaction is to simply ignore the overdraft protection and specify a different balance result directly.

```typescript
const concurrentWriteRepo = {
  currBalance: 0,
  balances: [100, 90],
  async getBalance(txn: Transaction) {
    return this.balances[this.currBalance++];
  },
  async updateBalance(txn: Transaction, amount: number) {
  }
}

...

await transferFunds(concurrentWriteRepo, 100);
```

This test double sets up two different balance results: it'll first return 100, which will bypass overdraft protection, but the next balance check will return 90 which will result in an insufficient funds error. One way this would be possible in real life is if multiple people have access to the same account and initiate a transfer in close proximity to one another.

There's a simple fix for this failure: just don't read the balance multiple times, and instead pass in the sampled balance to any function that needs it:

```typescript
async function transferFunds(balanceRepo: BalanceRepository, amount: number) {
  const client = await pool.connect();
  const txn = client.createTransaction();

  await txn.begin();

  const balance = await balanceRepo.getBalance(txn);
  const protectedBalance = await checkOverdraftProtection(txn, balance, balanceRepo, amount);
  await applyFundTransfer(txn, protectedBalance, balanceRepo, amount);
  
  await txn.commit();

  await client.release();
}
```

Now the logic of `checkOverdraftProtection` and `applyFundTransfer` can get changed to use a balance value instead of querying it. This also means that `checkOverdraftProtection` has to return the balance after protection is applied since `applyFundTransfer` used to get this value with the second balance query, and using the pre-protection balance will result in an insufficient funds error.

This solves the repeatable read anomaly by avoiding multiple reads, but there's still a major issue: there's a race condition between multiple concurrent transactions that can result in an incorrect balance.

# Race Conditions and Serializability

To show the error we can execute two fund transfers concurrently against the actual DB, and we can introduce a write delay so that we can control which one writes last (we'd see errors even without this, but this reduces the non-determinism):

```sql
create table accounts (balance int);
insert into accounts (balance) values (100);
```

```typescript
async function transferFunds(balanceRepo: BalanceRepository, amount: number, writeDelay?: number) {
  const client = await pool.connect();
  const txn = client.createTransaction();

  await txn.begin();

  const balance = await balanceRepo.getBalance(txn);

  if (writeDelay) {
    await new Promise(resolve => setTimeout(resolve, writeDelay));
  }

  const protectedBalance = await checkOverdraftProtection(txn, balance, balanceRepo, amount);
  await applyFundTransfer(txn, protectedBalance, balanceRepo, amount);
  
  await txn.commit();

  await client.release();
}

const postgresBalanceRepo = {
  async getBalance(txn: Transaction): Promise<number> {
    const result = await txn.queryObject('select balance from accounts');
    return result.rows[0].balance;
  },
  async updateBalance(txn: Transaction, amount: number) {
    await txn.queryObject('update accounts set balance = $1', [amount]);
  }
}

async function runInTransaction<T>(f: (txn: Transaction) => Promise<T>) {
  const conn = await pool.connect()
  const txn = conn.createTransaction()
  await txn.begin();

  const result = await f(txn);

  await txn.commit();
  await conn.release();

  return result
}

// Setup
await runInTransaction((txn) => {
  return postgresBalanceRepo.updateBalance(txn, 100);
});

// Run two concurrent fund transfers
await Promise.allSettled([transferFunds(postgresBalanceRepo, 80, 2000), transferFunds(postgresBalanceRepo, 60)]);

const balance = await runInTransaction((txn) => {
  return postgresBalanceRepo.getBalance(txn)
});

console.assert(balance === 60);
```

When this is run, the transfers will see the same initial balance (100), but the one with the write delay will overwrite the balance set in the other one. This also means that neither transfer will trigger overdraft protection, there will be no insufficient funds error, and the resulting balance will be an incorrect value of 20.

This is a _serialization anomaly_. The Postgres docs define this as: 

> The result of successfully committing a group of transactions is inconsistent with all possible orderings of running those transactions one at a time.

There are only two possible orderings of the two fund transfers here:

1. Transfer 80, then transfer 60
2. Transfer 60, then transfer 80

Since the starting balance is 100, both of these cases should trigger overdraft protection on the second transfer, and the resulting balance in both cases should be 60 (100 + 100 - 80 - 60). Race conditions can exist when transactions don't adhere to serializability, and that's what's going on here - two fund transfers are initiated, but only one is accounted for because of a concurrent race. This is known as the "lost update" problem.

There's a few different ways to fix this, but the simplest is to lock the row for the duration of the transaction with `FOR UPDATE`:

```typescript
const postgresBalanceRepo = {
  async getBalance(txn: Transaction): Promise<number> {
    const result = await txn.queryObject('select balance from accounts FOR UPDATE');
    return result.rows[0].balance;
  },
  ...
}
```

Again from the Postgres docs:

> FOR UPDATE causes the rows retrieved by the SELECT statement to be locked as though for update. This prevents them from being locked, modified or deleted by other transactions until the current transaction ends.

This means that each transaction will grab a lock on the `accounts` row and that will block all other transactions from modifying that row until it's complete, i.e. the transactions will execute in a serializable fashion. It's worth noting that this is now slower. Without the lock the transactions could truly operate concurrently, but now they have to wait in contention over balance updates to the same account. This is necessary for correct behavior, but it's worth understanding the tradeoff.

Also of note, test doubles alone won't help with this bug because the fix is in the real Postgres repository implementation. Test doubles are useful for testing application code independent of the database in many cases, but transaction isolation is a case where the different levels are so subtly different that it's simpler to test against the real thing.

----

Transaction isolation has a major impact on an application, both in terms of performance as well as its influence on domain logic. It's important to integration test against the real database to make sure that a weak transaction isolation level isn't the cause of concurrency bugs. To expose such bugs, we have to execute at least two concurrent transactions in a test case. Unfortunately this can require some amount of time-based coordination which is never ideal, but is often necessary when tools like databases have opaque non-deterministic behavior that's out of our control.

Still, it is something we can and should test for at the application level.

<hr>

[^fn1]: Interestingly, MySQL's default isolation level is Repeatable Read, which avoids the bug presented here. Still, it's very uncommon for any DB to have a default level of Serializable, so most databases are operating with weak isolation. A notable exception is [FoundationDB](https://www.google.com/search?q=foundationdb&rlz=1C5GCEM_enUS1058US1060&oq=foundationdb&gs_lcrp=EgZjaHJvbWUqBggAEEUYOzIGCAAQRRg7MgYIARBFGDkyBggCEEUYOzIGCAMQRRg7MgYIBBBFGDwyBggFEEUYPDIGCAYQRRg8MgYIBxBFGDzSAQc2OTlqMGo3qAIAsAIA&sourceid=chrome&ie=UTF-8), which does default to Serializable.

[^fn2]: Postgres actually only implements 3 out of 4, because Read Uncommitted conflicts with Postgres' MVCC implementation. For more detail on isolation levels as Postgres implements them, see: https://www.postgresql.org/docs/current/transaction-iso.html