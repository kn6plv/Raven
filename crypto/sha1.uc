/*
 * A JavaScript implementation of the Secure Hash Algorithm, SHA-1, as defined
 * in FIPS 180-1
 * Version 2.2 Copyright Paul Johnston 2000 - 2009.
 * Other contributors: Greg Holt, Andrew Kepert, Ydnar, Lostinet
 * Distributed under the BSD License
 * See http://pajhome.org.uk/crypt/md5 for details.
 */


// Add integers, wrapping at 2^32. This uses 16-bit operations internally
// to work around bugs in some JS interpreters.
function _add(x, y) {
    let lsw = (x & 0xFFFF) + (y & 0xFFFF);
    let msw = (x >> 16) + (y >> 16) + (lsw >> 16);
    return 0xffffffff & ((msw << 16) | (lsw & 0xFFFF));
}

/*
 * Bitwise rotate a 32-bit number to the left.
 */
function _rotateLeft(n, count) {
    return 0xffffffff & ((n << count) | (((n >> 1) & 0x7fffffff) >> (32 - count - 1)));
}

/*
 * Perform the appropriate triplet combination function for the current
 * iteration
 */
function _ft(t, b, c, d) {
    if (t < 20) {
        return (b & c) | ((~b) & d);
    } else if (t < 40) {
        return b ^ c ^ d;
    } else if (t < 60) {
        return (b & c) | (b & d) | (c & d);
    } else {
        return b ^ c ^ d;
    }
}

/*
 * Determine the appropriate additive constant for the current iteration
 */
function _kt(t) {
    if (t < 20) {
        return 1518500249;
    } else if (t < 40) {
        return 1859775393;
    } else if (t < 60) {
        return -1894007588;
    } else {
        return -899497514;
    }
}

/*
 * Calculate the SHA-1 of an array of big-endian words, and a bit length
 */
function sha1Binary(bin, len) {
    // append padding
    bin[len >> 5] |= 0x80 << (24 - len % 32);
    bin[((len + 64 >> 9) << 4) + 15] = len;

    let w = [];
    let a = 1732584193;
    let b = -271733879;
    let c = -1732584194;
    let d = 271733878;
    let e = -1009589776;

    for (let i = 0, il = length(bin); i < il; i += 16) {
        let _a = a;
        let _b = b;
        let _c = c;
        let _d = d;
        let _e = e;

        for (let j = 0; j < 80; j++) {
            if (j < 16) {
                w[j] = bin[i + j];
            } else {
                w[j] = _rotateLeft(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
            }
            let t = _add(_add(_rotateLeft(a, 5), _ft(j, b, c, d)),
                _add(_add(e, w[j]), _kt(j)));
            e = d;
            d = c;
            c = _rotateLeft(b, 30);
            b = a;
            a = t;
        }

        a = _add(a, _a);
        b = _add(b, _b);
        c = _add(c, _c);
        d = _add(d, _d);
        e = _add(e, _e);
    }
    return [a, b, c, d, e];
}

// Calculate the SHA1 of a raw string
export function hash(raw) {
    const binary = [];
    for (let i = 0; i < length(raw); i++) {
        binary[i >> 2] += ord(raw, i) << ((3 - (i & 3)) * 8);
    }
    const hash = sha1Binary(binary, length(raw) * 8);
    //let hex = "";
    //for (let i = 0; i < length(hash); i++) {
    //    const h = hash[i];
    //    hex += sprintf("%02x%02x%02x%02x", (h >> 24) & 255, (h >> 16) & 255, (h >> 8) & 255, h & 255);
    //}
    //return hex;
    let str = "";
    for (let i = 0; i < length(hash); i++) {
        const h = hash[i];
        str += chr((h >> 24) & 255, (h >> 16) & 255, (h >> 8) & 255, h & 255);
    }
    return str;
};
