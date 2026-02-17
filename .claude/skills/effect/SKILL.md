---
name: effect
description: Use when writing Effect-TS code, building services with Layers, handling typed errors, working with Streams, Schema validation, or questions about Effect APIs. Triggers on Effect imports, pipe/gen syntax, Layer/Context usage.
---

# Effect

## Fundamentals
- [effect-basics.md](references/effect-basics.md) - Effect type, creating/running effects
- [composition.md](references/composition.md) - Combining effects, gen/pipe patterns
- [error-handling.md](references/error-handling.md) - Typed errors, catchTag, catchAll, orElse

## Dependency Injection
- [context-and-services.md](references/context-and-services.md) - Context.Tag, basic services
- [layers.md](references/layers.md) - Layer construction, composition, ManagedRuntime
- [configuration.md](references/configuration.md) - Config module, environment variables

## Data & Validation
- [data-types.md](references/data-types.md) - Option, Either, Chunk, HashMap
- [schema.md](references/schema.md) - Schema validation, parsing, encoding
- [pattern-matching.md](references/pattern-matching.md) - Match module, exhaustive matching

## Concurrency
- [concurrency.md](references/concurrency.md) - Fibers, parallel/race, interruption
- [streams.md](references/streams.md) - Stream processing, async iterables
- [synchronization.md](references/synchronization.md) - Semaphore, Mutex, locks
- [fiber-ref.md](references/fiber-ref.md) - Fiber-local state

## Resources & Performance
- [resource-management.md](references/resource-management.md) - Scope, acquireRelease, finalizers
- [pool.md](references/pool.md) - Resource pooling
- [batching.md](references/batching.md) - Request batching, N+1 prevention
- [caching.md](references/caching.md) - Memoization, cache strategies

## Infrastructure
- [runtime.md](references/runtime.md) - Custom runtimes, configuration
- [testing.md](references/testing.md) - Test utilities, TestClock, it.effect
- [observability.md](references/observability.md) - Logging, tracing, metrics
- [scheduling.md](references/scheduling.md) - Schedule combinators, retries
- [state-management.md](references/state-management.md) - Ref, SynchronizedRef

## Platform & Integrations
- [platform.md](references/platform.md) - HTTP, FileSystem, Terminal
- [sql.md](references/sql.md) - Database queries, transactions
- [rpc.md](references/rpc.md) - Type-safe RPC
- [queues-and-pubsub.md](references/queues-and-pubsub.md) - Queue, PubSub
- [cluster.md](references/cluster.md) - Distributed systems
