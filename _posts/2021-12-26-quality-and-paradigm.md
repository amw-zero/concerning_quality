---
layout: post
title: 'Quality and Paradigm: The Assembly Language of Reasoning and the Domain-Specific Language of the Machine'
tags: formal_verification functional_programming imperative_programming
author: Alex Weisberger
---

Does programming paradigm affect the ultimate quality of software? I generally avoid stoking the eternal flame war of functional vs. imperative programming, but it has to be discussed since there are so many repeated statements of fact about which one leads to higher-quality programs[^fn1].  The arguments primarily exist along two dimensions: correctness and performance. Summing them up, functional programs are more correct but slow, and imperative programs are buggy but fast. Of course, there are counterexamples to each of these statements, but this is a fair generalization overall.

Thinking of it as a competition isn't helpful, though, because each paradigm has a different purpose: FP is optimized for mathematical reasoning, whereas imperative programming is fundamentally about manipulating computer hardware. It's this difference between reasoning and practical execution that suggests that the highest quality software actually requires utlizing both paradigms: no matter what level we write code at, we must be able to reason about how that code runs at the level of real-world machines.



# Destructive Array Updates

Destructive array updates are a great backdrop for analyzing the differences between the FP and imperative styles. We'll use C for the imperative example:

{% highlight c %}
int main() {
    int a[4] = {1, 2, 3};
    a[1] = 4;

    return 0;
}

{% endhighlight %}

In the imperative style, updating the value at index 1 in `a` mutates `a`, meaning printing `a` afterwards would show `[1, 4, 3]`. The 2 is gone, making the update destructive. This is a notoriously difficult example for FP to handle, which leads to its detractors to (justifiably) criticize it. How can a paradigm be considered serious if it can't handle one of the most common programming techniques there is?

This begs two questions: 

1. What exactly is difficult about modeling an array in FP?
2. Why is it so convenient in an imperative language? 

To look into #1, here's a first attempt at modeling the above imperative code in an FP style, in Isabelle/HOL[^fn2]:

```
fun update :: "'a list ⇒ nat ⇒ 'a ⇒ 'a list" where
"update [] i v = []" |
"update (x # xs) i v =
  (case i of 0 ⇒ v # xs | Suc j ⇒ x # update xs j v)"

definition "fp_list = [1, 2, 3::int]"

value "update fp_list 1 4" (* Returns [1, 4, 3] *)
value "fp_list" (* Returns [1, 2, 3] *)
```

We use a list to model an array since we can represent a list as a recursive datatype directly, e.g. `(Cons 1 (Cons 2 (Cons 3 Nil)))`. We have an `update` function which uses recursion and pattern matching on the list values to build up the updated value from scratch, with `update fp_list 1 4` equaling the desired value: `[1, 4, 3]`. However, this function does not have the semantics of the array update because `fp_list's` value remains unchanged after being passed as an argument to `update`. The value returned by `update` is not connected to or tied to the value of `fp_list` in any way, and this is because that is simply the semantics of mathematical functions - they only map input values to output values, i.e. they are pure.

To achieve destructive update semantics, we need to add the notion of a "reference." A reference is an indirection, a way to _refer_ to a value by something like a name or an address. There are a million ways to do this, but here's a simple approach:

```
type_synonym var_name = "string"
type_synonym state = "var_name ⇒ int list"

definition read_state :: "state ⇒ var_name ⇒ int list" where
"read_state s var = s var"

definition write_state :: "state ⇒ var_name ⇒ int list ⇒ state" where
"write_state s var l = s(var := l)"

definition imp_update :: "state ⇒ var_name ⇒ nat ⇒ int ⇒ state" where
"imp_update state var n idx = 
  (let list = read_state state var in
  write_state state var (update list n idx))"

definition "state ≡ λ v. (if v = ''a'' then fp_list else [])"

value "read_state (imp_update state ''a'' 1 4) ''a''" (* [1, 4, 3] *)
```

Our new function, `imp_update`, does have the destructive semantics we're looking for, but in order to get it we introduce the ability to reference a value by name. We do this by modeling state as a function from variable names to values (with the only values we can have being lists of integers to keep things simple). Then, instead of operating on values directly, we must read from and write to this state by specifying the referred variable's name - in this case `a`. It's worth calling out that in `write_state`, the syntax `s(var := l)` is actually creating a new function that has all the same mappings as `s` except with `var` now mapped to `l`. Isabelle/HOL allows us to manipulate functions in the true mathematical sense where they are just sets (of ordered pairs), and in that way they are the reasoning analog of hash tables.

