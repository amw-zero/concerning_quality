---
layout: post
title: 'Simulating Some Queues'
tags: performance
author: Alex Weisberger
---

System performance boils down to the timing behavior of various interacting queues. Queues are one of those incredibly simple but powerful concepts, but they have some unintuitive or non-obvious behavior when only thinking about them mathematically. Simulating queueing scenarios gives us a better picture about how queues operate in practice.


# The Unit Queue

Let's introduce the simplest possible queue as a reference point, which we'll call the unit queue. Requests arrive once per second, and each request takes one second to process. There's only one processor that services requests. Here are some quick definitions about the operations of this queue:

- **Arrival Rate**: the rate that requests come into the queue. Here, it is 1 / second.
- **Processing Time**: the time it takes to process a request. Here, it's 1 second.
- **Wait Time**: the amount of time a request waits after arrival and before processing begins. Here, the wait time for all requests is 0.
- **Latency**: the total time it takes to process a request after arrival. Here, it's 1 second.
- **Active Request**: a request that's currently being processed.
- **Queued Request**: a request that's waiting to be processed after arrival.
- **Queue Length**: the number of queued requests. Here, it's always 0.

This queue is in an equilibrium state: as soon as a request is done being processed, a new one comes in. And before the next one comes in, the current request has enough time to complete. This means that a request never has to wait to be processed, and it begins processing as soon as it comes in. Because of this, the queue length is always 0 and never grows.

# Discrete Event Simulation

This won't be a deep dive into discrete event simulation, but it helps to know a few things about it to understand the data that we're generating in our simulations. You can read more [in the SimPy docs](https://simpy.readthedocs.io/en/latest/).

The basic idea is that we emit events for system changes, and the system is assumed to be in the same state between events. Because of this, we can "fast forward" time by only considering the events and not waiting for time to pass. It's another manifestation of the state machine model of a system, only here we can keep track of the duration of each transition instead of only worrying about the states that changed.

In the case of a queue, we'll broadcast one event for each of:

* request arrival
* processing start
* processing end

With just these events, we can calculate:

* wait time (processing start - request arrival)
* processing time (processing end - processing start)
* latency (processing end - request arrival)

We can also record queue lengths whenever a request arrives. We'll look at some code in a bit, let's just focus on the behavior that the simulation gives us for the moment. Simulating 5 minutes of the unit queue leads to the following graphs:

<div style="display:flex">
  <img src="/assets/queue_simulations/unitqueue.svg" style="margin: auto;"/>
</div>

Visually, equilibrium is a bunch of straight lines. The reason the lines can remain straight is because the queue length is always 0, so no wait time ever gets introduced. Let's see what happens when we break this.

Queue equilibrium relies on the following inequality always being true:

$$ processing\ time \leq arrival\ rate $$

If the processing time ever exceeds the arrival rate, the queue length will begin to grow, and thus some wait time will be added to the latency of subsequent requests. Let's simulate the same 1 / second arrival rate, but with a 2 second processing time (note that 300 requests aren't recorded any more. This is because fewer requests can complete in the fixed time window when queueing is introduced):

<div style="display:flex">
  <img src="/assets/queue_simulations/unitqueue_slower.svg" style="margin: auto;"/>
</div>

The processing time remains constant at 2 seconds, but latency, wait time, and queue length all increase. It's actually worse, they increase _indefinitely_. This queue will never catch up, because the processing time exceeds the arrival rate. It is saturated.

The effect is brutal. After 100 requests arrive in the queue, only 50 have been processed, so there's a queue of 50 requests. Requests 101 and onward wait for 100 seconds before even beginning processing, and their total latency reflects this.

The lesson here is: there's no ideal processing time or arrival rate. Their relationship is what matters, so we need to know both. Even if there's no change in the processing time of a request, an increase in arrivals will lead to queueing and increased latencies across the board.

# Processing Distributions

