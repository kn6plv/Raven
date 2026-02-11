let sock = null;
let send = () => {};
let rightSelection = null;
let previousSelection = null;
let channels = null;
let echannels = null;
let directs = {};
const nodes = {};
let tests = null;
let me = {};
let textObs;
let updateTextTimeout;
let dropSelection;
let replyid;
let activeFilter;
let winlink = null;
let activityTimeout;
const xdiv = document.createElement("div");

const roles = {
    0: "Client",
    1: "Client Mute",
    2: "Router",
    3: "Route Client",
    4: "Repeater",
    5: "Tracker",
    6: "Sensor",
    7: "Tak",
    8: "Client Hidden",
    9: "Lost and Found",
    10: "Tak Tracker",
    11: "Router Late",
    12: "Client Base"
};

function Q(a, b)
{
    if (b) {
        return a.querySelector(b);
    }
    else {
        return document.querySelector(a);
    }
}

function I(id)
{
    return document.getElementById(id);
}

function N(html)
{
    xdiv.innerHTML = html;
    return xdiv.firstElementChild;
}

function T(text)
{
    xdiv.innerText = text.trim();
    return xdiv.innerHTML;
}

function getChannel(namekey)
{
    for (let i = 0; i < channels.length; i++) {
        if (channels[i].namekey === namekey) {
            return channels[i];
        }
    }
    return directs[namekey];
}

function isDirect(namekey)
{
    return namekey.indexOf("DirectMessages ") === 0;
}

function addDirect(namekey)
{
    if (!directs[namekey]) {
        directs[namekey] = {
            namekey: namekey,
            state: {
                count: 0,
                cursor: null,
                badge: true,
                images: true,
                winlink: true
            }
        };
    }
}

