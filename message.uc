import * as math from "math";
import * as node from "node";
import * as channel from "channel";

const DEFAULT_PRIORITY = 64;
const ACK_PRIORITY = 120;

export function createMessage(to, from, namekey, type, payload, extra)
{
    const hops = node.hopLimit();
    const msg = {
        from: from ?? node.id(), // From me by default
        to: to ?? node.BROADCAST,
        namekey: channel.getChannelByNameKey(namekey)?.namekey,
        id: math.rand(),
        rx_time: time(),
        priority: DEFAULT_PRIORITY,
        hop_limit: hops,
        transport: "native",
        data: {
            [type]: payload
        }
    };
    if (extra) {
        for (let k in extra) {
            if (k === "data") {
                for (let j in extra.data) {
                    msg.data[j] = extra.data[j];
                }
            }
            else {
                msg[k] = extra[k];
            }
        }
    }
    return msg;
};

export function createAckMessage(msg, reason)
{
    return createMessage(msg.from, null, msg.namekey, "routing", { error_reason: reason ?? 0, checksum: msg.data?.checksum }, {
        priority: ACK_PRIORITY,
        data: {
            request_id: msg.id
        }
    });
};
