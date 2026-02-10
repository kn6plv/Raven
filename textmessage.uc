import * as node from "node";
import * as nodedb from "nodedb";
import * as channel from "channel";
import * as message from "message";
import * as timers from "timers";
import * as router from "router";

let enabled = false;

const MAX_MESSAGES = 100;
const SAVE_INTERVAL = 5 * 60;

const channelmessages = {};
const channelmessagesdirty = {};

function loadMessages(namekey)
{
    if (!channelmessages[namekey]) {
        channelmessages[namekey] = platform.load(`messages.${namekey}`) ?? {
            max: MAX_MESSAGES,
            index: {},
            count: 0,
            cursor: null,
            messages: [],
            badge: true,
            images: true,
            winlink: channel.isDirect(namekey)
        };
        platform.badge(`messages.${namekey}`, channelmessages[namekey].badge ? channelmessages[namekey].count : 0);
    }
    return channelmessages[namekey];
}

export function saveMessages(namekey, chanmessages)
{
    if (!chanmessages) {
        chanmessages = channelmessages[namekey];
    }
    const messages = chanmessages.messages;
    const cursor = chanmessages.cursor;
    const max = chanmessages.max;
    const index = chanmessages.index;
    while (length(messages) > max) {
        const m = shift(messages);
        delete index[m.id];
    }
    let count = 0;
    for (let i = length(messages) - 1; i >= 0; i--) {
        if (messages[i].id === cursor) {
            break;
        }
        count++;
    }
    chanmessages.count = count;
    if (count === length(messages)) {
        chanmessages.cursor = null;
    }
    channelmessagesdirty[namekey] = true;
    platform.badge(`messages.${namekey}`, chanmessages.badge ? chanmessages.count : 0);
};

export function addMessage(msg)
{
    const chanmessages = loadMessages(msg.namekey);
    const idx = `${msg.from}:${msg.id}`;
    if (!chanmessages.index[idx]) {
        chanmessages.index[idx] = true;
        push(chanmessages.messages, {
            id: idx,
            from: msg.from,
            when: msg.rx_time,
            text: msg.data.text_message,
            structuredtext: msg.data.structured_text_message,
            replyid: msg.data.reply_id
        });
        saveMessages(msg.namekey, chanmessages);
        event.notify({ cmd: "text", namekey: msg.namekey, id: idx }, `text ${msg.namekey} ${idx}`);
    }
};

export function getMessages(namekey)
{
    return loadMessages(namekey).messages;
};

export function getMessage(namekey, id)
{
    const chanmessages = loadMessages(namekey);
    if (chanmessages && chanmessages.index[id]) {
        const messages = chanmessages.messages;
        for (let i = length(messages) - 1; i >= 0; i--) {
            const message = messages[i];
            if (message.id === id) {
                return message;
            }
        }
    }
    return null;
};

export function createMessage(to, namekey, text, structuredtext, replyto)
{
    const extra = {
        data: {}
    };
    if (replyto) {
        extra.data.reply_id = int(split(replyto, ":")[1]);
    }
    if (structuredtext) {
        extra.data.structured_text_message = structuredtext;
    }
    const msg = message.createMessage(to, null, namekey, "text_message", text, extra);
    addMessage(msg);
    return msg;
};

export function catchUpMessagesTo(namekey, id)
{
    const cm = loadMessages(namekey);
    if (cm.index[id] && id !== cm.cursor) {
        cm.cursor = id;
        saveMessages(namekey, cm);
    }
    return { count: cm.count, cursor: cm.cursor, max: cm.max, badge: cm.badge, images: cm.images, winlink: cm.winlink };
};

export function updateSettings(channels)
{
    for (let i = 0; i < length(channels); i++) {
        const channel = channels[i];
        const cm = loadMessages(channel.namekey);
        cm.badge = channel.badge;
        cm.max = channel.max;
        cm.images = channel.images;
        cm.winlink = channel.winlink;
        saveMessages(channel.namekey, cm);
    }
};

export function updateChannelBadge(namekey, badge)
{
    const chan = loadMessages(namekey);
    if (chan.badge != badge) {
        chan.badge = badge;
        saveMessages(namekey, chan);
    }
    if (channel.isDirect(namekey)) {
        const id = int(split(namekey, " ")[1]);
        const node = nodedb.getNode(id, false);
        if (node && node.favorite != badge) {
            node.favorite = badge;
            nodedb.updateNode(node);
            event.notify({ cmd: "favorites" });
        }
    }
};

function addDirectMessage(msg)
{
    updateChannelBadge(msg.namekey, true);
    addMessage(msg);
}

export function createDirectMessage(to, text, structuredtext, replyto)
{
    const extra = {
        namekey: to,
        want_ack: true,
        data: {}
    };
    if (replyto) {
        extra.data.reply_id = int(split(replyto, ":")[1]);
    }
    if (structuredtext) {
        extra.data.structured_text_message = structuredtext;
    }
    const id = int(split(to, " ")[1]);
    const msg = message.createMessage(id, null, null, "text_message", text, extra);
    addDirectMessage(msg);
    return msg;
};

export function state(namekey)
{
    const cm = loadMessages(namekey);
    return { count: cm.count, cursor: cm.cursor, max: cm.max, badge: cm.badge, images: cm.images, winlink: cm.winlink };
};

export function setup(config)
{
    if (config.messages) {
        enabled = true;
        timers.setInterval("textmessages", SAVE_INTERVAL);
        const channels = config.channels;
        if (channels) {
            for (let i = 0; i < length(channels); i++)  {
                loadMessages(channels[i].namekey);
            }
        }
        const favs = nodedb.getNodes(true);
        for (let i = 0; i < length(favs); i++) {
            loadMessages(nodedb.namekey(favs[i].id));
        }
    }
};

function saveToPlatform()
{
    for (let namekey in channelmessages) {
        if (channelmessagesdirty[namekey]) {
            channelmessagesdirty[namekey] = false;
            platform.store(`messages.${namekey}`, channelmessages[namekey]);
        }
    }
}

export function shutdown()
{
    saveToPlatform();
};

export function isMessagable()
{
    return enabled;
};

export function tick()
{
    if (timers.tick("textmessages")) {
        saveToPlatform();
    }
};

export function process(msg)
{
    if (!enabled) {
        return;
    }
    if (msg.data?.text_message) {
        if (node.forMe(msg) && channel.getLocalChannelByNameKey(msg.namekey)) {
            addMessage(msg);
        }
        else if (channel.isDirect(msg.namekey)) {
            if (node.toMe(msg)) {
                addDirectMessage(msg);
                if (msg.want_ack) {
                    router.queue(message.createAckMessage(msg));
                }
            }
            else if (node.fromMe(msg)) {
                addDirectMessage(msg);
            }
        }
    }
    else if (node.toMe(msg) && msg.data?.routing) {
        if (msg.data.routing.error_reason === 0) {
            const namekey = nodedb.namekey(msg.from);
            const idx = `${msg.to}:${msg.data.request_id}`;
            const message = getMessage(namekey, idx);
            if (message) {
                message.ack = true;
                saveMessages(namekey);
                event.notify({ cmd: "ack", namekey: namekey, id: idx }, `text ${namekey} ${idx}`);
            }
        }
    }
};
