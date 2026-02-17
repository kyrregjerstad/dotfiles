# Queues & PubSub

Effect provides three primitives for inter-fiber communication: **Queue** for work distribution, **PubSub** for broadcasting, and **Mailbox** for queues with completion signaling.

## Queue - Passing Values Between Fibers

Queue is the fundamental primitive for producer-consumer patterns. Values offered to a queue go to exactly one consumer.

### Creating Queues

Effect offers four queue types with different backpressure strategies:

```typescript
import { Queue, Effect } from "effect"

const program = Effect.gen(function* () {
  // Bounded - suspends offer when full (back-pressure)
  const bounded = yield* Queue.bounded<number>(5)

  // Unbounded - no capacity limit (use carefully)
  const unbounded = yield* Queue.unbounded<number>()

  // Sliding - drops OLD elements when full
  const sliding = yield* Queue.sliding<number>(5)

  // Dropping - drops NEW elements when full
  const dropping = yield* Queue.dropping<number>(5)
})
```

### Basic Operations

```typescript
import { Queue, Effect } from "effect"

const program = Effect.gen(function* () {
  const queue = yield* Queue.bounded<number>(5)

  // Offer a value - returns Effect<boolean>
  yield* queue.offer(1)
  yield* Queue.offer(queue, 2) // Alternative syntax

  // Take a value - suspends if empty
  const value = yield* queue.take
  console.log(value) // 1

  // Offer multiple values
  yield* Queue.offerAll(queue, [3, 4, 5])

  // Take all available values
  const all = yield* queue.takeAll // Chunk<number>

  // Take up to N values (non-blocking)
  const batch = yield* Queue.takeUpTo(queue, 10)

  // Take between min and max (waits for at least min)
  const between = yield* Queue.takeBetween(queue, 2, 10)
})
```

### Suspension Behavior

With bounded queues, `offer` suspends when full and `take` suspends when empty:

```typescript
import { Queue, Effect, Fiber } from "effect"

const program = Effect.gen(function* () {
  const queue = yield* Queue.bounded<number>(1)
  yield* queue.offer(1)
  console.log("Queue is full")

  // This fiber will suspend until someone takes
  const fiber = yield* queue.offer(2).pipe(Effect.fork)

  // Take frees up space, allowing the offer to complete
  const value = yield* queue.take
  yield* Fiber.join(fiber)
})
```

### The Boolean Return Value

`offer` returns `Effect<boolean>`:
- `true` = value was enqueued
- `false` = value was dropped (only with `dropping` or `sliding` strategies)

```typescript
import { Queue, Effect } from "effect"

const program = Effect.gen(function* () {
  const queue = yield* Queue.dropping<number>(1)

  const first = yield* queue.offer(1) // true
  const second = yield* queue.offer(2) // false - dropped

  const value = yield* queue.take
  console.log(value) // 1
})
```

### Non-Blocking Offer

Use `unsafeOffer` when you don't want to suspend:

```typescript
import { Queue, Effect } from "effect"

const program = Effect.gen(function* () {
  const queue = yield* Queue.bounded<number>(1)
  yield* queue.offer(1)

  // Returns boolean directly, not an Effect
  const accepted = queue.unsafeOffer(2) // false
})
```

### Shutting Down a Queue

`shutdown` interrupts all pending offers and takes:

```typescript
import { Queue, Effect, Fiber } from "effect"

const program = Effect.gen(function* () {
  const queue = yield* Queue.unbounded<number>()

  // Fork a fiber waiting for values
  const fiber = yield* Effect.gen(function* () {
    const value = yield* queue.take
    console.log("Received:", value)
  }).pipe(Effect.fork)

  yield* Effect.yieldNow()

  // Shutdown interrupts the waiting fiber
  yield* Queue.shutdown(queue)

  const exit = yield* Fiber.await(fiber)
  // Exit.Failure with Interrupt cause
})
```

### Stream Integration

Convert a queue to a stream for advanced processing:

