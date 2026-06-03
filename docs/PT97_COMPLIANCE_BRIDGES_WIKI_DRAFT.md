# Draft: "Part 97 Compliance" section for the Raven Bridges wiki page

> Paste this after the existing content on https://github.com/kn6plv/Raven/wiki/Bridges

---

## Part 97 Compliance

AREDN operates under FCC Part 97 (Amateur Radio Service), which **prohibits encryption** of message content over the air. Meshtastic and MeshCore, by contrast, are encrypted networks. Raven's bridge design enforces Part 97 compliance at the boundary between these networks through several mechanisms.

### Encryption Boundary

When a message crosses from Meshtastic or MeshCore into AREDN, the bridge **decrypts** it. The message then travels across the AREDN mesh as plaintext — visible to anyone monitoring the network, as required by Part 97.

When an AREDN message is forwarded to Meshtastic or MeshCore, the bridge **encrypts** it using the appropriate channel key before transmitting it to the encrypted network.

> **Important:** While messages may appear encrypted and secure when viewed on a Meshtastic or MeshCore device, they are always transmitted in the clear on the AREDN network.

### Channel Filters

Raven uses several channel-level filters to control what traffic can cross a bridge:

| Filter | Behavior |
|--------|----------|
| **AREDN-Only channels** | Channels using the AREDN key suffix (`og==`) are never forwarded to Meshtastic or MeshCore. Use these for traffic that must stay on the amateur radio network. |
| **Meshtastic preset isolation** | Default Meshtastic channels (LongFast, ShortFast, MediumFast, etc.) are not forwarded to MeshCore. |
| **MeshCore preset isolation** | The MeshCore public channel is not forwarded to Meshtastic. |

These filters prevent unintended leakage of platform-specific default channels across bridge boundaries.

### No Cross-Bridge Routing

Raven does **not** bridge traffic between Meshtastic and MeshCore. A message arriving from Meshtastic can only be forwarded via AREDN (MeshIP); it is never re-transmitted to MeshCore, and vice versa. This is enforced in the router: incoming bridge traffic is routed only over IP with `hop_limit = 0`, preventing further forwarding.

### Hop-Limit Clamping

Messages received from a bridge have their hop limit set to 1 upon arrival. This ensures that a downstream Raven node cannot re-bridge the message to another bridge instance, preventing uncontrolled propagation between networks.

### MeshCore Caveat

MeshCore does not currently offer a "Part 97 mode" — there is no way to disable encryption on MeshCore radio links. While Raven decrypts MeshCore traffic before placing it on the AREDN network (satisfying Part 97 on the AREDN side), the MeshCore radio segment itself remains encrypted. Operators should be aware of this regulatory grey area when deploying a MeshCore bridge.
