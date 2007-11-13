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
   echo "Please remove the openwebmail-current directory before running this script... quitting."
   exit 1
endif

if (-f "openwebmail-current.tar.gz") then
   rm openwebmail-current.tar.gz
endif

set SVNSERVER = "svn://openwebmail.acatysmoof.com/openwebmail/trunk/src"

# check out latest from SVN
svn export $SVNSERVER openwebmail-current
cd openwebmail-current

# generate changes.txt from SVN logs
echo "Generating changes.txt file..."
svn log -rHEAD:1 $SVNSERVER | sed 's/[    ]*$//;s/^[      ]*//;/./,/^$/\!d;s/ [0-9][0-9]:.*lines$//;s/^\(r[0-9]*\) | \([a-z0-9]*\) | \([0-9-]*\)/\3 (\1 \2)/;s/-\{72\}/----------/' > data/openwebmail/doc/changes.txt

# update the revision number to HEAD
echo "Setting revision and release date..."
set REVISIONNUMBER = `svn log -rHEAD $SVNSERVER | sed -n '2p' | cut -d' ' -f1 | sed s/r//`
sed -e "s/\(revision[[:space:]]*.*\) [0-9]* \(.*\)/\1 $REVISIONNUMBER \2/" -i '' cgi-bin/openwebmail/etc/defaults/openwebmail.conf

# update the release date
set RELEASEDATE = `date "+%Y%m%d"`
sed -e "s/\(releasedate[[:space:]]*\)[0-9]*/\1$RELEASEDATE/" -i '' cgi-bin/openwebmail/etc/defaults/openwebmail.conf

# fix permissions
echo "Permissioning files..."
chmod 755 cgi-bin data

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
cd ../..

# pack it up
echo "Creating tarball..."
tar -czf ../openwebmail-current.tar.gz data cgi-bin
cd ..

# clean up
echo "Cleaning up..."
rm -rf openwebmail-current

echo "done."

