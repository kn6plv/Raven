import * as channel from "channel";
import * as router from "router";
import * as message from "message";
import * as textmessage from "textmessage";
import * as timers from "timers";
import * as node from "node";

let enabled = false;

const SAVE_INTERVAL = 5 * 60;
const SYNC_DELAY = 30;
const DEFAULT_STORE_SIZE = 50;
const stores = {};
const dirty = {};
let defaultStoreSize = DEFAULT_STORE_SIZE;

function loadStore(namekey)
{
    if (!stores[namekey]) {
        stores[namekey] = platform.load(`textstore.${namekey}`) ?? {
            index: {},
            messages: [],
            size: defaultStoreSize
        };
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
    const idx = `${msg.from}:${msg.id}`;
    if (!store.index[idx]) {
        store.index[idx] = true;
        msg.stored = true;
        push(store.messages, json(sprintf("%J", msg)));
        sort(store.messages, (a, b) => a.rx_time - b.rx_time);
        while (length(store.messages) > store.size) {
            const m = shift(store.messages);
            delete store.index[m.id];
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

    if (cursor && store.index[cursor]) {
        for (let i = mlength - 1; i >= 0; i--) {
            const msg = messages[i];
            if (cursor === `${msg.from}:${msg.id}`) {
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
    for (let i = 0; i < limit; i++) {
        const tm = messages[start + i];
        router.queue(message.createMessage(msg.from, null, tm.namekey, "textstore_message", tm,
        {
            hop_start: 0,
            hop_limit: 0,
        }));
    }
}

export function syncMessageNamekey(namekey)
{
    const stores = platform.getStoresByNamekey(namekey);
    if (stores[0]) {
        const to = stores[0].id;
        const state = textmessage.state(namekey);
        router.queue(message.createMessage(to, null, namekey, "textstore_resend", {
            namekey: namekey,
            cursor: state.cursor,
            limit: state.max
        }));
    }
};

function syncMessages()
{
    const all = channel.getAllChannels();
    for (let i = 0; i < length(all); i++) {
        syncMessageNamekey(all[i].namekey);
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
        timers.setInterval("textstore", SAVE_INTERVAL);
    }
    timers.setTimeout("messagesync", SYNC_DELAY);
};

export function tick()
{
    if (timers.tick("textstore")) {
        saveToPlatform();
    }
    if (timers.tick("messagesync")) {
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
            textmessage.addMessage(msg.data.textstore_message);
            if (enabled) {
                addMessage(msg.data.textstore_message);
            }
        }
    }
    if (enabled) {
        if (msg.data?.text_message) {
            addMessage(msg);
            router.queue(message.createMessage(msg.from, null, msg.namekey, "textstore_ack", {
                id: msg.id
            }, {
                hop_start: 0,
                hop_limit: 0
            }));
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
