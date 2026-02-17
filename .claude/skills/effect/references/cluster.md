# Cluster

`@effect/cluster` provides a distributed systems framework for building scalable applications with automatic sharding, entity management, and durable messaging. It enables running stateful entities across multiple nodes with automatic load balancing and failover.

## Why Actors? The Problem with Horizontal Scaling

In a typical stateless application (e.g., a REST API), application logic is separated from state (database). This works well until you scale horizontally.

**The Race Condition Problem:**

When multiple server instances handle concurrent requests modifying the same data:

1. Request A fetches user balance: 100
2. Request B fetches user balance: 100
3. Request A adds 10, saves: 110
4. Request B adds 10, saves: 110 (should be 120!)

Traditional solutions like optimistic locking or database locks add complexity and performance overhead.

**The Actor Model Solution:**

Actors provide a way to maintain a **sequential processing model** even in distributed systems. Each entity (like `User:123`) becomes a **single source of truth** that processes operations one by one, eliminating race conditions.

## @effect/cluster for Distributed Systems

The cluster module is designed around several core concepts:

- **Entities**: Stateful actors that process messages sequentially, automatically distributed across cluster nodes
- **Sharding**: Automatic partitioning of entities across runners using consistent hashing
- **Runners**: Physical nodes that host and execute entities
- **Singletons**: Cluster-wide unique processes that run on exactly one node
- **Location Transparency**: You don't need to know where an actor runs—just its identity

### Core Components

```typescript
import {
  Entity,
  Singleton,
  Sharding,
  ShardingConfig,
  RunnerAddress,
  SocketRunner,
  SingleRunner
} from "@effect/cluster"
```

## Understanding the Actor Model

An Actor is a fundamental unit of computation that combines:

1. **State**: Private data held in-memory (not fetched from DB on each request)
2. **Behavior**: Logic to process messages
3. **Mailbox**: A queue of incoming messages providing backpressure

**Key Properties:**

- **Sequential Processing**: An actor picks one message, processes it, updates state, then picks the next. This eliminates race conditions for that entity.
- **In-Memory State**: Reads are instant (no DB round-trip), writes update memory immediately. Persistence is handled separately (write-behind or event sourcing).
- **Granularity**: Actors should be granular—one actor per User, not one actor for "All Users".

## Defining Entities

Entities are stateful actors that respond to RPC messages. Define an entity using `Entity.make` with a name and protocol:

```typescript
import { Entity, RunnerAddress, Singleton } from "@effect/cluster"
import { Rpc } from "@effect/rpc"
import { Effect, Schema, Layer, Option } from "effect"

// Define the entity protocol with RPC endpoints
const Counter = Entity.make("Counter", [
  Rpc.make("Increment", {
    payload: { amount: Schema.Number },
    success: Schema.Number
  }),
  Rpc.make("Decrement", {
    payload: { amount: Schema.Number },
    success: Schema.Number
  }),
  Rpc.make("GetValue", {
    success: Schema.Number
  })
])
```

### Implementing Entity Handlers

Convert an entity to a layer by providing handler implementations. Each entity instance maintains its own in-memory state:

```typescript
const CounterLive = Counter.toLayer(
  Effect.gen(function*() {
    // Access the current entity's address (Entity Type + Entity ID)
    const address = yield* Entity.CurrentAddress
    console.log("Creating Counter", address.entityId)

    // Entity-local state - kept in memory for fast access
    let state = 0

    // Cleanup on entity shutdown (passivation)
    yield* Effect.addFinalizer(() =>
      Effect.log(`Finalizing counter with value: ${state}`)
    )

    // Return handlers for each RPC - processed sequentially
    return {
      Increment: Effect.fnUntraced(function*({ payload: { amount } }) {
        state += amount
        return state
      }),
      Decrement: Effect.fnUntraced(function*({ payload: { amount } }) {
        state -= amount
        return state
      }),
      GetValue: Effect.fnUntraced(function*() {
        return state
      })
    }
  }),
  {
    maxIdleTime: "5 minutes",     // Auto-shutdown (passivation) after inactivity
    concurrency: 1,               // Sequential processing (default for actor semantics)
    mailboxCapacity: 1000         // Max queued messages (provides backpressure)
  }
)
```

