# Platform

The `@effect/platform` package provides platform-independent abstractions for common operations like HTTP clients/servers, file system access, and more. Platform-specific implementations exist in `@effect/platform-node`, `@effect/platform-bun`, and `@effect/platform-browser`.

## Overview of @effect/platform

The package offers several key modules:

- **HttpClient** - Make HTTP requests with typed responses
- **HttpServer/HttpApi** - Build type-safe HTTP servers with auto-generated docs
- **FileSystem** - Platform-agnostic file operations
- **Terminal** - Interactive terminal I/O
- **KeyValueStore** - Simple key-value storage abstraction

All modules follow the Effect pattern: they're defined as services that require platform-specific layers to run.

## HTTP Client

The HTTP client provides a composable way to make HTTP requests with Schema-validated responses.

### Basic Requests

```typescript
import {
  FetchHttpClient,
  HttpClient,
  HttpClientRequest,
  HttpClientResponse
} from "@effect/platform"
import { Effect, Schema } from "effect"

// Define response schema
class User extends Schema.Class<User>("User")({
  id: Schema.Number,
  name: Schema.String,
  email: Schema.String
}) {}

const fetchUser = Effect.gen(function* () {
  const client = yield* HttpClient.HttpClient

  const response = yield* client.get("https://api.example.com/users/1")

  // Decode JSON response with Schema
  return yield* HttpClientResponse.schemaBodyJson(User)(response)
}).pipe(
  Effect.scoped,
  Effect.provide(FetchHttpClient.layer)
)
```

### Building a Reusable Client

Create a configured client with base URL and default headers:

```typescript
import {
  FetchHttpClient,
  HttpClient,
  HttpClientRequest,
  HttpClientResponse
} from "@effect/platform"
import { Effect, flow, Layer, Schema } from "effect"

class Pokemon extends Schema.Class<Pokemon>("Pokemon")({
  id: Schema.Number,
  name: Schema.String,
  height: Schema.Number,
  weight: Schema.Number
}) {}

const makePokeApiClient = Effect.gen(function* () {
  const baseClient = yield* HttpClient.HttpClient

  // Configure client with base URL and JSON headers
  const client = baseClient.pipe(
    HttpClient.mapRequest(
      flow(
        HttpClientRequest.acceptJson,
        HttpClientRequest.prependUrl("https://pokeapi.co/api/v2")
      )
    ),
    HttpClient.filterStatusOk // Fail on non-2xx status
  )

  return {
    getPokemon: (name: string) =>
      client.get(`/pokemon/${name}`).pipe(
        Effect.flatMap(HttpClientResponse.schemaBodyJson(Pokemon)),
        Effect.scoped
      )
  }
})

// Usage
const program = Effect.gen(function* () {
  const pokeApi = yield* makePokeApiClient
  const pikachu = yield* pokeApi.getPokemon("pikachu")
  console.log(pikachu.name, pikachu.height)
}).pipe(Effect.provide(FetchHttpClient.layer))
```

### POST Requests with JSON Body

```typescript
import {
  FetchHttpClient,
  HttpClient,
  HttpClientRequest,
  HttpClientResponse
} from "@effect/platform"
import { Effect, Schema } from "effect"

const CreateTodo = Schema.Struct({
  title: Schema.String,
  completed: Schema.Boolean
})

const Todo = Schema.Struct({
  id: Schema.Number,
  title: Schema.String,
  completed: Schema.Boolean
})

const createTodo = (todo: typeof CreateTodo.Type) =>
  Effect.gen(function* () {
    const client = yield* HttpClient.HttpClient

    // Build request with JSON body
    const request = yield* HttpClientRequest.post("/todos").pipe(
      HttpClientRequest.schemaBodyJson(CreateTodo)
    )(todo)

    const response = yield* client.execute(
      HttpClientRequest.prependUrl("https://jsonplaceholder.typicode.com")(request)
    )

    return yield* HttpClientResponse.schemaBodyJson(Todo)(response)
  }).pipe(
    Effect.scoped,
    Effect.provide(FetchHttpClient.layer)
  )
```

