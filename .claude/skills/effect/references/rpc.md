# RPC

The `@effect/rpc` library provides a type-safe framework for building remote procedure call systems. It handles serialization, transport protocols, and error handling while maintaining full end-to-end type safety between client and server.

## Defining RPCs with RpcGroup and Rpc

RPCs are defined using `Rpc.make` and grouped together using `RpcGroup.make`. Each RPC specifies its name, payload schema, success schema, and optional error schema.

```ts
import { Rpc, RpcGroup } from "@effect/rpc"
import { Schema } from "effect"

// Define a domain model
class User extends Schema.Class<User>("User")({
  id: Schema.String,
  name: Schema.String
}) {}

// Define a group of RPCs
class UserRpcs extends RpcGroup.make(
  // Simple RPC with no payload
  Rpc.make("GetAllUsers", {
    success: Schema.Array(User)
  }),

  // RPC with payload and error
  Rpc.make("GetUserById", {
    success: User,
    error: Schema.String,
    payload: {
      id: Schema.String
    }
  }),

  // RPC with complex payload
  Rpc.make("CreateUser", {
    success: User,
    payload: {
      name: Schema.String,
      email: Schema.optionalWith(Schema.String, { default: () => "" })
    }
  })
) {}
```

For streaming responses, set `stream: true`:

```ts
class StreamRpcs extends RpcGroup.make(
  Rpc.make("StreamUsers", {
    success: User,
    stream: true,  // Returns a Stream<User, never>
    payload: {
      filter: Schema.optional(Schema.String)
    }
  }),

  Rpc.make("StreamWithErrors", {
    success: Schema.Number,
    error: Schema.String,  // Stream error type
    stream: true
  })
) {}
```

## Implementing Handlers

Handlers implement the business logic for each RPC. Use `RpcGroup.toLayer` to create a Layer from handler implementations:

```ts
import { Effect, Layer, Ref, Stream } from "effect"

// Define a service for data access
class UserRepository extends Effect.Service<UserRepository>()("UserRepository", {
  effect: Effect.gen(function* () {
    const users = yield* Ref.make<User[]>([
      new User({ id: "1", name: "Alice" }),
      new User({ id: "2", name: "Bob" })
    ])

    return {
      findAll: Ref.get(users),

      findById: (id: string) =>
        Ref.get(users).pipe(
          Effect.flatMap((list) => {
            const user = list.find((u) => u.id === id)
            return user
              ? Effect.succeed(user)
              : Effect.fail(`User not found: ${id}`)
          })
        ),

      create: (name: string) =>
        Ref.updateAndGet(users, (list) => [
          ...list,
          new User({ id: String(list.length + 1), name })
        ]).pipe(Effect.map((list) => list[list.length - 1]))
    }
  })
}) {}

// Implement handlers
const HandlersLive = UserRpcs.toLayer(
  Effect.gen(function* () {
    const repo = yield* UserRepository

    return {
      GetAllUsers: () => repo.findAll,
      GetUserById: ({ id }) => repo.findById(id),
      CreateUser: ({ name }) => repo.create(name)
    }
  })
).pipe(Layer.provide(UserRepository.Default))
```

For streaming handlers, return a `Stream` or `Mailbox`:

```ts
const StreamHandlersLive = StreamRpcs.toLayer(
  Effect.gen(function* () {
    return {
      StreamUsers: ({ filter }) =>
        Stream.fromIterable([
          new User({ id: "1", name: "Alice" }),
          new User({ id: "2", name: "Bob" })
        ]).pipe(
          Stream.filter((u) => !filter || u.name.includes(filter))
        ),

      StreamWithErrors: () =>
        Stream.range(1, 10).pipe(
          Stream.tap((n) =>
            n === 5
              ? Stream.fail("Error at 5")
              : Stream.succeed(n)
          )
        )
    }
  })
)
```

## Schema-Based Serialization

`@effect/rpc` supports multiple serialization formats through `RpcSerialization`:

```ts
import { RpcSerialization } from "@effect/rpc"

// NDJSON - newline-delimited JSON (default, good for streaming)
RpcSerialization.layerNdjson

// JSON - standard JSON (for protocols without framing)
RpcSerialization.layerJson

// MessagePack - binary format (smaller, faster)
RpcSerialization.layerMsgPack

// JSON-RPC - standard JSON-RPC 2.0 format
RpcSerialization.layerJsonRpc()

// NDJSON-RPC - JSON-RPC with newline delimiters
RpcSerialization.layerNdJsonRpc()
```

