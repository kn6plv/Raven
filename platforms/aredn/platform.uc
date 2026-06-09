import * as fs from "fs";
import * as timers from "../../timers.uc";
import * as uci from "uci";
import * as services from "aredn.services";
import * as babel from "aredn.babel";
import * as node from "../../node.uc";
import * as channel from "../../channel.uc";

const CURL = "/usr/bin/curl";

const pubID = "KN6PLV.raven.v1.1";
const pubTopic = "KN6PLV.raven.v1";

const RESCAN_INTERVAL = 1 * 60; // 1 minute
const STORE_SORT_TIMEOUT = 10 * 60; // 10 minutes
const STORAGE_CHECK_INTERVAL = 1 * 60; // 1 minute
const IMAGE_PRUNE_INTERVAL = 5 * 60; // 5 minutes

const MAX_BINARY_MEM = 0.1; // 10% free ram for binary storage
const DEFAULT_USB_IMAGE_QUOTA = 64 * 1024 * 1024;
const DEFAULT_MIN_FREE = 16 * 1024 * 1024;

const LOCATION_SOURCE_INTERNAL = 2;

const INTERNAL_ROOT = "/usr/local/raven";
const TMP_ROOT = "/tmp/apps/raven";
const USB_MOUNTPOINT = "/mnt/crow";
const USB_LABEL = "CROWDATA";

const ucdata = {};
let bynamekey = {};
let byid = {};
let stores = {};
let myid;
let meshipEnabled = false;
let meshtasticEnabled = false;
let meshcoreEnabled = false;
let meshipBridgeEnabled = false;
let storesEnabled = null;
let hasMeshIpForwarder = false;
let bridges = [];
const badges = {};
let pwatcher = null;
let watcher = null;
let maxBinarySize = 1 * 1024 * 1024;
let inShutdown = false;
let storeSort = 0;
let ramMessages = false;

let runtimeConfig = null;
let storageRoot = INTERNAL_ROOT;
let imageRoot = `${TMP_ROOT}/images`;
let degradedRoot = `${TMP_ROOT}/degraded`;
let storageConf = {};
let imageQuotaSize = maxBinarySize;
let minFreeBytes = DEFAULT_MIN_FREE;
let storageNotice = null;
let storageState = {
    mode: "internal",
    state: "ok",
    root: INTERNAL_ROOT,
    image_root: `${TMP_ROOT}/images`,
    mountpoint: null,
    reason: null
};

function mkdirp(p)
{
    const d = fs.dirname(p);
    if (d && !fs.access(d)) {
        mkdirp(d);
    }
    fs.mkdir(p);
}

function trimread(path, fallback)
{
    try {
        return trim(fs.readfile(path));
    }
    catch (_) {
        return fallback;
    }
}

function popenread(cmd)
{
    const p = fs.popen(cmd);
    if (!p) {
        return null;
    }
    const out = trim(p.read("all") ?? "");
    p.close();
    return out;
}

function isWritable(dir)
{
    try {
        const p = `${dir}/.crow-storage-test`;
        fs.writefile(p, "ok");
        fs.unlink(p);
        return true;
    }
    catch (_) {
        return false;
    }
}

function isMounted(mountpoint)
{
    return system(`/bin/mount | /bin/grep -q " on ${mountpoint} "`) === 0;
}

function bytesFromMb(v, fallback)
{
    if (v === null || v === undefined) {
        return fallback;
    }
    return (v + 0) * 1024 * 1024;
}

function freeBytes(path)
{
    const out = popenread(`/bin/df -Pk ${path} 2>/dev/null | /usr/bin/tail -n 1 | /usr/bin/awk '{print $4}'`);
    return out ? (out + 0) * 1024 : null;
}

function setStorageState(mode, state, root, image, mountpoint, reason)
{
    storageState = {
        mode: mode,
        state: state,
        root: root,
        image_root: image,
        mountpoint: mountpoint,
        reason: reason
    };
}

