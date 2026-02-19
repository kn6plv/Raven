import * as math from "math";
import * as websocket from "websocket";
import * as timers from "timers";
import * as node from "node";
import * as nodedb from "nodedb";
import * as channel from "channel";
import * as textmessage from "textmessage";
import * as textstore from "textstore";
import * as router from "router";
import * as winlink from "winlink";

const HW_AREDN = 254;
const HW_MESHCORE = 253;
const q = [];
let merge = {};
let update = null;
let activity = false;

export function setup(config)
{
    update = config.update;
    timers.setInterval("event", 0, 10 * 60);
    timers.setInterval("keepalive", 60);
};

function send(msg, to)
{
    DEBUG1("send %J\n", msg);
    websocket.send(to, sprintf("%J", msg));
    if (!to) {
        activity = true;
    }
}

export function queue(msg)
{
    push(q, msg);
    timers.trigger("event");
};

export function notify(event, mergekey)
{
    if (!mergekey) {
        mergekey = event.cmd;
    }
    if (!merge[mergekey]) {
        merge[mergekey] = true;
        push(q, event);
    }
    timers.trigger("event");
};

function longname2shortname(name)
{
    return join("", map(split(name, " "), w => substr(w, 0, 1)));
}

function basicNode(node)
{
    const nodeinfo = node?.nodeinfo;
    if (nodeinfo) {
        const bnode = {
            id: nodeinfo.id,
            num: node.id,
            favorite: node.favorite,
            short_name: nodeinfo.short_name ?? longname2shortname(nodeinfo.long_name),
            long_name: nodeinfo.long_name,
            role: nodeinfo.role ?? 0,
            lastseen: node.lastseen,
            hw: nodeinfo.hw_model === HW_AREDN ? "aredn" : nodeinfo.hw_model == HW_MESHCORE ? "meshcore" : "meshtastic",
            is_unmessagable: nodeinfo.is_unmessagable
        };
        if (node.favorite) {
            bnode.state = textmessage.state(nodedb.namekey(node.id));
        };
        return bnode;
    }
    return null;
}

function fullNode(node)
{
    const nodeinfo = node?.nodeinfo;
    if (nodeinfo) {
        const fnode = {
            id: nodeinfo.id,
            num: node.id,
            favorite: node.favorite,
            short_name: nodeinfo.short_name ?? longname2shortname(nodeinfo.long_name),
            long_name: nodeinfo.long_name,
            role: nodeinfo.role ?? 0,
            lastseen: node.lastseen,
            hops: node.hops,
            hw: nodeinfo.hw_model === HW_AREDN ? "aredn" : nodeinfo.hw_model === HW_MESHCORE ? "meshcore" : "meshtastic",
            is_unmessagable: nodeinfo.is_unmessagable,
            public_key: b64enc(nodeinfo.public_key),
            state: textmessage.state(nodedb.namekey(node.id))
        };
        const latitude_i = node.position?.latitude_i;
        const longitude_i = node.position?.longitude_i;
        if (latitude_i && longitude_i) {
            fnode.latitude = latitude_i / 10000000.0;
            fnode.longitude = longitude_i / 10000000.0;
            fnode.mapurl = platform.getMap(fnode.latitude,  fnode.longitude);
        }
        return fnode;
    }
    return null;
}

