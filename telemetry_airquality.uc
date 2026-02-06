import * as meshtastic from "meshtastic";
import * as telemetry from "telemetry";

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