function degraded(reason)
{
    storageRoot = degradedRoot;
    imageRoot = `${TMP_ROOT}/images`;
    mkdirp(`${storageRoot}/data`);
    mkdirp(`${storageRoot}/winlink/forms`);
    mkdirp(imageRoot);
    setStorageState(storageConf?.mode ?? "internal", "degraded", storageRoot, imageRoot, storageConf?.mountpoint ?? USB_MOUNTPOINT, reason);
    if (storageNotice !== reason && global.event) {
        storageNotice = reason;
        event.notify({ cmd: "/reply", reply: [ `<b>Crow storage degraded:</b> ${reason}`, "Core service is still running from node storage." ] }, `storage-degraded-${reason}`);
    }
}

function activateInternalStorage()
{
    storageRoot = INTERNAL_ROOT;
    imageRoot = `${TMP_ROOT}/images`;
    mkdirp(`${storageRoot}/data`);
    mkdirp(`${storageRoot}/winlink/forms`);
    mkdirp(imageRoot);
    setStorageState("internal", "ok", storageRoot, imageRoot, null, null);
}

function activateUsbStorage(conf)
{
    const mountpoint = conf.mountpoint ?? USB_MOUNTPOINT;
    mkdirp(mountpoint);

    if (!isMounted(mountpoint)) {
        if (conf.device) {
            system(`/bin/mount ${conf.device} ${mountpoint} >/dev/null 2>&1`);
        }
        if (!isMounted(mountpoint) && conf.uuid) {
            system(`/bin/mount UUID=${conf.uuid} ${mountpoint} >/dev/null 2>&1`);
        }
        if (!isMounted(mountpoint) && conf.label) {
            system(`/bin/mount LABEL=${conf.label} ${mountpoint} >/dev/null 2>&1`);
        }
    }

    if (!isMounted(mountpoint)) {
        degraded("USB storage is not mounted");
        return false;
    }
    if (!isWritable(mountpoint)) {
        degraded("USB storage is not writable");
        return false;
    }
    const free = freeBytes(mountpoint);
    if (free !== null && free < minFreeBytes) {
        degraded("USB storage free space is below minimum");
        return false;
    }

    storageRoot = mountpoint;
    imageRoot = `${storageRoot}/images`;
    mkdirp(`${storageRoot}/data`);
    mkdirp(`${storageRoot}/winlink/forms`);
    mkdirp(imageRoot);
    setStorageState("usb", "ok", storageRoot, imageRoot, mountpoint, null);
    return true;
}

function configureStorage(config)
{
    runtimeConfig = config;
    storageConf = config.storage ?? {};
    minFreeBytes = bytesFromMb(storageConf.min_free_mb, DEFAULT_MIN_FREE);

    if (storageConf.image_quota_bytes) {
        imageQuotaSize = storageConf.image_quota_bytes + 0;
    }
    else if (storageConf.image_quota_mb) {
        imageQuotaSize = bytesFromMb(storageConf.image_quota_mb, DEFAULT_USB_IMAGE_QUOTA);
    }
    else {
        imageQuotaSize = storageConf.mode === "usb" ? DEFAULT_USB_IMAGE_QUOTA : maxBinarySize;
    }

    if (storageConf.mode === "usb") {
        activateUsbStorage(storageConf);
    }
    else {
        activateInternalStorage();
    }
}

function overridePath()
{
    if (fs.access("/etc/raven.conf.override") || fs.access("/etc/raven.conf")) {
        return "/etc/raven.conf.override";
    }
    return `${fs.dirname(SCRIPT_NAME)}/raven.conf.override`;
}

function persistStorageConfig()
{
    let override = {};
    try {
        override = json(fs.readfile(overridePath()) ?? "{}");
    }
    catch (_) {
        override = {};
    }
    if (type(override) !== "object") {
        override = {};
    }
    override.storage = runtimeConfig.storage;
    fs.writefile(overridePath(), sprintf("%.2J", override));
}

function pruneDir(dirname, quota)
{
    if (!quota || quota <= 0 || !fs.access(dirname)) {
        return;
    }
    let size = 0;
    const dir = map(fs.lsdir(dirname), f => {
        const i = fs.stat(`${dirname}/${f}`);
        size += i.size;
        return { f: f, m: i.mtime, s: i.size };
    });
    sort(dir, (a, b) => a.m - b.m);
    for (let i = 0; size > quota && i < length(dir); i++) {
        size -= dir[i].s;
        fs.unlink(`${dirname}/${dir[i].f}`);
    }
}

