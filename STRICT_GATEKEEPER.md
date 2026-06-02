# Strict Gatekeeper mode

Strict Gatekeeper mode is an optional fail-closed bridge policy for sites that want tighter control over Meshtastic or MeshCore text traffic before it is forwarded to AREDN.

Example configuration:

```json
{
  "strict_gatekeeper": {
    "enabled": true,
    "gateway_callsign": "W6XYZ",
    "allowed_callsigns": ["KN6PLV", "KJ6DZB"]
  }
}
```

When enabled, Raven applies these controls before Meshtastic or MeshCore ingress is admitted to the routing queue:

- encrypted Meshtastic protobuf packets are dropped instead of decrypted for bridge forwarding;
- non-text bridged packets are dropped;
- the sender name must contain a US-style amateur callsign token such as `KN6PLV`, `W6XYZ`, or `KJ6DZB`;
- if `allowed_callsigns` is non-empty, the extracted sender callsign must also appear in that whitelist;
- forwarded text is re-written to originate from the gateway node, and the body is prefixed as `[SENDER via GATEWAY] message`.

## Operational caveats

Strict Gatekeeper mode is a transport safety control, not an identity proof system. Meshtastic and MeshCore display names are user-controlled, so a node can be renamed to look like a valid callsign. For real deployments, use `allowed_callsigns`; a future hardening step should bind allowed operators to a stable Meshtastic node ID or MeshCore public key.

The built-in callsign validator intentionally matches only a simple US amateur callsign form: one or two letters, one numeral, and one to three letters. It will reject international callsigns, special-event formats, and suffix forms that do not contain an extractable US callsign token.

Dropped packet logging uses the existing `DEBUG0` and `DEBUG1` debug channels. On headless OpenWrt deployments, confirm that log output is captured by the service manager or `logd` before relying on logs for troubleshooting.
