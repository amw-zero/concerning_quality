---
layout: post
title: 'The Verification Gap: A Major Hurdle for the Industry Adoption of Formal Methods'
tags: formal_verification
author: Alex Weisberger
---

Let's assume that we've made the decision to formally verify a project that we're working on. How would we even go about doing that? This simple question inevitably leads to the _verification gap_: the fact that software has to be executed at some point, but the tools for logic verification are often detached from the languages that we use to build executable programs. Some languages do exist[^fn1] that reduce or eliminate this gap at the software level, but the code they generate still runs on hardware without any formal semantics. Without trying to be an alarmist, there's really no escaping this problem. At the end of the day, there is always some delta between what can be verified and what is actually happening in a production system. Thinking about this gap is crucial in understanding the limitations of formal methods, but honing in on it also opens up the conversation for practical solutions and a deeper understanding of software correctness.



# Beginning at the Beginning

> Begin at the beginning, and do not allow yourself to gratify a mere idle curiosity by dipping into the book, here and there. This would very likely lead to your throwing it aside, with the remark “This is much too hard for me!”, and thus losing the chance of adding a very large item to your stock of mental delights.
> <br><br> **Symbolic Logic**
> <br>-Lewis Carrol

To understand the verification gap, we have to first really understand what formal verification is at its core, and that is: _showing the correctness of a system written in a formal logic._ Whether by model checking or mathematical proof, verifying a system requires an underlying logic with explicit, unambiguous semantics so that correctness statements can be stated and evaluated for truth. You can't evalulate statements or make judgements about a system that doesn't have an agreed upon set of rules. 

_Formal_ really just means that we have to "begin at the beginning." Everything about the logical rules are described, down to the primitive rules of inference. If we wanted to unturn all of the stones of our specification to understand some piece of functionality, we could, and this is why formal verification is so trustworthy - it doesn't rely on the ambiguities of our written languages. 

# The Other Side of the Pond

