---
layout: post
title: 'Misspecification: The Blind Spot of Formal Verification'
tags: formal_verification
author: Alex Weisberger
---

As people, we like to be right, and we also want to avoid the effort of _proving_ that we're right. So we often resort to logical fallacies to take shortcuts and strong-arm people into believing us. One such logical fallacy is an ["appeal to authority"](https://en.wikipedia.org/wiki/Argument_from_authority) - you simply reference someone or thing that is considered to be an expert, and voilá - now you are right!

The reason it's a logical fallacy is that even smart people make mistakes. Or, even more importantly, smart people can have ill-intent - what better way to use social capital than to convince your followers to buy your new book and pay for your next vacation? That's why papers should be peer-reviewed. That's why we reproduce empirical experiments. And that's why we should always have healthy skepticism and evaluate an argument for ourselves.

Formal verification is often presented as an appeal to authority. This progam was _formally verified_, so please stop asking me if there are any bugs! Well, there are simply no silver bullets out there, and formal verification is certainly not one of them because of a very serious blind spot: the possibility of misspecification.


# Specification and Misspecification

Formal verification implicitly means "verification against a specification," and the difficulty in creating this specification is often overlooked. What if we simply didn't specify the right thing? I say this all the time: computer programs are friggin complicated, for lack of a better term. Describing all of the subtleties of behavior in a manageable way is Sisyphean - forget one hyper-specific semantic fact, and your description is incorrect, but it can be so subtle that it's not even noticed until an equally hyper-specific scenario presents itself during real program usage. 

Misspecification is the omission or misstatement of an important behavior or property such that a program can be verified to fully meet its spec, but the spec permits undesirable behavior. As said by Donald Knuth: 

> "Beware of bugs in the above code; I have only proved it correct, not tried it."

But it is simply something we have to acknowledge about the end goal of testing and verification: we can only verify against our knowledge of what the code _should_ do.

We will look at a more realistic example, but to cut to the chase a little quicker, let's first consider the common example of the specification of a `sort` function:

~~~
function sort(array: number[]): number[] {
  // ... 
}
~~~
{: .language-typescript}

`sort` should:
- accept an array of numbers
- return an array of numbers in sorted order

Easy right?!

Well, what if `sort([3,2,1])` returns `[1,3]`? Is that in conflict with anything about this specification? It is not, and we need to strengthen the spec in order to prevent this:

`sort` should:
- accept an array of numbers
- return an array of numbers in sorted order
- **and the returned array should be a permutation of the input array**

Of course the last statement about the permutation is obvious after you see it, and of course it's impled when we said "return an array of numbers in sorted order." But "formal" in formal specification and verification isn't talking about a dress code, it's referring to the fact that statements must be precise and complete. One misstatement, or in this case, an _underspecification_, and unsatisfactory program behavior will be reported as "verified."

# Misspecified Relational Queries

Here's a more realistic example since I think sort functions are silly to analyze. 

Ok, so consider a CRM (customer relationship management) application. Specifically in the context of a sales pipeline. The point is to store information related to sales prospects as they move through the pipeline. Well, you are a really big sales organization, and your company may have done deals with other big companies before, but outside of your area. Let's say you work in the NYC office and you have a lead, and you have no idea that your Tokyo office has done business with this customer in their region. Tokyo might have some useful information about how the deal went through, so shouldn't our CRM notifiy you of that connection so that you could reach out and potentially close your deal faster?

Since people are generally not used to program specification, let's start backwards and look at the implementation first: 

~~~
const alasql = require("alasql");

function initDatabase() {
    let database = new alasql.Database();
    database.exec("CREATE TABLE deals (id int, customer varchar(128), stage varchar(128))")

    return database;
}

type Stage = "early" | "late";
type Customer = "c1" | "c2";

type Deal = {
    id: number,
    customer: Customer,
    stage: Stage,
}

function CreateDeal(deal: Deal, db: any) {
    db.exec("INSERT INTO deals (?, ? ,?)", [deal.id, deal.customer, deal.stage]);

    return deal;
}

function ConnectionExists(d: Deal, db: any): boolean {
    const connectedDeals: Deal[] = db.exec(
        "SELECT * FROM deals WHERE customer = ? and stage = 'late'",
        [d.customer],
    );

    return connectedDeals.length > 0;
}

const db = initDatabase();

