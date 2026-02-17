# SQL

Effect provides a comprehensive SQL toolkit through the `@effect/sql` package. It offers type-safe database access with tagged template literals, automatic query batching, migrations, and ORM integrations.

## @effect/sql Client

The core of Effect SQL is the `SqlClient` service. Each database has its own client implementation:

- `@effect/sql-pg` - PostgreSQL
- `@effect/sql-mysql2` - MySQL
- `@effect/sql-sqlite-node` - SQLite (Node.js)
- `@effect/sql-sqlite-bun` - SQLite (Bun)
- `@effect/sql-libsql` - LibSQL/Turso
- `@effect/sql-mssql` - Microsoft SQL Server
- `@effect/sql-d1` - Cloudflare D1

### Setting Up a Client

```typescript
import { Effect, pipe } from "effect"
import { PgClient } from "@effect/sql-pg"
import { SqlClient } from "@effect/sql"

// Create a layer for the database client
const SqlLive = PgClient.layer({
  database: "myapp_dev"
})

const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient

  const users = yield* sql<{
    readonly id: number
    readonly name: string
  }>`SELECT id, name FROM users`

  yield* Effect.log(`Got ${users.length} users`)
})

pipe(program, Effect.provide(SqlLive), Effect.runPromise)
```

For SQLite:

```typescript
import { SqliteClient } from "@effect/sql-sqlite-node"

const SqlLive = SqliteClient.layer({
  filename: "data/app.sqlite"
})
```

### Using Config for Connection Details

```typescript
import { Config } from "effect"
import { PgClient } from "@effect/sql-pg"

const SqlLive = PgClient.layerConfig({
  database: Config.string("DATABASE_NAME"),
  host: Config.string("DATABASE_HOST"),
  port: Config.number("DATABASE_PORT"),
  username: Config.string("DATABASE_USER"),
  password: Config.redacted("DATABASE_PASSWORD")
})
```

## Query Building

### Safe Interpolation

Values interpolated in tagged template queries are automatically parameterized:

```typescript
const getUser = (id: number) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient
    // id is safely parameterized: SELECT * FROM users WHERE id = $1
    const users = yield* sql`SELECT * FROM users WHERE id = ${id}`
    return users[0]
  })
```

### Identifiers

Use `sql()` to safely quote identifiers:

```typescript
const getFromTable = (table: string, limit: number) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient
    // table is quoted: SELECT * FROM "users" LIMIT $1
    return yield* sql`SELECT * FROM ${sql(table)} LIMIT ${limit}`
  })
```

### Unsafe Interpolation

For cases where you need raw SQL (like ORDER BY direction):

```typescript
type SortOrder = "ASC" | "DESC"

const getSorted = (column: string, order: SortOrder) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient
    // ORDER BY "created_at" ASC
    return yield* sql`SELECT * FROM users ORDER BY ${sql(column)} ${sql.unsafe(order)}`
  })
```

### IN Clauses

Use `sql.in()` for lists:

```typescript
const getUsersByIds = (ids: number[]) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient
    return yield* sql`SELECT * FROM users WHERE ${sql.in("id", ids)}`
  })
```

### AND/OR Combinators

Build complex WHERE clauses:

```typescript
const search = (names: string[], minAge: number) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient

    // AND combinator
    const results = yield* sql`SELECT * FROM users WHERE ${sql.and([
      sql.in("name", names),
      sql`age >= ${minAge}`
    ])}`
    // WHERE ("name" IN ($1,$2,$3) AND age >= $4)

    // OR combinator
    const altResults = yield* sql`SELECT * FROM users WHERE ${sql.or([
      sql.in("name", names),
      sql`age >= ${minAge}`
    ])}`

    return results
  })
```

### Insert & Update Helpers

```typescript
const createUser = (name: string, email: string) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient

    // Insert helper generates column list and values
    yield* sql`INSERT INTO users ${sql.insert({ name, email })}`
    // INSERT INTO users ("name", "email") VALUES ($1, $2)

    // Insert with RETURNING
    const [user] = yield* sql`
      INSERT INTO users ${sql.insert({ name, email }).returning("*")}
    `
    return user
  })

const updateUser = (id: number, updates: { name?: string; email?: string }) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient

    // Update helper, excluding id from SET clause
    yield* sql`UPDATE users SET ${sql.update(updates, ["id"])} WHERE id = ${id}`

    return yield* sql`SELECT * FROM users WHERE id = ${id}`
  })
```

