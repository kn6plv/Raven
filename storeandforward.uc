import * as meshtastic from "meshtastic";

meshtastic.registerProto(
    "statistics", null,
    {
        "1": "uint32 messages_total",
        "2": "uint32 messages_saved",
        "3": "uint32 messages_max",
        "4": "uint32 up_time",
        "5": "uint32 requests",
        "6": "uint32 requests_history",
        "7": "bool heartbeat",
        "8": "uint32 return_max",
        "9": "uint32 return_window"
    }
);
meshtastic.registerProto(
    "history", null,
    {
        "1": "uint32 history_messages",
        "2": "uint32 window",
        "3": "uint32 last_request"
    }
);
meshtastic.registerProto(
    "heartbeat", null,
    {
        "1": "uint32 period",
        "2": "uint32 secondary"
    }
);
meshtastic.registerProto(
    "storeandforward", 65,
    {
        "1": "enum rr",
        "2": "proto statistics stats",
        "3": "proto history history",
        "4": "proto heartbeat heartbeat",
        "5": "bytes text"
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
