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
#cp /dev/null cgi-bin/openwebmail/etc/filter.book
patch cgi-bin/openwebmail/etc/openwebmail.conf < /usr/local/www/cgi-bin/openwebmail/uty/openwebmail.conf.diff
rm cgi-bin/openwebmail/etc/openwebmail.conf.orig

tar -zcBpf /tmp/openwebmail-current.tgz *

cp /usr/local/www/data/openwebmail/doc/*.txt /usr/local/www/data/openwebmail/download/doc/
rm /usr/local/www/data/openwebmail/download/openwebmail-current.tgz
mv /tmp/openwebmail-current.tgz /usr/local/www/data/openwebmail/download/
chmod 644 /usr/local/www/data/openwebmail/download/openwebmail-current.tgz

date=`date "+%y%m%d"`

echo send openwebmail-current.tgz to mirror sites?
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo sending to mirror sites...

  echo "openwebmail current $date"| \
  /usr/local/bin/mutt -s "openwebmail current $date" \
  -a /usr/local/www/data/openwebmail/download/openwebmail-current.tgz \
  -a /usr/local/www/data/openwebmail/download/doc/changes.txt \
  openwebmail@turtle.ee.ncku.edu.tw \
  tchung@oaolinux.jpl.nasa.gov \
  elitric@hotmail.com 
fi

echo send openwebmail-current.tgz/chnages.txt to translators?
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo sending to translators...

  echo "openwebmail current $date">/tmp/mktgz.tmp.$$
  q /tmp/mktgz.tmp.$$
  cat /tmp/mktgz.tmp.$$| \
  /usr/local/bin/mutt -s "openwebmail current $date" \
  -a /usr/local/www/data/openwebmail/download/openwebmail-current.tgz \
  -a /usr/local/www/data/openwebmail/download/doc/changes.txt \
  st@e-puntcom.com \
  ruisb@ig.com.br \  
  gumo@lucifer.kgt.bme.hu \
  ful_s@fazekas.hu \
  jferra@sfconsultores.pt \
  flood@flood-net.de \
  lubos@klokner.sk \
  c.sabatier@bocquet.com \
  tryfan@telia.com \
  jablonski@dialogok.pl \
  jsmaldone@yahoo.com \
  wjun@mail.iap.ac.cn \
  michiel@connectux.com \
  lvm@mystery.lviv.net \
  kivilahti@exdecfinland.org \
  heljalaitinen@hotmail.com \
  michal@stavlib.hiedu.cz

  echo "openwebmail current $date is available at
http://turtle.ee.ncku.edu.tw/openwebmail/download/openwebmail-current.tgz">/tmp/mktgz.tmp.$$
  q /tmp/mktgz.tmp.$$
  cat /tmp/mktgz.tmp.$$| \
  /usr/local/bin/mutt -s "openwebmail current $date" \
  -a /usr/local/www/data/openwebmail/download/doc/changes.txt \
  i3100579@ingstud.units.it \
  frank@post12.tele.dk

  rm /tmp/mktgz.tmp.$$
fi
