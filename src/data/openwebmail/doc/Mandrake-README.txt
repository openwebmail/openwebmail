
Date: 10/20/2002
Last Revision: 10/20/2002
Author:  Paul Kelly (pksings.AT.users.forge.net)
File: Mandrake-README.txt

------------------------------------------------------------------------------
                       OPENWEBMAIL ON MANDRAKE 9.0 HOWTO
------------------------------------------------------------------------------

1. Download redhat RPM and tar/gzipped packages.
   You will need both. Make sure you get the latest released version of
   openwebmail, openwebmail-x.yy.tar.gz

2. Make sure you have all of Perl installed. I did not.
   And it was the cause of much frustration.
   And I had taken the installation route that supposedly installed all
   of it. I had to download all the packages and re-install them with
   the --force flag

3. Install the Openwebmail.rpm file.

4. Copy or move the latest openwebmail-x.yy.tar.gz" file to /var/www.
   Unzip it there, it will write over the existing (older) version.

5. Now the fun begins, this is what you have to do to make it work.....

a. In /etc/httpd/conf/commonhttpd.conf

Find the section appropriate for each of the following stanzas and add them.

<Directory /var/www/cgi-bin/openwebmail>
AllowOverride All
Options +ExecCGI
Order allow,deny
Allow from all
</Directory>>

Alias /cgi-bin/openwebmail /var/www/cgi-bin/openwebmail

AddHandler cgi-script .cgi .pl ( just add .pl onto the end of existing )

b. Edit /var/www/cgi-bin/openwebmail/etc/openwebmail.conf

There is an example of this file in it's correct format below.

change /var/mail to /var/spool/mail
change /var/log/openwebmail.log to /var/log/webmail/openwebmail.log (optional)

add "default_realname auto" line
this makes "from"line in webmail use login name.

c. Edit /var/www/cgi-bin/openwebmail/etc/dbm.conf

dbm_ext         .dir
dbmopen_ext     none
dbmopen_haslock yes

This parameter is only present and working in version 1.71 and
somehow Mandrake 9.0 requires it.

d. Edit /var/www/cgi-bin/openwebmail/etc/auth_unix.conf

make sure the lines that control authentication read as follows.

passwdfile_plaintext    /etc/passwd
passwdfile_encrypted    /etc/shadow
passwdmkdb              none
check_nologin           no
check_shell             no
check_cobaltuser        no

This will use the local unix password files for authentication.

6. Create the /var/log/webmail/ directory if you did the above optional step
   of moving the logfile.

7. add /var/log/webmail/openwebmail.log entry to /etc/logrotate.d/syslog file.
   This will cause you openwebmail logs to rotate like the rest of your system
   logs. Just add it to the existing line that's doing the current rotations.

8. Stop and restart httpd, "service httpd restart".

Done...

Now any user that has a password in /etc/passwd-/etc/shadow will be able to
login and see any mail that is waiting on them on this machine. If this machine
is catching the mail for your domain then all of that mail will be seen.
There are multiple methods of authentication that OWM supports. I am using the
easiest because it's all I require.
You will have to figure out on your own how to make the other methods work.

httpd://machinename/cgi-bin/openwebmail/openwebmail.pl will get you to it.
I put a link in my Home web page to it.

That is what I did, and it works and works well.
Best to everyone, and thanks again all you who contributed to this project.

#
# Open WebMail configuration file
#
# This file contains just the overrides from defaults/openwebmail.conf
# please make all changes to this file.
#
# This file sets options for all domains and all users.
# To set options on per domain basis, please put them in sites.conf/domainname
# To set options on per user basis, please put them in users.conf/username
#
domainnames auto
auth_module auth_unix.pl
mailspooldir /var/spool/mail
ow_cgidir /var/www/cgi-bin/openwebmail
ow_cgiurl /cgi-bin/openwebmail
ow_htmldir /var/www/data/openwebmail
ow_htmlurl /openwebmail
logfile /var/log/webmail/openwebmail.log
spellcheck /usr/local/bin/ispell
default_language en
default_realname auto
<default_signature>
--
Open WebMail Project (http://openwebmail.org)
</default_signature>

