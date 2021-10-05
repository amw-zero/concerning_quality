---
layout: post
title: 'Refactors as Algorithm Refinements: Simplifying the Behavior of Distributed Programs'
tags: formal_verification
author: Alex Weisberger
---

When thinking about verifying "real world" software, we must leave the formal, organized realm of math and logic, and move to the practical, messy realm of real programming tools, libraries, and frameworks. Their relationship is interesting though. For example, we often say that web applications are "simple" - they just move data around, perhaps we even call them CRUD apps. When we look at an abstraction of their specification, they actually can be very simple. Z-spec. But, once we move to client-server or even more distributed architectures such as microservices, the implementation becomes more complex. But the _behavior_ stays the same.

This sounds an awful lot like a common programming concept: refactoring. The definition of refactoring is "changing the implementation of a module without changing its behavior". But, this is another example where we're just making up a new word for an old concept: the concept of refinement.




Example of starting out with client-side "shell" of a behavior, i.e. adding comments. Refactor to a full-stack isomorphic implementation that actually stores to a database. Show how this is a refinement of the algorithm, the behavior is still the same. 

Compare to specification of an abstract algorithm and comparing it to a refinment. This is how formal verification is often done, for example sel4 and Project Everest.

What test-check calls ["model based testing"](https://github.com/dubzzz/fast-check/blob/main/documentation/Tips.md#model-based-testing-or-ui-test) compares a refined implementation to an abstract one.

https://en.wikipedia.org/wiki/Refinement_(computing)