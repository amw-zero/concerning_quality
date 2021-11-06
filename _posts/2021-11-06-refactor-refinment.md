---
layout: post
title: 'Refactoring as Refinement: Formalizing the Simplicity Underneath Distributed Programs'
tags: formal_verification
author: Alex Weisberger
---

"Real world" software is large, messy, and full of detail. A customer might just want to store and retrieve their data, but these simple requirements can get lost in the sea of programming language semantics, libraries, frameworks, databases, Internet protocols, serialization formats, performance optimizations, security hardening, auditability, monitorability, asynchronicity, ad infinitum. We should always try to simplify our stack, but practical computation is optimization to an extent - we will (and should) always want to use time and space as efficiently as possible.

To really understand this difference between functional and non-functional requirements, let's look two related concepts: refactoring and refinement. These are the fundamental concepts behind program transformation, and they each provide a framework for talking about how we change programs. They're really two sides of the same coin, but whereas refactoring is informal and intuitive, refinement is formal and verifiable.


# How Product Managers Think About Behavior

Remember - quality does not exist in a vacuum (link to Why quality?), and paying customers care little about a verified system that doesn't do what they want. This is why a good product manager is part psychotherapist, first extracting the customer's mindset before jumping into solutioning. So given that their primary concern is what a human being wants out of a system, how do they talk and think about behavior?

Here's an example of something they wouldn't say:

> To meet our customers' requirements, we're going to need to start with a microservice architecture communicating with gRPC over HTTP. We know that won't be good enough, so we'll also introduce a fanout-on-write pipeline to populate precomputed data in Redis. Of course, they also require a single-page application, so we'll need an API gateway for a React app to call to proxy requests to the appropriate services. With this in place, the customer will be able to run their baking business on our app.

Here's an example of something they would say:

> Bakers keep saying they spend too much time on the phone taking people's orders. They want a self-service order platform so they can spend less time on the phone and more time baking. Their customers should be allowed to place a new order, track their current orders, and view their previous orders. The bakers want to be able to see their upcoming orders so they can prioritize their work. With this in place, they'll lower their percentage of burnt biscuits and they'll have no problem signing up for our service contract.

Ok, admittedly, this is a very particular kind of application -the venerated Enterprise Application- but the point should be clear: PMs think and speak about things that happen in the physical world. Assuming we do want to build a computer program to solve this problem though, we will need some kind of interface between this view of the world and a computer. This specification is informal, and even though it's tiny it's rife with ambiguity and nondeterminism.


# Refactoring as Refinement

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