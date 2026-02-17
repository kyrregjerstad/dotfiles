# Batching & Requests

Effect provides a powerful system for automatically batching and deduplicating data requests. This is invaluable for optimizing database queries, API calls, and other I/O operations by combining multiple individual requests into efficient batch operations.

## Request & RequestResolver

The batching system consists of two core concepts:
- **Request**: A description of a data fetch operation with typed success and error values
- **RequestResolver**: A handler that knows how to fulfill requests, potentially in batches

### Defining Requests

Use `Request.TaggedClass` to define request types with typed responses:

```typescript
import { Request } from "effect"

// Request that returns a string (user name), fails with string error
class GetUserById extends Request.TaggedClass("GetUserById")<
  string,   // Success type
  string,   // Error type
  { readonly id: number }  // Payload
> {}

// Request that returns an array, never fails
interface GetAllUserIds extends Request.Request<ReadonlyArray<number>> {
  readonly _tag: "GetAllUserIds"
}
const GetAllUserIds = Request.tagged<GetAllUserIds>("GetAllUserIds")
```

For Schema-integrated requests (useful with persistence/caching):

```typescript
import { Schema, PrimaryKey } from "effect"

class GetUserById extends Schema.TaggedRequest<GetUserById>()("GetUserById", {
  failure: Schema.String,
  success: Schema.Struct({ id: Schema.Number, name: Schema.String }),
  payload: { id: Schema.Number }
}) {
  [PrimaryKey.symbol]() {
    return `GetUserById:${this.id}`
  }
}
```

### Creating Request Resolvers

`RequestResolver.makeBatched` creates a resolver that receives all pending requests at once:

```typescript
import { RequestResolver, Request, Effect, Match } from "effect"

const UserResolver = RequestResolver.makeBatched(
  (requests: Array<GetUserById | GetAllUserIds>) =>
    Effect.forEach(requests, (request) =>
      Match.value(request).pipe(
        Match.tag("GetAllUserIds", (req) =>
          Request.succeed(req, [1, 2, 3])
        ),
        Match.tag("GetUserById", (req) =>
          Request.completeEffect(
            req,
            Effect.fromNullable(users.get(req.id)).pipe(
              Effect.orElseFail(() => "User not found")
            )
          )
        ),
        Match.exhaustive
      )
    , { discard: true })
)
```

For tagged requests, `fromEffectTagged` provides a cleaner API:

```typescript
const UserResolver = RequestResolver.fromEffectTagged<GetUserById | GetAllUserIds>()({
  GetAllUserIds: (requests) =>
    Effect.forEach(requests, () => Effect.succeed([1, 2, 3])),
  GetUserById: (requests) =>
    Effect.forEach(requests, (req) =>
      Effect.fromNullable(users.get(req.id)).pipe(
        Effect.orElseFail(() => "User not found")
      )
    )
})
```

### Executing Requests

Use `Effect.request` to create an effect from a request and resolver:

```typescript
// Create request effects
const getAllUserIds = Effect.request(GetAllUserIds({}), UserResolver)
const getUserById = (id: number) => Effect.request(new GetUserById({ id }), UserResolver)

// Use them in your program
const program = Effect.gen(function*() {
  const ids = yield* getAllUserIds
  const names = yield* Effect.forEach(ids, getUserById, { batching: true })
  return names
})
```

## Automatic Batching & Deduplication

### Enabling Batching

Batching is enabled via the `batching: true` option on concurrent operations:

```typescript
// These two requests are batched into a single resolver call
const result = yield* Effect.all(
  [getUserById(1), getUserById(2)],
  { concurrency: "unbounded", batching: true }
)

// Works with Effect.forEach too
const names = yield* Effect.forEach(
  [1, 2, 3],
  (id) => getUserById(id),
  { batching: true }
)

// And Effect.zip
const [a, b] = yield* Effect.zip(
  getUserById(1),
  getUserById(2),
  { concurrent: true, batching: true }
)
```

You can also enable batching globally with `Effect.withRequestBatching`:

```typescript
const program = myEffect.pipe(
  Effect.withRequestBatching(true)
)
```

Or via a Layer:

```typescript
const BatchingLayer = Layer.setRequestBatching(true)

const program = myEffect.pipe(Effect.provide(BatchingLayer))
```

### How Batching Works

When batching is enabled:
1. Effect collects all pending requests during an execution step
2. Requests to the same resolver are grouped together
3. The resolver receives all requests in a single `runAll` call
4. Results are distributed back to their original callers

The resolver receives requests as `Array<Array<Request>>`:
- Outer array: batches that must run sequentially
- Inner array: requests that can run in parallel

### Nested Batching

Batching works across nested effect structures:

```typescript
const program = Effect.gen(function*() {
  const parents = yield* getAllParents  // 1st resolver call

  yield* Effect.forEach(
    parents,
    (parent) =>
      Effect.flatMap(
        getChildren(parent.id),  // 2nd call (batched)
        (children) =>
          Effect.forEach(
            children,
            (child) =>
              Effect.zip(
                getChildInfo(child.id),   // 3rd call (batched together)
                getChildExtra(child.id),
                { concurrent: true, batching: "inherit" }
              ),
            { concurrency: "unbounded", batching: "inherit" }
          )
      ),
    { concurrency: "inherit", batching: "inherit" }
  )
})
```

