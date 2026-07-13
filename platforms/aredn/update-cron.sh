#! /bin/sh
rm -f /tmp/raven.apk
wget -q -T 5 -O /tmp/raven.apk https://github.com/kn6plv/Raven/raw/refs/heads/main/raven-alpha.apk
if [ -f /tmp/raven.apk ] && ! cmp -s /tmp/raven.apk /etc/package_store/raven.apk ; then
  mv /tmp/raven.apk /etc/package_store/raven.apk
  apk add --allow-untrusted /etc/package_store/raven.apk
fi
