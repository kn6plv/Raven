import * as socket from "socket";
import * as struct from "struct";
import * as channel from "channel";
import * as node from "node";
import * as nodedb from "nodedb";
import * as crypto from "crypto.crypto";

// Public - 8b3387e9c5cdea6ac9e5edbaa115cd72 - izOH6cXN6mrJ5e26oRXNcg==
// #NAME -> sha256(#NAME)[0..15]

const ADDRESS = "224.0.0.69";
const PORT = 4402;

const HW_MESCORE = 253;

const MAX_TEXT_MESSAGE_LENGTH = 155;

const ROUTE_TYPE_TRANSPORT_FLOOD = 0x00;
const ROUTE_TYPE_FLOOD = 0x01;
const ROUTE_TYPE_DIRECT = 0x02;
const ROUTE_TYPE_TRANSPORT_DIRECT = 0x03;

const PAYLOAD_TYPE_REQ = 0x00;
const PAYLOAD_TYPE_RESPONSE = 0x01;
const PAYLOAD_TYPE_TXT_MSG = 0x02;
const PAYLOAD_TYPE_ACK = 0x03;
const PAYLOAD_TYPE_ADVERT = 0x04;
const PAYLOAD_TYPE_GRP_TXT = 0x05;
const PAYLOAD_TYPE_GRP_DATA = 0x06;
const PAYLOAD_TYPE_ANON_REQ = 0x07;
const PAYLOAD_TYPE_PATH = 0x08;
const PAYLOAD_TYPE_TRACE = 0x09;
const PAYLOAD_TYPE_MULTIPART = 0x0a;
const PAYLOAD_TYPE_CONTROL = 0x0b;
const PAYLOAD_TYPE_RAW_CUSTOM = 0x0f;

const PAYLOAD_VER_1 = 0x00;

const ADV_TYPE_NONE = 0;
const ADV_TYPE_CHAT = 1;
const ADV_TYPE_REPEATER = 2;
const ADV_TYPE_ROOM = 3;
const ADV_TYPE_SENSOR = 4;

const ADV_LATLON_MASK = 0x10;
const ADV_FEAT1_MASK = 0x20;
const ADV_FEAT2_MASK = 0x40;
const ADV_NAME_MASK = 0x80;

let s = null;
let bridge = ADDRESS;

