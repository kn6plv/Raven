import * as meshtastic from "meshtastic";

meshtastic.registerProto(
    "telemetry", 67,
    {
        "1": "fixed32 time",
        "2": "proto device_metrics device_metrics",
        "3": "proto environment_metrics environment_metrics",
        "4": "proto airquality_metrics airquality_metrics",
        "5": "proto power_metrics power_metrics",
        "6": "proto local_stats local_stats",
        "7": "proto health_metrics health_metrics",
        "8": "proto host_metrics host_metrics"
    }
);

export const DEFAULT_INTERVAL = 30 * 60;

export function convert(tounit, value)
{
    if (!value) {
        return null;
    }
    const fromunit = value.units;
    let v = value.value;
    switch (tounit) {
        case "C":
            switch(substr(fromunit, -1)) {
                case "F":
                    v = (v - 32) / 1.8;
                    break;
                default:
                    break;
            }
        case "hPA":
            switch (fromunit) {
                case "inHg":
                    v *= 33.86389;
                    break;
                default:
                    break;
            }
        case "m/s":
            switch (fromunit) {
                case "mph":
                    v *= 0.44704;
                    break;
                default:
                    break;
            }
        case "mm/h":
            switch (fromunit) {
                case "in/h":
                    v *= 25.4;
                    break;
                default:
                    break;
            }
        case "mm":
            switch (fromunit) {
                case "in":
                    v *= 25.4;
                    break;
                default:
                    break;
            }
        default:
            break;
    }
    return v;
};
