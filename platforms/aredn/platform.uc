import * as fs from "fs";
import * as socket from "socket";
import * as timers from "../../timers.uc";
import * as uci from "uci";
import * as services from "aredn.services";
import * as node from "../../node.uc";
import * as channel from "../../channel.uc";
import * as crypto from "../../crypto/crypto.uc";

const CURL = "/usr/bin/curl";

const pubID = "KN6PLV.raven.v1.1";
const pubTopic = "KN6PLV.raven.v1";

const RESCAN_INTERVAL = 1 * 60;

const MAX_BINARY_MEM = 0.1; // 10% free ram for binary storage

const LOCATION_SOURCE_INTERNAL = 2;

const ucdata = {};
let bynamekey = {};
let byid = {};
let forwarders = [];
let stores = {};
let myid;
let arednmeshEnabled = false;
let storesEnabled = null;
const badges = {};
let watcher = null;
let maxBinarySize = 1 * 1024 * 1024;

/* export */ function setup(config)
{
    function mkdirp(p)
    {
        const d = fs.dirname(p);
        if (d && !fs.access(d)) {
            mkdirp(d);
        }
        fs.mkdir(p);
    }
    mkdirp("/usr/local/raven/data");
    mkdirp("/usr/local/raven/winlink/forms");
    mkdirp("/tmp/apps/raven/images");

    const c = uci.cursor();
    ucdata.latitude = c.get("aredn", "@location[0]", "lat");
    ucdata.longitude = c.get("aredn", "@location[0]", "lon");
    ucdata.gridsquare = c.get("aredn", "@location[0]", "gridsquare");
    ucdata.height = c.get("aredn", "@location[0]", "height");
    ucdata.hostname = c.get("system", "@system[0]", "hostname");
    ucdata.mapUrl = c.get("aredn", "@location[0]", "map");

    const cm = uci.cursor("/etc/config.mesh");
    ucdata.main_ip = cm.get("setup", "globals", "wifi_ip");
    ucdata.lan_ip = cm.get("setup", "globals", "dmz_lan_ip");

    const cu = uci.cursor("/etc/local/uci");
    ucdata.macaddress = map(split(cu.get("hsmmmesh", "settings", "wifimac"), ":"), v => hex(v));

    if (config.arednmesh) {
        config.ipmesh = config.arednmesh;
        arednmeshEnabled = true;
        if (config.textstore) {
            if (config.textstore.stores) {
                storesEnabled = map(config.textstore.stores, s => s.namekey);
            }
            else {
                storesEnabled = [ "*" ];
            }
        }
    }

    const freemem = 1024 * match(fs.readfile("/proc/meminfo"), /MemFree: +(\d+) kB/)[1];
    const binarymem = freemem * MAX_BINARY_MEM;
    if (binarymem > maxBinarySize) {
        maxBinarySize = binarymem;
    }

    if (services.watch) {
        watcher = services.watch("publish");
    }
    else {
        timers.setInterval("aredn", 0, RESCAN_INTERVAL);
    }
}

