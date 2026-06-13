import * as socket from "socket";

const PORT = 4404;

let s = null;
let bridge = false;

export function setup(config)
{
    if (!config.meship) {
        return;
    }
    if (config.meship.bridge) {
        bridge = true;
    }
    s = socket.create(socket.AF_INET, socket.SOCK_DGRAM, 0);
    s.bind({
        port: PORT
    });
    s.listen();
};

export function shutdown()
{
};

export function handle()
{
    return s;
};

export function isBridge()
{
    return bridge;
};

export function recv()
{
    try {
        const m = s.recvmsg(65535);
        const msg = json(m.data);
        msg.ipaddress = m.address.address;
        // Avoid messages from remote networks if we don't have our own ip forwarder available.
        // This avoid async messages where we receive from remote networks but cannot reply.
        if (!bridge && msg.transport === "native" && !platform.canAcceptIPAddress(msg.ipaddress)) {
            return null;
        }
        return msg;
    }
    catch (_) {
        return null;
    }
};

export function send(to, msg, canforward)
{
    const targets = platform.getTargetsByIdAndNamekey(to, msg.namekey, canforward);
    const data = sprintf("%J", msg);
    const from = msg.from;
    for (let i = length(targets) - 1; i >= 0; i--) {
        const t = targets[i];
        if (t.id !== from) {
            const r = s.send(data, 0, {
                address: t.ip,
                port: PORT
            });
            if (r === null) {
                DEBUG1("meship:send error: %s\n", socket.error());
            }
        }
    }
};

export function tick()
{
};

export function process(msg)
{
};

export function cmd(msg, reply)
{
};