function storageHealthCheck()
{
    if (storageConf?.mode === "usb") {
        const mountpoint = storageConf.mountpoint ?? USB_MOUNTPOINT;
        if (!isMounted(mountpoint)) {
            degraded("USB storage is not mounted");
            return false;
        }
        if (!isWritable(mountpoint)) {
            degraded("USB storage is not writable");
            return false;
        }
        const free = freeBytes(mountpoint);
        if (free !== null && free < minFreeBytes) {
            pruneDir(`${mountpoint}/images`, imageQuotaSize);
            if (freeBytes(mountpoint) < minFreeBytes) {
                degraded("USB storage free space is below minimum");
                return false;
            }
        }
        if (storageState.state !== "ok") {
            activateUsbStorage(storageConf);
        }
    }
    return true;
}

/* export */ function storageStatus()
{
    storageHealthCheck();
    return storageState;
}

/* export */ function storageScan()
{
    const out = [];
    const blocks = fs.lsdir("/sys/block") ?? [];
    for (let i = 0; i < length(blocks); i++) {
        const dev = blocks[i];
        if (index(dev, "loop") === 0 || index(dev, "ram") === 0 || index(dev, "mtd") === 0 || index(dev, "ubiblock") === 0) {
            continue;
        }
        const removable = trimread(`/sys/block/${dev}/removable`, "0") === "1";
        if (!removable && index(dev, "sd") !== 0) {
            continue;
        }
        const sectors = trimread(`/sys/block/${dev}/size`, "0") + 0;
        const model = trimread(`/sys/block/${dev}/device/model`, "");
        const path = `/dev/${dev}`;
        push(out, {
            device: path,
            model: model,
            removable: removable,
            size_bytes: sectors * 512,
            mounted: system(`/bin/mount | /bin/grep -q "^${path}"`) === 0
        });
    }
    return out;
}

function isStorageCandidate(device)
{
    const candidates = storageScan();
    for (let i = 0; i < length(candidates); i++) {
        if (candidates[i].device === device) {
            return true;
        }
    }
    return false;
}

/* export */ function storageFormat(device, confirm)
{
    if (confirm !== "confirm") {
        return { ok: false, message: "Refusing to format without final 'confirm' argument." };
    }
    if (!device || !isStorageCandidate(device)) {
        return { ok: false, message: "Device is not a removable USB storage candidate." };
    }

    const mountpoint = USB_MOUNTPOINT;
    mkdirp(mountpoint);
    system(`/bin/umount ${device} >/dev/null 2>&1`);
    system(`/bin/umount ${mountpoint} >/dev/null 2>&1`);

    let rc = system(`/sbin/mkfs.ext4 -F -L ${USB_LABEL} ${device} >/tmp/crow-mkfs.log 2>&1`);
    if (rc !== 0) {
        rc = system(`/usr/sbin/mkfs.ext4 -F -L ${USB_LABEL} ${device} >/tmp/crow-mkfs.log 2>&1`);
    }
    if (rc !== 0) {
        return { ok: false, message: "mkfs.ext4 failed; see /tmp/crow-mkfs.log on the node." };
    }
    if (system(`/bin/mount ${device} ${mountpoint} >/dev/null 2>&1`) !== 0) {
        return { ok: false, message: "Formatted drive, but mount failed." };
    }

    const uuid = popenread(`/sbin/blkid -s UUID -o value ${device} 2>/dev/null`) ?? "";
    runtimeConfig.storage = {
        mode: "usb",
        mountpoint: mountpoint,
        device: device,
        uuid: uuid,
        label: USB_LABEL,
        image_quota_mb: storageConf.image_quota_mb ?? 64,
        min_free_mb: storageConf.min_free_mb ?? 16
    };
    storageConf = runtimeConfig.storage;
    configureStorage(runtimeConfig);
    persistStorageConfig();
    return { ok: true, message: `USB storage enabled at ${mountpoint}.`, uuid: uuid };
}

