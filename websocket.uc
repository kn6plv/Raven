import * as socket from "socket";
import * as struct from "struct";
import * as timers from "timers";
import * as crypto from "crypto.crypto";

const PORT = 4404;

const PING_INTERVAL = 30;

const MAGIC_KEY = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const S_HTTPHEADER = 0;
const S_MSGRECV = 1;

const OP_TEXT = 1;
const OP_BINARY = 2;
const OP_PING = 9;
const OP_PONG = 10;
const FIN = 128;

let s = null;
const allhandles = [];
const states = {};
let clientid = 1;

export function setup(config)
{
    if (!config.websocket) {
        return;
    }
    s = socket.create(socket.AF_INET, socket.SOCK_STREAM, 0);
    s.setopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);
    s.bind({
        port: config.websocket.port ?? PORT
    });
    s.listen();
    push(allhandles, s);
    timers.setInterval("websocket", PING_INTERVAL);
};

export function handles()
{
    return allhandles;
};

function close(handle)
{
    delete states[handle];
    const i = index(allhandles, handle);
    if (i > 0) {
        splice(allhandles, i, 1);
    }
    handle.close();
}

function accept()
{
    const ns = s.accept();
    if (ns) {
        push(allhandles, ns);
        states[ns] = {
            id: clientid++,
            state: S_HTTPHEADER,
            s: ns,
            incoming: "",
            msg: "",
            opcode: 0
        };
    }
    return [];
}

function decode(state)
{
    const messages = [];
    for (;;) {
        if (length(state.incoming) < 6) {
            break;
        }
        else {
            let mask;
            let off;
            const opcode = ord(state.incoming, 0);
            let len = ord(state.incoming, 1) & 127;
            if (len === 126) {
                if (length(state.incoming) >= 8) {
                    len = struct.unpack(">H", state.incoming, 2)[0];
                    mask = struct.unpack("<I", state.incoming, 4)[0];
                    mask = (mask << 32) | mask;
                    off = 8;
                }
                else {
                    len = -1;
                }
            }
            else if (len === 127) {
                if (length(state.incoming) >= 14) {
                    len = struct.unpack(">Q", state.incoming, 2)[0];
                    mask = struct.unpack("<I", state.incoming, 10)[0];
                    mask = (mask << 32) | mask;
                    off = 14;
                }
                else {
                    len = -1;
                }
            }
            else {
                mask = struct.unpack("<I", state.incoming, 2)[0];
                mask = (mask << 32) | mask;
                off = 6;
            }
            if (len >= 0 && off + len <= length(state.incoming)) {
                const buf = struct.buffer(substr(state.incoming, off, len));
                const rlen = int(len / 8);
                for (let i = 0; i < rlen; i++) {
                    const v = buf.get("<Q") ^ mask;
                    buf.pos(buf.pos() - 8);
                    buf.put("<Q", v);
                }
                for (let i = rlen * 8; i < len; i++) {
                    const v = buf.get("B") ^ ((mask >> (8 * (i & 3))) & 255);
                    buf.pos(buf.pos() - 1);
                    buf.put("B", v);
                }
                state.msg += buf.pull();
                state.incoming = substr(state.incoming, off + len);
                if (opcode & 15) {
                    state.opcode = opcode & 15;
                }
                if (opcode & 128) {
                    switch (state.opcode) {
                        case OP_TEXT:
                            push(messages, { text: state.msg, socket: state.id });
                            break;
                        case OP_BINARY:
                            push(messages, { binary: state.msg, socket: state.id });
                            break;
                        case OP_PING:
                            const reply = substr(state.msg, 0, 125);
                            state.s.send(struct.pack("2B", FIN | OP_PONG, length(reply)) + reply);
                            break;
                        default:
                            break;
                    }
                    state.opcode = 0;
                    state.msg = "";
                }
            }
            else {
                break;
            }
        }
    }
    return messages;
}

function encodeHeader(msg)
{
    const l = length(msg);
    if (l < 126) {
        return struct.pack(">BB", FIN | OP_TEXT, l);
    }
    else if (l < 65536) {
        return struct.pack(">BBH", FIN | OP_TEXT, 126, l);
    }
    else {
        return struct.pack(">BBQ", FIN | OP_TEXT, 127, l);
    }
}

function read(ns)
{
    const state = states[ns];
    if (!state) {
        return [];
    }
    switch (state.state) {
        case S_HTTPHEADER:
        {
            const data = ns.recv();
            if (!data || length(data) === 0) {
                close(ns);
                return [];
            }
            state.incoming += data;
            const i = index(state.incoming, "\r\n\r\n");
            if (i !== -1) {
                let key = null;
                let agent = "";
                const lines = split(substr(state.incoming, 0, i), "\r\n");
                if (platform.auth(lines)) {
                    for (let l = 0; l < length(lines); l++) {
                        const line = lines[l];
                        const kv = split(line, ": ");
                        const k = lc(kv[0]);
                        switch (k) {
                            case "sec-websocket-key":
                                key = kv[1];
                                break;
                            case "user-agent":
                                agent = kv[1];
                                break;
                            default:
                                break;
                        }
                    }
                }
                else {
                    DEBUG0("Bad or missing authentication.\n");
                    ns.send("HTTP/1.1 400 Bad authentication\r\n");
                }
                if (!key) {
                    close(ns);
                }
                else {
                    const digest = b64enc(crypto.sha1hash(`${key}${MAGIC_KEY}`));
                    ns.send(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${digest}\r\n\r\n`);
                    state.state = S_MSGRECV;
                    state.incoming = substr(state.incoming, i + 4);
                    return [ { text: '{"cmd":"connected","agent":"' + agent + '"}', socket: state.id }, ...decode(state) ];
                }
            }
            break;
        }
        case S_MSGRECV:
        {
            const data = ns.recv();
            if (!data || length(data) === 0) {
                close(ns);
                return;
            }
            state.incoming += data;
            return decode(state);
        }
        default:
            break;
    }
    return [];
}

export function recv(handle)
{
    return handle === s ? accept() : read(handle);
};

export function send(to, msg)
{
    const hdr = encodeHeader(msg);
    let targets;
    if (to) {
        targets = [];
        for (let ns in states) {
            if (states[ns].id === to) {
                targets = [ null, states[ns].s ];
                break;
            }
        }
    }
    else {
        targets = allhandles;
    }
    for (let i = 1; i < length(targets); i++) {
        const r = targets[i].sendmsg([ hdr, msg ]);
        if (r === null) {
            DEBUG0("websocket:send error: %s\n", socket.error());
            close(targets[i]);
        }
    }
};

function ping()
{
    const ping = struct.pack("2B", FIN | OP_PING, 0);
    for (let i = 1; i < length(allhandles); i++) {
        const r = allhandles[i].send(ping);
        if (r === null) {
            DEBUG0("websocket:ping error: %s\n", socket.error());
            close(allhandles[i]);
        }
    }
}

export function tick()
{
    if (timers.tick("websocket")) {
        ping();
    }
};

export function process()
{
};
