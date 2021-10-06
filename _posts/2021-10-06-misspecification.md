---
layout: post
title: 'Misspecification: The Blind Spot of Formal Verification'
tags: specification
author: Alex Weisberger
---

As people, we like to be right, and we also want to avoid the effort of _proving_ that we're right. So we often resort to logical fallacies to take shortcuts and strong-arm people into believing us. One such logical fallacy is an ["appeal to authority"](https://en.wikipedia.org/wiki/Argument_from_authority) - you simply reference someone or thing that is considered to be an expert, and voilá - now you are right!

The reason it's a logical fallacy is that even smart people make mistakes. Or, even more importantly, smart people can have ill-intent - what better way to use social capital than to convince your followers to buy your new book and pay for your next vacation? That's why papers should be peer-reviewed. That's why we reproduce empirical experiments. And that's why we should always have healthy skepticism and evaluate an argument for ourselves.

Formal verification is often presented as an appeal to authority. This progam was _formally verified_, so please stop asking me if there are any bugs! Well, there are simply no silver bullets out there, and formal verification is certainly not one of them because of a very serious blind spot: the possibility of misspecification.


# Specification and Misspecification

Formal verification implicitly means "verification against a specification," and the difficulty in creating this specification is often unmentioned and overlooked. What if we simply didn't specify the right thing? Computer programs, especially of any practical size, are inherently gigantic discrete structures. Describing all of the subtleties of their behavior in a manageable way is Sisyphean - forget one hyper-specific semantic fact, and your description is incorrect, but it can be so subtle that it's not even noticed until an equally hyper-specific scenario presents itself during real program usage. 

Misspecification is the omission or misstatement of an important behavior or property such that a program can be verified to fully meet its spec, but the spec permits undesirable behavior. As said by Donald Knuth: 

> "Beware of bugs in the above code; I have only proved it correct, not tried it."

It is simply something we have to acknowledge about the end goal of testing and verification: we can only verify against our understanding of what the code _should_ do.

We will look at a more realistic example next, but let's first consider a more illustrative one. A very commonly cited example of misspecification is for a `sort` function:

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

Of course the last statement about the permutation is obvious after you see it, and of course it's impled when we said "return an array of numbers in sorted order." But "formal" in formal methods isn't talking about a dress code, it's referring to the fact that statements must be precise and complete. One misstatement, or in this case, an _understatement_, and unsatisfactory program behavior will be reported as "verified."

# Specifying and Misspecifying Relational Queries

Here's a more realistic example since I think sort functions are silly to analyze. 

Consider a CRM (customer relationship management) application, specifically in the context of a sales pipeline. The point is to store information related to sales prospects as they move through the pipeline. Let's say, you are a really big sales organization, and your company may have done deals with the same companies that you're talking to, only outside of your area and office. Let's say you work in the NYC office and you have a lead, and you have no idea that your Tokyo office has done business with this customer in their region. Tokyo might have some useful information about how the deal went through - maybe the CEO likes golf, or knitting, or synchronized swimming. 

When this scenario is detected, we want our CRM to notify users of this connection so that they could reach out and potentially close their deals faster. We also distinguish between "early" and "late" stage deals, because we'd only want to know about deals that actually have some legs to them, not just every prospect that reached out for a brief phone call or free lunch.

Stated informally, the specification is something along the lines of:

* A Connection exists with a Deal if another Late Stage Deal with the same customer exists

Here's a formal specification of this behavior:

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

