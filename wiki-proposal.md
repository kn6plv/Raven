# Wiki Changes Proposal — Adding APRS to the Raven Wiki

## Current Wiki Structure (kn6plv/Raven/wiki)

| Page | Last Updated | Status |
|------|-------------|--------|
| Home | Apr 5 | — |
| Installation | Apr 5 | — |
| Getting Started | Mar 26 | — |
| Configuring Channels | Mar 26 | — |
| Sending Messages | Mar 31 | Empty / placeholder |
| Direct Messages | Mar 30 | Empty / placeholder |
| Advanced Configuration | Mar 29 | Short intro only |
| Meshtastic | Apr 15 | Full page |
| MeshCore | Apr 5 | Full page |
| Winlink | Apr 15 | Empty / placeholder |
| ??? (other pages) | Various | — |

---

## Proposed Changes

### 1. NEW PAGE: "APRS" (standalone wiki page)

**Location:** `wiki/APRS` (same sidebar level as Meshtastic and MeshCore)

This is where the bulk of APRS.md content goes, expanded with DM/group messaging details from the code. The page follows the same structure as the Meshtastic and MeshCore pages.

#### Proposed Content:

```markdown
# APRS

Raven can bridge APRS text messages to and from the AREDN mesh through a
configurable APRS backend. The default backend is APRS-IS, but Raven also
supports Dire Wolf KISS-over-TCP and Xastir/YAAC-style TCP text streams.

> **Important:** APRS is public amateur-radio traffic. Keep transmit disabled
> until the station callsign, APRS-IS login/passcode or local TNC path, and
> Part 97 operator control requirements are understood.

## Prerequisites

- A valid amateur radio callsign (with SSID, e.g. `N0CALL-10`)
- For APRS-IS: an APRS-IS passcode (if transmitting)
- For Dire Wolf / TNC: a local Dire Wolf or TNC instance reachable via TCP

## Enabling the APRS bridge

Edit `raven.conf.override` (see [Advanced Configuration](Advanced-Configuration))
and add an `aprs` block:

```json
{
  "aprs": {
    "enabled": true,
    "callsign": "N0CALL-10",
    "channel": "APRS og==",
    "default_group": "MyGroup",
    "backend": {
      "type": "aprsis",
      "host": "rotate.aprs2.net",
      "port": 14580,
      "tx_enabled": false
    }
  }
}
```

Restart Raven: `/etc/init.d/raven restart`

Raven will automatically create an **APRS-IS-Feed** channel. You can also
add a named APRS channel manually (see
[Configuring Channels](Configuring-Channels)).

## Backend types

### APRS-IS (Internet gateway)

```json
"backend": {
  "type": "aprsis",
  "host": "rotate.aprs2.net",
  "port": 14580,
  "passcode": "REPLACE_WITH_PASSCODE",
  "filter": "b/N0CALL-4/N0CALL-7",
  "tx_enabled": true
}
```

The `filter` field is an optional APRS-IS server-side filter
(see [APRS-IS filter docs](http://www.aprs-is.net/javAPRSFilter.aspx)).

### Dire Wolf KISS TCP (local TNC)

```json
"backend": {
  "type": "kiss_tcp",
  "host": "127.0.0.1",
  "port": 8001,
  "kiss_port": 0,
  "path": [],
  "tx_enabled": true
}
```

### Xastir / YAAC TCP text stream

```json
"backend": {
  "type": "tcp_text",
  "host": "127.0.0.1",
  "port": 14580,
  "tx_enabled": true
}
```

## The APRS-IS-Feed channel

When APRS is enabled without an explicit `channel` setting, Raven creates a
default channel called **APRS-IS-Feed**. All inbound APRS messages that do not
match a DM channel appear here. You can rename this by setting `"channel"` in
the `aprs` config block.

## Sending messages

All APRS messages are sent from the configured APRS channel in the Raven UI.

### Direct messages (DMs)

Send a message to a single APRS station by prefixing with `@`:

```
@N0CALL-4 hello from the mesh
```

When the remote station replies, Raven **automatically creates a DM channel**
for that callsign (e.g. `n0call-4 og==`) so subsequent messages appear in
their own conversation thread — just like a DM in any messaging app. You can
then type directly in that DM channel without the `@` prefix.

If you type `@callsign` in a DM channel where the callsign matches the
channel destination, Raven strips the prefix automatically.

### Group messages

Send to all members of a pre-configured group:

```
#MyGroup hello everyone
```

Send to an inline list of stations (without modifying the saved group):

```
#MyGroup N0CALL-4, N0CALL-7 hello everyone
```

Create or update a group on the fly and send:

```
join #MyGroup N0CALL-4, N0CALL-7 hello everyone
```

The `join` form creates `MyGroup` if it doesn't exist, replaces its member
list, and sends the message.

### How inbound messages are routed

| Sender is... | Delivered to... |
|---|---|
| A member of a configured group | The main APRS channel (so the group conversation stays visible) |
| A station with an existing DM channel | That DM channel |
| Any other station | The main APRS channel |

### Group repeat mode

Each group can optionally repeat messages between members:

```json
{
  "name": "MyGroup",
  "members": ["N0CALL-4", "N0CALL-7"],
  "repeat_member_messages": true,
  "rate_limit_seconds": 20,
  "max_members": 10
}
```

When enabled, a message from one group member is forwarded to all other group
members. Duplicate suppression and rate limiting prevent loops.

## Configuration reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `aprs.enabled` | bool | `false` | Enable the APRS bridge |
| `aprs.callsign` | string | node callsign | Station callsign with SSID |
| `aprs.channel` | string | `"APRS-IS-Feed og=="` | Raven channel namekey for APRS traffic |
| `aprs.default_group` | string | — | Default group name when none specified |
| `aprs.inline_max_members` | int | `10` | Max stations in an inline group send |
| `aprs.backend.type` | string | `"aprsis"` | Backend type: `aprsis`, `kiss_tcp`, `tcp_text` |
| `aprs.backend.host` | string | `"rotate.aprs2.net"` | Backend host |
| `aprs.backend.port` | int | `14580` | Backend port |
| `aprs.backend.passcode` | string | — | APRS-IS passcode (required for TX) |
| `aprs.backend.filter` | string | — | APRS-IS server-side filter |
| `aprs.backend.tx_enabled` | bool | `false` | Enable transmit |
| `aprs.backend.kiss_port` | int | `0` | KISS port number (kiss_tcp only) |
| `aprs.backend.path` | array | `[]` | Digipeater path (kiss_tcp only) |
| `aprs.groups[]` | array | `[]` | Pre-configured station groups |
| `aprs.groups[].name` | string | — | Group name |
| `aprs.groups[].members` | array | — | Array of callsigns |
| `aprs.groups[].repeat_member_messages` | bool | `false` | Repeat messages between members |
| `aprs.groups[].rate_limit_seconds` | int | `20` | Min seconds between group sends |
| `aprs.groups[].max_members` | int | `10` | Max group members |
```

