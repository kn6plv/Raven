import * as meshtastic from "meshtastic";
import * as telemetry from "telemetry";

meshtastic.registerProto(
    "environment_metrics", null,
    {
        "1": "float temperature",
        "2": "float relative_humidity",
        "3": "float barometric_pressure",
        "4": "float gas_resistance",
        "5": "float voltage",
        "6": "float current",
        "7": "uint32 iaq",
        "8": "float distance",
        "9": "float lux",
        "10": "float white_lux",
        "11": "float ir_lux",
        "12": "float uv_lux",
        "13": "uint32 wind_direction",
        "14": "float wind_speed",
        "15": "float weight",
        "16": "float wind_gust",
        "17": "float wind_lull",
        "18": "float radiation",
        "19": "float rainfall_1h",
        "20": "float rainfall_24h",
        "21": "uint32 soil_moisture",
        "22": "float soil_temperature"
    }
);