function nodeColors(n)
{
    const c = { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
    const bcolor = `rgb(${c.r},${c.g},${c.b})`;
    if ((c.r * 299 + c.g * 587 + c.b * 114) / 1000 > 127.5) {
        return { bcolor: bcolor, fcolor: "black" };
    }
    else {
        return { bcolor: bcolor, fcolor: "white" };
    }
}

function nodeExpand(node)
{
    node.colors = nodeColors(node.num);
    node.rolename = roles[node.role] ?? "?";
    return node;
}

function htmlChannel(channel)
{
    const nk = channel.namekey.split(" ");
    return `<div class="channel ${rightSelection === channel.namekey ? "selected" : ""}" data-namekey="${channel.namekey}" onclick="showNamekey('${channel.namekey}')">
        <div class="n">
            <div class="t">${channel.meshtastic ? "Meshtastic" : nk[0]}</div>
        </div>
        <div class="unread">${channel.state.count > 0 ? channel.state.count : ''}</div>
    </div>`;
}

function htmlNode(node)
{
    const namekey = `DirectMessages ${node.num}`;
    const filter = `${node.short_name} ${node.long_name}`.toLowerCase();
    let filtered = false;
    if (activeFilter && filter.indexOf(activeFilter) === -1) {
        filtered = true;
    }
    return `<div id="${node.id}" class="node ${node.hw} ${rightSelection === namekey ? 'selected' : ''}" ${filtered ? 'style="display:none"' : ''} data-namekey="${namekey}" data-filter="${filter}" onclick="showNamekey('${namekey}')">
        <div class="s" style="color:${node.colors.fcolor};background-color:${node.colors.bcolor}">${node.short_name}</div>
        <div class="logo"></div>
        <div class="m">
            <div class="l">${node.long_name}</div>
            <div class="r">${node.rolename}</div>
            <div class="t">${new Date(1000 * node.lastseen).toLocaleString()}</div>
        </div>
        <div class="unread">${ node.state?.count > 0 ? node.state.count : ""}</div>
        ${node.favorite ? '<div class="star true"></div>' : ''}
    </div>`;
}

function htmlNodeDetail(node)
{
    let map = "";
    if (node.mapurl) {
        map = `<a class="map" href="${node.mapurl}" target="_blank"><iframe src="${node.mapurl}"></iframe><div class="overlay"></div></a>`;
    }
    let hops = "";
    if (node.hops !== null) {
        hops = `<div class="r"><div>Hops</div><div>${node.hops}</div></div>`;
    }
    return `<div class="node-detail">
        <div class="node ${node.hw}">
            <div class="s" style="color:${node.colors.fcolor};background-color:${node.colors.bcolor}">${node.short_name}</div>
            <div class="logo"></div>
            <div class="m">
                <div class="l">${node.long_name}<div class="star ${node.favorite}" onclick="toggleFav(event,${node.num})"></div></div>
                <div class="r"><div>User Id</div><div>${node.id}</div></div>
                <div class="r"><div>Platform</div><div>${node.hw == "aredn" ? "AREDN" : "Meshtastic"}</div></div>
                <div class="r"><div>Public Key</div><div>${node.public_key}</div></div>
                ${hops}
                <div class="r"><div>Role</div><div>${node.rolename}</div></div>
                <div class="t"><div>Last seen</div><div>${new Date(1000 * node.lastseen).toLocaleString()}</div></div>
            </div>
        </div>
        ${map}
    </div>`;
}

function htmlText(text, useimage)
{
    let n = nodes[text.from];
    if (!n) {
        const id = text.from.toString(16);
        n = {
            id: `!${id}`,
            short_name: id.substr(-4),
            long_name: id.substr(-4),
            colors: nodeColors(text.from)
        };
    }
    let reply = "";
    if (text.replyid) {
        const key = `:${text.replyid}`;
        const r = texts.findLast(t => t.id.indexOf(key) !== -1);
        if (r) {
            reply = `<div class="r"><div>${T(r.text.replace(/\n/g," "))}</div></div>`;
        }
    }
    let textmsg = null;
    const structuredtext = text.structuredtext && text.structuredtext[0];
    if (structuredtext) {
        const wl = structuredtext.winlink;
        if (winlink && wl) {
            let show = "";
            if (winlink[wl.id]) {
                show = `onclick="showNamekey('winlink-express-show ${text.id}')"`;
            }
            textmsg = `<div class="b"><div class="ack ${text.ack ? 'true' : ''}"></div><div class="w" ${show}><div class="i">Winlink</div><span>${wl.id.replace("/", " | ")}</span></div></div>`;
        }
        const im = structuredtext.image;
        if (useimage && im) {
            textmsg = `<div class="b"><div class="ack ${text.ack ? 'true' : ''}"></div><div class="i"><a target="_blank" href="${im.url}"><img loading="lazy" src="${im.url}" onerror="this.src='/apps/raven/ix.png'"></a></div></div>`;
        }
    }
    if (!textmsg) {
        textmsg = `<div class="b"><div class="ack ${text.ack ? 'true' : ''}"></div><div class="t">` + T(text.text).replace(/https?:\/\/[^ \t<]+/g, v => `<a target="_blank" href="${v}">${v}</a>`) + '</div><a href="#" class="re" onclick="setupReply(event)">Reply</a></div>';
    }
    return `<div id="${text.id}" class="text ${n.num == me.num ? 'right ' : ''}${n.hw ? n.hw : ''}">
        ${reply}
        <div>
            <div class="s" style="color:${n.colors.fcolor};background-color:${n.colors.bcolor}">${n.short_name}</div>
            ${n?.hw ? '<div class="logo"></div>' : ''}
            <div class="c">
                <div class="l">${T(n.long_name + " (" + n.id + ")")} ${n ? "<div>&nbsp;" + (new Date(1000 * text.when).toLocaleString()) + "</div>" : ''}</div>
                ${textmsg}
            </div>
        </div>
    </div>`;
}

function htmlChannelConfig()
{
    const body = echannels.map((e, i) => {
        const ne = echannels[i + 1] || {};
        if (e.meshtastic) {
            return `<form class="c">
                <input value="Meshtastic" readonly><select onchange="typeChannelName(${i}, event.target.value)">
                    <option ${e.name === "Disabled" ? "selected" : ""}>Disabled</option>
                    <option ${e.name === "ShortTurbo" ? "selected" : ""}>ShortTurbo</option>
                    <option ${e.name === "ShortSlow" ? "selected" : ""}>ShortSlow</option>
                    <option ${e.name === "ShortFast" ? "selected" : ""}>ShortFast</option>
                    <option ${e.name === "MediumSlow" ? "selected" : ""}>MediumSlow</option>
                    <option ${e.name === "MediumFast" ? "selected" : ""}>MediumFast</option>
                    <option ${e.name === "LongSlow" ? "selected" : ""}>LongSlow</option>
                    <option ${e.name === "LongFast" ? "selected" : ""}>LongFast</option>
                    <option ${e.name === "LongMod" ? "selected" : ""}>LongMod</option>
                    <option ${e.name === "LongTurbo" ? "selected" : ""}>LongTurbo</option>
                </select>
                <input value="100" readonly>
                <div><input ${e.badge ? "checked" : ""} type="checkbox" oninput="typeChannelBadge(${i}, event.target.checked)"></div>
                <div><input disabled type="checkbox"></div>
                <div><input disabled ${e.telemetry ? "checked" : ""} type="checkbox" oninput="typeChannelTelemetry(${i}, event.target.checked)"></div>
                <div><input disabled type="checkbox"></div>
                <select disabled><option>new key</option></select>
                <button onclick="rmChannel(${i})" disabled>-</button>
                <button onclick="addChannel(${i})" ${e.readonly && ne.readonly ? "disabled" : ""}>+</button>
            </form>`;
        }
        return `<form class="c">
            <input value="${e.name}" oninput="typeChannelName(${i}, event.target.value)" required minlength="1" maxlength="11" size="11" placeholder="Name" ${e.readonly ? "readonly" : ""} pattern="[^ ]+">
            <input value="${e.key}" oninput="typeChannelKey(${i}, event.target.value)" required minlength="4" maxlength="43" size="43" placeholder="Key" ${e.readonly ? "readonly" : ""} pattern="[\\-A-Za-z0-9+\\/]*={0,3}">
            <input value="${e.max}" oninput="typeChannelMax(${i}, event.target.value)" required minlength="2" maxlength="4" size="4" placeholder="Count" ${e.readonly ? "readonly" : ""}>
            <div><input ${e.badge ? "checked" : ""} type="checkbox" oninput="typeChannelBadge(${i}, event.target.checked)"></div>
            <div><input ${e.images ? "checked" : ""} type="checkbox" oninput="typeChannelImages(${i}, event.target.checked)"></div>
            <div><input ${e.telemetry ? "checked" : ""} type="checkbox" oninput="typeChannelTelemetry(${i}, event.target.checked)"></div>
            <div><input ${e.winlink ? "checked" : ""} type="checkbox" oninput="typeChannelWinlink(${i}, event.target.checked)"></div>
            <select onchange="genChannelKey(${i}, event.target.value)" ${e.readonly ? "disabled" : ""}>
                <option>new key</option>
                <option>1 byte</option>
                <option>128 bit</option>
                <option>256 bit</option>
            </select>
            <button onclick="rmChannel(${i})" ${e.readonly ? "disabled" : ""}>-</button>
            <button onclick="addChannel(${i})" ${e.readonly && ne.readonly ? "disabled" : ""}>+</button>
        </form>`;
    }).join("");
    return `<div class="config">
        <div class="t">Configure Channels</div>
        <div class="b">
            <div class="ct">
                <div>Name</div>
                <div>ID or Key</div>
                <div>Max messages</div>
                <div>Notify</div>
                <div>Images</div>
                <div>Telemetry</div>
                <div>Winlink</div>
            </div>
            ${body}
        </div>
        <div class="d"><button onclick="doneChannels()">Done</button></div>
    </div>`;
}

function htmlWinlinkMenu(menu)
{
    let main = "";
    for (let i = 0; i < menu.length; i++) {
        const submenu = menu[i][1];
        let sub = "";
        for (let j = 0; j < submenu.length; j++) {
            sub += `<div onclick="showNamekey('winlink-express-form ${menu[i][0]}/${submenu[j]}')">${submenu[j]}</div>`;
        }
        main += `<div><div>${menu[i][0]}</div><div><div>${sub}</div></div></div>`;
    }
    return main;
}

function domWinlink(formdata)
{
    const win = N("<div class='winlink'><iframe></iframe><button onclick='winlinkCancel()'>Cancel</button></div>");
    Q(win, "iframe").srcdoc = formdata;
    return win;
}

function updateMe(msg)
{
    me = nodeExpand(msg.node);
    nodes[me.num] = me;
    I("post").style.display = me.is_unmessagable ? "none" : null;
}

function updateNodes(msg)
{
    I("nodes").innerHTML = msg.nodes.map(n => {
        n = nodeExpand(n);
        nodes[n.num] = n
        return htmlNode(n);
    }).join("");
}

function updateFavorites(msg)
{
    I("favorites").innerHTML = msg.nodes.map(n => {
        n = nodeExpand(n);
        nodes[n.num] = n
        return htmlNode(n);
    }).join("");
}

function updateNode(msg)
{
    const node = nodeExpand(msg.node);
    nodes[node.num] = node;
    const nd = N(htmlNode(node));
    const nl = msg.node.favorite ? I("favorites") : I("nodes");
    if (document.visibilityState == "hidden") {
        const n = I(msg.node.id);
        if (n) {
            nl.removeChild(n);
        }
        nl.insertBefore(nd, nl.firstElementChild);
    }
    else {
        const n = I(msg.node.id);
        if (n) {
            nl.replaceChild(nd, n);
        }
        else {
            nl.insertBefore(nd, nl.firstElementChild);
            const s = I("nodes-scroll");
            const c = s.getBoundingClientRect();
            const r = nd.getBoundingClientRect();
            if (r.bottom >= c.top && r.top < c.bottom) {
                nd.classList.add("fade");
            }
            else {
                s.scrollTop += nd.offsetHeight;
            }
        }
    }
}

function updateTitle()
{
    let count = 0;
    for (let i = 0; i < channels.length; i++) {
        if (channels[i].state.badge) {
            count += channels[i].state.count;
        }
    }
    for (let i in directs) {
        count += directs[i].state.count;
    }
    document.title = `Raven Mesh Messaging${count > 0 ? " (" + count + " unread)" : ""}`;
}

function updateChannels(msg)
{
    if (msg) {
        channels = msg.channels;
    }
    I("channels").innerHTML = channels.map(c => htmlChannel(c)).join("");
    updateTitle();
}

function getChannelUnread(channel)
{
    return Q(`[data-namekey="${channel.namekey}"] .unread`);
}

function restartTextsObserver(channel)
{
    if (textObs) {
        textObs.disconnect();
    }
    textObs = new IntersectionObserver(entries => {
        let newest = null;
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                textObs.unobserve(entry.target);
                channel.state.count--;
                if (!newest || entry.time >= newest.time) {
                    newest = entry;
                    channel.state.cursor = entry.target.id;
                }
            }
        });
        if (newest) {
            getChannelUnread(channel).innerText = (channel.state.count > 0 ? channel.state.count : "");
            updateTitle();
            send({ cmd: "catchup", namekey: channel.namekey, id: channel.state.cursor });
            if (textObs.root.lastElementChild.id === channel.state.cursor) {
                restartTextsObserver(channel);
            }
        }
    }, { root: I("texts") });
}

