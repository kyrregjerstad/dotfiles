# Streams

Effect Streams are pull-based, lazy sequences of values. Unlike push-based systems where producers control the pace, streams only produce values when the consumer requests them. This enables backpressure, safe handling of infinite sequences, and predictable resource usage.

```typescript
import { Effect, Stream } from "effect"

// Nothing runs here - just a blueprint
const infinite = Stream.iterate(0, (n) => n + 1)

// Still nothing running
const first5 = Stream.take(infinite, 5)

// NOW it runs, and stops automatically after 5 elements
const result = await Effect.runPromise(Stream.runCollect(first5))
// Chunk(0, 1, 2, 3, 4)
```

## Pull-based Streams

The key difference from push-based systems: **the consumer controls the pace**. Consider a paginated API:

```typescript
import { Console, Effect, Option, Stream } from "effect"

interface User {
  id: number
  name: string
}

const db: Record<number, { users: User[]; nextPage: Option.Option<number> }> = {
  1: { users: [{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }], nextPage: Option.some(2) },
  2: { users: [{ id: 3, name: "Charlie" }], nextPage: Option.none() }
}

const fetchPage = (page: number) =>
  Console.log(`Fetching page ${page}`).pipe(Effect.as(db[page]!))

// Stream that paginates through results
const users = Stream.paginateEffect(1, (page) =>
  fetchPage(page).pipe(
    Effect.map(({ users, nextPage }) => [users, nextPage] as const)
  )
).pipe(Stream.flattenIterables)

const program = users.pipe(
  Stream.tap((user) => Console.log(`Processing ${user.name}`)),
  Stream.tap(() => Effect.sleep("100 millis")),
  Stream.runDrain
)
// Output:
// Fetching page 1
// Processing Alice
// Processing Bob
// Fetching page 2      <- only fetched when page 1 is consumed
// Processing Charlie
```

Page 2 isn't fetched until page 1's users are processed. This is **backpressure** - the producer can't outrun the consumer.

## Creating Streams

### From Values

```typescript
import { Stream } from "effect"

// Single values
Stream.make(1, 2, 3)

// From iterables
Stream.fromIterable([1, 2, 3])

// From chunks (more efficient for batches)
Stream.fromChunk(Chunk.make(1, 2, 3))
Stream.fromChunks(chunk1, chunk2, chunk3)

// Ranges
Stream.range(1, 100)        // 1 to 100 inclusive
Stream.range(1, 100, 10)    // in chunks of 10
```

### From Effects

```typescript
import { Effect, Stream } from "effect"

// Single effect becomes single-element stream
Stream.fromEffect(Effect.succeed(42))

// Effect that might produce nothing
Stream.fromEffectOption(Effect.fail(Option.none()))  // empty stream

// Repeat an effect
Stream.repeatEffect(Effect.random)  // infinite stream of random numbers

// From a schedule
Stream.fromSchedule(Schedule.spaced("1 second"))  // emits elapsed duration
```

### Generators and Unfolds

```typescript
import { Option, Stream } from "effect"

// Iterate from initial value
Stream.iterate(0, (n) => n + 1)  // 0, 1, 2, 3, ...

// Unfold with termination control
Stream.unfold(0, (n) =>
  n < 10
    ? Option.some([n, n + 1] as const)  // [emit value, next state]
    : Option.none()                       // stop
)

// Unfold with effects
Stream.unfoldEffect(0, (n) =>
  Effect.succeed(n < 10 ? Option.some([n, n + 1] as const) : Option.none())
)
```

### From External Sources

```typescript
import { Stream } from "effect"

// Async iterables
async function* generateNumbers() {
  yield 1
  yield 2
  yield 3
}
Stream.fromAsyncIterable(generateNumbers(), (e) => new Error(String(e)))

// Web ReadableStream
Stream.fromReadableStream({
  evaluate: () => response.body!,
  onError: (e) => new StreamError(e)
})

// Queues
Stream.fromQueue(queue)
Stream.fromQueue(queue, { maxChunkSize: 10 })
```

## Transforming Streams

