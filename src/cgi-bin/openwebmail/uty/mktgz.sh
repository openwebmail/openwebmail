#!/bin/sh
# this is used by author to create the tarball of openwebmail

rm -f /tmp/openwebmail-current.tgz 2>/dev/null

cd /usr/local/www
tar --exclude data/openwebmail/download \
    -zcBpf /tmp/openwebmail-current.tgz cgi-bin/openwebmail data/openwebmail

cd /tmp
rm -Rf openwebmail-current 2>/dev/null
mkdir openwebmail-current
cd    openwebmail-current

tar -zxBpf ../openwebmail-current.tgz 

rm -Rf cgi-bin/openwebmail/etc/*-session-*
rm -Rf cgi-bin/openwebmail/etc/sessions/*
rm -Rf cgi-bin/openwebmail/etc/users/*
#rm     cgi-bin/openwebmail/uty/mktgz.sh

chmod 755 data cgi-bin
chmod 750 cgi-bin/openwebmail/etc
chmod 770 cgi-bin/openwebmail/etc/users
chmod 770 cgi-bin/openwebmail/etc/sessions

cp /dev/null cgi-bin/openwebmail/etc/address.book
cp /dev/null cgi-bin/openwebmail/etc/filter.book

tar -zcBpf /tmp/openwebmail-current.tgz *

cp /usr/local/www/cgi-bin/openwebmail/doc/*.txt /usr/local/www/data/openwebmail/download/
mv /tmp/openwebmail-current.tgz /usr/local/www/data/openwebmail/download/
