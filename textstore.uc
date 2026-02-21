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
const RESYNC_INTERVAL = 60 * 60;
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
                hop_start: 0,
                hop_limit: 0,
            }));
        }
    }
    else {
        router.queue(message.createMessage(msg.from, null, resend.namekey, "textstore_message", null, {
            hop_start: 0,
            hop_limit: 0,
        }));
    }
}

export function syncMessageNamekey(namekey)
{
    const stores = platform.getStoresByNamekey(namekey);
    if (stores[0]) {
        if (!synced[namekey]) {
            const to = stores[0].id;
            const state = textmessage.state(namekey);
            router.queue(message.createMessage(to, null, namekey, "textstore_resend", {
                namekey: namekey,
                cursor: state.cursor,
                limit: state.max
            }));
            synced[namekey] = true;
        }
    }
    else {
        synced[namekey] = false;
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
        const stores = platform.getStoresByNamekey(msg.namekey);
        if (stores[0]) {
            router.queue(message.createMessage(store[0].id, null, msg.namekey, "textstore_resend", {
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
    timers.setInterval("textstoreresync", RESYNC_INTERVAL);
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
    if (timers.tick("textstoreresync")) {
        syncMessages();
    }
};

export function process(msg)
{
    if (node.toMe(msg) && msg.data) {
        if (msg.data.textstore_ack) {
            const idx = `${msg.to}:${msg.data.textstore_ack.id}`;
            const message = textmessage.getMessage(msg.namekey, idx);
            if (message) {
                message.ack = true;
                textmessage.saveMessages(msg.namekey);
                event.notify({ cmd: "ack", namekey: msg.namekey, id: idx }, `text ${msg.namekey} ${idx}`);
            }
        }
        else if (msg.data.textstore_message) {
            timers.cancel("textstoresync");
            if (msg.data.textstore_message) {
                textmessage.addMessage(msg.data.textstore_message);
                if (enabled) {
                    addMessage(msg.data.textstore_message);
                }
            }
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
                    hop_start: 0,
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