function updateTexts(msg)
{
    clearTimeout(updateTextTimeout);
    const channel = getChannel(msg.namekey);
    channel.state = msg.state;
    resetPost();
    const t = I("texts");
    texts = msg.texts;
    t.innerHTML = msg.texts.map(t => htmlText(t, useImage(msg.namekey))).join("");
    restartTextsObserver(channel);
    if (channel.state.cursor) {
        I(channel.state.cursor).scrollIntoView({ behavior: "instant", block: "end", inline: "nearest" });
        for (let txt = t.firstElementChild; txt; txt = txt.nextSibling) {
            if (txt.id === channel.state.cursor) {
                for (txt = txt.nextSibling; txt; txt = txt.nextSibling) {
                    textObs.observe(txt);
                }
                break;
            }
        }
    }
    else if (t.firstElementChild) {
        const container = t.getBoundingClientRect();
        function onScreen(e)
        {
            const r = e.getBoundingClientRect();
            return r.bottom >= container.top && r.top < container.bottom;
        }
        t.firstElementChild.scrollIntoView({ behavior: "instant", block: "start", inline: "nearest" });
        for (let txt = t.firstElementChild; txt; txt = txt.nextSibling) {
            if (onScreen(txt)) {
                channel.state.count--;
                channel.state.cursor = txt.id
            }
            else {
                textObs.observe(txt);
            }
        }
        if (channel.state.cursor) {
            send({ cmd: "catchup", namekey: channel.namekey, id: channel.state.cursor });
        }
    }
    getChannelUnread(channel).innerText = (channel.state.count > 0 ? channel.state.count : "");
    updateTitle();
}

