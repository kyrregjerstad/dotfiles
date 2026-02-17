# Effect Basics

## Effect<A, E, R>

```ts
Effect<A, E, R>
//     │  │  └─ Requirements (dependencies needed to run)
//     │  └──── Error (typed failure)
//     └─────── Success (result value)
```

Defaults to `never` when not needed:

```ts
Effect<string>              // Effect<string, never, never>
Effect<string, Error>       // Effect<string, Error, never>
Effect<string, Error, Db>   // requires Db service
```

Effects are descriptions, not executions:

```ts
const effect = Console.log("Hello")  // nothing happens yet
Effect.runSync(effect)               // now it prints
```

## Creating Effects

### From values

```ts
Effect.succeed(42)                   // Effect<number>
Effect.fail(new MyError())           // Effect<never, MyError>
```

### From sync functions

```ts
// Won't throw
Effect.sync(() => Date.now())        // Effect<number>

// Might throw
Effect.try(() => JSON.parse(str))    // Effect<unknown, UnknownException>

// Might throw, custom error
Effect.try({
  try: () => JSON.parse(str),
  catch: (e) => new ParseError(e)
})  // Effect<unknown, ParseError>
```

### From async functions

```ts
// Won't reject
Effect.promise(() => Promise.resolve(42))  // Effect<number>

// Might reject
Effect.tryPromise(() => fetch(url))        // Effect<Response, UnknownException>

// Might reject, custom error
Effect.tryPromise({
  try: () => fetch(url),
  catch: (e) => new FetchError(e)
})  // Effect<Response, FetchError>

// With AbortSignal for interruption
Effect.tryPromise((signal) => fetch(url, { signal }))
```

### From callbacks

```ts
Effect.async<string, Error>((resume) => {
  fs.readFile("data.txt", "utf8", (err, data) => {
    if (err) resume(Effect.fail(err))
    else resume(Effect.succeed(data))
  })
})
```

## Running Effects

```ts
// Sync only, throws on async/error
Effect.runSync(effect)               // A

// Returns Promise, throws FiberFailure on error
await Effect.runPromise(effect)      // A

// Returns Exit with full type info (recommended)
const exit = await Effect.runPromiseExit(effect)
if (Exit.isSuccess(exit)) {
  exit.value  // A
} else {
  exit.cause  // Cause<E>
}
```

## Reference

| Constructor | Use Case | Error Type |
|-------------|----------|------------|
| `succeed(value)` | Pure value | never |
| `fail(error)` | Known failure | E |
| `sync(fn)` | Sync side effect (won't throw) | never |
| `try(fn)` | Sync that might throw | UnknownException |
| `promise(fn)` | Async (won't reject) | never |
| `tryPromise(fn)` | Async that might reject | UnknownException |
| `async(cb)` | Callback-based API | E |

| Runner | Returns | Behavior |
|--------|---------|----------|
| `runSync` | A | Throws on async/error |
| `runPromise` | Promise\<A\> | Throws FiberFailure |
| `runPromiseExit` | Promise\<Exit\<A, E\>\> | Typed Exit |
