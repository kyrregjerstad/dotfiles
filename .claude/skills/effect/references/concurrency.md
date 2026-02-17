# Concurrency

Effect provides a powerful concurrency model based on fibers - lightweight threads of execution that are more efficient than OS threads and simpler to work with than callbacks or promises. This chapter covers forking and joining fibers, structured concurrency, and parallel operations.

## Fibers

A fiber is a lightweight thread of execution that never consumes more than a whole thread (but may consume much less). Fibers are spawned by forking effects, which run concurrently with the parent effect. They can be joined to get their result, or interrupted to terminate them safely.

### Forking Effects

Use `Effect.fork` to spawn a new fiber that runs concurrently with the current one:

```typescript
import { Effect, Fiber } from "effect"

const slow = Effect.gen(function* () {
  yield* Effect.sleep("2 seconds")
  return 50
})

const program = Effect.gen(function* () {
  yield* Effect.log("before fork")

  // Fork returns immediately with a fiber handle
  const fiber = yield* Effect.fork(slow)

  yield* Effect.log("after fork - fiber is running in background")

  // Do other work while fiber runs...
  yield* Effect.sleep("500 millis")

  // Join to wait for the result
  const result = yield* Fiber.join(fiber)
  yield* Effect.log(`Got result: ${result}`)
})
```

Key forking functions:

| Function | Behavior |
|----------|----------|
| `Effect.fork` | Child fiber tied to parent's lifecycle |
| `Effect.forkScoped` | Child fiber tied to current scope's lifecycle |
| `Effect.forkDaemon` | Child fiber detached, runs globally (avoid this) |

### Joining Fibers

`Fiber.join` suspends the current fiber until the forked fiber completes, returning its result:

```typescript
import { Effect, Fiber } from "effect"

const program = Effect.gen(function* () {
  const fiber = yield* Effect.fork(
    Effect.succeed(42).pipe(Effect.delay("1 second"))
  )

  // Join waits for completion and returns the value
  const value = yield* Fiber.join(fiber)
  // value: 42
})
```

If the joined fiber failed, `Fiber.join` will fail with the same error. If it was interrupted, joining will result in an "inner interruption" that can be caught and recovered.

### Awaiting Fibers

`Fiber.await` is similar to `join` but returns an `Exit` instead of failing:

```typescript
import { Effect, Fiber, Exit } from "effect"

const program = Effect.gen(function* () {
  const fiber = yield* Effect.fork(Effect.fail("oops"))

  // Await returns Exit, never fails
  const exit = yield* Fiber.await(fiber)

  if (Exit.isSuccess(exit)) {
    console.log("Succeeded:", exit.value)
  } else {
    console.log("Failed:", exit.cause)
  }
})
```

### Interrupting Fibers

Effect provides multiple ways to interrupt fibers:

**`Fiber.interrupt` - When you have a fiber handle:**

```typescript
import { Effect, Fiber, Exit } from "effect"

const slow = Effect.gen(function* () {
  yield* Effect.sleep("2 seconds")
  return 50
})

const program = Effect.gen(function* () {
  const fiber = yield* Effect.fork(slow)

  yield* Effect.sleep("100 millis")

  // Interrupt returns the Exit of the interrupted fiber
  const exit = yield* Fiber.interrupt(fiber)
  console.log(Exit.isInterrupted(exit)) // true
})
```

**`Effect.interrupt` - Interrupt the current fiber from within:**

```typescript
import { Effect } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.fork(
    Effect.log("hello").pipe(
      Effect.delay("300 millis"),
      Effect.repeat({ times: 20 })
    )
  )

  yield* Effect.sleep("2 seconds")

  // Interrupts current fiber AND all child fibers
  return yield* Effect.interrupt
}).pipe(
  Effect.onInterrupt(() => Effect.log("interrupted"))
)
```

**Interruption happens at suspension points.** Without yielding control to the scheduler, interruption won't occur:

```typescript
const program = Effect.gen(function* () {
  const fiber = yield* Effect.fork(slow)

  // Without yieldNow, the fiber wouldn't be interrupted immediately
  yield* Effect.yieldNow()

  yield* Fiber.interrupt(fiber)
})
```

