---
layout: post
title: 'Underspecification: The Blind Spot of Formal Verification'
tags: formal_verification
author: Alex Weisberger
---

As people, we like to be right, and we also want to avoid the effort of _proving_ that we're right. So we often resort to logical fallacies to take shortcuts and strong-arm people into believing us. One such logical fallacy is an ["appeal to authority"](https://en.wikipedia.org/wiki/Argument_from_authority) - you simply reference someone or thing that is considered to be an expert, and voilá - now you are right!

The reason it's a logical fallacy is that even smart people make mistakes. Or, even more importantly, smart people can have ill-intent - what better way to use social capital than to convince your followers to buy your new book and pay for your next vacation? That's why papers should be peer-reviewed. That's why we reproduce empirical experiments. And that's why should always have healthy skepticism and evaluate an argument for ourselves.

Formal verification is often presented as an appeal to authority. This progam was _formally verified_, so please stop asking me if there are any bugs! Well, there are simply no silver bullets out there, and formal verification is certainly not one of them because of a very serious blind spot: the possibility of underspecification.


# Specification and Underspecification

Formal verification implicitly means "verification against a specification," and this specification is where the blind spot lies. What if we simply didn't specify the right thing? I say this all the time: computer programs are friggin complicated, for lack of a better term. Describing all of the subtleties of behavior in a manageable way is Sisyphean - forget one hyper-specific semantic fact, and your description is incorrect, but it can be so subtle that it's not even noticed until an equally hyper-specific scenario presents itself during real program usage. 

The most interesting example of this is something that I've taken to calling underspecification (I am unaware of another commonly used term for it). Underspecification is the omission of an important behavior or property such that the implementation can be verified to fully meet its spec, but it doesn't fully work as epected when actually used. Cue the best quote by Donald Knuth: "Beware of bugs in the above code; I have only proved it correct, not tried it."

But it is simply something we have to acknowledge about the end goal of testing and verification: we can only verify against our knowledge of what the code _should_ do.

We will look at a more realistic example, but to cut to the chase a little quicker, consider the specification of a `sort` function:

~~~
function sort(array: number[]): number[] {
  // ... 
}
~~~
{: .language-typescript}

`sort` should:
- accept an array of numbers
- return an array of numbers in sorted order

Easy right?!

Well, what if `sort([3,2,1])` returns `[1,3]`? Is that in conflict with anything about this specification? It is not, and we need to strengthen the spec in order to prevent this:

`sort` should:
- accept an array of numbers
- return an array of numbers in sorted order
- **and the returned array should be a permutation of the input array**

Of course the last statement about the permutation is obvious after you see it, and of course it's impled when we said "return an array of numbers in sorted order." But "formal" in formal specification and verification isn't talking about a dress code, it's referring to the fact that 

# A Web Application Example

Here's a more realistic example since I think sort functions are silly to analyze.

Underspecification is the one error that cannot be tested for. To test for it, we would have to teach a computer how to read minds and / or understand the higher-level goal of an application. It's also the main flaw of formal specification fand verification, so it's important to understand.




I just want to stress how many best practices do not address this problem:

* Using a repository pattern to remove the database from unit tests does not catch this
* Measuring code coverage would not alert you of this
* Formally proving ahead of time does not prevent this

There is simply no way to deal with this ahead of time, which is the frustrating thing about it, and why we especially need to keep it in the back of our minds.





Deal connections example (CRM):

deal connection exists if:

a late stage deal exists with the same tenant (customer) as the deal

Bug was: Forgot to only consider deals other than the current one. Otherwise

Cases:

1) given 2 connections with the tenant, then true

2) given no connections, then false

3) ? given 1 connection with the tenant, one without, then true

# Leftover

Example of division by 0 in proof of 1 + 1 = 2 (principle of explosion?)

Like the old South Park business plan:

Phase 3: Profit.

I think formal verification is often used as an appeal to authority. "This software is formally verified. Checkmate."

Well, like everything else, it's not that simple. The sel4 OS is formally verified, but they at least temper their results with reality: https://docs.sel4.systems/projects/sel4/frequently-asked-questions.html#does-sel4-have-zero-bugs.
