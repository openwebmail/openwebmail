
Date: 07/09/2001
Author:  Emir Litric (elitric@digitex.cc)
File: RedHat-README.txt


--------------------------------------------------------------------------------------
--------- SETUP OF THE OPENWEBMAIL WITH QUOTA SYSTEM ENABLED ON REDHAT LINUX 
---------
--------------------------------------------------------------------------------------



Disclaimer:

I AM NOT RESPONSIBLE FOR ANY DAMAGES INCURRED DUE TO ACTIONS TAKEN
BASED ON THIS DOCUMENT. This document only serves as an introduction on 
setting OpenWebMail
with Quota System enabled on Red Hat Linux.

Copyright:

This document is part of OpenWebMail documentation and it is licensed with 
GPL license.
You can use or distribute it freely as long as you complain with text of the 
GPL license.
For copy of GPL license please see copyright.txt file.

Introduction:

I wrote this document to help users of Red Hat Linux effectively setup 
Open WebMail with Quota
Support.  It will help avoid some problems specific to Red Hat Linux 
versions 6.2 and bellow.
At the time of writing this document current version of Open WebMail is 1.31.

Versions of Red Hat Linux covered in this document: 6.2 and 7.x
Partly covers Red Hat Linux versions bellow 6.2. (Quota Setup Trick)

Before you begin installing Open WebMail on your Linux box please make sure 
that you have read,
readme.txt, and faq.txt files. Reading them will help them setup your 
OpenWebMail easily.
Also, please make sure that you have downloaded and setup all necessary 
packages.

Here is quick procedure to install and prepare packages before installing 
Open WebMail.

You will need:

CGI.pm-2.74.tar.gz
MIME-Base64-2.12.tar.gz
Lingua-Ispell-0.07.tar.gz

INPORTANT NOTE:

The easiest way to install ispell or aspell packages is to use RPM package
Which comes with your Red Hat distribution.  If you didn't install them 
during your Linux
Installation use RPM to install them. Please read readme.txt file for help 
on installing
ispell from the sources.

*** OpenWebMail Setup for Red Hat Linux 6.2  ***
------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------


Download above-mentioned packages and copy them to /tmp directory.

For CGI.pm do the following:

   cd /tmp
      tar -zxvf CGI.pm-2.74.tar.gz
      cd CGI.pm-2.74
      perl Makefile.PL
      make
      make install

For MIME-Base64 do the following:

   cd /tmp
      tar -zxvf MIME-Base64-2.12.tar.gz
      cd MIME-Base64-2.12
      perl Makefile.PL
      make
      make install

For Lingua-Ispell do the following:

   cd /tmp
      tar -zxvf Lingua-Ispell-0.07.tar.gz
      cd Lingua-Ispell-0.07
      perl Makefile.PL
      make
      make install

Now download and install your openwebmail software.
Go to /home/httpd directory and extract your openwebmail-1.xx.tgz file you 
have just downloaded.

    cd /home/httpd
       tar -zxvBpf openwebmail-1.xx.tgz
       mv data/openwebmail html/
       rmdir data

Go to /home/httpd/cgi-bin/openwebmail directory and configure it for your 
site.
Change the following files:

      checkmail.pl
      openwebmail-prefs.pl
      openwebmail.pl
      spellcheck.pl
      vacation.pl

For first 4 files find the line with:
     push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
and change it to:
     push (@INC, '/home/httpd/cgi-bin/openwebmail', ".");

For vacation.pl find the line with:
     $myname = '/usr/local/www/cgi-bin/openwebmail/vacation.pl';
and change it to:
     $myname = '/home/httpd/cgi-bin/openwebmail/vacation.pl';

Go to /home/httpd/cgi-bin/openwebmail/etc directory and edit 
openwebmail.conf file so
it matches your configuration.

Bellow is the example of my openwebmail.conf file:

-----------------------------------------------------------------------------------------

#!/usr/bin/perl -T

$version = "1.30";

