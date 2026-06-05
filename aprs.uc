import * as socket from "socket";
import * as struct from "struct";
import * as node from "node";
import * as message from "message";
import * as channel from "channel";
import * as groups from "groups";

const FEND  = 0xc0;
const FESC  = 0xdb;
const TFEND = 0xdc;
const TFESC = 0xdd;
const CTRL_UI = 0x03;
const PID_NO_L3 = 0xf0;
const MAX_APRS_TEXT = 67;
const DEST = "APZRVN";

const RECONNECT_BASE_MS = 5000;
const RECONNECT_MAX_MS = 300000;

const DEFAULT_CHANNEL_NAME = "APRS-IS-Feed";
const DEFAULT_CHANNEL_KEY = "og==";

let cfg = null;
let router = null;
let channelKey = null;
let seq = 1;
export let enabled = false;

// --- Multi-backend registry ---
// Each backend instance: { config, socket, rxbuf, kiss_rxbuf, reconnect_after, reconnect_delay, pending_rx }
const backends = {};
let defaultBackendName = null;

// Channel → backend name mapping (namekey → backendName)
const channelBackendMap = {};

function backendTypeLabel(btype)
{
    switch (btype ?? "aprsis") {
        case "aprsis":   return "aprs-is";
        case "kiss_tcp": return "aprs-kiss";
        case "tcp_text":
        case "xastir":
        case "yaac":     return "aprs-tnc";
        default:         return "aprs";
    }
};

function makeBackendDisplayName(name, bcfg)
{
    return `${backendTypeLabel(bcfg?.type)}[${name}]`;
};

function createBackendInstance(name, bcfg)
{
    return {
        name: name,
        displayName: makeBackendDisplayName(name, bcfg),
        config: bcfg,
        socket: null,
        rxbuf: "",
        kiss_rxbuf: "",
        reconnect_after: 0,
        reconnect_delay: RECONNECT_BASE_MS,
        pending_rx: []
    };
};

function closeBackendSocket(inst)
{
    if (inst.socket) {
        inst.socket.close();
        inst.socket = null;
    }
}

// --- Utility functions ---

function now() { return time(); }

// Delegate to groups.uc for group management
function normcall(c) { return groups.normcall(c); }
function members(g) { return g?.members ?? []; }

// --- AX.25 / KISS helpers (unchanged) ---

function callsignSsid(call)
{
    const p = split(normcall(call), "-", 2);
    return { call: substr(p[0], 0, 6), ssid: int(p[1] ?? 0) & 15 };
}

function ax25Addr(call, last)
{
    const c = callsignSsid(call);
    let out = "";
    for (let i = 0; i < 6; i++) {
        const ch = i < length(c.call) ? ord(c.call, i) : 32;
        out += struct.pack("B", (ch & 0x7f) << 1);
    }
    out += struct.pack("B", 0x60 | (c.ssid << 1) | (last ? 1 : 0));
    return out;
}

function ax25Unaddr(frame, off)
{
    let call = "";
    for (let i = 0; i < 6; i++) {
        const c = ord(frame, off + i) >> 1;
        if (c !== 32) {
            call += chr(c);
        }
    }
    const ssid = (ord(frame, off + 6) >> 1) & 15;
    return ssid ? `${call}-${ssid}` : call;
}

function makeAx25(inst, info)
{
    const path = inst.config?.path ?? [];
    let out = ax25Addr(DEST, false) + ax25Addr(cfg.callsign, length(path) === 0);
    for (let i = 0; i < length(path); i++) {
        out += ax25Addr(path[i], i === length(path) - 1);
    }
    return out + struct.pack("2B", CTRL_UI, PID_NO_L3) + info;
}

function parseAx25(frame)
{
    if (length(frame) < 16) {
        return null;
    }
    const from = ax25Unaddr(frame, 7);
    let off = 14;
    while (off + 1 < length(frame) && !(ord(frame, off - 1) & 1)) {
        off += 7;
    }
    if (off + 2 >= length(frame)) {
        return null;
    }
    if (ord(frame, off) !== CTRL_UI || ord(frame, off + 1) !== PID_NO_L3) {
        return null;
    }
    return `${from}>${DEST}:${substr(frame, off + 2)}`;
}

function kissEscape(data)
{
    let out = "";
    for (let i = 0; i < length(data); i++) {
        const c = ord(data, i);
        if (c === FEND) {
            out += struct.pack("2B", FESC, TFEND);
        }
        else if (c === FESC) {
            out += struct.pack("2B", FESC, TFESC);
        }
        else {
            out += substr(data, i, 1);
        }
    }
    return out;
}

