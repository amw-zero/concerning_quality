---
layout: post
title: 'Quality and Paradigm: The Assembly Language of Reasoning and the Domain-Specific Language of the Machine'
tags: formal_verification functional_programming imperative_programming
author: Alex Weisberger
---

Does programming paradigm affect the ultimate quality of software? I generally avoid stoking the eternal flame war of functional vs. imperative programming, but it has to be discussed since there are so many repeated statements of fact about which one leads to higher-quality programs[^fn1]. The arguments primarily exist along two dimensions: correctness and performance. Summing them up, functional programs are more correct but slow, and imperative programs are buggy but fast. Of course, there are counterexamples to each of these statements, but this is a fair generalization overall.

Thinking of it as a competition isn't helpful though, because each paradigm has a different purpose: FP is optimized for mathematical reasoning, whereas imperative programming is fundamentally about manipulating computer hardware. It's this difference between reasoning and practical execution that suggests that the highest quality software actually requires utlizing both paradigms: no matter what level we write code at, we must be able to reason about how that code runs at the level of real-world machines. This is what allows us to achieve the holy grail of quality: fast and correct software.



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

It's this point that immediately leads to the answer to our second question: destructive updates are so natural in imperative languages because in them, state and references are **implicit**.

To dive into that, here's our initial C code again:

{% highlight c %}
int main() {
    int a[4] = {1, 2, 3};
    a[1] = 4;

    return 0;
}

{% endhighlight %}

and here's is the assembly code (ARM) that results from compiling[^fn3] it:

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

Even though functional languages have to worry about executability at some point, the paradigm of FP exists without any assumption of an underlying machine since its semantics is simply the semantics of math. This brings us to the difference between reasoning and execution.

# Reasoning vs. Execution

While the line between them can seem blurry, reasoning and execution are different activities. Reasoning is logical thinking. Instead of blindly accepting a conclusion, we use reasoning to justify the steps of thought that were taken to reach it. But reasoning is abstract, and there is no difference in cost to your mind between reasoning about tiny fractions or gargantuan numbers. Even infinite subjects, like the set of all even numbers greater than 9,000, can still be reasoned about - we know that all numbers in this set are greater than 5, for example.

In contrast, execution is about running specific programs on specific machines. This is where implementation details such as instruction set architecture and word sizes have to be considered, and also where time and space really matter. A program might even have an infinite loop, as all interactive programs do, but we will still only practicaly execute it a finite number of times because we want to know the result of the program in our lifetime. For this reason, along with the practical limitations of physical hardware, execution is inherently finite, and we can only execute a subset of what we can reason about. This distinction is notable, because each programming paradigm is optimized for one activity at the expense of the other. 

We often say that functional programming is higher-level than imperative, with imperative being lower-level and closer to the machine. But this is only true when considering execution. FP is "closer to the metal" of pure reasoning, whereas imperative programming is higher-level reasoning. This is because, again, functional programming is based on the semantics of math, which is foundational and can be seen as the "assembly language" of reasoning. With respect to reasoning, imperative programming is more like a domain-specific language that can be "compiled" to math's semantics by explicitly modeling computer memory with state and variable references in mathematical terms (as we saw in our previous example).

Destructive array updates are the perfect example of this. The imperative code for our example is way more compact because it's written using an effective DSL. The CPU and memory state are abstracted away from the _syntax_, though they are still part of the semantics, i.e. what the program actually does. This is the hallmark of DSLs - they make expressing concepts in a particular domain more natural by leaving parts of it implicit.

So FP and imperative programming mainly differ in their acknowledgement of computer hardware and their adherence to mathematical semantics. FP is programming with reasoning, and imperative programming is programming with a machine. They intersect at the aforementioned holy grail of formally verified, fast executable programs. For that, we need to be able to reason about imperative programs, i.e. reason about execution on a real computer.

# Reasoning About Execution

> Before software can be formally reasoned about, it must first be represented in some form of logic.[^fn4]

