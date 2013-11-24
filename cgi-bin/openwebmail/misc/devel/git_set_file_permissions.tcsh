#!/bin/tcsh -f

# set the permissions on a git cloned directory
# so that you can run openwebmail directly out of it
# git clone http://github.com/openwebmail/openwebmail.git openwebmail-current

cd cgi-bin/openwebmail
foreach DIR (etc/sites.conf etc/users.conf etc/defaults etc/templates etc/styles etc/holidays etc/maps misc)
   chown -vR 0:0 $DIR
   chmod -vR 644 $DIR
   find $DIR -type d -exec chmod -v 755 {} \;
end

chown root:mail * auth/* quota/* modules/* shares/* misc/* etc/*
chmod -v 644 */*pl
chmod -v 4755 openwebmail*.pl
chmod -v 755 vacation.pl userstat.pl preload.pl
chmod -v 771 etc/users etc/sessions
chmod -v 640 etc/smtpauth.conf
cd ../..

cd data/openwebmail
chown -vR 0:0 *
chmod -vR 644 *
find . -type d -exec chmod -v 755 {} \;
cd ../..

chmod -v 755 cgi-bin data

