#! /bin/sh

VER=0.0.1
REL=r$(($(date +%s) - $(date -d "2026-01-01 00:00:00" +%s)))
VERSION=${VER}-${REL}

ROOT=/tmp/raven-build-$$
SRC=$(dirname $0)/../..

rm -rf $ROOT/

mkdir -p $ROOT/data/www/cgi-bin/apps/raven \
    $ROOT/data/www/apps/raven \
    $ROOT/data/usr/local/raven/platforms/aredn $ROOT/data/usr/local/raven/crypto \
    $ROOT/data/etc/init.d \
    $ROOT/data/etc/local/mesh-firewall \
    $ROOT/data/etc/arednsysupgrade.d

cp $SRC/platforms/aredn/firewall $ROOT/data/etc/local/mesh-firewall/21-raven

cp $SRC/*.uc $ROOT/data/usr/local/raven/
cp $SRC/crypto/*.uc $ROOT/data/usr/local/raven/crypto/
cp $SRC/platforms/aredn/*.uc $ROOT/data/usr/local/raven/platforms/aredn/
cp $SRC/platforms/aredn/raven.conf $ROOT/data/usr/local/raven/

cp $SRC/ui/index.html $SRC/ui/ui.js $SRC/ui/ui.css $SRC/ui/raven.svg $ROOT/data/www/apps/raven/
cp $SRC/ui/raven.svg $ROOT/data/www/apps/raven/icon.svg
cp $SRC/ui/ix.png $ROOT/data/www/apps/raven/ix.png
cp $SRC/platforms/aredn/admin.sh $ROOT/data/www/cgi-bin/apps/raven/admin
cp $SRC/platforms/aredn/image.uc $ROOT/data/www/cgi-bin/apps/raven/image

cp $SRC/platforms/aredn/raven.init $ROOT/data/etc/init.d/raven

cp $SRC/platforms/aredn/upgrade.conf $ROOT/data/etc/arednsysupgrade.d/KN6PLV.raven.conf

echo "export const version = '${VERSION}';" > $ROOT/data/usr/local/raven/version.uc

chmod 755 $ROOT/data/etc/local/mesh-firewall/21-raven
chmod 755 $ROOT/data/www/apps/raven/* $ROOT/data/www/cgi-bin/apps/raven/admin $ROOT/data/www/cgi-bin/apps/raven/image

mkdir -p $ROOT/data/usr/local/raven/winlink/forms
cp -R $SRC/winlink/forms/* $ROOT/data/usr/local/raven/winlink/forms

#
# Make IPKG
#
mkdir -p $ROOT/control
cat > $ROOT/debian-binary <<__EOF__
2.0
__EOF__
cat > $ROOT/control/control <<__EOF__
Package: raven
Version: ${VERSION}
Depends: ucode, curl
Provides:
Source: package/raven
Section: net
Priority: optional
Maintainer: Tim Wilkinson (KN6PLV)
Architecture: all
Description: Mesh communications
__EOF__
cp $SRC/platforms/aredn/postinst $ROOT/control/postinst
cp $SRC/platforms/aredn/prerm $ROOT/control/prerm
chmod 755 $ROOT/control/postinst $ROOT/control/prerm

(cd $ROOT/control ; tar cfz ../control.tar.gz .)
(cd $ROOT/data ; tar cfz ../data.tar.gz .)
(cd $ROOT ; tar cfz raven_${VERSION}_all.ipk control.tar.gz data.tar.gz debian-binary)

rm -f ./raven_*_all.ipk
mv $ROOT/raven_${VERSION}_all.ipk .

#
# Make APK
#
rm -f ./raven-*.apk
cp $SRC/platforms/aredn/postinstall $ROOT/data/.post-install
cp $SRC/platforms/aredn/prerm $ROOT/data/.pre-deinstall
cp $SRC/platforms/aredn/postupgrade $ROOT/data/.post-upgrade
chmod 755 $ROOT/data/.post-install $ROOT/data/.pre-deinstall $ROOT/data/.post-upgrade
mkapk.py \
    -n raven \
    -v ${VER} \
    -d ${ROOT}/data \
    -a noarch \
    -r ${REL} \
    -D 'Raven Mesh Messaging' \
    -u 'https://github.com/kn6plv/raven' \
    -l 'MIT' \
    -m 'tim.j.wilkinson@gmail.com' \
    -p ucode,curl \
    -o .

rm -rf $ROOT/