export function tick()
{
    if (timers.tick("event")) {
        while (length(q) > 0) {
            const msg = shift(q);

            DEBUG1("%J\n", msg);

            switch (msg.cmd) {
                case "connected":
                {
                    notify({ cmd: "me" });
                    notify({ cmd: "channels" });
                    notify({ cmd: "favorites" });
                    notify({ cmd: "nodes" });
                    const namekey = channel.getAllLocalChannels()[0].namekey;
                    notify({ cmd: "texts", namekey: namekey }, `texts ${namekey}`);
                    notify({ cmd: "winmenu" });
                    break;
                }
                case "me":
                {
                    send({ event: msg.cmd, node: basicNode(nodedb.getNode(node.getInfo().id)) });
                    break;
                }
                case "nodes":
                {
                    const raw = nodedb.getNodes(false);
                    sort(raw, (a, b) => b.lastseen - a.lastseen);
                    const nodes = [];
                    for (let i = 0; i < length(raw) && length(nodes) < 200; i++) {
                        const node = basicNode(raw[i]);
                        if (node) {
                            push(nodes, node);
                        }
                    }
                    send({ event: msg.cmd, nodes: nodes });
                    break;
                }
                case "favorites":
                {
                    const raw = nodedb.getNodes(true);
                    sort(raw, (a, b) => a.nodeinfo?.long_name < b.nodeinfo?.long_name ? -1 : a.nodeinfo?.long_name > b.nodeinfo?.long_name ? 1 : 0);
                    const nodes = [];
                    for (let i = 0; i < length(raw) && length(nodes) < 200; i++) {
                        const node = basicNode(raw[i]);
                        if (node) {
                            push(nodes, node);
                        }
                    }
                    send({ event: msg.cmd, nodes: nodes });
                    break;
                }
                case "node":
                {
                    if (msg.id !== node.getInfo().id) {
                        const node = basicNode(nodedb.getNode(msg.id, false));
                        if (node) {
                            send({ event: msg.cmd, node: node });
                        }
                    }
                    break;
                }
                case "fullnode":
                {
                    const node = fullNode(nodedb.getNode(msg.id, false));
                    if (node) {
                        send({ event: msg.cmd, node: node });
                    }
                    break;
                }
                case "channels":
                {
                    const channels = map(channel.getAllLocalChannels(), c => {
                        return { namekey: c.namekey, meshtastic: c.meshtastic, winlink: c.winlink, telemetry: c.telemetry, state: textmessage.state(c.namekey) };
                    });
                    send({ event: msg.cmd, channels: channels });
                    break;
                }
                case "newchannels":
                {
                    for (let i = 0; i < length(msg.channels); i++) {
                        const c = msg.channels[i];
                        const n = split(c.namekey, " ");
                        c.namekey = `${substr(join("", slice(n, 0, -1)), 0, 13)} ${n[-1]}`;
                    }
                    const nchannels = channel.updateLocalChannels(msg.channels);
                    textmessage.updateSettings(msg.channels);
                    notify({ cmd: "channels" });
                    platform.publish(node.getInfo(), channel.getAllLocalChannels());
                    for (let i = 0; i < length(nchannels); i++) {
                        textstore.syncMessageNamekey(nchannels[i].namekey);
                    }
                    update("channels");
                    break;
                }
                case "catchup":
                {
                    send({ event: msg.cmd, namekey: msg.namekey, state: textmessage.catchUpMessagesTo(msg.namekey, msg.id) });
                    break;
                }
                case "texts":
                {
                    send({ event: msg.cmd, namekey: msg.namekey, texts: textmessage.getMessages(msg.namekey), state: textmessage.state(msg.namekey) });
                    break;
                }
                case "text":
                {
                    const text = textmessage.getMessage(msg.namekey, msg.id);
                    if (text) {
                        send({ event: msg.cmd, namekey: msg.namekey, text: text, state: textmessage.state(msg.namekey) });
                    }
                    break;
                }
                case "post":
                {
                    let tmsg;
                    let structuredtext = null;
                    if (msg.structuredtext) {
                        structuredtext = msg.structuredtext;
                        for (let i = 0; i < length(msg.structuredtext); i++) {
                            if (structuredtext[i].winlink) {
                                structuredtext[i].winlink = winlink.post(structuredtext[i].winlink.id, structuredtext[i].winlink.data);
                            }
                        }
                    }
                    if (channel.isDirect(msg.namekey)) {
                        tmsg = textmessage.createDirectMessage(msg.namekey, msg.text, structuredtext, msg.replyto, msg.last);
                    }
                    else if (channel.getLocalChannelByNameKey(msg.namekey)) {
                        tmsg = textmessage.createMessage(null, msg.namekey, msg.text, structuredtext, msg.replyto, msg.last);
                    }
                    if (tmsg) {
                        router.queue(tmsg);
                    }
                    break;
                }
                case "upload":
                {
                    const name = sprintf("img%08X.jpg", math.rand());
                    platform.storebinary(name, msg.binary);
                    send({ event: "uploaded", name: name }, msg.socket);
                    break;
                }
                case "fav":
                {
                    textmessage.updateChannelBadge(nodedb.namekey(msg.id), msg.favorite);
                    break;
                }
                case "ack":
                {
                    send({ event: msg.cmd, id: msg.id });
                    break;
                }
                case "winmenu":
                {
                    send({ event: msg.cmd, menu: winlink.menu() }, msg.socket);
                    break;
                }
                case "winform":
                {
                    const formdata = winlink.formpost(msg.id);
                    if (formdata) {
                        send({ event: msg.cmd, formdata: formdata }, msg.socket);
                    }
                    break;
                }
                case "winshow":
                {
                    try {
                        const sdata = textmessage.getMessage(msg.namekey, msg.id)?.structuredtext;
                        if (sdata && sdata[0] && sdata[0].winlink) {
                            const formdata = winlink.formshow(sdata[0].winlink.id, sdata[0].winlink.data);
                            if (formdata) {
                                send({ event: msg.cmd, id: msg.id, formdata: formdata }, msg.socket);
                            }
                        }
                    }
                    catch (_) {
                    }
                    break;
                }
                case "ping":
                {
                    send({ event: "pong" }, msg.socket);
                    break;
                }
                default:
                    break;
            }
        }
        merge = {};
    }
    if (timers.tick("keepalive")) {
        if (!activity) {
            send({ event: "beat" });
        }
        activity = false;
    }
};

export function process(msg)
{
};