function updateText(msg)
{
    if (texts.find(t => t.id === msg.id)) {
        return;
    }
    const t = I("texts");
    const atbottom = (t.scrollTop > t.scrollHeight - t.clientHeight - 50);
    texts.push(msg.text);
    const n = t.appendChild(N(htmlText(msg.text, useImage(msg.namekey))));
    if (atbottom && document.visibilityState == "visible") {
        t.lastElementChild.scrollIntoView({ behavior: "smooth", block: "end", inline: "nearest" });
        send({ cmd: "catchup", namekey: msg.namekey, id: msg.text.id });
    }
    else {
        textObs.observe(n);
        const channel = getChannel(msg.namekey);
        channel.state.count++;
        getChannelUnread(channel).innerText = channel.state.count;
        updateTitle();
    }
}

function updateState(msg)
{
    if (isDirect(msg.namekey)) {
        addDirect(msg.namekey);
    }
    const channel = getChannel(msg.namekey);
    if (channel) {
        channel.state = msg.state;
        getChannelUnread(channel).innerText = (channel.state.count > 0 ? channel.state.count : "");
        updateTitle();
    }
}

function updateNodeDetails(node)
{
    I("rheader").innerHTML = htmlNodeDetail(node);
}

function toggleFav(event, nodenum)
{
    const node = nodes[nodenum];
    if (node) {
        node.favorite = !node.favorite;
        if (node.favorite) {
            event.target.classList.add("true");
        }
        else {
            event.target.classList.remove("true");
        }
        send({ cmd: "fav", id: nodenum, favorite: node.favorite });
    }
}

