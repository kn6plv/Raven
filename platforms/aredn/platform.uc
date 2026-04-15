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

const MAX_BINARY_MEM = 0.1; // 10% free ram for binary storage

const LOCATION_SOURCE_INTERNAL = 2;

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

    if (config.messages?.ram) {
        ramMessages = true;
    }

    mkdirp("/usr/local/raven/data");
    mkdirp("/usr/local/raven/winlink/forms");
    mkdirp("/tmp/apps/raven/images");
    if (ramMessages) {
        mkdirp("/tmp/apps/raven/data");
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

    const freemem = 1024 * match(fs.readfile("/proc/meminfo"), /MemFree: +(\d+) kB/)[1];
    const binarymem = freemem * MAX_BINARY_MEM;
    if (binarymem > maxBinarySize) {
        maxBinarySize = binarymem;
    }

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
    // Image files are store in ramdisk
    if (index(name, "img") === 0) {
        return `/tmp/apps/raven/images/${name}`;
    }
    if (index(name, "winlink/") === 0) {
        return `/usr/local/raven/${name}`;
    }
    if (ramMessages && index(name, "messages.") === 0) {
        return `/tmp/apps/raven/data/${replace(name, /\//g, "_")}.json`;
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
            const mchan = channel.getChannelsByMeshtasticHash(null)[0];
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
    canAcceptIPAddress
};
