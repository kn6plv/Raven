import * as timers from "timers";
import * as node from "node";

const SAVE_INTERVAL = 60;

let nodedb;

export function setup(config)
{
    nodedb = platform.load("nodedb") ?? {};
    timers.setInterval("nodedb", SAVE_INTERVAL);
};

export function shutdown()
{
    platform.store("nodedb", nodedb);
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
};

export function updateNode(node)
{
    saveNode(node);
};

export function updateNodeinfo(id, nodeinfo)
{
    const node = getNode(id);
    node.nodeinfo = nodeinfo;
    saveNode(node);
};

export function updatePosition(id, position)
{
    const node = getNode(id);
    node.position = position;
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
        platform.store("nodedb", nodedb);
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
