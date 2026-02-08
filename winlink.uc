import * as node from "node";

const WINLINK_FORMS_DIR = "winlink/forms";
const menuitems = [];

export function formpost(id)
{
    let data = platform.loadbinary(`${WINLINK_FORMS_DIR}/${replace(id, /\.\./, "")}_Initial.html`);
    if (!data) {
        data = platform.loadbinary(`${WINLINK_FORMS_DIR}/${replace(id, /\.\./, "")} Initial.html`);
    }
    if (!data) {
        return null;
    }

    const me = node.getInfo();
    const loc = node.getLocation(true);

    data = replace(data, "onsubmit=", "xonsubmit=");
    data = replace(data, `action="http://{FormServer}:{FormPort}"`, `onsubmit="window.top.winlinkSubmit(event.target)"`);
    
    data = replace(data, /\{MsgSender\}/g, `${split(me.long_name, "-")[0]}`);
    data = replace(data, /\{SeqNum\}/g, "");
    data = replace(data, /\{Latitude\}/g, `${loc.lat}`);
    data = replace(data, /\{Longitude\}/g, `${loc.lon}`);
    data = replace(data, /\{GridSquare\}/g, "");
    data = replace(data, /\{GPS_SIGNED_DECIMAL\}/g, "");
    
    return data;
};

export function formview(id)
{
    let data = platform.loadbinary(`${WINLINK_FORMS_DIR}/${replace(id, /\.\./, "")}_Viewer.html`);
    if (!data) {
        data = platform.loadbinary(`${WINLINK_FORMS_DIR}/${replace(id, /\.\./, "")} Viewer.html`);
    }
    if (!data) {
        return null;
    }

    return data;
};

export function menu()
{
    return menuitems;
};

export function setup(config)
{
    const dirs = platform.dirtree(WINLINK_FORMS_DIR);
    for (let dir in dirs) {
        const contents = dirs[dir];
        if (contents) {
            const items = [];
            for (let file in contents) {
                if (substr(file, -12) === "Initial.html") {
                    const root = substr(file, 0, -13);
                    if ((contents[`${root}_Initial.html`] || contents[`${root} Initial.html`]) &&
                        (contents[`${root}_Viewer.html`] || contents[`${root} Viewer.html`])) {
                            push(items, root);
                    }
                }
            }
            sort(items);
            push(menuitems, [ dir, items ]);
        }
    }
    sort(menuitems, (a, b) => a[0] > b[0] ? -1 : a[0] < b[0] ? 1 : 0);
};

export function tick()
{
};

export function process(msg)
{
};
