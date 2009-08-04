#!/bin/tcsh -f

# This script creates an openwebmail-current tarball by performing the following:
#  - check out the latest version from SVN
#  - generate a changes.txt file from the SVN logs
#  - update the release date and revision number in openwebmail.conf
#  - change the file permissions to the correct defaults
#  - tar it all up
#
# This script must be run as root!

if (`whoami` != "root") then
   echo "This script must be run as root (su -)... quitting."
   exit 1
endif

if (-d "openwebmail-current") then
   echo "Please remove the openwebmail-current directory to successfully run this script... quitting."
   exit 1
endif

set SVNCOMMAND = "/usr/local/bin/svn"
set SVNSERVER = "http://openwebmail.acatysmoof.com/svn/trunk/src"
set REVISIONNUMBERHEAD = `$SVNCOMMAND info $SVNSERVER --revision HEAD | grep 'Last Changed Rev:' | awk '{print $4}'`

# get revision information for -current
if (-f "openwebmail-current.tar.gz") then
   set REVISIONNUMBERLAST = `tar -xzOf openwebmail-current.tar.gz cgi-bin/openwebmail/etc/defaults/openwebmail.conf | grep Rev: | awk '{print $3}'`
else
   set REVISIONNUMBERLAST = 0
endif

# do we need to update?
if ($REVISIONNUMBERLAST >= 0 && $REVISIONNUMBERHEAD > 0) then
   if ($REVISIONNUMBERLAST == $REVISIONNUMBERHEAD) then
      echo "Last revision ($REVISIONNUMBERLAST) == HEAD revision ($REVISIONNUMBERHEAD). No update required."
      exit 0
   else
      echo "Updating last revision ($REVISIONNUMBERLAST) ==> HEAD revision ($REVISIONNUMBERHEAD)"
   endif
else
   echo "Could not get Last revision number and HEAD revision number. Aborting."
   exit 1
endif

# we're updating, remove the old one
if (-f "openwebmail-current.tar.gz") then
   rm openwebmail-current.tar.gz
endif

# check out latest from SVN
$SVNCOMMAND export $SVNSERVER openwebmail-current > /dev/null
cd openwebmail-current

# update the homepage mirror that ships with the software
if (`hostname` == "gouda.acatysmoof.com") then
  set CURRENTREVISIONDATE = `date "+%B %d, %Y"`
  set CURRENTREVISIONSTRING = "$CURRENTREVISIONDATE Rev $REVISIONNUMBERHEAD"
  echo "Updating homepage current: $CURRENTREVISIONSTRING ..."
  sed -e "s/([[:alpha:]]*[[:space:]]*[0-9]*,[[:space:]]*[0-9]*[[:space:]]*Rev[[:space:]][0-9]*)/($CURRENTREVISIONSTRING)/" -i '' /home/alex/openwebmail.acatysmoof.com/index.html

  echo "Updating mirror homepage..."
  sed 's#<head>#<head><base href="http://openwebmail.acatysmoof.com/">#' < /home/alex/openwebmail.acatysmoof.com/index.html > data/openwebmail/openwebmail.html
endif

# generate changes.txt from SVN logs
echo "Generating changes.txt file..."
$SVNCOMMAND log -rHEAD:1 $SVNSERVER | sed 's/[    ]*$//;s/^[      ]*//;/./,/^$/\!d;s/ [0-9][0-9]:.*lines$//;s/^\(r[0-9]*\) | \([a-z0-9]*\) | \([0-9-]*\)/\3 (\1 \2)/;s/-\{72\}/----------/' > data/openwebmail/doc/changes.txt

# update the revision number to HEAD
echo "Setting revision and release date..."
sed -e "s/^\(revision[[:space:]]*.*\) [0-9]* \(.*\)/\1 $REVISIONNUMBERHEAD \2/" -i '' cgi-bin/openwebmail/etc/defaults/openwebmail.conf

# update the release date
set RELEASEDATE = `date "+%Y%m%d"`
sed -e "s/^\(releasedate[[:space:]]*\)[0-9]*/\1$RELEASEDATE/" -i '' cgi-bin/openwebmail/etc/defaults/openwebmail.conf

# fix permissions
echo "Permissioning files..."
chmod 755 cgi-bin data
chown -R 0:0 cgi-bin data

chmod 755 cgi-bin/openwebmail data/openwebmail
chown -R 0:0 cgi-bin/openwebmail data/openwebmail

cd cgi-bin/openwebmail
foreach DIR (etc/sites.conf etc/users.conf etc/defaults etc/templates etc/styles etc/holidays etc/maps misc)
   chown -R 0:0 $DIR
   chmod -R 644 $DIR
   find $DIR -type d -exec chmod 755 {} \;
end

chown root:mail * auth/* quota/* modules/* shares/* misc/* etc/*
chmod 644 */*pl
chmod 4755 openwebmail*.pl
chmod 755 vacation.pl userstat.pl preload.pl
chmod 771 etc/users etc/sessions
chmod 640 etc/smtpauth.conf
cd ../..

cd data/openwebmail
chown -R 0:0 *
chmod -R 644 *
find . -type d -exec chmod 755 {} \;

# miniturize xinha javascript
cd javascript/xinha
./openwebmail_compress.pl

cd ../../../..

# pack it up
echo "Creating tarball..."
tar -czf ../openwebmail-current.tar.gz data cgi-bin
cd ..

# clean up
echo "Cleaning up..."
rm -rf openwebmail-current

# writing md5
md5 -r openwebmail-current.tar.gz | tee MD5SUM

echo "done."

