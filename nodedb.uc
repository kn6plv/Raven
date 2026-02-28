import * as struct from "struct";
import * as timers from "timers";
import * as node from "node";
import * as utils from "utils";

const SAVE_INTERVAL = 17 * 60; // 17 minutes
const KEEP_WINDOW = 7 * 24 * 60 * 60; // 7 days

let nodedb;

export function setup(config)
{
    nodedb = platform.load("nodedb") ?? {};
    timers.setInterval("nodedb", SAVE_INTERVAL);
};

function saveDB()
{
    const window = time() - KEEP_WINDOW;
    for (let id in nodedb) {
        if (nodedb[id].lastseen < window) {
            delete nodedb[id];
        }
    }
    platform.store("nodedb", nodedb);
}

export function shutdown()
{
    saveDB();
};

export function getNode(id, create)
{
    if (id == node.id()) {
        return {
            me: true,
            id: id,
            nodeinfo: node.getInfo()
        };
    }
    return nodedb[id] ?? (create === false ? null : { id: id });
};

function saveNode(n)
{
    if (!n.me) {
        nodedb[n.id] = n;
        n.lastseen = time();
        event.notify({ cmd: "node", id: n.id }, `node ${n.id}`);
    }
}

export function createNode(id)
{
    if (!nodedb[id]) {
        saveNode(getNode(id));
    }
    return nodedb[id];
};

export function getNodeByLongname(longname)
{
    for (let k in nodedb) {
        if (nodedb[k].nodeinfo?.long_name === longname) {
            return nodedb[k];
        }
    }
    return null;
};

export function getNodeByPublickey(public_key, create)
{
    for (let k in nodedb) {
        if (nodedb[k].nodeinfo?.mc_public_key === public_key) {
            return nodedb[k];
        }
    }
    if (create === false) {
        return null;
    }
    return createNode(struct.unpack(">I", public_key)[0]);
};

export function getNodesByPublickeyHash(publicKeyHash, wantNative)
{
    const nodes = [];
    for (let k in nodedb) {
        const n = nodedb[k];
        if (n.nodeinfo?.mc_public_key !== null && ord(n.nodeinfo.mc_public_key) === publicKeyHash) {
            const isNative = n.nodeinfo.platform === "native";
            if ((wantNative && isNative) || (!wantNative && !isNative)) {
                push(nodes, n);
            }
        }
    }
    return nodes;
};

export function updateNode(n)
{
    if (n) {
        saveNode(n);
    }
};

export function updateNodeinfo(id, nodeinfo)
{
    const n = getNode(id);
    if (!n.me) {
        delete n.nodeinforequested;
        if (!n.nodeinfo) {
            n.nodeinfo = nodeinfo;
        }
        else {
            const cnodeinfo = n.nodeinfo;
            for (let k in nodeinfo) {
                cnodeinfo[k] = nodeinfo[k];
            }
        }
        n.nodeinfo.long_name = utils.utf8validCopy(n.nodeinfo.long_name);
        n.nodeinfo.short_name = utils.utf8validCopy(n.nodeinfo.short_name);
        saveNode(n);
    }
};

export function updatePosition(id, position)
{
    const n = getNode(id);
    if (!n.position) {
        n.position = position;
    }
    else {
        const cposition = n.position;
        for (let k in position) {
            cposition[k] = position[k];
        }
    }
    saveNode(n);
};

export function updateDeviceMetrics(id, metrics)
{
    const n = getNode(id);
    const telemetry = n.telemetry ?? (n.telemetry = {});
    telemetry.device_metrics = metrics;  
    saveNode(n);
};

export function updateEnvironmentMetrics(id, metrics)
{
    const n = getNode(id);
    const telemetry = n.telemetry ?? (n.telemetry = {});
    telemetry.environment_metrics = metrics;  
    saveNode(n);
};

export function updateAirQualityMetrics(id, metrics)
{
    const n = getNode(id);
    const telemetry = n.telemetry ?? (n.telemetry = {});
    telemetry.airquality_metrics = metrics;  
    saveNode(n);
};

export function updatePath(id, path)
{
    const n = getNode(id);
    n.path = path;
    saveNode(n);
};

export function getNodes(favorite)
{
    favorite = !favorite;
    const me = node.id();
    return filter(values(nodedb), n => n.id != me && !n.favorite === favorite);
};

export function namekey(id)
{
    return `DirectMessages ${id}`
};

export function tick()
{
    if (timers.tick("nodedb")) {
        saveDB();
    }
};

export function process(msg)
{
    if (msg.hop_start && msg.hop_limit) {
        const n = getNode(msg.from);
        n.hops = msg.hop_start - msg.hop_limit;
        saveNode(n);
    }
};
