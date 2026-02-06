import * as socket from "socket";

const PORT = 4404;

let s = null;

export function setup(config)
{
    if (!config.ipmesh) {
        return;
    }
    s = socket.create(socket.AF_INET, socket.SOCK_DGRAM, 0);
    s.bind({
        port: PORT
    });
    s.listen();
};

export function handle()
{
    return s;
};

export function recv()
{
    try {
        const msg = json(s.recvmsg(65535).data);
        // If we receive a message from an unknown target, refresh the platform targets in an
        // attempt to learn about it.
        if (!platform.getTargetById(msg.from)) {
            platform.refresh();
        }
        msg.transport = "ipmesh";
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
    for (let i = 0; i < length(targets); i++) {
        const r = s.send(data, 0, {
            address: targets[i].ip,
            port: PORT
        });
        if (r === null) {
            DEBUG0("ipmesh:send error: %s\n", socket.error());
        }
    }
};
