import * as struct from "struct";
import * as math from "math";

export function registerProto(protos, name, proto)
{
    if (!protos.encode) {
        protos.encode = {};
        protos.decode = {};
    }
    const decode = {};
    const encode = {};

    for (let id in proto) {
        const keys = split(proto[id], " ");
        switch (length(keys)) {
            case 4:
                if (keys[0] === "repeated") {
                    if (keys[1] === "unpacked") {
                        decode[id] = { name: keys[3], repeatedunpacked: keys[2] };
                        encode[keys[2]] = { id: int(id), repeatedunpacked: keys[2] };
                    }
                    else if (keys[1] === "packed") {
                        decode[id] = { name: keys[3], repeatedpacked: keys[2] };
                        encode[keys[2]] = { id: int(id), repeatedpacked: keys[2] };
                    }
                }
                break;
            case 3:
                switch (keys[0]) {
                    case "repeated":
                        decode[id] = { name: keys[2], repeatedpacked: keys[1] };
                        encode[keys[2]] = { id: int(id), repeatedpacked: keys[1] };
                        break;
                    case "proto":
                        decode[id] = { name: keys[2], proto: keys[1] };
                        encode[keys[2]] = { id: int(id), proto: keys[1] };
                        break;
                    default:
                        break;
                }
                break;
            case 2:
                decode[id] = { name: keys[1], type: keys[0] };
                encode[keys[1]] = { id: int(id), type: keys[0] };
                break;
            case 1:
                decode[id] = { name: keys[0], type: "varint" };
                encode[keys[0]] = { id: int(id), type: "varint" };
                break;
            default:
                break;
        }
    }

    protos.decode[name] = decode;
    protos.encode[name] = encode;
};

