# Raven APRS Bridge

Raven can bridge APRS text messages through one or more configurable APRS backends. Different channels can be bound to different backends — for example, `APRS og==` can use APRS-IS while `APRS2 og==` uses a local Dire Wolf KISS TNC.

APRS is public amateur-radio traffic. Keep transmit disabled until the station callsign, APRS-IS login/passcode or local TNC path, and operator control requirements are understood.

## Quick Start

1. Add an `aprs` block to `raven.conf` (see [Basic Configuration](#basic-configuration)).
2. Add an APRS channel to the `channels` array: `{ "namekey": "APRS og==", "backend": "aprsis1" }`.
3. Open the Raven UI. The APRS channel appears in the sidebar.
4. Type `/help` in the message box for a list of all commands.

---

## Slash Commands Reference

All slash commands are typed in the Raven chat message box. They start with `/` and are sent by pressing Enter.

### /help

Show a summary of all available commands.

```
/help
```

### /join — Create or join a channel / APRS group

```
/join #name                                — join/create shared-key channel (Meshtastic+MeshCore+AREDN)
/join %name                                — join/create AREDN-only channel
/join #name CALL1 CALL2 message text       — create APRS group + AREDN channel + send message
/join #name backend=NAME CALL1 CALL2 msg   — APRS group bound to a specific backend
```

**Channel-only join** (no callsigns): Creates a shared-key channel using `sha256("#name")` as the encryption key. The channel is usable by Meshtastic, MeshCore, and AREDN. Use `%name` instead of `#name` to create an AREDN-only channel (never bridged to encrypted networks).

**APRS group join** (with callsigns): Creates an AREDN-only channel (`#name og==`) and an APRS callsign group. The channel keeps the name you typed but uses the unencrypted `og==` key. The message is sent to each listed callsign via the APRS backend. APRS groups are always AREDN-only because APRS is Part 97 amateur radio traffic. The channel is automatically bound to the default APRS backend so messages typed in the channel are sent to all group members.

**Callsign detection:** Callsigns must contain at least one digit (e.g. `KN6PLV`, `KJ6DZB-4`). Plain words like `radio`, `check`, or `hello` are treated as message text, not callsigns.

The optional `backend=NAME` parameter binds the group (and its channel) to a specific named APRS backend (see [Multi-Backend Configuration](#multi-backend-configuration)).

**Examples:**

```
/join #EmComm
```
Creates the channel `#EmComm` with a shared encryption key. Anyone who joins `#EmComm` on any Raven node can see messages.

```
/join #TacNet KN6PLV KJ6DZB-4 radio check
```
Creates AREDN-only channel `#TacNet og==` (displayed as "TacNet" in the sidebar), creates group `#TacNet` with members KN6PLV and KJ6DZB-4, and sends "radio check" to both via APRS. Plain text typed in this channel is automatically sent to all group members.

```
/join #TacNet backend=direwolf1 KN6PLV KJ6DZB-4 radio check
```
Same as above, but sends via the `direwolf1` KISS TNC backend instead of the default.

### /leave — Leave a channel and remove APRS group

```
/leave #name
```

Removes the channel from the sidebar and deletes the APRS group if one exists for that name. Both `#name` and `%name` variants are removed.

**Example:**

```
/leave #TacNet
```

### /groups — List all APRS groups

```
/groups
```

Shows all configured APRS groups, their members, backend bindings, and repeat mode.

### /backends — List configured APRS backends

```
/backends
```

Shows all configured APRS backends with their name and type. Each entry displays the backend key and a label indicating its type (e.g. `aprs-is[aprsis1]`, `aprs-kiss[direwolf1]`, `aprs-tnc[xastir1]`).

Useful for verifying which backends are active and finding the correct name for `backend=NAME` in `/join` commands.

### /channels — Channel management

```
/channels              — list public channels on the local network
/channels world        — list public channels across the mesh (via bridge)
/channels join #name   — join a channel by name (generates key from name)
/channels join name key — join a channel by explicit name and key
/channels leave name   — leave a channel
```

The `/channels join` and `/channels leave` commands are the original channel management commands. The newer `/join` and `/leave` commands are recommended for most use — they handle both channels and APRS groups in one step.

---

## AREDN-Only Channels

Channels prefixed with `%` (instead of `#`) are **AREDN-only** — they travel exclusively over the AREDN mesh network and are never bridged to Meshtastic or MeshCore.

| Prefix | Key | Bridges to | Use case |
|--------|-----|-----------|----------|
| `#Name` | SHA-256 derived | Meshtastic + MeshCore + AREDN | General mesh chat |
| `%Name` | `og==` (unencrypted) | AREDN only | APRS groups, Part 97 compliant |

AREDN-only channels use the key `og==` (a single-byte default key), which means no encryption. This is required for amateur radio compliance.

**Why APRS groups are always AREDN-only:** FCC Part 97 prohibits encrypting amateur radio traffic. Because APRS is Part 97 amateur radio, APRS group messages must never be bridged to Meshtastic or MeshCore channels (which use encryption). When you create a group with `/join #TacNet KN6PLV KJ6DZB msg`, Raven uses the `og==` key (unencrypted) regardless of the prefix, keeping the channel name you typed.

A plain `/join #Name` (no callsigns) creates a shared-key encrypted channel that bridges across all three networks. Only when callsigns are added does the channel get forced to AREDN-only.

**Sidebar display:** Channel labels in the UI strip the `#` and `%` prefixes — a channel named `#TacNet og==` appears as "TacNet" in the sidebar.

---

## APRS Chat Commands

These are typed as regular messages (no `/` prefix) on an APRS channel such as `APRS og==`.

### Direct message

Send a direct APRS message to a single station:

```
@N0CALL-4 message text
```

### Send to a group

Send to all members of an existing APRS group:

```
#APRSgroup1 message text
```

### Send to an inline list

Send to specific callsigns without changing the group membership:

```
#APRSgroup1 N0CALL-4, N0CALL-7 message text
```

### In-chat group create (join)

Create or update an APRS group and send a message in one step (no `/` prefix — this is the in-chat variant):

```
join #APRSgroup1 N0CALL-4, N0CALL-7 message text
```

The `join` form creates `APRSgroup1` if it does not exist, replaces its member list, and sends the message. This does **not** create a separate channel — use `/join` (with the slash) for that.

---

## Basic Configuration

Add an `aprs` block to `raven.conf` and an APRS channel to `channels`:

```json
{
  "callsign": "N0CALL-10",
  "aprs": {
    "enabled": true,
    "callsign": "N0CALL-10",
    "channel": "APRS og==",
    "default_group": "APRSgroup1",
    "inline_max_members": 10,
    "backends": {
      "aprsis1": {
        "type": "aprsis",
        "host": "rotate.aprs2.net",
        "port": 14580,
        "tx_enabled": false
      }
    },
    "groups": [
      {
        "name": "APRSgroup1",
        "members": [ "N0CALL-4", "N0CALL-7" ],
        "repeat_member_messages": false,
        "rate_limit_seconds": 20,
        "max_members": 10
      }
    ]
  },
  "channels": [
    { "namekey": "AREDN og==", "telemetry": false },
    { "namekey": "APRS og==", "telemetry": false, "backend": "aprsis1" }
  ]
}
```

## Multi-Backend Configuration

Define multiple named backends under `aprs.backends` and bind each channel to a backend:

```json
{
  "aprs": {
    "enabled": true,
    "callsign": "N0CALL-10",
    "channel": "APRS og==",
    "default_group": "APRSgroup1",
    "backends": {
      "aprsis1": {
        "type": "aprsis",
        "host": "rotate.aprs2.net",
        "port": 14580,
        "passcode": "REPLACE_WITH_APRS_IS_PASSCODE",
        "filter": "b/N0CALL-4/N0CALL-7",
        "tx_enabled": true
      },
      "direwolf1": {
        "type": "kiss_tcp",
        "host": "127.0.0.1",
        "port": 8001,
        "kiss_port": 0,
        "path": [],
        "tx_enabled": true
      }
    },
    "groups": [
      {
        "name": "APRSgroup1",
        "members": [ "N0CALL-4", "N0CALL-7" ],
        "backend": "aprsis1"
      },
      {
        "name": "LocalTNC",
        "members": [ "N0CALL-2" ],
        "backend": "direwolf1"
      }
    ]
  },
  "channels": [
    { "namekey": "AREDN og==", "telemetry": false },
    { "namekey": "APRS og==", "telemetry": false, "backend": "aprsis1" },
    { "namekey": "APRS2 og==", "telemetry": false, "backend": "direwolf1" }
  ]
}
```

Raven opens a separate TCP connection for each named backend. Messages arriving on a backend are routed to the channel bound to that backend. Outbound messages are sent through the backend bound to the channel the message was posted from.

## Backward Compatibility

The old single `aprs.backend` (singular) configuration is still supported. If `aprs.backends` (plural) is not present, Raven wraps `aprs.backend` as `backends.default` automatically.

```json
"aprs": {
  "backend": {
    "type": "aprsis",
    "host": "rotate.aprs2.net",
    "port": 14580,
    "tx_enabled": false
  }
}
```

This is equivalent to:

```json
"aprs": {
  "backends": {
    "default": {
      "type": "aprsis",
      "host": "rotate.aprs2.net",
      "port": 14580,
      "tx_enabled": false
    }
  }
}
```

## Backend Types

### APRS-IS

Internet-connected APRS server. Most common for receive-only or wide-area APRS messaging.

```json
"aprsis1": {
  "type": "aprsis",
  "host": "rotate.aprs2.net",
  "port": 14580,
  "passcode": "REPLACE_WITH_APRS_IS_PASSCODE",
  "filter": "b/N0CALL-4/N0CALL-7",
  "tx_enabled": true
}
```

| Field | Description |
|-------|-------------|
| `type` | `"aprsis"` |
| `host` | APRS-IS server hostname (default: `rotate.aprs2.net`) |
| `port` | Server port (default: `14580`) |
| `passcode` | APRS-IS passcode for TX (default: `"-1"` = receive-only) |
| `filter` | Optional APRS-IS server-side filter string |
| `tx_enabled` | `true` to transmit, `false` for receive-only |

### Dire Wolf KISS TCP

Local Dire Wolf TNC via KISS-over-TCP. For RF APRS via a local radio.

```json
"direwolf1": {
  "type": "kiss_tcp",
  "host": "127.0.0.1",
  "port": 8001,
  "kiss_port": 0,
  "path": [],
  "tx_enabled": true
}
```

| Field | Description |
|-------|-------------|
| `type` | `"kiss_tcp"` |
| `host` | Dire Wolf host (default: `127.0.0.1`) |
| `port` | KISS TCP port (default: `8001`) |
| `kiss_port` | KISS port number 0-15 (default: `0`) |
| `path` | AX.25 digipeater path array, e.g. `["WIDE1-1","WIDE2-1"]` |
| `tx_enabled` | `true` to transmit |

### Xastir / YAAC / TCP text

Generic TNC2-format TCP text stream. Works with Xastir, YAAC, or any APRS application that speaks raw TNC2 over TCP.

```json
"xastir1": {
  "type": "tcp_text",
  "host": "127.0.0.1",
  "port": 14580,
  "tx_enabled": true
}
```

| Field | Description |
|-------|-------------|
| `type` | `"tcp_text"`, `"xastir"`, or `"yaac"` (all equivalent) |
| `host` | Server host |
| `port` | Server port |
| `tx_enabled` | `true` to transmit |

## Channel → Backend Binding

Each channel in the `channels` array can include a `backend` field matching a named backend:

```json
{ "namekey": "APRS og==", "backend": "aprsis1" }
{ "namekey": "APRS2 og==", "backend": "direwolf1" }
```

Channels without a `backend` field use the first defined backend (the default).

The binding can also be set from the Raven UI: open **Configure Channels** (the cog icon) — a **Backend** dropdown appears when APRS backends are configured.

## Backend Resolution Order

When sending a message, Raven resolves the backend in this order:

1. **Group backend** — if the target APRS group has a `backend` field, use it.
2. **Channel backend** — the backend bound to the channel the message was posted from.
3. **Default backend** — the first backend defined in `aprs.backends`.

## Group Repeat Mode

Each APRS group can optionally repeat received messages from one member to the others:

```json
{
  "name": "APRSgroup1",
  "members": [ "N0CALL-4", "N0CALL-7" ],
  "repeat_member_messages": true,
  "rate_limit_seconds": 20,
  "max_members": 10,
  "backend": "aprsis1"
}
```

When enabled, a message received from one group member is sent to the other members (not back to the sender). Raven applies duplicate suppression and rate limiting.

## UI Configuration

When APRS backends are configured, the **Configure Channels** dialog (cog icon in the Channels sidebar) shows a **Backend** dropdown for each channel. Select which backend a channel should use, or leave it as `(default)`.

Channels and APRS groups created via `/join` appear in the sidebar immediately. Use the cog to adjust settings (max messages, notifications, images, Winlink, backend) after creation.
