import * as router from "router";
import * as message from "message";
import * as node from "node";
import * as timers from "timers";
import * as nodedb from "nodedb";
import * as channel from "channel";
import * as meshtastic from "meshtastic";
import * as telemetry from "telemetry";

const GRID_POWER = 101;
let startTime = 0;
 
meshtastic.registerProto(
    "device_metrics", null,
    {
        "1": "uint32 battery_level",
        "2": "float voltage",
        "3": "float channel_utilization",
        "4": "float air_util_tx",
        "5": "uint32 uptime_seconds"
    }
);

export function setup(config)
{
    startTime = clock(true)[0];
    timers.setInterval("device_metrics", 60, config.telemetry?.device?.interval ?? telemetry.DEFAULT_INTERVAL);
};

export function tick()
{
    if (timers.tick("device_metrics")) {
        const telemetry = channel.getTelemetryChannels();
        for (let i = 0; i < length(telemetry); i++) {
            router.queue(message.createMessage(null, null, telemetry[i].namekey, "telemetry", {
                time: time(),
                device_metrics: {
                    battery_level: GRID_POWER,
                    uptime_seconds: clock(true)[0] - startTime
                }
            }));
        }
    }
};

export function process(msg)
{
    if (msg.data?.telemetry?.device_metrics && node.forMe(msg)) {
        nodedb.updateDeviceMetrics(msg.from, msg.data.telemetry.device_metrics);
    }
};
