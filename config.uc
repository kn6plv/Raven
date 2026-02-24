import * as fs from "fs";
import * as router from "router";
import * as channel from "channel";
import * as node from "node";
import * as ipmesh from "ipmesh";
import * as meshtastic from "meshtastic";
import * as meshtasticprotobufs from "meshtasticprotobufs";
import * as meshcore from "meshcore";
import * as websocket from "websocket";
import * as event from "event";

import * as nodedb from "nodedb";
import * as nodeinfo from "nodeinfo";
import * as textmessage from "textmessage";
import * as position from "position";
import * as traceroute from "traceroute";
import * as textstore from "textstore";
import * as device from "telemetry_device";
import * as environmental_weewx from "telemetry_environmental_weewx";
import * as airquality_purpleair from "telemetry_airquality_purpleair";
import * as winlink from "winlink";

let bconfig;
let config;
let override;

function jsonEq(a, b)
{
    return sprintf("%J", a) === sprintf("%J", b);
}

function clone(a)
{
    return json(sprintf("%J", a));
}

function update(option)
{
    let write = false;

    switch (option) {
        case "channels":
        {
            const channels = channel.getAllLocalChannels();
            const nchannels = [];
            for (let i = 0; i < length(channels); i++) {
                const nchannel = { namekey: channels[i].namekey };
                if (channels[i].telemetry) {
                    nchannel.telemetry = true;
                }
                if (channels[i].meshtastic) {
                    nchannel.meshtastic = true;
                }
                push(nchannels, nchannel);
            }
            if (!jsonEq(nchannels, config.channels)) {
                config.channels = nchannels;
                if (jsonEq(nchannels, bconfig.channels)) {
                    delete override.channels;
                }
                else {
                    override.channels = nchannels;
                }
                write = true;
            }
            break;
        }
        default:
            break;
    }

    if (write) {
        const data = sprintf("%.2J", override);
        if (fs.access("/etc/raven.conf.override")) {
            fs.writefile("/etc/raven.conf.override", data);
        }
        else if (fs.access(`${fs.dirname(SCRIPT_NAME)}/raven.conf.override`)) {
            fs.writefile(`${fs.dirname(SCRIPT_NAME)}/raven.conf.override`, data);
        }
        else if (fs.access("/etc/raven.conf")) {
            fs.writefile("/etc/raven.conf.override", data);
        }
        else if (fs.access(`${fs.dirname(SCRIPT_NAME)}/raven.conf`)) {
            fs.writefile(`${fs.dirname(SCRIPT_NAME)}/raven.conf.override`, data);
        }
    }
}

export function setup()
{
    push(REQUIRE_SEARCH_PATH, `${fs.dirname(SCRIPT_NAME)}/*.uc`);

    bconfig = json(fs.readfile("/etc/raven.conf") ?? fs.readfile(`${fs.dirname(SCRIPT_NAME)}/raven.conf`));
    config = clone(bconfig);
    override = json(fs.readfile("/etc/raven.conf.override") ?? fs.readfile(`${fs.dirname(SCRIPT_NAME)}/raven.conf.override`) ?? "[]");
    if (type(override) === "object") {
        function f(c, o)
        {
            for (let k in o) {
                if (o[k] === null) {
                    delete c[k];
                }
                else switch (type(o[k])) {
                    case "object":
                        if (!c[k]) {
                            c[k] = {};
                        }
                        f(c[k], o[k]);
                        break;
                    default:
                        c[k] = o[k];
                        break;
                }
            }
        }
        f(config, override);
    }
    else {
        override = {};
    }

    config.update = update;

    global.DEBUG0 = function(){};
    global.DEBUG1 = function(){};
    global.DEBUG2 = function(){};
    switch (config.debug)
    {
        case 2:
            global.DEBUG2 = printf;
        case 1:
            global.DEBUG1 = printf;
        case 0:
            global.DEBUG0 = printf;
            break;
        default:
            break;
    }

    DEBUG0("Starting up\nConfiguring\n");

    if (config.platform_aredn) {
        global.platform = require(`platforms.aredn.platform`);
    }
    else if (config.platform_debian) {
        global.platform = require(`platforms.debian.platform`);
    }
    global.platform.setup(config);
    router.registerApp(global.platform);

    global.platform.mergePlatformConfig(config);

    ipmesh.setup(config);
    router.registerApp(ipmesh);
    meshtastic.setup(config);
    router.registerApp(meshtastic);
    meshcore.setup(config);
    router.registerApp(meshcore);
    
    event.setup(config);
    global.event = event;
    router.registerApp(event);

    websocket.setup(config);
    nodedb.setup(config);
    router.registerApp(nodedb);
    node.setup(config);

    nodeinfo.setup(config);
    router.registerApp(nodeinfo);
    textmessage.setup(config);
    router.registerApp(textmessage);
    position.setup(config);
    router.registerApp(position);
    traceroute.setup(config);
    router.registerApp(traceroute);
    device.setup(config);
    router.registerApp(device);
    channel.setup(config);
    router.registerApp(channel);
    textstore.setup(config);
    router.registerApp(textstore);

    if (config.telemetry?.environmental_weewx) {
        environmental_weewx.setup(config);
        router.registerApp(environmental_weewx);
    }
    if (config.telemetry?.airquality_purpleair) {
        airquality_purpleair.setup(config);
        router.registerApp(airquality_purpleair);
    }

    winlink.setup(config);
    router.registerApp(winlink);

    platform.publish(node.getInfo(), channel.getAllLocalChannels());

    function shutdown()
    {
        DEBUG0("Shutting down\n");
        meshtastic.shutdown();
        meshcore.shutdown();
        ipmesh.shutdown();
        platform.shutdown();
        nodedb.shutdown();
        textmessage.shutdown();
        textstore.shutdown();
        DEBUG0("Shutdown\n");
        exit(0);
    }
    signal("SIGHUP", shutdown);
    signal("SIGINT", shutdown);
    signal("SIGTERM", shutdown);

    DEBUG0("Configured\n");
};

export function tick()
{
    DEBUG0("Tick\n");
    router.tick();
    gc("collect");
};