function kissFrame(inst, ax25)
{
    const port = (inst.config?.kiss_port ?? 0) & 15;
    return struct.pack("2B", FEND, port << 4) + kissEscape(ax25) + struct.pack("B", FEND);
}

function kissUnframe(inst, data)
{
    const frames = [];
    for (let i = 0; i < length(data); i++) {
        const c = ord(data, i);
        if (c === FEND) {
            if (length(inst.kiss_rxbuf) > 1) {
                push(frames, substr(inst.kiss_rxbuf, 1));
            }
            inst.kiss_rxbuf = "";
        }
        else if (c === FESC && i + 1 < length(data)) {
            const n = ord(data, ++i);
            inst.kiss_rxbuf += struct.pack("B", n === TFEND ? FEND : n === TFESC ? FESC : n);
        }
        else {
            inst.kiss_rxbuf += substr(data, i, 1);
        }
    }
    return frames;
}

// --- Message formatting ---

function aprsMessage(dst, text, id)
{
    dst = sprintf("%-9s", substr(normcall(dst), 0, 9));
    text = substr(text, 0, MAX_APRS_TEXT);
    return `:${dst}:${text}${id ? "{" + id : ""}`;
}

function tnc2(info) { return `${cfg.callsign}>${DEST},TCPIP*:${info}\r\n`; }

function parseTnc2(line)
{
    line = trim(line ?? "");
    const m = match(line, /^([^>]+)>[^:]+:(.*)$/);
    return m ? { from: normcall(m[1]), info: m[2] } : null;
}

function parseAprsMsg(line)
{
    const p = parseTnc2(line);
    if (!p || substr(p.info, 0, 1) !== ":") {
        return null;
    }
    const to = trim(substr(p.info, 1, 9));
    if (normcall(to) !== normcall(cfg.callsign)) {
        return null;
    }
    const body = substr(p.info, 11);
    const ack = match(body, /^ack([A-Za-z0-9]+)$/);
    if (ack) {
        return { from: p.from, ack: ack[1] };
    }
    const mid = match(body, /^(.*)\{([A-Za-z0-9]+)\}?[A-Za-z0-9]*$/);
    return { from: p.from, text: mid ? mid[1] : body, id: mid ? mid[2] : null };
}

function id3()
{
    seq = (seq % 999) + 1;
    return sprintf("%03d", seq);
}

function canRepeat(g, src, text, id)
{
    return groups.canRepeat(g, src, text, id);
}

// --- Backend resolution ---

// Resolve which backend name to use for a given namekey
function resolveBackendName(namekey)
{
    if (namekey && channelBackendMap[namekey]) {
        return channelBackendMap[namekey];
    }
    return defaultBackendName;
}

// Resolve which backend name to use for a group (group.backend > channel backend > default)
function resolveGroupBackendName(g, namekey)
{
    if (g?.backend && backends[g.backend]) {
        return g.backend;
    }
    return resolveBackendName(namekey);
}

function getBackendInstance(name)
{
    return backends[name ?? defaultBackendName];
}

// --- Multi-backend send ---

function backendSendTo(inst, info)
{
    if (!inst?.socket || !inst.config?.tx_enabled) {
        return false;
    }
    switch (inst.config?.type) {
        case "kiss_tcp":
            inst.socket.send(kissFrame(inst, makeAx25(inst, info)));
            return true;
        case "aprsis":
        case "xastir":
        case "yaac":
        case "tcp_text":
            inst.socket.send(tnc2(info));
            return true;
    }
    return false;
}

function backendSend(backendName, info)
{
    const inst = getBackendInstance(backendName);
    return backendSendTo(inst, info);
}

function sendOne(backendName, dst, text) { return backendSend(backendName, aprsMessage(dst, text, id3())); }

function sendList(backendName, list, text, except, max)
{
    const count = min(length(list), max ?? 10);
    for (let i = 0; i < count; i++) {
        const m = normcall(list[i]);
        if (m && m !== normcall(except)) {
            sendOne(backendName, m, text);
        }
    }
    return count > 0;
}

function sendGroup(g, text, except, namekey)
{
    if (!g) {
        return false;
    }
    const bn = resolveGroupBackendName(g, namekey);
    return sendList(bn, members(g), text, except, g.max_members ?? 10);
}

// --- Inbound channel resolution ---
// Each backend can have a default channel; group members always land on the main APRS channel.

