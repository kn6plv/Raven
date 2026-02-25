import * as meshtastic from "meshtastic";

meshtastic.registerProto(
    "packet", null,
    {
        "1": "fixed32 from",
        "2": "fixed32 to",
        "3": "uint32 channel",
        "4": "bytes decoded",
        "5": "bytes encrypted",
        "6": "fixed32 id",
        "7": "fixed32 rx_time",
        "8": "float rx_snr",
        "9": "uint32 hop_limit",
        "10": "bool want_ack",
        "11": "enum priority",
        "12": "int32 rx_rssi",
        "13": "enum delayed",
        "14": "bool via_mqtt",
        "15": "uint32 hop_start",
        "16": "bytes public_key",
        "17": "bool pki_encrypted",
        "18": "uint32 next_hop",
        "19": "uint32 relay_node",
        "20": "uint32 tx_after",
        "21": "enum transport_mechanism"
    }
);
meshtastic.registerProto(
    "data", null,
    {
        "1": "enum portnum",
        "2": "bytes payload",
        "3": "bool want_response",
        "4": "fixed32 dest",
        "5": "fixed32 source",
        "6": "fixed32 request_id",
        "7": "fixed32 reply_id",
        "8": "fixed32 emoji",
        "9": "uint32 bitfield"
    }
);
meshtastic.registerProto(
    "position", 3,
    {
        "1": "sfixed32 latitude_i",
        "2": "sfixed32 longitude_i",
        "3": "int32 altitude",
        "4": "fixed32 time",
        "5": "enum location_source",
        "6": "enum altitude_source",
        "7": "fixed32 timestamp",
        "8": "int32 timestamp_millis_adjust",
        "9": "sint32 altitude_hae",
        "10": "sint32 altitude_geoidal_separation",
        "11": "uint32 PDOP",
        "12": "uint32 HDOP",
        "13": "uint32 VDOP",
        "14": "uint32 gps_accuracy",
        "15": "uint32 ground_speed",
        "16": "uint32 ground_track",
        "17": "uint32 fix_quality",
        "18": "uint32 fix_type",
        "19": "uint32 sats_in_view",
        "20": "uint32 sensor_id",
        "21": "uint32 next_update",
        "22": "uint32 seq_number",
        "23": "uint32 precision_bits"
    }
);

meshtastic.registerProto(
    "routediscovery", null,
    {
        "1": "repeated fixed32 route",
        "2": "repeated int32 snr_towards",
        "3": "repeated fixed32 route_back",
        "4": "repeated int32 snr_back"
    }
);
meshtastic.registerProto(
    "routing", 5,
    {
        "1": "proto routediscovery route_request",
        "2": "proto routediscovery route_reply",
        "3": "enum error_reason"
    }
);

meshtastic.registerProto(
    "statistics", null,
    {
        "1": "uint32 messages_total",
        "2": "uint32 messages_saved",
        "3": "uint32 messages_max",
        "4": "uint32 up_time",
        "5": "uint32 requests",
        "6": "uint32 requests_history",
        "7": "bool heartbeat",
        "8": "uint32 return_max",
        "9": "uint32 return_window"
    }
);
meshtastic.registerProto(
    "history", null,
    {
        "1": "uint32 history_messages",
        "2": "uint32 window",
        "3": "uint32 last_request"
    }
);
meshtastic.registerProto(
    "heartbeat", null,
    {
        "1": "uint32 period",
        "2": "uint32 secondary"
    }
);
meshtastic.registerProto(
    "storeandforward", 65,
    {
        "1": "enum rr",
        "2": "proto statistics stats",
        "3": "proto history history",
        "4": "proto heartbeat heartbeat",
        "5": "bytes text"
    }
);

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
meshtastic.registerProto(
    "airquality_metrics", null,
    {
        "1": "uint32 pm10_standard",
        "2": "uint32 pm25_standard",
        "3": "uint32 pm100_standard",
        "4": "uint32 pm10_environmental",
        "5": "uint32 pm25_environmental",
        "6": "uint32 pm100_environmental",
        "7": "uint32 particles_03um",
        "8": "uint32 particles_05um",
        "9": "uint32 particles_10um",
        "10": "uint32 particles_25um",
        "11": "uint32 particles_50um",
        "12": "uint32 particles_10um",
        "13": "uint32 co2",
        "14": "float co2_temperature",
        "15": "float co2_humidity",
        "16": "float form_formaldehyde",
        "17": "float form_humidity",
        "18": "float form_temperature",
        "19": "uint32 pm40_standard",
        "20": "uint32 particles_40um",
        "21": "float pm_temperature",
        "22": "float pm_humidity",
        "23": "float pm_voc_idx",
        "24": "float pm_nox_idx",
        "25": "float particles_tps"
    }
);

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
meshtastic.registerProto(
    "airquality_metrics", null,
    {
        "1": "uint32 pm10_standard",
        "2": "uint32 pm25_standard",
        "3": "uint32 pm100_standard",
        "4": "uint32 pm10_environmental",
        "5": "uint32 pm25_environmental",
        "6": "uint32 pm100_environmental",
        "7": "uint32 particles_03um",
        "8": "uint32 particles_05um",
        "9": "uint32 particles_10um",
        "10": "uint32 particles_25um",
        "11": "uint32 particles_50um",
        "12": "uint32 particles_10um",
        "13": "uint32 co2",
        "14": "float co2_temperature",
        "15": "float co2_humidity",
        "16": "float form_formaldehyde",
        "17": "float form_humidity",
        "18": "float form_temperature",
        "19": "uint32 pm40_standard",
        "20": "uint32 particles_40um",
        "21": "float pm_temperature",
        "22": "float pm_humidity",
        "23": "float pm_voc_idx",
        "24": "float pm_nox_idx",
        "25": "float particles_tps"
    }
);
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

meshtastic.registerProto(
    "traceroute", 70,
    {
        "1": "repeated fixed32 route",
        "2": "repeated int32 snr_towards",
        "3": "repeated fixed32 route_back",
        "4": "repeated int32 snr_back"
    }
);

meshtastic.registerProto(
    "neighbor", null,
    {
        "1": "uint32 node_id",
        "2": "float snr",
        "3": "fixed32 last_rx_time",
        "4": "uint32 node_broadcast_interval_secs"
    }
);
meshtastic.registerProto(
    "neighborinfo", 71,
    {
        "1": "uint32 node_id",
        "2": "uint32 last_sent_by_id",
        "3": "uint32 node_broadcast_interval_secs",
        "4": "repeated unpacked neighbor neighbors"
    }
);