function sendMessage(event)
{
    const text = event.target.value;
    if (event.type === "keyup") {
        Q("#post .count").innerText = `${Math.max(0, text.length)}/200`;
    }
    else if (event.key === "Escape") {
        resetPost();
    }
    else if (event.key === "Enter" && !event.shiftKey) {
        if (text) {
            I("texts").lastElementChild.scrollIntoView({ behavior: "smooth", block: "end", inline: "nearest" });
            const namekey = rightSelection;
            const rid = replyid;
            setTimeout(_ => send({ cmd: "post", namekey: namekey, text: text.trim(), replyto: rid }), 500);
            if (isDirect(rightSelection)) {
                const fav = Q(`.node-detail .star:not(.true)`);
                if (fav) {
                    fav.classList.add("true");
                }
            }
        }
        resetPost();
        return false;
    }
    return true;
}

function setupReply(event)
{
    const t = Q(event.target.parentNode, ".t");
    const tt = t.closest(".text");
    tt.scrollIntoView({ behavior: "smooth", block: "end", inline: "nearest" });
    replyid = tt.id;
    const p = I("post");
    const n = N(`<div class="rt"><div>${t.innerText}</div></div>`);
    if (p.firstElementChild.nodeName == "DIV") {
        p.firstElementChild.remove();
    }
    p.insertBefore(n, p.firstElementChild);
    const pt = Q(p, "textarea");
    if (pt.placeholder === "Direct Message ...") {
        pt.placeholder = "Direct Reply ...";
    }
    else if (pt.placeholder === "Message ...") {
        pt.placeholder = "Reply ...";
    }
    pt.focus();
}

function resetPost()
{
    replyid = null;
    const p = I("post");
    if (p.firstElementChild.nodeName == "DIV") {
        p.firstElementChild.remove();
    }
    const t = Q(p, "textarea");
    t.value = "";
    p.style.display = null;
    const w = I("winmenu");
    if (me.is_unmessagable || rightSelection === "channel-config" || rightSelection.indexOf("winlink-express-") === 0) {
        p.style.display = "none";
    }
    else if (isDirect(rightSelection)) {
        t.placeholder = "Direct Message ...";
        if (nodes[rightSelection.split(" ")[1]]?.is_unmessagable) {
            p.style.display = "none";
        }
        w.style.display = winlink && getChannel(rightSelection)?.state?.winlink ? null : "none";
    }
    else {
        t.placeholder = "Message ...";
        w.style.display = winlink && getChannel(rightSelection)?.state?.winlink ? null : "none";
    }
}