### Basic Transformations

```typescript
import { Effect, Stream } from "effect"

Stream.make(1, 2, 3, 4, 5).pipe(
  // Transform each element
  Stream.map((n) => n * 2),           // 2, 4, 6, 8, 10

  // Transform with effects
  Stream.mapEffect((n) => Effect.succeed(n + 1)),

  // Filter elements
  Stream.filter((n) => n % 2 === 0),  // 2, 4

  // Side effects without changing values
  Stream.tap((n) => Console.log(`Got ${n}`)),

  // Take/drop elements
  Stream.take(3),                      // first 3
  Stream.drop(2),                      // skip first 2
  Stream.takeWhile((n) => n < 10),     // until predicate fails
)
```

### FlatMap and Concurrency

```typescript
import { Effect, Stream } from "effect"

// Sequential: each inner stream completes before next starts
Stream.make(1, 2, 3).pipe(
  Stream.flatMap((n) => Stream.make(n, n * 10))
)
// 1, 10, 2, 20, 3, 30

// Concurrent processing with mapEffect
Stream.make(1, 2, 3, 4, 5).pipe(
  Stream.mapEffect(
    (n) => Effect.delay(Effect.succeed(n * 2), "100 millis"),
    { concurrency: 3 }  // process up to 3 concurrently
  )
)
```

The `concurrency` option uses an internal semaphore. When all permits are taken, the stream stops pulling new elements until one completes.

### Working with Chunks

Streams process data in chunks for efficiency. You can work at the chunk level:

```typescript
import { Chunk, Stream } from "effect"

Stream.range(1, 100).pipe(
  // Rechunk to specific size
  Stream.rechunk(10),

  // Transform whole chunks
  Stream.mapChunks((chunk) =>
    Chunk.of(Chunk.reduce(chunk, 0, (a, b) => a + b))
  ),

  // Flatten chunks back to elements
  Stream.flattenChunks
)
```

## Handling Data Flow

### Grouping and Batching

```typescript
import { Stream } from "effect"

// Group by count
Stream.range(1, 25).pipe(
  Stream.grouped(5)  // Chunk([1,2,3,4,5]), Chunk([6,7,8,9,10]), ...
)

// Group by count OR time (whichever comes first)
events.pipe(
  Stream.groupedWithin(10, "1 second")  // max 10 items or every second
)
```

`groupedWithin` is useful for:
- Batching database inserts
- Aggregating metrics
- Rate-limiting API calls

### Scheduling

```typescript
import { Schedule, Stream } from "effect"

Stream.make(1, 2, 3).pipe(
  // Add delay between elements
  Stream.schedule(Schedule.spaced("100 millis")),

  // Or use tap with sleep
  Stream.tap(() => Effect.sleep("100 millis"))
)
```

### Buffering

`Stream.buffer` decouples producer and consumer into separate fibers:

```typescript
import { Stream } from "effect"

Stream.range(1, 1000).pipe(
  Stream.buffer({ capacity: 16 }),  // producer can get ahead by 16 items
  Stream.map((n) => expensiveOperation(n))
)
```

Buffer strategies:
- **`suspend`** (default): producer blocks when full
- **`dropping`**: new items dropped when full
- **`sliding`**: oldest items dropped to make room

### Handling Push-based Sources

Use `Stream.asyncPush` to convert push-based sources (WebSockets, event listeners) to streams:

```typescript
import { Effect, Stream } from "effect"

const ticks = Stream.asyncPush<number>((emit) =>
  Effect.acquireRelease(
    Effect.sync(() => {
      let count = 0
      return setInterval(() => emit.single(count++), 100)
    }),
    (handle) => Effect.sync(() => clearInterval(handle))
  )
)

// Control overflow at the source
const boundedTicks = Stream.asyncPush<number>(
  (emit) => /* setup */,
  { bufferSize: 10, strategy: "dropping" }
)
```

The `emit` helper provides:
- `emit.single(value)` - emit one value
- `emit.chunk(chunk)` - emit multiple values
- `emit.end()` - signal completion
- `emit.fail(error)` - signal error