/* export */ function storageMount()
{
    if (!runtimeConfig.storage) {
        runtimeConfig.storage = { mode: "usb", mountpoint: USB_MOUNTPOINT, label: USB_LABEL, image_quota_mb: 64, min_free_mb: 16 };
    }
    runtimeConfig.storage.mode = "usb";
    storageConf = runtimeConfig.storage;
    const ok = activateUsbStorage(storageConf);
    persistStorageConfig();
    return { ok: ok, message: ok ? `USB storage active at ${storageRoot}.` : storageState.reason };
}

/* export */ function storageDisable()
{
    if (!runtimeConfig.storage) {
        runtimeConfig.storage = {};
    }
    runtimeConfig.storage.mode = "internal";
    storageConf = runtimeConfig.storage;
    activateInternalStorage();
    persistStorageConfig();
    return { ok: true, message: "Crow storage returned to internal node storage." };
}

/* export */ function storageImageQuota(mb)
{
    if (!runtimeConfig.storage) {
        runtimeConfig.storage = {};
    }
    runtimeConfig.storage.image_quota_mb = mb + 0;
    imageQuotaSize = bytesFromMb(runtimeConfig.storage.image_quota_mb, DEFAULT_USB_IMAGE_QUOTA);
    pruneDir(imageRoot, imageQuotaSize);
    persistStorageConfig();
    return { ok: true, message: `Image quota set to ${runtimeConfig.storage.image_quota_mb} MB.` };
}

/* export */ function setup(config)
{
    if (config.messages?.ram) {
        ramMessages = true;
    }

    const freemem = 1024 * match(fs.readfile("/proc/meminfo"), /MemFree: +(\d+) kB/)[1];
    const binarymem = freemem * MAX_BINARY_MEM;
    if (binarymem > maxBinarySize) {
        maxBinarySize = binarymem;
    }

    configureStorage(config);
    if (ramMessages) {
        mkdirp(`${TMP_ROOT}/data`);
    }

    const c = uci.cursor();
    ucdata.latitude = c.get("aredn", "@location[0]", "lat");
    ucdata.longitude = c.get("aredn", "@location[0]", "lon");
    ucdata.gridsquare = c.get("aredn", "@location[0]", "gridsquare");
    ucdata.height = c.get("aredn", "@location[0]", "height");
    ucdata.hostname = c.get("system", "@system[0]", "hostname");
    ucdata.mapUrl = c.get("aredn", "@location[0]", "map");
    ucdata.isSupernode = c.get("aredn", "@supernode[0]", "enable") == "1";

    const cm = uci.cursor("/etc/config.mesh");
    ucdata.main_ip = cm.get("setup", "globals", "wifi_ip");
    ucdata.lan_ip = cm.get("setup", "globals", "dmz_lan_ip");

    const cu = uci.cursor("/etc/local/uci");
    ucdata.macaddress = map(split(cu.get("hsmmmesh", "settings", "wifimac"), ":"), v => hex(v));

    // Supernodes can *only* forward meship traffic. We disable every other kind of bridge
    // just in case they were enabled. Same for text storage as we dont want to store
    // text for every mesh in the supernode mesh. And make them unmessagable too.
    if (ucdata.isSupernode) {
        delete config.meshtastic;
        delete config.meshcore;
        delete config.textstore;
        delete config.messages;
    }

    if (config.arednmesh) {
        config.meship = config.arednmesh;
    }
    if (config.meship) {
        meshipEnabled = true;
        if (ucdata.isSupernode) {
            meshipBridgeEnabled = true;
            config.meship.bridge = true;
        }
        if (config.textstore) {
            if (config.textstore.stores) {
                storesEnabled = map(config.textstore.stores, s => s.namekey);
            }
            else {
                storesEnabled = [ "*" ];
            }
        }
    }

    if (config.meshtastic) {
        meshtasticEnabled = true;
    }
    if (config.meshcore) {
        meshcoreEnabled = true;
    }

    timers.setInterval("storagehealth", STORAGE_CHECK_INTERVAL);
    timers.setInterval("imageprune", IMAGE_PRUNE_INTERVAL);

    if (services.watch) {
        pwatcher = services.watch("publish");
        // We need a proper file description which supports ioctl calls.
        watcher = fs.fdopen(pwatcher.fileno());
    }
    else {
        timers.setInterval("aredn", 0, RESCAN_INTERVAL);
    }
}