# availablelanguages - A list of languages that are available for use.
@availablelanguages = qw(cn en es de dk fi fr hu it nl no pl pt ro ru sk 
tw);

# languagenames - A hash used to show the name of the languages that equate 
to
#                 each abbreviation.
%languagenames = (
                 cn => 'Chinese(GB)',
                 en => 'English',
                 es => 'Espanol',
                 de => 'Deutsch',
                 dk => 'Danish',
                 fi => 'Finnish',
                 fr => 'Francais',
                 hu => 'Hungarian',
                 it => 'Italiano',
                 nl => 'Nederlands',
                 no => 'Norsk',
                 pl => 'Polish',
                 pt => 'Portuguese',
                 ro => 'Romanian',
                 ru => 'Russian',
                 sk => 'Slovak',
                 tw => 'Taiwan'
                 );

# defaultlanguage - This is the language defaulted to if a user hasn't saved
#                   their own language preference yet.
$defaultlanguage = 'en';

# domainnames - Users can choose their outgoing mail domain from any one 
listed
#               in this array, enabling admins to now only install a single
#               copy of OpenWebMail and still support multiple domains.

#@domainnames = ( 'your.fully.qualified.domain.name' );
#@domainnames = (`/bin/hostname`);

@domainnames = ( 'digitex.cc','digitex-tech.com' );

# sendmail - The location of your sendmail binary, works with both sendmail
#            and exim, which can be run as sendmail and accepts the 
parameters
#            sent in this script.  Hopefully works with qmail's sendmail
#            compatability mode as well... let me know how it works!
$sendmail = '/usr/sbin/sendmail';

# genericstable - the location of sendmail genericstable
#                 It is used maps a local user to a virtualuser@virtualhost
#                 Then a user can logon webmail system with the virtualuser 
name
,
#                 and his mail will be sent with email 
virtualuser@virtualhost
$genericstable = '/etc/mail/virtusertable';

# spellcheck - The location of your spelling check program, it could be 
ether
#              ispell(http://fmg-www.cs.ucla.edu/geoff/ispell.html) or
#              aspell(http://aspell.sourceforge.net/)
$spellcheck = '/usr/bin/ispell';

# passwdfile - This is the location of the file containing both usernames 
and
#              their corresponding encrypted passwords.  If you're using
#              shadowed passwords, change it to /etc/shadow, and if you're
#              using FreeBSD, you probably want /etc/master.passwd.
#              If your're using NIS/YP, change it to '/usr/bin/ypcat 
passwd|'
$passwdfile = '/etc/shadow';

# timeoffset - This is the offset from GMT, in the notation [-|+]XXXX.
#              For example, for Taiwan, the offset is +0800.
$timeoffset = '-0600';

# mailspooldir - This is where your user mail spools are kept.  This value
#                will be ignored if you're using a system that doesn't
#                store mail spools in a common directory, and you set
#                homedirspools to 'yes'

$mailspooldir = '/home/spool/mail';

# hashedmailspools - Set this to 'yes' if your mail spool directory is set 
up
#                    like /var/spool/mail/u/s/username.  Most default
#                    sendmail installs aren't set up this way, you'll know
#                    if you need it.

$hashedmailspools = 'no';

# homedirspools - Set this to 'yes' if you're using qmail, and set the next
#                 variable to the filename of the mail spool in their
#                 directories.  Appropriate defaults have been supplied.

$homedirspools = 'no';
$homedirspoolname = 'Mailbox';

# homedirfolders       - Set this to 'yes' to put settings and folders for a
#                        user to a subdir in the user's homedir
#                        Set this to 'no' will put setting and folders for a
#                        user to $openwebmaildir/users/username/
# homedirfolderdirname - Set this to 'mail' to use ~user/mail/ for user's
#                        homdirfolders, it is compatibile with 'PINE' MUA.

$homedirfolders = 'yes';
$homedirfolderdirname = 'mail';

