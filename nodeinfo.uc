import * as router from "router";
import * as message from "message";
import * as node from "node";
import * as nodedb from "nodedb";
import * as timers from "timers";
import * as channel from "channel";
import * as textmessage from "textmessage";

const HW_PRIVATE = 255;
const HW_NATIVE = 254;
const HW_MESHCORE = 253;

const DEFAULT_INTERVAL = 3 * 60 * 60;
 
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
        hw_model: HW_NATIVE,
        role: me.role,
        public_key: me.public_key,
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
        hw_model: HW_NATIVE,
        public_key: me.mc_public_key,
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
        router.queue(createAdvertMessage());
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
            mc_public_key: advert.public_key,
            is_unmessagable: advert.is_unmessagable,
            path: msg.path
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
    if (msg.flood && msg.path) {
        nodedb.updatePath(msg.from, reverse(msg.path));
    }
    if (msg.data?.returned_path) {
        nodedb.updatePath(msg.from, msg.data.returned_path);
    }
};