function resolveInboundChannel(fromcall, backendName)
{
    // Check if sender is in any APRS group with a dedicated channel
    const memberGroups = groups.memberOf(fromcall);
    if (length(memberGroups) > 0) {
        for (let i = 0; i < length(memberGroups); i++) {
            const g = memberGroups[i];
            const baseName = substr(g.name, 0, 1) === "#" || substr(g.name, 0, 1) === "%"
                ? substr(g.name, 1) : g.name;
            // Check for %GroupName og== channel (APRS groups are AREDN-only)
            const arednNamekey = `%${baseName} og==`;
            if (channel.getLocalChannelByNameKey(arednNamekey)) {
                return arednNamekey;
            }
            // Check for #GroupName channel
            const hashNamekey = `#${baseName}`;
            const allLocal = channel.getAllLocalChannels();
            for (let j = 0; j < length(allLocal); j++) {
                if (index(allLocal[j].namekey, hashNamekey) === 0) {
                    return allLocal[j].namekey;
                }
            }
        }
        // Fall back to main APRS channel for group members without a dedicated channel
        return cfg.channel;
    }
    // Find the first channel bound to this backend
    for (let nk in channelBackendMap) {
        if (channelBackendMap[nk] === backendName) {
            // Check for DM channel
            if (channelKey && fromcall) {
                const dmNamekey = `${lc(trim(fromcall))} ${channelKey}`;
                if (channelByNameKey[dmNamekey]) {
                    return dmNamekey;
                }
            }
            return nk;
        }
    }
    // Fallback: deliver to an existing DM channel or the main APRS channel
    if (channelKey && fromcall) {
        const dmNamekey = `${lc(trim(fromcall))} ${channelKey}`;
        if (channelByNameKey[dmNamekey]) {
            return dmNamekey;
        }
    }
    return cfg.channel;
}

function ravenMsg(fromcall, text, backendName)
{
    const target = resolveInboundChannel(fromcall, backendName);
    const msg = message.createMessage(node.BROADCAST, node.UNKNOWN, target, "text_message", text, {
        transport: "aprs",
        originating_callsign: fromcall,
        data: { text_from: fromcall }
    });
    msg.namekey = target;
    return msg;
}

function sendAck(backendName, to, id)
{
    if (id) {
        backendSend(backendName, aprsMessage(to, `ack${id}`, null));
    }
}

function receiveLine(line, backendName)
{
    const m = parseAprsMsg(line);
    if (!m || !m.text) {
        return null;
    }
    sendAck(backendName, m.from, m.id);
    const mgroups = groups.memberOf(m.from);
    for (let i = 0; i < length(mgroups); i++) {
        const g = mgroups[i];
        if (g.repeat_member_messages && canRepeat(g, m.from, m.text, m.id)) {
            sendGroup(g, `[${m.from}] ${m.text}`, m.from, null);
        }
    }
    return ravenMsg(m.from, m.text, backendName);
}

// --- Outbound text parsing ---

function joinFrom(parts, start)
{
    let out = "";
    for (let i = start; i < length(parts); i++) {
        if (parts[i] !== "") {
            out += `${out ? " " : ""}${parts[i]}`;
        }
    }
    return out;
}

function parseInlineRecipients(rest)
{
    const parts = split(trim(rest ?? ""), " ");
    const dsts = [];
    let i = 0;
    for (; i < length(parts); i++) {
        let tok = replace(trim(parts[i]), /,$/, "");
        if (!tok) {
            continue;
        }
        if (!(match(tok, /^[A-Za-z0-9]{2,6}(-[0-9]{1,2})?$/) && match(tok, /[0-9]/))) {
            break;
        }
        push(dsts, normcall(tok));
    }
    const text = joinFrom(parts, i);
    return length(dsts) && text ? { dsts: dsts, text: text } : null;
}