### Column Name Transformation

Transform between camelCase (TypeScript) and snake_case (SQL):

```typescript
import { String } from "effect"
import { PgClient } from "@effect/sql-pg"

const SqlLive = PgClient.layer({
  database: "myapp",
  transformQueryNames: String.camelToSnake,  // JS -> SQL
  transformResultNames: String.snakeToCamel   // SQL -> JS
})

// Now you can use camelCase in code
const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient

  // Query uses snake_case, results come back as camelCase
  const users = yield* sql<{ id: number; createdAt: Date }>`
    SELECT id, created_at FROM users
  `
  // users[0].createdAt works
})
```

## Transactions

Wrap operations in a transaction with `sql.withTransaction`:

```typescript
const transferFunds = (from: number, to: number, amount: number) =>
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient

    yield* sql.withTransaction(
      Effect.gen(function*() {
        yield* sql`UPDATE accounts SET balance = balance - ${amount} WHERE id = ${from}`
        yield* sql`UPDATE accounts SET balance = balance + ${amount} WHERE id = ${to}`
      })
    )
  })
```

If any effect in the transaction fails, all changes are rolled back:

```typescript
const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient

  const result = yield* sql.withTransaction(
    Effect.gen(function*() {
      yield* sql`INSERT INTO users (name) VALUES ('Alice')`
      // This failure rolls back the insert
      yield* Effect.fail(new Error("abort"))
    })
  ).pipe(Effect.exit)

  // The insert was rolled back
})
```

## Migrations

Migrations are forward-only and written as Effect modules.

### Creating Migrations

```typescript
// src/migrations/0001_create_users.ts
import { Effect } from "effect"
import { SqlClient } from "@effect/sql"

export default Effect.flatMap(
  SqlClient.SqlClient,
  (sql) => sql`
    CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `
)
```

```typescript
// src/migrations/0002_add_posts.ts
import { Effect } from "effect"
import { SqlClient } from "@effect/sql"

export default Effect.flatMap(
  SqlClient.SqlClient,
  (sql) => sql`
    CREATE TABLE posts (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id),
      title VARCHAR(255) NOT NULL,
      body TEXT,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `
)
```

### Running Migrations

```typescript
import { Effect, Layer, pipe } from "effect"
import { NodeContext, NodeRuntime } from "@effect/platform-node"
import { PgClient, PgMigrator } from "@effect/sql-pg"
import { fileURLToPath } from "node:url"

const SqlLive = PgClient.layer({
  database: "myapp"
})

const MigratorLive = PgMigrator.layer({
  loader: PgMigrator.fromFileSystem(
    fileURLToPath(new URL("migrations", import.meta.url))
  ),
  // Optional: output schema file for reference
  schemaDirectory: "src/migrations"
}).pipe(Layer.provide(SqlLive))

const EnvLive = Layer.mergeAll(SqlLive, MigratorLive).pipe(
  Layer.provide(NodeContext.layer)
)

const program = Effect.gen(function*() {
  // Migrations run automatically when layer is provided
  yield* Effect.log("Migrations complete!")
})

pipe(program, Effect.provide(EnvLive), NodeRuntime.runMain)
```

For SQLite:

```typescript
import { SqliteClient, SqliteMigrator } from "@effect/sql-sqlite-node"
import { NodeContext } from "@effect/platform-node"

const ClientLive = SqliteClient.layer({
  filename: "data/app.sqlite"
})

const MigratorLive = SqliteMigrator.layer({
  loader: SqliteMigrator.fromFileSystem(
    fileURLToPath(new URL("./migrations", import.meta.url))
  )
}).pipe(Layer.provide(NodeContext.layer))

const SqlLive = MigratorLive.pipe(Layer.provideMerge(ClientLive))
```

## SqlSchema for Type-Safe Queries

`SqlSchema` provides schema-validated query helpers:

