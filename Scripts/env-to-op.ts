#!/usr/bin/env bun
import { $ } from "bun";
import { parseArgs, parseEnv } from "node:util";

const DEFAULT_VAULT = "ENV";
const CATEGORY = "Secure Note";

const { values, positionals } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		vault: { type: "string", short: "v", default: DEFAULT_VAULT },
		account: { type: "string", short: "a" },
		"dry-run": { type: "boolean", default: false },
		help: { type: "boolean", short: "h", default: false },
	},
	allowPositionals: true,
});

if (values.help || positionals.length < 2) {
	console.log(
		`Usage: env-to-op <env-file> <item-title> [--vault=<vault>] [--account=<account>] [--dry-run]

Creates a single 1Password "Secure Note" item where each env var is a concealed field.
Skips (with a warning) if an item with that title already exists in the vault.

Defaults: --vault="${DEFAULT_VAULT}"`,
	);
	process.exit(values.help ? 0 : 1);
}

const [envPath, title] = positionals as [string, string];
const vault = values.vault!;
const account = values.account;
const dryRun = values["dry-run"]!;

const accountArgs = account ? [`--account=${account}`] : [];

const file = Bun.file(envPath);
if (!(await file.exists())) {
	console.error(`✗ env file not found: ${envPath}`);
	process.exit(1);
}

const entries = Object.entries(parseEnv(await file.text()));
if (entries.length === 0) {
	console.error(`✗ no variables parsed from ${envPath}`);
	process.exit(1);
}

const exists = await $`op item get ${title} --vault=${vault} ${accountArgs}`.quiet().nothrow();
if (exists.exitCode === 0) {
	console.warn(`⚠ item "${title}" already exists in vault "${vault}" — skipping.`);
	process.exit(0);
}

const assignments = entries.map(([k, v]) => `${k}[concealed]=${v}`);

if (dryRun) {
	console.log("DRY RUN — would execute:");
	console.log(
		`op item create --category="${CATEGORY}" --vault=${vault} --title=${title} ` +
			entries.map(([k]) => `'${k}[concealed]=***'`).join(" "),
	);
	console.log(`\n${entries.length} field(s) to be created.`);
	process.exit(0);
}

const result =
	await $`op item create --category=${CATEGORY} --vault=${vault} --title=${title} ${accountArgs} ${assignments}`.nothrow();
if (result.exitCode !== 0) {
	process.exit(result.exitCode ?? 1);
}

console.log(`\n✓ created "${title}" in "${vault}" with ${entries.length} field(s).`);
console.log("\nSecret references:");
for (const [k] of entries) {
	console.log(`  ${k}=op(op://${vault}/${title}/${k})`);
}