Here's where simulations really become useful. We obviously won't have a system with constant processing times. They'll depend on any number of factors: customer size, data skew, current system load, etc. Let's look at what happens when we set the average processing time back to 1, but this time we distribute the times exponentially. As a reminder, the exponential distribution favors smaller values, but there's a long tail of large ones. It looks like this:

<div style="display:flex">
  <img src="/assets/queue_simulations/exp_dist.svg" style="margin: auto;"/>
</div>

This shows 100,000 random samplings of an exponential distribution. Thinking of it in terms of the number of requests that fall into the given processing time ranges, ~70,000 requests would be between 0 and 1 seconds, and ~90,000 would be between 0 and 2 seconds (90% of all requests). A relatively small number of requests would take more than 2 seconds, but we get requests all the way up to 12 seconds.

The average of all of these is still ~1 second. Let's see what happens when these are the processing times instead of the constant 1 second, keeping the 1 / second arrival rate constant:

<div style="display:flex">
  <img src="/assets/queue_simulations/queue_simulation_exponential.svg" style="margin: auto;"/>
</div>

The max processing time looks to be around 5 seconds, and there are only a few requests that high. But the latency increases to over 10 seconds at parts, because there's a big swell in the queue length at around request 150. I calculated some more metrics for this particular simulation run:

* p99 latency: 4.26s
* Average wait time: 3.34
* Average queue length: 2.93

Even with an average processing time of 1 second, and rare long requests, there is still pretty constant queueing here.

The lesson here being: don't only look at average request times, because there can be wildly different queueing characteristics for the same average value. The processing time distribution should always be considered.

In this particular case, where we only have one processor servicing the queue and a processing time distribution with a long tail, we can smooth out the queueing by adding an additional processor:

<div style="display:flex">
  <img src="/assets/queue_simulations/queue_simulation_exponential_multiple_processors.svg" style="margin: auto;"/>
</div>

This is slightly surprising, because we know that we have requests up to and past 5 seconds. If multiple of those happen at the same time, even with two processors they should clog up the queue and introduce queueing. But, we know that those long requests are rare, so the odds of two of them getting processed at the same time is low. It still does happen, as we see by the queue length increasing at certain points, but the queue recovers quickly. Average wait time for this run was 0.08 seconds, and the average queue length was 0.04. So, any latency is due to the actual request processing time, which is ideal.

# Code