export function decode(protos, name, buf)
{
    const proto = protos.decode[name] ?? {};
    const r = {};
    const len = length(buf);
    let i = 0;

    function varint()
    {
        let d = 0;
        let s = 0;
        while (i < len) {
            const n = ord(buf, i++);
            d += (n & 127) << s;
            if (n < 128) {
                return d;
            }
            s += 7;
        }
        return null;
    }

    while (i < len) {
        const v = varint();
        if (v === null) {
            return null;
        }
        let d = null;
        switch (v & 7) {
            case 0: // 
            {
                d = varint();
                break;
            }
            case 1: // I64
                d = ord(buf, i) + (ord(buf, i + 1) << 8) + (ord(buf, i + 2) << 16) + (ord(buf, i + 3) << 24) + (ord(buf, i) << 32) + (ord(buf, i + 1) << 40) + (ord(buf, i + 2) << 48) + (ord(buf, i + 3) << 56);
                i += 8;
                break;
            case 2: // LEN
            {
                const l = varint();
                d = substr(buf, i, l);
                i += l;
                break;
            }
            case 5: // I32
                d = ord(buf, i) + (ord(buf, i + 1) << 8) + (ord(buf, i + 2) << 16) + (ord(buf, i + 3) << 24);
                i += 4;
                break;
            default:
                return null;
        }
        if (d === null) {
            return null;
        }
        const vi = `${v >> 3}`;
        let k = proto[vi]?.name;
        if (k) {
            if (proto[vi].proto) {
                if (type(d) === "string") {
                    d = decode(protos, proto[vi].proto, d);
                }
            }
            else if (proto[vi].repeatedunpacked) {
                let v = d;
                d = r[k] || [];
                if (type(v) === "string") {
                    switch (proto[vi].repeatedunpacked) {
                        case "bytes":
                        case "string":
                            break;
                        default:
                            v = decode(protos, proto[vi].repeatedunpacked, v);
                            break;
                    }
                }
                if (v !== null) {
                    push(d, v);
                }
            }
            else if (proto[vi].repeatedpacked) {
                if (type(d) === "string") {
                    switch (proto[vi].repeatedpacked) {
                        case "fixed32":
                            d = struct.unpack(sprintf("<%dI", length(d) / 4), d);
                            break;
                        case "sfixed32":
                            d = struct.unpack(sprintf("<%di", length(d) / 4), d);
                            break;
                        case "fixed64":
                            d = struct.unpack(sprintf("<%dQ", length(d) / 8), d);
                            break;
                        case "sfixed64":
                            d = struct.unpack(sprintf("<%dq", length(d) / 8), d);
                            break;
                        case "float":
                            d = struct.unpack(sprintf("<%df", length(d) / 4), d);
                            break;
                        case "double":
                            d = struct.unpack(sprintf("<%dd", length(d) / 8), d);
                            break;
                        case "int32":
                        case "uint32":
                        case "int64":
                        case "uint64":
                        case "sint32":
                        case "sint64":
                        case "enum":
                        {
                            const buf = d;
                            const len = length(buf);
                            let i = 0;
                            d = [];
                            while (i < len) {
                                let v = 0;
                                let s = 0;
                                while (i < len) {
                                    const n = ord(buf, i++);
                                    v += (n & 127) << s;
                                    if (n < 128) {
                                        break;
                                    }
                                    s += 7;
                                }
                                switch (proto[vi].repeatedpacked) {
                                    case "int32":
                                    case "int64":
                                        if (v <= 0xffffffff) {
                                            v = struct.unpack("i", struct.pack("I", v))[0];
                                        }
                                        else {
                                            v = struct.unpack("q", struct.pack("Q", v))[0];
                                        }
                                        break;
                                    case "sint32":
                                    case "sint64":
                                        if (v & 1) {
                                            v = -(v + 1) >> 1;
                                        }
                                        else {
                                            v >>= 1;
                                        }
                                        break;
                                    default:
                                        break;
                                }
                                push(d, v);
                            }
                            break;
                        }
                        default:
                            break;
                    }
                }
            }
            else if (proto[vi].type) {
                switch (proto[vi].type) {
                    case "bool":
                        d = !!d;
                        break;
                    case "float":
                    case "double":
                        if (d <= 0xffffffff) {
                            d = struct.unpack("f", struct.pack("I", d))[0];
                        }
                        else {
                            d = struct.unpack("d", struct.pack("Q", d))[0];
                        }
                        break;
                    case "int32":
                    case "int64":
                    case "sfixed32":
                    case "sfixed64":
                        if (d <= 0xffffffff) {
                            d = struct.unpack("i", struct.pack("I", d))[0];
                        }
                        else {
                            d = struct.unpack("q", struct.pack("Q", d))[0];
                        }
                        break;
                    case "sint32":
                    case "sint64":
                        if (d & 1) {
                            d = -(d + 1) >> 1;
                        }
                        else {
                            d >>= 1;
                        }
                        break;
                    case "varint":
                    case "uint32":
                    case "uint64":
                    case "fixed32":
                    case "fixed64":
                    case "enum":
                    case "bytes":
                    case "string":
                    default:
                        break;
                }
            }
        }
        else {
            k = vi;
        }
        r[k] = d;
    }
    return r;
};

