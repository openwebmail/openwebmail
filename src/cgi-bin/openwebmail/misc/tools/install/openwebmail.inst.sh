#!/bin/sh
# this script is for freebsd.
# it installs openwebmail to /usr/local/www/cgi-bin/openwebmail
#                        and /usr/local/www/data/openwebmail

tmpdir=/tmp/openwebmail.inst.tmp
mkdir $tmpdir
cd $tmpdir

unset HTTP_PROXY
unset http_proxy
mv openwebmail-current.tar.gz openwebmail-current.tar.gz.orig
wget http://turtle.ee.ncku.edu.tw/openwebmail/download/current/openwebmail-current.tar.gz

cd /usr/local/www/cgi-bin/openwebmail/etc
cp openwebmail.conf calendar.book filter.book addressbooks/global $tmpdir

cd /usr/local/www
tar -zxBpf $tmpdir/openwebmail-current.tar.gz

cd /usr/local/www/cgi-bin/openwebmail

cp $tmpdir/openwebmail.conf $tmpdir/calendar.book $tmpdir/filter.book etc
cp $tmpdir/global etc/addressbooks/

# for perl 5.6 or above
echo "has_savedsuid_support	no">etc/suid.conf

sync; sync; sync;

./openwebmail-tool.pl --init --no

if [ -f /usr/local/bin/speedy_suid -a ! -f /usr/local/bin/speedy_suidperl ];  then
   ln -s /usr/local/bin/speedy_suid /usr/local/bin/speedy_suidperl
fi

patch -p1 < misc/patches/suidperl2speedy_suidperl.patch
#cat misc/patches/suidperl2speedy_suidperl.patch | \
#  sed -e 's/local\/bin\/speedy_suid/bin\/speedy_suid/'|patch -p1

\rm *orig
chgrp mail op*pl

./preload.pl openwebmail.pl openwebmail-main.pl
