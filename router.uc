import * as meshtastic from "meshtastic";
import * as meshcore from "meshcore";
import * as ipmesh from "ipmesh";
import * as node from "node";
import * as socket from "socket";
import * as timers from "timers";
import * as websocket from "websocket";

const MAX_RECENT = 128;
const recent = [];
const apps = [];
const q = [];

export function registerApp(app)
{
    push(apps, app);
};

export function process()
{
    while (length(q) > 0) {
        const msg = shift(q);

        if (node.fromMe(msg)) {
            DEBUG0("%.2J\n", msg);
        }
        else {
            DEBUG1("%.2J\n", msg);
        }

        // Give each app a chance at the message
        for (let i = 0; i < length(apps); i++) {
            apps[i].process(msg);
        }

        // Forward the message if it's not just to me. We never forward encrypted traffic.
        if (!node.toMe(msg) && !msg.encrypted) {
            if (!node.fromMe(msg)) {
                if (!node.canForward()) {
                    continue;
                }
                msg.hop_limit--;
                if (msg.hop_limit < 0) {
                    continue;
                }
            }

            // Determine which interfaces we can route the packet out on.
            // msg.transport == the way the message entered the system, "native" indicating it originated natively and didn't
            // arrive via a bridge.
            let toip = false;
            let tomeshtastic = false;
            let tomeshcore = false;
            // If we know where the msg goes, it goes vi IP
            if (platform.getTargetById(msg.to)) {
                toip = true;
            }
            // Otherwise if it's from me, then it goes everywhere
            else if (node.fromMe(msg)) {
                toip = true;
                tomeshtastic = true;
                tomeshcore = true;
            }
            // If the message originated natively, it can go to one of the bridges. Note that we dont sent traffic
            // from one bridge to another (no meshtastic <-> meshcore bridging) at the moment.
            else if (msg.transport === "native") {
                tomeshtastic = true;
                tomeshcore = true;
            }
            // Incoming bridge traffic can only route via IP
            else {
                toip = true;
            }

            if (toip) {
                try {
                    DEBUG1("Send IPMesh: %.2J\n", msg);
                    // Include forwarding nodes when sending the message if the hop_limit allows it
                    ipmesh.send(msg.to, msg, msg.hop_limit > 0);
                }
                catch (e) {
                    DEBUG0("ipmesh recv: %s\n", e.stacktrace);
                }
            }
            if (tomeshcore) {
                try {
                    DEBUG1("Send Meshcore: %.2J\n", msg);
                    meshcore.send(msg);
                }
                catch (e) {
                    DEBUG0("ipmesh recv: %s\n", e.stacktrace);
                }
            }
            // Meshtastic modifies the message so much come last
            if (tomeshtastic) {
                try {
                    DEBUG1("Send Meshtastic: %.2J\n", msg);
                    meshtastic.send(msg);
                }
                catch (e) {
                    DEBUG0("ipmesh recv: %s\n", e.stacktrace);
                }
            }
        }
    }
};

export function queue(msg)
{
    if (msg) {
        // Remember messages we queued for a little while and don't queue them again.
        if (index(recent, msg.id) === -1) {
            push(recent, msg.id);
            if (length(recent) > MAX_RECENT) {
                shift(recent);
            }
            push(q, msg);
        }
    }
};

export function tick()
{
    for (let i = 0; i < length(apps); i++) {
        apps[i].tick();
    }
    process();
    const sockets = [];
    const us = ipmesh.handle();
    if (us) {
        push(sockets, [ us, socket.POLLIN, "ipmesh" ]);
    }
    const ms = meshtastic.handle();
    if (ms) {
        push(sockets, [ ms, socket.POLLIN, "meshtastic" ]);
    }
    const mc = meshcore.handle();
    if (mc) {
        push(sockets, [ mc, socket.POLLIN, "meshcore" ]);
    }
    const ph = platform.handle();
    if (ph) {
        push(sockets, [ ph, socket.POLLIN|socket.POLLRDHUP, "platform" ]);
    }
    const ws = websocket.handles();
    if (ws) {
        for (let i = 0; i < length(ws); i++) {
            push(sockets, [ ws[i], socket.POLLIN|socket.POLLRDHUP, "websocket" ]);
        }
    }
    const v = socket.poll(timers.minTimeout(60) * 1000, ...sockets);
    for (let i = 0; i < length(v); i++) {
        if (v[i] && v[i][1]) {
            switch (v[i][2]) {
                case "websocket":
                {
                    const msgs = websocket.recv(v[i][0]);
                    for (let i = 0; i < length(msgs); i++) {
                        const msg = msgs[i];
                        if (msg.text) {
                            const j = json(msg.text);
                            j.socket = msg.socket;
                            event.queue(j);
                        }
                        else if (msg.binary) {
                            event.queue({ cmd: "upload", binary: msg.binary, socket: msg.socket });
                        }
                    }
                    break;
                }
                case "ipmesh":
                    try {
                        queue(ipmesh.recv());
                    }
                    catch (e) {
                        DEBUG0("ipmesh recv: %s\n", e.stacktrace);
                    }
                    break;
                case "meshtastic":
                    try {
                        queue(meshtastic.recv());
                    }
                    catch (e)
                    {
                        DEBUG0("meshtastic recv: %s\n", e.stacktrace);
                    }
                    break;
                case "meshcore":
                    try {
                        queue(meshcore.recv());
                    }
                    catch (e) {
                        DEBUG0("meshcore recv: %s\n", e.stacktrace);
                    }
                    break;
                case "platform":
                {
                    platform.handleChanges();
                    break;
                }
            }
        }
    }
};