The final evaluation shows that when we update `a` with `imp_update` and we read its value back out of the state, `a` does have the modified value of `[1, 4, 3]`.

This answers our first question: destructive updates are such a pain to model in an FP language because FP only has the notion of mathematical functions which are pure and don't modify their arguments. It can be done, but it requires manually modeling state and variable references. This leads to all variable accesses being polluted with an extra step - the state must be consulted to get anything done.

It's this point that immediately leads to the answer to our second question: destructive updates are so simple in imperative languages because in them, state and references are **implicit**.

To dive into that, here's our initial C code again:

{% highlight c %}
int main() {
    int a[4] = {1, 2, 3};
    a[1] = 4;

    return 0;
}

{% endhighlight %}

and here's is the assembly code (ARM) from compiling[^fn3] it:

<pre>
	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 11, 0
	.globl	_main                           ; -- Begin function main
	.p2align	2
_main:                                  ; @main
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #64                     ; =64
	stp	x29, x30, [sp, #48]             ; 16-byte Folded Spill
	add	x29, sp, #48                    ; =48
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	adrp	x8, ___stack_chk_guard@GOTPAGE
	ldr	x8, [x8, ___stack_chk_guard@GOTPAGEOFF]
	ldr	x8, [x8]
	stur	x8, [x29, #-8]
	str	wzr, [sp, #12]
	adrp	x8, l___const.main.a@PAGE
	add	x8, x8, l___const.main.a@PAGEOFF
	ldr	q0, [x8]
	str	q0, [sp, #16]
	<strong>mov	w9, #4                   ; Move the value 4 into a register 
	str	w9, [sp, #24]            ; Store that value at memory location a[1]</strong> 
	adrp	x8, ___stack_chk_guard@GOTPAGE
	ldr	x8, [x8, ___stack_chk_guard@GOTPAGEOFF]
	ldr	x8, [x8]
	ldur	x10, [x29, #-8]
	subs	x8, x8, x10
	b.ne	LBB0_2
; %bb.1:
	mov	w8, #0
	mov	x0, x8
	ldp	x29, x30, [sp, #48]             ; 16-byte Folded Reload
	add	sp, sp, #64                     ; =64
	ret
LBB0_2:
	bl	___stack_chk_fail
	.cfi_endproc
                                        ; -- End function
	.section	__TEXT,__literal16,16byte_literals
	.p2align	2                               ; @__const.main.a
l___const.main.a:
	.long	1                               ; 0x1
	.long	2                               ; 0x2
	.long	3                               ; 0x3
	.long	4                               ; 0x4

.subsections_via_symbols
</pre>

This has all of the compiled assembly for completeness, but highlighted is a `mov` instruction followed by a `str` instruction. Recall that a "move" instruction (`mov`) places a value into a register, and a "store" instruction (`str`) takes a value in a register and writes it to a location in memory. These two instructions are what the statement `a[1] = 4` get compiled into, and hopefully at this point a light bulb is turning on: imperative programs assume an underlying CPU and memory. The instructions might be slightly different depending on the processor, but destructive updates are simply taking advantage of memory instructions that every modern CPU supports.

Maybe visual with memory diagram compared to source code?

Even though functional languages have to worry about executability at some point, the paradigm of FP exists without any assumption of an underlying machine since its semantics is simply the semantics of math. This brings us to the difference between reasoning and execution.

# Reasoning vs. Execution

While the line between them can seem blurry, reasoning and execution are different activities. Reasoning is logical thinking. Instead of blindly accepting a conclusion, we use reasoning to justify the steps of thought that were taken to reach it. But reasoning is abstract. Even infinite subjects, like the set of all even numbers greater than 9,000, can still be reasoned about - we know that all numbers in this set are greater than 5, for example. 

In contrast, execution is about running specific programs on specific machines. This is where implementation details such as instruction set architecture and word sizes have to be considered. A program might even have an infinite loop, as all interactive programs do, but we will still only practicaly execute it a finite number of times because we want to know the result of the program. For this reason, along with the practical limitations of physical hardware, execution is inherently finite, and we can only execute a subset of what we can reason about. This distinction is notable, because each programming paradigm is optimized for one activity at the expense of the other. We often say that functional programming is higher-level than imperative, with imperative being lower-level and closer to the machine. But this is only true when considering execution. 

FP is "closer to the metal" of pure reasoning, whereas imperative programming is higher-level reasoning. This is because, again, functional programming is based on the semantics of math, which is foundational and can be seen as the "assembly language" of reasoning. With respect to reasoning, imperative programming is more like a domain-specific language that can be "compiled" to math's semantics by explicitly modeling computer memory with state and variable references in mathematical terms (as we saw in our previous example).

Destructive array updates are the perfect example of this. The imperative code for our example is way more compact because it's written using an effective DSL. The CPU and memory state is abstracted away from the _syntax_, though it is still part of the semantics, i.e. what the program actually does. This is the hallmark of DSLs - they make expressing concepts in a particular domain more natural by leaving parts of it implicit.

So how does this affect the quality of "regular" programs?

Many people will passionately pick either paradigm depending on the domain that they work in. For example, operating system and video game developers pretty much always pick imperative languages, especially compiled ones, because maximal efficiency is an absolute requirement. Many enterprise applications require far less resources, so for these some people choose higher-level languages (wrt execution) like FP or even interpreted imperative languages since they can provide an easier programmer experience. This choice has many dimensions to it, so I'm not trying to oversimplify it, but quality is a huge part of the decision. We all want fast and correct programs that are easy for a team of programmers to create, but each domain is unique, and the importance of performance or correctness has different weights.

But all programs, no matter the paradgim, must execute on real hardware, and we must also reason about them to understand them. This means that, for the performance-critical applications, we still want to make guarantees about their behavior. For the less performance-critical applications, some parts of the system do end up suffering from performance problems, and we want to be able to optimize these critical paths when necessary as well. There are also cases of interest outside of these, for example graph algorithms are generally really easy to express in an imperative style and we might want to 

For all of these cases, the answer to me is not to focus on reasoning or execution separately, but to use them both, i.e. to reason about execution.

# Reasoning About Execution

> Before software can be formally reasoned about, it must first be represented in some form of logic.[^fn5]

Reasoning about software is thinking about how it will execute at runtime. As programmers, this is our primary job, trying to understand all of the possible executions that can happen. We want to be able to confidently make statements like "an array is never accessed outside of its bounds,"[^fn6] which is not always immediately obvious when the index is a dynamic value. Rather than work out a lengthy example, I just want to talk about a simple one since it involves a number of interesting techniques. Sticking with our destructive array update example from earlier, 


```
theorem    
  "valid 
    (λs. is_valid_w32 s a)
    (update_arr' a v)
    (λrv s. is_valid_w32 s a ∧
      s[ptr_add a 1] = v)"
  unfolding update_arr'_def
  apply(wp)
  apply(auto simp: fun_upd_def)
  done
end
```

garbage collector that handles memory management.A big example of that is garbage collection. 

Reasoning about programs is an activity that's limited to a programmer's brain. 

There are plenty of situations where a functional program 

While there are some reasoning techniques that don't technically rely on functional programming ([Hoare logic comes to mind](http://sunnyday.mit.edu/16.355/Hoare-CACM-69.pdf)), most fully formalized ones do. This is the case with proof assistants such as Isabelle/HOL, which I'm more partial to. When reasoning has to be automated, we choose a suitable base logic from which others can be embedded and encoded into.

That logic is never "imperative programming," because as shown, imperative programming is too high-level to serve as a foundation.

Fill in the blanks - make implicit explicit

# Reasoning About Execution

embedding

With these concepts outlined, how then should we reason _about_ execution? 

Given that they really aren't competing, they should actually be cooperating. FP is meant for reasoning about programs, and this is why the lambda calculus is the basis of so many verification efforts. It's simply the more elegant mathematical basis for computing, in contrast to the Turing machine. Turing machines are helpful for reasoning about certain aspects of computability, but the concept of terms and reduction in lambda calculus is truly intuitive - it pretty much amounts to the symbol manipulation taught in high school algebra class.

Look at languages like F*, where it's actually used as the base logic for other DSLs. Low* is one such DSL that makes reasoning about imperative code easier, and it offers a direct extraction to C code.

Proof assistants. bla bla.

# Thoughts

Again, my only point in bringing this up is to talk about quality. From that angle, the distinction between functional and imperative is moot, because programs must execute on real hardware, and we also must reason about them to understand them. We don't like to think about the bits and bytes of machines, but at some point those details tend to poke through whatever abstraction we create while trying to hide them. Take tail-recursion - recursion is the way to iterate in FP, and the immediate problem it causes is that it requires keeping the function stack state around throughout the entire recursion. If the recursion depth / number of iterations is large, the program runs out of stack space, i.e. a stack overflow occurs. 

We've known about this since the lat 70s, so FP languages generally know how to optimize a program in tail-recursive form so that the actual machine code run is the same as an imperative loop.

 As we said earlier, functional programs are higher-level from an execution perspective, but the only way for them to be practically usable is to use garbage collection and tail-recursion.

Thinking about example using AutoCorres: https://www.mail-archive.com/devel@sel4.systems/msg02412.html. MLton compiler not installing though.

Modes

Reasoning and execution are opposite ends of the same spectrum. Math can be used to reason about infinity, but only subset of that is able to be run on computer hardware. But the destination is what influences how we think about it. Here's what I mean - generally, we see FP as more abstract and higher-level than imperative programming. But, I think this is only when taking the POV of wanting to ultimately result in an executable program. After all, this is what programmers do - create runnable programs.

The difference comes when our desire is to reason about the program, that is to understand what it's going to do in all cases. This is the point of view taken when assessing the quality of a program. In order to do that, we have to have some explicit understanding of what the program does and what correctness means. In this direction FP is actually lower level, and imperative is higher level, because of the implicit assumptions that an imperative program makes that aren't present in the FP paradigm. 

In the destructive array update example, 

How are we able to comprehend infinity? I mean that in the literal sense, not dramatically or philosophically. Take this definition of even integers:

`even = { n ∈ int | n % 2 = 0 }`

This says that `even` is equal to the set of all `n` that are integers such that 2 divides `n`. Since there are an infinite number of integers, this too is an infinite set. But even though it's infinite, we can understand it conceptually

First, we'll define reasoning as "the act of thinking with logical rules." 

Math existed long before computers, and it is the fundamental tool of human reasoning[^fn4]. Mathematical reasoning exists in purely abstract space, with no limit on what be reasoned about. That's not an exaggeration, math can be used to understand completely infinite or nondeterministic structures. Take a predicate for expressing even numbers: 



There are infinitely many integers, and this set goes on forever, but we can still understand exactly what it means and even build other concepts on top of it.

Computers, on the other hand, are worried about executing programs. And part of that is executing programs quickly, because a program that you have to wait 10 years or perhaps even a lifetime to complete is not useful. 

The line gets blurry where they intersect. For example, consider tail-recursion in a functional program. Tail-recursion allows efficient compilation of a recursive function definition into an imperative loop. We're also seeing a resurgence of popularity in imperative languages supporting value semantics and other FP features, so the whole program doesn't have to be written in one paradigm.

Counterintuitively, and borrowing terms from each other's paradigm, this makes functional programming the "assembly language" of reasoning, and imperative programming a DSL for programming computer hardware. On the execution dimension, imperative languages are lower level and FP is higher level. On the reasoning dimension, FP is the basis whereas imperative is a layer on top of that.

The CPU + memory is an implementation of the semantics of the assembly language.

and I think the criticisms of it might extend from the fact that people want to reason at the higher and more practically-oriented level of the imperative DSL for Von Neumann CPUs.

A classic example of this is with the relational data model. The model itself is really just a semantic model - it governs the values that should be returned for certain operations, but that's it. That semantics is defined in terms of set theory, and the semantics is given at a high level. Here's the definition of a (natural) join from the original paper on the relational model:

```
R*S = {(a, b, c):R(a, b) ∧ S(b, c))}
```
"where R (a, b) has the value true if (a, b) is a member of R
and similarly for S(b, c)."

(this effectively says that the join of relations R containing and S )

This communicates the exact functionality of a join, but it does so by showing how to reason about a join. This set comprehension is not executable directly. 

But, have you ever inspected a query plan? A query plan shows how to actually carry a query out.

```
Limit  (cost=0.28..0.80 rows=2 width=57)
   ->  Nested Loop  (cost=0.28..1780.05 rows=6909 width=57)
         ->  Seq Scan on table_b  (cost=0.00..39.80 rows=980 width=8)
         ->  Index Scan using a_to_b_id_idx on table_a  (cost=0.28..1.66 rows=12 width=57)
               Index Cond: (a_id = table_b.id)
```

Execution is physical. Another way to look at this is that your brain is an interpreter for the language of math. For whatever reason, something like "is 5 in the range 0 < x < 15", we can determine instantly.

For imperative updates to work, variables have to be stored somewhere, and in the physical world that means the presence of hardware memory. The missing assumption from the first example is hardware memory, along with the ability to read from and write to it.

If we squint a little bit, we can see that with state, we're are effectively describing the presence of an underlying Von Neumann CPU. That is, This isn't some article bashing Von Neumann architectures, quite the contrary. These are what we have built and optimized to an incredible degree, and we owe our entire digital existence to them. 

From this point of view, the imperative paradigm is a domain-specific language for operating a Von Neumann computer, embedded within a functional language. This is certainly the point of view that proof assistants take. Isabelle/HOL uses a functional programming language as its language for describing logic, and so does Coq. While the lambda calculus and Turing machines both have their mathematical theories, it is the lambda calculus that is closer to everyday math - (a Turing machine requires the introduction of abstract concepts such as "head" and "tape" - these are not as foundational as functions, sets, and values.) Tape is memory

The idea of imperative memory updates is one interesting dimension to look at FP, because it highlights the misunderstanding that both camps have about it. I would say that beyond mutability vs. immutability, the central notion of FP is that it makes implicit assumptions explicit. There is simply no framework for introduction implicit anything, everything must be a mathematical value or function on values. Take something seemingly simple like an in-place array update, i.e.:

CPU as interpreter for instruction set.

Imperative programs are said to be buggier, with their shared mutable state a minefield of unintentional and intractable behavior. Functional programs, according to common wisdom, avoid all bugs with statelessness, purity, and equational reasoning. On a different dimension, functional programs are reported to be less efficient in general since they can't take advantage of mutable state for optimizations, whereas imperative programs are 

Example involving program counter.

FP depends on garbage collection, another example of how it 

Monad state update?

Recurrence relations - math's method of state

This makes projects like Project Everest and sel4 the most exciting to me, because they are absolutely uncompromising when it comes to performance. They do this by embracing the fact that programs are going to run on a Von Neumann CPU at the end of the day.

However, FP is often fiercely touted as directly leading to software of higher quality, and the oppsite is From that angle, it's worth talking about. Proponents of FP claim that the very act of using an FP design or language can get rid of whole classes of bugs. Its detractors scorn it or laugh it off as silly. When something keeps coming back though, I believe that's simply proof that there is something there, whether or not we understand it. Human intuition is like a statistical engine - while it can be wrong, it can also be right.

possible footnote: You could then search for advice on how to fix a stack overflow on Stack Overflow.

---
[^fn1]: We'll leave out other paradigms from this discussion, such as logic programming, acknowledging that FP and imperative aren't the only possible programming paradigms.

[^fn2]: The `list_update` function is then the same as [the implementation in the List Isabelle/HOL theory](https://isabelle.in.tum.de/library/HOL/HOL/List.html), so this is more or less how an update is implemented in pure FP.

[^fn3]: Compiled with `clang -S` on an M1 Macbook

[^fn4]: Here, I'm saying that math is a superset of logic for convenience. The difference has been debated [for quite some time](https://www.memoriapress.com/articles/logic-not-math/), but since math requires logical reasoning in the form of proofs it's simpler to refer to math instead of always saying "math and logic." I acknowledge this might be heretical.

[^fn5]: From [Automated proof-producing abstraction of C code](https://unsworks.unsw.edu.au/fapi/datastream/unsworks:13743/SOURCE02?view=true), David Greenaway's PhD's thesis.

[^fn6]: This is something that some dependently typed languages can check at compile-time which is certainly an interesting path to continue to research. It's not a silver bullet either, though, because of practical limitations of what types can be expressed and checked. This tends to come down to a matter of taste, and for me, the jury is still out on the practical utility of dependently typed languages, even though some amazing work has been done in that area. Suffice it to say, formal reasoning and verification can be done absolutely be done without them.