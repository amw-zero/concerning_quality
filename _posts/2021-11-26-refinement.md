---
layout: post
title: 'Refinement: Formalizing the Simplicity Underneath Complex Programs'
tags: formal_verification refinement formal_specification
author: Alex Weisberger
---

"Real world" software is large, messy, and full of detail. A customer might just want to store and retrieve their data, but those simple requirements can get lost in the sea of programming language semantics, libraries, frameworks, databases, Internet protocols, serialization formats, performance optimizations, security hardening, auditability, monitorability, asynchronicity, etc., etc., ad infinitum. We should always try to simplify our stack, but practical computation is optimization to an extent - how would you like to use a logically correct application where each interaction takes 10 seconds to give feedback?

To really understand this difference between functional and non-functional requirements, let's look at the concept of _refinement_. Refinement is the fundamental concept behind behavior-preserving program transformation, and it allows us to separate abstraction from implementation in a formal and verifiable process.


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

This simple abstract data type captures the activity of the problem domain. It's still described in a programming language, but could never be deployed as a real system because it lacks too many details necessary for a modern, interactive program to function.

# Refinement: the Opposite of Abstraction

At some point, we have to actually encode these activities as a deployable application though, and this is where the abstraction level changes. No longer are we only concerned with the nouns and verbs of the problem domain, but we also have to worry about concrete technologies, user experiences, performance, and security. Here's where we need to think about things like relational databases, client-server architecture, and user authentication, etc.

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

When the same `placeOrder` call is made, the same result is achieved (at least it seems that way by inspection), but the behavior is carried out internally in a more detailed way than the previous version. We say that `BakeryBusinessWithServer` _refines_ `BakeryBusiness`. Refinement means going from more to less abstract, or from less to more specific. `BakeryBusiness` has hardly any detail, being just raw data and operations. Placing an order via `BakeryBusinessWithServer` results in the same ultimate state, but introduces the more specific functionality of calling a server.

