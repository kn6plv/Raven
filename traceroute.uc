import * as message from "message";
import * as router from "router";
import * as node from "node";
import * as meshtastic from "meshtastic";

meshtastic.registerProto(
    "traceroute", 70,
    {
        "1": "repeated fixed32 route",
        "2": "repeated int32 snr_towards",
        "3": "repeated fixed32 route_back",
        "4": "repeated int32 snr_back"
    }
);

const ROUTE_SIZE = 8;

export function setup(config)
{
};

export function tick()
{
};

export function process(msg)
{
    if (msg.data?.traceroute) {
        const traceroute = msg.data.traceroute;
        let routes;
        let snrs;
        if (msg.data.request_id) {
            // Back
            routes = traceroute.route_back;
            snrs = traceroute.snr_back;
        }
        else {
            // Toward
            routes = traceroute.route;
            snrs = traceroute.snr_towards;
        }

        // Fill in missing traceroute pieces (from nodes which dont support this?)
        if (msg.hop_start && msg.hop_limit && msg.hop_limit <= msg.hop_start) {
            const rdiff = msg.hop_start - msg.hop_limit - length(routes);
            for (let i = 0; i < rdiff; i++) {
                if (length(routes) < ROUTE_SIZE) {
                    push(routes, node.BROADCAST);
                }
            }
            const sdiff = length(routes) - length(snrs);
            for (let i = 0; i < sdiff; i++) {
                if (length(snrs) < ROUTE_SIZE) {
                    push(snrs, -128);
                }
            }
        }

        if (length(snrs) < ROUTE_SIZE) {
            push(snrs, 0); // snr == 0
        }
    
        if (!node.toMe(msg)) {
            if (length(routes) < ROUTE_SIZE) {
                push(routes, node.id());
            }
        }
        else {
            router.queue(
                message.createMessage(msg.from, msg.to, msg.namekey, "traceroute", traceroute, {
                    data: {
                        request_id: msg.id
                    }
                })
            );
        }
    }
};