/* export */ function shutdown()
{
    services.unpublish(pubID);
    if (watcher) {
        services.unwatch(watcher);
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

    if (config.role === "client_mute" && config.meshtastic && config.ipmesh) {
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
    // Image files are store in ramdisk
    if (index(name, "img") === 0) {
        return `/tmp/apps/raven/images/${name}`;
    }
    if (index(name, "winlink/") === 0) {
        return `/usr/local/raven/${name}`;
    }
    return `/usr/local/raven/data/${replace(name, /\//g, "_")}.json`;
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
    const p = path(name);
    // Keep a copy of the stored file until the new one is written
    if (fs.access(p)) {
        fs.unlink(`${p}~`);
        fs.rename(p, `${p}~`);
    }
    fs.writefile(p, sprintf("%.02J", data));
    fs.unlink(`${p}~`);
}

/* export */ function storebinary(name, data)
{
    const p = path(name);
    // Reduce cached files to maxBinarySize
    const dirname = fs.dirname(p);
    let size = 0;
    const dir = map(fs.lsdir(dirname), f => {
        const i = fs.stat(`${dirname}/${f}`);
        size += i.size;
        return { f: f, m: i.mtime, s: i.size };
    });
    sort(dir, (a, b) => a.m - b.m);
    for (let i = 0; size > maxBinarySize && i < length(dir); i++) {
        size -= dir[i].s;
        fs.unlink(`${dirname}/${dir[i].f}`);
    }
    fs.writefile(p, data);
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
    if (id === node.BROADCAST) {
        let targets = [];
        const services = bynamekey[namekey];
        if (services) {
            targets = slice(services);
        }
        if (canforward) {
            for (let i = 0; i < length(forwarders); i++) {
                const forwarder = forwarders[i];
                if (index(targets, forwarder) === -1) {
                    push(targets, forwarder);
                }
            }
        }
        let store = stores[namekey];
        if (store) {
            for (let i = 0; i < length(store); i++) {
                if (index(targets, store[i]) === -1) {
                    push(targets, store[i]);
                }
            }
        }
        store = stores["*"];
        if (store) {
            for (let i = 0; i < length(store); i++) {
                if (index(targets, store[i]) === -1) {
                    push(targets, store[i]);
                }
            }
        }
        return targets;
    }
    else {
        const target = byid[id];
        if (target) {
            return [ target ];
        }
        return canforward ? forwarders : [];
    }
}

/* export */ function getTargetById(id)
{
    return byid[id];
}

/* export */ function getStoresByNamekey(namekey)
{
    return stores[namekey] ?? stores["*"] ?? [];
}

/* export */ function publish(me, channels)
{
    if (!arednmeshEnabled) {
        return;
    }
    myid = me.id;
    services.publish(pubID, pubTopic, { id: myid, ip: ucdata.main_ip, role: me.role, key: crypto.pKeyToString(me.private_key), channels: map(channels, c => c.namekey), store: storesEnabled });
}

/* export */ function badge(key, count)
{
    if (count === null) {
        delete badges[key];
    }
    else {
        badges[key] = count;
    }
    let total = 0;
    for (let k in badges) {
        total += badges[k];
    }
    fs.writefile("/tmp/apps/raven/badge", total == 0 ? "" : total > 99 ? "99+" : `${total}`);
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
    forwarders = [];
    const ostores = sprintf("%J", stores);
    stores = {};
    for (let i = 0; i < length(published); i++) {
        const service = published[i];
        if (service.id !== myid) {
            byid[service.id] = service;
            const nchannels = {};
            for (let j = 0; j < length(service.channels); j++) {
                const namekey = service.channels[j];
                if (!bynamekey[namekey]) {
                    bynamekey[namekey] = [];
                    channel.addMessageNameKey(namekey);
                }
                push(bynamekey[namekey], service);
                nchannels[namekey] = true;
            }
            service.channels = nchannels;
            if (node.canRoleForward(service.role)) {
                push(forwarders, service);
            }
            if (service.store) {
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
    if (sprintf("%J", stores) !== ostores) {
        timers.trigger("textstoreresync");
    }
}

/* export */ function tick()
{
    if (timers.tick("aredn")) {
        refreshTargets();
    }
}

/* export */ function process(msg)
{
}

/* export */ function refresh()
{
    refreshTargets();
}

/* export */ function handle()
{
    return watcher;
}

/* export */ function handleChanges()
{
    for (;;) {
        const v = socket.poll(0, [ watcher, socket.POLLIN|socket.POLLRDHUP ]);
        if (!v[0] || !v[0][1]) {
            break;
        }
        const e = watcher.read("line");
        if (!length(e)) {
            services.unwatch(watcher);
            watcher = services.watch("publish");
            break;
        }
    }
    refreshTargets();
}

/* export */ function getMap(lat, lon)
{
    return ucdata.mapUrl ? replace(replace(ucdata.mapUrl, "(lat)", lat), "(lon)", lon) : null;
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
    getStoresByNamekey,
    publish,
    badge,
    auth,
    tick,
    process,
    refresh,
    handle,
    handleChanges,
    getMap
};