### Entity Options

When creating an entity layer, you can configure:

| Option | Description |
|--------|-------------|
| `maxIdleTime` | Duration after which idle entities are passivated (shut down to save resources) |
| `concurrency` | Number of concurrent message handlers. Use `1` for strict actor semantics, `"unbounded"` for parallel processing |
| `mailboxCapacity` | Maximum pending messages. Provides backpressure protection against traffic spikes |
| `disableFatalDefects` | Prevent defects from terminating the entity |
| `defectRetryPolicy` | Schedule for retrying after defects |

## Virtual Actors (Lazy Activation)

Actors in Effect Cluster are **virtual**—they don't consume resources until they receive a message:

- **Activation**: When a message arrives for `User:456`, if the actor doesn't exist, it's created automatically
- **Passivation**: After `maxIdleTime` of inactivity, actors are removed from memory to save resources
- **Rehydration**: When a passivated actor receives a new message, it's recreated (potentially on a different node)

This means you can have millions of logical actors while only keeping active ones in memory.

## Sharding & Entity Management

Entities are automatically distributed across runners using consistent hashing. Each entity ID maps to a shard, and shards are assigned to runners.

### How Sharding Works

1. **Entity ID → Shard**: The entity ID is hashed to determine its shard
2. **Shard → Runner**: Each shard is assigned to exactly one runner (singleton guarantee)
3. **Automatic Rebalancing**: When runners join/leave, shards are redistributed
4. **Rehydration**: Actors on failed nodes are recreated on healthy nodes

This ensures that for any given ID (e.g., `User:123`), only **one** instance of that actor exists in the entire cluster.

```typescript
import { ShardingConfig } from "@effect/cluster"

// Configure sharding behavior
const config = ShardingConfig.layer({
  shardsPerGroup: 300,           // Number of shards per group
  shardGroups: ["default"],      // Logical groupings of shards
  entityMaxIdleTime: "1 minute", // Default idle timeout
  runnerShardWeight: 1           // Relative shard assignment weight
})
```

### Sharding Configuration

Key configuration options:

```typescript
const ShardingConfigDefaults = {
  shardsPerGroup: 300,
  shardGroups: ["default"],
  entityMailboxCapacity: 4096,
  entityMaxIdleTime: "1 minute",
  entityTerminationTimeout: "15 seconds",
  shardLockRefreshInterval: "10 seconds",
  shardLockExpiration: "35 seconds",
  refreshAssignmentsInterval: "3 seconds",
  runnerHealthCheckInterval: "1 minute"
}
```

### Location Transparency & Clients

You don't need to know *where* an actor is running. You just need its **identity** (Entity Type + Entity ID). The client automatically routes messages to the correct runner:

```typescript
Effect.gen(function*() {
  // Get a client factory for the Counter entity
  const makeClient = yield* Counter.client

  // Create a client for a specific entity instance
  // The system handles routing to wherever this entity lives
  const counter = makeClient("user-123")

  // Call entity methods - routed transparently
  const value1 = yield* counter.Increment({ amount: 5 })
  const value2 = yield* counter.Increment({ amount: 3 })
  const current = yield* counter.GetValue({})

  console.log(`Counter value: ${current}`) // 8
})
```

## Singletons

Singletons are processes that run on exactly one node in the cluster. Use them for coordination tasks:

```typescript
import { Singleton } from "@effect/cluster"

// Create a singleton that coordinates between entities
const CoordinatorSingleton = Singleton.make(
  "Coordinator",
  Effect.gen(function*() {
    yield* Effect.log("Coordinator starting")

    // This will only run on one node
    while (true) {
      yield* Effect.log("Performing coordination...")
      yield* Effect.sleep("30 seconds")
    }
  })
)

// Singletons are automatically migrated if the host node fails
```

### Singleton with Entity Communication

Singletons can interact with entities:

