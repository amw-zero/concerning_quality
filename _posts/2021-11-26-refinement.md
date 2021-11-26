---
layout: post
title: 'Refinement: Formalizing the Simplicity Underneath Complex Programs'
tags: formal_verification refinement formal_specification
author: Alex Weisberger
---

"Real world" software is large, messy, and full of detail. A customer might just want to store and retrieve their data, but those simple requirements can get lost in the sea of programming language semantics, libraries, frameworks, databases, Internet protocols, serialization formats, performance optimizations, security hardening, auditability, monitorability, asynchronicity, etc., etc., ad infinitum. We should always try to simplify our stack, but practical computation is optimization to an extent - how would you like to use a logically correct application where each interaction takes 10 seconds to give feedback?

To really understand this difference between functional and non-functional requirements, let's look at the concept of _refinement_. Refinement is the fundamental concept behind behavior-preserving program transformation, and it allows us to separate abstraction from mplementation in formal and verifiable process.


# How Product Managers Think About Behavior

Let's first think about behavior at a high level. Remember - [quality does not exist in a vacuum]({% post_url 2020-12-19-why-quality %}), and paying customers care little about a verified system that doesn't do what they want. This is why a good product manager is part psychotherapist, first extracting the customer's mindset before jumping into solutioning. So given that their primary concern is what a human being wants out of a system, how do they talk and think about behavior?

Here's an example of something they wouldn't say:

> To meet our customers' requirements, we're going to need to start with a microservice architecture communicating with gRPC over HTTP. We know that won't be good enough, so we'll also introduce a fanout-on-write pipeline to populate precomputed data in Redis. Of course, they also require a single-page application, so we'll need an API gateway for a React app to call that proxies requests to the appropriate services. With this in place, the customer will be able to run their baking business on our app.

Here's an example of something they would say:

> Bakers are telling us that they keep burning their biscuits while they're on the phone taking people's orders. They want a self-service order platform so they can spend less time on the phone and more time baking. If their customers can place and track their own orders, the bakers could see their upcoming orders and prioritize their work with fewer phone calls. With this in place, they'll lower their percentage of burnt biscuits (PBB) and they'll have no problem signing up for our service contract.

PMs think and speak about things that happen in the physical world. In the bakery example, they'd speak of bakers, biscuits, customers, and orders. They'd speak about the process of customers placing orders and how the bakers view and fulfill them. PMs live in the _problem domain_ - the sphere of activity of a particular business, field, or anything that we want to model as a computer program.

Let's make this more concrete with some code. Here's a small subset of the bakery behavior at the level of abstraction of the problem domain:


{% highlight typescript %}
type Order = {
  customer: string,
  amount: number,
  sku: string,
  dueBy: Date,
}

class BakeryBusiness {
    orders: Order[] = []

    placeOrder(order: Order) {
        this.orders.push(order);
    }
}

let bakery = new BakeryBusiness();
bakery.placeOrder({
    customer: "Biscuit Buyer",
    amount: 10.00,
    sku: "b123",
    dueBy: new Date("July 8th, 2021"),
});
{% endhighlight %}

We have an `Order` type, a `BakeryBusiness` class which maintains the state of orders, and the `placeOrder` method which adds to the current state of `Orders`. There's no user interface, server, database, or anything like that, just some behavior modeled as data and operations on it. A customer placing an order in real life is modeled by instantiating a `BakeryBusiness` and calling the `placeOrder` method on it, as shown.

This simple abstract data type captures the activity of the problem domain, but could never be deployed as a real system.

# Refinement: the Opposite of Abstraction

At some point, we have to actually encode these activities as a deployable application though, and this is where the abstraction level changes. No longer are we only concerned with the abstract nouns and verbs of the problem domain, but we also have to worry about concrete technologies, user experiences, performance, and security. Here's where we need to think about things like relational databases, client-server architecture, and user authentication, etc.

Let's introduce a client-server architecture into our `BakeryBusiness` model:

{% highlight typescript %}
class BakeryBusinessWithServer {
    orders: Order[] = []

    placeOrder(order: Order) {
        const serializedOrder = JSON.stringify(order);
        this.server(serializedOrder);
    }

    server(data: string) {
        const order = JSON.parse(data);
        this.orders.push(order);
    }
}