---

### 2. UPDATE: "Integrating with other mesh platforms" section (if this is a sidebar category)

Currently the wiki sidebar groups **Meshtastic** and **MeshCore** as peer integration pages. **Add APRS** as a third entry at the same level:

```
Integrating with other platforms
├── Meshtastic
├── MeshCore
└── APRS          ← NEW
```

---

### 3. UPDATE: "Configuring Channels" page

Add a paragraph about the APRS channel after the existing channel key discussion:

#### Add after the MeshCore key paragraph:

```markdown
### APRS channel

When the APRS bridge is enabled, Raven automatically creates an
**APRS-IS-Feed** channel for inbound and outbound APRS traffic. You can also
add a custom APRS channel manually using a channel name and key of your
choosing; just make sure the `aprs.channel` config value matches the channel's
namekey.

Direct messages to individual APRS stations can create additional DM channels
automatically. These appear in your channel list as the remote callsign
(e.g. `n0call-4`) and share the same key as the main APRS channel.

See [APRS](APRS) for full configuration details.
```

---

### 4. UPDATE: "Advanced Configuration" page

The current page only explains `raven.conf` vs `raven.conf.override`. Add APRS as a documented config block alongside any other advanced options.

#### Append to the existing content:

```markdown
## APRS bridge

Raven can bridge APRS text messages to and from the AREDN mesh. Add an `aprs`
block to your override file to enable it:

```json
{
  "aprs": {
    "enabled": true,
    "callsign": "N0CALL-10",
    "backend": {
      "type": "aprsis",
      "host": "rotate.aprs2.net",
      "port": 14580,
      "tx_enabled": false
    }
  }
}
```

Supported backend types are `aprsis` (APRS-IS internet gateway), `kiss_tcp`
(Dire Wolf KISS-over-TCP), and `tcp_text` (Xastir/YAAC-style TCP).

For the complete configuration reference, group messaging, and DM channel
behavior, see the [APRS](APRS) wiki page.
```

---

### 5. UPDATE: "_Sidebar" (wiki navigation)

Add APRS to the sidebar navigation. Proposed structure:

```markdown
- [Home](Home)
- [Installation](Installation)
- [Getting Started](Getting-Started)
- [Configuring Channels](Configuring-Channels)
- **Integrating with other platforms**
  - [Meshtastic](Meshtastic)
  - [MeshCore](MeshCore)
  - [APRS](APRS)
- [Advanced Configuration](Advanced-Configuration)
- [Winlink](Winlink)
```

---

## Summary of changes

| Target | Action | What |
|--------|--------|------|
| **New: `APRS`** | Create | Full standalone page — config, backends, DM channels, groups, inbound routing, config reference |
| **Configuring Channels** | Append | Short paragraph about APRS channel and auto-created DM channels |
| **Integrating with other platforms** | Add link | APRS alongside Meshtastic and MeshCore |
| **Advanced Configuration** | Append | Brief APRS config block example with link to full APRS page |
| **_Sidebar** | Update | Add APRS under the platforms section |

## What happens to APRS.md in the repo?

Keep `APRS.md` in the `pt97-compliance` branch as a quick-start reference, but
update it to point to the wiki for the full documentation:

> For the complete APRS documentation including DM channels, group messaging,
> inbound routing, and all backend options, see the
> [Raven Wiki — APRS](https://github.com/kn6plv/Raven/wiki/APRS) page.