function useImage(namekey)
{
    const channel = getChannel(namekey);
    return channel && !channel.meshtastic && channel.state.images;
}

function drag(event)
{
    event.preventDefault();
    if (useImage(rightSelection)) {
        if (event.type === "dragenter") {
            event.target.classList.add("drop");
            event.target.placeholder = "Drop image here ...";
        }
        else {
            event.target.classList.remove("drop");
            event.target.placeholder = "Message ...";
        }
    }
}

function sendDrop(event)
{
    event.preventDefault();
    event.target.classList.remove("drop");
    event.target.placeholder = "Message ...";
    if (!useImage(rightSelection)) {
        return;
    }
    dropSelection = rightSelection;
    const file = event.dataTransfer.files[0];
    switch (file?.type ?? "-") {
        case "image/jpeg":
        case "image/png":
        case "image/gif":
        case "image/svg+xml":
        case "image/webp":
        {
            const reader = new FileReader();
            reader.onload = function()
            {
                const maxWidth = 1024;
                const maxHeight = 768;
                const img = new Image();
                img.onload = function()
                {
                    const canvas = document.createElement('canvas');
                    if (img.width > img.height) {
                        if (img.width > maxWidth) {
                            canvas.width = maxWidth;
                            canvas.height = img.height * maxWidth / img.width;
                        }
                        else {
                            canvas.width = img.width;
                            canvas.height = img.height;
                        }
                    }
                    else {
                        if (img.height > maxHeight) {
                            canvas.width = img.width * maxHeight / img.height;
                            canvas.height = maxHeight;
                        }
                        else {
                            canvas.width = img.width;
                            canvas.height = img.height;
                        }
                    }
                    const context = canvas.getContext('2d');
                    context.imageSmoothingEnabled = true;
                    context.drawImage(img, 0, 0, canvas.width,  canvas.height);
                    canvas.toBlob(blob => {
                        event.target.placeholder = "Uploading image ...";
                        send(blob);
                    }, "image/jpeg", 0.9);
                }
                img.src = reader.result;
            }
            reader.readAsDataURL(file);
            break;
        }
        default:
            break;
    }
}

function addChannel(idx)
{
    echannels.splice(idx + 1, 0, { name: "", key: "", max: 100, badge: true, images: true, telemetry: false, winlink: false });
    I("texts").innerHTML = htmlChannelConfig();
}

function rmChannel(idx)
{
    echannels.splice(idx, 1);
    I("texts").innerHTML = htmlChannelConfig();
}

function typeChannelName(idx, value)
{
    echannels[idx].name = value;
}

function typeChannelKey(idx, value)
{
    echannels[idx].key = value;
}

function typeChannelMax(idx, value)
{
    echannels[idx].max = value;
}

function typeChannelBadge(idx, value)
{
    echannels[idx].badge = value;
}

function typeChannelImages(idx, value)
{
    echannels[idx].images = value;
}

function typeChannelTelemetry(idx, value)
{
    for (let i = 0; i < echannels.length; i++) {
        echannels[i].telemetry = false;
    }
    if (value) {
        echannels[idx].telemetry = true;
    }
    else {
        echannels.find(c => c.meshtastic).telemetry = true;
    }
    I("texts").innerHTML = htmlChannelConfig();
}

function typeChannelWinlink(idx, value)
{
    echannels[idx].winlink = value;
}

function genChannelKey(idx, value)
{
    function bytesToBase64(bytes)
    {
        return btoa(Array.from(bytes, byte => String.fromCodePoint(byte)).join(""));
    }
    function rand() {
        return Math.floor(Math.random() * 255);
    }
    let key = null;
    switch (value) {
        case "1 byte":
            key = [ rand() ];
            break;
        case "128 bit":
            key = [ rand(), rand(), rand(), rand(), rand(), rand(), rand(), rand() ];
            break;
        case "256 bit":
            key = [ rand(), rand(), rand(), rand(), rand(), rand(), rand(), rand(),
                    rand(), rand(), rand(), rand(), rand(), rand(), rand(), rand() ];
            break;
        default:
            break;
    }
    if (key) {
        echannels[idx].key = bytesToBase64(key);
        I("texts").innerHTML = htmlChannelConfig();
    }
}