### Platform-Specific Layers

Choose the appropriate HTTP client layer for your runtime:

```typescript
// Browser/Bun - uses fetch
import { FetchHttpClient } from "@effect/platform"
const layer = FetchHttpClient.layer

// Node.js - uses http/https modules
import { NodeHttpClient } from "@effect/platform-node"
const layer = NodeHttpClient.layer
```

## HTTP API (Server)

The HttpApi module provides a declarative way to define type-safe HTTP APIs with automatic Swagger documentation and client generation.

### Defining an API

```typescript
import {
  HttpApi,
  HttpApiEndpoint,
  HttpApiGroup,
  HttpApiSchema
} from "@effect/platform"
import { Schema } from "effect"

// Define schemas
const User = Schema.Struct({
  id: Schema.Number,
  name: Schema.String,
  createdAt: Schema.DateTimeUtc
})

const idParam = HttpApiSchema.param("id", Schema.NumberFromString)

// Define endpoints
const getUsers = HttpApiEndpoint.get("getUsers", "/users")
  .addSuccess(Schema.Array(User))

const getUser = HttpApiEndpoint.get("getUser")`/users/${idParam}`
  .addSuccess(User)
  .addError(Schema.String, { status: 404 })

const createUser = HttpApiEndpoint.post("createUser", "/users")
  .setPayload(Schema.Struct({ name: Schema.String }))
  .addSuccess(User, { status: 201 })

// Group endpoints
const usersGroup = HttpApiGroup.make("users")
  .add(getUsers)
  .add(getUser)
  .add(createUser)

// Create the API
const api = HttpApi.make("myApi").add(usersGroup)
```

### Implementing and Serving the API

```typescript
import {
  HttpApi,
  HttpApiBuilder,
  HttpApiEndpoint,
  HttpApiGroup,
  HttpApiSchema,
  HttpApiSwagger,
  HttpMiddleware,
  HttpServer
} from "@effect/platform"
import { NodeHttpServer, NodeRuntime } from "@effect/platform-node"
import { DateTime, Effect, Layer, Schema } from "effect"
import { createServer } from "node:http"

const User = Schema.Struct({
  id: Schema.Number,
  name: Schema.String,
  createdAt: Schema.DateTimeUtc
})

const idParam = HttpApiSchema.param("id", Schema.NumberFromString)

const usersGroup = HttpApiGroup.make("users").add(
  HttpApiEndpoint.get("getUser")`/users/${idParam}`.addSuccess(User)
)

const api = HttpApi.make("myApi").add(usersGroup)

// Implement the group handlers
const usersGroupLive = HttpApiBuilder.group(api, "users", (handlers) =>
  handlers.handle("getUser", ({ path: { id } }) =>
    Effect.succeed({
      id,
      name: "John Doe",
      createdAt: DateTime.unsafeNow()
    })
  )
)

// Combine into API layer
const MyApiLive = HttpApiBuilder.api(api).pipe(Layer.provide(usersGroupLive))

// Serve with middleware
const ServerLive = HttpApiBuilder.serve(HttpMiddleware.logger).pipe(
  Layer.provide(HttpApiSwagger.layer()), // Auto-generate /docs
  Layer.provide(HttpApiBuilder.middlewareCors()),
  Layer.provide(MyApiLive),
  HttpServer.withLogAddress,
  Layer.provide(NodeHttpServer.layer(createServer, { port: 3000 }))
)

Layer.launch(ServerLive).pipe(NodeRuntime.runMain)
```

### Deriving a Client

Generate a fully typed client from your API definition:

```typescript
import { FetchHttpClient, HttpApiClient } from "@effect/platform"
import { Effect } from "effect"

// api is the same HttpApi definition from the server
const program = Effect.gen(function* () {
  const client = yield* HttpApiClient.make(api, {
    baseUrl: "http://localhost:3000"
  })

  // Fully typed! client.users["getUser"]({ path: { id: 1 } })
  const user = yield* client.users["getUser"]({ path: { id: 1 } })
  console.log(user.name)
}).pipe(Effect.provide(FetchHttpClient.layer))
```

