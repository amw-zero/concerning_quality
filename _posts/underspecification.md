---
layout: post
title: 'Underspecification'
tags: testing
author: Alex Weisberger
---

Underspecification is the one error that cannot be tested for. To test for it, we would have to teach a computer how to read minds and / or understand the higher-level goal of an application. It's also the main flaw of formal specification and verification, so it's important to understand.

People like to be right. And, people also don't want to go through the effort to _prove_ that they're right, so they often resort to logical fallacies to take shortcuts to strong-arm people into believing them. One such logical fallacy is an "appeal to authority" - you simply reference someone or thing that is thought to be an expert, and voi la - now you are right!

Like the old South Park business plan:

Phase 3: Profit.

I think formal verification is often used as an appeal to authority. "This software is formally verified. Checkmate."

Well, like everything else, it's not that simple. The sel4 OS is formally verified, but they at least temper their results with reality: https://docs.sel4.systems/projects/sel4/frequently-asked-questions.html#does-sel4-have-zero-bugs.

Deal connections example (CRM):

deal connection exists if:

a late stage deal exists with the same tenant (customer) as the deal

Bug was: Forgot to only consider deals other than the current one. Otherwise

Cases:

1) given 2 connections with the tenant, then true

2) given no connections, then false

3) ? given 1 connection with the tenant, one without, then true



