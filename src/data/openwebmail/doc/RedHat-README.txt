
Date: 07/09/2001
Last Revision: 10/30/2001
Author:  Emir Litric (elitric@digitex.cc)
File: RedHat-README.txt

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

CGI.pm-2.74.tar.gz
MIME-Base64-2.12.tar.gz

------------------------------------------------------------------------------
INPORTANT NOTE:

The easiest way to install ispell or aspell packages is to use RPM package
Which comes with your Red Hat distribution.  If you didn't install them 
during your Linux installation use RPM to install them. Please read readme.txt 
file for help on installing ispell from the sources.

Please read faq.txt and readme.txt files for help on optional packages.
------------------------------------------------------------------------------

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

Now download and install your openwebmail software.

(RedHat 6.x users) Go to /home/httpd directory and extract your 
openwebmail-1.xx.tgz file you have just downloaded.  

   cd /home/httpd
   tar -zxvBpf openwebmail-1.xx.tgz

(RedHat 7.x users) Go to /var/www directory and extract your 
openwebmail-1.xx.tgz file you have just downloaded.  

   cd /var/www
   tar -zxvBpf openwebmail-1.xx.tgz
       
Link /usr/local/www directory to whatever your web root is.

For RedHat Linux 6.x it will be linked to /home/httpd:
For RedHat Linux 7.x it will be linked to /var/www:

(Quick command help):

RH 6.x:    ln -s /home/httpd/ /usr/local/www
RH 7.x:    ln -s /var/www/ /usr/local/www



Go to /usr/local/www/cgi-bin/openwebmail/etc directory and edit 
openwebmail.conf file so that it matches your configuration.

Bellow is the example of my openwebmail.conf file:

--------------------------------------------------------------------- start --
#
# Open WebMail configuration file
#

version                 1.51

##############################################################################
# host depend configuration
##############################################################################
#
# domainnames : Users can choose their outgoing mail domain from any one
# listed here, enabling admins to now only install a single copy of OpenWebMail
# and still support multiple domains.
#
# ps: if set this to auto, the domainname will be got by running '/bin/hostname'
#
#domainnames            server1.domain1.com, server2.domain2.com
domainnames             auto

#
# sendmail : The location of your sendmail binary, works with both sendmail
# and exim, which can be run as sendmail and accepts the parameters sent in
# this script.  Hopefully works with qmail's sendmail compatibility mode as
# well...
#
sendmail                /usr/sbin/sendmail

#
# virtusertable : the location of sendmail virtusertable.
# It is used maps a virtualuser to the real userid in system.
# A virtualuser can be in the form a pure username or username@somedomain
# Please refer to http://www.sendmail.org/virtual-hosting.html for more detail
#
# When a user logins Open WebMail with a loginname,
# this loginname will be checked in the following order:
# 1. Is this loginname a virtualuser defined in virtusertable?
# 2. Is this loginname a real userid in system?
# 3. Does this loginname match the username part of a specific virtualuser?
#
virtusertable           /etc/mail/virtusertable

#
# ------------------------------   --------------------------------
# auth_module : the authentication module used in openwebmail
# ------------------------------   --------------------------------
# auth_module                      authentication by
# ------------------------------   --------------------------------
# auth_unix.pl                     unix passwd
# auth_pam.pl                      pam (pluggable authentication module)
# ------------------------------   --------------------------------
#
# ps: ONCE YOU HAVE DECIDED WHICH AUTH_MODULE TO USE,
#     DON'T FORGET TO EDIT THE GLOBAL VARIABLE DEFINITION IN THE BEGINING
#     OF THAT AUTH_MODULE!!!
#
auth_module             auth_unix.pl

#
# mailspooldir : This is where your user mail spools are kept.  This value
# will be ignored if you're using a system that doesn't store mail spools
# in a common directory, and you set homedirspools to 'yes'
#
mailspooldir            /var/spool/mail

#
# use_hashedmailspools : Set this to 'yes' if your mail spool directory is
# set up like /var/spool/mail/u/s/username. Most default sendmail installs
# aren't set up this way, you'll know if you need it.
#
use_hashedmailspools    no