```typescript
import { SqlClient, SqlSchema } from "@effect/sql"
import { Schema } from "effect"

class User extends Schema.Class<User>("User")({
  id: Schema.Number,
  name: Schema.String,
  email: Schema.String
}) {}

const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient

  // findAll - returns array of decoded results
  const findAllUsers = SqlSchema.findAll({
    Request: Schema.Void,
    Result: User,
    execute: () => sql`SELECT * FROM users`
  })
  const users = yield* findAllUsers()

  // findOne - returns Option
  const findUserById = SqlSchema.findOne({
    Request: Schema.Number,
    Result: User,
    execute: (id) => sql`SELECT * FROM users WHERE id = ${id}`
  })
  const maybeUser = yield* findUserById(1)

  // single - returns one result or fails
  const getUserById = SqlSchema.single({
    Request: Schema.Number,
    Result: User,
    execute: (id) => sql`SELECT * FROM users WHERE id = ${id}`
  })
  const user = yield* getUserById(1)  // Fails if not found

  // void - for mutations
  const deleteUser = SqlSchema.void({
    Request: Schema.Number,
    execute: (id) => sql`DELETE FROM users WHERE id = ${id}`
  })
  yield* deleteUser(1)
})
```

## SqlResolver for Batching

`SqlResolver` enables automatic request batching (see Batching chapter for details):

```typescript
import { SqlClient, SqlResolver } from "@effect/sql"
import { Effect, Schema } from "effect"

class Person extends Schema.Class<Person>("Person")({
  id: Schema.Number,
  name: Schema.String
}) {}

const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient

  // ordered - results in same order as requests
  const InsertPerson = yield* SqlResolver.ordered("InsertPerson", {
    Request: Schema.Struct({ name: Schema.String }),
    Result: Person,
    execute: (requests) =>
      sql`INSERT INTO people ${sql.insert(requests)} RETURNING *`
  })

  // findById - match results by ID
  const GetPersonById = yield* SqlResolver.findById("GetPersonById", {
    Id: Schema.Number,
    Result: Person,
    ResultId: (p) => p.id,
    execute: (ids) => sql`SELECT * FROM people WHERE id IN ${sql.in(ids)}`
  })

  // grouped - multiple results per request
  const GetPersonsByName = yield* SqlResolver.grouped("GetPersonsByName", {
    Request: Schema.String,
    RequestGroupKey: (name) => name,
    Result: Person,
    ResultGroupKey: (p) => p.name,
    execute: (names) => sql`SELECT * FROM people WHERE name IN ${sql.in(names)}`
  })

  // Use with batching
  const [alice, bob] = yield* Effect.all(
    [InsertPerson.execute({ name: "Alice" }), InsertPerson.execute({ name: "Bob" })],
    { batching: true }
  )
})
```

## Model API

The `Model` module provides schema variants for different operations:

```typescript
import { Model } from "@effect/sql"
import { Schema } from "effect"

const UserId = Schema.Number.pipe(Schema.brand("UserId"))

class User extends Model.Class<User>("User")({
  // Generated - excluded from insert, available in select/update
  id: Model.Generated(UserId),

  // Regular field - included everywhere
  name: Schema.NonEmptyTrimmedString,
  email: Schema.String,

  // DateTimeInsert - auto-generated on insert
  createdAt: Model.DateTimeInsertFromDate,

  // DateTimeUpdate - auto-updated
  updatedAt: Model.DateTimeUpdateFromDate,

  // Sensitive - excluded from JSON output
  passwordHash: Model.Sensitive(Schema.String)
}) {}

// Different schema variants for different contexts
User              // SELECT schema (all fields)
User.insert       // INSERT schema (excludes id, createdAt, updatedAt)
User.update       // UPDATE schema (all fields)
User.json         // JSON API (excludes passwordHash)
User.jsonCreate   // JSON API create (insert fields, no sensitive)
User.jsonUpdate   // JSON API update
```

### Model Repository

Generate CRUD operations automatically:

```typescript
import { Model, SqlClient } from "@effect/sql"
import { Effect, Schema } from "effect"

const UserId = Schema.Number.pipe(Schema.brand("UserId"))

class User extends Model.Class<User>("User")({
  id: Model.Generated(UserId),
  name: Schema.NonEmptyTrimmedString,
  email: Schema.String,
  createdAt: Model.DateTimeInsertFromDate,
  updatedAt: Model.DateTimeUpdateFromDate
}) {}

const program = Effect.gen(function*() {
  const repo = yield* Model.makeRepository(User, {
    tableName: "users",
    spanPrefix: "UserRepo",
    idColumn: "id"
  })

  // Insert
  const user = yield* repo.insert({ name: "Alice", email: "alice@example.com" })

  // Find by ID (returns Option)
  const found = yield* repo.findById(user.id)

  // Update
  const updated = yield* repo.update({ ...user, name: "Alice Smith" })

  // Delete
  yield* repo.delete(user.id)
})
```

## ORM Integrations

Effect SQL integrates with Drizzle and Kysely.

