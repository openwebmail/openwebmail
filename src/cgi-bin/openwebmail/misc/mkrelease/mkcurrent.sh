#!/bin/sh
#
# this is used by author to create the tarball of openwebmail
#

tmpdir=/tmp/openwebmail.mkrelease.tmp
rm -Rf $tmpdir
mkdir $tmpdir
cd $tmpdir

q /usr/local/www/cgi-bin/openwebmail/etc/defaults/openwebmail.conf
q /usr/local/www/data/openwebmail/doc/changes.txt \
  /usr/local/www/data/openwebmail/index.html \
  /usr/local/www/cgi-bin/openwebmail/misc/mkrelease/notify.sh

#################################################################

echo "make new openwebmail-current.tar.gz? (y/N)"
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
   # nothing
else
   su webmail -c '/bin/sh /usr/local/www/cgi-bin/openwebmail/misc/mkrelease/notify.sh'
   exit
fi

cd /usr/local/www

echo strip script, lang, template and txt files
perl /usr/local/www/cgi-bin/openwebmail/misc/mkrelease/stripblank.pl \
cgi-bin/openwebmail/* \
cgi-bin/openwebmail/*/* \
cgi-bin/openwebmail/*/*/* \
data/openwebmail/* \
data/openwebmail/*/* \
data/openwebmail/*/*/*

echo collect openwebmail current files...

tar --exclude data/openwebmail/download \
    -zcBpf /$tmpdir/openwebmail-current.tar.gz cgi-bin/openwebmail data/openwebmail

echo extract files to $tmpdir...

cd $tmpdir

mkdir openwebmail-current
cd    openwebmail-current

tar -zxBpf ../openwebmail-current.tar.gz
rm ../openwebmail-current.tar.gz
rm -Rf cgi-bin/openwebmail/etc/*.db
rm -Rf cgi-bin/openwebmail/etc/maps/*.db
rm -Rf cgi-bin/openwebmail/etc/sessions/* cgi-bin/openwebmail/etc/sessions/.[A-z]*
rm -Rf cgi-bin/openwebmail/etc/users/*
rm -Rf cgi-bin/openwebmail/etc/users.conf/[a-z]*
rm -Rf data/openwebmail/screenshots
rm -Rf data/openwebmail/download
rm -Rf data/openwebmail/applet/mindterm2/*.jar data/openwebmail/applet/mindterm2/*.txt

cp cgi-bin/openwebmail/misc/mkrelease/openwebmail.conf cgi-bin/openwebmail/etc/openwebmail.conf
rm    cgi-bin/openwebmail/etc/addressbooks/* cgi-bin/openwebmail/etc/address.book* cgi-bin/openwebmail/etc/calendar.book*
touch cgi-bin/openwebmail/etc/addressbooks/global cgi-bin/openwebmail/etc/calendar.book

cd cgi-bin/openwebmail
patch -R -f -p1 -s < /usr/local/www/cgi-bin/openwebmail/misc/patches/suidperl2speedy_suidperl.patch
rm *.orig
cd ../..

echo fix permissions...

cd cgi-bin/openwebmail
for d in etc/sites.conf etc/users.conf etc/defaults etc/templates etc/styles etc/holidays etc/maps misc; do
   chown -R 0.0 $d
   chmod -R 644 $d
   find $d -type d -exec chmod 755 {} \;
done
chown root.mail * auth/* quota/* modules/* shares/* misc/* etc/*
chmod 644 */*pl
chmod 4755 openwebmail*.pl
chmod 755 vacation.pl userstat.pl preload.pl
chmod 771 etc/users etc/sessions
chmod 640 etc/smtpauth.conf
cd ../..

cd data/openwebmail
chown -R 0.0 *
chmod -R 644 *
find ./ -type d -exec chmod 755 {} \;
cd ../..

echo make openwebmail-current.tar.gz...

chmod 755 cgi-bin data
tar -zcBpf $tmpdir/openwebmail-current.tar.gz cgi-bin/openwebmail data/openwebmail

#################################################################

cd  $tmpdir

