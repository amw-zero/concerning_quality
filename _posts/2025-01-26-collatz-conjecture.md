---
layout: post
title: Branch Coverage Won't Prove The Collatz Conjecture
tags: testing
author: Alex Weisberger
---

The Collatz conjecture is the prime example of the limitations of thinking in terms of branch coverage. It can be written as a recursive function in 5 lines of code with only three branches. That's great, except we have no idea if it's true or not, and no amount of tests can prove either way.


Here's the code for generating the Collatz process:

```typescript
function collatz(n: number): boolean {
    if (n === 1) {
        return true;
    }

    return n % 2 === 0 ? collatz(n / 2) : collatz(3 * n + 1);
}
```

It's quite simple, by almost any metric. Just a couple of conditionals, and some plain arithmetic. The conjecture is that this _always_ returns true: no matter the starting number, all paths should end at 1, says Collatz.

There's only a few lines of code. Let's just test all the branches. To make this a little more explicit, let's unwind the ternary into an if-else:

```typescript
function collatz(n: number): boolean {
    if (n === 1) {
        return true;
    }

    if (n % 2 === 0) {
        return collatz(n / 2)
    } else {
        return collatz(3 * n + 1);
    }
}
```

We only need 2 test cases to hit all 3 branches: n=2, and n=3. Here's the sequence of `n` values that result in each case, just to get a feel for how the state progresses:

```plaintext
n=2 -> n=1 ==> true
n=3 -> n=10 -> n=5 -> n=16 -> n=8 -> n=4 -> n=2 -> n=1 ==> true
```

That was easy. All the branches are covered. There's just one problem: since it was proposed in the 1930s, the entirety of the math community has been unable to prove this true or not. We don't know if this is just a pattern up to some gigantic value of n, after which it breaks down, or if it's the real deal and we can finally watch it grow up into a real theorem. We simply don't know for sure if it's _always_ true, or even within what bounds it is true. The issue is that the state oscillates. If we could show that every iteration of the recursion produced a smaller value, then we'd be sure that we'll always get down to 1. But when n is odd, we go _up_. The progress is inconsistent. It, pretty surprisingly given its apparent simplicity, completely eludes our species.

Look back at the above test cases and how they create sequences of `n` values. Sequences like this are what software behavior boils down to. A program is really two things: its code, along with the set of all behaviors that it produces. Branch coverage is a statement about the code, but it doesn't touch the full breadth of the runtime behavior of the program. And the runtime behavior is what determines correctness.

This is why a tiny little function can lead to an unknowable question. There are lots of numbers, so lots of possible sequences of `n`, and in this case the code branches keep getting revisited until the program terminates. That is, _if_ it terminates.

Branch coverage will get a small glimpse of your code's behavior, but it isn't enough to prove the Collatz conjecture.