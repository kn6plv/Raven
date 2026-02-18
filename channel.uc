import * as struct from "struct";
import * as crypto from "crypto.crypto";

const meshtasticChannelPresets = [
    "Disabled",
    "ShortTurbo",
    "ShortSlow",
    "ShortFast",
    "MediumSlow",
    "MediumFast",
    "LongSlow",
    "LongFast",
    "LongMod",
    "LongTurbo"
];

global.channelByNameKey = {};
global.channelsByMeshtasticHash = {};
global.channelsByMeshcoreHash = {};
let meshtasticChannel;
let localChannelByNameKey = {};

function getCryptoKey(key)
{
    key = b64dec(key);
    if (length(key) === 1) {
        return [ 0xd4, 0xf1, 0xbb, 0x3a, 0x20, 0x29, 0x07, 0x59, 0xf0, 0xbc, 0xff, 0xab, 0xcf, 0x4e, 0x69, ord(key, 0) ];
    }
    else {
        const crypto = [];
        for (let i = 0; i < length(key); i++) {
            crypto[i] = ord(key, i);
        }
        return crypto;
    }
}

function getMeshtasticHash(name, crypto)
{
    let hash = 0;
    for (let i = 0; i < length(name); i++) {
        hash ^= ord(name, i);
    }
    for (let i = 0; i < length(crypto); i++) {
        hash ^= crypto[i];
    }
    return hash;
}

function getMeshcoreHash(key)
{
    return crypto.sha256hash(struct.pack(`${length(key)}B`, ...key))[0];
}

export function addMessageNameKey(namekey)
{
    if (channelByNameKey[namekey]) {
        return channelByNameKey[namekey];
    }
    const nk = split(namekey, " ");
    const crypto = getCryptoKey(nk[1]);
    const meshtastichash = getMeshtasticHash(nk[0], crypto);
    const meshcorehash = getMeshcoreHash(crypto);
    const chan = { namekey: namekey, crypto: crypto, hash: meshtastichash, meshcorehash: meshcorehash, telemetry: false };
    channelByNameKey[namekey] = chan;
    let bucket = channelsByMeshtasticHash[meshtastichash] ?? (channelsByMeshtasticHash[meshtastichash] = []);
    push(bucket, chan);
    bucket = channelsByMeshcoreHash[meshcorehash] ?? (channelsByMeshcoreHash[meshcorehash] = []);
    push(bucket, chan);
    return chan;
};

function setLocalChannel(config)
{
    const name = split(config.namekey, " ")[0];
    const chan = addMessageNameKey(config.namekey);
    if (chan.crypto[-1] === 1 && index(meshtasticChannelPresets, name) !== -1) {
        chan.meshtastic = true;
        chan.telemetry = true;
        meshtasticChannel = chan;
    }
    if (config.telemetry !== null) {
        chan.telemetry = config.telemetry;
    }
    localChannelByNameKey[config.namekey] = chan;
};

export function getChannelsByMeshtasticHash(hash)
{
    if (!hash) {
        return [ meshtasticChannel ];
    }
    return channelsByMeshtasticHash[hash];
};

export function getChannelsByMeshcoreHash(hash)
{
    return channelsByMeshcoreHash[hash];
};

export function getLocalChannelByNameKey(namekey)
{
    if (!namekey) {
        return meshtasticChannel;
    }
    return localChannelByNameKey[namekey];
};

export function getChannelByNameKey(namekey)
{
    if (!namekey) {
        return meshtasticChannel;
    }
    return channelByNameKey[namekey];
};

export function getAllLocalChannels()
{
    return values(localChannelByNameKey);
};

export function getTelemetryChannels()
{
    const telemetry = [];
    for (let namekey in channelByNameKey) {
        const chan = channelByNameKey[namekey];
        if (chan.telemetry) {
            push(telemetry, chan);
        }
    }
    return telemetry;
};

export function updateLocalChannels(channels)
{
    const oldLocalChannelByNameKey = localChannelByNameKey;
    localChannelByNameKey = {};
    for (let i = 0; i < length(channels); i++) {
        setLocalChannel(channels[i]);
    }
    const newchannels = [];
    for (let namekey in localChannelByNameKey) {
        if (!oldLocalChannelByNameKey[namekey]) {
            push(newchannels, localChannelByNameKey[namekey]);
        }
    }
    return newchannels;
};

export function isDirect(namekey)
{
    return index(namekey, "DirectMessages ") === 0;
};

export function setup(config)
{
    const channels = config.channels;
    if (channels) {
        for (let i = 0; i < length(channels); i++) {
            setLocalChannel(channels[i]);
        }
    }
};

export function tick()
{
};

export function process(msg)
{
};
