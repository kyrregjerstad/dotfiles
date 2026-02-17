# Scheduling

Schedules define when and how often operations should be repeated or retried. They are composable, stateful policies that control timing, delays, and recurrence limits.

## Schedule Basics

A `Schedule<Out, In, R>` produces output values of type `Out` from input values of type `In`, possibly requiring context `R`. Schedules determine:

- **When** to continue (or stop)
- **How long** to wait between executions
- **What value** to produce for each recurrence

```ts
import { Effect, Schedule } from "effect"

// Repeat 3 times with no delay
const basic = Schedule.recurs(3)

// Repeat with 1 second between each execution
const spaced = Schedule.spaced("1 second")

// Exponential backoff starting at 100ms
const exponential = Schedule.exponential("100 millis")
```

## Retry Policies

Use `Effect.retry` with a schedule to retry failed effects:

```ts
import { Effect, Schedule } from "effect"

const fetchData = Effect.tryPromise(() => fetch("/api/data"))

// Retry up to 3 times
const withRetry = fetchData.pipe(Effect.retry(Schedule.recurs(3)))

// Retry with exponential backoff
const withBackoff = fetchData.pipe(
  Effect.retry(Schedule.exponential("100 millis"))
)
```

### Conditional Retry

Retry only on specific errors using the options object:

```ts
import { Effect, Schedule } from "effect"

class NetworkError {
  readonly _tag = "NetworkError"
}

class ValidationError {
  readonly _tag = "ValidationError"
}

const program = Effect.fail(new NetworkError())

// Only retry NetworkError, not ValidationError
const selective = program.pipe(
  Effect.retry({
    while: (error) => error._tag === "NetworkError",
    schedule: Schedule.spaced("500 millis")
  })
)

// Retry until condition is met
const untilSuccess = program.pipe(
  Effect.retry({
    until: (error) => error._tag === "ValidationError",
    schedule: Schedule.recurs(5)
  })
)
```

### Retry with Fallback

Use `Effect.retryOrElse` to provide a fallback when retries are exhausted:

```ts
import { Effect, Schedule } from "effect"

const unreliable = Effect.fail("connection failed")

const withFallback = unreliable.pipe(
  Effect.retryOrElse(
    Schedule.recurs(3),
    (error, attempts) => Effect.succeed(`fallback after ${attempts} attempts`)
  )
)
```

## Repeat Patterns

Use `Effect.repeat` to repeat successful effects:

```ts
import { Effect, Schedule, Console } from "effect"

// Repeat 3 additional times (4 total executions)
const repeated = Console.log("tick").pipe(
  Effect.repeat(Schedule.recurs(3))
)

// Repeat every second
const periodic = Console.log("heartbeat").pipe(
  Effect.repeat(Schedule.spaced("1 second"))
)
```

### Repeat with Conditions

```ts
import { Effect, Ref, Schedule } from "effect"

const countdown = Effect.gen(function* () {
  const counter = yield* Ref.make(10)

  // Repeat while counter > 0
  yield* Ref.updateAndGet(counter, (n) => n - 1).pipe(
    Effect.tap((n) => Effect.log(`Count: ${n}`)),
    Effect.repeat({ while: (n) => n > 0 })
  )
})

// Repeat until a condition is met
const untilDone = Effect.gen(function* () {
  const ref = yield* Ref.make(0)

  yield* Ref.updateAndGet(ref, (n) => n + 1).pipe(
    Effect.repeat({ until: (n) => n === 5 })
  )
})
```

### Combining Schedule with Conditions

```ts
import { Effect, Ref, Schedule } from "effect"

const limited = Effect.gen(function* () {
  const ref = yield* Ref.make(0)

  // Repeat up to 10 times OR until value reaches 5
  yield* Ref.updateAndGet(ref, (n) => n + 1).pipe(
    Effect.repeat({
      schedule: Schedule.recurs(10),
      until: (n) => n === 5
    })
  )
})
```

### Simple Repeat with Times

For simple cases, use `times` instead of a full schedule:

```ts
import { Effect, Console } from "effect"

// Execute 3 times total (initial + 2 repeats)
const simple = Console.log("hello").pipe(
  Effect.repeat({ times: 2 })
)
```

## Schedule Composition

Schedules can be combined using composition operators.