```typescript
const AggregatorSingleton = Singleton.make(
  "Aggregator",
  Effect.gen(function*() {
    const makeClient = yield* Counter.client

    // Aggregate values from multiple counters
    while (true) {
      let total = 0
      for (const userId of ["user-1", "user-2", "user-3"]) {
        const counter = makeClient(userId)
        total += yield* counter.GetValue({})
      }
      yield* Effect.log(`Total across all counters: ${total}`)
      yield* Effect.sleep("1 minute")
    }
  })
)
```

## Message Persistence & Recovery

To survive crashes, actors need persistence. Effect Cluster supports durable messaging with SQL-backed storage.

### Persisted Messages

Messages marked as persisted are saved to durable storage before delivery:

```typescript
import { ClusterSchema } from "@effect/cluster"

// Mark an RPC as persisted (durable)
const DurableCounter = Entity.make("DurableCounter", [
  Rpc.make("Increment", {
    payload: { amount: Schema.Number },
    success: Schema.Number
  }).annotate(ClusterSchema.Persisted, true)
])
```

Persisted messages:
- Are written to storage before delivery
- Survive runner failures
- Are retried until acknowledged (forward recovery)
- Maintain ordering guarantees

### Event Sourcing Pattern

For full state recovery, consider event sourcing:

- Instead of saving current state ("Balance: 100"), save events ("Deposited 50", "Withdrew 10")
- On actor rehydration, replay events to rebuild state
- Provides full audit trail and point-in-time recovery

## Distributed Transactions: Sagas

When operations span multiple actors (e.g., transfer money from Alice to Bob), you can't use a single database transaction. Use the **Saga pattern** instead:

1. Deduct from Alice (Success)
2. Add to Bob (Failed?)
3. If Bob fails, trigger a **compensation** action to refund Alice

Each step is a local transaction, with compensating actions for rollback.

## Running a Cluster

### Single Node (Development)

For development or single-node deployments, use `SingleRunner`:

```typescript
import { SingleRunner } from "@effect/cluster"
import { SqliteClient } from "@effect/sql-sqlite-node"

const SqlLive = SqliteClient.layer({
  filename: "cluster.db"
})

// Single-node cluster with SQL persistence
const ClusterLive = SingleRunner.layer().pipe(
  Layer.provide(SqlLive)
)

// Combine with entity layers
const AppLive = Layer.mergeAll(
  CounterLive,
  CoordinatorSingleton
).pipe(
  Layer.provide(ClusterLive)
)

// Launch the application
Layer.launch(AppLive).pipe(Effect.runFork)
```

### Multi-Node (Production)

For distributed deployments, use `SocketRunner` or `NodeClusterSocket`:

```typescript
import { NodeClusterSocket, NodeRuntime } from "@effect/platform-node"
import { PgClient } from "@effect/sql-pg"

// PostgreSQL for distributed storage
const SqlLive = PgClient.layer({
  host: "localhost",
  database: "cluster"
})

// Cluster configuration for this node
const ClusterLive = NodeClusterSocket.layer({
  storage: "sql",           // Use SQL for distributed storage
  shardingConfig: {
    runnerAddress: Option.some(
      RunnerAddress.make("node1.cluster.local", 34431)
    )
  }
}).pipe(
  Layer.provide(SqlLive)
)

// Start the runner
Layer.mergeAll(
  CounterLive,
  AggregatorSingleton
).pipe(
  Layer.provide(ClusterLive),
  Layer.launch,
  NodeRuntime.runMain
)
```

### Cluster Layer Options

The `NodeClusterSocket.layer` accepts:

```typescript
NodeClusterSocket.layer({
  // Serialization format for RPC
  serialization: "msgpack" | "ndjson",

  // Run as client-only (no entity hosting)
  clientOnly: true | false,

  // Storage backend
  storage: "local" | "sql" | "byo",

  // Health checking strategy
  runnerHealth: "ping" | "k8s",

  // Sharding configuration overrides
  shardingConfig: { ... }
})
```

## Testing Entities

Test entities in isolation using `Entity.makeTestClient`:

```typescript
import { it, describe } from "@effect/vitest"
import { Entity } from "@effect/cluster"

describe("Counter Entity", () => {
  it.scoped("should increment correctly", () =>
    Effect.gen(function*() {
      // Create a test client factory
      const makeClient = yield* Entity.makeTestClient(
        Counter,
        CounterLive
      )

      const counter = makeClient("test-1")

      const result = yield* counter.Increment({ amount: 5 })
      expect(result).toBe(5)

      const final = yield* counter.GetValue({})
      expect(final).toBe(5)
    }).pipe(
      Effect.provide(ShardingConfig.layer())
    )
  )
})
```

## Complete Example

A full cluster application with entities, singletons, and persistence:

```typescript
import { Entity, RunnerAddress, Singleton } from "@effect/cluster"
import { NodeClusterSocket, NodeRuntime } from "@effect/platform-node"
import { Rpc } from "@effect/rpc"
import { Effect, Layer, Logger, LogLevel, Option, Schema } from "effect"

// --- Entity Definition ---
const Counter = Entity.make("Counter", [
  Rpc.make("Increment", {
    payload: { amount: Schema.Number },
    success: Schema.Number
  }),
  Rpc.make("Decrement", {
    payload: { amount: Schema.Number },
    success: Schema.Number
  })
])

// --- Entity Implementation ---
const CounterLive = Counter.toLayer(
  Effect.gen(function*() {
    console.log("Creating Counter", yield* Entity.CurrentAddress)

    // In-memory state - fast reads, instant writes
    let state = 0

    yield* Effect.addFinalizer(() => Effect.log("Finalizing", state))

    // Handlers process messages sequentially (concurrency: 1 is default)
    return {
      Increment: Effect.fnUntraced(function*({ payload: { amount } }) {
        state += amount
        return state
      }),
      Decrement: Effect.fnUntraced(function*({ payload: { amount } }) {
        state -= amount
        return state
      })
    }
  }),
  { maxIdleTime: "10 seconds", concurrency: "unbounded" }
)

// --- Singleton Definition ---
const SendMessage = Singleton.make(
  "SendMessage",
  Effect.gen(function*() {
    const makeClient = yield* Counter.client
    const client = makeClient("test")

    yield* Effect.log("Client", yield* client.Increment({ amount: 1 }))
    yield* Effect.log("Client 2", yield* client.Increment({ amount: 1 }))
    yield* Effect.log("Client 3", yield* client.Decrement({ amount: 1 }))
  })
)

// --- Cluster Setup ---
const ShardingLive = NodeClusterSocket.layer({
  storage: "local",
  shardingConfig: {
    runnerAddress: Option.some(RunnerAddress.make("localhost", 50000))
  }
})

// --- Application ---
Layer.mergeAll(
  CounterLive,
  SendMessage
).pipe(
  Layer.provide(ShardingLive),
  Layer.provide(Logger.minimumLogLevel(LogLevel.All)),
  Layer.launch,
  NodeRuntime.runMain
)
```

## Key Concepts Summary

| Concept | Description |
|---------|-------------|
| **Entity** | Stateful actor that processes messages sequentially, eliminating race conditions |
| **Virtual Actor** | Actors are created on-demand and passivated when idle to save resources |
| **Sharding** | Automatic distribution of entities across runners via consistent hashing |
| **Runner** | Physical node that hosts entities |
| **Singleton** | Cluster-wide unique process that runs on exactly one node |
| **Shard** | Logical partition of entities; each shard assigned to exactly one runner |
| **Location Transparency** | Clients route messages without knowing which node hosts the entity |
| **Mailbox** | Message queue providing sequential processing and backpressure |
| **Saga** | Pattern for distributed transactions across multiple actors |

The cluster module enables building robust distributed systems with:
- Sequential processing model even at scale (no race conditions)
- Automatic load balancing and failover
- Location-transparent entity access
- Virtual actors with lazy activation/passivation
- Durable messaging with persistence
- Kubernetes-native health checking
- SQL-backed distributed coordination
