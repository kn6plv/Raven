import * as meshtastic from "meshtastic";

meshtastic.registerProto(
    "power_metrics", null,
    {
        "1": "float ch1_voltage",
        "2": "float ch1_current",
        "3": "float ch2_voltage",
        "4": "float ch2_current",
        "5": "float ch3_voltage",
        "6": "float ch3_current",
        "7": "float ch4_voltage",
        "8": "float ch4_current",
        "9": "float ch5_voltage",
        "10": "float ch5_current",
        "11": "float ch6_voltage",
        "12": "float ch6_current",
        "13": "float ch7_voltage",
        "14": "float ch7_current",
        "15": "float ch8_voltage",
        "16": "float ch8_current"
    }
);

export function setup(config)
{
};

export function tick()
{
};

export function process(msg)
{
};