### Lower-Level Router API

For simpler use cases, use `HttpRouter` directly:

```typescript
import {
  HttpMiddleware,
  HttpRouter,
  HttpServer,
  HttpServerRequest,
  HttpServerResponse
} from "@effect/platform"
import { NodeHttpServer, NodeRuntime } from "@effect/platform-node"
import { Effect, Layer } from "effect"
import { createServer } from "node:http"

const router = HttpRouter.empty.pipe(
  HttpRouter.get("/", HttpServerResponse.text("Hello, World!")),

  HttpRouter.get("/echo", Effect.gen(function* () {
    const req = yield* HttpServerRequest.HttpServerRequest
    return HttpServerResponse.text(`You requested: ${req.url}`)
  })),

  HttpRouter.post("/data", Effect.gen(function* () {
    const req = yield* HttpServerRequest.HttpServerRequest
    const body = yield* req.json
    return HttpServerResponse.json({ received: body })
  }))
)

const ServerLive = router.pipe(
  HttpServer.serve(HttpMiddleware.logger),
  HttpServer.withLogAddress,
  Layer.provide(NodeHttpServer.layer(createServer, { port: 3000 }))
)

Layer.launch(ServerLive).pipe(NodeRuntime.runMain)
```

## FileSystem

The FileSystem service provides platform-agnostic file operations. All operations return Effects that may fail with `PlatformError`.

### Basic Operations

```typescript
import { FileSystem } from "@effect/platform"
import { NodeContext, NodeRuntime } from "@effect/platform-node"
import { Effect } from "effect"

const program = Effect.gen(function* () {
  const fs = yield* FileSystem.FileSystem

  // Check if file exists
  const exists = yield* fs.exists("./config.json")

  // Read file as string
  const content = yield* fs.readFileString("./config.json")

  // Read file as bytes
  const bytes = yield* fs.readFile("./image.png")

  // Write string to file
  yield* fs.writeFileString("./output.txt", "Hello, Effect!")

  // Write bytes
  yield* fs.writeFile("./data.bin", new Uint8Array([1, 2, 3]))

  // Create directory (recursive by default)
  yield* fs.makeDirectory("./nested/dirs", { recursive: true })

  // List directory contents
  const files = yield* fs.readDirectory("./src")

  // Copy files
  yield* fs.copy("./source", "./destination")

  // Remove file or directory
  yield* fs.remove("./temp", { recursive: true })
})

program.pipe(Effect.provide(NodeContext.layer), NodeRuntime.runMain)
```

### Streaming Files

```typescript
import { FileSystem } from "@effect/platform"
import { NodeContext, NodeRuntime } from "@effect/platform-node"
import { Console, Effect, Stream } from "effect"

const program = Effect.gen(function* () {
  const fs = yield* FileSystem.FileSystem

  // Stream file contents
  yield* fs.stream("./large-file.txt").pipe(
    Stream.decodeText("utf-8"),
    Stream.splitLines,
    Stream.take(10),
    Stream.runForEach(Console.log)
  )

  // Write stream to file using sink
  yield* Stream.make("line1\n", "line2\n", "line3\n").pipe(
    Stream.encodeText,
    Stream.run(fs.sink("./output.txt"))
  )
})

program.pipe(Effect.provide(NodeContext.layer), NodeRuntime.runMain)
```

### Temporary Files and Directories