This is written in [Alloy](https://alloy.readthedocs.io/en/latest/intro.html),  which lends itself very nicely to modeling relational data models. I won't be doing an Alloy tutorial here, but this is the gist. This spec defines the data model of the app (`Customer`, `Stage`, and `Deal`), along with the logic for the `connectionExists` query. The logic of `connectionExists` can be read as: "A connection exists for a `Deal` `d` if there exists a previous `Deal`, they both have the same `Customer`, and the previous `Deal` was late stage. We could implement this with the following code:

~~~
const alasql = require("alasql");

type Stage = "early" | "late";
type Customer = "c1" | "c2";

type Deal = {
    id: number,
    customer: Customer,
    stage: Stage,
}

function ConnectionExists(d: Deal, db): boolean {
    const connectedDeals: Deal[] = db.exec(
        "SELECT * FROM deals WHERE customer = ? and stage = 'late'",
        [d.customer, d.id],
    );

    return connectedDeals.length > 0;
}

function CreateDeal(deal: Deal, db): Deal {
    db.exec("INSERT INTO deals (?, ? ,?)", [deal.id, deal.customer, deal.stage]);

    return deal;
}
~~~
{: .language-typescript}

[`alasql`](https://github.com/agershun/alasql) is an in-memory SQL database that, among other things, makes examples like these easy to write. If we were to play around with this for a bit, we would notice a bug. But it's not an implementation bug - it's a _design_ bug, a bug in our actual algorithm for implementing the requirements. Consider the following test case:

~~~
function initDatabase() {
    let database = new alasql.Database();
    database.exec(
        "CREATE TABLE deals 
            (id int, customer varchar(128), stage varchar(128))"
    )

    return database;
}

function testOnlyNewDealLateStage() {
    let db = initDatabase();

    const newDeal = CreateDeal({ id: 1, customer: "c2", stage: "late"}, db);

    const connectionExists = ConnectionExists(newDeal, db);

    return connectionExists == false;
}
~~~
{: .language-typescript}

Here, we only create one late stage deal, and our logic reports that a connection exists for it. Remember - the point of a connection is to alert someone when there is a _previously existing_ deal with their new customer. That implies that more than one Deal must exist for `ConnectionExists` to ever return true.

Our implementation was perfectly fine, but our behavior was misspecified. 

Here's the fix, first in the spec:

~~~
pred connectionExists(d: Deal) {
  let ExistingDeals = Deal - d |
    some prevDeal: ExistingDeals | 
      d.customer = prevDeal.customer and prevDeal.stage in Late
}
~~~

Instead of querying for the connected deals in the set of all Deals (which `Deal` represents), we query all Deals other than the one whose connections we're looking for: `ExistingDeals = Deal - d`. The new implementation would be:

~~~
function ConnectionExists(d: Deal, db: any): boolean {
    const connectedDeals: Deal[] = db.exec(
        "SELECT * FROM deals WHERE customer = ? and stage = 'late' and id != d.id",
        [d.customer, d.id],
    );

    return connectedDeals.length > 0;
}
~~~
{: .language-typescript}

What we witnessed here was a misspecification. If we look back at the informal description of the feature, notice how it says "...if another Deal." In retrospect it's pretty clear that we should subtract the subject Deal from the rest of the existing Deals in the system when looking for connections. But that subtle fact was not captured in our first version of the specification, because formally capturing subtlety is hard! There is a quote from Dick Guindon:

> Writing is nature’s way of letting you know how sloppy your thinking is.

To which [Leslie Lamport adds](https://lamport.azurewebsites.net/tla/book-02-08-08.pdf):

>  Mathematics is nature’s way of letting you know how sloppy your writing is.

In this case, it wasn't that we didn't understand the gist of the requirements, but that a subtle aspect of them was lost in translation from the informal to the formal. The nature of our brains is to muddle details together and to arrive at conclusions based on fuzzy logic. Formal specifications are not fuzzy, nor can they infer what we mean, so they must be precise, literal, and complete.

We also actually understood the desired requirements here, what if we don't even have a firm grasp on that? The converse of this example is also possible, where we perfectly specify behavior that does not meet the user's needs.

Misspecification is a tricky problem - do we have any mirrors to help us with this blind spot?

# The Weakest Link Need Not Break the Chain

Knowing about a weakness does not mean that all is lost though. In fact, it strengthens our practice of verification because we can acknowledge that the specification is our linchpin and compensate. If a small misspecification can lead to total system instability, then we had better focus on validating our specs. 

A blind spot is only blind if we can't see it.

I love how [Andrew Helwer puts it](https://ahelwer.ca/post/2018-02-12-formal-verification/), referring to a verified system as a "chain of truth" that "is fundamentally without an anchor." There is no watcher watching the watchers here, no verification that can be performed on the spec itself. How could an algorithm tell us that we're saying what we want to say? There are tools here though to help with this, taking advantage of the fact that a specification is often much higher level, more abstract, and more semantically defined than an implementation. For example, we can check a specification for properties, which are much more powerful than test cases because properties operate on the entire set of all program behaviors, rather than the few specific code paths that are exercised with tests.

Consider the following proposed property of our spec:

~~~
pred connectionExists(d: Deal, Deals: set Deal) {
  let ExistingDeals = Deals - d |
    some prevDeal: ExistingDeals |
      d.customer = prevDeal.customer and prevDeal.stage in Late
}

assert oppositeStagesRemainConnected {
  all d: Deal, d': Deal, d'': Deal |
    disjoint[d, d', d''] and
    d.customer = d'.customer and d.customer = d''.customer and
    d'.stage != d.stage implies 
      connectionExists[d, Deal - d'] implies connectionExists[d', Deal - d]
}
~~~

This says approximately: "For all combinations of 3 different Deals with the same Customer, if 2 of the Deals have opposite stages and one of those has a connection, then so does the other." To express this property, we modify `connectionExists` to take in the set of Deals to check a connection within. This isn't an obvious property by any means[^fn1], but it does arise after thinking about the general reason behind our previous design bug. The bug occurred because we improperly reported a connection only for a Late Stage Deal, so it makes sense to come up with a property that relates Deals with different Stages.

Using properties in this way is much, much more robust than test cases, because properties are general. For example, here's the test case we wrote after we encountered the previous bug: 

~~~
function testOnlyNewDealLateStage() {
    let db = initDatabase();

    const newDeal = CreateDeal({ id: 1, customer: "c2", stage: "late"}, db);

    const connectionExists = ConnectionExists(newDeal, db);

    return connectionExists == false;
}
~~~
{: .language-typescript}

This test case transcribes the literal scenario where we encountered the bug, so the focus is (as is usual with example-based testing) on a specific scenario. We might have tried to change the implementation to this at first:

~~~
pred connectionExists(d: Deal, Deals: set Deal) {
  #{prevDeal: Deals | d.customer = prevDeal.customer and prevDeal.stage in Late } > 1
}
~~~

Instead of checking for the existence of a single Deal, we check for more than one Deal. We know this isn't correct logic now, but it's not always so obvious in the moment, and it's a common programming reflex to think we have an off-by-one error and just increase the count. This test case does not fail for this new logic though! That's a really common problem with test suites - even with tons and tons of test cases, they don't actually get at the essence of the requirements. We can look at a test suite as providing an implicit specification, and a missing test case is equivalent to a misspecification.

When checking the property, however, Alloy can report a counterexample by generating all combinations of input data, up to a configurable bound at least. It quickly finds this counterexample:

<div style="display: flex">
  <img src="/assets/ConnectionAlloyCounterexample.png" style=""/> 
</div>

It generated 2 Deals with different Stages that should have connections but don't because of our faulty implementation, and it did it without us writing any explicit test cases or coming up with interesting data states. 

# Wrapping Up

Here's the full specification plus property check at this point:

~~~
sig Customer {}

abstract sig Stage {}
one sig Early extends Stage {}
one sig Late extends Stage {}

sig Deal {
  customer: Customer,
  stage: Stage
}

pred connectionExists(d: Deal, Deals: set Deal) {
  let ExistingDeals = Deals - d |
    some prevDeal: ExistingDeals |
      d.customer = prevDeal.customer and prevDeal.stage in Late
}

assert oppositeStageDealsRemainConnected {
  all d: Deal, d': Deal, d'': Deal | 
    disjoint[d, d', d''] and
    d.customer = d'.customer and d.customer = d''.customer and
    d'.stage != d.stage implies 
      connectionExists[d, Deal - d'] implies connectionExists[d', Deal - d]
}
 
check oppositeStageDealsRemainConnected for 5
~~~

It's not like this took thousands of lines of test setup code and hundreds of minutes of test time in CI. Specifications plus properties plus model checking have a great cost-to-benefit ratio, with the main benefit being that we get more confidence that we're avoiding a misspecification as we check properties that we feel accurately describe our problem.

It also does this in 26 milliseconds on my machine, through the dark artistry of SAT solvers.

This is why, if you ask me, individual test cases should become the assembly language of testing and verification. There's nothing stopping us from writing targeted test cases for specific, important scenarios, but it is simply way too weak and costly to be our primary verification technique.  

Lastly, I just want to stress how many best practices do not address the misspecification here:

* Measuring code coverage would not alert you of this, it's easy to get 100% test coverage, especially for queries where all of the logic is within the query itself
* Formally proving ahead of time does not prevent this - again, our specification itself was incorrect, we would have ended up with a formally verified program that a user would instantly distrust after hitting this scenario
* Using a repository pattern to remove the database from unit tests does nothing to test the actual query logic, which as was shown here can be subtly surprising.

There is simply no way to deal with this ahead of time, which is the frustrating thing about it, and why we especially need to keep it in the back of our minds. Overall, misspecification is always a risk, but it's not a death sentence. By validating specifications with properties and model checking, we can retain many of the benefits while minimizing the risk. The loop continues, because there is no way to prove our properties are sufficient, but we can at least focus on a small set of important properties instead of endless amounts of individual test cases.

<hr>

[^fn1]: It is a property with a [metamorphic relation](https://www.hillelwayne.com/post/metamorphic-testing/) though, which I have been finding are easier to dream up for more "business logic" type behavior