Serialization uses Effect Schema under the hood, so all schema transformations apply:

```ts
class UserRpcs extends RpcGroup.make(
  Rpc.make("GetUser", {
    success: User,
    payload: {
      // Schema transformations work automatically
      id: Schema.NumberFromString
    }
  })
) {}
```

## Server Setup

Create an RPC server using `RpcServer.layer` with a protocol layer:

### HTTP Server

```ts
import { HttpRouter } from "@effect/platform"
import { BunHttpServer, BunRuntime } from "@effect/platform-bun"
import { RpcServer, RpcSerialization } from "@effect/rpc"
import { Layer } from "effect"

// Create RPC server layer
const RpcLayer = RpcServer.layer(UserRpcs).pipe(
  Layer.provide(HandlersLive)
)

// Configure HTTP protocol at /rpc endpoint
const HttpProtocol = RpcServer.layerProtocolHttp({ path: "/rpc" }).pipe(
  Layer.provide(RpcSerialization.layerNdjson)
)

// Compose and serve
const Main = HttpRouter.Default.serve().pipe(
  Layer.provide(RpcLayer),
  Layer.provide(HttpProtocol),
  Layer.provide(BunHttpServer.layer({ port: 3000 }))
)

BunRuntime.runMain(Layer.launch(Main))
```

### WebSocket Server

```ts
const WsProtocol = RpcServer.layerProtocolWebsocket({ path: "/rpc" }).pipe(
  Layer.provide(RpcSerialization.layerMsgPack)
)

const Main = HttpRouter.Default.serve().pipe(
  Layer.provide(RpcLayer),
  Layer.provide(WsProtocol),
  Layer.provide(BunHttpServer.layer({ port: 3000 }))
)
```

### TCP Socket Server

```ts
import { NodeSocketServer } from "@effect/platform-node"
import { SocketServer } from "@effect/platform"

const TcpServer = RpcLayer.pipe(
  Layer.provideMerge(RpcServer.layerProtocolSocketServer),
  Layer.provide(RpcSerialization.layerNdjson),
  Layer.provide(NodeSocketServer.layer({ port: 9000 }))
)
```

### Worker Server (Browser)

```ts
import * as BrowserRuntime from "@effect/platform-browser/BrowserRuntime"
import * as BrowserWorkerRunner from "@effect/platform-browser/BrowserWorkerRunner"
import { RpcServer } from "@effect/rpc"

const WorkerServer = RpcServer.layer(WorkerRpcs).pipe(
  Layer.provide(HandlersLive),
  Layer.provide(RpcServer.layerProtocolWorkerRunner),
  Layer.provide(BrowserWorkerRunner.layer)
)

BrowserRuntime.runMain(BrowserWorkerRunner.launch(WorkerServer))
```

## Client Setup

Create type-safe RPC clients using `RpcClient.make`:

### HTTP Client

```ts
import { FetchHttpClient } from "@effect/platform"
import { RpcClient, RpcSerialization } from "@effect/rpc"
import { Effect, Layer, Stream } from "effect"

// Configure protocol
const ProtocolLive = RpcClient.layerProtocolHttp({
  url: "http://localhost:3000/rpc"
}).pipe(
  Layer.provide([
    FetchHttpClient.layer,
    RpcSerialization.layerNdjson
  ])
)

// Use the client
const program = Effect.gen(function* () {
  const client = yield* RpcClient.make(UserRpcs)

  // Call simple RPC
  const users = yield* client.GetAllUsers({})

  // Call RPC with payload
  const user = yield* client.GetUserById({ id: "1" })

  // Handle streaming RPC
  const stream = client.StreamUsers({ filter: "A" })
  const collected = yield* Stream.runCollect(stream)

  return { users, user, collected }
}).pipe(Effect.scoped)

program.pipe(
  Effect.provide(ProtocolLive),
  Effect.runPromise
)
```

### WebSocket Client