# use_dotlockfile - Set this to 'yes' to use .lock file for filelock
#                   This is only recommended if the mailspool or user's 
homedir
#                   are located on an remote nfs server and the lockd on
#                   your nfs server or client has problems
#                   ps: the freebsd/linux nfs may need this. solaris 
doesn't.
$use_dotlockfile = 'no';

# dbm_ext - This is the extension name for the dbm file on your system
#           set this to 'db' for FreeBSD, 'dir' for Solaris
$dbm_ext = 'db';

# openwebmaildir - This directory should be mode 750 and owned by the user
#                  this script will be running as (root in many cases).
#
# There are serval subdir under this directory
#    'styles'    - holds styles definitions
#    'templates' - holds html templates for different languages
#    'lang'      - hold messages for different languages
#    'sessions'  - holds temporary session files and attachments currently
#                  using by each session.
#    'users'     - holds individual directories for users to store their
#                  personal preferences, signatures, and addressbooks in.

$openwebmaildir = '/home/httpd/cgi-bin/openwebmail/etc';

# vacationinit - The location of the vacation program with option to init
#                the vacation db
$vacationinit = '/home/httpd/cgi-bin/openwebmail/vacation.pl -i';

# vacationpipe - The location of the vacation program with option to read 
data
#                piped from sendmail. 60s means mails from same user within 
60
#                seconds will be replied only once
$vacationpipe = '/home/httpd/cgi-bin/openwebmail/vacation.pl -t60s';

# global_addressbook - addressbook shared by all user
$global_addressbook = '/home/httpd/cgi-bin/openwebmail/etc/address.book';

# global_filterbook - filterbook shared by all user
$global_filterbook = '/home/httpd/cgi-bin/openwebmail/etc/filter.book';

# logfile - This should be set either to 'no' or the filename of a file 
you'd
#           like to log actions to.
#$logfile = '/home/httpd/cgi-bin/openwebmail/openwebmail.log';

$logfile = '/var/log/openwebmail.log';

# scripturl - The location (relative to ServerRoot) of the CGI script, used 
in
#             some error messages to provide a link back to the login page
$scripturl = '/cgi-bin/openwebmail/openwebmail.pl';

# prefsurl - This is the location (relative to ServerRoot) of the user setup
#            and address book script.
$prefsurl = '/cgi-bin/openwebmail/openwebmail-prefs.pl';

# spellcheckurl - This is the location (relative to ServerRoot) of the
#                 spellcheck script

# imagedir_url - This points to the relative URL where OpenWebMail will find
#                its graphics, for buttons, icons, and the like.
$imagedir_url = '/openwebmail/images';

# logo_url - This graphic will appear at the top of OpenWebMail login pages.
$logo_url = '/openwebmail/images/openwebmail.gif';

# bg_url - Set this to the location of a graphic you would like to use as a
#          background for all of your mail client pages.
$bg_url = '/openwebmail/images/openwebmail-bg.gif';

# sound_url - this is the sound file played if new mail found
#             openwebmail checks new mail for user every 15 min if user is
#             in INBOX folderview. Set $to '' will disable this feature
$sound_url = '/openwebmail/yougotmail.wav';

# sessiontimeout - This indicates how many minutes of inactivity pass before
#                  a session is considered timed out, and the user needs to
#                  log in again.  Make sure this is big enough that a user
#                  typing a long message won't get autologged while typing!
$sessiontimeout = 60;

# headersperpage - This indicates the maximium number of headers to display
#                   to a user at a time.  Keep this reasonable to ensure
#                   fast load times for slow connection users.
$headersperpage = 20;

# filter_repeatlimit - Messages in INBOX with same subject from same people
#                      will be treated as repeated messages. If repeated 
count
#                      is more than the filter_repeatlimit, these repeated
#                      messages will be moved to mail-trash folder. Set
#                      this value to 0 will disable the repeatness check.
$filter_repeatlimit = 10;