```typescript
import { Queue, Effect, Stream } from "effect"

const program = Effect.gen(function* () {
  const queue = yield* Queue.unbounded<number>()

  yield* Stream.fromQueue(queue).pipe(
    Stream.mapEffect(
      (n) => Effect.log(`Processing: ${n}`),
      { concurrency: 2 }
    ),
    Stream.runDrain,
    Effect.fork
  )

  yield* queue.offer(1)
  yield* queue.offer(2)
  yield* Effect.sleep("100 millis")
  yield* Queue.shutdown(queue)
})
```

`Stream.fromQueue` internally batches takes for efficiency (up to 4096 items by default):

```typescript
Stream.fromQueue(queue, { maxChunkSize: 100 })
```

## PubSub - Broadcasting to Multiple Subscribers

With Queue, each value goes to one consumer. PubSub broadcasts to **all** subscribers:

```typescript
import { PubSub, Effect, Fiber } from "effect"

const program = Effect.gen(function* () {
  const pubsub = yield* PubSub.bounded<number>(10)

  const makeConsumer = (id: number) =>
    Effect.gen(function* () {
      const subscription = yield* pubsub.subscribe
      const value = yield* subscription.take
      console.log(`Consumer ${id} received ${value}`)
    })

  // Start 3 consumers
  const fiber = yield* Effect.all(
    [makeConsumer(1), makeConsumer(2), makeConsumer(3)],
    { concurrency: "unbounded" }
  ).pipe(Effect.fork)

  yield* Effect.yieldNow()
  yield* Effect.yieldNow()

  yield* pubsub.publish(42)
  yield* Fiber.join(fiber)
  // All three consumers receive 42
}).pipe(Effect.scoped)
```

### Creating PubSub

Same strategies as Queue:

```typescript
import { PubSub, Effect } from "effect"

const program = Effect.gen(function* () {
  // Standard strategies
  const bounded = yield* PubSub.bounded<number>(10)
  const unbounded = yield* PubSub.unbounded<number>()
  const dropping = yield* PubSub.dropping<number>(10)
  const sliding = yield* PubSub.sliding<number>(10)

  // With replay - late subscribers get recent history
  const withReplay = yield* PubSub.unbounded<number>({ replay: 3 })
})
```

### Publishing and Subscribing

```typescript
import { PubSub, Queue, Effect } from "effect"

const program = Effect.gen(function* () {
  const pubsub = yield* PubSub.bounded<number>(10)

  // Subscribe returns a Queue.Dequeue<A>
  const subscription = yield* pubsub.subscribe

  // Publish values
  yield* pubsub.publish(1)
  yield* pubsub.publishAll([2, 3, 4])

  // Take from subscription (same API as Queue)
  const value = yield* subscription.take
  const all = yield* subscription.takeAll
}).pipe(Effect.scoped) // Subscriptions require a scope
```

### Subscriptions Require Scope

`subscribe` returns `Effect<Queue.Dequeue<A>, never, Scope>`. When the scope closes, the subscription is automatically unregistered:

```typescript
import { PubSub, Effect } from "effect"

const program = Effect.gen(function* () {
  const pubsub = yield* PubSub.bounded<number>(10)

  // Each scoped block gets its own subscription
  yield* Effect.scoped(
    Effect.gen(function* () {
      const sub = yield* pubsub.subscribe
      // subscription active here
    })
  )
  // subscription automatically closed
})
```

### Replay for Late Subscribers

Late subscribers normally miss earlier messages. Use `replay` to buffer recent messages:

```typescript
import { PubSub, Effect } from "effect"

const program = Effect.gen(function* () {
  const pubsub = yield* PubSub.unbounded<number>({ replay: 3 })

  yield* pubsub.publishAll([1, 2, 3, 4, 5])

  // Late subscriber joins
  const sub = yield* pubsub.subscribe
  const messages = yield* sub.takeAll
  // Chunk(3, 4, 5) - the last 3 messages
}).pipe(Effect.scoped)
```

