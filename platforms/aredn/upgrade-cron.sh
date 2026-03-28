#! /bin/sh
if [ -f /etc/package_store/raven.apk ]; then
    wget -q -T 5 -O /tmp/raven.apk https://github.com/kn6plv/Raven/raw/refs/heads/main/raven-alpha.apk
    if cmp -s /tmp/raven.apk /etc/package_store/raven.apk ; then
        mv /tmp/raven.apk /etc/package_store/raven.apk
        apk add --allow-untrusted /etc/package_store/raven.apk
    fi
fi
if [ -f /etc/package_store/raven.ipk ]; then
    wget -q -T 5 -O /tmp/raven.ipk https://github.com/kn6plv/Raven/raw/refs/heads/main/raven-alpha.ipk
    if cmp -s /tmp/raven.ipk /etc/package_store/raven.ipk ; then
        mv /tmp/raven.ipk /etc/package_store/raven.ipk
        opkg -force-overwrite install /etc/package_store/raven.ipk
    fi
fi
