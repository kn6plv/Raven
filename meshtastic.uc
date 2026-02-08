import * as socket from "socket";
import * as math from "math";
import * as struct from "struct";
import * as protobuf from "protobuf";
import * as crypto from "crypto.crypto";
import * as channel from "channel";
import * as node from "node";
import * as nodedb from "nodedb";

const ADDRESS = "224.0.0.69";
const PORT = 4403;

const BITFIELD_MQTT_OKAY = 1;
const TRANSPORT_MECHANISM_MULTICAST_UDP = 6;
const MAX_TEXT_MESSAGE_LENGTH = 200;

let s = null;

/*
 * Known port numbers
 *
 *  2 - hardware
 *  3 - position
 *  4 - nodeinfo
 *  5 - routing
 *  6 - admin
 *  7 - compressed
 *  8 - waypoint
 *  9 - audio
 * 10 - detectionsensor
 * 11 - alert
 * 12 - keyverification
 * 32 - reply
 * 33 - iptunnel
 * 34 - paxcounter
 * 64 - serial
 * 65 - storeandforward
 * 66 - rangetest
 * 67 - telemetry
 * 68 - zps
 * 69 - simulator
 * 70 - traceroute
 * 71 - neighborinfo
 * 72 - atak
 * 73 - mapreport
 * 74 - powerstress
 * 76 - reticulumtunnel
 * 77 - cayenne
 * 257 - atakforwarder
 */

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

registerProto(
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
registerProto(
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

const sharedKeys = {};

function getSharedKey(priv, pub)
{
    const hkey = `${crypto.pKeyToString(priv)}${pub}`;
    let sharedkey = sharedKeys[hkey];
    if (!sharedkey) {
        sharedkey = crypto.getSharedKey(priv, crypto.stringToPKey(pub));
        sharedKeys[hkey] = sharedkey;
    }
    return sharedkey;
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
    if (!msg.encrypted) {
        return decodePacketData(msg);
    }
    if (recvDirect(msg)) {
        const frompublic = nodedb.getNode(msg.from)?.nodeinfo?.public_key;
        const toprivate = node.toMe(msg) ? node.getInfo().private_key : platform.getTargetById(msg.to)?.key;
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
        const hashchannels = channel.getChannelsByHash(msg.channel);
        if (hashchannels) {
            for (let i = 0; i < length(hashchannels); i++) {
                const chan = hashchannels[i];
                msg.decoded = crypto.decryptCTR(msg.from, msg.id, chan.crypto, msg.encrypted);
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
        const fromprivate = node.fromMe(msg) ? node.getInfo().private_key : platform.getTargetById(msg.from)?.key;
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
            msg.encrypted = crypto.encryptCTR(msg.from, msg.id, chan.crypto, msg.decoded);
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
};

export function handle()
{
    return s;
};

function makeNativeMsg(data)
{
    const msg = decodePacket(data);
    if (msg) {
        msg.transport = "meshtastic";
    }
    return msg;
}

function makeMeshtasticMsg(msg)
{
    if (node.isBroadcast(msg)) {
        const chan = channel.getChannelByNameKey(msg.namekey);
        if (!chan) {
            return null;
        }
        msg.channel = chan.hash;
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
