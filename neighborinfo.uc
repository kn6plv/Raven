
import * as meshtastic from "meshtastic";

meshtastic.registerProto(
    "neighbor", null,
    {
        "1": "uint32 node_id",
        "2": "float snr",
        "3": "fixed32 last_rx_time",
        "4": "uint32 node_broadcast_interval_secs"
    }
);
meshtastic.registerProto(
    "neighborinfo", 71,
    {
        "1": "uint32 node_id",
        "2": "uint32 last_sent_by_id",
        "3": "uint32 node_broadcast_interval_secs",
        "4": "repeated unpacked neighbor neighbors"
    }
);

export function setup(config)
{
};

export function tick()
{
};

export function process(msg)
{
};
