# Schema

Effect Schema is a powerful data validation and transformation library built into Effect. Unlike libraries that only validate, Schema supports both **decoding** (parsing external data) and **encoding** (serializing back to external formats)—making it ideal for APIs, forms, and data persistence.

## Defining Schemas

### Basic Types

Schema provides primitives that mirror TypeScript types:

```typescript
import { Schema } from "effect"

// Primitives
Schema.String    // string
Schema.Number    // number
Schema.Boolean   // boolean
Schema.BigInt    // bigint
Schema.Undefined // undefined
Schema.Null      // null

// Literals
Schema.Literal("active", "inactive")  // "active" | "inactive"
Schema.Literal(1, 2, 3)               // 1 | 2 | 3
```

### Schema.Struct

Define object shapes with typed properties:

```typescript
const Person = Schema.Struct({
  name: Schema.String,
  age: Schema.Number,
  email: Schema.String,
})

// Inferred type: { readonly name: string; readonly age: number; readonly email: string }
type Person = typeof Person.Type
```

### Schema.Class

Create classes with built-in validation. Classes get constructors that validate input and include an `_tag` for discriminated unions:

```typescript
class User extends Schema.Class<User>("User")({
  id: Schema.Number,
  name: Schema.String,
  email: Schema.String,
}) {}

// Construct with validation
const user = new User({ id: 1, name: "Alice", email: "alice@example.com" })

// The class works like a schema
Schema.decodeSync(User)({ id: 1, name: "Alice", email: "alice@example.com" })
```

Add methods and computed properties:

```typescript
class User extends Schema.Class<User>("User")({
  firstName: Schema.String,
  lastName: Schema.String,
}) {
  get fullName() {
    return `${this.firstName} ${this.lastName}`
  }
}
```

### Collections

```typescript
// Arrays
Schema.Array(Schema.Number)  // number[]

// Tuples
Schema.Tuple(Schema.String, Schema.Number)  // [string, number]

// Records (dictionaries)
Schema.Record({ key: Schema.String, value: Schema.Number })  // Record<string, number>

// Sets and Maps (decode from arrays)
Schema.Set(Schema.String)                                    // Set<string>
Schema.Map({ key: Schema.String, value: Schema.Number })     // Map<string, number>
```

### Unions and Optional

```typescript
// Union types
Schema.Union(Schema.String, Schema.Number)  // string | number

// Nullable
Schema.NullOr(Schema.String)  // string | null

// Optional properties in structs
const Config = Schema.Struct({
  host: Schema.String,
  port: Schema.optional(Schema.Number),  // port?: number | undefined
})

// Optional with default
const ConfigWithDefault = Schema.Struct({
  host: Schema.String,
  port: Schema.optionalWith(Schema.Number, { default: () => 3000 }),
})
```

## Decoding & Encoding

The core operations: **decode** converts external data to your domain types, **encode** converts back.

### Synchronous Operations

```typescript
const Person = Schema.Struct({
  name: Schema.String,
  age: Schema.Number,
})

// decodeSync - throws on failure
const person = Schema.decodeSync(Person)({ name: "Alice", age: 30 })
// { name: "Alice", age: 30 }

// encodeSync - convert back to encoded form
const encoded = Schema.encodeSync(Person)(person)
// { name: "Alice", age: 30 }
```

When the encoded and decoded types are the same (no transformations), decode and encode are identical.

### Effect-Based Operations

For safer error handling, use the Effect-returning variants:

```typescript
// Returns Effect<Person, ParseError, never>
const decoded = Schema.decode(Person)({ name: "Alice", age: 30 })

// Run it
const person = Effect.runSync(decoded)
```

### Handling Unknown Input

When parsing data from external sources (API responses, form data), use `decodeUnknown`:

```typescript
// decodeUnknownSync - validates unknown input
const parseUser = Schema.decodeUnknownSync(User)

try {
  const user = parseUser(JSON.parse(response))
} catch (error) {
  // ParseError with detailed path information
}
```