# filter_fakedsmtp - We call a message 'fakedsmtp' if
#                    1.the message from sender to receiver passes through
#                      one or more smtp relays and the first smtp relay has
#                      a invalid hostname.
#                    2.The message is delived from sender to receiver 
directly
#                      and the sender has invalid hostname.
#                    When this option is set to 'yes', those fakedsmtp
#                    messages will be moved to mail-trash.
$filter_fakedsmtp = 'no';

# $enable_pop3 - Open WebMail has complete support for pop3 mail.
#                If you want to disable pop3 related functions from user,
#                please set this to 'no'
$enable_pop3 = 'yes';

# $enable_setfromname - This option would allow user to set their fromname
#                       of the sender email address in a messagese
$enable_setfromname = 'no';


# $hide_internal - If this option is enabled, internal messages used by
#                  POP3 or IMAP server will be hidden from users
$hide_internal = 'yes';

# maxabooksize - This is the maximum size, in kilobytes, that a user's
#                filterbook, addressbook or pop3book can grow to.
#                This avoids a user filling up your server's hard drive 
space
#                by spamming garbage book entries.
$maxabooksize = 50;
# folderquota - Once a user's saved mail spools (not including their INBOX,
#               which, if managed, will have to be managed with system 
quotas)
#               meet or exceed this size (in KB), no future messages will be
#               able to be sent to any folder other than TRASH, where they 
will
#               be immediately deleted, until space is freed.  This does not
#               prevent the operation taking the user over this limit from
#               completing, it simply inhibits further saving of messages 
until
#               the folder size is brought down again.
#
#              10 MB Quota for My Site

$folderquota = 10000;

# $attlimit - This is the limit on the size of attachments (in MB).  Large
#             attachments can significantly drain a server's resources 
during
#             the encoding process.  Note that this affects outgoing
#             attachment size only, and will not prevent users from 
receiving
#             messages with large attachments.  That's up to you in your
#             sendmail configuration. Set this to 0 to disable the limit
#             (not recommended).
#             Some proxy server alos has size limit on POST operation, the
#             size of your attachment will also be limited by that
#
#              10 MB Attachment Limit for My Site

$attlimit = 10;

# defaultautoreplysubject - default subject for auto reply message
$defaultautoreplysubject = "This is an autoreply...[Re: \$SUBJECT]";

# defaultautoreplytext - default text for auto reply message
$defaultautoreplytext ="Hello,

I will not be reading my mail for a while.
Your mail regarding '\$SUBJECT' will be read when I return.";

# defaultsingature - default signature for all users
$defaultsignature = "";

1;

-----------------------------------------------------------------------------------------

* Setup openwebmail.log rotation.  (optional)


/var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }

to /etc/logrotate.d/syslog to enable logrotate on openwebmail.log



* Setup Openwebmail to use SMRSH (SendMail Restricted SHell).  (IMPORTANT)

  Red Hat 6.2 Sendmail is setup with SMRSH.  This means that vacation.pl 
file needs to be
  added to /etc/smrsh directory.  The easiest way to do it is just by simply 
linking it to
  your actual vacation.pl script and then restarting SendMail.
  This will help avoiding "Returned mail: see transcript for details" error 
message.

  cd /etc/smrsh
  ln -s /home/httpd/cgi-bin/openwebmail/vacation.pl /etc/smrsh/vacation.pl



* Redirect sessions to directory other then /home (IMPORTANT SETUP FOR 
QUOTA)

   mkdir /var/openwebmail
   mkdir /var/openwebmail/etc
   mkdir /var/openwebmail/etc/sessions

   chown root:wheel /var/openwebmail
   chown root:mail /var/openwebmail/etc
   chown root:mail /var/openwebmail/etc/sessions

   chmod 750 /var/openwebmail/etc
   chmod 770 /var/openwebmail/etc/sessions

   ln -s /var/openwebmail/etc/sessions 
/home/httpd/cgi-bin/openwebmail/etc/sessions



IMPORTANT:  Sometimes you might run into error dealing with negative message 
values if
            you using Quota on the /home partition.  This is not OpenWebMail 