/* export */ function shutdown()
{
    inShutdown = true;
    services.unpublish(pubID);
    if (watcher) {
        services.unwatch(pwatcher);
        watcher.close();
    }
}

/* export */ function mergePlatformConfig(config)
{
    const location = config.location ?? (config.location = {});
    if (location.latitude === null) {
        location.latitude = ucdata.latitude;
    }
    if (location.longitude === null) {
        location.longitude = ucdata.longitude;
    }
    if (location.altitude === null) {
        location.altitude = ucdata.height;
    }
    if (location.gridsquare === null) {
        location.gridsquare = ucdata.gridsquare;
    }
    if (location.precision === null) {
        location.precision = 32;
    }
    if (location.source === null && fs.readfile("/tmp/timesync") === "gps") {
        location.source = LOCATION_SOURCE_INTERNAL;
    }

    if (config.meshtastic && config.meshtastic?.address === null) {
        config.meshtastic.address = ucdata.lan_ip;
    }
    if (config.meshcore && config.meshcore?.address === null) {
        config.meshcore.address = ucdata.lan_ip;
    }

    if (config.role === "client_mute" && (config.meshtastic || config.meshcore || ucdata.isSupernode) && config.meship) {
        config.role = "client";
    }

    if (!config.channels) {
        config.channels = [];
    }
    if (length(filter(config.channels, c => c.namekey === "AREDN og==")) === 0) {
        push(config.channels, { "namekey": "AREDN og==" });
    }

    if (config.long_name === null) {
        config.long_name = ucdata.hostname;
    }
    if (config.short_name === null) {
        config.short_name = substr(split(ucdata.hostname, "-", 2)[0], -4);
    }
    const callsign = split(config.long_name, "-")[0];
    if (callsign) {
        config.callsign = callsign;
    }

    if (config.macaddress === null) {
        config.macaddress = ucdata.macaddress;
    }
}

function path(name)
{
    if (index(name, "img") === 0) {
        return `${imageRoot}/${name}`;
    }
    if (index(name, "winlink/") === 0) {
        return `${storageRoot}/${name}`;
    }
    if (ramMessages && storageState.state !== "usb" && index(name, "messages.") === 0) {
        return `${TMP_ROOT}/data/${replace(name, /\//g, "_")}.json`;
    }
    return `${storageRoot}/data/${replace(name, /\//g, "_")}.json`;
}

/* export */ function load(name)
{
    const p = path(name);
    try {
        return json(fs.readfile(p));
    }
    catch (_) {
        fs.unlink(p);
    }
    try {
        return json(fs.readfile(`${p}~`));
    }
    catch (_) {
        fs.unlink(`${p}~`);
    }
    return null;
}

/* export */ function loadbinary(name)
{
    const p = path(name);
    try {
        return fs.readfile(p);
    }
    catch (_) {
        fs.unlink(p);
    }
    try {
        return fs.readfile(`${p}~`);
    }
    catch (_) {
        fs.unlink(`${p}~`);
    }
    return null;
}

/* export */ function store(name, data)
{
    storageHealthCheck();
    const p = path(name);
    mkdirp(fs.dirname(p));
    // Keep a copy of the stored file until the new one is written
    if (fs.access(p)) {
        fs.unlink(`${p}~`);
        fs.rename(p, `${p}~`);
    }
    if (name === "nodedb" && !inShutdown) {
        // Special handling because this gets very big
        // and big flash writes block the app for too long
        const filename = "/tmp/raven.nodedb";
        const f = fs.open(filename, "w");
        f.write("{\n");
        for (let id in data) {
            f.write(`  "${id}": ${sprintf("%J", data[id])},\n`)
        }
        f.write("}\n");
        f.close();
        system(`(mv -f ${filename} ${p}; rm -f ${p}~) &`);
    }
    else {
        fs.writefile(p, sprintf("%.02J", data));
        fs.unlink(`${p}~`);
    }
}

