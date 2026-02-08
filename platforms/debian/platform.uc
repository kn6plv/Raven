import * as fs from "fs";

let rootdir = "/tmp/raven";

/* export */ function setup(config)
{
    rootdir = config.platform_debian?.store ?? rootdir;
    function mkdirp(p)
    {
        const d = fs.dirname(p);
        if (d && !fs.access(d)) {
            mkdirp(d);
        }
        fs.mkdir(p);
    }
    mkdirp(rootdir);
}

/* export */ function shutdown()
{
}

/* export */ function mergePlatformConfig(config)
{
}

/* export */ function load(name)
{
    const data = fs.readfile(`${rootdir}/${name}.json`);
    return data ? json(data) : null;
}

/* export */ function loadbinary(name)
{
    return fs.readfile(`${rootdir}/${name}`);
}

/* export */ function store(name, data)
{
    fs.writefile(`${rootdir}/${name}.json`, sprintf("%.02J", data));
}

/* export */ function storebinary(name, data)
{
    fs.writefile(`${rootdir}/${name}.json`, data);
}

/* export */ function dirtree()
{
    return [];
}

/* export */ function fetch(url, timeout)
{
    const p = fs.popen(`curl --max-time ${timeout} --silent --output - ${url}`);
    if (!p) {
        return null;
    }
    const all = p.read("all");
    p.close();
    return all;
}

/* export */ function getTargetsByIdAndNamekey()
{
    return [];
}

/* export */ function getTargetById(id)
{
    return null;
}

/* export */ function getStoresByNamekey()
{
    return [];
}

/* export */ function publish()
{
}

/* export */ function badge(key, count)
{
}

/* export */ function auth(headers)
{
    return true;
};

/* export */ function tick()
{
}

/* export */ function process(msg)
{
}

/* export */ function refresh()
{
}

/* export */ function handle()
{
    return null;
}

/* export */ function handleChanges()
{
}

/* export */ function getMap()
{
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
