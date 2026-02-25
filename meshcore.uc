import * as socket from "socket";
import * as struct from "struct";
import * as channel from "channel";
import * as node from "node";
import * as nodedb from "nodedb";
import * as crypto from "crypto.crypto";
import * as timers from "timers";

// =====
// NOTES
// =====
//
// Bridge packets:
//
// Packets arrive from the bridge in the form they have just arrived on the bridge devices, before any processing
// Similarly, sent packets sent to the bridge appear on the bridge device as if they've just been received by the radio.
// For arriving packets, this means for non-flood routing, the packet will had the bridge's hash as the first part of the
// path as it's not yet been removed by the bridge (as it would if it was routing it to use).
//
// Channels:
//
// Public - 8b3387e9c5cdea6ac9e5edbaa115cd72 - izOH6cXN6mrJ5e26oRXNcg==
// #NAME -> sha256(#NAME)[0..15]
//

const ADDRESS = "224.0.0.69";
const PORT = 4402;

const SAVE_INTERVAL = 19 * 60; // 19 minutes
const ACK_INTERVAL = 60; // 1 minute

const HW_MESHCORE = 253;

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

const TEXT_TYPE_PLAIN = 0x00;
const TEXT_TYPE_CLI = 0x01;
const TEXT_TYPE_SIGNED = 0x02;

let s = null;
let bridge = ADDRESS;
let bridgeHash = null;

let sharedKeys = {};
let xPriv = {};
let xPub = {};
const recentKeys = {};
const pendingAcks = {};

function getSharedKey(priv, pub)
{
    const hkey = `${priv}${pub}`;
    let sharedkey = sharedKeys[hkey];
    if (!sharedkey) {
        let xpriv = xPriv[priv];
        if (!xpriv) {
            xpriv = crypto.ed25519_privkey_to_x25519(priv);
            xPriv[priv] = xpriv;
        }
        let xpub = xPub[pub];
        if (!xpub) {
            xpub = crypto.ed25519_pubkey_to_x25519(pub);
            xPub[pub] = xpub;
        }
        sharedkey = struct.unpack("32B", crypto.getSharedKey(xpriv, xpub));
        sharedKeys[hkey] = sharedkey;
    }
    return sharedkey;
}

function loadSharedKeys()
{
    const data = platform.load("meshcore.sharedkeys");
    if (data) {
        sharedKeys = data.sharedKeys;
        xPriv = data.xPriv;
        xPub = data.xPub;
    }
}

function saveSharedKeys()
{
    platform.store("meshcore.sharedkeys", {
        sharedKeys: sharedKeys,
        xPriv: xPriv,
        xPub: xPub
    });
}

function getRecentKeys(fromhash, tohash)
{
    return recentKeys[`${fromhash}:${tohash}`]
}

function addRecentKey(fromhash, tohash, from, to, sharedkey)
{
    const hkey = `${fromhash}:${tohash}`;
    const rkey = `${tohash}:${fromhash}`;
    push(recentKeys[hkey] ?? (recentKeys[hkey] = []), { from: from, to: to, key: sharedkey });
    push(recentKeys[rkey] ?? (recentKeys[rkey] = []), { from: to, to: from, key: sharedkey });
}

function addToAckQ(to, from, id, checksum)
{
    pendingAcks[struct.pack("4B", ...checksum)] = { to: to, from: from, id: id, checksum: checksum, when: time(), retry: 0 };
}

function ackAck(checksum)
{
    const ack = pendingAcks[checksum];
    if (ack) {
        delete pendingAcks[checksum];
    }
    return ack;
}

function processAcks()
{
    const when = time() - ACK_INTERVAL;
    for (let k in pendingAcks) {
        if (pendingAcks[k].when < when) {
            delete pendingAcks[k];
        }
    }
}

