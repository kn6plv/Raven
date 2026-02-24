import * as timers from "timers";
import * as message from "message";
import * as router from "router";
import * as nodedb from "nodedb";
import * as node from "node";
import * as channel from "channel";

const DEFAULT_INTERVAL = 60 * 60;

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
