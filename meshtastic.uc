import * as socket from "socket";
import * as math from "math";
import * as struct from "struct";
import * as protobuf from "protobuf";
import * as crypto from "crypto.crypto";
import * as channel from "channel";
import * as node from "node";
import * as nodedb from "nodedb";
import * as timers from "timers";

const ADDRESS = "224.0.0.69";
const PORT = 4403;

const SAVE_INTERVAL = 19 * 60; // 19 minutes

const BITFIELD_MQTT_OKAY = 1;
const TRANSPORT_MECHANISM_MULTICAST_UDP = 6;
const MAX_TEXT_MESSAGE_LENGTH = 200;

let s = null;

const portnum2Proto = {};
const proto2Portnum = {};
const protos = {};

export function registerProto(name, portnum, decode)
{
    protobuf.registerProto(protos, name, decode);
    if (portnum) {
        portnum2Proto[portnum] = name;
        proto2Portnum[name] = portnum;
    }
};

let sharedKeys = {};

function getSharedKey(priv, pub)
{
    const hkey = `${priv}${pub}`;
    let sharedkey = sharedKeys[hkey];
    if (!sharedkey) {
        sharedkey = crypto.getSharedKey(priv, pub);
        sharedKeys[hkey] = sharedkey;
    }
    return sharedkey;
}

function loadSharedKeys()
{
    const data = platform.load("meshtastic.sharedkeys");
    if (data) {
        sharedKeys = data.sharedKeys;
    }
}

function saveSharedKeys()
{
    platform.store("meshtastic.sharedkeys", {
        sharedKeys: sharedKeys
    });
}

function sendDirect(msg)
{
    return node.fromMe(msg) && !node.isBroadcast(msg) && (!msg.namekey || channel.isDirect(msg.namekey));
}

function recvDirect(msg)
{
    return node.forMe(msg) && !msg.channel;
}

function decodePacketData(msg)
{
    if (msg.decoded) {
        const data = protobuf.decode(protos, "data", msg.decoded);
        if (data && data.portnum !== null && data.payload && data.bitfield !== null) {
            delete msg.decoded;
            if (data.portnum === 1) {
                data.text_message = data.payload;
                delete data.payload;
                msg.data = data;
                return msg;
            }
            const protoname = portnum2Proto[`${data.portnum}`];
            if (protoname) {
                data[protoname] = protobuf.decode(protos, protoname, data.payload);
                if (data[protoname]) {
                    delete data.payload;
                    msg.data = data;
                    return msg;
                }
            }
        }
    }
    return null;
}

function decodePacket(pkt)
{
    const msg = protobuf.decode(protos, "packet", pkt);
    // Set the hop_limit to 1 to prevent this from being routed back out to meshtastic or meshcore
    msg.hop_limit = 1;
    msg.transport = "meshtastic";
    if (!msg.encrypted) {
        return decodePacketData(msg);
    }
    if (recvDirect(msg)) {
        const frompublic = nodedb.getNode(msg.from)?.nodeinfo?.public_key;
        const toprivate = node.toMe(msg) ? node.getInfo().private_key : platform.getTargetById(msg.to)?.private_key;
        if (frompublic && toprivate) {
            const sharedkey = getSharedKey(toprivate, frompublic);
            const hash = crypto.sha256hash(sharedkey);
            const ciphertext = substr(msg.encrypted, 0, -12);
            const auth = substr(msg.encrypted, -12, 8);
            const xnonce = substr(msg.encrypted, -4);
            msg.decoded = crypto.decryptCCM(msg.from, msg.id, hash, ciphertext, xnonce, auth);
            msg.namekey = nodedb.namekey(msg.from);
            if (decodePacketData(msg)) {
                delete msg.encrypted;
                return msg;
            }
        }
    }
    else {
        const hashchannels = channel.getChannelsByMeshtasticHash(msg.channel);
        if (hashchannels) {
            for (let i = 0; i < length(hashchannels); i++) {
                const chan = hashchannels[i];
                msg.decoded = crypto.decryptCTR(msg.from, msg.id, chan.symmetrickey, msg.encrypted);
                msg.namekey = chan.namekey;
                if (decodePacketData(msg)) {
                    delete msg.encrypted;
                    return msg;
                }
            }
        }
    }
    return null;
}