const existingDeal = CreateDeal({ id: 1, customer: "c1", stage: "late" }, db);
const newDeal = CreateDeal({ id: 2, customer: "c1", stage: "late"}, db);

ConnectionExists(newDeal, db);

// true - there was an existing late stage deal 
~~~
{: .language-typescript}

For simplicity, we're using [`alasql`](https://github.com/agershun/alasql), an in-memory SQL database implementation, because there's a subtle bug here, and it's in the SQL queries.

Hopefully it's clear what the code does based on the description of the feature. We model Deals, Customers, and Stages. We provide a way to create Deals in the database. We then implement `ConnectionExists` which performs the logic for our definition of a "connection" with the customer by querying the database for deals of interest - so called "connected Deals." Let's then start by relaxing the definition of formal verification a bit, and use what is almost certainly the most common form of it: automated testing. Automated testing is an approximation of proof by exhaustion / case analysis, where we attempt to prove each logical state true, one by one. 

Let's start with these cases:

~~~
function testConnectionDoesntExist() {
    let db = initDatabase();

    const newDeal = CreateDeal({ tenant: "t2", stage: "early"}, db);
    
    const connectionExists = ConnectionExists(newDeal, db);

    return connectionExists == false;
}

function testConnectionDoesExist() {
    let db = initDatabase();

    CreateDeal({ tenant: "t2", stage: "late"}, db)
    const newDeal = CreateDeal({ tenant: "t2", stage: "late"}, db);

    const connectionExists = ConnectionExists(newDeal, db);

    return connectionExists == true;
}
~~~
{: .language-typescript}

`ConnectionExists` returns a bool, so it seems sensible to check cases where it returns both true and false. But we notice a problem when playing around with the application in production: if we have no existing Deals with a Customer, and we create a late stage Deal, `ConnectionExists` returns `true`. We only want to notify of a connection if there was already an existing Deal before creating a new one, so this is undesirable behavior. If we view our test cases as hinting at the program specification, that specification is underspecified so far - it simply fails to address this case. And since we never test every possible case, misspecification often presents itself as missing test cases with missing test cases. 

We strengthen the specification by adding another case:

~~~
function testOnlyNewDealLateStage() {
    let db = initDatabase();

    const newDeal = CreateDeal({ id: 1, customer: "c2", stage: "late"}, db);

    const connectionExists = ConnectionExists(newDeal, db);

    return connectionExists == false;
}
~~~
{: .language-typescript}

How should we make it pass? Well, our logic checks if there's at least one Connected Deal (`connectedDeals.length > 0`), but here we only have one Deal, so we might be tempted to just check for the presence of more than one Deal:

~~~
function ConnectionExists(d: Deal, db: any): boolean {
    const connectedDeals: Deal[] = db.exec(
        "SELECT * FROM deals WHERE customer = ? and stage = 'late'",
        [d.customer],
    );

    // ** Updated logic **
    return connectedDeals.length > 1;
}
~~~
{: .language-typescript}

Now all of the tests pass. but we later find out again that we have still underspecified the desired behavior. Consider this case:

~~~
function testNewEarlyStageDeal() {
    let db = initDatabase();

    CreateDeal({ id: 1, customer: "c2", stage: "late"}, db)
    const newDeal = CreateDeal({ id: 2, customer: "c2", stage: "early"}, db);

    const connectionExists = ConnectionExists(newDeal, db);

    return connectionExists == true;
}
~~~
{: .language-typescript}

This should pass, but it does not, because we're expecting two late-stage Deals now. In this scenario, there is only one. To wrap up, here is the working implementation of `ConnectionExists`, reflecting the fact that what we really want is to consider only Deals _other_ than the newly created one when looking for existing connections:

~~~
function ConnectionExists(d: Deal, db: any): boolean {
    // Query for Deal other than the one we're looking for a connection on
    const connectedDeals: Deal[] = db.exec(
        "SELECT * FROM deals WHERE customer = ? and stage = 'late' and id != ?",
        [d.customer, d.id],
    );

    // There only needs to be 1 other such Deal for a connection to exist.
    return connectedDeals.length > 0;
}
~~~
{: .language-typescript}

# From Test Cases to Specification

Test cases describe what the program should do, but only implicitly. A specification describes it explicitly. Here's a specification of this behavior:

~~~
sig Customer {}

abstract sig Stage {}
one sig Early extends Stage {}
one sig Late extends Stage {}

sig Deal {
  customer: Customer,
  stage: Stage
}

