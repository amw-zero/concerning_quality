---
layout: post
title: 'Most Tests Should Be Generated'
tags: testing philosophy
author: Alex Weisberger
---

Traditional testing wisdom eventually invokes the test pyramid, which is a guide to the proportion of tests to write along the isolation / integration spectrum. There's an eternal debate about what the best proportion should be at each level, but interestingly it's always presented with the assumption that test cases are hand-written. We should also think about test generation as a dimension, and if I were to draw a pyramid about it I'd place generated tests on the bottom and hand-written scenarios on top, i.e. most tests should be generated.


# Correctness is What We Want

What are we even trying to do with testing? The end goal is to show correctness. We do this for two main reasons: to show that new functionality does what's expected before release, and to ensure that existing functionality is not broken between releases. Tests are a means to this end, nothing more. Importantly, they also can only ever show _approximate_ correctness. To understand that fully, let's define correctness precisely. Here's a paraphrasing of Kedar Namjoshi's definition from [Designing a Self-Certifying Compiler](https://www.youtube.com/watch?v=GZXSSCF4siY).

First we have to define what a program is. The simplest representation is just a function from values in X to values in Y. This may look oversimplified, but an interactive program can even be modeled this way by assuming the program function is invoked in response to each user interaction in a loop. So a program P is:


$$ P: X \rightarrow Y $$

Correctness requires a specification to check against. This might be surprising, since one rarely exists, but think of traditional test suites as simply defining this specification point-wise. A specification S can be a function of the same type:

$$ S: X \rightarrow Y $$

We can express correctness with the following property:

$$ \forall x \in X: P(x) = S(x) $$

In English: for every x value in X, evaluating P(x) yields the same value as evaluating S(x).

Point being, we want to check that the implementation program does the same thing as the specification, always. Notice how achieving 100% branch coverage in a test suite doesn't get us here by the way, since that doesn't account for all inputs in *X*.

Let's look at how scenarios and generated tests differ with how they show correctness.

# Testing for Correctness with Scenarios

As I mentioned, the traditional test pyramid is talking about hand-written test scenarios, aka examples / test cases etc. Correctness is pretty simple to express as a logical property, but it's very difficult to test for. The first thing we run into is the test oracle problem - how do we actually get the value of *S(x)* to check against? Executable specifications rarely exist (though I am a proponent of using them for this reason), so normally what happens is that the test writer interprets an informal specification and hard codes the expected value of *S(x)* for a specific x as the test assertion. The informal specification is what the team talks about when deciding to build the feature, and the test writer is the test oracle. Sometimes some details are written down, sometimes not, but the burden of coming up with the expected test value is always on the test writer, and it's a completely manual process.

The next issue is the number of values in the input domain X. Each test case needs to specify a single input value from X, but testing for all values from X is not feasible in any way. This is not an exaggeration - if X is the set of single 64-bit integers, we'd have to check 18,446,744,073,709,551,616 test cases. This multiplies for each additional integer, and how many integers do you think are in the entire state of a realistic program? We said earlier that a test suite only approximates correctness, but this makes it more formal. A test suite actually represents this property:


$$ TX \cup X \land \forall tx \in TX: P(tx) = S(tx) $$


How effective a test suite is boils down to how confident we are that testing the input values that we chose implies that the correctness will hold for all of the input values, i.e.


$$\forall tx \in TX: P(tx) = S(tx) \implies \forall x \in X: P(x) = S(x)$$


This is probably true sometimes, but we have no guarantee of it in general. How can we ever know that the values that we pick out of X are "good enough"?

So test scenarios have an informal and manual test oracle process, and are pretty quantitatively incomplete in terms of how much of the input domain they can possibly cover. That doesn't mean they're not useful! Testing via scenarios is unreasonably effective in practice. There are two main benefits to them. First, they're easy to write. This is likely because they require very literal and linear reasoning, since we just need to assert on the actual output of the program. If we really want, we can just run the program and observe what it outputs and record that as a test assertion. People do this all the time, and there's even a strategy that takes this to the extreme called "golden testing" or "snapshot testing."

The next benefit, somewhat obviously, is that they're specific. If we have a test case in our head that we know is really important to check, why not just write it out? When we do this, we [also get more local error messaging when the test fails](https://buttondown.email/hillelwayne/archive/some-tests-are-stronger-than-others/#fnref:stronger-than-nitpick), which can point us in a very specific direction. This is always cited as one of the main benefits of unit testing, and it really is helpful to have a specific area of the code to look at vs. trying to track down a weird error in a million lines of code.

Now let's look at generated tests.

# Generating Tests for Properties

Our correctness statement from earlier is expressed as a property: *P(x) = S(x)* is a property that's either true or not for all of the program inputs. Now, we know that we can't actually check every single input in a test, but what we can do is generate lots and lots of inputs and check if the property holds. With property-based testing these inputs are usually generated randomly, but there are [other data generation strategies as well]({% post_url 2022-08-31-category-partition-properties %}). So here, we're talking about property-based testing more generally, and it has a couple of subtly different problems than testing with scenarios.

When checking for properties, the test oracle problem also presents itself immediately. We can always evaluate *P(x)*, since that's our implementation that we obviously control, but how do we know what the expected value *S(x)* is? And, furthermore, we have a chicken-and-egg problem: how do we know what *S(x)* is when code is generating `x` and we don't know what it is ahead of time?

The answer is to define *S(x)* with logic that we can actually execute in the test, i.e. an executable specification. This often sounds weird to people at first, but looking at our correctness statement this is the more natural way to test. Instead of implicitly defining the specification via a bunch of individual test cases, we just define *S(x)* and call it during testing. This can take the form of simple functions that represent invariants of the code, all the way up to [entire models of the functional behavior]({% post_url 2022-08-11-model-based-testing %}).

The input space issue is also still present with property-based testing, but in a different way: generating data is hard. Like, really hard. One of the main challenges is logical constraints, e.g. "this number must be less than 100". These constraints can get very complicated in real-world domains, and sometimes that even leads to performance issues where you have to discard generated inputs until the constraint is met.

Property-based testing has an absolute killer feature though: it discovers failure cases for you, i.e. it actually finds unknown unknowns. This is worth more than gold. With scenarios, you have to know the failure ahead of time, but isn't every bug in production a result of a failure that you didn't even think of before deploying? Rather than check cases that we know ahead of time, we generate tests that search for interesting failures. This simply can't be done with ahead-of-time test scenarios.

# The Test Generation Pyramid

We looked at some of the pros and cons of scenarios vs. generated tests, so which should we prefer? I definitely think we should write both kinds, but overall most tests should be generated. Test strategies have to be represented as a triangle, so here is this idea in triangle form:

<div style="display: flex; justify-content: center;">
  <img src="/assets/generated_tests/generated-tests.png" style="width:64%"/>
</div>

Why should we prefer generated tests? It all boils down to the fact that they find failures for us, which means that they naturally bring us closer to correctness. Unfortunately, no matter how perfect our selected test scenarios are they leave the vast majority of the input space uncovered, and there is no way to know which uncovered inputs are important and which are redundant. By having a suite of generated tests that are constantly looking for new inputs, we put ourselves in the best position to find edge cases that we just aren't considering at the moment.

It's like having a robot exploratory tester that we can deploy at will, which opens up a whole new mode of testing. We can run generated tests in CI before merging, sure, but we can also run them around the clock since generated tests _search_ for failures vs. checking predetermined scenarios. More testing time means more of the input domain being searched, so to check more inputs we simply run each generated test for longer and run more test processes in parallel.

This doesn't mean that we stop writing scenarios. That's why there's two sections in the pyramid. All of the proposed values of test scenarios are valid - we get specific error messages, free executable documentation, and a guarantee that important cases are checked. But generated tests are [fundamentally stronger](https://buttondown.email/hillelwayne/archive/some-tests-are-stronger-than-others/#fnref:stronger-than-nitpick) than scenarios, since the generated tests will often find the same inputs that we use in our scenarios in addition to ones we haven't thought about.

Since the ultimate goal of testing is correctness, not documentation and local error messages, it's in our best interest to supplement our scenarios with lots and lots of generated tests.
