#!/bin/sh
#
# this is used by author to create the tarball of openwebmail
#

q /usr/local/www/cgi-bin/openwebmail/etc/openwebmail.conf.default
q /usr/local/www/data/openwebmail/doc/changes.txt \
  /usr/local/www/data/openwebmail/index.html \
  /usr/local/www/cgi-bin/openwebmail/uty/notify.sh

##########################################################

echo "make new openwebmail-current.tgz? (y/N)"
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
   # nothing
else
   su webmail -c '/bin/sh /usr/local/www/cgi-bin/openwebmail/uty/notify.sh'
   exit
fi

echo make openwebmail-current.tgz

rm -f /tmp/openwebmail-current.tgz /tmp/openwebmail-current 2>/dev/null
cd /usr/local/www
tar --exclude data/openwebmail/download \
    -zcBpf /tmp/openwebmail-current.tgz cgi-bin/openwebmail data/openwebmail

cd /tmp
rm -Rf www www.orig etc etc.orig openwebmail.conf.default.orig openwebmail.conf.default 2>/dev/null
mkdir openwebmail-current
cd    openwebmail-current

tar -zxBpf ../openwebmail-current.tgz 

rm -Rf cgi-bin/openwebmail/hc
rm -Rf cgi-bin/openwebmail/hc.tab
rm -Rf cgi-bin/openwebmail/etc/*.db
rm -Rf cgi-bin/openwebmail/etc/*-session-*
rm -Rf cgi-bin/openwebmail/etc/sessions/* cgi-bin/openwebmail/etc/sessions/.[A-z]*
rm -Rf cgi-bin/openwebmail/etc/users/*
rm -Rf data/openwebmail/screenshots
rm -Rf data/openwebmail/download
rm -Rf data/openwebmail/applet/mindterm2/*.jar data/openwebmail/applet/mindterm2/*.txt

chmod 755 data cgi-bin
chmod 755 cgi-bin/openwebmail/etc
chmod 770 cgi-bin/openwebmail/etc/users
chmod 770 cgi-bin/openwebmail/etc/sessions

cp /dev/null cgi-bin/openwebmail/etc/address.book
cp /dev/null cgi-bin/openwebmail/etc/calendar.book
#cp /dev/null cgi-bin/openwebmail/etc/filter.book
patch cgi-bin/openwebmail/etc/openwebmail.conf < /usr/local/www/cgi-bin/openwebmail/uty/openwebmail.conf.diff
rm cgi-bin/openwebmail/etc/openwebmail.conf.orig
rm cgi-bin/openwebmail/etc/openwebmail.conf.rej
chown root.mail cgi-bin/openwebmail/etc/openwebmail.conf

cd cgi-bin/openwebmail
patch -f -p1 < /usr/local/www/cgi-bin/openwebmail/uty/speedy2suidperl.diff
rm *.orig
chown root.mail openwebmail*pl
chmod 4755 openwebmail*pl
cd ../..

tar -zcBpf /tmp/openwebmail-current.tgz *

##########################################################

oldtgz=`ls -tr /usr/local/www/data/openwebmail/download/openwebmail-?.*tgz|tail -1`
if [ ! -z "$oldtgz" ]; then
   oldrelease=`echo $oldtgz|sed -e 's/.*openwebmail-//'|sed -e 's/\.tgz.*//'`

   echo make openwebmail-current-$oldrelease.diff.gz

   cd /tmp
   mv openwebmail-current www

   mkdir www.orig
   cd www.orig
   tar -zxBpf $oldtgz
   cd ..

   sh /usr/local/www/cgi-bin/openwebmail/uty/mkmd5list.sh ./www.orig release
   sh /usr/local/www/cgi-bin/openwebmail/uty/mkmd5list.sh ./www      current
   diff -ruN /tmp/md5list.release /tmp/md5list.current|grep '^+'|cut -c35-|grep openwebmail >/tmp/md5.diff
   cd /usr/local/www
   tar -zcBpf /tmp/openwebmail-current-$oldrelease.files.tgz -I /tmp/md5.diff

   cd /tmp
   rm -Rf \
   www.orig/data/openwebmail/images \
   www.orig/data/openwebmail/*.wav \
   www.orig/data/openwebmail/*.au \
   www.orig/data/openwebmail/index.html \
   www/data/openwebmail/images \
   www/data/openwebmail/*.wav \
   www/data/openwebmail/*.au \
   www/data/openwebmail/index.html

   diff -ruN www.orig www|grep -v '^Binary files '|gzip -9>openwebmail-current-$oldrelease.diff.gz

   mv www.orig/cgi-bin/openwebmail/etc/openwebmail.conf.default openwebmail.conf.default.orig
   mv www/cgi-bin/openwebmail/etc/openwebmail.conf.default      openwebmail.conf.default
   diff -ruN openwebmail.conf.default.orig openwebmail.conf.default > openwebmail.conf.default-current-$oldrelease.diff

   mv www.orig www.orig.tmp
   mv www www.tmp

   mkdir -p \
   www.orig/cgi-bin/openwebmail/etc/template \
   www.orig/cgi-bin/openwebmail/etc/lang \
   www.orig/data/openwebmail/javascript/htmlarea.openwebmail/popups \
   www/cgi-bin/openwebmail/etc/template \
   www/cgi-bin/openwebmail/etc/lang \
   www/data/openwebmail/javascript/htmlarea.openwebmail/popups \

   for d in cgi-bin/openwebmail/etc/lang \
            cgi-bin/openwebmail/etc/templates \
            data/openwebmail/javascript/htmlarea.openwebmail/popups; do
      mv www.orig.tmp/$d/en www.orig/$d/
      mv www.tmp/$d/en www/$d/
   done

   diff -ruN www.orig www > lang-templates-current-$oldrelease.diff

   rm -Rf www www.orig www.tmp www.orig.tmp \
          openwebmail.conf.default.orig \
          openwebmail.conf.default \
          md5list.release \
          md5list.current \
          md5.diff 2>/dev/null
fi

##########################################################

echo cp new stuff to download

if [ ! -d "/usr/local/www/data/openwebmail/download" ]; then
   mkdir /usr/local/www/data/openwebmail/download
fi

cp /usr/local/www/data/openwebmail/doc/*.txt /usr/local/www/data/openwebmail/download/doc/

rm /usr/local/www/data/openwebmail/download/openwebmail*current*gz 
for f in openwebmail-current.tgz \
         openwebmail-current-$oldrelease.files.tgz \
         openwebmail-current-$oldrelease.diff.gz \
         openwebmail.conf.default-current-$oldrelease.diff \
         lang-templates-current-$oldrelease.diff; do
   mv /tmp/$f /usr/local/www/data/openwebmail/download/
   chmod 644 /usr/local/www/data/openwebmail/download/$f
done

su webmail -c '/bin/sh /usr/local/www/cgi-bin/openwebmail/uty/notify.sh'
