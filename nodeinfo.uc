import * as router from "router";
import * as message from "message";
import * as node from "node";
import * as nodedb from "nodedb";
import * as timers from "timers";
import * as meshtastic from "meshtastic";
import * as channel from "channel";
import * as textmessage from "textmessage";
import * as crypto from "crypto.crypto";

const PRIVATE_HW = 255;
const RAVEN_HW = 254;
const MESHCORE_HW = 253;
const DEFAULT_INTERVAL = 3 * 60 * 60;
 
meshtastic.registerProto(
    "nodeinfo", 4,
    {
        "1": "string id",
        "2": "string long_name",
        "3": "string short_name",
        "4": "bytes macaddr",
        "5": "enum hw_model",
        "6": "bool is_licensed",
        "7": "enum role",
        "8": "bytes public_key",
        "9": "bool is_unmessagable"
    }
);

export function setup(config)
{
    timers.setInterval("nodeinfo", 60, config.nodeinfo?.interval ?? DEFAULT_INTERVAL);
};

function createNodeinfoMessage(to, namekey, extra)
{
    const me = node.getInfo();
    return message.createMessage(to, null, namekey, "nodeinfo", {
        id: sprintf("!%08x", me.id),
        long_name: me.long_name,
        short_name: me.short_name,
        macaddr: me.macaddr,
        hw_model: RAVEN_HW,
        role: me.role,
        public_key: crypto.pKeyToString(me.public_key),
        is_unmessagable: !textmessage.isMessagable()
    }, extra);
}

function createAdvertMessage()
{
    const me = node.getInfo();
    const loc = node.getLocation(true);
    return message.createMessage(null, null, null, "advert", {
        role: me.role,
        name: me.long_name,
        public_key: crypto.pKeyToString(me.public_key),
        position: {
            latitude_i: int(loc.lat * 10000000),
            longitude_i: int(loc.lon * 10000000)
        }
    });
}

export function tick()
{
    if (timers.tick("nodeinfo")) {
        const telemetry = channel.getTelemetryChannels();
        for (let i = 0; i < length(telemetry); i++) {
            router.queue(createNodeinfoMessage(null, telemetry[i].namekey, null));
        }
        // Not yet supported
        //router.queue(createAdvertMessage());
    }
};

export function process(msg)
{
    if (msg.data?.nodeinfo) {
        nodedb.updateNodeinfo(msg.from, msg.data.nodeinfo);
        if (node.toMe(msg) && msg.data.want_response) {
            router.queue(createNodeinfoMessage(msg.from, msg.namekey, {
                data: {
                    reply_id: msg.id
                }
            }));
        }
    }
    else if (msg.data?.advert) {
        const advert = msg.data.advert;
        nodedb.updateNodeinfo(msg.from, {
            id: sprintf("!%08x", msg.from),
            long_name: advert.name,
            hw_model: advert.hw_model,
            role: advert.role,
            public_key: advert.public_key,
            is_unmessagable: advert.is_unmessagable
        });
        if (advert.position) {
            nodedb.updatePosition(msg.from, advert.position);
        }
    }
    else if (!nodedb.getNode(msg.from, false) && !node.fromMe(msg)) {
        nodedb.createNode(msg.from);
        router.queue(createNodeinfoMessage(msg.from, msg.namekey, {
            data: {
                want_response: true
            }
        }));
    }
};
