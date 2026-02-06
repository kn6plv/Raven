#!/usr/bin/ucode

import * as config from "./config.uc";

config.setup();
for (;;) {
    config.tick();
}
