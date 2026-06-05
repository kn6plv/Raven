import * as struct from "struct";
import * as channel from "channel";
import * as textmessage from "textmessage";
import * as crypto from "crypto.crypto";

let groups = [];
let recent = {};
let last_group_tx = {};
let inline_max_members = 10;

function now()
{
    return time();
};

// --- Utility ---

export function normcall(c)
{
    return uc(trim(c ?? ""));
};

function members(g)
{
    return g?.members ?? [];
};

// --- Group CRUD ---

export function getGroup(name)
{
    name = lc(trim(name ?? ""));
    for (let i = 0; i < length(groups); i++) {
        if (lc(groups[i].name) === name) {
            return groups[i];
        }
    }
    return null;
};

export function putGroup(name, dsts, opts)
{
    let g = getGroup(name);
    if (!g) {
        g = {
            name: name,
            members: [],
            repeat_member_messages: opts?.repeat_member_messages ?? false,
            rate_limit_seconds: opts?.rate_limit_seconds ?? 20,
            max_members: opts?.max_members ?? inline_max_members
        };
        push(groups, g);
    }
    g.members = dsts;
    if (opts?.backend) {
        g.backend = opts.backend;
    }
    if (opts?.repeat_member_messages != null) {
        g.repeat_member_messages = opts.repeat_member_messages;
    }
    return g;
};

export function removeGroup(name)
{
    name = lc(trim(name ?? ""));
    for (let i = 0; i < length(groups); i++) {
        if (lc(groups[i].name) === name) {
            splice(groups, i, 1);
            return true;
        }
    }
    return false;
};

export function memberOf(call)
{
    const out = [];
    call = normcall(call);
    for (let i = 0; i < length(groups); i++) {
        const g = groups[i];
        for (let j = 0; j < length(members(g)); j++) {
            if (normcall(members(g)[j]) === call) {
                push(out, g);
                break;
            }
        }
    }
    return out;
};

export function allGroups()
{
    return groups;
};

// --- Duplicate / rate-limit ---

export function canRepeat(g, src, text, id)
{
    const key = `${g.name}:${src}:${text}:${id ?? ""}`;
    if (recent[key] && now() - recent[key] < 1800) {
        return false;
    }
    recent[key] = now();
    const minsec = g.rate_limit_seconds ?? 20;
    if (last_group_tx[g.name] && now() - last_group_tx[g.name] < minsec) {
        return false;
    }
    last_group_tx[g.name] = now();
    return true;
};

// --- Join command parsing ---
// Parse args after "/join": ["#TacNet", "backend=direwolf1", "KN6PLV", "KJ6DZB", "radio", "check"]
// Returns: { name, arednOnly, backendName, members[], messageText } or null

export function parseJoinArgs(args)
{
    if (length(args) < 1) {
        return null;
    }

    const name = args[0];
    // Must start with # or %
    if (ord(name, 0) !== 35 && ord(name, 0) !== 37) {
        return null;
    }

    let backendName = null;
    const mems = [];
    let msgStart = -1;

    for (let i = 1; i < length(args); i++) {
        const tok = args[i];
        // backend=NAME
        const bm = match(tok, /^backend=(.+)$/i);
        if (bm) {
            backendName = bm[1];
            continue;
        }
        // Callsign: 1-6 alphanumeric with at least one digit, optional -SSID
        const cleaned = replace(trim(tok), /,$/, "");
        if (match(cleaned, /^[A-Za-z0-9]{2,6}(-[0-9]{1,2})?$/) && match(cleaned, /[0-9]/)) {
            push(mems, normcall(cleaned));
            continue;
        }
        // First non-callsign, non-backend token = start of message text
        msgStart = i;
        break;
    }

    let messageText = null;
    if (msgStart >= 0) {
        const parts = [];
        for (let i = msgStart; i < length(args); i++) {
            push(parts, args[i]);
        }
        messageText = join(" ", parts);
    }

    // When callsigns are present, force AREDN-only (Part 97: APRS must not bridge to encrypted networks)
    const arednOnly = ord(name, 0) === 37 || length(mems) > 0;

    return {
        name: name,
        arednOnly: arednOnly,
        backendName: backendName,
        members: mems,
        messageText: messageText
    };
};

// --- Channel creation ---
// Creates a channel for a group/join name. Returns the namekey.
// arednOnly=true → %Name og== (AREDN-only, never bridged)
// arednOnly=false → #Name <sha256key> (bridges to Meshtastic+MeshCore+AREDN)

export function createGroupChannel(name, arednOnly)
{
    let chanName = name;
    let key;

    if (arednOnly || ord(name, 0) === 37) {
        // AREDN-only: use og== key (unencrypted)
        // Keep the user's original name — the og== key is what marks it AREDN-only
        key = "og==";
    }
    else {
        // Shared-key channel: #Name sha256(#Name)[0:16]
        key = b64enc(struct.pack("16B", ...crypto.sha256hash(name)));
    }

    const namekey = `${chanName} ${key}`;

    // Already registered — just return it
    if (channel.getLocalChannelByNameKey(namekey)) {
        return namekey;
    }

    // Build updated channel list including the new one
    const newchannel = { namekey: namekey, max: 100, badge: true, images: false, telemetry: false, winlink: false };
    const currchannels = map(channel.getAllLocalChannels(), c => {
        const s = textmessage.state(c.namekey);
        return { namekey: c.namekey, max: s.max, badge: s.badge, images: s.images, telemetry: c.telemetry, winlink: s.winlink, backend: c.backend ?? "" };
    });

    // Fire newchannels event — reuses the full channel pipeline
    event.queue({ cmd: "newchannels", channels: [ ...currchannels, newchannel ] });

    return namekey;
};

// --- Setup ---

export function setup(config)
{
    groups = config.aprs?.groups ?? [];
    inline_max_members = config.aprs?.inline_max_members ?? 10;
};

export function tick()
{
};

export function process(msg)
{
};
