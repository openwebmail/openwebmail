#!/bin/sh
pkgdir=$1
if [ -z "$pkgdir" ]; then
  pkgdir=/usr/local/www
fi
tagname=$2
if [ -z "$tagname" ]; then
   tagname=`hostname|cut -d. -f1`
fi
output=/tmp/md5list.$tagname
tmp=/tmp/md5list.$$

cd $pkgdir

find ./cgi-bin/openwebmail -type f -print \
|grep -v cgi-bin/openwebmail/etc/sessions \
|grep -v cgi-bin/openwebmail/etc/users \
|grep -v cgi-bin/openwebmail/etc/calendar.book \
|grep -v cgi-bin/openwebmail/etc/address.book \
|grep -v '\.db$' > $tmp

find ./data/openwebmail -type f -print \
|grep -v data/openwebmail/download >> $tmp

sort $tmp|xargs md5 -r> $output
rm $tmp
echo $output done
