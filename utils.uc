export function utf8validCopy(input)
{
    if (input === null) {
        return null;
    }
    let output = "";
    for (let i = 0; i < length(input); ) {
        const b0 = ord(input, i++);
        switch (b0 & 0xC0) {
            case 0x00:
            case 0x40:
                output += uchr(b0);
                break;
            case 0x80:
                for (; (ord(input, i) & 0xC0) === 0x80; i++); // Error - resync
                break;
            case 0xC0:
                const b1 = ord(input, i++);
                if ((b1 & 0xC0) !== 0x80) {
                    for (; (ord(input, i) & 0xC0) === 0x80; i++); // Error - resync
                }
                else if ((b0 & 0xE0) === 0xE0) {
                    const b2 = ord(input, i++);
                    if ((b2 & 0xC0) !== 0x80) {
                        for (; (ord(input, i) & 0xC0) === 0x80; i++); // Error - resync
                    }
                    else if ((b0 & 0xF0) === 0xF0) {
                        const b3 = ord(input, i++);
                        if ((b3 & 0xC0) !== 0x80) {
                            for (; (ord(input, i) & 0xC0) === 0x80; i++); // Error - resync
                        }
                        else if ((b0 & 0xF8) === 0xF8) {
                            for (; (ord(input, i) & 0xC0) === 0x80; i++); // Error - resync
                        }
                        else {
                            output += uchr(((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F));
                        }
                    }
                    else {
                        output += uchr(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F));
                    }
                }
                else {
                    output += uchr(((b0 & 0x1F) << 6) | (b1 & 0x3F));
                }
                break;
        }
    }
    return output;
};
