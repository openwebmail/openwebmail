
Date: 07/09/2001
Last Revision: 10/30/2001
Author:  Emir Litric (elitric.AT.digitex.cc)
File: RedHat-README.txt

ps: This document is somewhat outdated,
    please refer to http://forum.openwebmail.org/viewtopic.php?t=37
    for more updated information.

------------------------------------------------------------------------------
     SETUP OF THE OPENWEBMAIL WITH QUOTA SYSTEM ENABLED ON REDHAT LINUX
------------------------------------------------------------------------------

Disclaimer:

I AM NOT RESPONSIBLE FOR ANY DAMAGES INCURRED DUE TO ACTIONS TAKEN
BASED ON THIS DOCUMENT. This document only serves as an introduction on
setting OpenWebMail with Quota System enabled on Red Hat Linux.

Copyright:

This document is part of OpenWebMail documentation and it is licensed with
GPL license. You can use or distribute it freely as long as you complain with
text of the GPL license. For copy of GPL license please see copyright.txt file.

Changes:

- 02/20/2002 - Revision for 1.62.  Use of new openwebmail.conf file.
- 10/29/2001 - Revision for 1.50.  Use of new openwebmail.conf file.
               Link to /usr/local/www directory instead of editing of all
               configuration files.
- 07/09/2001 - First Written Documentation

Introduction:

I wrote this document to help users of Red Hat Linux effectively setup
Open WebMail with Quota support. It will help avoid some problems specific
to Red Hat Linux versions 6.2 and bellow.
At the time of writing this document current version of Open WebMail is 1.50.

Versions of Red Hat Linux covered in this document: 6.2 and 7.x
Partly covers Red Hat Linux versions bellow 6.2. (Quota Setup Trick)



------------------------------------------------------------------------------
 OpenWebMail Setup for Red Hat Linux
------------------------------------------------------------------------------

Before you begin installing Open WebMail on your Linux box please make sure
that you have read readme.txt, and faq.txt files. Reading them will help them
setup your OpenWebMail easily. Also, please make sure that you have downloaded
and setup all necessary packages.

Here is quick procedure to install and prepare packages before installing
Open WebMail.

You will need:

CGI.pm-3.05.tar.gz
MIME-Base64-3.01.tar.gz
libnet-1.19.tar.gz
Text-Iconv-1.2.tar.gz

------------------------------------------------------------------------------
IMPORTANT NOTE:

The easiest way to install ispell or aspell packages is to use RPM package
Which comes with your Red Hat distribution.  If you didn't install them
during your Linux installation use RPM to install them. Please read readme.txt
file for help on installing ispell from the sources.

Please read faq.txt and readme.txt files for help on optional packages.
------------------------------------------------------------------------------

Download above-mentioned packages and copy them to /tmp directory.

For CGI.pm do the following:

   cd /tmp
   tar -zxvf CGI.pm-3.05.tar.gz
   cd CGI.pm-3.05
   perl Makefile.PL
   make
   make install

For MIME-Base64 do the following:

   cd /tmp
   tar -zxvf MIME-Base64-3.01.tar.gz
   cd MIME-Base64-3.01
   perl Makefile.PL
   make
   make install

For libnet do the following:

   cd /tmp
   tar -zxvf libnet-1.19.tar.gz
   cd libnet-1.19
   perl Makefile.PL
   make
   make install

For Text-Iconv-1.2 do the following:

   Since Text-Iconv-1.2 is actually a perl interface to the underlying iconv()
   support, you have to check if iconv() support is available in your system.
   Please type the following command

   man iconv

   If there is no manual page for iconv, your system may not support iconv().
   Don't worry, you can have the iconv() support by installing libiconv package.

   cd /tmp
   tar -zxvf Text-Iconv-1.2.tar.gz
   cd Text-Iconv-1.2
   perl Makefile.PL
   make
   make test

   ps: If the 'make test' failed, it means you set wrong value for LIBS and
       INC in Makefile.PL or your iconv support is not complete.
       You may copy the misc/patches/iconv.pl.fake to shares/iconv.pl to make
       openwebmail work without iconv support.

   make install