### Shutdown

```typescript
import { PubSub, Effect } from "effect"

const program = Effect.gen(function* () {
  const pubsub = yield* PubSub.bounded<number>(10)

  yield* PubSub.shutdown(pubsub)      // Interrupts all subscribers
  yield* PubSub.isShutdown(pubsub)    // Check if shut down
  yield* PubSub.awaitShutdown(pubsub) // Wait for shutdown
})
```

### Stream Integration

```typescript
import { PubSub, Stream, Effect } from "effect"

const program = Effect.gen(function* () {
  const pubsub = yield* PubSub.bounded<number>(10)

  // PubSub to Stream
  yield* Stream.fromPubSub(pubsub).pipe(
    Stream.take(5),
    Stream.runCollect,
    Effect.fork
  )

  // Stream to PubSub
  const anotherPubsub = yield* Stream.range(1, 10).pipe(
    Stream.toPubSub({ capacity: 10 })
  )
})
```

## Mailbox - Queue with Completion Signaling

Mailbox extends Queue with an error channel and completion signaling. It's planned to replace Queue in Effect v4.

### Creating Mailboxes

```typescript
import { Mailbox, Effect } from "effect"

const program = Effect.gen(function* () {
  // Unbounded (default)
  const mailbox = yield* Mailbox.make<number>()

  // With capacity
  const bounded = yield* Mailbox.make<number>(10)

  // With strategy
  const dropping = yield* Mailbox.make<number>({
    capacity: 10,
    strategy: "dropping"
  })
  const sliding = yield* Mailbox.make<number>({
    capacity: 10,
    strategy: "sliding"
  })

  // With error type
  const withErrors = yield* Mailbox.make<number, Error>()
})
```

### The Done Flag

Unlike Queue's `takeAll` which returns `Chunk<A>`, Mailbox returns a tuple with a done flag:

```typescript
import { Mailbox, Effect } from "effect"

const program = Effect.gen(function* () {
  const mailbox = yield* Mailbox.make<number>()

  yield* mailbox.offer(1)
  yield* mailbox.offer(2)
  yield* mailbox.end

  // Returns [messages, done]
  const [messages, done] = yield* mailbox.takeAll
  // messages: Chunk(1, 2)
  // done: true
})
```

This enables clean consumer loops:

```typescript
import { Mailbox, Effect } from "effect"

const consumer = (mailbox: Mailbox.Mailbox<number>) =>
  Effect.gen(function* () {
    while (true) {
      const [messages, done] = yield* mailbox.takeAll
      for (const msg of messages) {
        console.log("Processing:", msg)
      }
      if (done) break
    }
  })
```

### Completion Signaling

```typescript
import { Mailbox, Effect } from "effect"

const program = Effect.gen(function* () {
  const mailbox = yield* Mailbox.make<number>()

  yield* mailbox.offer(1)
  yield* mailbox.offer(2)

  // Signal completion
  yield* mailbox.end

  // Further offers return false
  const accepted = yield* mailbox.offer(3) // false
})
```

### Error Signaling

Mailbox has a typed error channel:

```typescript
import { Mailbox, Effect, Data } from "effect"

class ProcessingError extends Data.TaggedError("ProcessingError")<{
  readonly reason: string
}> {}

const program = Effect.gen(function* () {
  const mailbox = yield* Mailbox.make<number, ProcessingError>()

  yield* mailbox.offer(1)
  yield* mailbox.offer(2)
  yield* mailbox.fail(new ProcessingError({ reason: "Something went wrong" }))

  // Consumer still gets buffered messages first
  const [messages, done] = yield* mailbox.takeAll
  // messages: Chunk(1, 2), done: false

  // Next take fails with the error
  const error = yield* mailbox.takeAll.pipe(Effect.flip)
  // ProcessingError { reason: "Something went wrong" }
})
```

### Awaiting Full Consumption

`await` waits until the mailbox is ended AND all messages are consumed:

```typescript
import { Mailbox, Effect } from "effect"

const program = Effect.gen(function* () {
  const mailbox = yield* Mailbox.make<string>()

  // Producer
  yield* Effect.gen(function* () {
    yield* mailbox.offer("task-1")
    yield* mailbox.offer("task-2")
    yield* mailbox.end
  }).pipe(Effect.fork)

  // Consumer
  yield* Effect.gen(function* () {
    while (true) {
      const [messages, done] = yield* mailbox.takeAll
      for (const msg of messages) {
        yield* Effect.sleep("10 millis") // Simulate work
      }
      if (done) return
    }
  }).pipe(Effect.fork)

  // Wait until done AND all messages consumed
  yield* mailbox.await
  console.log("Everything processed!")
})
```

### Stream Conversion

```typescript
import { Mailbox, Stream, Effect } from "effect"

const program = Effect.gen(function* () {
  const mailbox = yield* Mailbox.make<number>()

  yield* Mailbox.toStream(mailbox).pipe(
    Stream.mapEffect((n) => Effect.log(`Processing: ${n}`)),
    Stream.runDrain,
    Effect.fork
  )

  yield* mailbox.offerAll([1, 2, 3])
  yield* mailbox.end
})
```

### Unsafe Methods for Callbacks

Use these in synchronous callback contexts:

```typescript
import { Mailbox, Exit, Effect } from "effect"

const program = Effect.gen(function* () {
  const mailbox = yield* Mailbox.make<number>()

  // In callback code
  mailbox.unsafeOffer(1)              // returns boolean
  mailbox.unsafeOfferAll([2, 3, 4])   // returns remaining Chunk
  mailbox.unsafeDone(Exit.void)       // end synchronously
  mailbox.unsafeDone(Exit.fail("e"))  // fail synchronously
})
```

## Comparison Table

| Feature | Queue | PubSub | Mailbox |
|---------|-------|--------|---------|
| Distribution | One consumer | All subscribers | One consumer |
| Completion signal | No | No | Yes (`end`) |
| Error channel | No | No | Yes (`fail`) |
| `takeAll` returns | `Chunk<A>` | `Chunk<A>` | `[Chunk<A>, done]` |
| Await all consumed | No | No | Yes (`await`) |
| Replay | No | Yes | No |

## Real-World Example: Job Processor Service

A job processor using Mailbox with typed errors:

```typescript
import { Effect, Mailbox, Stream, Console, Data } from "effect"

class JobError extends Data.TaggedError("JobError")<{
  readonly reason: string
}> {}

class JobProcessor extends Effect.Service<JobProcessor>()("JobProcessor", {
  scoped: Effect.gen(function* () {
    const mailbox = yield* Mailbox.make<number, JobError>()

    // Fork processor into the scope
    yield* Effect.forkScoped(
      Mailbox.toStream(mailbox).pipe(
        Stream.mapEffect(
          (value) => Console.log(`Processing job ${value}`),
          { concurrency: 2 }
        ),
        Stream.runDrain
      )
    )

    return {
      offer: (value: number) => mailbox.offer(value),
      end: mailbox.end,
      fail: (reason: string) => mailbox.fail(new JobError({ reason })),
      await: mailbox.await
    }
  })
}) {}

// Usage
const program = Effect.gen(function* () {
  const processor = yield* JobProcessor
  yield* processor.offer(1)
  yield* processor.offer(2)
  yield* processor.end
  yield* processor.await
})
```

## Summary

- **Queue**: Work distribution (one consumer per value). Use for job queues, producer-consumer patterns.
- **PubSub**: Broadcasting (all subscribers get all values). Use for event systems, multi-consumer scenarios.
- **Mailbox**: Queue with completion signaling. Use when consumers need to know when to stop.

Choose based on your messaging pattern:
- Need to distribute work? → Queue
- Need to broadcast events? → PubSub
- Need completion/error signaling? → Mailbox
