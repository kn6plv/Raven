import * as struct from "struct";
import * as timers from "timers";
import * as node from "node";

const SAVE_INTERVAL = 17 * 60; // 17 minutes
const KEEP_WINDOW = 7 * 24 * 60 * 60; // 7 days

const HW_NATIVE = 254;

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
    return nodedb[id] ?? (create === false ? null : { id: id });
};

function saveNode(node)
{
    nodedb[node.id] = node;
    node.lastseen = time();
    event.notify({ cmd: "node", id: node.id }, `node ${node.id}`);
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
        const node = nodedb[k];
        if (node.nodeinfo?.mc_public_key !== null && ord(node.nodeinfo.mc_public_key) === publicKeyHash) {
            const isNative = node.nodeinfo.hw_model === HW_NATIVE;
            if ((wantNative && isNative) || (!wantNative && !isNative)) {
                push(nodes, node);
            }
        }
    }
    return nodes;
};

export function updateNode(node)
{
    saveNode(node);
};

export function updateNodeinfo(id, nodeinfo)
{
    const node = getNode(id);
    if (!node.nodeinfo) {
        node.nodeinfo = nodeinfo;
    }
    else {
        const cnodeinfo = node.nodeinfo;
        for (let k in nodeinfo) {
            cnodeinfo[k] = nodeinfo[k];
        }
    }
    saveNode(node);
};

export function updatePosition(id, position)
{
    const node = getNode(id);
    if (!node.position) {
        node.position = position;
    }
    else {
        const cposition = node.position;
        for (let k in position) {
            cposition[k] = position[k];
        }
    }
    saveNode(node);
};

export function updateDeviceMetrics(id, metrics)
{
    const node = getNode(id);
    const telemetry = node.telemetry ?? (node.telemetry = {});
    telemetry.device_metrics = metrics;  
    saveNode(node);
};

export function updateEnvironmentMetrics(id, metrics)
{
    const node = getNode(id);
    const telemetry = node.telemetry ?? (node.telemetry = {});
    telemetry.environment_metrics = metrics;  
    saveNode(node);
};

export function updateAirQualityMetrics(id, metrics)
{
    const node = getNode(id);
    const telemetry = node.telemetry ?? (node.telemetry = {});
    telemetry.airquality_metrics = metrics;  
    saveNode(node);
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
    const node = getNode(msg.from, false);
    if (node && msg.hop_start && msg.hop_limit) {
        node.hops = msg.hop_start - msg.hop_limit;
        saveNode(node);
    }
};