Now download and install your openwebmail software.

(RedHat 6.x users) Go to /home/httpd directory and extract your
openwebmail-1.xx.tar.gz file you have just downloaded.

   cd /home/httpd
   tar -zxvBpf openwebmail-1.xx.tar.gz
   edit etc/auth_unix.conf (from etc/defaults/auth_unix.conf)
   set passwdfile_encrypted to /etc/shadow
       passwdmkdb           to none

   cd cgi-bin/etc
   edit openwebmail.conf:
   set mailspool  to /var/spool/mail
       ow_cgidir  to /home/httpd/cgi-bin
       ow_htmldir to /home/httpd/data
       spellcheck to /usr/bin/aspell

(RedHat 7.x users) Go to /var/www directory and extract your
openwebmail-1.xx.tar.gz file you have just downloaded.

   cd /var/www
   tar -zxvBpf openwebmail-1.xx.tar.gz
   edit etc/auth_unix.conf (from etc/defaults/auth_unix.conf)
   set passwdfile_encrypted to /etc/shadow
       passwdmkdb           to none

   cd cgi-bin/etc
   edit openwebmail.conf:
   set mailspool  to /var/spool/mail
       ow_cgidir  to /var/www/cgi-bin
       ow_htmldir to /var/www/data
       spellcheck to /usr/bin/aspell

Bellow is the example of my openwebmail.conf file on RedHat 7.x:

--------------------------------------------------------------------- start --
#
# Open WebMail configuration file
#
# This file contains just the overrides from defaults/openwebmail.conf
# please make all changes to this file.
#
# This file set options for all domains and all users.
# To set options on per domain basis, please put them in sites.conf/domainname
# To set options on per user basis, please put them in users.conf/username
#
domainnames		auto
auth_module		auth_unix.pl
mailspooldir		/var/spool/mail
timeoffset		-0600
ow_cgidir		/var/www/cgi-bin/openwebmail
ow_cgiurl		/cgi-bin/openwebmail
ow_htmldir		/var/www/data/openwebmail
ow_htmlurl		/openwebmail
logfile			/var/log/openwebmail.log
spellcheck		/usr/bin/aspell
default_language	en

<default_signature>
--
Open WebMail Project (http://openwebmail.org)
</default_signature>
----------------------------------------------------------------------- end --

Bellow is the example of my dbm.conf file on RedHat 7.x:

--------------------------------------------------------------------- start --
dbm_ext			.db
dbmopen_ext		none
dbmopen_haslock		no
----------------------------------------------------------------------- end --




------------------------------------------------------------------------------
 Setup openwebmail.log rotation.  (optional)
------------------------------------------------------------------------------

/var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }

to /etc/logrotate.d/syslog to enable logrotate on openwebmail.log



------------------------------------------------------------------------------
 Setup Openwebmail to use SMRSH (SendMail Restricted SHell).  (IMPORTANT)
------------------------------------------------------------------------------

Red Hat 6.2 and 7.1 Sendmail is setup with SMRSH. This means that vacation.pl
file needs to be added to /etc/smrsh directory.  The easiest way to do it is
just by simply linking it to your actual vacation.pl script and then
restarting SendMail. This will help avoiding "Returned mail: see transcript
for details" error message.

  cd /etc/smrsh
  ln -s /home/httpd/cgi-bin/openwebmail/vacation.pl /etc/smrsh/vacation.pl



------------------------------------------------------------------------------
 Redirect sessions to directory other then /home (IMPORTANT SETUP FOR QUOTA)
------------------------------------------------------------------------------

  This is for RedHat 6.2 only since 7.x httpd dir is already /var/www

  mkdir /var/openwebmail
  mkdir /var/openwebmail/etc
  mkdir /var/openwebmail/etc/sessions

  chown root:wheel /var/openwebmail
  chown root:mail /var/openwebmail/etc
  chown root:mail /var/openwebmail/etc/sessions

  chmod 755 /var/openwebmail/etc
  chmod 770 /var/openwebmail/etc/sessions

  ln -s /var/openwebmail/etc/sessions /home/httpd/cgi-bin/openwebmail/etc/sessions


