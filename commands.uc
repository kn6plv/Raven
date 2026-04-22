import * as channel from "channel";
import * as router from "router";
import * as message from "message";
import * as textmessage from "textmessage";
import * as node from "node";

function getPublicChannels()
{
    const channels = [];
    const all = channel.getAllChannelNamekeys();
    for (let i = 0; i < length(all); i++) {
        const namekey = all[i];
        if (channel.isMeshtasticPreset(namekey) || channel.isMeshcorePreset(namekey) || channel.isAREDNPreset(namekey)) {
            push(channels, `<div class="cj">${split(namekey, " ")[0]}</div>`);
        }
        else if (ord(namekey) === 35 /* # */ || ord(namekey) === 37 /* % */ || channel.isAREDNOnly(namekey)) {
            push(channels, `<div class="cj" onclick='cmd("/channels join ${namekey}")'>${split(namekey, " ")[0]}</div>`);
        }
    }
    return sort(channels);
}

function getBridge()
{
    const services = platform.getTargetsByIdAndNamekey(null, null, true);
    for (let i = 0; i < length(services); i++) {
        const bridges = services[i].bridge;
        for (let j = 0; j < length(bridges); j++) {
            if (bridges[j].meship) {
                return services[i].id;
            }
        }
    }
    return null;
}

export function post(cmd, id)
{
    switch (cmd[0]) {
        case "channels":
        {
            switch (cmd[1] ?? "local") {
                case "world":
                {
                    const bridge = getBridge();
                    if (bridge) {
                        router.queue(message.createMessage(bridge, null,null, "command", {
                            id: id,
                            cmd: "get_public_channels"
                        }, {
                            hop_limit: 0
                        }));
                        break;
                    }
                    // Fall through
                }
                case "local":
                {
                    const reply = [
                        "Public channels on local network", "&nbsp;",
                        ...getPublicChannels()
                    ];
                    event.queue({ cmd: "/reply", reply: reply, socket: id });
                    break;
                }
                case "join":
                {
                    if (cmd[2] && cmd[3]) {
                        let join = true;
                        const namekey = `${cmd[2]} ${cmd[3]}`;
                        const newchannel = { namekey: namekey, max: 100, badge: true, images: false, telemetry: false, winlink: false };
                        const currchannels = map(channel.getAllLocalChannels(), c => {
                            const s = textmessage.state(c.namekey);
                            if (c.namekey === namekey) {
                                join = false;
                            }
                            return { namekey: c.namekey, max: s.max, badge: s.badge, images: s.images, telemetry: c.telemetry, winlink: s.winlink };
                        });
                        if (join) {
                            event.queue({ cmd: "newchannels", channels: [ ...currchannels, newchannel ] });
                            event.queue({ cmd: "/reply", reply: [ `Joined channel ${cmd[2]}` ], socket: id });
                        }
                    }
                    break;
                }
                case "leave":
                {
                    if (cmd[2]) {
                        const name = `${cmd[2]} `;
                        const currchannels = channel.getAllLocalChannels();
                        const newchannels = map(filter(currchannels, c => index(c.namekey, name) !== 0), c => {
                            const s = textmessage.state(c.namekey);
                            return { namekey: c.namekey, max: s.max, badge: s.badge, images: s.images, telemetry: c.telemetry, winlink: s.winlink };
                        });
                        if (length(currchannels) !== length(newchannels)) {
                            event.queue({ cmd: "newchannels", channels: newchannels });
                            event.queue({ cmd: "/reply", reply: [ `Left channel ${name}` ], socket: id });
                        }
                    }
                    break;
                }
                default:
                    break;
            }
        }
        default:
            break;
    }
};

export function setup(config)
{
};

export function tick()
{
};

export function process(msg)
{
    if (msg.data?.command && node.toMe(msg)) {
        switch (msg.data.command.cmd) {
            case "get_public_channels":
            {
                router.queue(message.createMessage(msg.from, null,null, "command", {
                    id: msg.data.command.id,
                    cmd: "reply_public_channels",
                    channels: getPublicChannels(),
                }, {
                    hop_limit: 0
                }));
                break;
            }
            case "reply_public_channels":
            {
                const reply = [
                    "Public channels on world network", "&nbsp;",
                    ...msg.data.command.channels
                ];
                event.queue({ cmd: "/reply", reply: reply, socket: msg.data.command.id });
            }
            default:
                break;
        }
    }
};
