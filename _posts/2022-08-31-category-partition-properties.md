---
layout: post
title: 'Domain-Driven Test Data Generation: A Category-Partition Method and Property-Based Testing Mashup'
tags: testing
author: Alex Weisberger
---

[Property-based testing](https://increment.com/testing/in-praise-of-property-based-testing/) is a well-known testing approach where random input generation is combined with checking correctness properties expressed as predicate functions. The goal of property-based testing is to use large amounts of these randomly generated inputs as a proxy for asserting that the property is _always_ true, also known as an invariant of the program. That's the main difference from example-based testing: examples check the expected result of a single program execution, whereas properties are statements about _all_ program executions. 

No matter how many inputs we generate, though, anything short of exhaustive testing or proof leaves room for errors. This begs the question: are there other data generation strategies that we can use to check the same correctness properties that we'd use when property-based testing? A property predicate doesn't care how the input data was generated, so we can decouple how data is produced from the actual property checking.

Enter the [category-partition method](https://www.researchgate.net/publication/220422305_The_Category-Partition_Method_for_Specifying_and_Generating_Functional_Tests), a testing technique that's existed since the 1980s. It's a hybrid human/automated approach for creating domain-driven test data. One of the biggest "downsides" to it is that it can produce lots of test cases, which often makes it prohibitively expensive for manual and example-based testing. But when testing for properties, lots of test cases is a _good_ thing. So is the mashup of category-partition-created-inputs and property-based-testing-properties a hyphen-laden match made in heaven?



# A Brief Overview of the Category-Partition Method

The category-partition method starts with decomposing the full input domain of an operation into "categories," which basically are groups of 
related inputs. Let's think about the `viewScheduledTransactions` operation from the previous [post about model-based testing a personal budgeting application]({% post_url 2022-08-11-model-based-testing %}). In that application, we can add our recurring bills and give them recurrence rules like "due every 2 weeks" or "due every month on the 8th." Once we do that, we can view their occurrences in a given time range. For example if we take a bill that's due every month on the 8th, in the range between 8/1/2022 and 10/31/2022 it would occur on 8/8, 9/8, and 10/8. Similar to recurring calendar events.

So the type signature of `viewScheduledTransactions` is:

~~~
const viewScheduledTransactions: (
  startDate: Date, 
  endDate: Date, 
  recurringTransactions: RecurringTransaction[]
) => ScheduledTransaction[];
~~~
{: .language-typescript}

An example category of this operation would be: "duration of the start and end date range." The key is, we came up with this category based on domain knowledge, which is that Dates are notoriously complex and we likely want to try out many different ranges to account for crossing daylight savings boundaries for example. The category then consists of different choices related to that concept, such as "spanning 2 months" or "spanning 11 months." This is why it's called the category-partition method: first we identify categories of input data, and then we partition that category into multiple different choices. Each choice refers to a group of related inputs, because there are many date ranges that are 2 months apart.

Next, in the unoptimized version of the method, we take the Cartesian product of all of the categories to create all combinations of data that select one option out of each category. For example, if we introduce another category called: "recurrence rule type" with "weekly and monthly" options, the product of both of those categories would be:

```
["spanning 2 months", "spanning 11 months"] X ["weekly", "monthly"] = [
  ["spanning 2 months", "weekly"],
  ["spanning 2 months", "monthly"],
  ["spanning 11 months", "weekly"],
  ["spanning 11 months", "monthly"]
]
```

And finally, we use these combinations to create test cases. The `["spanning 2 months", "weekly"]` combination could translate to a test case of:

~~~
const startDate = new Date("2022-08-01");
const endDate = new Date("2022-10-01");
const biweeklyBill = { 
  name: "Comic books", 
  amount: 20.0, 
  recurrenceRule: {
    recurrenceType: "weekly",
    interval: 2,
  }
};

const expectedValue = viewScheduleTransactions(startDate, endDate, [biWeeklyBill]);
~~~
{: .language-typescript}

It helps to think about this visually.

This represents the full set of all combinations of our inputs:

<div style="display:flex">
  <img src="/assets/category_partition_properties/InputSpaceFull.svg" style="margin: auto;"/>
</div>

The first category that we define partitions the full input space into the number of choices in that category. For our date range duration category:

<div style="display:flex">
  <img src="/assets/category_partition_properties/InputSpaceCategory1.svg" style="margin: auto;  padding: 20px"/>
</div>

And now, because we use the product of all categories, when we introduce a new category we don't just add its choices to the diagram, we divide each _existing_ partition by each of the new choices, i.e.:

<div style="display:flex">
  <img src="/assets/category_partition_properties/InputSpaceCategory2.svg" style="margin: auto;  padding: 20px"/>  
</div>

Notice how each slice was further partitioned into "weekly" and "monthly" slices. As we add more and more categories, the input space gets partitioned into finer-grained slices, and each slice represents the data for a single test case:

<div style="display:flex">
  <img src="/assets/category_partition_properties/InputSpaceDivided.svg" style="margin: auto; padding: 20px"/>  
</div>

Now, I said this is the unoptimized version of the method. A large part of the original category-partition method paper is devoted to techniques for reducing the amount of test cases that get generated because the number of elements in a Cartesian product grows very rapidly, and this method was originally intended for manual testing. Since we're going to be combining this generated test data with _properties_ and not with manual or automated example-based test cases, let's skip that part! We can just generate and use all of the combinations.

# Generating the Input Data

First, we need the concept of the "combination of selected category choices," which the paper calls a _test frame_ (`CreateRecurringTransaction` is a type defined in the [example repo](https://github.com/amw-zero/personal_finance_funcorrect/blob/main/personalfinance.ts)). A test frame should include all necessary input data for executing a test case:

~~~
type DateRange = {
  start: Date,
  end: Date,
};

type TestFrame = {
  dateRange: DateRange,
  recurringTransactions: CreateRecurringTransaction[],
};
~~~
{: .language-typescript}

The goal is to create an array of `TestFrames` where each frame is built up from a single selection from each of the categories. Based on that, it makes sense to make selection functions which take in a `TestFrame` and apply their selected values to it, e.g. here are the selection function for the "date range duration" category:

~~~
function selectShortDuration(input: TestFrame) {
  input.dateRange.start.setMonth(1);
  input.dateRange.end.setMonth(2);
}

function selectMediumDuration(input: TestFrame) {
  input.dateRange.start.setMonth(3);
  input.dateRange.end.setMonth(6);
}

function selectLongDuration(input: TestFrame) {
  input.dateRange.start.setMonth(0);
  input.dateRange.end.setMonth(11);
}
~~~
{: .language-typescript}

And the category itself is just an array of these selections:

~~~
function durationCategory() {
  return [selectShortDuration, selectMediumDuration, selectLongDuration];
}
~~~
{: .language-typescript}

Now what we want to do is generate the product of multiple categories like this, and iterate through them to end up with a list of `TestFrames`:

~~~
type SelectionFunc = (i: TestFrame) => void;

const selectionCombinations: SelectionFunc[][] = product(
  startTimeOfDayCategory(),
  endTimeOfDayCategory(),
  durationCategory(),
  ruleTypeCategory(),
);

let testFrames: TestFrame[] = [];

for (const selectionCombination of selectionCombinations) {
  let startDate = new Date();
  let endDate = new Date();
  let recurringTransactions: CreateRecurringTransaction[] = [];

  let frame = { dateRange: { start: startDate, end: endDate }, recurringTransactions };
  for (const selection of selectionCombination) {
    selection(frame);
  }

  testFrames.push(frame);
}
~~~
{: .language-typescript}

The `product` function (which doesn't exist in JS btw, but is easy enough to write), takes in an array of arrays of these selection functions, and generates all combinations of them. For example, a selection combination looks like this:

~~~
[
  [Function: selectMiddleOfDayStart],
  [Function: selectMiddleOfDayEnd],
  [Function: selectShortDuration],
  [Function: selectSomeMonthlyRule]
]
~~~
{: .language-typescript}

where `selectMiddleOfDayStart` is one choice out of the `startTimeOfDayCategory`, `selectMiddleOfDayEnd` is one choice out of `endTimeOfDayCategory`, etc. Again - the product produces _all_ such combinations.

The produced test frame from this selection combination is:

~~~
{
  dateRange: { start: "2022-03-03T17:34:48.422Z", end: "2022-03-31T16:34:48.422Z" },
  recurringTransactions: [{ 
    name: "monthlyRt1", 
    amount: 10, 
    recurrenceRule: { 
      recurrenceType: "monthly", 
      day: 2 
    }
  }]
}
~~~
{: .language-typescript}

We can see that the both date range values occur in the middle of the day, and the duration between them is short (less than 1 month). Since the monthly rule choice was chosen out of the `ruleTypeCategory`, the generated recurring transaction has a monthly recurrence rule. This is a faithful interpretation of the category selections in this combination.

Now, we have a big array of input data that we can check against a property.

# From Examples to Properties

Let's use the same property that we used in the previous post, and simply check that the web application implementation conforms to the simplified model:

~~~
Deno.test("Category-partition inputs plus model conformance property", async (t) => {
  let i = 0;
  for (const frame of testFrames) {
    let client = new Client();
    let budget = new Budget();

    await client.setup();
    await t.step(`Frame ${i}`, async (t) => {
      for (const crt of frame.recurringTransactions) {
        await client.addRecurringTransaction(crt);
        budget.addRecurringTransaction(crt);
      }

      await client.viewScheduledTransactions(frame.dateRange.start, frame.dateRange.end);
      budget.viewScheduledTransactions(frame.dateRange.start, frame.dateRange.end);

      assertEquals(client.scheduledTransactions, budget.scheduledTransactions);
    });
    i += 1;
    await client.teardown();
  }
});
~~~
{: .language-typescript}

That completes the mashup. Once we have generated test frames, properties themselves are extremely uncomplicated. In this case the property is just a single assertion that two values are equal. We don't even need a property-based testing library here, since those are mostly focused on the input-data generation and checking of the property multiple times. Since we generated our own input data and it's just an array, we don't need either of these features.

# Observations

Here's what I like about generating test data this way. The biggest problem with testing in general is [state space explosion]({% post_url 2021-1-2-state-explosion %}), and the root of that problem is the nature of combinations and how they grow in number multiplicatively. In the full input space, combinations simply grow way too fast to exhaustively test. The category-partition method fights fire with fire by partitioning this input space into very fine-grained slices with only a few user-defined categories because of the power of the Cartesian product. The key difference is that we control the rate of growth by treating all members of a slice equivalently (i.e. they are equivalance classes). 

Since each slice is a combination of all of the input variables, we end up with very specific data scenarios based on knowledge of the domain. This intuitively feels like it would place a lot of stress on the implementation, which is what we want out of our test data. There's also at least one study that used a similar approach and [it resulted in very high test coverage and found a large number of defects during testing](https://www.cs.cornell.edu/courses/cs5154/2021sp/resources/ISP-IndustrialCaseStudy.pdf).

As anecdotal evidence, the first time I ran this test (which was generated from relatively simple categories), it found an edge case which I didn't correct in the last post. It's a very specific scenario where two different recurring transactions end up expanding to the same date, and then the secondary order of transactions doesn't agree between the model and implementation. That's not conclusive evidence, but it is pretty promising as I forgot about that edge case already and this approach rediscovered it for me.

The categories shown here led to 81 test frames getting generated. That's nothing for a property-based test, but that number will grow very quickly as new categories and choices are added. For example, if we have 10 categories with 5 choices each, that already hits over 9 million test frames. We didn't cover test frame optimization here, but as I said there's a lot of information in the paper and elsewhere about how to exclude contradictory or redundant test frames.

Because of all of this, I see this being used as a complementary approach to random data generation. Randomess is very powerful, and when it's great, it's great. The major downside of it is that guiding the randomness to create complex, domain-based data can be a chore, and at the end of the day the strength of random testing comes from it being unbiased. By checking the same properties with both random and domain-driven data generation strategies, we can get a better proxy for checking all inputs.

[Here's the actual test](https://github.com/amw-zero/personal_finance_funcorrect/blob/main/categorytest.ts) created in this post. It sits in the same repo as the personal finance test application, so the application code can be consulted as well.

<hr>