## Merging Streams

### Two Streams

```typescript
import { Stream, Schedule } from "effect"

const llmTokens = Stream.fromIterable("Hello world").pipe(
  Stream.schedule(Schedule.spaced("50 millis")),
  Stream.map((char) => ({ _tag: "token" as const, content: char }))
)

const keepAlive = Stream.tick("200 millis").pipe(
  Stream.map(() => ({ _tag: "ping" as const }))
)

// Merge both, interleaved by arrival time
const merged = Stream.merge(llmTokens, keepAlive, {
  haltStrategy: "left"  // stop when llmTokens ends
})
```

Halt strategies:
- **`both`** (default): wait for all to finish
- **`left`**: stop when left stream ends
- **`right`**: stop when right stream ends
- **`either`**: stop when any stream ends

### Multiple Typed Streams

```typescript
import { Stream } from "effect"

// Automatically tags each stream
const events = Stream.mergeWithTag(
  {
    llm: Stream.make("token1", "token2"),
    system: Stream.make("connected", "ready")
  },
  { concurrency: "unbounded" }
)
// Type: { _tag: "llm", value: string } | { _tag: "system", value: string }
```

### Dynamic Stream Lists

```typescript
import { Stream } from "effect"

const streams = [
  Stream.make(1, 2),
  Stream.make(10, 20),
  Stream.make(100, 200)
]

Stream.mergeAll(streams, {
  concurrency: 2,    // max 2 streams at once
  bufferSize: 16     // shared output queue size
})
```

## Running Streams

Streams are descriptions - running them produces effects:

```typescript
import { Effect, Stream } from "effect"

const stream = Stream.make(1, 2, 3)

// Collect all elements into a Chunk
const all = Stream.runCollect(stream)
// Effect<Chunk<number>>

// Discard all elements (for side effects only)
const drain = Stream.runDrain(stream)
// Effect<void>

// Run effect for each element
const forEach = Stream.runForEach(stream, (n) => Console.log(n))
// Effect<void>

// Fold elements
const sum = Stream.runFold(stream, 0, (acc, n) => acc + n)
// Effect<number>

// Get first element
const first = Stream.runHead(stream)
// Effect<Option<number>>

// Get last element
const last = Stream.runLast(stream)
// Effect<Option<number>>
```

## Practical Example: File Watcher

```typescript
import { FileSystem } from "@effect/platform"
import { NodeFileSystem, NodeRuntime } from "@effect/platform-node"
import { Console, Effect, Layer, Stream } from "effect"

Effect.gen(function*() {
  const fs = yield* FileSystem.FileSystem

  yield* fs.watch("src", { recursive: true }).pipe(
    Stream.filter((event) => event.path.endsWith(".ts")),
    Stream.tap((event) => Console.log(`Changed: ${event.path}`)),
    Stream.runForEach((event) => rebuildFile(event.path))
  )
}).pipe(
  Effect.provide(NodeFileSystem.layer),
  NodeRuntime.runMain
)
```

## Practical Example: AI Streaming

```typescript
import { Effect, Stream } from "effect"

interface AiModel {
  streamText: (prompt: string) => Stream.Stream<string, AiError>
}

const program = Effect.gen(function*() {
  const ai = yield* AiModel

  yield* ai.streamText("Explain streams").pipe(
    // Buffer tokens for smoother display
    Stream.groupedWithin(5, "100 millis"),
    Stream.map((chunk) => chunk.join("")),
    Stream.runForEach((text) => Console.log(text))
  )
})
```

## Key Takeaways

1. **Pull-based**: Consumer controls pace, enabling natural backpressure
2. **Lazy**: Streams are blueprints - nothing runs until you call a `run*` method
3. **Composable**: Transform with `map`, `filter`, `flatMap` like arrays
4. **Concurrent**: Use `concurrency` option in `mapEffect` for parallel processing
5. **Push conversion**: Use `Stream.asyncPush` for WebSockets, events, timers
6. **Merging**: Combine streams with `merge`, `mergeWithTag`, or `mergeAll`
