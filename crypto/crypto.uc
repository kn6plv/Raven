import * as struct from "struct";
import * as aes from "aes";
import * as x25519 from "curve25519";
import * as usign from "usign";
import * as sha256 from "sha256";
import * as sha1 from "sha1";

export function decryptECB(key, encrypted)
{
    let plain = "";

    aes.AES_Init();

    const ekey = aes.AES_ExpandKey(slice(key, 0, 16));

    for (let i = 0; i < length(encrypted); i += 16) {
        plain += struct.pack("16B", ...aes.AES_Decrypt(struct.unpack("16B", encrypted, i), ekey));
    }

    aes.AES_Done();

    return plain;
};

export function encryptECB(key, plain)
{
    let encrypted = "";

    aes.AES_Init();

    const ekey = aes.AES_ExpandKey(slice(key, 0, 16));

    for (let i = 0; i < length(plain); i += 16) {
        encrypted += struct.pack("16B", ...aes.AES_Encrypt(struct.unpack("16B", plain, i), ekey));
    }

    aes.AES_Done();

    return encrypted;
};

export function decryptCTR(from, id, key, encrypted)
{
    let plain = "";

    aes.AES_Init();

    const ekey = aes.AES_ExpandKey(slice(key));

    const counter = struct.unpack("16B", struct.pack("<IIII", id, 0, from, 0));
    let ecounterIdx = 16;
    let ecounter;

    for (let i = 0; i < length(encrypted); i++) {
        if (ecounterIdx === 16) {
            ecounter = aes.AES_Encrypt(slice(counter), ekey);
            ecounterIdx = 0;
            for (let j = 15; j >= 0; j--) {
                if (counter[j] !== 255) {
                    counter[j]++;
                    break;
                }
                counter[j] = 0;
            }
        }
        plain += chr(ord(encrypted, i) ^ ecounter[ecounterIdx++]);
    }

    aes.AES_Done();

    return plain;
};

export function encryptCTR(from, id, key, plain)
{
    return decryptCTR(from, id, key, plain);
};

export function decryptCCM(from, id, key, encrypted, xnonce, auth)
{
    let plain = "";

    aes.AES_Init();

    const ekey = aes.AES_ExpandKey(slice(key));

    const nonce = struct.pack("<I", id) + xnonce + struct.pack("<II", from, 0);
    const counter = struct.unpack("16B", struct.pack("B", 1) + substr(nonce, 0, 13) + struct.pack("2B", 0, 0));
    const a = aes.AES_Encrypt(slice(counter), ekey);
    let t = [];
    for (let i = 0; i < length(auth); i++) {
        push(t, ord(auth, i) ^ a[i]);
    }

    counter[15] = 1;
    let ecounterIdx = 16;
    let ecounter;
    for (let i = 0; i < length(encrypted); i++) {
        if (ecounterIdx === 16) {
            ecounter = aes.AES_Encrypt(slice(counter), ekey);
            ecounterIdx = 0;
            for (let j = 15; j >= 0; j--) {
                if (counter[j] !== 255) {
                    counter[j]++;
                    break;
                }
                counter[j] = 0;
            }
        }
        plain += chr(ord(encrypted, i) ^ ecounter[ecounterIdx++]);
    }

    const x = struct.unpack("16B", struct.pack("B", 1|((length(auth) - 2) << 2)) + substr(nonce, 0, 13) + struct.pack(">H", length(plain)));
    aes.AES_Encrypt(x, ekey);
    let xcounterIdx = 0;
    for (let i = 0; i < length(plain); i++) {
        if (xcounterIdx === 16) {
            aes.AES_Encrypt(x, ekey);
            xcounterIdx = 0;
        }
        x[xcounterIdx++] ^= ord(plain, i);
    }
    if (length(plain) % 16) {
        aes.AES_Encrypt(x, ekey);
    }

    aes.AES_Done();

    for (let i = 0; i < length(t); i++) {
        if (x[i] !== t[i]) {
            return null;
        }
    }

    return plain;
};

export function encryptCCM(from, id, key, plain, xnonce, authlen)
{
    let encrypted = "";

    aes.AES_Init();

    const ekey = aes.AES_ExpandKey(slice(key));

    const nonce = struct.pack("<I", id) + xnonce + struct.pack("<II", from, 0);

    const x = struct.unpack("16B", struct.pack("B", 1|((authlen - 2) << 2)) + substr(nonce, 0, 13) + struct.pack(">H", length(plain)));
    aes.AES_Encrypt(x, ekey);
    let xcounterIdx = 0;
    for (let i = 0; i < length(plain); i++) {
        if (xcounterIdx === 16) {
            aes.AES_Encrypt(x, ekey);
            xcounterIdx = 0;
        }
        x[xcounterIdx++] ^= ord(plain, i);
    }
    if (length(plain) % 16) {
        aes.AES_Encrypt(x, ekey);
    }

    const counter = struct.unpack("16B", struct.pack("B", 1) + substr(nonce, 0, 13) + struct.pack("2B", 0, 0));
    const a = aes.AES_Encrypt(slice(counter), ekey);
    let auth = "";
    for (let i = 0; i < authlen; i++) {
        auth += chr(x[i] ^ a[i]);
    }

    counter[15] = 1;
    let dcounterIdx = 16;
    let dcounter;
    for (let i = 0; i < length(plain); i++) {
        if (dcounterIdx === 16) {
            dcounter = aes.AES_Encrypt(slice(counter), ekey);
            dcounterIdx = 0;
            for (let j = 15; j >= 0; j--) {
                if (counter[j] !== 255) {
                    counter[j]++;
                    break;
                }
                counter[j] = 0;
            }
        }
        encrypted += chr(ord(plain, i) ^ dcounter[dcounterIdx++]);
    }

    aes.AES_Done();

    return encrypted + auth;
};

export function generateKeys()
{
    const keys = usign.ed25519GenerateKeys();
    return {
        private: keys.private_key,
        edpublic: keys.public_key,
        xpublic: struct.pack("<16H", ...x25519.curve25519(struct.unpack("<16H", keys.private_key)))
    };
};

export function getSharedKey(myprivatekey, theirpublickey)
{
    return struct.pack("<16H", ...x25519.curve25519(struct.unpack("<16H", myprivatekey), struct.unpack("<16H", theirpublickey)));
};

export function sign(privatekey, publickey, plain)
{
    return usign.ed25519Sign(privatekey, publickey, plain);
};

export function verify(publickey, plain, signature)
{
    return usign.ed25519Verify(publickey, plain, signature);
};

export function ed25519_privkey_to_x25519(key)
{
    return struct.pack("<16H", ...x25519.ed25519_privkey_to_x25519(key));
};

export function ed25519_pubkey_to_x25519(key)
{
    return struct.pack("<16H", ...x25519.ed25519_pubkey_to_x25519(struct.unpack("<16H",key)));
};

export function sha256hash(data)
{
    return sha256.hash(data);
};

export function sha256hmac(key, data)
{
    let okey = "";
    let ikey = "";
    for (let i = 0; i < 64; i++) {
        const val = key[i] ?? 0;
        okey += chr(val ^ 0x5c);
        ikey += chr(val ^ 0x36);
    }
    return sha256.hash(okey + struct.pack("32B", ...sha256.hash(ikey + data)));
};

export function sha1hash(data)
{
    return sha1.hash(data);
};