We saw the difficulty with destructive array updates in a functional language. Since FP is closer to pure reasoning, this dificulty directly translates to reasoning about code in a compiled imperative language such as C. There's tons of research about how to best reason about imperative programs, but I'll highlight one approach here: translating code into a logic as a shallow embedding and reasoning via Hoare triples. In this case, the logic is higher-order logic - the flavor that Isabelle/HOL implements. Once we're in the logic, we can determine the truth or falsity of statements with pure reasoning.

Let's slightly modify our example so that it operates on arbitrary arrays instead of the one hardcoded one:

{% highlight c %}
// File: array_update.c
void update_arr(unsigned int arr[], unsigned int v) {
    arr[1] = v;
}

unsigned a[3] = {1,2,3};

int main(void) {
    update_arr(a, 4);

    return 0;
}
{% endhighlight %}

The behavior of `update_arr` is very simple: it is correct if the passed in array is updated at index 1 with the value `v`. 

Let's pull it into Isabelle for reasoning:

```
theory ImperativeReasoning

imports AutoCorres.AutoCorres

begin

install_C_file "array_update.c"
autocorres[heap_abs_syntax] "array_update.c"

context test begin

definition "array_mem_valid s a = (is_valid_w32 s a ∧ is_valid_w32 s (ptr_add a 1))"

theorem
  "validNF
    (λs. array_mem_valid s a ∧ s = s0)
    (update_arr' a v)
    (λ_ s. (array_mem_valid s a) ∧ s = s0[(ptr_add a 1) := v])"
  unfolding update_arr'_def and array_mem_valid_def
  apply(wp)
  apply(auto simp: fun_upd_def)
  done
```