With `batching: "inherit"`, child operations inherit batching settings from parents.

### Request Deduplication

Even with batching disabled, identical requests are deduplicated:

```typescript
// Both requests get the same cached result - resolver called once
const [a, b] = yield* Effect.all(
  [getUserById(1), getUserById(1)],
  { concurrency: "unbounded", batching: true }
).pipe(Effect.withRequestCaching(true))
```

### Request Caching

Enable caching to avoid re-fetching:

```typescript
import { Request, Layer } from "effect"

// Configure cache with capacity and TTL
const CacheLayer = Layer.mergeAll(
  Layer.setRequestCache(Request.makeCache({
    capacity: 100,
    timeToLive: "60 seconds"
  })),
  Layer.setRequestCaching(true)
)

// Or toggle caching per-effect
const cached = myEffect.pipe(Effect.withRequestCaching(true))

// Pre-warm cache
yield* Effect.cacheRequestResult(
  new GetUserById({ id: 1 }),
  Exit.succeed("John")
)
```

## Resolver Configuration

### Limiting Batch Size

Use `batchN` to limit how many requests are processed at once:

```typescript
const LimitedResolver = UserResolver.pipe(
  RequestResolver.batchN(15)  // Max 15 requests per batch
)
```

### Providing Context to Resolvers

Resolvers can require services from the environment:

```typescript
const UserResolver = RequestResolver.makeBatched(
  (requests: Array<GetUserById>) =>
    Effect.gen(function*() {
      const db = yield* Database
      // Use db to fulfill requests...
    })
).pipe(
  RequestResolver.contextFromServices(Database)
)
```

### Lifecycle Hooks

Add logic before/after resolver execution:

```typescript
const traced = RequestResolver.aroundRequests(
  UserResolver,
  (requests) => Effect.log(`Processing ${requests.length} requests`),
  (requests, _) => Effect.log(`Completed ${requests.length} requests`)
)
```

## SQL Resolvers

The `@effect/sql` package provides pre-built resolver patterns for database operations:

```typescript
import { SqlResolver, SqlClient } from "@effect/sql"
import { Schema } from "effect"

class Person extends Schema.Class<Person>("Person")({
  id: Schema.Number,
  name: Schema.String
}) {}

const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient

  // Ordered resolver - results match request order
  const Insert = yield* SqlResolver.ordered("InsertPerson", {
    Request: Schema.Struct({ name: Schema.String }),
    Result: Person,
    execute: (requests) => sql`INSERT INTO people ${sql.insert(requests)} RETURNING *`
  })

  // FindById resolver - matches results to requests by ID
  const GetById = yield* SqlResolver.findById("GetPersonById", {
    Id: Schema.Number,
    Result: Person,
    ResultId: (result) => result.id,
    execute: (ids) => sql`SELECT * FROM people WHERE id IN ${sql.in(ids)}`
  })

  // Grouped resolver - returns arrays grouped by key
  const GetByName = yield* SqlResolver.grouped("GetPersonByName", {
    Request: Schema.String,
    RequestGroupKey: (name) => name,
    Result: Person,
    ResultGroupKey: (person) => person.name,
    execute: (names) => sql`SELECT * FROM people WHERE name IN ${sql.in(names)}`
  })

  // Execute batched
  const [john, jane] = yield* Effect.all(
    [Insert.execute({ name: "John" }), Insert.execute({ name: "Jane" })],
    { batching: true }
  )

  const people = yield* Effect.all(
    [GetById.execute(john.id), GetById.execute(jane.id)],
    { batching: true }
  )
})
```

### Resolver Types

- **`ordered`**: Results must be in same order as requests
- **`findById`**: Match results to requests using an ID field
- **`grouped`**: Group multiple results per request using a key
- **`void`**: For operations that don't return data (INSERT/UPDATE)

## Practical Patterns

### API Data Loader

```typescript
class FetchUser extends Request.TaggedClass("FetchUser")<
  User,
  FetchError,
  { id: string }
> {}

const ApiResolver = RequestResolver.makeBatched(
  (requests: Array<FetchUser>) =>
    Effect.gen(function*() {
      // Single batch API call
      const ids = requests.map(r => r.id)
      const response = yield* Http.get(`/api/users?ids=${ids.join(",")}`)
      const users = yield* Schema.decodeUnknown(Schema.Array(User))(response)

      // Complete each request
      yield* Effect.forEach(requests, (req) =>
        Request.completeEffect(
          req,
          Effect.fromNullable(users.find(u => u.id === req.id)).pipe(
            Effect.orElseFail(() => new FetchError({ id: req.id }))
          )
        )
      )
    })
)

const fetchUser = (id: string) => Effect.request(new FetchUser({ id }), ApiResolver)
```

### GraphQL-style Data Loading

```typescript
const loadUserWithPosts = (userId: number) =>
  Effect.gen(function*() {
    const user = yield* getUserById(userId)
    const posts = yield* getPostsByUser(userId)
    const comments = yield* Effect.forEach(
      posts,
      (post) => getCommentsByPost(post.id),
      { batching: true }
    )
    return { user, posts, comments }
  })

// Load multiple users - all queries batched appropriately
const users = yield* Effect.forEach(
  [1, 2, 3],
  loadUserWithPosts,
  { batching: true, concurrency: "unbounded" }
)
```
