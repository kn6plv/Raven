# Raven APRS Bridge

Raven can bridge APRS text messages through a configurable APRS backend. The default backend is APRS-IS, but the APRS module also includes support for Xastir/YAAC-style TCP text streams and Dire Wolf KISS-over-TCP.

APRS is public amateur-radio traffic. Keep transmit disabled until the station callsign, APRS-IS login/passcode or local TNC path, and operator control requirements are understood.

## Basic configuration

Add an `aprs` block to `raven.conf` and add the APRS channel to `channels`:

```json
{
  "callsign": "N0CALL-10",
  "aprs": {
    "enabled": true,
    "callsign": "N0CALL-10",
    "channel": "APRS og==",
    "default_group": "APRSgroup1",
    "inline_max_members": 10,
    "backend": {
      "type": "aprsis",
      "host": "rotate.aprs2.net",
      "port": 14580,
      "tx_enabled": false
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
    { "namekey": "APRS og==", "telemetry": false }
  ]
}
```

For APRS-IS transmit, set a valid APRS-IS passcode in the backend config and set `tx_enabled` to `true` only when ready.

## Backend types

APRS-IS:

```json
"backend": {
  "type": "aprsis",
  "host": "rotate.aprs2.net",
  "port": 14580,
  "passcode": "REPLACE_WITH_APRS_IS_PASSCODE",
  "filter": "b/N0CALL-4/N0CALL-7",
  "tx_enabled": true
}
```

Dire Wolf KISS TCP:

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

Xastir, YAAC, or another APRS/TNC2-style TCP server:

```json
"backend": {
  "type": "tcp_text",
  "host": "127.0.0.1",
  "port": 14580,
  "tx_enabled": true
}
```

## Sending APRS messages

Use the configured APRS Raven channel, for example `APRS og==`.

Send a direct APRS message:

```text
@N0CALL-4 message text
```

Send to an existing configured group:

```text
#APRSgroup1 message text
```

Send to an inline list without changing the configured group:

```text
#APRSgroup1 N0CALL-4, N0CALL-7 message text
```

Create or update a runtime APRS group and send the message:

```text
join #APRSgroup1 N0CALL-4, N0CALL-7 message text
```

The `join` form creates `APRSgroup1` if it does not already exist, replaces its member list with the listed stations, and sends the message to those stations.

## Group repeat mode

Each group can optionally repeat received APRS messages from one group member back out to the other group members:

```json
{
  "name": "APRSgroup1",
  "members": [ "N0CALL-4", "N0CALL-7" ],
  "repeat_member_messages": true,
  "rate_limit_seconds": 20,
  "max_members": 10
}
```

When enabled, a message received from one group member is sent to the other group members, not back to the sender. Raven applies simple duplicate suppression and rate limiting to reduce loops.