### ParseError

When validation fails, you get a `ParseError` with detailed information:

```typescript
const Person = Schema.Struct({
  name: Schema.String,
  age: Schema.Number,
})

Schema.decodeSync(Person)({ name: "Alice", age: "thirty" })
// ParseError: { readonly name: string; readonly age: number }
// └─ ["age"]
//    └─ Expected number, actual "thirty"
```

The error traces the exact path to the invalid value.

## Transformations

The power of Schema: define how data transforms between external and internal representations.

### Built-in Transformations

Schema includes common transformations:

```typescript
// String to number
Schema.NumberFromString  // "123" <-> 123

// String to Date
Schema.DateFromString    // "2024-01-01" <-> Date

// String to boolean
Schema.BooleanFromString // "true" <-> true

// Trim whitespace
Schema.Trim              // "  hello  " <-> "hello"

// Split string to array
Schema.split(",")        // "a,b,c" <-> ["a", "b", "c"]
```

Use them in structs:

```typescript
const Author = Schema.Struct({
  name: Schema.String,
  age: Schema.NumberFromString,  // Accepts "26", decodes to 26
})

// Decode: string -> number
const author = Schema.decodeSync(Author)({ name: "Alice", age: "26" })
// { name: "Alice", age: 26 }

// Encode: number -> string
const encoded = Schema.encodeSync(Author)(author)
// { name: "Alice", age: "26" }
```

### Accessing Types

Every schema has `.Type` (decoded) and `.Encoded` (encoded) type accessors:

```typescript
const Author = Schema.Struct({
  name: Schema.String,
  age: Schema.NumberFromString,
})

type AuthorType = typeof Author.Type
// { readonly name: string; readonly age: number }

type AuthorEncoded = typeof Author.Encoded
// { readonly name: string; readonly age: string }
```

### Schema.transform

Create custom transformations with `Schema.transform`:

```typescript
const HeightInCm = Schema.Number.pipe(
  Schema.transform(
    Schema.String,
    {
      decode: (n) => `${n}cm`,           // number -> string
      encode: (s) => Number(s.slice(0, -2))  // string -> number
    }
  )
)

Schema.decodeSync(HeightInCm)(175)   // "175cm"
Schema.encodeSync(HeightInCm)("175cm")  // 175
```

### Schema.transformOrFail

When transformations can fail, use `transformOrFail`:

```typescript
import { ParseResult } from "effect"

const IntFromString = Schema.String.pipe(
  Schema.transformOrFail(
    Schema.Number,
    {
      decode: (s, _, ast) => {
        const n = Number(s)
        return Number.isNaN(n)
          ? ParseResult.fail(new ParseResult.Type(ast, s, "Expected a numeric string"))
          : ParseResult.succeed(n)
      },
      encode: (n) => ParseResult.succeed(String(n))
    }
  )
)
```

## Refinements and Filters

Add validation constraints to schemas:

### Built-in Refinements

```typescript
// String constraints
Schema.String.pipe(
  Schema.minLength(1),
  Schema.maxLength(100),
  Schema.pattern(/^[a-z]+$/)
)

// Number constraints
Schema.Number.pipe(
  Schema.int(),
  Schema.positive(),
  Schema.between(1, 100)
)

// Common validated types
Schema.NonEmptyString    // string with length > 0
Schema.Positive          // number > 0
Schema.Int               // integer
```

### Custom Filters

```typescript
const Even = Schema.Number.pipe(
  Schema.filter((n) => n % 2 === 0, {
    message: () => "Expected an even number"
  })
)

Schema.decodeSync(Even)(4)  // 4
Schema.decodeSync(Even)(3)  // ParseError: Expected an even number
```

### Branded Types

Create nominal types that provide compile-time safety:

```typescript
const UserId = Schema.String.pipe(
  Schema.brand("UserId")
)

type UserId = typeof UserId.Type
// string & Brand<"UserId">

// Create branded values
const id = UserId.make("user-123")

// Type-safe: can't pass raw string where UserId expected
function getUser(id: UserId) { ... }
getUser("user-123")  // Type error!
getUser(id)          // OK
```

Combine brands with refinements:

```typescript
const Email = Schema.String.pipe(
  Schema.pattern(/^[^@]+@[^@]+\.[^@]+$/),
  Schema.brand("Email")
)

type Email = typeof Email.Type
// string & Brand<"Email">
```

## Composing Schemas

### Extending Structs

```typescript
const BaseEntity = Schema.Struct({
  id: Schema.Number,
  createdAt: Schema.DateFromString,
})

const User = Schema.Struct({
  ...BaseEntity.fields,
  name: Schema.String,
  email: Schema.String,
})
```

### Picking and Omitting

```typescript
const User = Schema.Struct({
  id: Schema.Number,
  name: Schema.String,
  email: Schema.String,
  password: Schema.String,
})

// Pick specific fields
const UserPublic = User.pipe(Schema.pick("id", "name", "email"))

// Omit fields
const UserInput = User.pipe(Schema.omit("id"))
```

### Making Properties Partial or Required

```typescript
const User = Schema.Struct({
  id: Schema.Number,
  name: Schema.String,
  email: Schema.String,
})

// All properties optional
const PartialUser = Schema.partial(User)

// Specific properties optional
const UpdateUser = Schema.Struct({
  ...Schema.partial(User.pipe(Schema.omit("id"))).fields,
  id: Schema.Number,
})
```

## Working with Classes

### Schema.TaggedClass

For discriminated unions, use `TaggedClass` which automatically adds a `_tag` property:

```typescript
class Circle extends Schema.TaggedClass<Circle>()("Circle", {
  radius: Schema.Number,
}) {}

class Rectangle extends Schema.TaggedClass<Rectangle>()("Rectangle", {
  width: Schema.Number,
  height: Schema.Number,
}) {}

const Shape = Schema.Union(Circle, Rectangle)

// Pattern match on _tag
const area = (shape: typeof Shape.Type) => {
  switch (shape._tag) {
    case "Circle":
      return Math.PI * shape.radius ** 2
    case "Rectangle":
      return shape.width * shape.height
  }
}
```

### Schema.TaggedError

Create Error classes with schema validation—useful with Effect's error handling:

```typescript
class ValidationError extends Schema.TaggedError<ValidationError>()("ValidationError", {
  field: Schema.String,
  message: Schema.String,
}) {}

// Use in Effect
const validate = (input: unknown) =>
  Effect.fail(new ValidationError({ field: "email", message: "Invalid email" }))
```

## JSON Schema Generation

Generate JSON Schema from your schemas:

```typescript
import { JSONSchema } from "effect"

const User = Schema.Struct({
  name: Schema.String,
  age: Schema.Number.pipe(Schema.int(), Schema.positive()),
})

const jsonSchema = JSONSchema.make(User)
// {
//   type: "object",
//   properties: {
//     name: { type: "string" },
//     age: { type: "integer", exclusiveMinimum: 0 }
//   },
//   required: ["name", "age"]
// }
```

## Summary

| Feature | Description |
|---------|-------------|
| `Schema.Struct` | Object shapes with typed properties |
| `Schema.Class` | Classes with validation and methods |
| `Schema.decode/encode` | Transform between external and internal types |
| `Schema.transform` | Custom bidirectional transformations |
| `Schema.filter` | Add validation constraints |
| `Schema.brand` | Nominal types for compile-time safety |
| `.Type` / `.Encoded` | Access decoded/encoded TypeScript types |

Key insight: Schema tracks both directions. The **Encoded** type is what your external world sees (JSON, forms). The **Type** is your internal domain model. Schema bridges the gap safely.