lastreleasetgz=`ls -tr /usr/local/www/data/openwebmail/download/release/openwebmail-?.*.tar.gz|tail -1`
if [ ! -z "$lastreleasetgz" -a -f "$lastreleasetgz" ]; then
   lastrelease=`echo $lastreleasetgz|sed -e 's/.*openwebmail-//'|sed -e 's/\.tar\.gz.*//'`

   echo make current-$lastrelease-openwebmail.diff.gz...

   cd $tmpdir
   mv openwebmail-current www

   mkdir www.orig
   cd www.orig
   tar -zxBpf $lastreleasetgz
   cd ..

   sh /usr/local/www/cgi-bin/openwebmail/misc/mkrelease/genmd5list.sh ./www.orig release >/dev/null
   sh /usr/local/www/cgi-bin/openwebmail/misc/mkrelease/genmd5list.sh ./www      current >/dev/null

   diff -ruN md5list.release md5list.current|grep '^+'|cut -c35-|grep openwebmail >$tmpdir/md5.diff
   cd /usr/local/www
   tar -zcBpf $tmpdir/current-$lastrelease-openwebmail.files.tar.gz -I $tmpdir/md5.diff

   cd $tmpdir

   rm -Rf \
   www.orig/data/openwebmail/images \
   www.orig/data/openwebmail/*.wav \
   www.orig/data/openwebmail/*.au \
   www.orig/data/openwebmail/index.html \
   www/data/openwebmail/images \
   www/data/openwebmail/*.wav \
   www/data/openwebmail/*.au \
   www/data/openwebmail/index.html

   diff -ruN www.orig www|grep -v '^Binary files '|gzip -9>current-$lastrelease-openwebmail.diff.gz

   # for old tgz without etc/defaults/ dir
   mv www.orig/cgi-bin/openwebmail/etc/openwebmail.conf.default  openwebmail.conf.default.orig 2>/dev/null
   mv www.orig/cgi-bin/openwebmail/etc/defaults/openwebmail.conf openwebmail.conf.default.orig 2>/dev/null
   mv www/cgi-bin/openwebmail/etc/defaults/openwebmail.conf      openwebmail.conf.default
   diff -ruN openwebmail.conf.default.orig openwebmail.conf.default > current-$lastrelease-openwebmail.conf.default.diff

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

   diff -ruN www.orig www > current-$lastrelease-lang-templates.diff

   rm -Rf www www.orig www.tmp www.orig.tmp \
          openwebmail.conf.default.orig \
          openwebmail.conf.default \
          md5list.release \
          md5list.current \
          md5.diff 2>/dev/null
fi

#################################################################

echo cp new stuff to download/current/...

if [ ! -d "/usr/local/www/data/openwebmail/download" ]; then
   mkdir /usr/local/www/data/openwebmail/download
fi
if [ ! -d "/usr/local/www/data/openwebmail/download/current" ]; then
   mkdir /usr/local/www/data/openwebmail/download/current
fi

cp /usr/local/www/data/openwebmail/doc/*.txt /usr/local/www/data/openwebmail/download/doc/

rm /usr/local/www/data/openwebmail/download/current/openwebmail*current*gz
for f in openwebmail-current.tar.gz \
         current-$lastrelease-openwebmail.files.tar.gz \
         current-$lastrelease-openwebmail.diff.gz \
         current-$lastrelease-openwebmail.conf.default.diff \
         current-$lastrelease-lang-templates.diff; do
   mv $tmpdir/$f /usr/local/www/data/openwebmail/download/current/
   chmod 644 /usr/local/www/data/openwebmail/download/current/$f
done
cd /usr/local/www/data/openwebmail/download/current
md5 -r current* openwebmail-current*>MD5SUM

#################################################################

releasedate=`grep '^releasedate' /usr/local/www/cgi-bin/openwebmail/etc/defaults/openwebmail.conf | cut -f3`
version=`grep '^version.*[2-9]\.' /usr/local/www/cgi-bin/openwebmail/etc/defaults/openwebmail.conf | cut -f4`

echo ""
echo "make snapshot/openwebmail-$version-$releasedate.tar.gz? (y/N)"
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo copy current to snapshot $version-$releasedate...
  cd /usr/local/www/data/openwebmail/download/snapshot
  cp /usr/local/www/data/openwebmail/download/current/openwebmail-current.tar.gz openwebmail-$version-$releasedate.tar.gz
  grep -v $releasedate MD5SUM >/tmp/.md5.tmp.$$
  md5 -r openwebmail-$version-$releasedate.tar.gz >> /tmp/.md5.tmp.$$
  cp /tmp/.md5.tmp.$$ MD5SUM
  rm /tmp/.md5.tmp.$$
fi

#################################################################

cd $tmpdir
su webmail -c '/bin/sh /usr/local/www/cgi-bin/openwebmail/misc/mkrelease/notify.sh'
cd ..
rmdir $tmpdir