On the other end of the spectrum is what I'm certainly most familiar with, and I imagine it's also what most working programmers are most familiar with: programming languages. You know, tools that create programs that run on real computers. [Python, Java, etc.](https://www.tiobe.com/tiobe-index/) The long story short is, you can't formally reason about almost any programming language because basically none of them have a semantics that's formally defined[^fn2]. Many languages are based on papers, ideas, and theories that _are_ formally defined, but for the most part... we just build new languages as ideas arise. As you can see, this is the root of the verification gap - our tools are simply not built with verification in mind.

If you ask me, this is perfectly justified because since the inception of computing, we've been bogged down with solving legitimately and extremely difficult problems. Like the small feat of figuring out how to write and execute programs with machines, or building complex compiler toolchains. We've been busy figuring out how to enable ourselves to actually build the software that the world desires, and adding verifiability on top of that just hasn't been a factor with much economic pressure behind it.

# Closing the Gap

It certainly seems that there's been an uptick in interest in formal methods recently, with various forms of it being used at [Amazon](https://lamport.azurewebsites.net/tla/formal-methods-amazon.pdf), [Mozilla](https://blog.mozilla.org/security/2020/07/06/performance-improvements-via-formally-verified-cryptography-in-firefox/), [Microsoft](https://project-everest.github.io/), [Elastic](https://www.youtube.com/watch?v=qYDcbcOVurc), [Cockroach Labs](https://www.cockroachlabs.com/blog/parallel-commits/), [MongoDB](https://www.youtube.com/watch?v=wVmGMQZSP88&list=PLvaSNyqj9rnK4ZJHenG-4emWltWh4vpFv&index=6), and others. We've gotten very far with our current tooling and testing methodologies, but we may be at a tipping point where we're expected to build such constantly complex software that a new level of tools is necessary - a possible second software crisis.

How we deal with the verification gap will likely be a key factor in the growth of formal methods in the future.

So on one end of the gap we have logical formalisms with pure and unambiguous semantics, on the other we have practical but messy programming languages, and statements about our logical model unfortunately don't carry over to the implementation. What can we do to link the two sides? If it's really the biggest roadblock to the practical usage of formal methods, then we had better understand what our options are. There are many approaches, and they broadly fall into three categories: program extraction, program parsing, and program testing. This definitely isn't an exhaustive list either, but is at least a good introduction to common approaches and success stories.

## Program Extraction

With this approach, we start out all the way at the verifiability end of the spectrum. That is, we don't start with a "typical" programming language, but we first express the logic of our program in some formal logic. Most commonly with this approach, this is done in a proof assistant like Isabelle/HOL, Coq, or Why3. I'm most familiar with Isabelle, but all of the ones listed here have logics that feel very similar to Standard ML, Ocaml, or Haskell with some additional features for expressing theorems. In fact, [Concrete Semantics](http://concrete-semantics.org/), the amazing book about compiler correctness, describes its underlying logic (higher-order logic, or HOL) as being "functional programming + logic."

An example project that took this approach is [CompCert](https://compcert.org/), the formally verified C compiler. The compiler functionality and correctness theorems are all described and proved in Coq's logic, and Coq, like most proof assistants, provides the functionality to translate from its logic to a "real" programming language - in this case Ocaml.

It's important to note that the program extraction itself is generally not verified, so the full trust in the verification effort ends at this boundary. However, the extraction process is also fairly straightforward due to the closeness of Coq's logic ([the Calculus of Inductive Constructions](https://en.wikipedia.org/wiki/Calculus_of_constructions)) and Ocaml. This is the case for many proof assistants and languages.

## Program Parsing

> The first step required to formally reason about a program is to parse the code into a formal logic.
> <br><br>_[Bridging the Gap: Automatic Verified Abstraction of C](https://trustworthy.systems/publications/nicta_full_text/5662.pdf)_,
> <br>-David Greenaway, June Andronick, and Gerwin Klein

The next approach worth mentioning is program parsing, where we write a full implementation in a programming language, but parse that language into the formal logic and perform verification there.

An example project of this is [sel4](https://sel4.systems/), a formally verified OS kernel written in C. The key phrase here is "written in C," and this is why parsing the implementation is necessary. A parser translates the C implementation code into a representation inside of the Isabelle/HOL proof assistant where the actual verification is performed. The main implication of this approach is that they first [had to define a "very exact and faithful formal semantics for a large subset of the C programming language"](http://web1.cs.columbia.edu/~junfeng/09fa-e6998/papers/sel4.pdf) inside of higher-order logic, Isabelle/HOL's core logic. 

The "faithfulness" of this semantics has to be trusted along with the parser. But a compelling aspect of this approach is that the actual executable C code can be written directly, so the verification effort is kind of "on top" of the regular program development. I think this is a methodology that a lot of programmers can at least wrap their heads around, whereas program extraction might seem a little more spooky.

## Program Testing

The last approach is where we do all of our verification on a logical specification, and then use that specification to check if the actual implementation is valid by comparing program executions to the specification. There are many ways to do this "checking," but the main one we'll talk about here is model-based test case generation. This is when the specification is used to generate test cases to be run on the implementation, comparing the two. Discrepencies in the tests would mean that the implementation doesn't successfully adhere to the specification.

MongoDB used this to [test the implementation of a conflict-resolution algorithm](https://www.youtube.com/watch?v=wVmGMQZSP88&t=954s) in their MongoDB Realm product. First, they wrote a TLA+ specification of the algorithm. They used TLC, the TLA+ model checker, to check some properties on this model to get confidence about its functionality. They then used a combination of the TLA+ tooling and some of their own custom tooling to generate test cases for their Golang implementation of the algorithm. All-in-all, this led to 4,913 test cases being generated which achieved 100% branch coverage in the implementation.

Overall generating test cases is a compelling approach because of its simplicity. Test frameworks exist for all major programming langauges, so the only problem to solve is how to map the specification to test cases in an automated process. Compared to other tasks in the verification sphere, this is pretty straightforward. The main downside is that anything short of exhaustive testing isn't verification anymore, so the trust in the implementation holding the same properties as the spec isn't as strong.

# Closing Thoughts

The verification gap is often brought up as an argument for formal verification being a non-starter for any project. While it is absolutely real, and absolutely something that needs to be addressed, there are options with proven case studies. Like everything else, each approach has ups and downs, but once the gap is acknowledged it can be crossed.

<hr>

[^fn1]: Like [F*](https://www.fstar-lang.org/), [Dafny](https://dafny.org/dafny/), [Why3](https://why3.lri.fr/doc/index.html), and [Chalice](https://www.microsoft.com/en-us/research/project/chalice/). Each takes a different and interesting approach to bridging the verification gap.

[^fn2]: The only marginally used language that I know about with a full formal semantics is [Standard ML](https://smlfamily.github.io/sml90-defn.pdf). Worth mentioning, [WebAssembly](https://webassembly.github.io/spec/core/) does too! If others are out there, I'd love to know about them.
