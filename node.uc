import * as struct from "struct";
import * as math from "math";
import * as crypto from "crypto.crypto";

const LOCATION_PRECISION = 16;
const LOCATION_SOURCE_MANUAL = 1;

const MAX_SHORT_NAME_LENGTH = 4;
const MAX_LONG_NAME_LENGTH = 36;

export const ROLE_CLIENT = 0;
export const ROLE_CLIENT_MUTE = 1;
export const ROLE_ROUTER = 2;
export const ROLE_ROUTER_CLIENT = 3;
export const ROLE_REPEATER = 4;
export const ROLE_TRACKER = 5;
export const ROLE_SENSOR = 6;
export const ROLE_TAK = 7;
export const ROLE_CLIENT_HIDDEN = 8;
export const ROLE_LOST_AND_FOUND = 9;
export const ROLE_TAK_TRACKER = 10;
export const ROLE_ROUTER_LATE = 11;
export const ROLE_CLIENT_BASE = 12;

const DEFAULT_HOPS = 5;

let me = null;
let fuzzyLocation = null;
let preciseLocation = null;
let maxHops = DEFAULT_HOPS;

export const BROADCAST = 0xffffffff;

export function id()
{
    return me.id;
};

export function forMe(msg)
{
    return msg.to === BROADCAST || msg.to === me.id;
};

export function isBroadcast(msg)
{
    return msg.to === BROADCAST;
};

export function toMe(msg)
{
    return msg.to === me.id;
};

export function fromMe(msg)
{
    return msg.from === me.id;
};

export function canRoleForward(role)
{
    switch (role) {
        case ROLE_CLIENT_MUTE:
        case ROLE_CLIENT_HIDDEN:
        case ROLE_TRACKER:
        case ROLE_LOST_AND_FOUND:
        case ROLE_SENSOR:
            return false;
        default:
            return true;
    }
};

export function canForward()
{
    return canRoleForward(me.role);
};

export function hopLimit()
{
    return maxHops;
};

function save()
{
    platform.store("node", me);
};

function createNode(config)
{
    const id = config.macaddress ?? [ math.rand() & 255, math.rand() & 255, math.rand() & 255, math.rand() & 255, math.rand() & 255, math.rand() & 255 ];
    const keypair = crypto.generateKeyPair();
    me = {
        id: (id[2] << 24) + (id[3] << 16) + (id[4] << 8) + id[5],
        long_name: sprintf("Raven %02x%02x", id[4], id[5]),
        short_name: sprintf("%02x%02x", id[4], id[5]),
        macaddr: struct.pack("6B", id[0], id[1], id[2], id[3], id[4], id[5]),
        private_key: keypair.private,
        public_key: keypair.public,
        lat: null,
        lon: null,
        alt: null,
        precision: null,
        role: ROLE_CLIENT_MUTE
    };
    save();
    return me;
};

function maskLoc(v, p)
{
    if (p !== 32) {
        v = int(v * 10000000);
        const mask = -1 << p;
        const nmask = ~mask;
        v = (v & mask) | (math.rand(nmask) & nmask);
        v = v / 10000000.0;
    }
    return v;
}

export function setup(config)
{
    me = platform.load("node") ?? createNode(config);
    const location = config.location;
    if (location) {
        me.precision = max(LOCATION_PRECISION, min(32, location.precision ?? me.precision ?? 0));
        me.lat = location.latitude ?? me.lat;
        me.lon = location.longitude ?? me.lon;
        me.alt = location.altitude ?? me.alt;
        preciseLocation = {
            lat: me.lat,
            lon: me.lon,
            alt: me.alt,
            precision: 32,
            source: location.source ?? LOCATION_SOURCE_MANUAL

        };
        fuzzyLocation = {
            lat: maskLoc(me.lat),
            lon: maskLoc(me.lon),
            alt: me.alt,
            precision: me.precision,
            source: location.source ?? LOCATION_SOURCE_MANUAL
        };
    }
    if (config.long_name) {
        me.long_name = substr(config.long_name, 0, MAX_LONG_NAME_LENGTH);
    }
    if (config.short_name) {
        me.short_name = substr(config.short_name, 0, MAX_SHORT_NAME_LENGTH);
    }
    switch (config.role) {
        case "client":
            if (config.ipmesh && config.meshtastic) {
                me.role = ROLE_CLIENT;
            }
            else {
                me.role = ROLE_CLIENT_MUTE;
            }
            break;
        case "client_mute":
            me.role = ROLE_CLIENT_MUTE;
            break;
        default:
            print(`Unknown role: ${config?.role}\n`);
            break;
    }
    maxHops = config.maxhops || DEFAULT_HOPS;
    save();
};

export function getInfo()
{
    return me;
};

export function getLocation(precise)
{
    return precise ? preciseLocation : fuzzyLocation;
};
