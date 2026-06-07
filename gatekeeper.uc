import * as node from "node";
import * as nodedb from "nodedb";

const US_CALLSIGN_RE = /^[A-Z]{1,2}[0-9][A-Z]{1,3}$/;

let strict_enabled = false;
let gateway_callsign = null;
let allowed = {};
let allowed_count = 0;

function norm(s)
{
    if (!s) {
        return null;
    }
    s = uc(trim(`${s}`));
    const m = match(s, /([A-Z]{1,2}[0-9][A-Z]{1,3})/);
    return m ? m[1] : null;
}

function loadAllowed(list)
{
    allowed = {};
    allowed_count = 0;
    if (type(list) !== "array") {
        return;
    }
    for (let i = 0; i < length(list); i++) {
        const cs = norm(list[i]);
        if (cs && !allowed[cs]) {
            allowed[cs] = true;
            allowed_count++;
        }
    }
}

export function setup(config)
{
    let raw = config.strict_gatekeeper ?? {};
    // Accept both object and array-of-one-object config formats
    if (type(raw) === "array") {
        raw = raw[0] ?? {};
    }
    const gk = raw;
    strict_enabled = !!gk.enabled;
    gateway_callsign = norm(gk.gateway_callsign ?? config.callsign);
    loadAllowed(gk.allowed_callsigns ?? config.allowed_callsigns);
    if (strict_enabled && !gateway_callsign) {
        DEBUG0("gatekeeper: strict mode enabled but no valid gateway callsign configured\n");
    }
};

export function isEnabled()
{
    return strict_enabled;
};

export function gatewayCallsign()
{
    return gateway_callsign;
};

export function senderCallsignFromNodeId(id)
{
    const info = nodedb.getNode(id, false)?.nodeinfo;
    return norm(info?.long_name) ?? norm(info?.short_name) ?? null;
};

export function senderCallsignFromTextName(name)
{
    return norm(name);
};

export function allowSenderCallsign(callsign)
{
    callsign = norm(callsign);
    if (!strict_enabled) {
        return callsign;
    }
    if (!gateway_callsign) {
        DEBUG0("gatekeeper: drop, no valid gateway callsign\n");
        return null;
    }
    if (!callsign || !match(callsign, US_CALLSIGN_RE)) {
        DEBUG1("gatekeeper: drop, invalid sender callsign\n");
        return null;
    }
    if (allowed_count > 0 && !allowed[callsign]) {
        DEBUG1("gatekeeper: drop, sender callsign not whitelisted\n");
        return null;
    }
    return callsign;
};

export function allowSenderNode(id)
{
    return allowSenderCallsign(senderCallsignFromNodeId(id));
};

export function annotateViaGateway(msg, sender_callsign)
{
    if (!strict_enabled) {
        return msg;
    }
    sender_callsign = allowSenderCallsign(sender_callsign);
    if (!sender_callsign) {
        return null;
    }
    if (!msg?.data?.text_message) {
        DEBUG1("gatekeeper: drop, bridged packet is not a text message\n");
        return null;
    }
    msg.from = node.id();
    msg.originating_callsign = gateway_callsign;
    msg.data.text_from = sender_callsign;
    msg.data.text_message = `[${sender_callsign} via ${gateway_callsign}] ${msg.data.text_message}`;
    return msg;
};

export function filterInboundBridge(msg)
{
    if (!strict_enabled || !msg) {
        return msg;
    }
    if (msg.encrypted) {
        DEBUG0("gatekeeper: drop encrypted bridged packet\n");
        return null;
    }
    if (!msg.data?.text_message) {
        DEBUG1("gatekeeper: drop non-text bridged packet\n");
        return null;
    }
    if (msg.from === node.id() && msg.originating_callsign === gateway_callsign) {
        return msg;
    }
    const sender = msg.data?.text_from ? allowSenderCallsign(msg.data.text_from) : allowSenderNode(msg.from);
    if (!sender) {
        return null;
    }
    return annotateViaGateway(msg, sender);
};

export function tick()
{
};

export function process(msg)
{
};