```ts
import { NodeSocket } from "@effect/platform-node"

const WsProtocol = RpcClient.layerProtocolSocket().pipe(
  Layer.provide(NodeSocket.layerWebSocket("ws://localhost:3000/rpc")),
  Layer.provide(RpcSerialization.layerMsgPack)
)
```

### Worker Client (Browser)

```ts
import * as BrowserWorker from "@effect/platform-browser/BrowserWorker"
import { RpcClient } from "@effect/rpc"
import MyWorker from "./worker.ts?worker"

const WorkerProtocol = RpcClient.layerProtocolWorker({
  size: 1,           // Number of worker instances
  concurrency: 1     // Concurrent requests per worker
}).pipe(
  Layer.provide(BrowserWorker.layerPlatform(() => new MyWorker()))
)

class WorkerClient extends Effect.Service<WorkerClient>()("WorkerClient", {
  dependencies: [WorkerProtocol],
  scoped: Effect.gen(function* () {
    return { client: yield* RpcClient.make(WorkerRpcs) }
  })
}) {}
```

## Middleware

Middleware intercepts RPC calls on both server and client. Define middleware using `RpcMiddleware.Tag`:

```ts
import { RpcMiddleware } from "@effect/rpc"
import { Context, Effect, Layer, Headers } from "effect"

// Define what middleware provides
class CurrentUser extends Context.Tag("CurrentUser")<CurrentUser, User>() {}

// Define the middleware tag
class AuthMiddleware extends RpcMiddleware.Tag<AuthMiddleware>()("AuthMiddleware", {
  provides: CurrentUser,           // Context it provides to handlers
  failure: Schema.String,          // Error type if auth fails
  requiredForClient: true          // Must implement on client too
}) {}
```

Apply middleware to RPCs:

```ts
class SecureRpcs extends RpcGroup.make(
  Rpc.make("GetProfile", { success: User })
    .middleware(AuthMiddleware),  // Apply to single RPC

  Rpc.make("UpdateProfile", {
    success: User,
    payload: { name: Schema.String }
  })
)
  .middleware(AuthMiddleware)  // Apply to entire group
{}
```

Implement server middleware:

```ts
const AuthServerLive = Layer.succeed(
  AuthMiddleware,
  AuthMiddleware.of(({ headers, payload, rpc }) =>
    Effect.gen(function* () {
      const token = Headers.get(headers, "authorization")
      if (!token) {
        return yield* Effect.fail("Missing authorization header")
      }
      // Validate token and return user
      return new User({ id: "123", name: "Authenticated User" })
    })
  )
)

const ServerLive = RpcServer.layer(SecureRpcs).pipe(
  Layer.provide(HandlersLive),
  Layer.provide(AuthServerLive)
)
```

Implement client middleware:

```ts
const AuthClientLive = RpcMiddleware.layerClient(
  AuthMiddleware,
  ({ request, rpc }) =>
    Effect.succeed({
      ...request,
      headers: Headers.set(request.headers, "authorization", "Bearer my-token")
    })
)

const ClientLive = Layer.scoped(
  UsersClient,
  RpcClient.make(SecureRpcs)
).pipe(Layer.provide(AuthClientLive))
```

### Wrapping Middleware

Middleware can also wrap handler execution for cross-cutting concerns:

```ts
import { Metric } from "effect"

class TimingMiddleware extends RpcMiddleware.Tag<TimingMiddleware>()("TimingMiddleware", {
  wrap: true  // Wraps handler execution
}) {}

const rpcDuration = Metric.histogram("rpc_duration_ms")
const rpcErrors = Metric.counter("rpc_errors")

const TimingLive = Layer.succeed(
  TimingMiddleware,
  TimingMiddleware.of(({ next, rpc }) =>
    next.pipe(
      Effect.tap(() => Effect.logInfo(`RPC ${rpc._tag} succeeded`)),
      Effect.tapError(() => Metric.increment(rpcErrors)),
      Effect.timed,
      Effect.tap(([duration]) =>
        Metric.update(rpcDuration, duration.millis)
      ),
      Effect.map(([, result]) => result)
    )
  )
)
```

## Testing RPCs

Use `RpcTest.makeClient` for in-memory testing without network:

```ts
import { RpcTest } from "@effect/rpc"
import { it } from "@effect/vitest"

class UsersClient extends Context.Tag("UsersClient")<
  UsersClient,
  RpcClient.RpcClient<typeof UserRpcs>
>() {
  // Production layer using real protocol
  static layer = Layer.scoped(UsersClient, RpcClient.make(UserRpcs))

  // Test layer using in-memory transport
  static layerTest = Layer.scoped(
    UsersClient,
    RpcTest.makeClient(UserRpcs)
  ).pipe(
    Layer.provide(HandlersLive)
  )
}

it.effect("fetches user by id", () =>
  Effect.gen(function* () {
    const client = yield* UsersClient
    const user = yield* client.GetUserById({ id: "1" })
    expect(user.name).toBe("Alice")
  }).pipe(Effect.provide(UsersClient.layerTest))
)
```

## Complete Example

Here's a complete example showing client and server setup:

**request.ts** - Shared RPC definitions:
```ts
import { Rpc, RpcGroup } from "@effect/rpc"
import { Schema } from "effect"

export class Todo extends Schema.Class<Todo>("Todo")({
  id: Schema.Number,
  title: Schema.String,
  completed: Schema.Boolean
}) {}

export class TodoRpcs extends RpcGroup.make(
  Rpc.make("List", {
    success: Schema.Array(Todo)
  }),
  Rpc.make("Create", {
    success: Todo,
    payload: { title: Schema.String }
  }),
  Rpc.make("Toggle", {
    success: Todo,
    error: Schema.String,
    payload: { id: Schema.Number }
  })
) {}
```

**server.ts** - Server implementation:
```ts
import { HttpRouter } from "@effect/platform"
import { BunHttpServer, BunRuntime } from "@effect/platform-bun"
import { RpcServer, RpcSerialization } from "@effect/rpc"
import { Effect, Layer, Ref } from "effect"
import { Todo, TodoRpcs } from "./request.js"

const HandlersLive = TodoRpcs.toLayer(
  Effect.gen(function* () {
    const todos = yield* Ref.make<Todo[]>([])
    let nextId = 1

    return {
      List: () => Ref.get(todos),

      Create: ({ title }) =>
        Ref.updateAndGet(todos, (list) => [
          ...list,
          new Todo({ id: nextId++, title, completed: false })
        ]).pipe(Effect.map((list) => list[list.length - 1])),

      Toggle: ({ id }) =>
        Ref.get(todos).pipe(
          Effect.flatMap((list) => {
            const idx = list.findIndex((t) => t.id === id)
            if (idx === -1) return Effect.fail(`Todo ${id} not found`)
            const updated = new Todo({
              ...list[idx],
              completed: !list[idx].completed
            })
            return Ref.set(todos, [
              ...list.slice(0, idx),
              updated,
              ...list.slice(idx + 1)
            ]).pipe(Effect.as(updated))
          })
        )
    }
  })
)

const Main = HttpRouter.Default.serve().pipe(
  Layer.provide(RpcServer.layer(TodoRpcs)),
  Layer.provide(HandlersLive),
  Layer.provide(RpcServer.layerProtocolHttp({ path: "/rpc" })),
  Layer.provide(RpcSerialization.layerNdjson),
  Layer.provide(BunHttpServer.layer({ port: 3000 }))
)

BunRuntime.runMain(Layer.launch(Main))
```

**client.ts** - Client usage:
```ts
import { FetchHttpClient } from "@effect/platform"
import { RpcClient, RpcSerialization } from "@effect/rpc"
import { Effect, Layer } from "effect"
import { TodoRpcs } from "./request.js"

const ProtocolLive = RpcClient.layerProtocolHttp({
  url: "http://localhost:3000/rpc"
}).pipe(
  Layer.provide([FetchHttpClient.layer, RpcSerialization.layerNdjson])
)

const program = Effect.gen(function* () {
  const client = yield* RpcClient.make(TodoRpcs)

  // Create todos
  yield* client.Create({ title: "Learn Effect" })
  yield* client.Create({ title: "Build something cool" })

  // List all
  let todos = yield* client.List({})
  console.log("All todos:", todos)

  // Toggle first todo
  yield* client.Toggle({ id: 1 })

  // List again
  todos = yield* client.List({})
  console.log("After toggle:", todos)
}).pipe(Effect.scoped)

program.pipe(
  Effect.provide(ProtocolLive),
  Effect.runPromise
)
```