### Union (Either Continues)

`Schedule.union` continues as long as **either** schedule wants to continue, using the shorter delay:

```ts
import { Schedule } from "effect"

// Exponential backoff capped at 1 minute
const capped = Schedule.exponential("200 millis").pipe(
  Schedule.union(Schedule.spaced("1 minute"))
)
```

This is a common pattern for retry policies - exponential growth that caps at a maximum delay.

### Intersection (Both Must Continue)

`Schedule.intersect` continues only while **both** schedules want to continue:

```ts
import { Schedule } from "effect"

// Exponential backoff, max 3 retries
const limited = Schedule.exponential("1 second").pipe(
  Schedule.intersect(Schedule.recurs(3))
)

// Fixed interval, limited by count
const bounded = Schedule.fixed("1 second").pipe(
  Schedule.intersect(Schedule.recurs(5))
)
```

### Sequential Composition

`Schedule.andThen` runs the first schedule, then the second:

```ts
import { Schedule } from "effect"

// 3 quick retries, then switch to slower retries
const twoPhase = Schedule.recurs(3).pipe(
  Schedule.andThen(Schedule.spaced("5 seconds"))
)
```

### Compose (Pipe Output to Input)

`Schedule.compose` pipes the output of one schedule to the input of another:

```ts
import { Schedule } from "effect"

// Get elapsed time at each recurrence
const withElapsed = Schedule.spaced("1 second").pipe(
  Schedule.compose(Schedule.elapsed)
)
```

## Delay Strategies

Effect provides several built-in delay strategies:

### Fixed Delays

```ts
import { Schedule } from "effect"

// Constant delay between executions
const fixed = Schedule.fixed("100 millis")

// Similar to fixed, but measures from end of execution
const spaced = Schedule.spaced("100 millis")
```

`fixed` maintains consistent intervals from the start of each execution, while `spaced` waits a fixed duration after each execution completes.

### Exponential Backoff

```ts
import { Schedule } from "effect"

// Default factor of 2: 100ms, 200ms, 400ms, 800ms...
const exp = Schedule.exponential("100 millis")

// Custom factor of 3: 100ms, 300ms, 900ms, 2700ms...
const expFactor = Schedule.exponential("100 millis", 3)
```

### Fibonacci Delays

```ts
import { Schedule } from "effect"

// 100ms, 100ms, 200ms, 300ms, 500ms, 800ms...
const fib = Schedule.fibonacci("100 millis")
```

### Linear Growth

```ts
import { Schedule } from "effect"

// 100ms, 200ms, 300ms, 400ms...
const linear = Schedule.linear("100 millis")
```

### Custom Delays

```ts
import { Schedule } from "effect"

// Explicit delay sequence
const custom = Schedule.fromDelays(
  "100 millis",
  "500 millis",
  "1 second",
  "5 seconds"
)
```

## Modifying Schedules

### Adding Jitter

Add randomness to prevent thundering herd:

```ts
import { Schedule } from "effect"

const jittered = Schedule.exponential("1 second").pipe(
  Schedule.jittered
)
```

### Capping Delays

```ts
import { Schedule, Duration } from "effect"

// Cap delay at 8 seconds
const capped = Schedule.exponential("1 second", 2).pipe(
  Schedule.modifyDelay(Duration.min("8 seconds"))
)
```

### Effectful Delay Modification

```ts
import { Effect, Schedule, Duration } from "effect"

const withLogging = Schedule.exponential("1 second").pipe(
  Schedule.modifyDelayEffect((attempt, delay) =>
    Effect.as(
      Effect.log(`Attempt ${attempt}, waiting ${Duration.toMillis(delay)}ms`),
      Duration.times(delay, 2)
    )
  )
)
```

### Time Limits

```ts
import { Schedule } from "effect"

// Stop after 5 seconds total elapsed time
const timeLimited = Schedule.spaced("1 second").pipe(
  Schedule.upTo("5 seconds")
)
```

### Reset After Inactivity

```ts
import { Schedule } from "effect"

// Reset retry count if 5 seconds pass without failure
const resetting = Schedule.recurs(5).pipe(
  Schedule.resetAfter("5 seconds")
)
```

## Filtering with Predicates

### WhileInput / UntilInput

Filter based on the input to the schedule:

