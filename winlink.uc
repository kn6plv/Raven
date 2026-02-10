import * as node from "node";

const WINLINK_FORMS_DIR = "winlink/forms";
const menuitems = [];
const forms = {};

export function formpost(id)
{
    let data = platform.loadbinary(`${WINLINK_FORMS_DIR}/${forms[id]?.post}`);
    if (!data) {
        return null;
    }

    const me = node.getInfo();
    const loc = node.getLocation(true);
   
    data = replace(data, /\{MsgSender\}/ig, `${split(me.long_name, "-")[0]}`);
    data = replace(data, /\{SeqNum\}/ig, "");
    data = replace(data, /\{Latitude\}/ig, `${loc.lat}`);
    data = replace(data, /\{Longitude\}/ig, `${loc.lon}`);
    data = replace(data, /\{GridSquare\}/ig, "");
    data = replace(data, /\{GPS_SIGNED_DECIMAL\}/ig, "? ?");
    data = replace(data, /\{Location_Source\}/ig, "SPECIFIED");
    
    return data;
};

export function formshow(id, formdata)
{
    let data = platform.loadbinary(`${WINLINK_FORMS_DIR}/${forms[id]?.view}`);
    if (!data) {
        return null;
    }

    for (let key in formdata)
    {
        data = replace(data, regexp(`\\{var ${key}\\}`, "ig"), formdata[key]);
    }
    data = replace(data, /\{var [^}]+\}/ig, "");

    return data;
};

export function post(id, formdata)
{
    const keys = forms[id]?.keys;
    if (!keys) {
        return;
    }
    const nformdata = {};
    for (let i = 0; i < length(keys); i++) {
        const key = keys[i];
        if (formdata[key] !== null && formdata[key] !== "") {
            nformdata[key] = formdata[key];
        }
    }
    return sprintf("%J", { winlink: { id: id, data: nformdata } });
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
                if (substr(file, -4) === ".txt") {
                    const txt = platform.loadbinary(`${WINLINK_FORMS_DIR}/${dir}/${file}`);
                    if (txt) {
                        const formdata = match(split(txt, "\n", 2)[0], /^Form:([^,]+),(.+)$/);
                        if (formdata) {
                            const keys = map(match(txt, /<var ([^>]+)>/g), k => k[1]);
                            const root = substr(file, 0, -4);
                            forms[`${dir}/${root}`] = { post: `${dir}/${trim(formdata[1])}`, view: `${dir}/${trim(formdata[2])}`, keys: keys };
                            push(items, root);
                        }
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