bug but rather
            configuration issue.

Here is a short description of problem I have experienced and small trick I 
used to solve it.

I have setup Quota file system support on my /home partition where I 
allocated 11MB for each
user using e-mail system.

Users of the Openwebmail will have 10 MB with 10 MB Max attachment size.
I also had to move my Sendmail spool directory to /home partition for two 
reasons.

First one is:

   Open WebMail uses files in /var/spool/mail directory for INBOX folder.
   If I left default sendmail mail spool configuration it in 
/var/spool/mail,
   my users would have 10 MB quota on all directories except INBOX.
   This means that they could have 200 or 300 MB in INBOX folder and only 10 
MB in
   other folders.  My solution was to rename old /var/spool/mail folder to 
something else
   and then create /home/spool/mail folder with same permissions and then 
create symbolic
   link to mail spool folder.

    /var/spool/mail  -->  /home/spool/mail

   With this small redirection I now have my INBOX folder part of the 11MB 
Quota.

Second one is:

    Easier backup and administration of the /home partition.

However, default Apache root directory is also found on /home partition 
(/home/httpd).

Problem I was experiencing was:

    If I setup /home partition Quota on 11MB and then try to send attachment 
that is 7MB for instance,
    my openwebmail shows -1 size of the message in SENT folder rather then 
7MB.
    Problem occurs with sessions files located in 
/home/httpd/cgi-bin/openwebmail/etc/sessions directory.

    In reality, OpenWebMail uses 14MB user space to send 7MB attachment.
    (7MB goes to temporary session and 7MB to /home/username/mail/ folder)
    This 7MB session is then deleted after the operation is completed.  
However, with 11 MB user quota
    limit, attachment that needs to be copied to SENT folder gets corrupted 
(it can copy only remaining 4MB)
    and that is where things get a little bit screwed up.  OpenWebMail then 
shows -1 message size
    instead original 7MB.

    Solution is to move /home/httpd/cgi-bin/openwebmail/etc/sessions 
directory to a partition other then
    /home  (where Quota is implemented).  In my case I used /var partition.
    This document contains small help on linking sessions to another 
partition. (Procedure written above)

    If your apache root is setup somewhere else (e.g. /var/www) you will be 
fine.



*** OpenWebMail Setup for Red Hat Linux 7.1  ***

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

Red Hat decided that, starting with version 7.0, Apache root will be 
/var/www rather then /home/httpd.

In order to setup OpenWebMail just follow the exactly same procedure for 6.2 
but use /var/www instead
/home/httpd.

Again here is the procedure.

Download above-mentioned packages and copy them to /tmp directory.

For CGI.pm do the following:

   cd /tmp
      tar -zxvf CGI.pm-2.74.tar.gz
      cd CGI.pm-2.74
      perl Makefile.PL
      make
      make install

For MIME-Base64 do the following:

   cd /tmp
      tar -zxvf MIME-Base64-2.12.tar.gz
      cd MIME-Base64-2.12
      perl Makefile.PL
      make
      make install

For Lingua-Ispell do the following:

   cd /tmp
      tar -zxvf Lingua-Ispell-0.07.tar.gz
      cd Lingua-Ispell-0.07
      perl Makefile.PL
      make
      make install

Now download and install your openwebmail software.
Go to /var/www directory and extract your openwebmail-1.xx.tgz file you have 
just downloaded.

    cd /var/www
       tar -zxvBpf openwebmail-1.xx.tgz
       mv data/openwebmail html/
       rmdir data

Go to /var/www/cgi-bin/openwebmail directory and configure it for your site.
Change the following files:

      checkmail.pl
      openwebmail-prefs.pl
      openwebmail.pl
      spellcheck.pl
      vacation.pl

For first 4 files find the line with:
     push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
and change it to:
     push (@INC, '/var/www/cgi-bin/openwebmail', ".");

For vacation.pl find the line with:
     $myname = '/usr/local/www/cgi-bin/openwebmail/vacation.pl';
