import * as math from "math";
import * as channel from "channel";
import * as router from "router";
import * as message from "message";
import * as textmessage from "textmessage";
import * as timers from "timers";
import * as node from "node";

let enabled = false;

const SAVE_INTERVAL = 5 * 60;
const SYNC_FIRST_INTERVAL = 5;
const SYNC_INTERVAL = 10;
const DEFAULT_STORE_SIZE = 50;
const stores = {};
const synced = {};
const dirty = {};
const indexes = {};
let defaultStoreSize = DEFAULT_STORE_SIZE;
let syncCount = 3;

function loadStore(namekey)
{
    if (!stores[namekey]) {
        stores[namekey] = platform.load(`textstore.${namekey}`) ?? {
            messages: [],
            size: defaultStoreSize
        };
        const messages = stores[namekey].messages;
        const index = {};
        indexes[namekey] = index;
        for (let i = 0; i < length(messages); i++) {
            index[messages[i].id] = true;
        }

    }
    return stores[namekey];
}

function saveToPlatform()
{
    for (let namekey in stores) {
        if (dirty[namekey]) {
            dirty[namekey] = false;
            platform.store(`textstore.${namekey}`, stores[namekey]);
        }
    }
}

function addMessage(msg)
{
    const store = loadStore(msg.namekey);
    if (!indexes[msg.namekey][msg.id]) {
        indexes[msg.namekey][msg.id] = true;
        msg.stored = true;
        push(store.messages, json(sprintf("%J", msg)));
        sort(store.messages, (a, b) => a.rx_time - b.rx_time);
        while (length(store.messages) > store.size) {
            const m = shift(store.messages);
            delete indexes[msg.namekey][m.id];
        }
        dirty[msg.namekey] = true;
    }
}

function resendMessages(msg)
{
    const resend = msg.data.textstore_resend;

    const store = loadStore(resend.namekey);
    const messages = store.messages;
    const mlength = length(messages);

    let start = 0;
    let limit = min(resend.limit, store.size);
    const cursor = resend.cursor;

    if (cursor && indexes[resend.namekey][cursor]) {
        for (let i = mlength - 1; i >= 0; i--) {
            const msg = messages[i];
            if (cursor == msg.id) {
                start = i + 1;
                break;
            }
        }
    }
    if (start + limit < mlength) {
        start = mlength - limit;
    }
    else if (start + limit > mlength) {
        limit = mlength - start;
    }
    if (limit > 0) {
        for (let i = 0; i < limit; i++) {
            const tm = messages[start + i];
            router.queue(message.createMessage(msg.from, null, resend.namekey, "textstore_message", tm, {
                hop_limit: 0
            }));
        }
    }
    else {
        router.queue(message.createMessage(msg.from, null, resend.namekey, "textstore_message", {}, {
            hop_limit: 0
        }));
    }
}

export function syncMessageNamekey(namekey)
{
    const store = platform.getStoreByNamekey(namekey);
    if (store) {
        if (synced[namekey] !== store.id) {
            const state = textmessage.state(namekey);
            router.queue(message.createMessage(store.id, null, namekey, "textstore_resend", {
                namekey: namekey,
                cursor: state.last,
                limit: state.max
            }));
        }
    }
    else {
        delete synced[namekey];
    }
};

function syncMessages()
{
    const all = channel.getAllLocalChannels();
    for (let i = 0; i < length(all); i++) {
        syncMessageNamekey(all[i].namekey);
    }
}

function checkMissing(msg)
{
    if (msg.data.last_id && !textmessage.getMessage(msg.namekey, msg.data.last_id)) {
        const store = platform.getStoreByNamekey(msg.namekey);
        if (store) {
            router.queue(message.createMessage(store.id, null, msg.namekey, "textstore_resend", {
                namekey: msg.namekey,
                cursor: msg.data.last_id,
                limit: 1
            }));
        }
    }
}

export function setup(config)
{
    if (config.textstore) {
        enabled = true;
        const stores = config.textstore.stores;
        if (stores) {
            for (let i = 0; i < length(stores); i++) {
                const s = stores[i];
                if (s.namekey === "*") {
                    defaultStoreSize = s.size || DEFAULT_STORE_SIZE;
                }
                else {
                    const store = loadStore(s.namekey);
                    store.size = s.size || DEFAULT_STORE_SIZE;
                    dirty[s.namekey] = true;
                }
            }
        }
        timers.setInterval("textstoresave", SAVE_INTERVAL);
    }
    timers.setInterval("textstoresync", SYNC_FIRST_INTERVAL, SYNC_INTERVAL);
};

export function tick()
{
    if (timers.tick("textstoresave")) {
        saveToPlatform();
    }
    if (timers.tick("textstoresync")) {
        syncMessages();
        syncCount--;
        if (syncCount <= 0) {
            timers.cancel("textstoresync");
        }
    }
};

export function process(msg)
{
    if (node.toMe(msg) && msg.data) {
        if (msg.data.textstore_ack) {
            const message = textmessage.getMessage(msg.namekey, msg.data.textstore_ack.id);
            if (message) {
                message.ack = true;
                textmessage.saveMessages(msg.namekey);
                event.notify({ cmd: "ack", namekey: msg.namekey, id: msg.data.textstore_ack.id }, `ack ${msg.namekey} ${msg.data.textstore_ack.id}`);
            }
        }
        else if (msg.data.textstore_message) {
            if (msg.data.textstore_message.data) {
                textmessage.addMessage(msg.data.textstore_message);
                if (enabled) {
                    addMessage(msg.data.textstore_message);
                }
            }
            synced[msg.namekey] = msg.from;
        }
    }
    if (msg.data?.text_message && node.forMe(msg) && channel.getLocalChannelByNameKey(msg.namekey)) {
        checkMissing(msg);
    }
    if (enabled) {
        if (msg.data?.text_message) {
            addMessage(msg);
            if (msg.transport === "native") {
                router.queue(message.createMessage(msg.from, null, msg.namekey, "textstore_ack", {
                    id: msg.id
                }, {
                    hop_limit: 0
                }));
            }
        }
        else if (msg.data?.textstore_resend) {
            resendMessages(msg);
        }
    }
};

export function shutdown()
{
    if (enabled) {
        saveToPlatform();
    }
};