export function setup(config)
{
    if (!config.meshcore) {
        return;
    }
    const address = config.meshcore.address;
    if (config.meshcore.bridge) {
        bridge = config.meshcore.bridge;
    }
    bridgeHash = config.meshcore.bridgehash;
    if (bridgeHash === null) {
        print("Missing bridge hash - disabling direct routing\n");
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

    loadSharedKeys();

    timers.setInterval("meshcore.save", SAVE_INTERVAL);
    timers.setInterval("meshcore.acks", ACK_INTERVAL);
};

export function shutdown()
{
    saveSharedKeys();
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
        from: node.UNKNOWN,
        to: node.UNKNOWN,
        // Set the hop_limit to 1 to prevent this from being routed back out to meshcore or meshtastic
        hop_limit: 1,
        data: {},
        transport: "meshcore"
    };
    const header = ord(pkt, offset);
    offset++;
    switch (header & 0x03) {
        case ROUTE_TYPE_TRANSPORT_FLOOD:
            msg.flood = true;
            msg.to = node.BROADCAST;
            msg.transport_codes = struct.unpack("<HH", pkt, offset);
            offset += 4;
            break;
        case ROUTE_TYPE_FLOOD:
            msg.flood = true;
            msg.to = node.BROADCAST;
            break;
        case ROUTE_TYPE_DIRECT:
            msg.flood = false;
            break;
        case ROUTE_TYPE_TRANSPORT_DIRECT:
            msg.flood = false;
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
    const path = substr(pkt, offset + 1, pathlen);
    offset += pathlen + 1;

    if (msg.flood) {
        if (bridgeHash !== null) {
            msg.path = path + chr(bridgeHash);
        }
    }
    else {
        // pathlen == 0: We are the destination for this packet. We may not be the target because of the 8-bit hash thing.
        // pathlen == bridge: We are the last hop on the path before the final destination is reached.
        if (!(pathlen === 0 || (pathlen === 1 && ord(path) === bridgeHash))) {
            // Otherwise, not for us.
            return null;
        }
    }

    msg.pkthash = crypto.sha256hash(chr(type) + (type === PAYLOAD_TYPE_TRACE ? msg.path : "") + substr(pkt, offset));
    msg.id = (msg.pkthash[0] << 24) | (msg.pkthash[1] << 16) + (msg.pkthash[2] << 8) + msg.pkthash[3];

    switch (type) {
        case PAYLOAD_TYPE_PATH:
        case PAYLOAD_TYPE_REQ:
        case PAYLOAD_TYPE_RESPONSE:
        case PAYLOAD_TYPE_TXT_MSG:
        {
            const tohash = ord(pkt, offset);
            const fromhash = ord(pkt, offset + 1);
            const mac = struct.unpack("2B", pkt, offset + 2);
            const encrypted = substr(pkt, offset + 4);

            let secretkey = null;
            let fnodeid = null;
            let tnodeid = null;
            const me = node.getInfo();

            const recents = getRecentKeys(fromhash, tohash);
            if (recents) {
                for (let i = 0; i < length(recents); i++) {
                    const recent = recents[i];
                    const hmac = crypto.sha256hmac(recent.key, encrypted);
                    if (hmac[0] === mac[0] && hmac[1] === mac[1]) {
                        secretkey = recent.key;
                        fnodeid = recent.from;
                        tnodeid = recent.to;
                        break;
                    }
                }
            }
            if (!secretkey) {
                const fromnodes = nodedb.getNodesByPublickeyHash(fromhash, false);
                const tonodes = nodedb.getNodesByPublickeyHash(tohash, true);
                if (!me.is_unmessagable && node.getMeshcoreHash() === tohash) {
                    push(tonodes, {
                        me: true,
                        id: node.id(),
                        nodeinfo: me
                    });
                }
                for (let i = 0; i < length(fromnodes) && !secretkey; i++) {
                    const fnode = fromnodes[i];
                    if (!fnode.nodeinfo.is_unmessagable) {
                        const frompublic = fnode.nodeinfo.mc_public_key;
                        for (let j = 0; j < length(tonodes); j++) {
                            const tnode = tonodes[j];
                            if (!tnode.nodeinfo.is_unmessagable) {
                                const toprivate = tnode.me ? tnode.nodeinfo.private_key : platform.getTargetById(tnode.id)?.private_key;
                                if (toprivate) {
                                    const key = getSharedKey(toprivate, frompublic);
                                    const hmac = crypto.sha256hmac(key, encrypted);
                                    if (hmac[0] === mac[0] && hmac[1] === mac[1]) {
                                        secretkey = key;
                                        fnodeid = fnode.id;
                                        tnodeid = tnode.id;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
                if (secretkey) {
                    addRecentKey(fromhash, tohash, fnodeid, tnodeid, secretkey);
                }
            }
            if (secretkey) {
                msg.to = tnodeid;
                msg.from = fnodeid;
                const plain = crypto.decryptECB(secretkey, encrypted);
                switch (type) {
                    case PAYLOAD_TYPE_TXT_MSG:
                    {
                        const timestampAndFlags = struct.unpack("<IB", plain);
                        msg.rx_time = timestampAndFlags[0];
                        msg.attempt = timestampAndFlags[1] & 3;
                        let offset = 5;
                        switch (timestampAndFlags[1] & 3) {
                            case TEXT_TYPE_PLAIN:
                                break;
                            case TEXT_TYPE_SIGNED:
                                // Skip senders public key prefix verification
                                offset += 4;
                                break;
                            case TEXT_TYPE_CLI:
                            default:
                                return null;
                        }
                        msg.want_ack = true;
                        msg.namekey = nodedb.namekey(fnodeid);
                        msg.data.text_message = rtrim(substr(plain, offset), "\u0000");
                        msg.data.checksum = slice(crypto.sha256hash(substr(plain, 0, offset) + msg.data.text_message + nodedb.getNode(fnodeid).nodeinfo.mc_public_key), 0, 4);
                        return msg;
                    }
                    case PAYLOAD_TYPE_PATH:
                    {
                        let offset = 1;
                        const pathlen = ord(plain);
                        const path = substr(plain, offset, pathlen);
                        offset += pathlen;
                        if (offset < length(plain)) {
                            switch (ord(plain, offset)) {
                                case PAYLOAD_TYPE_ACK:
                                {
                                    const ack = ackAck(substr(plain, offset + 1, offset + 5));
                                    if (ack) {
                                        msg.to = ack.from;
                                        msg.from = ack.to;
                                        msg.data.routing = { error_reason: 0, checksum: ack.checksum };
                                        msg.data.request_id = ack.id;
                                        msg.returned_path = path;
                                        return msg;
                                    }
                                    break;
                                }
                                default:
                                    break;
                            }
                        }
                        break;
                    }
                    default:
                        break;
                }
            }
            return null;
        }
        case PAYLOAD_TYPE_ADVERT:
        {
            const advert = {};
            msg.data.advert = advert;
            advert.hw_model = HW_MESHCORE;
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
                    advert.is_unmessagable = false;
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
        case PAYLOAD_TYPE_ACK:
        {
            const ack = ackAck(substr(pkt, offset, offset + 4));
            if (ack) {
                msg.to = ack.from;
                msg.from = ack.to;
                msg.data.routing = { error_reason: 0, checksum: ack.checksum };
                msg.data.request_id = ack.id;
                return msg;
            }
            break;
        }
        case PAYLOAD_TYPE_GRP_DATA:
        case PAYLOAD_TYPE_ANON_REQ:
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
        DEBUG0("meshcore:makeNativeMsg error: %s\n%s\n", e, e.stacktrace);
        return null;
    }
}

function makePktHeader(type, path)
{
    if (path && bridgeHash !== null) {
        return chr((PAYLOAD_VER_1 << 6) | (type << 2) | ROUTE_TYPE_DIRECT) + chr(length(path)) + path;
    }
    // If we dont have a path, create a flood route building a new path.
    return chr((PAYLOAD_VER_1 << 6) | (type << 2) | ROUTE_TYPE_FLOOD) + chr(0);
}

function getDirectSendKey(msg)
{
    const topublic = nodedb.getNode(msg.to)?.nodeinfo?.mc_public_key;
    const fromprivate = node.fromMe(msg) ? node.getInfo().private_key : platform.getTargetById(msg.from)?.private_key;
    const frompublic = nodedb.getNode(msg.from)?.nodeinfo?.mc_public_key;
    if (topublic && fromprivate && frompublic) {
        const tohash = ord(topublic);
        const fromhash = ord(frompublic);
        const sharedkey = getSharedKey(fromprivate, topublic);
        const recents = getRecentKeys(fromhash, tohash);
        if (recents) {
            let found = false;
            for (let i = 0; i < length(recents); i++) {
                if (recents[i].key === sharedkey) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                addRecentKey(fromhash, tohash, msg.from, msg.to, sharedkey);
            }
        }
        return {
            topublic: topublic,
            fromprivate: fromprivate,
            frompublic: frompublic,
            tohash: tohash,
            fromhash: fromhash,
            sharedkey: sharedkey
        };
    }
    return null;
}

function pad(buf)
{
    while (length(buf) % 32 != 0) {
        buf += "\u0000";
    }
    return buf;
}

function makeMeshcoreMsg(msg)
{
    let pkt = null;

    if (node.isBroadcast(msg)) {
        msg.path = null;
    }
    else {
        msg.path = nodedb.getNode(msg.to, false)?.path;
    }

    if (msg.data?.advert) {
        const advert = msg.data.advert;

        let type = ADV_LATLON_MASK | ADV_NAME_MASK;
        switch (advert.role) {
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

        pkt = makePktHeader(PAYLOAD_TYPE_ADVERT, null) + advert.public_key + struct.pack("<I", msg.rx_time) + signature + appdata;
    }
    else if (msg.data?.text_message) {
        if (sendDirect(msg)) {
            const keys = getDirectSendKey(msg);
            if (keys) {
                const plain = struct.pack("<IB", msg.rx_time, 0) + substr(msg.data.text_message, 0, MAX_TEXT_MESSAGE_LENGTH);
                addToAckQ(msg.to, msg.from, msg.id, slice(crypto.sha256hash(plain + keys.frompublic), 0, 4));

                const encrypted = crypto.encryptECB(keys.sharedkey, pad(plain));
                const hmac = crypto.sha256hmac(keys.sharedkey, encrypted);

                pkt = makePktHeader(PAYLOAD_TYPE_TXT_MSG, msg.path) + struct.pack("4B", keys.tohash, keys.fromhash, hmac[0], hmac[1]) + encrypted;
            }
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
                const plain = pad(struct.pack("<IB", msg.rx_time, 0) + substr(text, 0, MAX_TEXT_MESSAGE_LENGTH));
                const encrypted = crypto.encryptECB(chan.symmetrickey, plain);
                const hmac = crypto.sha256hmac(chan.symmetrickey, encrypted);

                pkt = makePktHeader(PAYLOAD_TYPE_GRP_TXT, null) + struct.pack("3B", chan.meshcorehash, hmac[0], hmac[1]) + encrypted;
            }
        }
    }
    else if (msg.data?.routing) {
        if (msg.data.routing.error_reason === 0 && msg.data.routing.checksum) {
            if (msg.path) {
                const keys = getDirectSendKey(msg);
                if (keys) {
                    const plain = chr(length(msg.path)) + msg.path + chr(PAYLOAD_TYPE_ACK) + struct.pack("4B", ...msg.data.routing.checksum);

                    const encrypted = crypto.encryptECB(keys.sharedkey, pad(plain));
                    const hmac = crypto.sha256hmac(keys.sharedkey, encrypted);

                    pkt = makePktHeader(PAYLOAD_TYPE_PATH, msg.path) + struct.pack("4B", keys.tohash, keys.fromhash, hmac[0], hmac[1]) + encrypted;
                }
            }
            if (!pkt) {
                pkt = makePktHeader(PAYLOAD_TYPE_ACK, null) + struct.pack("4B", ...msg.data.routing.checksum);
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

export function tick()
{
    if (timers.tick("meshcore.save")) {
        saveSharedKeys();
    }
    if (timers.tick("meshcore.acks")) {
        processAcks();
    }
};

export function process(msg)
{
};