function doneChannels()
{
    const nchannels = [];
    const channelnames = [];
    echannels.forEach(e => {
        try {
            if (e.name.length >= 1 && e.key.length >= 4 && e.name.search(/[ \t]/) === -1 && atob(e.key) && e.max >= 10 && e.max <= 1000) {
                const namekey = `${e.name} ${e.key}`;
                const channel = getChannel(namekey) || { meshtastic: false, state: { count: 0, cursor: null, max: 100, badge: true, images: true } };
                channelnames.push({ namekey: namekey, max: e.max, badge: e.badge, images: e.images, telemetry: e.telemetry, winlink: e.winlink });
                channel.state.max = e.max;
                channel.state.badge = e.badge;
                channel.state.images = e.images;
                channel.state.winlink = e.winlink;
                channel.telemetry = e.telemetry;
                nchannels.push({ namekey: namekey, telemetry: channel.telemetry, meshtastic: channel.meshtastic, state: channel.state });
            }
        }
        catch (_) {
        }
    });
    updateChannels({ channels: nchannels });
    showNamekey(channelnames[0].namekey);
    send({ cmd: "newchannels", channels: channelnames });
}

function winlinkMenuShow()
{
    I("winmenu").classList.add("active");
}

function winlinkMenuHide()
{
    I("winmenu").classList.remove("active");
}

function winlinkMenu(msg)
{
    if (msg.menu.length) {
        const menus = Q("#winmenu .menus");
        menus.innerHTML = htmlWinlinkMenu(msg.menu);
        winlink = {};
        for (let i = 0; i < msg.menu.length; i++) {
            const submenu = msg.menu[i][1];
            for (let j = 0; j < submenu.length; j++) {
                winlink[`${msg.menu[i][0]}/${submenu[j]}`] = true;
            }
        }
    }
}

function winlinkFormDisplay(msg)
{
    const texts = I("texts");
    texts.textContent = null;
    clearTimeout(updateTextTimeout);
    texts.appendChild(domWinlink(msg.formdata));
    resetPost();
    const win = Q(texts, "iframe").contentWindow;
    function fixup()
    {
        if (!win.document.querySelector("div")) {
            setTimeout(fixup, 10);
            return;
        }
        const form = win.document.querySelector("form");
        if (form) {
            form.removeAttribute("action");
            form.setAttribute("onsubmit", "formDataToObject(event.target);window.top.winlinkSubmit(document.getElementById('parseme').value)");
        }
    }
    fixup();
}

function winlinkCancel()
{
    showNamekey(previousSelection);
}

function winlinkSubmit(formdata)
{
    const chan = getChannel(previousSelection);
    if (chan?.state?.winlink) {
        const namekey = previousSelection;
        const form = rightSelection.substr(21);
        setTimeout(_ => send({ cmd: "post", namekey: namekey, text: `[Winlink: ${form.replace("/", " | ")}]`, structuredtext: [ { winlink: { id: form, data: JSON.parse(formdata) } }] }), 500);
    }
    showNamekey(previousSelection);
}

function filterNodes(event)
{
    activeFilter = event.target.value.toLowerCase();
    const nodes = document.querySelectorAll("#nodes-container .node");
    if (!activeFilter) {
        for (let i = nodes.length - 1; i >= 0; i--) {
            nodes[i].style.display = null;
        }
    }
    else {
        for (let i = nodes.length - 1; i >= 0; i--) {
            const node = nodes[i];
            if (node.dataset.filter.indexOf(activeFilter) === -1) {
                node.style.display = "none";
                node.classList.remove("fade");
            }
            else {
                node.style.display = null;
            }
        }
    }
}