Now for a little code, for those who are interested in running their own simulations (you'll need to install `simpy`, `matplotlib`, and `numpy` via your favorite Python dependency manager):

```python
import simpy
import itertools
import random
from dataclasses import dataclass
import matplotlib.pyplot as plt
import numpy as np

SIM_DURATION = 300

EXPONENTIAL_DIST = 'exponential'
GAUSSIAN_DIST = 'gaussian'
UNIFORM_DIST = 'uniform'
CONSTANT_DIST = 'constant'

MEAN_PROCESSING_TIME = 1
NUM_PROCESSORS = 1

@dataclass
class Monitor:
    wait_times: list[float]
    queue_lengths: list[int]
    latencies: list[float]
    processing_times: list[float]

class Queue:
    queue: simpy.Resource

    def __init__(self, env):
        self.env = env
        self.queue = simpy.Resource(env,  NUM_PROCESSORS)

def request(env, n, dist, monitor, queue):
    arrival = env.now
    monitor.queue_lengths.append(len(queue.queue.queue))
    with queue.queue.request() as req:
        yield req
        wait = env.now - arrival
        monitor.wait_times.append(wait)

        processing_start = env.now
        execution_time = 1
        mean_processing_time = MEAN_PROCESSING_TIME
        if dist == EXPONENTIAL_DIST:
            execution_time = random.expovariate(1 / mean_processing_time)
        elif dist == GAUSSIAN_DIST:
            execution_time = random.gauss(mean_processing_time, mean_processing_time / 4)
        elif dist == UNIFORM_DIST:
            delta = mean_processing_time * 0.5
            execution_time = random.uniform(mean_processing_time - delta, mean_processing_time + delta)
        elif dist == CONSTANT_DIST:
            execution_time = mean_processing_time

        yield env.timeout(execution_time)
        monitor.processing_times.append(env.now - processing_start)
        monitor.latencies.append(env.now - arrival)

def generate_load(env, latency_dist, monitor, queue):
    req_count = itertools.count()
    while True:
        yield env.timeout(1)
        env.process(request(env, next(req_count), latency_dist, monitor, queue))

def simulate_queue(latency_dist, monitor):
    env = simpy.Environment()
    q = Queue(env)
    env.process(generate_load(env, latency_dist, monitor, q))

    env.run(until=SIM_DURATION)

monitors = {}
for latency_dist in [CONSTANT_DIST, UNIFORM_DIST]:
    monitor = Monitor([], [], [], [])
    simulate_queue(latency_dist, monitor)
    monitors[latency_dist] = monitor

    print(f"Wait times: {monitor.wait_times}")
    print(f"Queue lengths: {monitor.queue_lengths}")
    print(f"Latencies: {monitor.latencies}")

    print()
    print(f"Average wait time: {sum(monitor.wait_times) / len(monitor.wait_times):.2f}")
    print(f"Average latency: {sum(monitor.latencies) / len(monitor.latencies):.2f}")
    print(f"p99 Latency: {np.percentile(np.array(monitor.latencies), 99):.2f}")
    print(f"Average queue length: {sum(monitor.queue_lengths) / len(monitor.queue_lengths):.2f}")
    print(f"Average processing time: {sum(monitor.processing_times) / len(monitor.processing_times):.2f}")

    print()

plot_monitors(monitors)
```

This is set up to run multiple different processing time distributions, which you can mix and match to compare. The main thing to know about the pattern that `SimPy` employs is that you `yield` events, which basically means "wait for this event to occur." In `generate_load` we first `yield env.timeout(1)`, which is how we say to send requests every 1 second. To be pedantic, this just sends it every one "time unit," and we are just interpreting it as the unit being seconds.

After that timeout completes, we run the `request` function which interacts with the queue. `SimPy` has the concept of a `Resource` which is a thing that can only be accessed a finite number of times. A `Resource` with a capacity set to 1 is equivalent to a queue with 1 processor. We wait for the queue to be available with:

```python
with queue.queue.request() as req:
    yield req
    ...
```

Then we pick a distribution and sample a value out of it, and wait for another timeout event  with `yield env.timeout(execution_time)` which simulates the request processing time. We pass a `Monitor` object throughout which keeps track of the various raw pieces of data so we can plot them later.

Here's the definition of `plot_monitors` for completeness:

```python
def plot_monitors(monitors):
    for dist, monitor in monitors.items():
        plot_monitor(dist, monitor,)

def plot_monitor(dist, monitor):
    min_len = min(len(monitor.wait_times), len(monitor.latencies), len(monitor.queue_lengths), len(monitor.processing_times))

    x_values = range(min_len)
    y_values_list = [
        monitor.processing_times[:min_len],
        monitor.latencies[:min_len],
        monitor.wait_times[:min_len],
        monitor.queue_lengths[:min_len],
    ]
    y_labels = ["Processing Time (s)", "Latency (s)", "Wait Time (s)", "Queue Length"]
    titles = ["Processing Time", "Latency", "Wait Time", "Queue Length"]

    num_subplots = len(y_values_list)
    fig, axes = plt.subplots(num_subplots, 1, figsize=(8, 6))

    for i, ax in enumerate(axes):
        ax.plot(x_values, y_values_list[i], linestyle='-', label=y_labels[i])
        ax.set_title(titles[i], fontweight='bold')
        ax.set_xlabel("Request Number")
        ax.set_ylabel(y_labels[i])
        ax.grid(True, linestyle='--', alpha=0.7)
    
    plt.tight_layout()
    plt.show()
```