/* export */ function storebinary(name, data)
{
    storageHealthCheck();
    const p = path(name);
    const dirname = fs.dirname(p);
    mkdirp(dirname);
    fs.writefile(p, data);
    if (index(name, "img") === 0) {
        pruneDir(dirname, imageQuotaSize);
    }
    else {
        pruneDir(dirname, maxBinarySize);
    }
}

/* export */ function dirtree(name)
{
    function read(dir)
    {
        const r = {};
        const files = fs.lsdir(dir);
        for (let i = 0; i < length(files); i++) {
            const n = files[i];
            const dn = `${dir}/${n}`;
            r[n] = fs.lstat(dn)?.type === "directory" ? read(dn) : true;
        }
        return r;
    }
    return read(path(name));
}

/* export */ function fetch(url, timeout)
{
    const p = fs.popen(`${CURL} --max-time ${timeout} --silent --output - ${url}`);
    if (!p) {
        return null;
    }
    const all = p.read("all");
    p.close();
    return all;
}

/* export */ function getTargetsByIdAndNamekey(id, namekey, canforward)
{
    let targets = [];
    if (id === node.BROADCAST) {
        const services = bynamekey[namekey];
        if (services) {
            targets = slice(services);
        }
        let store = stores[namekey];
        if (store) {
            targets = [ ...targets, ...store ];
        }
        store = stores["*"];
        if (store) {
            targets = [ ...targets, ...store ];
        }
    }
    else {
        const target = byid[id];
        if (target) {
            return [ target ];
        }
    }
    if (canforward && length(bridges) > 0) {
        targets = [ ...targets, ...bridges ];
    }
    return uniq(targets);
}

/* export */ function getTargetById(id)
{
    return byid[id];
}

/*
 * Order stores so the closest ones are first.
 */
function orderStores()
{
    const allstores = {};
    for (let k in stores) {
        const s = stores[k];
        for (let i = 0; i < length(s); i++) {
            allstores[s[i].ip] = { store: s[i], metric: 9999999 };
        }
    }
    const routes = babel.getHostRoutes();
    for (let i = 0; i < length(routes); i++) {
        const r = routes[i];
        const s = allstores[r.ip];
        if (s) {
            s.metric = r.metric;
        }
    }
    for (let k in stores) {
        sort(stores[k], (a, b) => allstores[a.ip].metric - allstores[b.ip].metrics);
    }
    storeSort = time() + STORE_SORT_TIMEOUT;
}

/* export */ function getStoreByNamekey(namekey)
{
    if (time() > storeSort) {
        orderStores();
    }
    return (stores[namekey] ?? stores["*"] ?? [])[0];
}

/* export */ function publish(me, channels)
{
    if (!meshipEnabled) {
        return;
    }
    myid = me.id;
    const info = {
        id: myid,
        ip: ucdata.main_ip,
        private_key: me.private_key,
        channels: map(channels, c => c.namekey)
    };
    if (storesEnabled) {
        info.store = storesEnabled;
    }
    if (meshtasticEnabled || meshcoreEnabled || meshipBridgeEnabled) {
        info.bridge = [];
        if (meshtasticEnabled) {
            const mconf = {};
            for (let i = 0; i < length(channels); i++) {
                if (channel.isMeshtasticPreset(channels[i].namekey)) {
                    mconf.preset = split(channels[i].namekey, " ")[0];
                    break;
                }
            }
            push(info.bridge, { meshtastic: mconf });
        }
        if (meshcoreEnabled) {
            push(info.bridge, { meshcore: {} });
        }
        if (meshipBridgeEnabled) {
            push(info.bridge, { meship: {} });
        }
    }
    services.publish(pubID, pubTopic, info);
}

/* export */ function badge(key, count)
{
    if (!count) {
        delete badges[key];
    }
    else {
        badges[key] = count;
    }
    let total = 0;
    for (let k in badges) {
        total += badges[k];
    }
    fs.writefile("/tmp/apps/raven/badge", total == 0 ? "" : total > 999 ? "999+" : `${total}`);
}