function showNamekey(namekey)
{
    if (namekey == rightSelection) {
        if (getChannel(namekey)) {
            I("texts").lastElementChild.scrollIntoView({ behavior: "smooth", block: "end", inline: "nearest" });
        }
    }
    else {
        previousSelection = rightSelection;
        rightSelection = namekey;
        updateChannels();
        const selected = Q("#nodes-container .node.selected");
        if (selected) {
            selected.classList.remove("selected");
        }
        I("rheader").innerHTML = "";
        if (namekey === "channel-config") {
            echannels = [];
            channels.forEach((c, i) => {
                const nk = c.namekey.split(" ");
                echannels.push({
                    name: nk[0],
                    key: nk[1],
                    meshtastic: c.meshtastic,
                    readonly: i < 2,
                    max: c.state.max,
                    badge: c.state.badge,
                    images: useImage(c.namekey),
                    telemetry: c.telemetry,
                    winlink: c.state.winlink
                });
            });
            I("texts").innerHTML = htmlChannelConfig();
            resetPost();
        }
        else {
            if (namekey.indexOf("winlink-express-form ") === 0) {
                send({ cmd: "winform", namekey: previousSelection, id: namekey.substr(21) });
            }
            else if (namekey.indexOf("winlink-express-show ") === 0) {
                send({ cmd: "winshow", namekey: previousSelection, id: namekey.substr(21) });
            }
            else {
                if (isDirect(namekey)) {
                    addDirect(namekey);
                    send({ cmd: "fullnode", id: namekey.split(" ")[1] });
                    Q(`[data-namekey="${namekey}"]`).classList.add("selected");
                }
                send({ cmd: "texts", namekey: namekey });
            }
            clearTimeout(updateTextTimeout);
            updateTextTimeout = setTimeout(_ => {
                I("texts").innerHTML = "";
                resetPost();
            }, 500);
        }
    }
}

function restartup()
{
    if (sock) {
        try {
            if (sock.readyState < 2) {
                sock.close();
            }
        }
        catch (_) {
        }
        sock = null;
        send = () => {};
        setTimeout(startup, 2000);
    }
}

function activity()
{
    clearTimeout(activityTimeout);
    activityTimeout = setTimeout(restartup, 70 * 1000);
}

function startup()
{
    sock = new WebSocket(`ws://${location.hostname}:4404`);
    sock.addEventListener("open", _ => {
        activity();
        send = (msg) => sock.send(msg instanceof Blob ? msg : JSON.stringify(msg));
    });
    sock.addEventListener("close", restartup);
    sock.addEventListener("error", restartup);
    sock.addEventListener("message", e => {
        activity();
        try {
            const msg = JSON.parse(e.data);
            switch (msg.event) {
                case "me":
                    updateMe(msg);
                    break;
                case "nodes":
                    updateNodes(msg);
                    break;
                case "favorites":
                    updateFavorites(msg);
                    break;
                case "channels":
                    if (!rightSelection) {
                        rightSelection = msg.channels[0].namekey;
                    }
                    updateChannels(msg);
                    break;
                case "texts":
                    if (rightSelection == msg.namekey) {
                        updateTexts(msg);
                    }
                    else {
                        updateState(msg);
                    }
                    break;
                case "node":
                    updateNode(msg);
                    break;
                case "fullnode":
                {
                    const node = nodeExpand(msg.node);
                    if (rightSelection == `DirectMessages ${node.num}`) {
                        updateNodeDetails(node);
                    }
                    break;
                }
                case "text":
                    if (rightSelection == msg.namekey) {
                        updateText(msg);
                    }
                    else {
                        updateState(msg);
                    }
                    break;
                case "catchup":
                    updateState(msg);
                    break;
                case "uploaded":
                {
                    Q("#post textarea").placeholder = "Message ...";
                    if (useImage(dropSelection)) {
                        const hostname = location.hostname.indexOf(".local.mesh") == -1 ? `${location.hostname}.local.mesh` : location.hostname;
                        I("texts").lastElementChild.scrollIntoView({ behavior: "smooth", block: "end", inline: "nearest" });
                        setTimeout(_ => send({ cmd: "post", namekey: dropSelection, text: `[Image]`, structuredtext: [ { image: { url: `http://${hostname}/cgi-bin/apps/raven/image?i=${msg.name}` } } ] }), 500);
                    }
                    break;
                }
                case "ack":
                {
                    const ack = Q(I(msg.id), ".ack");
                    if (ack) {
                        ack.classList.add(true);
                    }
                    break;
                }
                case "winmenu":
                    winlinkMenu(msg);
                    resetPost();
                    break;
                case "winform":
                case "winshow":
                    winlinkFormDisplay(msg);
                    break;
                case "beat":
                    break;
                default:
                    break;
            }
        }
        catch (_) {
        }
    });
}

document.addEventListener("DOMContentLoaded", startup);
