---
layout: post
title: 'Quality and Paradigm: The Assembly Language of Reasoning and the Domain-Specific Language of Computer Hardware'
tags: formal_verification functional_programming imperative_programming
author: Alex Weisberger
---

Does programming paradigm affect the ultimate quality of software? I generally avoid stoking the eternal flame war of functional vs. imperative programming, but it has to be discussed since there are so many repeated statements of fact about which one leads to higher-quality programs[^fn1].  The arguments primarily exist along two dimensions: correctness and performance. Summing them up, functional programs are correct but slow, and imperative programs are buggy but fast. Of course, there are counterexamples to each of these statements, but this is a fair generalization overall.

Thinking of it as a competition isn't helpful, though, because each of these paradigms is meant for something different: FP is optimized for pure logical reasoning, whereas imperative programming is fundamentally about manipulating available computer hardware. It's this difference between reasoning and practical execution that suggests that the highest quality software actually requires utlizing both paradigms at some point. It might be wishful thinking, but maybe there is no war after all.



# Destructive Array Updates

Let's use destructive array updates as a backdrop for analyzing the difference in strengths between the FP and imperative styles. We'll use C for the imperative example since it provides an easy way to look at assembly instructions, which will be useful later on:

{% highlight c %}
int main() {
    int a[4] = {1, 2, 3};
    a[1] = 4;

    return 0;
}

{% endhighlight %}

In the imperative style, updating the value at index 1 in `a` mutates `a`, meaning printing `a` afterwards would show `[1, 4, 3]`. The 2 is gone, and the update is destructive. This is a notoriously difficult example for FP to handle, which leads to its detractors to (justifiably) criticize it. How can a paradigm be considered serious if it can't handle one of the most common programming techniques there is?

This begs two questions: 

1. What exactly is difficult about modeling an array in FP?
2. Why is it so convenient in an imperative language? 

To look into #1, here's a first attempt at modeling the above imperative code in an FP style[^fn2]:

```
fun update :: "'a list ⇒ nat ⇒ 'a ⇒ 'a list" where
"update [] i v = []" |
"update (x # xs) i v =
  (case i of 0 ⇒ v # xs | Suc j ⇒ x # list_update xs j v)"

definition "fp_list = [1, 2, 3::int]"

value "update fp_list 1 4" (* Returns [1, 4, 3] *)
value "fp_list" (* Returns [1, 2, 3] *)
```

We use a list to model an array since we can represent a list as a recursive datatype directly, e.g. `(Cons 1 (Cons 2 (Cons 3 Nil)))`. We have an `update` function which uses recursion and pattern matching on the list values to construct the correct value from scratch: `update fp_list 1 4 = [1, 4, 3]`. However, this function does not have the semantics of the array update because `fp_list's` value remains unchanged even though it is passed as an argument to `update`. The value returned by `update` is not connected to or tied to the value of `fp_list` in any way, and this is because that is simply the semantics of mathematical functions.

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

Our new function, `imp_update`, does have the destructive semantics we're looking for. In order to get it, we introduce the ability to reference a value by name. We do this by modeling state as a function from variable names to values (with the only values we can have being lists of integers to keep things simple). Then, instead of operating on values directly, we must read from and write to this state by specifying the referred variable's name - in this case `a`. It's worth calling out that in `write_state`, the syntax `s(var := l)` is actually creating a new function that has all the same mappings as `s` except `var` now maps to `l`. This is because Isabelle/HOL allows us to manipulate functions in the true math sense where they are just sets.

The final evaluation shows that when we update `a` with `imp_update` and we read its value back out of the state, `a` does have the modified value of `[1, 4, 3]`.

This answers our first question: destructive updates are such a pain to model in an FP language because FP only has the notion of mathematical functions which are pure. It can be done, but it requires manually modeling state and variable references. It also leads to all variable accesses being polluted with an extra step - the state must be consulted.

It's this point that immediately leads to the answer to our second question: destructive updates are so simple in an imperative language because state and references are **implicit**.

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

