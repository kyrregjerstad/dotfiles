---
name: testing
description: Write tests for the bitfocus-buttons codebase. Use when asked to write tests, add test coverage, or create test files. Follows Testing Trophy philosophy prioritizing integration tests.
---

# Testing Skill

Write tests following our Testing Trophy philosophy: prioritize integration tests over unit tests.

Use built-in tools for exploration: `Grep` (ripgrep), `Glob` (fd-style file finding), `Read`. Avoid bash grep/find.

## Philosophy

- **Confidence over coverage** - ROI where return=confidence, investment=time
- **Resemble real usage** - test how software is actually used
- **Test behavior, not implementation** - refactors shouldn't break tests
- **Mock sparingly** - only at boundaries, never system under test

## Test Types

| Type | Pattern | Location | When |
|------|---------|----------|------|
| Integration | `*.integration.test.ts` | `tests/integration/` | **Default choice** - real DB, Redis, servers |
| Unit | `*.test.ts` | Colocated with source | Complex isolated logic, edge cases |
| Frontend | `*.test.tsx` | `src/www-ui/` | React components with jsdom |

**Start with integration test. Drop to unit only if too slow/complicated.**

## Commands

**Prefer running specific files** - fastest feedback loop:

```bash
npm run test:run -- --silent path/to/file.test.ts     # PREFERRED - fastest
```

Only run broader scopes when needed:

```bash
npm run test:run -- --silent --project integration    # Integration only
npm run test:run -- --silent --project backend        # Backend only
npm run test:run -- --silent --project workflow       # Workflow only
npm run test:run -- --silent --project www-ui         # Frontend only
npm run test:run -- --silent                          # All tests
```

Always use `-- --silent` to minimize output.

## Integration Tests

Use `createWwwTestSuite()` for full isolated environment (PostgreSQL, Redis, Fastify, Prisma):

```typescript
import { describe, expect, it, beforeAll, afterAll } from 'vitest'
import { createWwwTestSuite } from '../helpers'

describe('Feature Name', () => {
  const suite = createWwwTestSuite()

  beforeAll(suite.startServer)
  afterAll(suite.stopServer)

  it('describes expected behavior', async () => {
    // Use tRPC client
    const result = await suite.client.router.method.query()

    // Verify via direct DB access
    const dbRecord = await suite.db.model.findUnique({ where: { id: result.id } })

    expect(result.field).toBe('expected')
    expect(dbRecord).not.toBeNull()
  })
})
```

Suite provides:
- `suite.client` - authenticated tRPC client
- `suite.db` - direct Prisma access
- `suite.serverUrl` - for raw HTTP requests

## Unit Tests (Backend)

Colocate with source file. Mock external dependencies only:

```typescript
import { describe, expect, it } from 'vitest'
import { myFunction } from './myModule'

describe('myFunction', () => {
  it('handles normal case', () => {
    const result = myFunction(input)
    expect(result).toBe(expected)
  })

  it('handles edge case', () => {
    expect(() => myFunction(badInput)).toThrow()
  })
})
```

## Workflow Node Tests

Use `setupNode` helper with `expectSuccess`/`expectError`:

```typescript
import { beforeEach, describe, it } from 'vitest'
import { expectSuccess, setupNode } from '../testHelpers'
import { MyNode } from './MyNode'

describe('MyNode', () => {
  let node: MyNode

  beforeEach(() => {
    const setup = setupNode(MyNode)
    node = setup.node
  })

  it.each([
    { input: 'a', expected: 'b' },
    { input: 'c', expected: 'd' },
  ])('transforms $input to $expected', async ({ input, expected }) => {
    const result = await node.render({ value: input })
    expectSuccess(result, { output: expected })
  })
})
```

Helpers:
- `setupNode(NodeClass)` - creates node with mocked workflow
- `expectSuccess(result, expected)` - asserts ok result matches
- `expectError(result, errorType)` - asserts error type
- `expectOk(result, expected)` - asserts ok without checking error
- `expectNoError(result)` - asserts no error field

