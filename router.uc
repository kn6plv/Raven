import * as meshtastic from "meshtastic";
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
            if (msg.transport !== "ipmesh") {
                DEBUG1("Send IPMesh: %.2J\n", msg);
                // Include forwarding nodes when sending the message if the hop_limit allows it
                // and we are not ourselves a forwarder (in which case using another would be redundant)
                ipmesh.send(msg.to, msg, msg.hop_limit > 0 && !node.canForward());
            }
            if (msg.transport !== "meshtastic" && (node.isBroadcast(msg) || !platform.getTargetById(msg.to))) {
                DEBUG1("Send Meshtastic: %.2J\n", msg);
                meshtastic.send(msg);
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
                case "ipmesh":
                    try {
                        queue(ipmesh.recv());
                    }
                    catch (_) {
                    }
                    break;
                case "meshtastic":
                    try {
                        queue(meshtastic.recv());
                    }
                    catch (_)
                    {
                    }
                    break;
                case "platform":
                {
                    platform.handleChanges();
                    break;
                }
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
                    }
                    break;
            }
        }
    }
};