### Protecting Code from Interruption

Use `Effect.uninterruptible` to protect regions of code:

```typescript
const critical = Effect.gen(function* () {
  yield* Effect.log("Starting critical section")
  yield* Effect.sleep("2 seconds")
  yield* Effect.log("Completed critical section")
}).pipe(Effect.uninterruptible)

// Even if interrupt is called, this completes before being interrupted
```

### Cleanup on Interruption

Attach finalizers that run when a fiber is interrupted:

```typescript
const slow = Effect.gen(function* () {
  yield* Effect.sleep("2 seconds")
  return 50
}).pipe(
  Effect.onInterrupt(() => Effect.log("Cleaning up..."))
)
```

## Structured Concurrency

Effect uses structured concurrency, where child fibers are tied to their parent's lifecycle. When a parent fiber is interrupted, all its children are automatically interrupted.

### Effect.fork vs Effect.forkDaemon

With `Effect.fork`, child fibers follow the parent:

```typescript
import { Effect } from "effect"

const repeat = Effect.log("hello").pipe(
  Effect.delay("300 millis"),
  Effect.repeat({ times: 20 })
)

Effect.gen(function* () {
  yield* Effect.fork(repeat)
  yield* Effect.sleep("2 seconds")
  return yield* Effect.interrupt
  // Child fiber gets interrupted when parent is interrupted
}).pipe(
  Effect.onInterrupt(() => Effect.log("interrupted"))
)
```

`Effect.forkDaemon` creates detached fibers that run independently:

```typescript
Effect.gen(function* () {
  yield* Effect.forkDaemon(repeat)
  yield* Effect.sleep("2 seconds")
  return yield* Effect.interrupt
  // Parent is interrupted, but repeat continues running!
})
```

**Avoid `forkDaemon`** - it breaks structured concurrency and makes resource management unpredictable.

### Forking into Scopes

The better alternative to `forkDaemon` is `Effect.forkScoped`, which ties the fiber to a scope instead of the direct parent:

```typescript
import { Effect } from "effect"

const heartbeat = Effect.log("heartbeat").pipe(
  Effect.delay("1 second"),
  Effect.forever
)

const program = Effect.gen(function* () {
  // Fiber is tied to the scope, not the parent
  yield* Effect.forkScoped(heartbeat)

  yield* Effect.sleep("5 seconds")
  // When scope closes, fiber is interrupted
}).pipe(Effect.scoped)
```

This gives you control over fiber lifetime without detaching globally. When the scope closes, all forked fibers are interrupted.

### Forking into a Specific Scope

Use `Effect.forkIn` when you have a specific scope in hand:

```typescript
import { Effect, Scope } from "effect"

const program = Effect.gen(function* () {
  const scope = yield* Scope.make

  // Fork into the explicit scope
  yield* Effect.forkIn(heartbeat, scope)

  yield* Effect.sleep("5 seconds")
  yield* Scope.close(scope, Exit.void)
  // Fiber interrupted when scope closes
})
```

## Parallel Operations

### Effect.all

`Effect.all` is the primary way to run multiple effects, with configurable concurrency:

**Sequential (default):**

```typescript
import { Effect, Array } from "effect"

const makeTask = (index: number) =>
  Effect.gen(function* () {
    yield* Effect.sleep("200 millis")
    yield* Effect.log(`Task ${index} finished`)
  })

const program = Effect.gen(function* () {
  const tasks = Array.makeBy(10, (i) => makeTask(i))

  // Sequential - tasks run one after another
  yield* Effect.all(tasks)
})
```

**Unbounded concurrency:**

```typescript
const program = Effect.gen(function* () {
  const tasks = Array.makeBy(10, (i) => makeTask(i))

  // All tasks run simultaneously
  yield* Effect.all(tasks, { concurrency: "unbounded" })
})
```

**Bounded concurrency:**

```typescript
const program = Effect.gen(function* () {
  const tasks = Array.makeBy(10, (i) => makeTask(i))

  // Only 2 tasks run at any given time
  yield* Effect.all(tasks, { concurrency: 2 })
})
// Output:
// Task 0 finished
// Task 1 finished
// Task 2 finished
// ...
```