export function setup(config)
{
    if (!config.meshcore) {
        return;
    }
    const address = config.meshcore.address;
    if (config.meshcore.bridge) {
        bridge = config.meshcore.bridge;
    }
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

function fletch16(data, offset, count)
{
    let sum1 = 0;
    let sum2 = 0;
    count += offset;
    for (let i = offset; i < count; i++) {
        sum1 = (sum1 + ord(data, i)) % 255;
        sum2 = (sum1 + sum2) % 255;
    }
    return (sum2 << 8) | sum1;
}

function sendDirect(msg)
{
    return node.fromMe(msg) && !node.isBroadcast(msg) && (!msg.namekey || channel.isDirect(msg.namekey));
}

function decodePacket(pkt)
{
    //print("decode ", pkt, "\n");
    let offset = 0;
    const msg = {
        data: {}
    };
    const header = ord(pkt, offset);
    offset++;
    switch (header & 0x03) {
        case ROUTE_TYPE_TRANSPORT_FLOOD:
            msg.route_type = "transport_flood";
            msg.to = node.BROADCAST;
            msg.transport_codes = struct.unpack("<HH", pkt, offset);
            offset += 4;
            break;
        case ROUTE_TYPE_FLOOD:
            msg.route_type = "flood";
            msg.to = node.BROADCAST;
            break;
        case ROUTE_TYPE_DIRECT:
            msg.route_type = "direct";
            break;
        case ROUTE_TYPE_TRANSPORT_DIRECT:
            msg.route_type = "transport_direct";
            msg.transport_codes = struct.unpack("<HH", pkt, offset);
            offset += 4;
            break;
        default:
            return null;
    }
    const type = (header >> 2) & 0x0F;
    switch ((header >> 6) & 0x03) {
        case PAYLOAD_VER_1:
            msg.version = "1";
            break;
        default:
            return null;
    }

    const pathlen = ord(pkt, offset);
    msg.path = substr(pkt, offset + 1, pathlen);
    offset += pathlen + 1;

    msg.pkthash = crypto.sha256hash(chr(type) + (type === PAYLOAD_TYPE_TRACE ? msg.path : "") + substr(pkt, offset));
    msg.id = (msg.pkthash[0] << 24) | (msg.pkthash[1] << 16) + (msg.pkthash[2] << 8) + msg.pkthash[3];

    switch (type) {
        case PAYLOAD_TYPE_REQ:
        case PAYLOAD_TYPE_RESPONSE:
        case PAYLOAD_TYPE_TXT_MSG:
        case PAYLOAD_TYPE_ACK:
            break;
        case PAYLOAD_TYPE_ADVERT:
        {
            const advert = {};
            msg.data.advert = advert;
            advert.hw_model = HW_MESCORE;
            advert.is_unmessagable = true;
            advert.public_key = substr(pkt, offset, 32);
            advert.timestamp = struct.unpack("<I", pkt, offset + 32)[0];
            const signature = substr(pkt, offset + 36, 64);
            offset += 100;

            const plain = advert.public_key + struct.pack("<I", advert.timestamp) + substr(pkt, offset);
            if (!crypto.verify(advert.public_key, plain, signature)) {
                return null;
            }

            const type = ord(pkt, offset);
            offset++;
            switch (type & 0x0f) {
                case ADV_TYPE_CHAT:
                    advert.role = node.ROLE_COMPANION;
                    break;
                case ADV_TYPE_REPEATER:
                    advert.role = node.ROLE_REPEATER;
                    break;
                case ADV_TYPE_ROOM:
                    advert.role = node.ROLE_ROOM;
                    break;
                case ADV_TYPE_SENSOR:
                    advert.role = node.ROLE_SENSOR;
                    break;
                case ADV_TYPE_NONE:
                default:
                    break;
            }
            if (type & ADV_LATLON_MASK) {
                const latlon = struct.unpack("<ii", pkt, offset);
                advert.position = {
                    latitude_i: latlon[0] * 10,
                    longitude_i: latlon[1] * 10
                };
                offset += 8;
            }
            if (type & ADV_FEAT1_MASK) {
                offset += 2;
            }
            if (type & ADV_FEAT2_MASK) {
                offset += 2;
            }
            if (type & ADV_NAME_MASK) {
                advert.name = substr(pkt, offset);
            }
            msg.from = nodedb.getNodeByPublickey(advert.public_key).id;
            return msg;
        }
        case PAYLOAD_TYPE_GRP_TXT:
        {
            const channelhash = ord(pkt, offset);
            const mac = struct.unpack("2B", pkt, offset + 1);
            const encrypted = substr(pkt, offset + 3);
            const hashchannels = channel.getChannelsByMeshcoreHash(channelhash);
            for (let i = 0; i < length(hashchannels); i++) {
                const key = hashchannels[i].symmetrickey;
                const hmac = crypto.sha256hmac(key, encrypted);
                if (hmac[0] === mac[0] && hmac[1] === mac[1]) {
                    const plain = crypto.decryptECB(key, encrypted);
                    const timestampAndFlags = struct.unpack("<IB", plain);
                    if (timestampAndFlags[1] !== 0) {
                        return null;
                    }
                    msg.namekey = hashchannels[i].namekey;
                    msg.rx_time = timestampAndFlags[0];
                    const fm = split(substr(plain, 5), ": ", 2);
                    msg.from = nodedb.getNodeByLongname(fm[0])?.id ?? node.UNKNOWN;
                    msg.data.text_message = rtrim(fm[1], "\u0000");
                    msg.data.text_from = fm[0];
                    return msg;
                }
            }
            break;
        }
        case PAYLOAD_TYPE_GRP_DATA:
        case PAYLOAD_TYPE_ANON_REQ:
        case PAYLOAD_TYPE_PATH:
        case PAYLOAD_TYPE_TRACE:
        case PAYLOAD_TYPE_MULTIPART:
        case PAYLOAD_TYPE_CONTROL:
        case PAYLOAD_TYPE_RAW_CUSTOM:
        default:
            break;
    }

    return null;
}

function makeNativeMsg(data)
{
    const header = struct.unpack(">HH", data);
    const chksum = struct.unpack(">H", data, length(data) - 2);
    if (header[0] !== 0xC03E || header[1] + 6 !== length(data) || chksum[0] !== fletch16(data, 4, header[1])) {
        return null;
    }
    try {
        return decodePacket(substr(data, 4, length(data) - 6));
    }
    catch (e) {
        DEBUG0("meshcore:makeNativeMsg error: %s\n", e.stacktrace);
        return null;
    }
}

function makeMeshcoreMsg(msg)
{
    let pkt = null;

    if (msg.data?.advert) {
        const advert = msg.data.advert;

        let type = ADV_LATLON_MASK | ADV_NAME_MASK;
        switch (advert.type) {
            case node.ROLE_REPEATER:
            case node.ROLE_CLIENT:
                type |= ADV_TYPE_REPEATER;
                break;
            case node.ROLE_ROOM:
                type |= ADV_TYPE_ROOM;
                break;
            case node.ROLE_SENSOR:
                type |= ADV_TYPE_SENSOR;
                break;
             case node.ROLE_CLIENT_MUTE:
             case node.ROLE_COMPANION:
             default:
                type |= ADV_TYPE_CHAT;
                break;
        }
        const appdata = struct.pack("<Bii", type, advert.position.latitude_i / 10, advert.position.longitude_i / 10) + advert.name;

        const plain = advert.public_key + struct.pack("<I", msg.rx_time) + appdata;
        const fromprivate = node.fromMe(msg) ? node.getInfo().private_key : platform.getTargetById(msg.from)?.private_key;
        const signature = crypto.sign(fromprivate, advert.public_key, plain);

        pkt = struct.pack("2B", (PAYLOAD_VER_1 << 6) | (PAYLOAD_TYPE_ADVERT << 2) | ROUTE_TYPE_FLOOD, 0) +
            advert.public_key + struct.pack("<I", msg.rx_time) + signature + appdata;
    }
    else if (msg.data?.text_message) {
        if (sendDirect(msg)) {
            return null;
        }
        else {
            const chan = channel.getChannelByNameKey(msg.namekey);
            if (chan) {
                const name = nodedb.getNode(msg.from, false)?.nodeinfo?.long_name ?? msg.data.text_from ?? `${msg.from}`;
                let text = `${name}: ${msg.data.text_message}`;
                if (msg.data.reply_id) {
                    const reply = nodedb.getNode(msg.data.reply_id, false)?.nodeinfo?.long_name;
                    if (reply) {
                        text = `@[${reply}]${text}`;
                    }
                }
                let plain = struct.pack("<IB", msg.rx_time, 0) + substr(text, 0, MAX_TEXT_MESSAGE_LENGTH);
                while (length(plain) % 32 != 0) {
                    plain += "\u0000";
                }
                const encrypted = crypto.encryptECB(chan.symmetrickey, plain);
                const hmac = crypto.sha256hmac(chan.symmetrickey, encrypted);

                pkt = struct.pack("2B", (PAYLOAD_VER_1 << 6) | (PAYLOAD_TYPE_GRP_TXT << 2) | ROUTE_TYPE_FLOOD, 0) +
                    struct.pack("3B", chan.meshcorehash, ...hmac) + encrypted;
            }
        }
    }

    if (!pkt) {
        return null;
    }

    const len = length(pkt);
    return struct.pack(">HH", 0xC03E, len) + pkt + struct.pack(">H", fletch16(pkt, 0, len));
}

export function recv()
{
    return makeNativeMsg(s.recvmsg(512).data);
};

export function send(msg)
{
    if (s !== null) {
        const pkt = makeMeshcoreMsg(msg);
        if (pkt) {
            const r = s.send(pkt, 0, {
                address: bridge,
                port: PORT
            });
            if (r == null) {
                DEBUG0("meshcore:send error: %s\n", socket.error());
            }
        }
    }
};
