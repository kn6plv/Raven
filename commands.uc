import * as channel from "channel";

export function post(cmd)
{
    switch (cmd[0]) {
        case "channels":
        {
            const channels = [];
            const all = channel.getAllChannelNamekeys();
            for (let i = 0; i < length(all); i++) {
                const namekey = all[i];
                if (ord(namekey) === 35 /* # */ || ord(namekey) === 37 /* % */ || channel.isAREDNOnly(namekey) || channel.isMeshtasticPreset(namekey) || channel.isMeshcorePreset(namekey)) {
                    push(channels, split(namekey, " ")[0]);
                }
            }
            return [
                "Public channels on local network", "&nbsp;",
                ...sort(channels)
            ];
        }
        default:
            return null;
    }
};