With bounded concurrency, Effect only forks the specified number of fibers initially. Remaining effects wait in a queue and are only started when slots become available.

### Effect.all with Objects and Tuples

`Effect.all` preserves structure:

```typescript
// With objects
const result = yield* Effect.all({
  user: fetchUser(id),
  posts: fetchPosts(id),
  friends: fetchFriends(id)
}, { concurrency: "unbounded" })
// result: { user: User, posts: Post[], friends: Friend[] }

// With tuples
const [user, posts] = yield* Effect.all([
  fetchUser(id),
  fetchPosts(id)
], { concurrency: "unbounded" })
```

### Effect.race

`Effect.race` runs two effects concurrently and returns the first one to succeed:

```typescript
import { Effect, Console } from "effect"

const task1 = Effect.succeed("task1").pipe(
  Effect.delay("200 millis"),
  Effect.tap(Console.log("task1 done")),
  Effect.onInterrupt(() => Console.log("task1 interrupted"))
)

const task2 = Effect.succeed("task2").pipe(
  Effect.delay("100 millis"),
  Effect.tap(Console.log("task2 done")),
  Effect.onInterrupt(() => Console.log("task2 interrupted"))
)

const program = Effect.race(task1, task2)
// Output:
// task2 done
// task1 interrupted
// Result: "task2"
```

When one effect fails, the other continues:

```typescript
const task1 = Effect.fail("task1 error").pipe(Effect.delay("100 millis"))
const task2 = Effect.succeed("task2").pipe(Effect.delay("200 millis"))

const program = Effect.race(task1, task2)
// Result: "task2" (waits for task2 since task1 failed)
```

When both fail, the result contains both errors:

```typescript
const task1 = Effect.fail("error1").pipe(Effect.delay("100 millis"))
const task2 = Effect.fail("error2").pipe(Effect.delay("200 millis"))

const program = Effect.race(task1, task2)
// Fails with Cause containing both errors (Parallel cause)
```

### Effect.raceAll

`Effect.raceAll` races multiple effects:

```typescript
import { Effect, Console } from "effect"

const task1 = Effect.succeed("task1").pipe(Effect.delay("100 millis"))
const task2 = Effect.succeed("task2").pipe(Effect.delay("200 millis"))
const task3 = Effect.succeed("task3").pipe(Effect.delay("150 millis"))

const program = Effect.raceAll([task1, task2, task3])
// Output:
// task1 done
// task2 interrupted
// task3 interrupted
// Result: "task1"
```

### Effect.raceFirst

`Effect.raceFirst` returns the result of the first effect to complete, regardless of success or failure:

```typescript
const task1 = Effect.fail("quick failure").pipe(Effect.delay("50 millis"))
const task2 = Effect.succeed("slow success").pipe(Effect.delay("200 millis"))

const program = Effect.raceFirst(task1, task2)
// Fails with "quick failure" (first to complete)
```

### Using Effect.runCallback for Cancellation

For imperative contexts (like React), use `Effect.runCallback`:

```typescript
import { Effect } from "effect"
import { setTimeout } from "node:timers/promises"

const repeat = Effect.log("hello").pipe(
  Effect.delay("300 millis"),
  Effect.repeat({ times: 20 })
)

const program = Effect.gen(function* () {
  yield* Effect.fork(repeat)
  return yield* Effect.never // Runs indefinitely
}).pipe(
  Effect.onInterrupt(() => Effect.log("interrupted"))
)

// runCallback returns a cancel function
const cancel = Effect.runCallback(program)

// Later, from anywhere:
await setTimeout(2000)
cancel() // Interrupts the program
```

This pattern is perfect for React hooks:

```typescript
useEffect(() => {
  const cancel = Effect.runCallback(myProgram)
  return cancel // Cleanup function
}, [])
```

## Semaphores for Concurrency Control

A semaphore is a synchronization primitive that controls access through permits. Use it to limit concurrent access to shared resources:

```typescript
import { Effect } from "effect"

const program = Effect.gen(function* () {
  // Create a semaphore with 5 permits
  const semaphore = yield* Effect.makeSemaphore(5)

  const protectedTask = (id: number) =>
    semaphore.withPermits(1)(
      Effect.gen(function* () {
        yield* Effect.log(`Task ${id} running`)
        yield* Effect.sleep("1 second")
        yield* Effect.log(`Task ${id} done`)
      })
    )

  // Only 5 tasks run at a time
  yield* Effect.all(
    Array.from({ length: 20 }, (_, i) => protectedTask(i)),
    { concurrency: "unbounded" }
  )
})
```

### Practical Use Cases

**Preventing concurrent token refreshes:**

```typescript
const createTokenService = Effect.gen(function* () {
  const refreshSemaphore = yield* Effect.makeSemaphore(1)

  const refreshToken = (token: string) =>
    refreshSemaphore.withPermits(1)(
      Effect.gen(function* () {
        yield* Effect.log("Refreshing token...")
        const newToken = yield* callRefreshAPI(token)
        return newToken
      })
    )

  return { refreshToken }
})
```

**Rate limiting API calls:**

```typescript
const createAPIClient = Effect.gen(function* () {
  // Allow max 5 concurrent API calls
  const apiSemaphore = yield* Effect.makeSemaphore(5)

  const fetchWithLimit = (url: string) =>
    apiSemaphore.withPermits(1)(
      Effect.tryPromise(() => fetch(url))
    )

  return { fetch: fetchWithLimit }
})
```

## Fiber Collections

Effect provides specialized data structures for managing groups of fibers:

### FiberSet

A `FiberSet` holds a mutable collection of fibers. When the associated scope closes, all fibers are interrupted:

```typescript
import { Effect, FiberSet } from "effect"

const program = Effect.gen(function* () {
  const fiberSet = yield* FiberSet.make<string, never>()

  // Add fibers to the set
  yield* FiberSet.run(fiberSet, task1)
  yield* FiberSet.run(fiberSet, task2)

  // Wait for all fibers
  yield* FiberSet.join(fiberSet)
}).pipe(Effect.scoped)
```

### FiberMap

A `FiberMap` associates fibers with keys, automatically interrupting the previous fiber when a new one is added with the same key:

```typescript
import { Effect, FiberMap } from "effect"

const program = Effect.gen(function* () {
  const fiberMap = yield* FiberMap.make<string, string, never>()

  // If we run a new fiber with the same key, the old one is interrupted
  yield* FiberMap.run(fiberMap, "user-123", fetchUserData("user-123"))
  yield* FiberMap.run(fiberMap, "user-456", fetchUserData("user-456"))

  // Later, running with same key interrupts the previous
  yield* FiberMap.run(fiberMap, "user-123", fetchUserData("user-123"))
}).pipe(Effect.scoped)
```

### FiberHandle

A `FiberHandle` holds a single fiber reference, interrupting the previous fiber when a new one is set:

```typescript
import { Effect, FiberHandle } from "effect"

const program = Effect.gen(function* () {
  const handle = yield* FiberHandle.make<string, never>()

  // Set a fiber
  yield* FiberHandle.run(handle, longRunningTask)

  // Setting a new fiber interrupts the previous
  yield* FiberHandle.run(handle, anotherTask)

  yield* FiberHandle.join(handle)
}).pipe(Effect.scoped)
```

## Summary

- **Fibers** are lightweight threads spawned with `Effect.fork`
- **`Fiber.join`** waits for completion and returns the result (or fails)
- **`Fiber.await`** waits for completion and returns an `Exit`
- **`Fiber.interrupt`** terminates a fiber from outside
- **`Effect.interrupt`** terminates the current fiber from within
- **Structured concurrency** ties child fiber lifecycles to parents
- **`Effect.forkScoped`** ties fibers to scopes for controlled cleanup
- **`Effect.all`** runs effects with configurable concurrency
- **`Effect.race`** returns the first successful result
- **`Effect.raceFirst`** returns the first to complete (success or failure)
- **Semaphores** control concurrent access to resources
- **FiberSet/FiberMap/FiberHandle** manage collections of fibers
