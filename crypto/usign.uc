import * as fs from "fs";
import * as struct from "struct";

const USIGN = "/usr/bin/usign";

const TMP_PRIVATE_KEY = "/tmp/raven.privatekey";
const TMP_PUBLIC_KEY = "/tmp/raven.publickey";
const TMP_SIGNATURE = "/tmp/raven.signature";
const TMP_PLAIN = "/tmp/raven.msg";

export function ed25519GenerateKeys()
{
    let r = null;
    system(`${USIGN} -q -G -p /dev/null -s ${TMP_PRIVATE_KEY}`);
    const p = fs.open(TMP_PRIVATE_KEY);
    if (p) {
        p.read("line"); // Discard
        const data = b64dec(p.read("line"));
        p.close();
        const privkey = substr(data, 40, 32);
        const pubkey = substr(data, 72, 32);
        r = {
            public_key: pubkey,
            private_key: privkey
        };
    }
    fs.unlink(TMP_PRIVATE_KEY);
    return r;
};

export function ed25519Sign(privatekey, publickey, plain)
{
    let r = null;
    fs.writefile(TMP_PLAIN, plain);
    fs.writefile(TMP_PRIVATE_KEY, "\n" + b64enc("Ed" + struct.pack("=HIQQQQ", 0, 0, 0, 0, 0, 0) + privatekey + publickey));
    system(`${USIGN} -q -S -x ${TMP_SIGNATURE} -s ${TMP_PRIVATE_KEY} -m ${TMP_PLAIN}`);
    const p = fs.open(TMP_SIGNATURE);
    if (p) {
        p.read("line"); // Discard
        const data = b64dec(p.read("line"));
        p.close();
        r = substr(data, 10, 64);
    }
    fs.unlink(TMP_PLAIN);
    fs.unlink(TMP_PRIVATE_KEY);
    fs.unlink(TMP_SIGNATURE);
    return r;
};

export function ed25519Verify(publickey, plain, signature)
{
    fs.writefile(TMP_PLAIN, plain);
    fs.writefile(TMP_PUBLIC_KEY, "\n" + b64enc("Ed" + struct.pack("Q", 0) + publickey));
    fs.writefile(TMP_SIGNATURE, "\n" + b64enc("Ed" + struct.pack("Q", 0) + signature));
    let r = false;
    if (system(`${USIGN} -q -V -p ${TMP_PUBLIC_KEY} -m ${TMP_PLAIN} -x ${TMP_SIGNATURE}`) == 0) {
        r = true;
    }
    fs.unlink(TMP_PLAIN);
    fs.unlink(TMP_PUBLIC_KEY);
    fs.unlink(TMP_SIGNATURE);
    return r;
};
