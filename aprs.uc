import * as socket from "socket";
import * as struct from "struct";
import * as node from "node";
import * as message from "message";
import * as channel from "channel";

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
let s = null;
let rxbuf = "";
let kiss_rxbuf = "";
let seq = 1;
let recent = {};
let last_group_tx = {};
let reconnect_after = 0;
let reconnect_delay = RECONNECT_BASE_MS;
let pending_rx = [];
export let enabled = false;

function now() { return time(); }

function closeSocket()
{
    if (s) {
        s.close();
        s = null;
    }
}

function normcall(c) { return uc(trim(c ?? "")); }
function members(g) { return g?.members ?? []; }

function memberOf(call)
{
    const out = [];
    call = normcall(call);
    for (let i = 0; i < length(cfg.groups ?? []); i++) {
        const g = cfg.groups[i];
        for (let j = 0; j < length(members(g)); j++) {
            if (normcall(members(g)[j]) === call) {
                push(out, g);
                break;
            }
        }
    }
    return out;
}

function getGroup(name)
{
    name = lc(trim(name ?? ""));
    for (let i = 0; i < length(cfg.groups ?? []); i++) {
        if (lc(cfg.groups[i].name) === name) {
            return cfg.groups[i];
        }
    }
    return null;
}

function putGroup(name, dsts)
{
    let g = getGroup(name);
    if (!g) {
        g = {
            name: name,
            members: [],
            repeat_member_messages: false,
            rate_limit_seconds: 20,
            max_members: cfg.inline_max_members ?? 10
        };
        if (!cfg.groups) {
            cfg.groups = [];
        }
        push(cfg.groups, g);
    }
    g.members = dsts;
    return g;
}

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

function makeAx25(info)
{
    const path = cfg.backend?.path ?? [];
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

function kissFrame(ax25)
{
    const port = (cfg.backend?.kiss_port ?? 0) & 15;
    return struct.pack("2B", FEND, port << 4) + kissEscape(ax25) + struct.pack("B", FEND);
}

function kissUnframe(data)
{
    const frames = [];
    for (let i = 0; i < length(data); i++) {
        const c = ord(data, i);
        if (c === FEND) {
            if (length(kiss_rxbuf) > 1) {
                push(frames, substr(kiss_rxbuf, 1));
            }
            kiss_rxbuf = "";
        }
        else if (c === FESC && i + 1 < length(data)) {
            const n = ord(data, ++i);
            kiss_rxbuf += struct.pack("B", n === TFEND ? FEND : n === TFESC ? FESC : n);
        }
        else {
            kiss_rxbuf += substr(data, i, 1);
        }
    }
    return frames;
}

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
    const key = `${g.name}:${src}:${text}:${id ?? ""}`;
    if (recent[key] && now() - recent[key] < 1800) {
        return false;
    }
    recent[key] = now();
    const minsec = g.rate_limit_seconds ?? 20;
    if (last_group_tx[g.name] && now() - last_group_tx[g.name] < minsec) {
        return false;
    }
    last_group_tx[g.name] = now();
    return true;
}

function backendSend(info)
{
    if (!s || !cfg.backend?.tx_enabled) {
        return false;
    }
    switch (cfg.backend?.type) {
        case "kiss_tcp":
            s.send(kissFrame(makeAx25(info)));
            return true;
        case "aprsis":
        case "xastir":
        case "yaac":
        case "tcp_text":
            s.send(tnc2(info));
            return true;
    }
    return false;
}

function sendOne(dst, text) { return backendSend(aprsMessage(dst, text, id3())); }

function sendList(list, text, except, max)
{
    const count = min(length(list), max ?? 10);
    for (let i = 0; i < count; i++) {
        const m = normcall(list[i]);
        if (m && m !== normcall(except)) {
            sendOne(m, text);
        }
    }
    return count > 0;
}

function sendGroup(g, text, except)
{
    if (!g) {
        return false;
    }
    return sendList(members(g), text, except, g.max_members ?? 10);
}

function resolveInboundChannel(fromcall)
{
    // Group members always land in the main APRS channel so the
    // conversation stays visible to the whole group.
    if (length(memberOf(fromcall)) > 0) {
        return cfg.channel;
    }
    // Otherwise deliver to an existing DM channel for this callsign,
    // falling back to the main APRS group channel.
    if (channelKey && fromcall) {
        const dmNamekey = `${lc(trim(fromcall))} ${channelKey}`;
        if (channelByNameKey[dmNamekey]) {
            return dmNamekey;
        }
    }
    return cfg.channel;
}

function ravenMsg(fromcall, text)
{
    const target = resolveInboundChannel(fromcall);
    const msg = message.createMessage(node.BROADCAST, node.UNKNOWN, target, "text_message", text, {
        transport: "aprs",
        originating_callsign: fromcall,
        data: { text_from: fromcall }
    });
    msg.namekey = target;
    return msg;
}

function sendAck(to, id)
{
    if (id) {
        backendSend(aprsMessage(to, `ack${id}`, null));
    }
}