In some ways, this is similar to refactoring, but refactoring is [generally concerned with improving the readability or understandability of a program](https://martinfowler.com/bliki/IsOptimizationRefactoring.html). Performance optimizations, for example, may or may not be considered refactors, but they are definitely considered refinements. So refactoring and refinement exist along slightly different dimensions.

A big difference is how each determines whether or not the behavior is the same between the two program versions. With refactoring, this is done with tests. We can imagine a set of tests that were developed for `BakeryBusiness`, and if they pass for `BakeryBusinessWithServer`, then the refactoring is considered to preserve the behavior. As we know, tests don't actually catch all bugs though, and bugs can especially creep in if the new version is much more complex than the old. Imagine a bug in `JSON.parse` that only occurs when parsing an array containing the number 7 in a nested key, i.e. `{ nested: { key: [7] } }`. The abstract implementation may or may not have tests for this case, so the new implementation might introduce this bug while passing all of the existing tests (a classic example of the [underspecification that test suites provide]({% post_url 2021-10-06-misspecification %})).

Refinement, on the other hand, comes with a theory that's mathematically verifiable. The version with the bug in `JSON.parse` could not be considered a refinement of the abstract version because refinement is concerned with all program executions. Even still, the difference is mostly philosophical, as (correct) refactors can always be shown to be refinements. Relating the two is convenient since most people have heard of refactoring, whereas refinement is generally only discussed in the verification community.

What I want to stress about refinement is that it is generally done because we _want_ to have an abstract specification of a program. This may sound odd, but consider the importance and potential utility of the product manager's view of the system (`BakeryBusiness`). It is smaller, simpler, and easier to make general statements about. It is also substantially easier to verify properties at this level of abstraction. Isn't this view then completely demolished by the technical detail of the actual code? We then have to resort to writing endless amounts of test cases at the implementation level. From that angle, it's not so strange to want to keep that view in tact and instead prove that the implementation refines it.

# Justifying a Refinement

Refinement is a whole field unto itself, with the main theory being laid out in the [refinement calculus](https://lara.epfl.ch/w/_media/sav08:backwright98refinementcalculus.pdf). It's way too deep to fully cover, but here is a taste of what it takes to prove that a program is a refinement of another.

There are many ways to prove refinement between two programs, but the simplest to understand is equality - if two programs result in the exact same value for all possible inputs, then one can be seen to refine the other. Let's call our more abstract method for placing orders `place_order`, and let's call our version that uses a server `place_order_http`. In Isabelle/HOL, which for the most part resembles other functional programming languages, we would express equality of the two functions as a theorem:

{% highlight plaintext %}
theorem "place_order_http orders order = place_order orders order"
{% endhighlight %}

`orders` is the state of `Orders` in the system (corresponding to `bakery.orders` in the TS example), and `order` is the new `Order` being placed. The fact that their values aren't specified means this theorem must hold for all possible values in order for it to be true.

Let's first introduce the abstract implementation:

{% highlight plaintext %}
record order =
  amount :: nat

type_synonym orders = "order set"

fun place_order :: "orders ⇒ order ⇒ orders" where
"place_order os order = insert order os"
{% endhighlight %}

We introduce the `order` type as a record with just an `amount` field for simplicity, and we define the `place_order` function as simply inserting an `order` into the passed in state of all `orders`. Note how simple this is.

Let's now introduce the version that calls to a server, serializing before the call and deserializing after. Note - we implement the serialization and deserialization of the number here to illustrate that we need to know about these implementations to complete the proof:

{% highlight plaintext %}
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

{% highlight plaintext %}
lemma ser_deser[simp]: "nat_of_string (string_of_nat n) = n"
  apply(induction n rule: digit_list.induct)
   apply(auto simp: string_of_nat_def)
  done

theorem "place_order_http os order = place_order os order"
  apply(cases order)
   apply(simp add: serialize_def deserialize_def http_server_def place_order_http_def)
  done
{% endhighlight %}

Isabelle considers this proof sufficient, and we can now say that we've proven what seemed intuitively obvious: pushing an `Order` into an in-memory list has the same external behavior as calling an HTTP server which does it after deserializing the serialized data sent to it. This is true of all possible program executions though - a test case cannot be constructed that results in this equality not holding, and that's a great assurance.

More importantly (for the topic of this post) is that we now have the simpler `place_order` function as a living artifact, instead of being hidden or implicit in the implementation level code. Should we want to prove anything about the system, we could do it on this version and be sure that it also holds for the implementation.

Here's the full example:

{% highlight plaintext %}
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

Refinement can be much more involved than proving simple equalities like this. You can read more about a practical example of a refinement proof in the [paper about refinement in the sel4 OS implementation](http://isabelle.informatik.tu-muenchen.de/~kleing/papers/klein_sw_10.pdf). This example is fine for our purposes of introducing refinement though, and hopefully illustrates the idea.

# Program Equivalence and Simplicity

My point in bringing up refinement is to comment on the perceived complexity of software systems. It seems to me that we often think that systems are fundamentally simple at their core, but somehow we still get bogged down with all of the implementation details in bringing that simple behavior to life. I think the idea of abstraction level that refinement provides can help with this - the essence of the behavior is not the code, but a higher level specification that exists at the level of the problem domain. Refinement is then a way to transform this specification into an implementation that has an industrial-strength architecture, providing a framework for verifying that this transformation is actually correct.

When I hear people say "well, this is just a CRUD app," this is what I think is behind that statement. We know that the behavior underlying a multi-process application is simpler than the code that we have to write to support that behavior. The definition of `place_order` is simpler than `place_order_http`, because it is reduced to the essential components in the problem domain, and nothing more. Simply introducing a client-server architecture into this application means we have to think about data serialization, something completely unrelated to bakers, bakeries, or biscuits.

The reason I'm so interested in refinement from this angle is that I believe the conventional methods of achieving this separation of abstraction layers fail us. Things like hexagonal / onion / layered architecture aim to separate high-level behavior from implementation choices, but at the cost of verbose and difficult code. Test suites rarely live up to the promise of supporting radical refactors without modification. Frameworks just mash all of the technical concerns together rather than expose this simple kernel of behavior underneath a complex technical system.

Refinement offers a way to encode the most important part of the system, the abstract specification, and tie it to the final implementation. This offers a new way of thinking about programming methodology that I think is really promising. This is different than viewing refinement as purely a verification technique. In this light, refinement is actually the enabler of a way of formalizing the _simplicity_ at the heart of software, in contrast to Domain-Driven Design's attempt to tackle the complexity.

 Of course, it's no silver bullet, and the effort to fully prove the refinement of an entire system has been shown to be quite large. But there are a growing number of successful case studies using this method such as:

* The aforementioned [sel4 project](https://sel4.systems/). Their whole verification effort is based on refinement of an abstract specification.
* [Fiat](https://plv.csail.mit.edu/fiat/) which compiles high level specifications to effcient implementations along with a proof of refinement.
* [Cogent](https://www.youtube.com/watch?v=sJwcm_worfM&ab_channel=ICFPVideo) which helps reduce the time and cost of verifying file system implementations (also in the sel4 project) by automating parts of the refinement process from an executable specification to C code.

Cogent in particular takes a really exciting approach by solving part of this problem at the programming language level. It's hard to refine an abstract specification all the way down to C. The Cogent compiler automates this last step to C, while also providing a corresponding specification at around the executable level. If all that's left is to prove a refinement from the fully abstract level to this level, that still greatly reduces the cost of refinement verification in general.

All this is to say, design patterns and architecture might not be the answer to this problem - actually separating abstract specification and implementation may be the path to a better development experience. And there are languages and tools out there waiting to be born to advance that goal.

--- 

# Acknowledgements

I'd really like to thank the members of the [Isabelle Zulip chat](https://isabelle.zulipchat.com/) for helping me when I was stuck in the above equality proof. Particularly Wenda Li, Mathias Fleury, and Manuel Eberl all provided very helpful feedback.