let bakery = new BakeryBusinessWithServer();
bakery.placeOrder({
    customer: "Biscuit Buyer",
    amount: 10.00,
    sku: "b123",
    dueBy: new Date("July 8th, 2021"),
});
{% endhighlight %}

This new implementation does the same thing: model a customer placing an order to a bakery, but it does so by making a call to a server which performs the actual functionality. This is of course a simplified model of a server, but the basic idea is there: first, the `Order` is serialized then passed to the server. The server deserializes it back into an `Order` where it's then added to the system state.

When the same `placeOrder` call is made, the same result is achieved, but the behavior is carried out internally in a more detailed way than the previous version. We say that `BakeryBusinessWithServer` refines `BakeryBusiness` - it is less abstract.

In some ways, this is similar to refactoring, but refactoring is [generally concerned with improving the readability or understandability of a program](https://martinfowler.com/bliki/IsOptimizationRefactoring.html). Performance optimizations, for example, may or not be considered refactors, but they are definitely considered refinements. So refactoring and refinement exist along slightly different dimensions.

A big difference is how each determines whether or not the behavior is the same between the two program versions. With refactoring, this is done with tests. We can imagine a set of tests that were developed for `BakeryBusiness`, and if they pass for `BakeryBusinessWithServer`, then the refactoring is considered to preserve the behavior. As we know, tests don't actually catch all bugs though, and bugs can especially creep in if the new version is much more complex than the old. Imagine a bug in `JSON.parse` that only occurs when parsing an array containing the number 7 in a nested key, i.e. `{ nested: { key: [7] } }`. The abstract implementation may or may not have tests for this case, so the new implementation might introduce this bug while passing all of the existing tests (a classic example of the [underspecification that test suites provide]({% post_url 2021-10-06-misspecification %})).

Refinement, on the other hand, comes with a theory that's mathematically verifiable. The version with the bug in `JSON.parse` could not be considered a refinement of the abstract version because refinement is concerned with all program executions. Even still, the difference is mostly philosophical, as refactors can always be shown to be refinements. Relating the two is important, though, since most people have heard of refactoring, whereas refinement is generally only discussed in the verification community.

What I want to stress about refinement is that it is generally done because we _want_ to have an abstract specification of a program. This may sound odd, but consider the importance (and utility) of the product manager's view of the system (`BakeryBusiness`). It is smaller, simpler, and easier to make general statements about. It is also substantially easier to verify properties at this level of abstraction, in contrast to writing endless amounts of test cases at the implementation level. Isn't this view then completely demolished by the technical detail of the actual code? From that angle, it's not so strange to want to keep that view in tact somehow.

# Justifying a Refinement

Refinement is a whole field unto itself, with the main theory being laid out in the [refinement calculus](https://lara.epfl.ch/w/_media/sav08:backwright98refinementcalculus.pdf). It's way too deep to fully cover, but here is a taste of what it takes to prove that a program is a refinement of another.

There are many ways to prove refinement between two programs, but the simplest to understand is equality - if two programs result in the exact same value for all possible inputs, then one can be seen to refine the other. Let's call our more abstract method for placing orders `place_order`, and let's call our version that uses a server `place_order_http`. In Isabelle/HOL we would express equality of the two functions as a theorem:

{% highlight isabelle %}
theorem "place_order_http orders order = place_order orders order"
{% endhighlight %}

`orders` is the state of `Orders` in the system (corresponding to `bakery.orders` in the TS example), and `order` is the new `Order` being placed. The fact that their values aren't specified means this theorem must hold for all possible values in order for it to be true.

Let's first introduce the abstract implementation:

{% highlight isabelle %}
record order =
  amount :: nat

type_synonym orders = "order set"

fun place_order :: "orders ⇒ order ⇒ orders" where
"place_order os order = insert order os"
{% endhighlight %}

We introduce the `order` type as a record with just an `amount` field for simplicity, and we define the `place_order` function as simply inserting an `order` into the passed in state of all `orders`. Pretty simple.

Let's now introduce the version that calls to a server, serializing before the call and deserializing after. Note - we implement the serialization and deserialization of the number here to illustrate that we need to know about these implementations to complete the proof:

{% highlight isabelle %}
type_synonym http_data = string

fun digit_list :: "nat ⇒ nat list" where
"digit_list 0 = []" |
"digit_list n = n mod 10 # digit_list (n div 10)"

definition string_of_nat :: "nat ⇒ string" where
"string_of_nat n = map char_of (digit_list n)"

fun nat_of_string :: "string ⇒ nat" where
"nat_of_string [] = 0" |
"nat_of_string (d # ds) = (of_char d) + 10 * (nat_of_string ds)"

definition deserialize :: "http_data ⇒ order" where
"deserialize d = ⦇ amount = (nat_of_string d) ⦈"

definition serialize :: "order ⇒ http_data" where
"serialize ord = string_of_nat (amount ord)"

definition http_server :: "http_data ⇒ orders ⇒ orders" where
"http_server d os = place_order os (deserialize d)"
  
definition place_order_http :: "orders ⇒ order ⇒ orders" where
"place_order_http os order = http_server (serialize order) os"
{% endhighlight %}

Now, we have both `place_order` and `place_order_http` defined. Aside from the implementation of `nat_of_string` and `string_of_nat` for serialization purposes, this is a pretty straighforward translation from the Typescript version.

Now, here is the proof for our desired theorem, using an intermediate lemma: 

{% highlight isabelle %}
lemma ser_deser[simp]: "nat_of_string (string_of_nat n) = n"
  apply(induction n rule: digit_list.induct)
   apply(auto simp: string_of_nat_def)
  done

theorem "place_order_http os order = place_order os order"
  apply(cases order)
   apply(simp add: serialize_def deserialize_def http_server_def place_order_http_def)
  done
{% endhighlight %}

Isabelle considers this proof sufficient, and we can now say that we've proven what seemed intuitively obvious: pushing an `Order` into an in-memory list has the same external behavior as calling an HTTP server which does it after deserializing the serialized data sent to it.

Here's the full example:

{% highlight isabelle %}
record order =
  amount :: nat

type_synonym orders = "order set"

fun place_order :: "orders ⇒ order ⇒ orders" where
"place_order os order = insert order os"

type_synonym http_data = string

fun digit_list :: "nat ⇒ nat list" where
"digit_list 0 = []" |
"digit_list n = n mod 10 # digit_list (n div 10)"

definition string_of_nat :: "nat ⇒ string" where
"string_of_nat n = map char_of (digit_list n)"

fun nat_of_string :: "string ⇒ nat" where
"nat_of_string [] = 0" |
"nat_of_string (d # ds) = (of_char d) + 10 * (nat_of_string ds)"

definition deserialize :: "http_data ⇒ order" where
"deserialize d = ⦇ amount = (nat_of_string d) ⦈"

definition serialize :: "order ⇒ http_data" where
"serialize ord = string_of_nat (amount ord)"

definition http_server :: "http_data ⇒ orders ⇒ orders" where
"http_server d os = place_order os (deserialize d)"
  
definition place_order_http :: "orders ⇒ order ⇒ orders" where
"place_order_http os order = http_server (serialize order) os"

lemma ser_deser[simp]: "nat_of_string (string_of_nat n) = n"
  apply(induction n rule: digit_list.induct)
   apply(auto simp: string_of_nat_def)
  done
 
theorem "place_order_http os order = place_order os order"
  apply(cases order)
   apply(simp add: serialize_def deserialize_def http_server_def place_order_http_def)
  done
{% endhighlight %}

Refinement is much deeper than proving simple equalities, and generally relies on proving that the refining implementation leads to a _subset_ of states of the refined one. You can read more about a practical example of a refinement proof in the [paper about refinement in the sel4 OS implementation](http://isabelle.informatik.tu-muenchen.de/~kleing/papers/klein_sw_10.pdf). This example is fine for our purposes of introducing refinement though, and hopefully illustrates the idea in an easier to understand way.

# Program Equivalence and Simplicity

My point in bringing up refinement is to comment on the perceived complexity of software systems. It seems to me that we often think that systems are fundamentally simple at their core, but somehow we still get bogged down with all of the implementation details in bringing that simple behavior to life. I think the idea of abstraction level that refinement provides can help with this - the essence of the behavior is not the code, but a higher level specification that exists at the level of the problem domain. Refinement is then a way to transform this specification into an implementation that has an industrial-strength architecture, providing a framework for verifying that this transformation is actually correct.

When I hear people say "well, this is just a CRUD app," this is what I think is behind that statement. We know that the behavior underlying a multi-process application is simpler than the code that we have to write to support that behavior in the system. The definition of `place_order` is vastly simpler than `place_order_http`, because it is reduced to the essential components in the problem domain, and nothing more. Simply introducing a client-server architecture into this application means we have to think about data serialization, something completely unrelated to bakers, bakeries, or biscuits.

The reason I'm so interested in refinement from this angle is that I believe the conventional methods of achieving this separation of abstraction layers fail us. Things like hexagonal / onion / layered architecture aim to separate high-level behavior from implementation choices, but at the cost of verbose and difficult code. Test suites rarely live up to the promise of supporting radical refactors without modification. Frameworks just mash all of the technical concerns together rather than expose this simple kernel of behavior underneath a complex technical system.

Refinement offers a way to encode the most important part of the system, the abstract specification, and tie it to the final implementation. This offers a new way of thinking about programming methodology that I think is really promising. Of course, it's no silver bullet, and the effort to fully prove the refinement of an entire system has been shown to be quite large. But there are a growing number of successful case studies using this method such as:

* The aforementioned [sel4 project](https://sel4.systems/). Their whole verification effort is based on refinement of an abstract specification.
* [Fiat](https://plv.csail.mit.edu/fiat/) which compiles high level specifications to effcient implementations along with a proof of refinement.
* [Cogent](https://www.youtube.com/watch?v=sJwcm_worfM&ab_channel=ICFPVideo) which helps reduce the time and cost of verifying file system implementations by automating parts of the refinement process from an executable specification to C code.

Design patterns and architecture might not be the answer to this problem - actually separating specification and implementation may be the path to a better development experience.

--- 

# Leftover from Refactoring

(*
This is the definition of refactoring, and that's is exactly what's going on here. This version has the same external behavior as the first (at least it seems that way), but its structure has changed - the concept of a server was introduced, for whatever technical reason, and `placeOrder` now talks to it instead of just pushing to a member array directly. This is similar to the well-known [Extract Method](https://refactoring.guru/extract-method) refactoring, but the argument has to be serialized and deserialized since the method in this case represents a separate server process.*)

How do we actually know that `BakeryBusinessWithServer` truly has the same behavior as `BakeryBusiness` though? What if `JSON.stringify` and `JSON.parse` were functions that we wrote? Do we trust ourselves to have handled all of the intricacies of data serialization properly? Most conversations about refactoring also speak of using tests to ensure that the behavior does in fact stay the same. You can imagine a set of tests that we'd have for the first example. If these tests pass after the refactor, the presumption is that the new implementation didn't change any behavior.



This is where I want to introduce the concept of refinement.

Refinement is also about code transformation that preserves behavior, 



I think almost everyone has heard of refactoring, whereas refinement is something that's only really discussed in the verification community. The ideas are subtly different, but there is also a lot of overlap, the most obvious being that they are both methods of transforming programs while keeping the behavior the same. Refactoring is more concrete, focusing on transformations between working programs. Refinement is a generalization of this, and is able to handle transformations between nondeterministic specifications and working programs. It's also able to handle programs that do _less_ than the program that they are refining, which is probably the biggest distinction.

The most important thing to understand about refinement is that it's meant to mean the opposite of _abstraction_. Something that's abstract might leave out a bunch of details, where a refinement fills in those details while preserving the original idea. In the case of our two bakery models, the first model is the abstraction while the second adds the technical details of a client-server architecture. Refactoring can also be performed to add details

# Closing

We made a lot of simplifications here, the most obvious one being that the client and server are written in the same language. This language boundary is a big problem, but one that is solved in a number of ways. Our "server" also writes 

# Refactoring as Refinement

To get on the same page, when we talk about refactoring, we mean "modifying the structure of a program without changing its behavior." This is always presented in an informal way though! How do we really know that a refactor preserves behavior? The conventional wisdom is to check this with tests, meaning in order to safely refactor, we need to have tests written ahead of time, and those tests need to guarantee correct behavior.

Our definition of refactoring mentions that it should not change "its behavior." This is odd when you think about it - how do we actually know if the behavior was changed or not?

Serialization / deserialization example refinement in isabelle - correctness theorem: serde impl matches abstract impl.

{% highlight isabelle %}
definition deserialize :: "http_data ⇒ order" where
"deserialize d = ⦇ amount = (nat_of_string d) ⦈"

definition serialize :: "order ⇒ http_data" where
"serialize ord = string_of_nat (amount ord)"

fun http_server :: "http_data ⇒ orders ⇒ orders" where
"http_server d os = place_order os (deserialize d)"
  
fun place_order_http :: "orders ⇒ order ⇒ orders" where
"place_order_http os order = http_server (serialize order) os"

theorem "deserialize (serialize order) = order"
  apply(cases order)
  apply(simp add: serialize_def deserialize_def)
  done
 
theorem "place_order_http os order = place_order os order"
  apply(cases order)
  apply(simp add: serialize_def deserialize_def)
  done
{% endhighlight %}

# A Language-Driven Future?

I'll close with this - what really gets me interested in this idea is that there are a few research projects out there that have gotten really promising results out of this idea. The first is [Cogent](https://github.com/au-ts/cogent) (more links) which is a research project within the group that works on sel4, the formally verified OS kernel. Cogent was created to address the needs of implementing file systems for OS's - they simply require way too much code to hand-verify, so Cogent automates a lot of the effort by creating a language and toolchain for verification. It does this by being a bridge between Isabelle / HOL and C, and by proving that the C code refines the corresponding higher-level HOL logical specification. This is the idea of the _certifying compiler_ - a tool that provably produces a correct piece of software for you.

There's also CakeML, which is closer to a "regular" programming language - it's just based on a subset of Standard ML, which is regular at least if you've used other functional programming languages.

Now, these projects are even still slightly different than what I'm thinking about - they really address the gap between a specification of the same algorithm in both a formal logic and a programming language. I have even heard this called the verification or verifiability gap - the tools we use to verify tend to be detached from the ultimate programming langauge that's used to create and execute a program. That's still a hugely important gap to cross, and these projects are amazing for tackling that.

What I'm talking about is a step further though - what if we view an entire software system as a refinement of an abstract specification? As we showed in this toy example, refinement can also be used to show equivalence between an abstract spec written from a product manager or business's perspective and a client-server implementation written from the engineering team's perspective. Could we create a language that is aimed at this style of development?

# Where Test Suites Fail

It is often said that refactoring can't be done properly without a test suite. But how can you possible truly refactor when your tests are referring to so many individual units withiin your program? Has anyone ever felt like there is some secret club that knows the "true way" to do this, but they won't actually tell anyone how? They just say "well, your abstractions aren't abstract enough" or "you are testing implementation and not behavior." You are not alone in thinking that this sounds like sage-like advice that isn't achievable by mere mortals.

Kent Beck acknowledged that [his traditional view of TDD doesn't apply to all scenarios](https://qr.ae/pGD2CN), especially Facebook. He says:

> The only way to check the quality of my work is with feedback. Some of that feedback can be collected before going into production and some can only be collected in production (this was a point I didn't understand four years ago).

To me, this is a comment about optimization. At Facebook, you can TDD all you want, but that will tell you almost nothing about the performance of your code with a billion concurrent users. Now granted, pretty much none of us are Facebook, but I believe optimization problems are always there.

That doesn't mean TDD is bad, it's just that it so clearly has its limits, and might not be helping us toward our goal of quality.

# Traceability and Stepwise Refinement

# Prior Art

Refinement is a big topic in the verification community, that's nothing new. This idea comes up in other places too. For example, the `fast-check` property-based testing library supports something they call [model-based testing](https://github.com/dubzzz/fast-check/blob/main/documentation/Tips.md#model-based-testing-or-ui-test). If you squint, you can see that this is really just showing that an implementation is a refinement of some more abstract behavior, what they call the "model" here. It's 

# Scratch 

This is most apparent in any kind of distributed system, including basic client-server systems. Going from 1 to 2 processes immediately 

When thinking about verifying "real world" software, we must leave the formal, organized realm of math and logic, and move to the practical, messy realm of real programming tools, libraries, and frameworks. They have a well known relationship though. For example, we often say that web applications are "simple" - they just move data around, perhaps we even call them CRUD apps. If we look at an abstraction version of their specification, this can be true - their high level behavior is much simpler than the production implementation. Twitter is the classic example - they really have only a few beahviors: create a tweet, retweet, like, and add a comment. But the implementation is [among the most complex in the world](http://highscalability.com/blog/2013/7/8/the-architecture-twitter-uses-to-deal-with-150m-active-users.html). 

Another difference is that the connotation of refactoring is generally about improving the code itself in some way, whether making it more readable or more . Refinement is generally about increasing specificity from an abstract specification, though optimization does fall in this bucket.

---- 

This code means something very specific and deterministic, but that doesn't mean that it's at the complexity level of the actual implementation that ends up getting built. There's no mention of client, servers, or databases here, just raw behavior modeled as data and operations on it. A specification of behavior at this level is often referred to as an "abstract specification," and this is the closest we can get to matching the product manager's view of behavior. The PM is also proxy for the entire business here - this is how the _entire business_ thinks about the software. When a sales pitch is being made, it's made at this abstraction level. When marketing storylines are created and presented, it's at this abstraction level. 

I want to really dig this in: no one except programmers is interested in the architectural and optimization concerns that go into a production-ready implementation 

But a use case by itself isn't, ironically, usable. We need to animate it into a production system. And for that, we turn to refactoring and refinement.

# Scratch

A well-known categorization of requirements is "functional" vs. "non-functional," but that separation only exists conceptually. IDEs don't offer a button to "reduce to functional requirements," you have to   

Example of starting out with client-side "shell" of a behavior, i.e. adding comments. Refactor to a full-stack isomorphic implementation that actually stores to a database. Show how this is a refinement of the algorithm, the behavior is still the same. 

Compare to specification of an abstract algorithm and comparing it to a refinment. This is how formal verification is often done, for example sel4 and Project Everest.

What test-check calls ["model based testing"](https://github.com/dubzzz/fast-check/blob/main/documentation/Tips.md#model-based-testing-or-ui-test) compares a refined implementation to an abstract one.

https://en.wikipedia.org/wiki/Refinement_(computing)

Consider this highly simplified implementation and invocation:

~~~
type Commment = {
    content: String
}

class Application {
    comments: Commment[] = []

    addComment(c: Commment) {
        this.comments.push(c);
    }

    viewComments() {
        return this.comments;
    }
}

let app = new Application();

app.addComment({ content: "Hey"});
~~~
{: .language-typescript}

the initial state is `comments = []`, and the final state is `comments = [{ content: "Hey" }]`.


Then take this slightly more complicated implementation, which fetches comments first from a server:
~~~
type AddComment = {
    type: "add_comment",
    comment: Commment
}

type ViewComments = {
    type: "view_comments"
}

type Endpoint = AddComment | ViewComments;

class ApplicationWithServer {
    clientComments: Commment[] = []
    serverComments: Commment[] = []

    async addComment(c: Commment) {
        return this.server({ type: "add_comment", comment: c });
    }

    async viewComments() {
        return this.server({ type: "view_comments"});
    }

    async server(endpoint: Endpoint) {
        function wait() {
            return new Promise(resolve => setTimeout(resolve, 200))
        }
        switch (endpoint.type) {
        case "add_comment":
            await wait();
            this.serverComments.push(endpoint.comment);
            break;
        case "view_comments":
            await wait();
            this.clientComments = this.serverComments;
            break;
        }
    }
}

(async () => {
    let appWithServer = new ApplicationWithServer();
    await appWithServer.addComment({ content: "Hey"});
    await appWithServer.viewComments()

    console.log(appWithServer.clientComments);
})();
~~~
{: .language-typescript}

The initial state here is:

```
clientComments = []
serverComments = []
```

And the final state is:

```
clientComments = Commment[{ content: "Hey" }]
serverComments = Commment[{ content: "Hey" }]
```

We have more state variables in the second implementation, and we even have more intermediatet states - `serverComments` get populated before `viewComments()` populates `clientComments`. But if we only consider `clientComments`, we have the same initial and resulting states. Saying this another way, `Application` implies `ApplicationWithServer` or:

`Application` => `ApplicationWithServer`

This means that if any state 

This is what "refinement" means - a program refines another if it achieves all of the same states and invariants on those states.

# In Progress

simple. Z-spec. But, once we move to client-server or even more distributed architectures such as microservices, the implementation becomes more complex. But the _behavior_ stays the same.

This sounds an awful lot like a common programming concept: refactoring. The definition of refactoring is "changing the implementation of a module without changing its behavior". But, this is another example where we're just making up a new word for an old concept: the concept of refinement.