#
# use_homedirspools : Set this to 'yes' if you're using qmail, and set the
# next variable to the filename of the mail spool in their directories.
# Appropriate defaults have been supplied.
#
use_homedirspools       no
homedirspoolname        Mailbox

#
# use_homedirfolders   : Set this to 'yes' to put settings and folders for a
# user to a subdir in the user's homedir. Set this to 'no' will put setting
# and folders for a user to openwebmaildir/users/username/
# homedirfolderdirname : Set this to 'mail' to use ~user/mail/ for user's
# homdirfolders, it is compatible with 'PINE' MUA.
#
use_homedirfolders      no
homedirfolderdirname    mail

#
# use_dotlockfile : Set this to 'yes' to use .lock file for filelock
# This is only recommended if the mailspool or user's homedir are located on
# an remote nfs server and the lockd on your nfs server or client has problems
# ps: the freebsd/linux nfs may need this. solaris doesn't.
#
use_dotlockfile         no

#
# dbm_ext : This is the extension name for the dbm file on your system
# Set this to '.db' for FreeBSD, '.dir' for Solaris
#
dbm_ext                 .db

#
# timeoffset : This is the offset from GMT, in the notation [-|+]XXXX.
# For example, for Taiwan, the offset is +0800.
#
timeoffset              -0600



##############################################################################
# openwebmail system configuration
##############################################################################
#
# ow_cgidir : the directory for openwebmail cgi programs
#
ow_cgidir               /usr/local/www/cgi-bin/openwebmail

#
# ow_cgiurl : the url for ow_cgidir
#
ow_cgiurl               /cgi-bin/openwebmail

#
# ow_htmldir : the directory for openwebmail webpage/image/sound files
#
ow_htmldir              /usr/local/www/data/openwebmail

#
# ow_htmlurl : the url for ow_htmldir
#
ow_htmlurl              /openwebmail

#
# ow_etcdir : the directory for openwebmail runtime resource files,
#
# There are serval subdir under this directory
#   styles/    - holds styles definitions
#   templates/ - holds html templates for different languages
#   lang/      - hold messages for different languages
#   sessions/  - holds temporary session files and attachments currently
#                using by each session.
#   users/     - holds individual directories for users to store their
#                personal preferences, signatures, and addressbooks in.
#
# ps: The directories sessions/ and users/ should be mode 750 and owned by the
#     user that openwebmail script will be running as (root in many cases) for
#     better security.
#
ow_etcdir               %ow_cgidir%/etc

#
# logo_url : This graphic will appear at the top of OpenWebMail login pages.
#
logo_url                %ow_htmlurl%/images/openwebmail.gif

#
# logo_link : The link to go when user clicks the logo image
#
logo_link               http://turtle.ee.ncku.edu.tw/openwebmail/

#
# sound_url : this is the sound file played if new mail is found.
# Openwebmail checks new mail for user every 15 min if user is in INBOX
# folderview. Set to '' will disable this feature
#
sound_url               %ow_htmlurl%/yougotmail.wav

#
# logfile : This should be set either to 'no' or the filename of a file
# you'd like to log actions to.
#
logfile         %ow_cgidir%/openwebmail.log
#logfile                        /var/log/openwebmail.log

#
# global_addressbook : addressbook shared by all user
#
global_addressbook      %ow_etcdir%/address.book

#
# global_filterbook : filterbook shared by all user
#
global_filterbook       %ow_etcdir%/filter.book

#
# spellcheck : The location of your spelling check program, it could be ether
# ispell(http://fmg-www.cs.ucla.edu/geoff/ispell.html) or aspell
# (http://aspell.sourceforge.net/)
#
spellcheck              /usr/bin/aspell

#
# spellcheck_dictionaries : The names of all dictionaries supported by your
# spellcheck program.
#
spellcheck_dictionaries english, american

#
# vacationinit : The location of the vacation program with option to init
# the vacation db
#
vacationinit            %ow_cgidir%/vacation.pl -i

