#!/bin/sh
# genmd5list dirname md5file

pkgdir=$1
if [ -z "$pkgdir" ]; then
  pkgdir=/usr/local/www
fi
tagname=$2
if [ -z "$tagname" ]; then
   tagname=`hostname|cut -d. -f1`
fi

pwd=`pwd`
output=$pwd/md5list.$tagname
tmpfile=$pwd/md5list.tmp.$$

cd $pkgdir

find ./cgi-bin/openwebmail -type f -print \
|grep -v cgi-bin/openwebmail/etc/sessions \
|grep -v cgi-bin/openwebmail/etc/users \
|grep -v cgi-bin/openwebmail/etc/calendar.book \
|grep -v cgi-bin/openwebmail/etc/address.book \
|grep -v '\.db$' > $tmpfile

find ./data/openwebmail -type f -print \
|grep -v data/openwebmail/download >> $tmpfile

sort $tmpfile|xargs md5 -r 2>/dev/null > $output
rm $tmpfile
echo $output done