function encodePacket(msg)
{
    const direct = sendDirect(msg);
    const data = msg.data;
    if (data.text_message) {
        data.portnum = 1;
        data.payload = substr(data.text_message, 0, MAX_TEXT_MESSAGE_LENGTH);
        delete data.text_message;
    }
    else {
        for (let protoname in proto2Portnum) {
            if (data[protoname]) {
                data.portnum = proto2Portnum[protoname];
                data.payload = protobuf.encode(protos, protoname, data[protoname]);
                delete data[protoname];
                break;
            }
        }
    }
    if (!data.payload) {
        return null;
    }
    msg.decoded = protobuf.encode(protos, "data", msg.data);
    delete msg.data;
    if (direct) {
        delete msg.channel;
        const topublic = nodedb.getNode(msg.to)?.nodeinfo?.public_key;
        const fromprivate = node.fromMe(msg) ? node.getInfo().private_key : platform.getTargetById(msg.from)?.private_key;
        if (topublic && fromprivate) {
            const sharedkey = getSharedKey(fromprivate, topublic);
            const hash = crypto.sha256hash(sharedkey);
            const xnonce = struct.pack("4B", math.rand() & 255, math.rand() & 255, math.rand() & 255, math.rand() & 255);
            msg.encrypted = crypto.encryptCCM(msg.from, msg.id, hash, msg.decoded, xnonce, 8) + xnonce;
            delete msg.decoded;
            return protobuf.encode(protos, "packet", msg);
        }
    }
    else {
        const chan = channel.getChannelByNameKey(msg.namekey);
        if (chan) {
            msg.encrypted = crypto.encryptCTR(msg.from, msg.id, chan.symmetrickey, msg.decoded);
            delete msg.decoded;
            return protobuf.encode(protos, "packet", msg);
        }
    }
    return null;
}

export function setup(config)
{
    if (!config.meshtastic) {
        return;
    }
    const address = config.meshtastic.address;
    s = socket.create(socket.AF_INET, socket.SOCK_DGRAM, 0);
    s.bind({
        port: PORT
    });
    if (!address) {
        s.setopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, {
            multiaddr: ADDRESS
        });
    }
    else {
        s.setopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, {
            address: address
        });
        s.setopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, {
            address: address,
            multiaddr: ADDRESS
        });
    }
    s.setopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 0);
    s.listen();

    loadSharedKeys();

    timers.setInterval("meshtastic", SAVE_INTERVAL);
};

export function shutdown()
{
    saveSharedKeys();
};

export function handle()
{
    return s;
};

function makeNativeMsg(data)
{
    return decodePacket(data);
}

function makeMeshtasticMsg(msg)
{
    if (node.isBroadcast(msg)) {
        const chan = channel.getChannelByNameKey(msg.namekey);
        if (!chan) {
            return null;
        }
        msg.channel = chan.meshtastichash;
    }
    msg.rx_snr = 0;
    msg.rx_rssi = 0;
    msg.relay_node = msg.from & 255;
    msg.transport_mechanism = TRANSPORT_MECHANISM_MULTICAST_UDP;
    msg.data.bitfield = BITFIELD_MQTT_OKAY;
    return encodePacket(msg);
}

export function recv()
{
    return makeNativeMsg(s.recvmsg(512).data);
};

export function send(msg)
{
    if (s !== null) {
        const pkt = makeMeshtasticMsg(msg);
        if (pkt) {
            const r = s.send(pkt, 0, {
                address: ADDRESS,
                port: PORT
            });
            if (r == null) {
                DEBUG0("meshtastic:send error: %s\n", socket.error());
            }
        }
    }
};

export function tick()
{
     if (timers.tick("meshtastic")) {
        saveSharedKeys();
    }
};

export function process(msg)
{
};