#
# vacationpipe : The location of the vacation program with option to read
# data piped from sendmail. 60s means mails from same user within 60 seconds
# will be replied only once
#
vacationpipe            %ow_cgidir%/vacation.pl -t60s

#
#
# g2b_converter : program to convert chinese GB to Big5 code
# b2g_converter : program to convert chinese Big5 to GB code
#
# these 2 converter will be required only if lang is 'tw' or 'cn'
#
g2b_converter           %ow_cgidir%/hc -mode g2b -t %ow_cgidir%/hc.tab
b2g_converter           %ow_cgidir%/hc -mode b2g -t %ow_cgidir%/hc.tab

#
# enable_changepwd : Set this to 'yes' if you want to let user set their
# password through the web mail interface
#
enable_changepwd        yes

#
# enable_setfromemail : This option would allow user to set their from
# email address in a message
#
enable_setfromemail     yes

#
# enable_autoreply : This option would allow user to enable autoreply
# for their incoming messages
#
enable_autoreply        yes

#
# enable_pop3 : Open WebMail has complete support for pop3 mail. If you want
# to disable pop3 related functions from user, please set this to 'no'
#
enable_pop3             yes

#
# @disallowed_pop3servers : Array of hostnames which we disallow. The host
# may share the same mailspool, or for some administrative reason be
# undesirable.
#
disallowed_pop3servers  turtle.ee.ncku.edu.tw, turtle

#
# autopop3_at_refresh : If user enables autopop3 in user preference,
# openwebmail will fetch pop3mail automatically when he login.
# In that case, if this option is set to yes, openwebamil will also
# fecth pop3mail at refresh, please refer to option refreshinterval
#
autopop3_at_refresh     yes

#
# symboliclink_mbox : Some pop3d moves messages from mail spool to ~/mbox 
# if the pop3 client chooses to reserve the message on server.
# With this option set to 'yes', openwebmail will symlink 
# ~/mbox -> ~/mail/saved-messages to make messages accessable either in 
# pop3 client or openwebmail
#
symboliclink_mbox	yes

#
# sessiontimeout : This indicates how many minutes of inactivity pass before
# a session is considered timed out, and the user needs to log in again.
# Make sure this is big enough that a user typing a long message won't get
# timeouted while typing!
#
sessiontimeout          60

#
# refreshinterval : This is the interval in minutes that openwebmail will
# refresh the screen when the user is listing a folder or reading a message.
# It gives the openwebmail a chance to check the new mail status.
# This value should be shorter than 'sessiontimeout'.
#
refreshinterval         15

#
# foldername_maxlen : This is the maximum length for the name of a folder
#
foldername_maxlen       32

#
# folderquota : Once a user's saved mail spools (including their INBOX)
# meet or exceed this size (in KB), no future messages will be able to be
# sent to any folder other than TRASH, where they will be immediately deleted,
# until space is freed. This does not prevent the operation taking the user
# over this limit from completing, it simply inhibits further saving of
# messages until the folder size is brought down again.
#
folderquota             10000

#
# maxbooksize : This is the maximum size, in kilobytes, that a user's
# filterbook, addressbook, pop3book or historybook can grow to. This avoids
# a user filling up your server's hard drive space by spamming garbage book
# entries.
#
maxbooksize             10

#
# attlimit : This is the limit on the size of attachments (in MB).  Large
# attachments can significantly drain a server's resources during
# the encoding process.  Note that this affects outgoing attachment size only,
# and will not prevent users from receiving messages with large attachments.
# That's up to you in your sendmail configuration.
#
# Set this to 0 to disable the limit (not recommended).
#
# Some proxy server also has size limit on POST operation, the size of your
# attachment will also be limited by that
#
attlimit                50

