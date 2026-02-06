#! /bin/sh

VERSION=0.0.1

ROOT=/tmp/raven-build-$$
SRC=$(dirname $0)/../..

rm -rf $ROOT/

mkdir -p $ROOT/control \
    $ROOT/data/www/cgi-bin/apps/raven \
    $ROOT/data/www/apps/raven \
    $ROOT/tmp/apps/raven \
    $ROOT/data/usr/local/raven/platforms/aredn $ROOT/data/usr/local/raven/crypto \
    $ROOT/data/etc/init.d \
    $ROOT/data/etc/local/mesh-firewall \
    $ROOT/data/etc/arednsysupgrade.d

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
cp $SRC/platforms/aredn/firewall $ROOT/data/etc/local/mesh-firewall/21-raven

chmod 755 $ROOT/control/postinst $ROOT/control/prerm $ROOT/data/etc/local/mesh-firewall/21-raven

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

chmod 755 $ROOT/data/www/apps/raven/* $ROOT/data/www/cgi-bin/apps/raven/admin $ROOT/data/www/cgi-bin/apps/raven/image

(cd $ROOT/control ; tar cfz ../control.tar.gz .)
(cd $ROOT/data ; tar cfz ../data.tar.gz .)
(cd $ROOT ; tar cfz raven_${VERSION}_all.ipk control.tar.gz data.tar.gz debian-binary)

mv $ROOT/raven_${VERSION}_all.ipk .
rm -rf $ROOT/