and change it to:
     $myname = '/var/www/cgi-bin/openwebmail/vacation.pl';

Go to /var/www/cgi-bin/openwebmail/etc directory and edit openwebmail.conf 
file so
it matches your configuration.

Bellow is the example of my openwebmail.conf file:

-----------------------------------------------------------------------------------------

#!/usr/bin/perl -T

$version = "1.30";

# availablelanguages - A list of languages that are available for use.
@availablelanguages = qw(cn en es de dk fi fr hu it nl no pl pt ro ru sk 
tw);

# languagenames - A hash used to show the name of the languages that equate 
to
#                 each abbreviation.
%languagenames = (
                 cn => 'Chinese(GB)',
                 en => 'English',
                 es => 'Espanol',
                 de => 'Deutsch',
                 dk => 'Danish',
                 fi => 'Finnish',
                 fr => 'Francais',
                 hu => 'Hungarian',
                 it => 'Italiano',
                 nl => 'Nederlands',
                 no => 'Norsk',
                 pl => 'Polish',
                 pt => 'Portuguese',
                 ro => 'Romanian',
                 ru => 'Russian',
                 sk => 'Slovak',
                 tw => 'Taiwan'
                 );

# defaultlanguage - This is the language defaulted to if a user hasn't saved
#                   their own language preference yet.
$defaultlanguage = 'en';

# domainnames - Users can choose their outgoing mail domain from any one 
listed
#               in this array, enabling admins to now only install a single
#               copy of OpenWebMail and still support multiple domains.

#@domainnames = ( 'your.fully.qualified.domain.name' );
#@domainnames = (`/bin/hostname`);

@domainnames = ( 'digitex.cc','digitex-tech.com' );

# sendmail - The location of your sendmail binary, works with both sendmail
#            and exim, which can be run as sendmail and accepts the 
parameters
#            sent in this script.  Hopefully works with qmail's sendmail
#            compatability mode as well... let me know how it works!
$sendmail = '/usr/sbin/sendmail';

# genericstable - the location of sendmail genericstable
#                 It is used maps a local user to a virtualuser@virtualhost
#                 Then a user can logon webmail system with the virtualuser 
name
,
#                 and his mail will be sent with email 
virtualuser@virtualhost
$genericstable = '/etc/mail/virtusertable';

# spellcheck - The location of your spelling check program, it could be 
ether
#              ispell(http://fmg-www.cs.ucla.edu/geoff/ispell.html) or
#              aspell(http://aspell.sourceforge.net/)
#
#  Red Hat Linux 7.1 uses aspell instead ispell.

$spellcheck = '/usr/bin/aspell';

# passwdfile - This is the location of the file containing both usernames 
and
#              their corresponding encrypted passwords.  If you're using
#              shadowed passwords, change it to /etc/shadow, and if you're
#              using FreeBSD, you probably want /etc/master.passwd.
#              If your're using NIS/YP, change it to '/usr/bin/ypcat 
passwd|'
$passwdfile = '/etc/shadow';

# timeoffset - This is the offset from GMT, in the notation [-|+]XXXX.
#              For example, for Taiwan, the offset is +0800.
$timeoffset = '-0600';

# mailspooldir - This is where your user mail spools are kept.  This value
#                will be ignored if you're using a system that doesn't
#                store mail spools in a common directory, and you set
#                homedirspools to 'yes'

$mailspooldir = '/home/spool/mail';

# hashedmailspools - Set this to 'yes' if your mail spool directory is set 
up
#                    like /var/spool/mail/u/s/username.  Most default
#                    sendmail installs aren't set up this way, you'll know
#                    if you need it.

$hashedmailspools = 'no';

# homedirspools - Set this to 'yes' if you're using qmail, and set the next
#                 variable to the filename of the mail spool in their
#                 directories.  Appropriate defaults have been supplied.

$homedirspools = 'no';
$homedirspoolname = 'Mailbox';