##############################################################################
# default setting for user preference
##############################################################################
#
# default_language : This is the language defaulted to if a user hasn't saved
# their own language preference yet.
#
# supported language including: (defined in openwebmail-shared.pl)
#
# ca           => Catalan
# da           => Danish
# de           => German                # Deutsch
# en           => English
# es           => Spanish               # Espanol
# fi           => Finnish
# fr           => French
# hu           => Hungarian
# it           => Italian
# nl           => Dutch # Nederlands
# no_NY        => Norwegian Nynorsk
# pl           => Polish
# pt           => Portuguese
# pt_BR        => Portuguese Brazil
# ro           => Romanian
# ru           => Russian
# sk           => Slovak
# sv           => Swedish               # Svenska
# zh_CN.GB2312 => Chinese ( Simplified )
# zh_TW.Big5   => Chinese ( Traditional )
#
#default_language       zh_TW.Big5
default_language       en

#
# default_bgurl : the default background image used for new user
#
# ps: if set this to none, a transparent blank background will be used
#
#default_bgurl          none
default_bgurl           %ow_htmlurl%/images/backgrounds/Globe.gif

#
# default_style - the default style used for new user
#
default_style           Default

#
# default_iconset : the default iconset used for new user
#
default_iconset         Default

#
# default_sort : default message sorting, available value:
#                date, subject, size, sender, recipient
#
default_sort            date

#
# default_headersperpage : This indicates the maximum number of headers to
# display to a user at a time. Keep this reasonable to ensure fast load time
# for slow connection users.
#
default_headersperpage  10

#
# hideinternal : If this option is enabled, internal messages used by
# POP3 or IMAP server will be hidden from users
#
default_hideinternal    yes

#
# default_editcolumns : default columns for message composing windows
#
default_editcolumns     78

#
# default_editrows : default rows for message composing windows
#
default_editrows        20

#
# default_dictionary - the default dictionary used in spellcheck for new user
#
default_dictionary      english

#
# default_filter_repeatlimit : Messages in INBOX with same subject from same
# people will be treated as repeated messages. If repeated count is more than
# this value, messages will be moved to mail-trash folder.
# Set this value to 0 will disable this feature.
#
default_filter_repeatlimit      10

#
# default_filter_fakedsmtp : We call a message 'fakedsmtp' if
# 1.the message from sender to receiver passes through one or more smtp relays
#   and the first smtp relay has a invalid hostname.
# 2.The message is delivered from sender to receiver directly and the sender
#   has invalid hostname. When this option is set to 'yes', those fakedsmtp
#   messages will be moved to mail-trash.
#
default_filter_fakedsmtp        no

#
# default_disablejs : if set this option to 'yes', the java script in in html
# message will be disabled
#
default_disablejs               no

#
# default_newmailsound : if this option is set to yes, the user will be
# notified with sound 'You have mail' when new mail is available
#
default_newmailsound            yes

#
# default_autopop3 : if this option is set to yes, openwebmail will fetch
# pop3 mail for user automatically when the user login
#
default_autopop3                yes

#
#
# default_trashreserveddays : message in trash will be deleted if its day
# age is more than this value, 0 means forever
#
default_trashreserveddays       7

#
# default_autoreplysubject : default subject for auto reply message
#
default_autoreplysubject        This is an autoreply...[Re: \$SUBJECT]

#
# defaultautoreplytext : default text for auto reply message
#
<default_autoreplytext>
Hello,

I will not be reading my mail for a while.
Your mail regarding '\$SUBJECT' will be read when I return.
</default_autoreplytext>

#
# defaultsingature : default signature for all users
#
<default_signature>
--
Distributed System Laboratory (http://dslab.ee.ncku.edu.tw)
Department of Electrical Engineering
National Cheng Kung University, Tainan, Taiwan, R.O.C.
</default_signature>
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
(thanks to Thomas Chung, tchung@pasadena.oao.com) 
------------------------------------------------------------------------------

For security reasons, the default configuration of sendmail allows sending,
but not receiving over the net (by default it will only accept connections 
on the loopback interface.)

Configure sendmail to accept incoming connections by as follows:

1. Modify /usr/share/sendmail-cf/cf/redhat.mc
   Comment out the following line by prepedning with a 'dnl'.  
     
      DAEMON_OPTIONS(ort=smtp,Addr=127.0.0.1, Name=MTA')

   Another appropriate step for a server system is to comment out the line
 
      FEATURE(ccept_unresolvable_domains')

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


Emir Litric (elitric@yahoo.com)