function parseOutboundText(text)
{
    text = trim(text ?? "");
    let m = match(text, /^@([A-Za-z0-9-]+)\s+(.+)$/);
    if (m) {
        return { dst: normcall(m[1]), text: m[2] };
    }
    // join #groupname [backend=NAME] CALL1 CALL2 message text
    m = match(text, /^join\s+#([^ ]+)\s+backend=([^ ]+)\s+(.+)$/i);
    if (m) {
        const inline = parseInlineRecipients(m[3]);
        if (inline) {
            inline.join = true;
            inline.group = m[1];
            inline.backend = m[2];
            return inline;
        }
    }
    m = match(text, /^join\s+#([^ ]+)\s+(.+)$/i);
    if (m) {
        const inline = parseInlineRecipients(m[2]);
        if (inline) {
            inline.join = true;
            inline.group = m[1];
            return inline;
        }
    }
    m = match(text, /^#([^ ]+)\s+(.+)$/);
    if (m) {
        const inline = parseInlineRecipients(m[2]);
        if (inline) {
            inline.group = m[1];
            return inline;
        }
        return { group: m[1], text: m[2] };
    }
    return { group: cfg.default_group, text: text };
}

// --- Per-backend connect / recv ---

function connectBackend(name, inst)
{
    if (!enabled || inst.socket) {
        return;
    }
    const t = now() * 1000;
    if (inst.reconnect_after > 0 && t < inst.reconnect_after) {
        return;
    }
    const b = inst.config ?? {};
    const btype = b.type ?? "aprsis";
    const host = b.host ?? (btype === "aprsis" ? "rotate.aprs2.net" : "127.0.0.1");
    const port = b.port ?? (btype === "kiss_tcp" ? 8001 : 14580);
    inst.socket = socket.create(socket.AF_INET, socket.SOCK_STREAM, 0);
    if (!inst.socket || inst.socket.connect({ address: host, port: port }) === null) {
        DEBUG0("%s: connect %s:%d failed (retry in %ds): %s\n", inst.displayName, host, port, inst.reconnect_delay / 1000, socket.error());
        closeBackendSocket(inst);
        inst.reconnect_after = t + inst.reconnect_delay;
        inst.reconnect_delay = min(inst.reconnect_delay * 2, RECONNECT_MAX_MS);
        return;
    }
    inst.reconnect_delay = RECONNECT_BASE_MS;
    inst.reconnect_after = 0;
    inst.socket.listen();
    if (btype === "aprsis") {
        const passcode = b.passcode ?? "-1";
        inst.socket.send(`user ${cfg.callsign} pass ${passcode} vers Raven 0.1\r\n`);
        if (b.filter) {
            inst.socket.send(`# filter ${b.filter}\r\n`);
        }
    }
    DEBUG0("%s: connected %s:%d\n", inst.displayName, host, port);
}

function recvFromBackend(inst)
{
    if (length(inst.pending_rx) > 0) {
        return shift(inst.pending_rx);
    }
    const data = inst.socket.recv(2048);
    if (!data) {
        closeBackendSocket(inst);
        return null;
    }
    if (inst.config?.type === "kiss_tcp") {
        const frames = kissUnframe(inst, data);
        for (let i = 0; i < length(frames); i++) {
            const cmd = ord(frames[i], 0) & 0x0f;
            if (cmd === 0) {
                const line = parseAx25(substr(frames[i], 1));
                const msg = receiveLine(line, inst.name);
                if (msg) {
                    push(inst.pending_rx, msg);
                }
            }
        }
    }
    else {
        inst.rxbuf += data;
        const lines = split(inst.rxbuf, "\n");
        inst.rxbuf = pop(lines);
        for (let i = 0; i < length(lines); i++) {
            const msg = receiveLine(lines[i], inst.name);
            if (msg) {
                push(inst.pending_rx, msg);
            }
        }
    }
    return length(inst.pending_rx) > 0 ? shift(inst.pending_rx) : null;
}

// --- Public API ---

export function setup(config)
{
    cfg = config.aprs;
    if (!cfg?.enabled) {
        return;
    }
    enabled = true;
    cfg.callsign = normcall(cfg.callsign ?? config.callsign);
    cfg.channel = cfg.channel ?? `${DEFAULT_CHANNEL_NAME} ${DEFAULT_CHANNEL_KEY}`;
    channelKey = split(cfg.channel, " ", 2)[1];
    channel.updateLocalChannels([ { namekey: cfg.channel } ]);
    router = config.router;

    // --- Initialize backends ---
    // Backward compat: single "backend" → backends.default
    let backendsCfg = cfg.backends;
    if (!backendsCfg) {
        backendsCfg = {};
        if (cfg.backend) {
            backendsCfg["default"] = cfg.backend;
        }
        else {
            backendsCfg["default"] = { type: "aprsis" };
        }
    }
    // Pick the first backend as default
    let firstName = null;
    for (let name in backendsCfg) {
        backends[name] = createBackendInstance(name, backendsCfg[name]);
        if (!firstName) {
            firstName = name;
        }
    }
    defaultBackendName = firstName;

    // Build channel→backend map from config channels
    if (config.channels) {
        for (let i = 0; i < length(config.channels); i++) {
            const ch = config.channels[i];
            if (ch.backend && backends[ch.backend]) {
                channelBackendMap[ch.namekey] = ch.backend;
            }
        }
    }
    // Also bind the main APRS channel to default if not already bound
    if (!channelBackendMap[cfg.channel]) {
        channelBackendMap[cfg.channel] = defaultBackendName;
    }

    // Connect all backends
    for (let name in backends) {
        connectBackend(name, backends[name]);
    }
};

export function shutdown()
{
    for (let name in backends) {
        closeBackendSocket(backends[name]);
    }
};

// Returns array of { socket, name, displayName } for router to poll
export function handle()
{
    const handles = [];
    for (let name in backends) {
        const inst = backends[name];
        connectBackend(name, inst);
        if (inst.socket) {
            push(handles, { socket: inst.socket, name: name, displayName: inst.displayName });
        }
    }
    return length(handles) > 0 ? handles : null;
};

// Receive from a specific backend by name
export function recv(backendName)
{
    const inst = backends[backendName];
    if (!inst) {
        return null;
    }
    return recvFromBackend(inst);
};

export function send(msg)
{
    if (!enabled || !msg?.data?.text_message) {
        return;
    }
    // Only process messages on channels we know about
    const bn = resolveBackendName(msg.namekey);
    if (msg.namekey !== cfg.channel && !channelBackendMap[msg.namekey]) {
        // Check if it's a DM channel with our key
        const parts = split(msg.namekey, " ", 2);
        if (!(channelKey && parts[1] === channelKey)) {
            return;
        }
    }
    const p = parseOutboundText(msg.data.text_message);
    if (p.dst) {
        sendOne(bn, p.dst, p.text);
    }
    else if (p.dsts) {
        if (p.join) {
            groups.putGroup(p.group, p.dsts, { backend: p.backend });
        }
        const g = groups.getGroup(p.group);
        const gbn = resolveGroupBackendName(g, msg.namekey);
        sendList(gbn, p.dsts, p.text, null, cfg.inline_max_members ?? 10);
    }
    else {
        // If channel corresponds to a group, use it; otherwise fall back to default_group
        const chanName = split(msg.namekey, " ")[0];
        let g = groups.getGroup(chanName);
        if (!g) {
            g = groups.getGroup(p.group);
        }
        sendGroup(g, p.text, null, msg.namekey);
    }
};

export function tick()
{
    for (let name in backends) {
        const inst = backends[name];
        while (length(inst.pending_rx) > 0) {
            const msg = shift(inst.pending_rx);
            if (msg) {
                router.queue(msg);
            }
        }
    }
};

export function process(msg)
{
    if (!enabled || !node.fromMe(msg) || !msg?.data?.text_message) {
        return;
    }
    if (msg.namekey === cfg.channel || channelBackendMap[msg.namekey]) {
        send(msg);
        return;
    }
    // Check for DM channels sharing the APRS channel key
    const parts = split(msg.namekey, " ", 2);
    if (channelKey && parts[1] === channelKey) {
        const dst = normcall(parts[0]);
        if (dst) {
            let text = trim(msg.data.text_message ?? "");
            const m = match(text, /^@([A-Za-z0-9-]+)\s+(.+)$/s);
            if (m && normcall(m[1]) === dst) {
                text = m[2];
            }
            const bn = resolveBackendName(msg.namekey);
            sendOne(bn, dst, text);
        }
    }
};

// Return list of backend info for UI: [ { key, label }, ... ]
export function getBackendNames()
{
    const out = [];
    for (let name in backends) {
        push(out, { key: name, label: backends[name].displayName });
    }
    return out;
};

// Update channel→backend binding at runtime
//   backendName = "name"  → bind to specific backend
//   backendName = ""      → explicitly clear binding (UI cleared it)
//   backendName = null    → not specified, bind to default if not already bound
export function updateChannelBackend(namekey, backendName)
{
    if (backendName && backends[backendName]) {
        channelBackendMap[namekey] = backendName;
    }
    else if (backendName === "") {
        // Explicitly cleared by UI
        delete channelBackendMap[namekey];
    }
    else if (!channelBackendMap[namekey] && defaultBackendName) {
        // Not specified (null) — bind to default
        channelBackendMap[namekey] = defaultBackendName;
    }
};

// Send a message to all members of an APRS group (called from commands.uc /join)
export function sendToGroup(g, text, namekey)
{
    if (!enabled || !g) {
        return;
    }
    const bn = resolveGroupBackendName(g, namekey);
    const mems = g.members ?? [];
    for (let i = 0; i < length(mems); i++) {
        const m = normcall(mems[i]);
        if (m) {
            sendOne(bn, m, text);
        }
    }
};
