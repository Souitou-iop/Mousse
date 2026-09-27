# Mousse CLI for Agents

This guide describes the local command-line surface intended for scripts and AI agents. The CLI is a short-lived client for the **already running** Mousse app; it does not start a second app process or create a second event tap.

## 1. Preconditions

1. Mousse must already be running.
2. The agent must be able to execute the `Mousse` executable. For a packaged app, use the binary inside the app bundle, for example:
   ```sh
   /Applications/Mousse.app/Contents/MacOS/Mousse status
   ```
   When running from this repository, use the executable produced by the project build.
3. Commands are local-only. The app exposes a user-owned Unix-domain socket with mode `0600` while it is running.

If Mousse is not running, the CLI writes an error to stderr and exits with code `1`.

## 2. Discover the interface

Agents should begin with:

```sh
Mousse help
Mousse --version
```

`Mousse help` is generated from the same configuration-key table used by the command router. Treat it as the runtime source of truth when a newer build adds or changes a key.

## 3. Commands

| Command | Purpose | Output |
| --- | --- | --- |
| `Mousse status` | Read the engine and permission summary. | One JSON object. |
| `Mousse diagnostics` | Read the full diagnostics snapshot. | One JSON object. |
| `Mousse get <key>` | Read one supported scalar configuration value. | One JSON object. |
| `Mousse set <key> <value>` | Validate, apply, and persist one supported scalar configuration value. | One JSON object. |
| `Mousse quit` | Ask the running app to terminate gracefully. | One JSON object. |
| `Mousse help` | Print command and key usage. | Human-readable text. |
| `Mousse --version` | Print the app version. | Text. |

Do not use `quit` as a health check. It is a mutating command that terminates the app.

## 4. Recommended agent workflow

For a read-only inspection:

```sh
Mousse status
Mousse diagnostics
Mousse get enabled
```

For a configuration change:

1. Read `status` or `diagnostics` first.
2. Read the current value with `get`.
3. Validate the requested value against the key table below (or the current `Mousse help` output).
4. Apply exactly one change with `set`.
5. Check the JSON response and exit code.
6. Read the key again if the workflow needs independent confirmation.

Example:

```sh
Mousse get scrollMode
Mousse set scrollMode smooth
Mousse get scrollMode
```

`set` uses the same live-reload and persistence path as the Settings UI. It only accepts the whitelisted scalar keys; it cannot replace mappings or arbitrary configuration blobs.

## 5. Supported configuration keys

The accepted values in the current protocol are:

| Key | Type / accepted values |
| --- | --- |
| `edgeScroll` | `true` or `false` |
| `edgeScrollSpeed` | Number from `50` to `2400` |
| `enabled` | `true` or `false` |
| `reverseScroll` | `true` or `false` |
| `scrollAcceleration` | `true` or `false` |
| `scrollMode` | `standard`, `smooth`, or `smoothStep` |
| `scrollSmoothness` | `snappy`, `balanced`, or `floaty` |
| `scrollSpeed` | Number from `0.05` to `3.0` |
| `smoothHighRes` | `true` or `false` |
| `zoomSpeed` | Number from `0.2` to `6.0` |

The list is intentionally narrow. Use `Mousse help` for the authoritative, build-specific list.

Examples:

```sh
Mousse set enabled false
Mousse set scrollSpeed 0.5
Mousse set edgeScroll true
Mousse set scrollMode smoothStep
```

Boolean values must be written as `true` or `false`. Numeric values must be finite and within the key's range. Enum values are case-sensitive. Values that are not booleans or finite numbers are sent as strings, then validated by the app.

## 6. Output and exit-code contract

All command requests that talk to the app return one JSON object on stdout. Successful responses contain:

```json
{
  "ok": true,
  "v": 1
}
```

The command-specific payload is included alongside `ok` and `v`. Errors contain:

```json
{
  "ok": false,
  "v": 1,
  "error": "..."
}
```

Exit codes:

- `0`: command succeeded (`ok: true`).
- `1`: runtime or app error, including Mousse not running or a rejected request.
- `2`: CLI usage error, such as a missing argument or invalid command shape.

Agents should check both the process exit code and the JSON `ok` field. Never infer success from stdout being non-empty.

Example error handling in POSIX shell:

```sh
if output="$(Mousse set scrollSpeed 0.5)"; then
  printf '%s\n' "$output"
else
  status=$?
  printf 'Mousse CLI failed (exit %s): %s\n' "$status" "$output" >&2
  exit "$status"
fi
```

## 7. Optional direct socket protocol

Most agents should invoke the CLI instead of implementing the socket client. If a local integration needs the protocol directly, the app accepts one newline-terminated JSON request per Unix-domain socket connection:

```json
{"v":1,"cmd":"get","key":"scrollMode"}
```

Supported commands are `status`, `diagnostics`, `get`, `set`, and `quit`. `get` requires `key`; `set` requires `key` and `value`. Every request must include protocol version `"v": 1`.

The socket path is derived from the user's macOS Application Support directory:

```text
~/Library/Application Support/Mousse/mousse.sock
```

The socket is available only while the app is running and is restricted to the local user. The CLI remains the compatibility boundary preferred for agents.

## 8. Safety rules for agents

- Prefer `status`, `diagnostics`, and `get` before making changes.
- Change one key at a time and preserve the returned JSON for auditability.
- Do not call `quit` unless the user or workflow explicitly requires stopping Mousse.
- Do not write configuration files directly when the same change is available through `set`.
- Treat unknown keys, rejected values, and a missing app as failures requiring a new decision, not as permission to guess.