There's actually quite a bit going on in this short example, so let's unpack it. First, this is using [AutoCorres](https://github.com/seL4/l4v/blob/master/tools/autocorres/README.md), which is a tool for reasoning about C code via an Isabelle/HOL representation. The `install_C_file` and `autocorres` commands parse and translate the C code of our example, with `autocorres` performing several abstractions and optimizations to the code that greatly simplifies reasoning about it in Isabelle. For what we're talking about, the most relevant abstraction is that the concept of a _heap_ is added to the translated C code. The heap is a model of the underlying memory that the C program interacts with via pointers, arrays, mallocs, or any other memory-manipulating constructs. Because we are going to be reasoning about the program, the memory must be modeled explicitly, as we did in the functional destructive array update code. AutoCorres has a more advanced design of the heap, which you [can read more about in David Greenaway's PhD thesis](https://trustworthy.systems/publications/nicta_full_text/8758.pdf). I recommend at least reading the chapter about heap abstraction, it's pretty digestible and very informative.

Next, let's unpack the theorem that we've constructed:

```
theorem
  "validNF
    (λs. array_mem_valid s a ∧ s = s0)
    (update_arr' a v)
    (λ_ s. (array_mem_valid s a) ∧ s = s0[(ptr_add a 1) := v])"
```

In math, a theorem is just a statement that is proven to be true, and the primary way that we can reason about anything is to come up with some such statement and try and evaluate its truth or accuracy. One of the most common ways of expressing statements about an imperative program is with Hoare logic, which is what we're doing in this theorem. `validNF p c q` is a function that represents a Hoare triple, which is a specification of what a program or part of a program should do in order to be correct. It takes three arguments:

* `p` is a precondition. This must be true before executing the command `c`.
* `c` is a command. This is some program statement or set of statements that we're looking to reason about.
* `q` is a postcondition. This must be true after `c` is executed.

Our precondition is: `(λs. array_mem_valid s a ∧ s = s0)`, where we defined `array_mem_valid s a` as `is_valid_w32 s a ∧ is_valid_w32 s (ptr_add a 1)`. The precondition is actually a function where the argument `s` is the current state of the program, which includes the current heap state. `is_valid_w32 s a` checks that a pointer `a` in state `s` is "valid", where validity is pointer validity as described by the semantics of C. For example, for a pointer to be valid, it must not be NULL. The intention here is to guarantee memory safety - if for any reason the starting address of `a` has become NULL, this precondition is not met and `update_arr` would fail if it were called. We also add the condition that `s = s0` which is just so that we can reference this initial state in the postcondition later on, a common pattern when using Hoare triples.

Then, our command is: `update_arr' a v`. This is just calling the translated `update_arr` function with arbitrary arrays `a` and values `v`.

Finally our postcondition is: `λ_ s. (array_mem_valid s a) ∧ s = s0[(ptr_add a 1) := v]`. This is a function whose first value we'll ignore (`_`), and whose second value is again the program state, but after executing the command. We again check for pointer validity, ensuring that `update_arr'` is memory safe. The second part of the condition, `s = s0[(ptr_add a 1) := v]`, says that the only change to the program state is that address `a + 1` is now set to the `v` passed into `update_arr'`. This ensures that no other random memory updates have occurred.

The "NF" in `validNF` stands for "non-failure" which means that we are also saying that, as long as the precondition is met, `update_arr'` will execute to termination with no failures, known as "total correctness." A more traditional way of representing Hoare triples is by writing: `{P}C{Q}`, and it can even be written this way in Isabelle using custom syntax rules, but we wrote it using a plain function call to show that there's no magic going on under the hood. Here are the definitions that make up `validNF`: 

```
validNF P f Q ≡ valid P f Q ∧ no_fail P f
valid P f Q ≡ ∀s. P s ⟶ (∀(r,s') ∈ fst (f s). Q r s')
no_fail P m ≡ ∀s. P s ⟶ ¬ (snd (m s))
```

The definitions themselves aren't exactly important for this exampe, but I'm sharing them to show that this theorem amounts to an equation, and we ultimately want to prove that the left hand and right are equivalent.

To recap: we translated our actual C code into Isabelle/HOL, and then we wrote a Hoare triple which specifies what it means for `update_arr'` to be correct. If this call to `validNF` can be proven to be true, then `update_arr'` can be taken to be correct with respect to this specification. With a few proof statements, we do get Isabelle to accept this statement as proven:

```
unfolding update_arr'_def and array_mem_valid_def
apply(wp)
apply(auto simp: fun_upd_def)
done
```

`AutoCorres` provides the proof tactic `wp` which converts a Hoare triple into the weakest precondition needed to be satisfied in order for the postcondition to hold, an [old trick from Djikstra](https://www.cs.utexas.edu/users/EWD/transcriptions/EWD04xx/EWD472.html) that allows us to reduce a Hoare triple into a single logical formula that we need to prove. One absolutely invaluable benefit of moving from C to higher-order logic for reasoning is that we can use functional programming with a bit of added logic on top to define the semantics of a program along with Hoare triples about it. Once we do that, we can prove all kinds of things using only term simplification, which is what the `unfolding update_arr'_def and array_mem_valid_def` and `apply(auto simp: fun_upd_def)` lines mean - the proof is literally just a transformation of the code until the left hand side of an equation exactly matches the right hand side. This is only possible because of the heap being explicitly modeled, and couldn't be done by using the imperative code directly.

# Outro

By using each paradigm for what it's best at, we can formally reason about execution all the way down to the machine level when necessary. That isn't to say that we should only reserve FP for reasoning within a proof assistant. There are plenty of optimizations out there that can translate FP code into efficient machine code, the classic example being tail-call elimination. But, sometimes, embracing the machine is the right call and can lead to unparalleled performance improvements. There are also times where imperative code is just inherently more clear, with nothing to do with performance. As they say, choose the right tool for the right job.

Understanding the strengths of each paradigm, though, rather than seeing either as a one-size fits all solution to all of software's problems is the key to determining which one is right and when.

---
[^fn1]: We'll leave out other paradigms from this discussion, such as logic programming, acknowledging that FP and imperative aren't the only possible programming paradigms.

[^fn2]: The `list_update` function is then the same as [the implementation in the List Isabelle/HOL theory](https://isabelle.in.tum.de/library/HOL/HOL/List.html), so this is more or less how an update is implemented in pure FP.

[^fn3]: Compiled with `clang -S`

[^fn4]: From [Automated Proof-producing Abstraction of C Code](https://unsworks.unsw.edu.au/fapi/datastream/unsworks:13743/SOURCE02?view=true), David Greenaway's PhD's thesis.