## Frontend Tests (www-ui)

Uses jsdom, Testing Library, MSW for API mocking:

```typescript
import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MyComponent } from './MyComponent'

describe('MyComponent', () => {
  it('renders correctly', () => {
    render(<MyComponent prop="value" />)
    expect(screen.getByText('expected text')).toBeInTheDocument()
  })
})
```

## Effect Tests

For Effect-TS services, use `@effect/vitest` integration:

```typescript
import { it } from '@effect/vitest'
import { makeDatabaseTest } from '@lib-apps/effect/db'
import { Effect, Exit, Layer } from 'effect'
import { beforeEach, describe, expect } from 'vitest'
import { mockDeep, mockReset } from 'vitest-mock-extended'

const prismaMock = mockDeep<ButtonsPrismaClient>()
const serviceMock = mockDeep<typeof MyService.Service>()

beforeEach(() => {
  mockReset(prismaMock)
  mockReset(serviceMock)
})

// Build test layer with mocked dependencies
const TestLayer = MyService.DefaultWithoutDependencies.pipe(
  Layer.provide(
    Layer.mergeAll(
      makeDatabaseTest(prismaMock),
      Layer.succeed(DependencyService, serviceMock as typeof DependencyService.Service),
    ),
  ),
)

const runTest = <E, A>(effect: Effect.Effect<A, E, MyService>) =>
  effect.pipe(Effect.provide(TestLayer))

describe('MyService', () => {
  it.effect('succeeds when condition met', () =>
    Effect.gen(function* () {
      const service = yield* MyService

      serviceMock.method.mockImplementation(() => Effect.succeed(value))

      const result = yield* service.doSomething({ input: 'test' })

      expect(result.field).toBe('expected')
    }).pipe(runTest),
  )

  it.effect('fails with specific error', () =>
    Effect.gen(function* () {
      const service = yield* MyService

      serviceMock.method.mockImplementation(() =>
        Effect.fail(new MyError({ reason: 'test' }))
      )

      const result = yield* Effect.exit(service.doSomething({ input: 'bad' }))

      expect(Exit.isFailure(result)).toBe(true)
    }).pipe(runTest),
  )
})
```

Key patterns:
- `it.effect()` - Effect-aware test runner from `@effect/vitest`
- `Effect.gen(function* () { ... })` - generator syntax for effects
- `yield*` - await Effect values
- `Effect.exit()` - capture result without throwing
- `Exit.isSuccess/isFailure` - check outcomes
- `makeDatabaseTest(prismaMock)` - database layer for tests
- `Layer.succeed(Service, mock)` - provide mocked service
- Mock implementations return Effects: `mockImplementation(() => Effect.succeed(value))`

**Providing dependencies:** Check the service definition first:
- Some services export `.Test` or `.Mock` layers - use those directly
- Others need `DefaultWithoutDependencies` + manual layer composition

## Mocking Patterns

**Prisma (unit tests):**
```typescript
import { mockDeep } from 'vitest-mock-extended'
import type { PrismaClient } from '@prisma/client'
const prismaMock = mockDeep<PrismaClient>()
```

**Redis (unit tests):**
```typescript
vi.mock('@lib-apps/redisclient/operations/variables', () => ({
  getCompanionVariableValues: vi.fn().mockResolvedValue({}),
}))
```

**MSW (frontend):**
```typescript
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'

const server = setupServer(
  http.get('/api/data', () => HttpResponse.json({ data: 'test' }))
)
```

## Best Practices

**Do:**
- Descriptive test names: behavior + expected outcome
- Test success AND error cases
- Use `it.each()` for parameterized tests
- Keep tests simple and readable
- Each test runs independently

**Don't:**
- Test framework behavior (React, Prisma work)
- Write brittle implementation-detail tests
- Share state between tests
- Over-mock - prefer real dependencies

## Deciding What to Test

1. Will this give confidence to ship?
2. Does it resemble real usage?
3. What's the ROI (time vs confidence)?
4. Can it be tested at higher level?
5. Am I testing my code or the framework?
