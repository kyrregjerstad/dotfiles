# Vulnerability Pattern Reference

## Injection Patterns

### SQL Injection
```
# Direct concatenation
query(`SELECT * FROM users WHERE id = ${userId}`)
db.raw(`DELETE FROM ${table}`)
execute("SELECT * FROM " + tableName)

# Safe patterns (for comparison)
query(`SELECT * FROM users WHERE id = ?`, [userId])
db.where({ id: userId })
```

### Command Injection
```
# Dangerous
exec(`ls ${userInput}`)
spawn('sh', ['-c', userCommand])
child_process.execSync(cmd)

# Check for sanitization nearby
```

### NoSQL Injection
```
# MongoDB operator injection
db.find({ user: req.body.user })  # if body.user = { $ne: null }
Model.findOne(req.query)          # query params as-is
```

## XSS Patterns

### DOM XSS
```
element.innerHTML = userInput
document.write(data)
$(selector).html(untrusted)
location.href = userControlled
eval(userInput)
new Function(userInput)
```

### React/Vue
```
dangerouslySetInnerHTML={{ __html: data }}
v-html="userContent"
```

## Auth Weaknesses

### JWT Issues
```
jwt.verify(token, secret, { algorithms: ['none'] })  # allows none
jwt.decode(token)  # decode without verify
secret = 'secret'  # weak secret
```

### Session Issues
```
cookie: { secure: false }
httpOnly: false
sameSite: 'none'
```

### Password Storage
```
md5(password)
sha1(password)
password == storedPassword  # plaintext comparison
```

## IDOR Patterns
```
# Direct ID from request without ownership check
const item = await db.item.findUnique({ where: { id: req.params.id } })
return item  # no check if item.userId === currentUser.id

# Mass assignment
await db.user.update({ where: { id }, data: req.body })  # can update role
```

## Config Issues

### CORS
```
cors({ origin: '*' })
Access-Control-Allow-Origin: *
credentials: true  # with wildcard origin = bad
```

### Debug/Dev in Prod
```
debug: true
NODE_ENV: 'development'
FLASK_DEBUG=1
verbose: true
stack traces in error responses
```

### Exposed Secrets
```
API_KEY = "sk-..."
password: "hardcoded123"
secret: process.env.SECRET || "default-secret"  # fallback is dangerous
```

## File Extensions to Prioritize
- Auth: `**/auth/**`, `**/middleware/**`, `**/*auth*`, `**/*session*`
- API: `**/api/**`, `**/routes/**`, `**/controllers/**`
- Config: `**/*config*`, `**/*.env*`, `**/settings*`
- DB: `**/models/**`, `**/schema*`, `**/*query*`, `**/*sql*`
