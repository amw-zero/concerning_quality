---
layout: post
title: 'Forward and Backward Reasoning in Proof Assistants'
tags: formal_methods
author: Alex Weisberger
---

Proof assistants are really fascinating tools, but the learning curve can be extremely steep. If you're a programmer by trade and not a mathematician, this curve can be even steeper, because it's not like programmers are doling out proofs left and right at work. One particular sticking point that I had trouble overcoming is the difference between forward vs. backward reasoning - proofs assistants support both.


# Forward Reasoning

When thinking about logic, we generally think about forward arguments which get built up from one statement to the next, in sequence. For example, let's make a logical argument about monitoring. We want to get an alert when our app goes down, and one way we know that the app is down is when a test user can't login and see the home page. The way to express that in logic is to say that the home page not loading implies that the app is down:

$$ HomePageDoesntLoad \implies AppIsDown $$

Implication is a useful thing to know, but it only tells us about the overall relationship and doesn't tell us whether the app is down right now or not. We want to know the current state so we can determine if we should page someone, and for that we can use one of the oldest rules in all of logic: modus ponens.

Modus ponens is also known as "implication elimination," which more accurately describes its behavior. It allows us to infer something about an implication, but the conclusion no longer contains one - the implication gets eliminated:


$$ \dfrac{P~~~~~~~P \implies Q}{ Q }$$


This is written out as an inference rule, which in this case means that if we know P is true, and we know that P implies Q, then we can infer that Q is also true. On top of the bar are the premises, and on the bottom is the conclusion which we can infer if the premises are true. The reason that this rule is so old is that it's just a formal description of common sense - if P implies Q, and we know P is true, _of course_ Q is true. That's what implies means.

In our monitoring context, we can take P to be "the home page doesn't load" and Q to be "the app is down," and by this rule we can conclude that the app is down if we actually observe the home page being unable to load. This is a forward argument - when an inference rule is taken from top to bottom.

Proof assistants almost always support forward reasoning. One way to do this in Isabelle is with the `frule` tactic:

```plaintext
lemma 
  assumes HomePageDoesntLoad 
    and "HomePageDoesntLoad ⟶ AppIsDown"
  shows "AppIsDown"
  using assms
  by (frule_tac P=HomePageDoesntLoad and Q="AppIsDown" in mp)
```

`mp` is the rule for modus ponens, which is defined like this[^fn1]:

```plaintext
lemma 
  assumes "P ⟶ Q"
    and P
  shows Q
  ...
```

`frule_tac` allows us to take a forward logical step if the premises are shown to be true. Since they're assumed here, they are true, and we prove `AppIsDown` in one step.

# Backward Reasoning

Proof assistants also allow us to work backwards from a goal. 

Let's take a look at a backward proof of our lemma:

```plaintext
lemma 
  assumes hp_load: HomePageDoesntLoad 
    and imp_appdown: "HomePageDoesntLoad ⟶ AppIsDown"
  shows "AppIsDown"
  apply(rule_tac P=HomePageDoesntLoad and Q=AppIsDown in mp)
  using imp_appdown
    apply(assumption)
  using hp_load
    apply(assumption)
  done
```

Here, instead of `frule_tac`, we use `rule_tac`, which applies a rule in a backward fashion. Instead of going from top to bottom in the rule, we replace the current proof goal with the premises in the top of the rule. This allows us to prove each one separately, which is one of the main benefits of backward rule application: we can more easily divide and conquer a complicated proof.

It works because an inference rule can be interpreted in two ways. As we said, the forward interpretation is: "we can conclude the bottom of the top premises are true." The backward interpretation is: "to prove the bottom, it suffices to prove the top premises." These are logically equivalent.

To dive in a bit more, we can look at the proof state after each step in the proof above. At the beginning of the proof, the goal is simply the final conclusion we want to show:

```plaintext
lemma 
  assumes hp_load: HomePageDoesntLoad 
    and imp_appdown: "HomePageDoesntLoad ⟶ AppIsDown"
  shows "AppIsDown"

goal (1 subgoal):
 1. AppIsDown 
```

Now we apply modus ponens backwards:

```plaintext
apply(rule_tac P=HomePageDoesntLoad and Q=AppIsDown in mp)

goal (2 subgoals):
 1. HomePageDoesntLoad ⟶ AppIsDown
 2. HomePageDoesntLoad
```

Instead of having to show `AppIsDown` directly, we now just have to show that `HomePageDoesntLoad ⟶ AppIsDown` and `HomePageDoesntLoad`. In a real proof, we'd have to figure out how to prove these independently, but here both of these are true by assumption so the rest of the proof just pulls in the appropriate one and applies it.

# Which One's Better?

The unfortunate answer is that there's no preferred direction, and we'll often want to use both. We can also use higher-level and more powerful tactics anyway, which abstract the underlying reasoning. This monitoring example is very trivial, and can be proven in Isabelle with a variety of one liners, like:

```plaintext
lemma 
  assumes HomePageDoesntLoad 
    and "HomePageDoesntLoad ⟶ AppIsDown"
  shows "AppIsDown"
  by (auto simp: assms)
```

Backward reasoning seems more natural many times, but this is likely because of the history of proof assistants: they were pretty much designed around backward reasoning and interactivity from the start. The line gets blurred with more recent developments like Isar, which is an Isabelle sublanguage for defining structured proofs. In Isar, individual steps might be proven in a backwards fashion, but the proof proceeds in a structured and forward manner. Isar proofs are almost always preferred because they more closely resemble pen-and-paper proofs, and bring the very relevant intermediate proof state to the foreground.

Here's one for the monitoring example:

```plaintext
lemma 
  assumes imp_appdown: "HomePageDoesntLoad ⟶ AppIsDown"
    and hp_load: HomePageDoesntLoad
  shows "AppIsDown"
proof (rule mp[where P=HomePageDoesntLoad and Q=AppIsDown])
  from imp_appdown show "HomePageDoesntLoad ⟶ AppIsDown" by assumption
  from hp_load show HomePageDoesntLoad by assumption
qed 
```

This pretty closely mirrors the backward proof from before, and that's because the structure of the proof is based on the backward application of `mp` by choosing `rule` and not `frule` in the `proof` command. But now the intermediate goals are visible, which gives the proof more structure. This is especially helpful for more complicated goals that can't be proven in a single step because each goal can be respectively built up via intermediate steps.

All this to say: the logical direction often changes throughout a proof in a proof assistant, and the same rules can be used both forwards and backwards. Knowing which direction is being used is crucial for understanding our proofs.

<hr>

[^fn1]: It's actually defined as an axiom, which means it's implicitly taken to be true, and it also uses the older-style Isabelle syntax which lists assumptions in brackets: `"⟦P ⟶ Q; P⟧ ⟹ Q"`. But this is equivalent to the `assumes ... shows ...` syntax being used here.