#!/usr/bin/ucode
import * as fs from "fs";

const q = getenv("QUERY_STRING") || "";
const m = match(q, /i=([^/&]*)/);
let img = `/tmp/apps/raven/images/${m ? m[1] : "NONE"}`;
let info = fs.stat(img);
let type = "image/jpeg";
if (!info) {
    img = "/www/apps/raven/ix.png";
    info = fs.stat(img);
    type = "image/png";
}
print("Status: 200 OK\r\n");
print(`Content-Type: ${type}\r\n`);
print(`Content-Length: ${info.size}\r\n`);
print("Access-Control-Allow-Origin: *\r\n");
print("\n");
const f = fs.open(img);
if (f) {
    for (;;) {
        const d = f.read(10240);
        if (!d) {
            break;
        }
        print(d);
    }
    f.close();
}