function receiveLine(line)
{
    const m = parseAprsMsg(line);
    if (!m || !m.text) {
        return null;
    }
    // ACK the incoming message so the sender knows we received it
    sendAck(m.from, m.id);
    const groups = memberOf(m.from);
    for (let i = 0; i < length(groups); i++) {
        const g = groups[i];
        if (g.repeat_member_messages && canRepeat(g, m.from, m.text, m.id)) {
            sendGroup(g, `[${m.from}] ${m.text}`, m.from);
        }
    }
    return ravenMsg(m.from, m.text);
}

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
        if (!match(tok, /^[A-Za-z0-9]{1,6}(-[0-9]{1,2})?$/)) {
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

function connect()
{
    if (!enabled || s) {
        return;
    }
    // Exponential backoff: skip connect attempts until the backoff timer expires
    const t = now() * 1000;
    if (reconnect_after > 0 && t < reconnect_after) {
        return;
    }
    const b = cfg.backend ?? {};
    const type = b.type ?? "aprsis";
    const host = b.host ?? (type === "aprsis" ? "rotate.aprs2.net" : "127.0.0.1");
    const port = b.port ?? (type === "kiss_tcp" ? 8001 : 14580);
    s = socket.create(socket.AF_INET, socket.SOCK_STREAM, 0);
    if (!s || s.connect({ address: host, port: port }) === null) {
        DEBUG0("aprs: connect %s:%d failed (retry in %ds): %s\n", host, port, reconnect_delay / 1000, socket.error());
        closeSocket();
        reconnect_after = t + reconnect_delay;
        reconnect_delay = min(reconnect_delay * 2, RECONNECT_MAX_MS);
        return;
    }
    // Connected — reset backoff
    reconnect_delay = RECONNECT_BASE_MS;
    reconnect_after = 0;
    s.listen();
    if (type === "aprsis") {
        const passcode = b.passcode ?? "-1";
        s.send(`user ${cfg.callsign} pass ${passcode} vers Raven 0.1\r\n`);
        if (b.filter) {
            s.send(`# filter ${b.filter}\r\n`);
        }
    }
    DEBUG0("aprs: connected %s:%d type=%s\n", host, port, type);
}

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
    // Ensure the feed channel is registered (aprs.setup runs before channel.setup)
    channel.updateLocalChannels([ { namekey: cfg.channel } ]);
    router = config.router;
    if (!cfg.backend) {
        cfg.backend = {};
    }
    if (!cfg.backend.type) {
        cfg.backend.type = "aprsis";
    }
    connect();
};

export function shutdown() { closeSocket(); };
export function handle()
{
    connect();
    return s;
};

export function recv()
{
    // Return buffered messages from a previous read first
    if (length(pending_rx) > 0) {
        return shift(pending_rx);
    }
    const data = s.recv(2048);
    if (!data) {
        closeSocket();
        return null;
    }
    if (cfg.backend?.type === "kiss_tcp") {
        const frames = kissUnframe(data);
        for (let i = 0; i < length(frames); i++) {
            const cmd = ord(frames[i], 0) & 0x0f;
            if (cmd === 0) {
                const line = parseAx25(substr(frames[i], 1));
                const msg = receiveLine(line);
                if (msg) {
                    push(pending_rx, msg);
                }
            }
        }
    }
    else {
        rxbuf += data;
        const lines = split(rxbuf, "\n");
        rxbuf = pop(lines);
        for (let i = 0; i < length(lines); i++) {
            const msg = receiveLine(lines[i]);
            if (msg) {
                push(pending_rx, msg);
            }
        }
    }
    return length(pending_rx) > 0 ? shift(pending_rx) : null;
};

export function send(msg)
{
    if (!enabled || !msg?.data?.text_message || msg.namekey !== cfg.channel) {
        return;
    }
    const p = parseOutboundText(msg.data.text_message);
    if (p.dst) {
        sendOne(p.dst, p.text);
    }
    else if (p.dsts) {
        if (p.join) {
            putGroup(p.group, p.dsts);
        }
        sendList(p.dsts, p.text, null, cfg.inline_max_members ?? 10);
    }
    else {
        sendGroup(getGroup(p.group), p.text, null);
    }
};

export function tick()
{
    // Drain any buffered messages from a previous multi-message read
    while (length(pending_rx) > 0) {
        const msg = shift(pending_rx);
        if (msg) {
            router.queue(msg);
        }
    }
};
export function process(msg)
{
    if (!enabled || !node.fromMe(msg) || !msg?.data?.text_message) {
        return;
    }
    if (msg.namekey === cfg.channel) {
        // Message on the main APRS channel – use normal send logic
        send(msg);
        return;
    }
    // Check for DM channels sharing the APRS channel key (e.g. "kj6dzb-4 og==")
    const parts = split(msg.namekey, " ", 2);
    if (channelKey && parts[1] === channelKey) {
        const dst = normcall(parts[0]);
        if (dst) {
            // Strip @callsign prefix when it matches the DM destination
            let text = trim(msg.data.text_message ?? "");
            const m = match(text, /^@([A-Za-z0-9-]+)\s+(.+)$/s);
            if (m && normcall(m[1]) === dst) {
                text = m[2];
            }
            sendOne(dst, text);
        }
    }
};