```ts
import { Schedule } from "effect"

// Only retry while error is recoverable
const recoverable = Schedule.spaced("200 millis").pipe(
  Schedule.whileInput((error: string) => error !== "fatal")
)
```

### WhileOutput / UntilOutput

Filter based on schedule output:

```ts
import { Schedule, Duration } from "effect"

// Stop when elapsed time exceeds limit
const bounded = Schedule.spaced("100 millis").pipe(
  Schedule.compose(Schedule.elapsed),
  Schedule.whileOutput((elapsed) =>
    Duration.lessThan(elapsed, Duration.seconds(5))
  )
)
```

## Cron-like Scheduling

Schedule execution at specific times:

```ts
import { Effect, Schedule } from "effect"

// Every 2 minutes
const everyTwoMinutes = Schedule.cron("*/2 * * * *")

// At 4:30 on the 5th and 15th of each month
const specific = Schedule.cron("30 4 5,15 * *")

// Time-based schedules
const hourly = Schedule.hourOfDay(4)           // At 4:00 each day
const atMinute = Schedule.minuteOfHour(30)     // At :30 each hour
const daily = Schedule.dayOfMonth(1)           // On the 1st of each month
const weekly = Schedule.dayOfWeek(1)           // Every Monday
```

Combine time-based schedules:

```ts
import { Schedule } from "effect"

// At 4:20 each day
const dailyAt420 = Schedule.hourOfDay(4).pipe(
  Schedule.intersect(Schedule.minuteOfHour(20))
)
```

## Schedule Outputs

Schedules can output useful information:

```ts
import { Schedule } from "effect"

// Output the recurrence count
const counted = Schedule.count

// Output elapsed time since start
const timed = Schedule.elapsed

// Output number of repetitions
const repetitions = Schedule.repetitions

// Forever with void output
const forever = Schedule.forever
```

### Accessing Iteration Metadata

```ts
import { Effect, Schedule } from "effect"

const withMetadata = Effect.gen(function* () {
  const meta = yield* Schedule.CurrentIterationMetadata
  console.log(`Recurrence: ${meta.recurrence}`)
  console.log(`Elapsed: ${meta.elapsed}`)
}).pipe(
  Effect.repeat(Schedule.recurs(5))
)
```

## Real-World Retry Pattern

A production-ready retry policy combining multiple strategies:

```ts
import { Effect, Schedule, Duration } from "effect"

// Exponential backoff capped at 8 seconds, with jitter
const retryPolicy = Schedule.exponential("1 second", 2).pipe(
  Schedule.modifyDelay(Duration.min("8 seconds")),
  Schedule.jittered,
  Schedule.intersect(Schedule.recurs(10))
)

const resilientFetch = (url: string) =>
  Effect.tryPromise(() => fetch(url)).pipe(
    Effect.timeout("5 seconds"),
    Effect.retry({
      while: (error) => isTransientError(error),
      schedule: retryPolicy
    })
  )
```

## Schedules with Streams

Schedules can control stream timing:

```ts
import { Stream, Schedule } from "effect"

// Emit values at fixed intervals
const timed = Stream.range(1, 10).pipe(
  Stream.schedule(Schedule.fixed("100 millis"))
)

// Create a stream from a schedule
const fromSchedule = Stream.fromSchedule(Schedule.spaced("1 second"))
```

## Summary

| Schedule | Description |
|----------|-------------|
| `recurs(n)` | Execute n additional times |
| `once` | Execute one additional time |
| `forever` | Execute indefinitely |
| `spaced(d)` | Fixed delay after each execution |
| `fixed(d)` | Fixed interval from start of each execution |
| `exponential(d, f)` | Exponential growth with optional factor |
| `fibonacci(d)` | Fibonacci sequence delays |
| `linear(d)` | Linear growth delays |
| `fromDelays(...)` | Custom delay sequence |

| Combinator | Description |
|------------|-------------|
| `union` | Continue while either wants to |
| `intersect` | Continue while both want to |
| `andThen` | Run first, then second |
| `compose` | Pipe output to input |
| `jittered` | Add random jitter |
| `modifyDelay` | Transform delays |
| `upTo(d)` | Stop after duration |
| `resetAfter(d)` | Reset state after inactivity |
| `whileInput/Output` | Continue while predicate holds |