pred connectionExists(d: Deal) {
  some prevDeal: Deal | d.customer = prevDeal.customer and prevDeal.stage in Late
}
~~~

This is written in [Alloy](https://alloytools.org/), which most people probably don't know and I'm not going to do a tutorial in this post (Hillel Wayne has created [good documentation though](https://alloy.readthedocs.io/en/latest/language/signatures.html)). Alloy lends itself very nicely to modeling relational data models though, and here's the gist. This spec defines the data model of the app (`Customer`, `Stage`, and `Deal`), along with the logic for the `connectionExists` query. The spec logic can be read as: "A connection exists for a `Deal` `d` if there exists a previous `Deal`, they both have the same `Customer`, and the previous `Deal` was late stage.

When considering this spec, and the first bug that was noticed, I think this would be the most natural fix:

~~~
pred connectionExists(d: Deal) {
  let existingDeals = Deal - d |
    some prevDeal: existingDeals | d.customer = prevDeal.customer and prevDeal.stage in Late
}
~~~

Instead of querying all `Deals`, we limit the scope to `existingDeals` which subtracts the `Deal` that we're inquiring about its connections. More importantly, compare how we address the new knowledge that the newly created deal should be ignored when querying for connected deals. Here's how we add that knowledge to the "implicit spec" with another test case:

~~~
function testNewEarlyStageDeal() {
    let db = initDatabase();

    CreateDeal({ id: 1, customer: "c2", stage: "late"}, db)
    const newDeal = CreateDeal({ id: 2, customer: "c2", stage: "early"}, db);

    const connectionExists = ConnectionExists(newDeal, db);

    return connectionExists == true;
}
~~~
{: .language-typescript}

Nowhere does this test say anything about only consdering the non-new Deals, we just have a bunch of data and an assertion. The behavior is implicit. 

But with a formal spec, it is simply a modification of the spec:

One thing I want to call out is, this wasn't a big investment. Yea, you have to learn Alloy - a language and a corresponding tool. Or, you have to research and pick another specification tool, which are not known for their usability. I can't deny that. But, this spec is 14 lines of code. The creator of Alloy, Daniel Jackson, often preaches the value of "leightweight formal methods" for this reason. Check out a post by him and some colleages where they [model and check various properties about the web's Same Origin Policy](http://aosabook.org/en/500L/the-same-origin-policy.html).


Case analysis leads to an implicit specification, with the individual cases displaying specific behavior. Writing a formal specification obviously makes the specification explicit, but it is also a _general_ description of the program. Nothing about writing a formal spec takes away the risk of misspecification, but because it is both explicit and general, it can be a better tool for reasoning about and adapting to it.

With that, here's a specification of this behavior:

# Wrapping Up

I just want to stress how many best practices do not address this problem:

* Using a repository pattern to remove the database from unit tests does not catch this
* Measuring code coverage would not alert you of this
* Formally proving ahead of time does not prevent this

There is simply no way to deal with this ahead of time, which is the frustrating thing about it, and why we especially need to keep it in the back of our minds. I tried for a while to come up with a property that prevents this ahead of time, but I could never think of anything that didn't have extreme hindsight bias. If anyone sees anything, please reach out and let me know! 

Also, if you ask me, individual test cases should become the assembly language of testing and verification. There's nothing us from writing targeted test cases for specific, important scenarios, but it is simply way too weak and costly to be our primary verification technique. 

# Fire and Brimstone

So that's it. We have no hope. Entropy will take its place as the rightful ruler of the computer program universe, and we will slowly but surely devolve into bug-ridden chaos. We are doomed.

Eh, not really. It's like everything else. We just need to be conscious of it and take hefty phrases like "formal verification" with a grain of salt.

# Leftover

Example of division by 0 in proof of 1 + 1 = 2 (principle of explosion?)

Like the old South Park business plan:

Phase 3: Profit.

I think formal verification is often used as an appeal to authority. "This software is formally verified. Checkmate."

Well, like everything else, it's not that simple. The sel4 OS is formally verified, but they at least temper their results with reality: https://docs.sel4.systems/projects/sel4/frequently-asked-questions.html#does-sel4-have-zero-bugs.

Misspecification is the one error that cannot be tested for. To test for it, we would have to teach a computer how to read minds and / or understand the higher-level goal of an application. It's also the main flaw of formal specification fand verification, so it's important to understand.