# homedirfolders       - Set this to 'yes' to put settings and folders for a
#                        user to a subdir in the user's homedir
#                        Set this to 'no' will put setting and folders for a
#                        user to $openwebmaildir/users/username/
# homedirfolderdirname - Set this to 'mail' to use ~user/mail/ for user's
#                        homdirfolders, it is compatibile with 'PINE' MUA.

$homedirfolders = 'yes';
$homedirfolderdirname = 'mail';

# use_dotlockfile - Set this to 'yes' to use .lock file for filelock
#                   This is only recommended if the mailspool or user's 
homedir
#                   are located on an remote nfs server and the lockd on
#                   your nfs server or client has problems
#                   ps: the freebsd/linux nfs may need this. solaris 
doesn't.
$use_dotlockfile = 'no';

# dbm_ext - This is the extension name for the dbm file on your system
#           set this to 'db' for FreeBSD, 'dir' for Solaris
$dbm_ext = 'db';

# openwebmaildir - This directory should be mode 750 and owned by the user
#                  this script will be running as (root in many cases).
#
# There are serval subdir under this directory
#    'styles'    - holds styles definitions
#    'templates' - holds html templates for different languages
#    'lang'      - hold messages for different languages
#    'sessions'  - holds temporary session files and attachments currently
#                  using by each session.
#    'users'     - holds individual directories for users to store their
#                  personal preferences, signatures, and addressbooks in.

$openwebmaildir = '/var/www/cgi-bin/openwebmail/etc';

# vacationinit - The location of the vacation program with option to init
#                the vacation db
$vacationinit = '/var/www/cgi-bin/openwebmail/vacation.pl -i';

# vacationpipe - The location of the vacation program with option to read 
data
#                piped from sendmail. 60s means mails from same user within 
60
#                seconds will be replied only once
$vacationpipe = '/var/www/cgi-bin/openwebmail/vacation.pl -t60s';

# global_addressbook - addressbook shared by all user
$global_addressbook = '/var/www/cgi-bin/openwebmail/etc/address.book';

# global_filterbook - filterbook shared by all user
$global_filterbook = '/var/www/cgi-bin/openwebmail/etc/filter.book';

# logfile - This should be set either to 'no' or the filename of a file 
you'd
#           like to log actions to.
#$logfile = '/var/www/cgi-bin/openwebmail/openwebmail.log';

$logfile = '/var/log/openwebmail.log';

# scripturl - The location (relative to ServerRoot) of the CGI script, used 
in
#             some error messages to provide a link back to the login page
$scripturl = '/cgi-bin/openwebmail/openwebmail.pl';

# prefsurl - This is the location (relative to ServerRoot) of the user setup
#            and address book script.
$prefsurl = '/cgi-bin/openwebmail/openwebmail-prefs.pl';

# spellcheckurl - This is the location (relative to ServerRoot) of the
#                 spellcheck script

# imagedir_url - This points to the relative URL where OpenWebMail will find
#                its graphics, for buttons, icons, and the like.
$imagedir_url = '/openwebmail/images';

# logo_url - This graphic will appear at the top of OpenWebMail login pages.
$logo_url = '/openwebmail/images/openwebmail.gif';

# bg_url - Set this to the location of a graphic you would like to use as a
#          background for all of your mail client pages.
$bg_url = '/openwebmail/images/openwebmail-bg.gif';

# sound_url - this is the sound file played if new mail found
#             openwebmail checks new mail for user every 15 min if user is
#             in INBOX folderview. Set $to '' will disable this feature
$sound_url = '/openwebmail/yougotmail.wav';

# sessiontimeout - This indicates how many minutes of inactivity pass before
#                  a session is considered timed out, and the user needs to
#                  log in again.  Make sure this is big enough that a user
#                  typing a long message won't get autologged while typing!
$sessiontimeout = 60;

# headersperpage - This indicates the maximium number of headers to display
#                   to a user at a time.  Keep this reasonable to ensure
#                   fast load times for slow connection users.
$headersperpage = 20;

