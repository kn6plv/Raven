import * as channel from "channel";
import * as router from "router";
import * as message from "message";
import * as node from "node";

function getPublicChannels()
{
    const channels = [];
    const all = channel.getAllChannelNamekeys();
    for (let i = 0; i < length(all); i++) {
        const namekey = all[i];
        if (ord(namekey) === 35 /* # */ || ord(namekey) === 37 /* % */ || channel.isAREDNOnly(namekey) || channel.isMeshtasticPreset(namekey) || channel.isMeshcorePreset(namekey)) {
            push(channels, split(namekey, " ")[0]);
        }
    }
    return sort(channels);
}

export function post(cmd, id)
{
    switch (cmd[0]) {
        case "channels":
        {
            if (cmd[1] === "world") {
                let service = null;
                const services = platform.getTargetsByIdAndNamekey(null, null, true);
                for (let i = 0; i < length(services); i++) {
                    const bridges = services[i].bridge;
                    for (let j = 0; j < length(bridges); j++) {
                        if (bridges[j].meship) {
                            service = services[i];
                            break;
                        }
                    }
                }
                if (service) {
                    router.queue(message.createMessage(service.id, null,null, "command", {
                        id: id,
                        cmd: "get_public_channels"
                    }, {
                        hop_limit: 0
                    }));
                }
            }
            else {
                const reply = [
                    "Public channels on local network", "&nbsp;",
                    ...getPublicChannels()
                ];
                event.queue({ cmd: "/reply", reply: reply, socket: id });
            }
            break;
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