IMPORTANT:  Sometimes you might run into error dealing with negative message
values if you using Quota on the /home partition.  This is not OpenWebMail
bug but rather configuration issue.

Here is a short description of problem I have experienced and small trick I
used to solve it.

I have setup Quota file system support on my /home partition where I
allocated 11MB for each user using e-mail system.

Users of the Openwebmail will have 10 MB with 10 MB Max attachment size.
I also had to move my Sendmail spool directory to /home partition for two
reasons.

First one is:

   Open WebMail uses files in /var/spool/mail directory for INBOX folder.
   If I left default sendmail mail spool configuration it in /var/spool/mail,
   my users would have 10 MB quota on all directories except INBOX.
   This means that they could have 200 or 300 MB in INBOX folder and only 10
   MB in other folders.  My solution was to rename old /var/spool/mail folder
   to something else and then create /home/spool/mail folder with same
   permissions and then create symbolic link to mail spool folder.

   /var/spool/mail  -->  /home/spool/mail

   With this small redirection I now have my INBOX folder part of the 11MB
   Quota.

Second one is:

   Easier backup and administration of the /home partition.

However, default Apache root directory is also found on /home partition
(/home/httpd). Problem I was experiencing was:

   If I setup /home partition Quota on 11MB and then try to send attachment
   that is 7MB for instance, my openwebmail shows -1 size of the message in
   SENT folder rather then 7MB. Problem occurs with sessions files located
   in /home/httpd/cgi-bin/openwebmail/etc/sessions directory.

   In reality, OpenWebMail uses 14MB user space to send 7MB attachment.
   (7MB goes to temporary session and 7MB to /home/username/mail/ folder)
   This 7MB session is then deleted after the operation is completed.
   However, with 11 MB user quota limit, attachment that needs to be copied
   to SENT folder gets corrupted (it can copy only remaining 4MB) and that
   is where things get a little bit screwed up.
   OpenWebMail then shows -1 message size instead original 7MB.

Solution is to move /home/httpd/cgi-bin/openwebmail/etc/sessions directory
to a partition other the /home  (where Quota is implemented).
In my case I used /var partition.

This document contains small help on linking sessions to another partition.
(Procedure written above)
If your apache root is setup somewhere else (e.g. /var/www) you will be fine.


------------------------------------------------------------------------------
Some issues of the sendmail on RedHat 7.1
(thanks to Thomas Chung, tchung.AT.openwebmail.org)
------------------------------------------------------------------------------

For security reasons, the default configuration of sendmail allows sending,
but not receiving over the net (by default it will only accept connections
on the loopback interface.)

Configure sendmail to accept incoming connections by as follows:

1. Modify /usr/share/sendmail-cf/cf/redhat.mc
   Comment out the following line by prepedning with a 'dnl'.

      DAEMON_OPTIONS('Port=smtp,Addr=127.0.0.1, Name=MTA')

   Another appropriate step for a server system is to comment out the line

      FEATURE('Accept_unresolvable_domains')

   Then save the file.

2. Build a new redhat.cf in the same directory.

      cd /usr/share/sendmail-cf/cf/
      make redhat.cf

3. Use new sendmail.cf

      cp /etc/sendmail.cf /etc/sendmail.cf.save
      cp /usr/share/sendmail-cf/cf/redhat.cf /etc/sendmail.cf

------------------------------------------------------------------------------



Now you are ready to test your OpenWebMail installation.
Please point your browser to:

http://yourservername/cgi-bin/openwebmail/openwebmail.pl

If you still have problems, check your openwebmail directory and file
permissions and read FAQ and README file.

Have fun and let me know of any suggestions.


Emir Litric (elitric.AT.yahoo.com)