/* export */ function auth(headers)
{
    for (let i = 0; i < length(headers); i++) {
        const kv = split(headers[i], ": ");
        if (lc(kv[0]) === "cookie") {
            const ca = split(kv[1], ";");
            for (let j = 0; j < length(ca); j++) {
                const cookie = trim(ca[j]);
                if (index(cookie, "authV1=") === 0) {
                    let key = null;
                    const f = fs.open("/etc/shadow");
                    if (f) {
                        for (let l = f.read("line"); length(l); l = f.read("line")) {
                            if (index(l, "root:") === 0) {
                                key = trim(l);
                                break;
                            }
                        }
                        f.close();
                    }
                    return (key == b64dec(substr(cookie, 7)) ? true : false);
                }
            }
            break;
        }
    }
    return false;
};

function refreshTargets()
{
    const published = services.published(pubTopic);
    byid = {};
    bynamekey = {};
    const meshtasticForwarders = [];
    const meshcoreForwarders = [];
    const meshipForwarders = [];
    stores = {};
    hasMeshIpForwarder = false;
    for (let i = 0; i < length(published); i++) {
        const service = published[i];
        if (service.id !== myid) {
            byid[service.id] = service;
            const nchannels = {};
            for (let j = 0; j < length(service.channels); j++) {
                const namekey = service.channels[j];
                if (!bynamekey[namekey]) {
                    bynamekey[namekey] = [];
                }
                push(bynamekey[namekey], service);
                nchannels[namekey] = true;
            }
            service.channels = nchannels;
            if (service.bridge && !meshipBridgeEnabled) {
                for (let j = 0; j < length(service.bridge); j++) {
                    const b = service.bridge[j];
                    if (!meshtasticEnabled && b.meshtastic) {
                        push(meshtasticForwarders, service);
                    }
                    if (!meshcoreEnabled && b.meshcore) {
                        push(meshcoreForwarders, service);
                    }
                    if (b.meship) {
                        hasMeshIpForwarder = true;
                        push(meshipForwarders, service);
                    }
                }
            }
            if (!ucdata.isSupernode && service.store) {
                for (let j = 0; j < length(service.store); j++) {
                    const key = service.store[j];
                    if (!stores[key]) {
                        stores[key] = [];
                    }
                    push(stores[key], service);
                }
            }
        }
    }
    channel.updateRemoteNameKeys(keys(bynamekey));
    bridges = uniq([ ...meshtasticForwarders, ...meshcoreForwarders, ...meshipForwarders ]);
    orderStores();
}

/* export */ function tick()
{
    if (timers.tick("aredn")) {
        refreshTargets();
    }
    if (timers.tick("storagehealth")) {
        storageHealthCheck();
    }
    if (timers.tick("imageprune")) {
        pruneDir(imageRoot, imageQuotaSize);
    }
}

/* export */ function process(msg)
{
}

/* export */ function handle()
{
    return watcher;
}

/* export */ function handleChanges()
{
    const FIONREAD_TYPE = 0x54;
    const FIONREAD_NUM = 0x1B;

    const len = watcher.ioctl(fs.IOC_DIR_READ, FIONREAD_TYPE, FIONREAD_NUM, 4);
    if (len === null || len < 0) {
        services.unwatch(pwatcher);
        watcher.close();
        pwatcher = services.watch("publish");
        watcher = fs.fdopen(pwatcher.fileno());
    }
    else if (len > 0) {
        watcher.read(len);
    }

    refreshTargets();
}

/* export */ function getMap(lat, lon)
{
    return ucdata.mapUrl ? replace(replace(ucdata.mapUrl, "(lat)", lat), "(lon)", lon) : null;
}

/* export */ function canAcceptIPAddress(address)
{
    return hasMeshIpForwarder || system(`/sbin/ip route show table 20 | grep -q ${address}`) === 0;
}

return {
    setup,
    shutdown,
    mergePlatformConfig,
    load,
    loadbinary,
    store,
    storebinary,
    dirtree,
    fetch,
    getTargetsByIdAndNamekey,
    getTargetById,
    getStoreByNamekey,
    publish,
    badge,
    auth,
    tick,
    process,
    handle,
    handleChanges,
    getMap,
    canAcceptIPAddress,
    storageStatus,
    storageScan,
    storageFormat,
    storageMount,
    storageDisable,
    storageImageQuota
};
