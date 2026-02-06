import * as timers from "timers";
import * as message from "message";
import * as router from "router";
import * as nodedb from "nodedb";
import * as node from "node";
import * as channel from "channel";
import * as meshtastic from "meshtastic";

const DEFAULT_INTERVAL = 60 * 60;

meshtastic.registerProto(
    "position", 3,
    {
        "1": "sfixed32 latitude_i",
        "2": "sfixed32 longitude_i",
        "3": "int32 altitude",
        "4": "fixed32 time",
        "5": "enum location_source",
        "6": "enum altitude_source",
        "7": "fixed32 timestamp",
        "8": "int32 timestamp_millis_adjust",
        "9": "sint32 altitude_hae",
        "10": "sint32 altitude_geoidal_separation",
        "11": "uint32 PDOP",
        "12": "uint32 HDOP",
        "13": "uint32 VDOP",
        "14": "uint32 gps_accuracy",
        "15": "uint32 ground_speed",
        "16": "uint32 ground_track",
        "17": "uint32 fix_quality",
        "18": "uint32 fix_type",
        "19": "uint32 sats_in_view",
        "20": "uint32 sensor_id",
        "21": "uint32 next_update",
        "22": "uint32 seq_number",
        "23": "uint32 precision_bits"
    }
);

export function setup(config)
{
    if (node.getLocation()) {
        timers.setInterval("position", 60, config.position?.interval ?? DEFAULT_INTERVAL);
    }
};

function position(precise)
{
    const loc = node.getLocation(precise);
    return {
        latitude_i: int(loc.lat * 10000000),
        longitude_i: int(loc.lon * 10000000),
        altitude: int(loc.alt),
        time: time(),
        location_source: loc.source,
        precision_bits: loc.precision
    };
}

export function tick()
{
    if (timers.tick("position")) {
        const telemetry = channel.getTelemetryChannels();
        for (let i = 0; i < length(telemetry); i++) {
            router.queue(message.createMessage(null, null, telemetry[i].namekey, "position", position(false)));
        }
    }
};

export function process(msg)
{
    if (msg.data?.position && node.forMe(msg)) {
        nodedb.updatePosition(msg.from, msg.data.position);
        if (node.toMe(msg) && msg.data.want_response) {
            router.queue(
                message.createMessage(msg.from, msg.to, msg.namekey, "position", position(false), {
                    data: {
                        reply_id: msg.id
                    }
                })
            );
        }
    }
};
