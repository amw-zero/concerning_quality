---
layout: post
title: Why Quality?
author: Alex Weisberger
---

First thing's first: why should we care about the quality of software? 

Does it matter?[^fn1] The answer, like all answers, is that it completely depends on the context. Software is vastly diverse, and not all applications require the same level of quality and reliability. The most obvious litmus test is "will people die if the application fails to perform its job?" That isn't the only dimension to consider, though. For example, people are very sensitive to mistakes made with their money. Our time is precious, our money is earned, and we expect our banking software to work correctly.



Errors are themselves contextual. If a UI button is mistakenly released with the wrong color, it might not cause outrage in the customerbase or cost the company money. Color can be aesthetic, and while aesthetics are important, they're fairly easy to fix and generally don't cause harm when they're wrong. However, color can also convey semantic meaning. Consider a legend, where color can be used to distinguish between categories. It would be extremely frustrating if a navigation application mistakenly displayed a traffic value as green (low traffic) instead of red (high traffic). Within the same application, a failure to display the correct colors can be totally benign or very disappointing depending on the use case.

This means that at the highest level, quality is about people, their feelings, and their expectations. There's no such thing as inherent correctness of software, only the satisfaction of expectations. So quality is much more than just testing, much more than just measured uptime. It is being truly compassionate toward customers by understanding their expectations and ensuring that they are met.

We should care about software quality if we care about our customers.

## On the Importance of Expectations

Commerce and business are founded on expectations. Value is simply the monetary amount that someone is willing to pay to for a particular expectation to be met. Again, that expectation is contextual. When we buy a car, for example, we are perfectly fine with repairing tires and alternators at the expected frequency. We are not fine, however, when we have to make three trips to the mechanic within a month of buying the car.  In the US, we have a term for cars that have more problems than expected. Such a car is called a _lemon_, and it's a big enough problem that we actually have an [area of legislation](https://en.wikipedia.org/wiki/Lemon_law) devoted to protecting consumers who have purchased them.

No one likes getting a lemon.

To call the meeting of consumer expectations "important" is actually an extreme understatement to me - it's the sole purpose of a business. Why would someone continue to pay for something that isn't providing them the value that they expected in return? This is where it gets murky, because a piece of software often performs so many individual functions, and a large percentage of them may in fact work as expected. However, it's pretty safe to say that some subset of functions does not work in every piece of software. This is just accepted in the industry, as evidenced by the flippancy with how we talk about bugs. Again, that's not to say that software should be perfect, but I think our collective tolerance for bugs is way too low.

Here's a common joke:

_A mechnical engineer, an electrical engineer, and a software engineer are riding in a car. The car breaks down._

_The mechanical engineer says, "Don't worry. I'll pop the hood and take a look at the engine."_

_The electrical engineer says, "While you do that, I'll take a look at the battery and wiring."_

_The software engineer says, "Why don't we just get out of the car and get in again?"_

Funny, but unfortunately rooted in truth.

Maybe the users are ok with "turning it off and on again"[^fn2]. If so, no problem. But I encounter people all the time who are sitting at work, sighing in frustration at a computer that either keeps crashing or freezes before they're done checking someone out. Sometimes it's a performance issue. Sometimes it's a typo in the code that wasn't caught. The point is, users of software don't see it as different than any other product on the planet, they just want it to work. And when they were sold something that doesn't, that is a violation of their trust.

There's two ultimate outcomes when customer expectations aren't met. First, after they've had enough, they simply find a competitor and switch to their product. Broken promises devalue a software product, and it's only a matter of time before this gets reflected on the balance sheet. 

The second outcome is the one I'm more worried about. There isn't always a suitable competitor, or sometimes the software is integral to a customers' business and is too expensive to migrate off of. In this case, the customers feel powerless and grow to resent the product, but they never actually leave. This seems fine in the short term, but in the long term devalues any future product that a company might want to create or any upsells that they'd like to pitch to existing customers.

Either way, a lack of quality will ultimately affect the earning potential of a company. Beyond that, it wastes an enormous amount of people's time by promising value that does not get delivered. Because of this, I think managing customer expectations should be the top priority of a software project.

<hr>

The question of whether or not we should care about software quality depends on our own values as software creators, as well as the expectations of the customers of the product. These are the variables that we should be thinking about when running a project. No matter what, we should understand the customer expecations, because a failure to do so will result in money lost and dissatisfied users in one way or another. As long as people remain at the center of software creation and consumption, quality should be right there with it.

<hr>

[^fn1]: I definitely think it matters, but it's a little more complicated than that.

[^fn2]: As seen on [The IT Crowd](https://www.youtube.com/watch?v=p85xwZ_OLX0)