Even though functional languages have to worry about executability at some point, the general paradigm of FP exists without any such assumption.

This brings us to the difference between reasoning and execution.

# Reasoning vs. Execution

For imperative updates to work, variables have to be stored somewhere, and in the physical world that means the presence of hardware memory. The missing assumption from the first example is hardware memory, along with the ability to read from and write to it.

If we squint a little bit, we can see that with state, we're are effectively describing the presence of an underlying Von Neumann CPU. That is, This isn't some article bashing Von Neumann architectures, quite the contrary. These are what we have built and optimized to an incredible degree, and we owe our entire digital existence to them. 

From this point of view, the imperative paradigm is a domain-specific language for operating a Von Neumann computer, embedded within a functional language. This is certainly the point of view that proof assistants take. Isabelle/HOL uses a functional programming language as its language for describing logic, and so does Coq. While the lambda calculus and Turing machines both have their mathematical theories, it is the lambda calculus that is closer to everyday math - (a Turing machine requires the introduction of abstract concepts such as "head" and "tape" - these are not as foundational as functions, sets, and values.) Tape is memory

Counterintuitively, and borrowing terms from each other's paradigm, this makes functional programming the "assembly language" of reasoning, and imperative programming a DSL for computer hardware.


and I think the criticisms of it might extend from the fact that people want to reason at the higher and more practically-oriented level of the imperative DSL for Von Neumann CPUs.

# Reasoning About Execution

Given that they really aren't competing, they should actually be cooperating. FP is meant for reasoning about programs, and this is why the lambda calculus is the basis of so many verification efforts. It's simply the more elegant mathematical basis for computing, in contrast to the Turing machine. Turing machines are helpful for reasoning about certain aspects of computability, but the concept of terms and reduction in lambda calculus is truly intuitive - it pretty much amounts to the symbol manipulation taught in high school algebra class.

Look at languages like F*, where it's actually used as the base logic for other DSLs. Low* is one such DSL that makes reasoning about imperative code easier, and it offers a direct extraction to C code.

Proof assistants. bla bla.

# Thoughts

The idea of imperative memory updates is one interesting dimension to look at FP, because it highlights the misunderstanding that both camps have about it. I would say that beyond mutability vs. immutability, the central notion of FP is that it makes implicit assumptions explicit. There is simply no framework for introduction implicit anything, everything must be a mathematical value or function on values. Take something seemingly simple like an in-place array update, i.e.:

CPU as interpreter for instruction set.

Imperative programs are said to be buggier, with their shared mutable state a minefield of unintentional and intractable behavior. Functional programs, according to common wisdom, avoid all bugs with statelessness, purity, and equational reasoning. On a different dimension, functional programs are reported to be less efficient in general since they can't take advantage of mutable state for optimizations, whereas imperative programs are 

Example involving program counter.

FP depends on garbage collection, another example of how it 

Monad state update?

Recurrence relations - math's method of state

This makes projects like Project Everest and sel4 the most exciting to me, because they are absolutely uncompromising when it comes to performance. They do this by embracing the fact that programs are going to run on a Von Neumann CPU at the end of the day.

However, FP is often fiercely touted as directly leading to software of higher quality, and the oppsite is From that angle, it's worth talking about. Proponents of FP claim that the very act of using an FP design or language can get rid of whole classes of bugs. Its detractors scorn it or laugh it off as silly. When something keeps coming back though, I believe that's simply proof that there is something there, whether or not we understand it. Human intuition is like a statistical engine - while it can be wrong, it can also be right.

---
[^fn1]: We'll leave out other paradigms from this discussion, such as logic programming, acknowledging that FP and imperative aren't the only possible programming paradigms.

[^fn2]: The `list_update` function is then the same as the implementation in the List Isabelle/HOL theory, so this is more or less how an update is implemented in pure FP.

[^fn3]: Compiled with `clang -S` on an M1 Macbook