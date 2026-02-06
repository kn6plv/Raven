import * as node from "node";

const favorites = {};
const zeroCostHops = {};

export function setup(config)
{
    const nodes = config.favorites?.nodes;
    if (nodes) {
        for (let i = 0; i < length(nodes); i++) {
            const hid = nodes[i];
            const id = hex(substr(hid,1));
            favorites[id] = true;
            if (!zeroCostHops[id & 255]) {
                zeroCostHops[id & 255] = [];
            }
            push(zeroCostHops[id & 255], id);
        }
    }
};

export function tick()
{
};

export function process(msg)
{
    switch (node.getInfo().role) {
        case node.ROLE_ROUTER:
        case node.ROLE_ROUTER_LATE:
        case node.CLIENT_BASE:
            if (msg.hop_limit < msg.hop_start && zeroCostHops[msg.relay_node]) {
                const relays = zeroCostHops[msg.relay_node];
                for (let i = 0; i < length(relays); i++) {
                    const role = nodedb.getNode(relays[i]).role;
                    if (role === node.ROLE_ROUTER || role === node.ROLE_ROUTER_LATE) {
                        msg.hop_limit++;
                        break;
                    }
                }
            }
            break;
        default:
            break;
    }
};
