# Raven Part 97 Compliance — Quick-Start Reference

> Source: [kn6plv/Raven](https://github.com/kn6plv/Raven) · wiki page: [Bridges](https://github.com/kn6plv/Raven/wiki/Bridges)
> Last reviewed: 2026-06-03

## TL;DR

AREDN is an amateur-radio (Part 97) network — **all traffic over the air must be unencrypted**.
Meshtastic and MeshCore are encrypted networks.
Raven bridges traffic between them, so it must enforce Part 97 at the boundary.

## Key Filters (code refs: `channel.uc`, `router.uc`)

| Filter | Function | Effect |
|--------|----------|--------|
| **AREDN-Only channels** | `isAREDNOnly(namekey)` | Channels ending in `" og=="` are never forwarded to Meshtastic or MeshCore. Traffic stays on-mesh. |
| **Meshtastic preset isolation** | `isMeshtasticPreset(namekey)` | Default Meshtastic channels (LongFast, ShortFast, etc.) are not forwarded to MeshCore. |
| **MeshCore preset isolation** | `isMeshcorePreset(namekey)` | The MeshCore public channel is not forwarded to Meshtastic. |
| **No cross-bridge routing** | router.uc routing logic | Raven **never** copies traffic between Meshtastic ↔ MeshCore. Each bridge only talks to/from AREDN. |
| **Hop-limit clamping** | `msg.hop_limit = 1` in bridge recv | Messages arriving from a bridge are clamped so they cannot be re-bridged by a downstream node. |
| **Bridge-origin IP-only routing** | `toip = true; msg.hop_limit = 0` | Incoming bridge traffic is forwarded only via MeshIP (AREDN), never back out a bridge. |

## Encryption Boundary

- **Meshtastic / MeshCore → AREDN**: Bridge decrypts the message. AREDN carries plaintext only.
- **AREDN → Meshtastic / MeshCore**: Bridge encrypts the message before sending to the encrypted network.
- Uses AES-CTR (channel messages) or AES-CCM (direct messages) for Meshtastic; ECB shared-key for MeshCore.

## Practical Implications

1. **One bridge per network type is enough** — all Raven nodes on the AREDN mesh can reach Meshtastic/MeshCore through a single bridge instance.
2. **Messages on AREDN are always in the clear** — even if they look encrypted on Meshtastic/MeshCore devices.
3. **AREDN-only channels** (`" og=="` postfix) give operators a way to keep sensitive infrastructure traffic off the bridges entirely.
4. **MeshCore currently has no Part 97 mode** (no way to disable encryption), so using it over amateur radio frequencies is a regulatory grey area. Raven's bridge decrypts on the AREDN side, but the MeshCore radio link itself remains encrypted.

## Config Example (raven.conf)

```json
{
  "channels": [
    { "namekey": "AREDN og==", "telemetry": false },
    { "namekey": "LongFast AQ==", "telemetry": true, "meshtastic": true }
  ],
  "meshtastic": { "address": "192.168.1.100" },
  "meshcore": { "bridgekey": "XXXX", "address": "..." }
}
```

- Channels with the `og==` postfix → AREDN-only, Part 97 safe
- Meshtastic preset channels (e.g., `LongFast AQ==`) → bridged to Meshtastic only, never to MeshCore
