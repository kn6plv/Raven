# Cross-Platform Join / Group Chat Analysis

> How the APRS `join` group-creation pattern could be adopted by Meshtastic, MeshCore, and MeshChat — and what code can be shared.

## Current State: How Each Transport Handles Groups

### APRS (`aprs.uc`)
- **Groups are explicit callsign lists** stored in `cfg.groups[]`.
- The `join #groupname CALL1 CALL2 message` command creates/updates a group at runtime and sends the message to each member individually via APRS.
- Groups can optionally repeat received messages to other members (`repeat_member_messages`).
- Each group can now be bound to a specific APRS backend (`group.backend`).
- Group creation does **not** create a new Raven channel — everything stays on the main APRS channel.

### Meshtastic (`meshtastic.uc`)
- **No group concept** — Meshtastic uses shared symmetric key channels.
- "Groups" are achieved by sharing a channel name+key. All devices with the same key hear the same traffic.
- Messages are encrypted with the channel key (AES-CTR for channel messages, AES-CCM for direct).
- There is no runtime group creation — channels must be pre-configured.
- Direct messages go to a specific node ID, not a callsign.

### MeshCore (`meshcore.uc`)
- **Rooms** exist as a MeshCore concept (`ADV_TYPE_ROOM`), but Raven doesn't create them.
- Group text messages (`PAYLOAD_TYPE_GRP_TXT`) are encrypted with the channel's symmetric key and broadcast.
- Direct messages are encrypted with per-peer shared keys (X25519 key exchange).
- Like Meshtastic, "groups" are really shared-key channels.
- No runtime group creation from Raven.

### Summary Table

| Feature | APRS | Meshtastic | MeshCore |
|---------|------|------------|----------|
| Group = | Callsign list | Shared key channel | Shared key channel / Room |
| Runtime create | ✅ `join` command | ❌ | ❌ |
| Member addressing | Individual callsigns | Broadcast on channel | Broadcast on channel |
| Backend binding | ✅ per-group | N/A (multicast UDP) | N/A (multicast UDP) |
| Encryption | None (Part 97) | AES-CTR / AES-CCM | AES-ECB shared key |

## How `join` Could Work for Meshtastic and MeshCore

### The Key Difference

APRS groups are **address lists** — the bridge sends individual messages to each member. Meshtastic/MeshCore groups are **shared-key broadcast channels** — anyone with the key hears everything.

For Meshtastic/MeshCore, "joining a group" means **creating a new channel with a shared key**, not adding callsigns to a list.

### Proposed `join` for Meshtastic/MeshCore

```text
join #EmComm
```

This would:
1. Generate a deterministic key from the name: `sha256("#EmComm")[0:16]` → base64 (this is already how `#NAME` channels work in the existing key-gen UI code — see `genChannelKey` in `ui.js`).
2. Register the channel via `channel.updateLocalChannels()`.
3. Trigger a "Configure Channel" step — the new channel appears in the channel list and the UI prompts or auto-saves.
4. The channel is now usable for both Meshtastic and MeshCore (unless the name matches a preset isolation rule).

The user on the other end would need to `join #EmComm` as well (or be given the key) — this is inherent to the shared-key model.

### Proposed `join` for MeshChat / Mixed Use

MeshChat (the web UI) could offer a unified `join` command:

```text
join #EmComm                           → creates channel, Meshtastic+MeshCore+AREDN
join #EmComm backend=direwolf1         → creates channel + binds to APRS backend
join #APRSnet KN6PLV KJ6DZB hello      → APRS-style callsign group
```

The command parser would detect:
- If callsigns follow the group name → APRS-style group (callsign list)
- If no callsigns → channel-based group (shared key)

## Shared Code: A `groups.uc` Module

Several pieces of the APRS group logic are transport-agnostic and could be extracted:

### Candidates for `groups.uc`

```
// From aprs.uc — generic group management
normcall(c)              → already useful across transports
memberOf(call)           → "which groups is this callsign in?"
getGroup(name)           → lookup by name
putGroup(name, members)  → create/update group
parseInlineRecipients()  → parse "CALL1, CALL2 message text"
canRepeat(g, src, text)  → duplicate suppression + rate limiting

// New shared functionality
createGroupChannel(name) → register via channel.updateLocalChannels()
resolveGroupBackend(g)   → backend resolution chain
```

### What stays transport-specific

```
// APRS-specific
backendSend()            → TCP socket I/O
ax25Addr() / kissFrame() → AX.25 framing
sendAck()                → APRS message ACK protocol

// Meshtastic-specific
encodePacket()           → protobuf + AES-CTR encryption
makeMeshtasticMsg()      → multicast UDP send

// MeshCore-specific
makeMeshcoreMsg()        → binary packet + AES-ECB encryption
```

### Proposed `groups.uc` Interface

```js
// groups.uc
export function setup(config);
export function getGroup(name);
export function putGroup(name, members, opts);  // opts: { backend, repeat, rate_limit }
export function removeGroup(name);
export function memberOf(call);
export function allGroups();
export function parseJoinCommand(text);         // returns { group, members?, backend?, text }
export function canRepeat(group, src, text, id);
export function createGroupChannel(name);       // registers channel via channel.uc
```

Each transport module would import `groups.uc` and use it for group management, while keeping their own send/receive logic.

## Channel Creation on Group Join

When a new group is created via `join`, a "Configure Channel" step should occur:

1. **`groups.uc` calls `channel.updateLocalChannels()`** to register the new channel with the Raven channel system.
2. **The channel appears in the UI** immediately — the `event.uc` `channels` event fires.
3. **For APRS channels**: The channel gets the `og==` key (AREDN-only, never bridged to Meshtastic/MeshCore).
4. **For Meshtastic/MeshCore channels**: The channel gets a `sha256(#name)` key and is bridgeable.
5. **Backend binding**: If the `join` command specified `backend=NAME`, the channel→backend binding is set.
6. **Persistence**: `config.uc` writes the new channel to `raven.conf.override` so it survives restarts.

### UI Flow

When a user types `join #NewGroup ...` in the chat:
1. Group is created, message is sent.
2. Channel list updates automatically (websocket event).
3. User can click the cog → **Configure Channels** to adjust settings (backend, notify, images, etc.).

Alternatively, the UI could pop a brief "Channel created: NewGroup" toast notification.

## Implementation Status

1. ✅ **`groups.uc` extracted** — shared group CRUD, join parsing, channel creation (~220 lines).
2. ✅ **`/join` slash command** — unified entry point in `commands.uc` for both channel joins and APRS groups.
3. ✅ **`/leave` slash command** — removes channel + APRS group in one step.
4. ✅ **`/groups` slash command** — lists all APRS groups and members.
5. ✅ **`/help` slash command** — documents all available commands.
6. ✅ **Multi-backend APRS** — per-channel backend binding, `/join` supports `backend=NAME`.
7. 🔮 **MeshCore Room integration** — future: map Raven groups to MeshCore Room advertisements.

### What `meshtastic.uc` and `meshcore.uc` needed: Nothing

They already send to any channel by namekey. The `/join #name` command creates the channel via `groups.createGroupChannel()`, which fires the `newchannels` event through the existing pipeline. The router's forwarding logic and the transport `send()` functions handle the rest automatically.