export function encode(protos, name, data)
{
    const proto = protos.encode[name];
    if (!proto) {
        print(`Missing proto ${name}\n`);
        return null;
    }

    function varint(v)
    {
        let b = "";
        if (v < 0) {
            b += chr(128 | (v & 127));
            v = (v >> 7) & 0x1fffffffffffffff;
        }
        for (;;) {
            if (v < 128) {
                b += chr(v);
                return b;
            }
            b += chr(128 | (v & 127));
            v >>= 7;
        }
    }

    function tag(id, type)
    {
        return varint(id << 3 | type);
    }

    const r = [];
    for (let k in data) {
        const p = proto[k];
        let v = data[k];
        let d = null;
        if (!p) {
            //print(`Missing proto ${name}:${k}\n`);
        }
        else if (p.proto) {
            const buf = encode(protos, p.proto, v);
            d = tag(p.id, 2) + varint(length(buf)) + buf;
        }
        else if (p.repeatedunpacked) {
            d = "";
            for (let i = 0; i < length(v); i++) {
                const vi = v[i];
                if (type(vi) === "string") {
                    let buf = null;
                    switch (p.repeatedunpacked) {
                        case "bytes":
                        case "string":
                            buf = vi;
                            break;
                        default:
                            buf = encode(protos, p.repeatedunpacked, vi);
                            break;
                    }
                    if (buf !== null) {
                        d += tag(p.id, 2) + varint(length(buf)) + buf;
                    }
                }
                else {
                    switch (p.repeatedunpacked) {
                        case "varint":
                        case "uint32":
                        case "uint64":
                        case "int32":
                        case "int64":
                        case "enum":
                            d += tag(p.id, 0) + varint(vi);
                            break;
                        case "bool":
                            d += tag(p.id, 0) + varint(vi ? 1 : 0);
                            break;
                        case "sint32":
                        case "sint64":
                            if (v >= 0) {
                                v <<= 1;
                            }
                            else {
                                v = (math.abs(vi) << 1) - 1;
                            }
                            d += tag(p.id, 0) + varint(vi);
                            break;
                        case "float":
                            d += tag(p.id, 5) + struct.pack("<f", vi);
                            break;
                        case "double":
                            d += tag(p.id, 1) + struct.pack("<d", vi);
                            break;
                        case "fixed32":
                            d += tag(p.id, 5) + struct.pack("<I", vi);
                            break;
                        case "sfixed32":
                            d += tag(p.id, 5) + struct.pack("<i", vi);
                            break;
                        case "fixed64":
                            d += tag(p.id, 5) + struct.pack("<Q", vi);
                            break;
                        case "sfixed64":
                            d += tag(p.id, 1) + struct.pack("<q", vi);
                            break;
                        default:
                            break;
                    }
                }
            }
        }
        else if (p.repeatedpacked) {
            d = "";
            for (let i = 0; i < length(v); i++) {
                let vi = v[i];
                switch (p.repeatedpaced) {
                    case "varint":
                    case "uint32":
                    case "uint64":
                    case "int32":
                    case "int64":
                    case "enum":
                        d += varint(vi);
                        break;
                    case "bool":
                        d += varint(vi ? 1 : 0);
                        break;
                    case "sint32":
                    case "sint64":
                    {
                        if (vi >= 0) {
                            vi <<= 1;
                        }
                        else {
                            vi = (math.abs(vi) << 1) - 1;
                        }
                        d += varint(vi);
                        break;
                    }
                    case "float":
                        d += struct.pack("<f", vi);
                        break;
                    case "double":
                        d += struct.pack("<d", vi);
                        break;
                    case "fixed32":
                        d += struct.pack("<I", vi);
                        break;
                    case "sfixed32":
                        d += struct.pack("<i", vi);
                        break;
                    case "fixed64":
                        d += struct.pack("<Q", vi);
                        break;
                    case "sfixed64":
                        d += struct.pack("<q", vi);
                        break;
                    default:
                        break;
                }
            }
            d = tag(p.id, 2) + varint(length(d)) + d;
        }
        else if (p.type) {
            switch (p.type) {
                case "varint":
                case "uint32":
                case "uint64":
                case "int32":
                case "int64":
                case "enum":
                    d = tag(p.id, 0) + varint(v);
                    break;
                case "bool":
                    d = tag(p.id, 0) + varint(v ? 1 : 0);
                    break;
                case "sint32":
                case "sint64":
                    if (v >= 0) {
                        v <<= 1;
                    }
                    else {
                        v = (math.abs(v) << 1) - 1;
                    }
                    d = tag(p.id, 0) + varint(v);
                    break;
                case "float":
                    d = tag(p.id, 5) + struct.pack("<f", v);
                    break;
                case "double":
                    d = tag(p.id, 1) + struct.pack("<d", v);
                    break;
                case "fixed32":
                    d = tag(p.id, 5) + struct.pack("<I", v);
                    break;
                case "sfixed32":
                    d = tag(p.id, 5) + struct.pack("<i", v);
                    break;
                case "fixed64":
                    d = tag(p.id, 5) + struct.pack("<Q", v);
                    break;
                case "sfixed64":
                    d = tag(p.id, 1) + struct.pack("<q", v);
                    break;
                case "bytes":
                case "string":
                    d = tag(p.id, 2) + varint(length(v)) + v;
                    break;
                default:
                    break;
            }
        }
        if (d !== null) {
            r[p.id] = d;
        }
    }
    let b = "";
    for (let i = 0; i < length(r); i++) {
        if (r[i]) {
            b += r[i];
        }
    }
    return b;
};