# filter_repeatlimit - Messages in INBOX with same subject from same people
#                      will be treated as repeated messages. If repeated 
count
#                      is more than the filter_repeatlimit, these repeated
#                      messages will be moved to mail-trash folder. Set
#                      this value to 0 will disable the repeatness check.
$filter_repeatlimit = 10;

# filter_fakedsmtp - We call a message 'fakedsmtp' if
#                    1.the message from sender to receiver passes through
#                      one or more smtp relays and the first smtp relay has
#                      a invalid hostname.
#                    2.The message is delived from sender to receiver 
directly
#                      and the sender has invalid hostname.
#                    When this option is set to 'yes', those fakedsmtp
#                    messages will be moved to mail-trash.
$filter_fakedsmtp = 'no';

# $enable_pop3 - Open WebMail has complete support for pop3 mail.
#                If you want to disable pop3 related functions from user,
#                please set this to 'no'
$enable_pop3 = 'yes';

# $enable_setfromname - This option would allow user to set their fromname
#                       of the sender email address in a messagese
$enable_setfromname = 'no';


# $hide_internal - If this option is enabled, internal messages used by
#                  POP3 or IMAP server will be hidden from users
$hide_internal = 'yes';

# maxabooksize - This is the maximum size, in kilobytes, that a user's
#                filterbook, addressbook or pop3book can grow to.
#                This avoids a user filling up your server's hard drive 
space
#                by spamming garbage book entries.
$maxabooksize = 50;
# folderquota - Once a user's saved mail spools (not including their INBOX,
#               which, if managed, will have to be managed with system 
quotas)
#               meet or exceed this size (in KB), no future messages will be
#               able to be sent to any folder other than TRASH, where they 
will
#               be immediately deleted, until space is freed.  This does not
#               prevent the operation taking the user over this limit from
#               completing, it simply inhibits further saving of messages 
until
#               the folder size is brought down again.
#
#              10 MB Quota for My Site

$folderquota = 10000;

# $attlimit - This is the limit on the size of attachments (in MB).  Large
#             attachments can significantly drain a server's resources 
during
#             the encoding process.  Note that this affects outgoing
#             attachment size only, and will not prevent users from 
receiving
#             messages with large attachments.  That's up to you in your
#             sendmail configuration. Set this to 0 to disable the limit
#             (not recommended).
#             Some proxy server alos has size limit on POST operation, the
#             size of your attachment will also be limited by that
#
#              10 MB Attachment Limit for My Site

$attlimit = 10;

# defaultautoreplysubject - default subject for auto reply message
$defaultautoreplysubject = "This is an autoreply...[Re: \$SUBJECT]";

# defaultautoreplytext - default text for auto reply message
$defaultautoreplytext ="Hello,

I will not be reading my mail for a while.
Your mail regarding '\$SUBJECT' will be read when I return.";

# defaultsingature - default signature for all users
$defaultsignature = "";

1;

-----------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------



* Setup openwebmail.log rotation.  (optional)

/var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }

to /etc/logrotate.d/syslog to enable logrotate on openwebmail.log



* Setup Openwebmail to use SMRSH (SendMail Restricted SHell).  (IMPORTANT)

  Red Hat 7.1 Sendmail is setup with SMRSH.  This means that vacation.pl 
file needs to be
  added to /etc/smrsh directory.  The easiest way to do it is just by simply 
linking it to
  your actual vacation.pl script and then restarting SendMail.
  This will help avoiding "Returned mail: see transcript for details" error 
message.

  cd /etc/smrsh
  ln -s /var/www/cgi-bin/openwebmail/vacation.pl /etc/smrsh/vacation.pl


Now you are ready to test your OpenWebMail installation.

Please point your browser to:

     http://yourservername/cgi-bin/openwebmail/openwebmail.log

If you still have problems, check your openwebmail directory and file 
permissions and read
FAQ and README file.

Have fun and let me know of any suggestions.

Emir Litric (elitric@digitex.cc)