### Drizzle Integration

```typescript
import { SqlClient } from "@effect/sql"
import * as SqliteDrizzle from "@effect/sql-drizzle/Sqlite"
import { SqliteClient } from "@effect/sql-sqlite-node"
import * as D from "drizzle-orm/sqlite-core"
import { Effect, Layer } from "effect"

const SqlLive = SqliteClient.layer({ filename: "app.db" })
const DrizzleLive = SqliteDrizzle.layer.pipe(Layer.provide(SqlLive))

// Define tables using Drizzle schema
const users = D.sqliteTable("users", {
  id: D.integer("id").primaryKey(),
  name: D.text("name"),
  email: D.text("email")
})

const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient
  const db = yield* SqliteDrizzle.SqliteDrizzle

  // Create table
  yield* sql`CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY, name TEXT, email TEXT
  )`

  // Use Drizzle query builder
  yield* db.insert(users).values({ name: "Alice", email: "alice@example.com" })

  const results = yield* db.select().from(users).where(D.eq(users.name, "Alice"))

  // Transactions work too
  yield* db.withTransaction(
    Effect.gen(function*() {
      yield* db.insert(users).values({ name: "Bob" })
      yield* db.update(users).set({ email: "updated@example.com" })
    })
  )
})
```

### Kysely Integration

```typescript
import * as SqliteKysely from "@effect/sql-kysely/Sqlite"
import * as Sqlite from "@effect/sql-sqlite-node"
import { Effect, Layer, Context } from "effect"
import type { Generated } from "kysely"

// Define database types
interface User {
  id: Generated<number>
  name: string
  email: string
}

interface Database {
  users: User
}

// Create a tagged service for the Kysely instance
class SqliteDB extends Context.Tag("SqliteDB")<
  SqliteDB,
  SqliteKysely.EffectKysely<Database>
>() {}

const SqliteLive = Sqlite.SqliteClient.layer({ filename: ":memory:" })
const KyselyLive = Layer.effect(SqliteDB, SqliteKysely.make<Database>())
  .pipe(Layer.provide(SqliteLive))

const program = Effect.gen(function*() {
  const db = yield* SqliteDB

  // Schema management
  yield* db.schema
    .createTable("users")
    .addColumn("id", "integer", c => c.primaryKey().autoIncrement())
    .addColumn("name", "text", c => c.notNull())
    .addColumn("email", "text")

  // Type-safe queries
  yield* db.insertInto("users").values({ name: "Alice", email: "alice@example.com" })

  const users = yield* db.selectFrom("users").selectAll()

  // Transactions with automatic rollback on failure
  const result = yield* db.withTransaction(
    Effect.gen(function*() {
      yield* db.insertInto("users").values({ name: "Bob" })
      yield* db.updateTable("users").set({ name: "Robert" })
      return yield* db.selectFrom("users").selectAll()
    })
  )
})
```

## Best Practices

### Layer Composition

Compose SQL and migrator layers:

```typescript
import { NodeContext } from "@effect/platform-node"
import { SqlClient } from "@effect/sql"
import { SqliteClient, SqliteMigrator } from "@effect/sql-sqlite-node"
import { Layer } from "effect"

const ClientLive = SqliteClient.layer({
  filename: "data/app.sqlite"
})

const MigratorLive = SqliteMigrator.layer({
  loader: SqliteMigrator.fromFileSystem("./migrations")
}).pipe(Layer.provide(NodeContext.layer))

// Migrations run when layer initializes
export const SqlLive = MigratorLive.pipe(Layer.provideMerge(ClientLive))
```

### Testing with Mock Client

```typescript
import { SqlClient } from "@effect/sql"
import { Layer, identity } from "effect"

// Create a mock for testing
export const SqlTest = Layer.succeed(
  SqlClient.SqlClient,
  {
    withTransaction: identity,
    // Add other methods as needed
  } as SqlClient.SqlClient
)
```

### Error Handling

SQL operations can fail with `SqlError`:

```typescript
import { SqlError } from "@effect/sql"
import { Effect } from "effect"

const program = Effect.gen(function*() {
  const sql = yield* SqlClient.SqlClient

  yield* sql`INSERT INTO users (email) VALUES (${"duplicate@test.com"})`.pipe(
    Effect.catchTag("SqlError", (error) => {
      // Handle constraint violations, connection errors, etc.
      return Effect.log(`SQL error: ${error.message}`)
    })
  )
})
```