```typescript
import { FileSystem } from "@effect/platform"
import { NodeContext, NodeRuntime } from "@effect/platform-node"
import { Effect } from "effect"

const program = Effect.gen(function* () {
  const fs = yield* FileSystem.FileSystem

  // Create temp directory (cleaned up manually)
  const tempDir = yield* fs.makeTempDirectory({ prefix: "myapp-" })

  // Create temp directory that's cleaned up when scope closes
  const scopedDir = yield* fs.makeTempDirectoryScoped({ prefix: "work-" })
  // Use scopedDir... automatically removed when scope ends

  // Create temp file
  const tempFile = yield* fs.makeTempFileScoped()
  yield* fs.writeFileString(tempFile, "temporary data")
}).pipe(Effect.scoped) // Scope ensures cleanup

program.pipe(Effect.provide(NodeContext.layer), NodeRuntime.runMain)
```

### Watching for Changes

```typescript
import { FileSystem } from "@effect/platform"
import { NodeFileSystem, NodeRuntime } from "@effect/platform-node"
import { Console, Effect, Stream } from "effect"

const program = Effect.gen(function* () {
  const fs = yield* FileSystem.FileSystem

  yield* fs.watch("./src", { recursive: true }).pipe(
    Stream.runForEach((event) =>
      Console.log(`${event.type}: ${event.path}`)
    )
  )
})

program.pipe(Effect.provide(NodeFileSystem.layer), NodeRuntime.runMain)
```

## Terminal

The Terminal service provides interactive command-line I/O:

```typescript
import { Terminal } from "@effect/platform"
import { NodeRuntime, NodeTerminal } from "@effect/platform-node"
import { Console, Effect } from "effect"

const program = Effect.gen(function* () {
  const terminal = yield* Terminal.Terminal

  // Read a line from stdin
  yield* Console.log("What's your name?")
  const name = yield* terminal.readLine

  yield* Console.log(`Hello, ${name}!`)

  // Read another line
  yield* Console.log("What's your favorite color?")
  const color = yield* terminal.readLine

  yield* Console.log(`${name} likes ${color}!`)
})

program.pipe(Effect.provide(NodeTerminal.layer), NodeRuntime.runMain)
```

## KeyValueStore

A simple key-value storage abstraction with multiple backends:

```typescript
import { KeyValueStore } from "@effect/platform"
import { Effect } from "effect"

const program = Effect.gen(function* () {
  const kv = yield* KeyValueStore.KeyValueStore

  // Set a value
  yield* kv.set("user:1", JSON.stringify({ name: "Alice" }))

  // Get a value (returns Option)
  const value = yield* kv.get("user:1")

  // Check if key exists
  const exists = yield* kv.has("user:1")

  // Remove a key
  yield* kv.remove("user:1")

  // Clear all keys
  yield* kv.clear
}).pipe(
  // Use in-memory store
  Effect.provide(KeyValueStore.layerMemory)
)

// Or use file-system backed store (Node.js)
import { NodeKeyValueStore } from "@effect/platform-node"
const fsBackedStore = NodeKeyValueStore.layerFileSystem("./data/kv")

// Or use browser localStorage
import { BrowserKeyValueStore } from "@effect/platform-browser"
const browserStore = BrowserKeyValueStore.layerLocalStorage
```

## Platform Layers

Each platform provides a convenience layer that bundles common services:

```typescript
// Node.js - includes FileSystem, Path, Terminal, etc.
import { NodeContext } from "@effect/platform-node"
Effect.provide(NodeContext.layer)

// Bun - includes FileSystem, Path, Terminal, etc.
import { BunContext } from "@effect/platform-bun"
Effect.provide(BunContext.layer)

// Browser - includes limited services
import { BrowserContext } from "@effect/platform-browser"
Effect.provide(BrowserContext.layer)
```

## runMain

Each platform provides a `runMain` function that properly handles the Effect lifecycle:

```typescript
import { NodeRuntime } from "@effect/platform-node"
import { Effect } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.log("Application starting...")
  // Your app logic
  yield* Effect.log("Done!")
})

// Handles interruption, logging, and exit codes
NodeRuntime.runMain(program)
```

Key behaviors of `runMain`:
- Logs errors and sets appropriate exit codes
- Handles SIGINT/SIGTERM for graceful shutdown
- Properly tears down resources on interruption
- Uses the platform's default runtime configuration
