#!/bin/sh
#
# this is used by author to create the tarball of openwebmail
#

##########################################################

echo make openwebmail-current.tgz

rm -f /tmp/openwebmail-current.tgz 2>/dev/null
cd /usr/local/www
tar --exclude data/openwebmail/download \
    -zcBpf /tmp/openwebmail-current.tgz cgi-bin/openwebmail data/openwebmail

cd /tmp
rm -Rf openwebmail-current www.orig www 2>/dev/null
mkdir openwebmail-current
cd    openwebmail-current

tar -zxBpf ../openwebmail-current.tgz 

rm -Rf cgi-bin/openwebmail/hc
rm -Rf cgi-bin/openwebmail/hc.tab
rm -Rf cgi-bin/openwebmail/etc/*.db
rm -Rf cgi-bin/openwebmail/etc/*-session-*
rm -Rf cgi-bin/openwebmail/etc/sessions/*
rm -Rf cgi-bin/openwebmail/etc/users/*
rm -Rf data/openwebmail/screenshots
rm -Rf data/openwebmail/download
#rm     cgi-bin/openwebmail/uty/mktgz.sh

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
   cp www.orig/cgi-bin/openwebmail/etc/openwebmail.conf.default openwebmail.conf.default.orig
   cp www/cgi-bin/openwebmail/etc/openwebmail.conf.default      openwebmail.conf.default
   diff -ruN openwebmail.conf.default.orig openwebmail.conf.default >openwebmail.conf.default-current-$oldrelease.diff

   rm -Rf www.orig openwebmail.conf.default.orig openwebmail.conf.default
   mv www openwebmail-current
fi

##########################################################

echo cp new stuff to download

cp /usr/local/www/data/openwebmail/doc/*.txt /usr/local/www/data/openwebmail/download/doc/

rm /usr/local/www/data/openwebmail/download/openwebmail*current*gz 
for f in openwebmail-current.tgz openwebmail-current-$oldrelease.diff.gz openwebmail.conf.default-current-$oldrelease.diff; do
   mv /tmp/$f /usr/local/www/data/openwebmail/download/
   chmod 644 /usr/local/www/data/openwebmail/download/$f
done

su webmail -c '/bin/sh /usr/local/www/cgi-bin/openwebmail/uty/notify.sh'
