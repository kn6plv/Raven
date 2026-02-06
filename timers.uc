
global.timers = {};

function setTimer(name, delay, timeout)
{
    if (type(timeout) === "string") {
        switch (substr(timeout, -1)) {
            case "m":
                timeout = int(timeout) * 60;
                break;
            case "h":
                timeout = int(timeout) * 60 * 60;
                break;
            case "s":
            default:
                timeout = int(timeout);
                break;
        }
    }
    if (type(delay) === "string") {
        switch (substr(delay, -1)) {
            case "m":
                delay = int(delay) * 60;
                break;
            case "h":
                delay = int(delay) * 60 * 60;
                break;
            case "s":
            default:
                delay = int(delay);
                break;
        }
    }
    timers[name] = { next: clock()[0] + delay, timeout: timeout };
}

export function setInterval(name, delay, timeout)
{
    setTimer(name, delay, timeout ?? delay);
};

export function setTimeout(name, timeout)
{
    setTimer(name, timeout, -1);
};

export function tick(name)
{
    const now = clock()[0];
    const timer = timers[name];
    if (timer && now >= timer.next) {
        if (timer.timeout === -1) {
            delete timers[name];
        }
        else {
            timer.next += timer.timeout;
        }
        return true;
    }
    return false;
};

export function trigger(name, delay)
{
    const timer = timers[name];
    if (timer) {
        timer.next = min(timer.next, clock()[0] + (delay ?? 0));
    }
};

export function minTimeout(limit)
{
    let next = 0xffffffffff;
    map(values(timers), timer => next = min(timer.next, next));
    return min(limit, max(0, next - clock()[0]));
};
