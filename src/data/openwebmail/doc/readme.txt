
Open WebMail is a webmail system based on
the Neomail version 1.14 from Ernie Miller.

Open WebMail is targeted on dealing with very big mail folder files in a
memory efficient way. It also provides many features to help users to
switch from Microsoft Outlook smoothly.


FEATURES
---------
Open WebMail has the following enhanced features:

For Users:

* Auto Login
* Multiple Languages/Multiple Charsets
* Strong MIME Message Capability
* Full Content Search
* Draft Folder Support
* Confirm Reading Support
* Spelling Check Support
* vCard compliant Addressbook
* POP3 Support
* Mail Filter Support
* AntiSpam Support through SpamAssassin (http://www.spamassassin.org)
* AntiVirus Support through ClamAV (http://www.clamav.net)
* Calendar with Reminder/Notification Support
* Webdisk Support
* HTTP Compression

For System:

* Fast Folder Access
* Efficient Message Movement
* Smaller Memory Footprint
* Graceful File Lock
* Various Authentication Modules
* PAM support
* Remote SMTP Relaying
* Virtual Hosting
* User Alias
* Pure Virtual User Support
* Per User Capability Configuration
* Persistent Running through SpeedyCGI


REQUIREMENT
-----------
Apache web server with cgi enabled
Perl 5.005 or above

CGI.pm-3.05.tar.gz            (required)
MIME-Base64-3.01.tar.gz       (required)
libnet-1.19.tar.gz            (required)
Digest-1.08.tar.gz            (required)
Digest-MD5-2.33.tar.gz        (required)
Text-Iconv-1.2.tar.gz         (required)
libiconv-1.9.1.tar.gz         (required if system doesn't support iconv)

CGI-SpeedyCGI-2.22.tar.gz     (optional but highly recommended, for persistent running)
Compress-Zlib-1.33.tar.gz     (optional, for HTTP compression)
ispell-3.1.20.tar.gz          (optional, for spellcheck)
Quota-1.4.10.tar.gz           (optional, for unixfs quota support)
Authen-PAM-0.14.tar.gz        (optional, for auth_pam support)
openssl-0.9.7d.tar.gz         (optional, for pop3 over SSL support,
                               required only if system doesn't support libssl)
Net_SSLeay.pm-1.25.tar.gz     (optional, for pop3 over SSL support)
IO-Socket-SSL-0.96.tar.gz     (optional, for pop3 over SSL support)
clamav-0.70.tar.gz            (optional, for viruscheck,
                               available at http://www.clamav.net)
Mail-SpamAssassin-3.02.tar.gz (optional, for spamcheck,
                               available at http://www.spamassassin.org)
antiword-0.35.tar.gz          (optional, for msword preview)
ImageMagick-5.5.3.tar.gz      (optional, for thumbnail support in webdisk)
tnef-1.2.3.1.tar.gz           (optional, tnef is used mostly by mails from MS Outlook and Exchange)
wget-1.9.1.tar.gz             (optional, for URL uploading support in webdisk & msg composing)
lsof_4.73A.freebsd.tar.bz2    (optional, for openwebmail-tool --unlock)


INSTALL REQUIRED PACKAGES
-------------------------
First, you have to download required packages from
http://openwebmail.org/openwebmail/download/packages/
and copy them to /tmp


CGI.pm installation:

   cd /tmp
   tar -zxvf CGI.pm-3.05.tar.gz
   cd CGI.pm-3.05
   perl Makefile.PL
   make
   make install

ps: It is reported that Open Webmail will hang in attachment uploading
    when used with older version of CGI module. We recommend using CGI
    version 2.74 or above for Open WebMail.
    To check the version of your CGI module :

    perl -MCGI -e 'print $CGI::VERSION'


MIME-Base64 installation:

   cd /tmp
   tar -zxvf MIME-Base64-3.01.tar.gz
   cd MIME-Base64-3.01
   perl Makefile.PL
   make
   make install

ps: Though you may already have the MIME-Base64 perl module,
    we recommended you install MIME-Base64 module from source.
    This would enable the XS support in this module which greatly
    improves the encoding/decoding speed of MIME attachment.


libnet installation:

   cd /tmp
   tar -zxvf libnet-1.19.tar.gz
   cd libnet-1.19
   perl Makefile.PL (ans 'no' if asked to update configuration)
   make
   make install


Text-Iconv-1.2 installation:

   Since Text-Iconv-1.2 is actually a perl interface to the underlying iconv()
   support, you have to check if iconv() support is available in your system.
   Please type the following command

   man iconv

   If there is no manual page for iconv, your system might not support iconv(),
   You need to install libiconv package to get iconv() support.

   cd /tmp
   tar -zxvf libiconv-1.9.1.tar.gz
   cd libiconv-1.9.1
   ./configure
   make
   make install

   Type 'man iconv' again to make sure the libiconv is successfully installed.
   Then we start to install the Text-Iconv package

   cd /tmp
   tar -zxvf Text-Iconv-1.2.tar.gz
   cd Text-Iconv-1.2
   perl Makefile.PL

   ps: If your system is FreeBSD, or you just installed libiconv manually,
       please edit the Makefile.PL and change the LIBS and INC lines
       as the following before doing 'perl Makefile.PL'

       'LIBS'         => ['-L/usr/local/lib -liconv'], # e.g., '-lm'
       'INC'          => '-I/usr/local/include',      # e.g., '-I/usr/include/other'

   make
   make test

   ps: If the 'make test' failed, it means you set wrong value for LIBS and
       INC in Makefile.PL or your iconv support is not complete.
       You may copy the misc/patches/iconv.pl.fake to shares/iconv.pl to make
       openwebmail work without iconv support.

   make install


INSTALL OPENWEBMAIL
-------------------
The latest released or current version is available at
http://openwebmail.org/openwebmail/


If you are using FreeBSD and install apache with pkg_add,

1. chmod 4555 /usr/bin/suidperl
   (It seems perl after 5.8.1 should set the suidperl to 555 instead,
    or the suid support may not work)

2. cd /usr/local/www
   tar -zxvBpf openwebmail-X.XX.tar.gz

3. cd /usr/local/www/cgi-bin/openwebmail/etc
   modify openwebmail.conf for your need.

4. execute /usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl --init

ps: If you are using FreeBSD and your perl is compiled from port,
    then please note that the SUID support is disabled by default
    since the port for perl 5.8.1 or later

    You need to do 'make -DENABLE_SUIDPERL' in making port


If you are using RedHat 7.x (or most Linux) with Apache

1. cd /var/www
   tar -zxvBpf openwebmail-X.XX.tar.gz
   mv data/openwebmail html/
   rmdir data

2. cd /var/www/cgi-bin/openwebmail/etc

   modify auth_unix.conf from defaults/auth_unix.conf
   a. set passwdfile_encrypted to '/etc/shadow'
   b  set passwdmkdb           to 'none'

   modify openwebmail.conf
   a. set mailspooldir to '/var/spool/mail'
   b. set ow_htmldir   to '/var/www/html/openwebmail'
      set ow_cgidir    to '/var/www/cgi-bin/openwebmail'
   c. set spellcheck   to '/usr/bin/ispell -a -S -w "-" -d @@@DICTIONARY@@@ -p @@@PDICNAME@@@'
   d. change default_signature for your need
   e. other changes you want

3. add
   /var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }
   to /etc/logrotate.d/syslog to enable logrotate on openwebmail.log

4. execute /var/www/cgi-bin/openwebmail/openwebmail-tool.pl --init

If you are using RedHat 6.2, please use /home/httpd instead of /var/www
ps: It is highly recommended to read the doc/RedHat-README.txt(contributed by
    elitric.AT.yahoo.com) if you are installing Open WebMail on RedHat Linux.

ps: Thomas Chung (tchung.AT.openwebmail.org) maintains the rpm for all
    released and current version of openwebmail, It is available at
    http://openwebmail.org/openwebmail/download/redhat/rpm/.

    Documents for RH7.3/RH8/RH9, RHEL3, FC1/FC2/FC3 are available at
    http://openwebmail.org/openwebmail/download/redhat/howto/00-openwebmail.html
    You can get openwebmail working in 5 minutes with this :)


If you are using other UNIX with apache, that is okay

Try to find the parent directory of both your data and cgi-bin directory,
eg: /usr/local/apache/share, then

1. cd /usr/local/apache/share
   tar -zxvBpf openwebmail-X.XX.tar.gz
   mv data/openwebmail htdocs/
   rmdir data

2. cd /usr/local/apache/share/cgi-bin/openwebmail

   modify openwebmail*.pl
   change the #!/usr/bin/suidperl to the location where your suidperl is.

3. cd /usr/local/apache/share/cgi-bin/openwebmail/etc

   modify openwebmail.conf
   a. set mailspooldir to where your system mail spool is
   b. set ow_htmldir   to '/usr/local/apache/share/htdocs'
      set ow_cgidir    to '/usr/local/apache/share/cgi-bin'
   c. set spellcheck   to '/usr/local/bin/ispell -a -S -w "-" -d @@@DICTIONARY@@@ -p @@@PDICNAME@@@'
   d. change default_signature for your need
   e. other changes you want

   modify auth_unix.conf from defaults/auth_unix.conf
   a. set passwdfile_encrypted to '/etc/shadow'
   b  set passwdmkdb           to 'none'

4. execute /usr/local/apache/share/cgi-bin/openwebmail/openwebmail-tool.pl --init

ps:If you are installing Open WebMail on Solaris, please put
   'the path of your openwebmail cgi directory' in the first line of
   file /etc/openwebmail_path.conf.

   For example, if the script is located at
   /usr/local/apache/share/cgi-bin/openwebmail/openwebmail.pl,

   then the content of /etc/openwebmail_path.conf should be:
   /usr/local/apache/share/cgi-bin/openwebmail

ps: If you are using Apache server 2.0 or later,
    please edit your Apache Configuration file, replace

    AddDefaultCharset ISO-8859-1

    with

    AddDefaultCharset off


INITIALIZE OPENWEBMAIL
----------------------
In the last step of installing openwebmail, you have done:

cd the_directory_of_openwebmail_cgi_scripts
./openwebmail-tool.pl --init

This init will create the mapping tables used by openwebmail in the future.
If you skip this step, you will not be able to access the openwebmail through
web interface.

As perl on various platforms may use different underlying dbm system, the
default setting in the_directory_of_openwebmail_cgi_scripts/etc/dbm.conf
may be not correct for your system.

The init routine will test them and try to give you some useful suggestions.

1. it checks options in etc/dbm.conf,
   if they are set to wrong value, you may see output like
-------------------------------------------------------------
Please change '/the_directory_of_openwebmail_scripts/etc/dbm.conf' from

dbm_ext                 .db
dbmopen_ext             none
dbmopen_haslock         no

to

dbm_ext                 .db
dbmopen_ext             none
dbmopen_haslock         no
-------------------------------------------------------------

2. it checks if the dbm system uses DB_File.pm by default and will
   suggest a necessary patch to DB_File.pm, you may see output like
-------------------------------------------------------------
Please modify /usr/libdata/perl/5.00503/mach/DB_File.pm by adding

        $arg[3] = 0666 unless defined $arg[3];

before the following text (about line 247)

        # make recno in Berkeley DB version 2 work like recno in version 1
-------------------------------------------------------------

Please follow the suggestion or the openwebmail may not work properly.
And don't forget to redo './openwebmail-tool.pl --init' after you complete
the modification.


USING OPENWEBMAIL WITH OTHER SMTP SERVER
----------------------------------------
To make openwebmail use other SMTP server for mail sending,
you have to set the option 'smtpserver' in openwebmail.conf.
Just change the default value '127.0.0.1' to the name/ip of that SMTP server.

Please be sure the SMTP server allows mail relayed from your openwebmail host.


FILTER SUPPORT
--------------
The mailfilter checks if messages in INBOX folder matches the filters rules
defined by user. If matches, move/copy the message to the target folder.
If you move a message to the DELETE folder, which means deleting messages
from a folder. If you use INBOX as the destination in a filter rule,
any message matching this rule will be kept in the INBOX folder and
other rules will be ignored.


VIRUSCHECK SUPPORT
------------------
Openwebmail can call external programs to do viruscheck for pop3 or
other messages in INBOX. To enable virus check support, you have to

1. install ClamAV (http://www.clamav.net/)
   And ensure you have started up the daemon of the clamav - clamd
2. modify option viruscheck_pipe according to the location of clamdscan
   (it is the client side of ClamAV)
3. set viruscheck_source_allowed to either pop3 or all.
   This depends on the configuration of your mail system
   If MTA or mail deliver will do virus scanning,
   then you should set this to pop3, otherwise, you may set it to all.
4. set enable_viruscheck to yes in openwebmail.conf
5. there are some other viruscheck related options in defaults/openwebmail.conf,
   please refer to openwebmail.conf.help for more detail

ps: Thomas Chung has written a document
    "HOWTO install and configure ClamAV for Open WebMail on Red Hat/Fedora Core"
    It is available at http://openwebmail.org/openwebmail/download/redhat/howto/virus/ClamAV/HOWTO-clamav.txt


SPAMCHECK SUPPORT
-----------------
Openwebmail can call external programs to do spamcheck for pop3 or
other messages in INBOX. To enable spam check support, you have to

1. install SpamAssassin (http://www.spamassassin.org)
   And ensure you have started up the daemon of the spamassasin (spamd)
ps:Please be sure that the spamd is started with -L or --local option
   This causes spamd to do local only test, or the spamcheck will take
   a much longer time.
2. modify option spamcheck_pipe according to the location of spamc
   (it is the client side of spamassassin)
3. set spamcheck_source_allowed to either pop3 or all.
   This depends on the configuration of your mail system
   If MTA or mail deliver will do spam scanning,
   then you should set this to pop3, otherwise, you should set it to all.
4. set enable_spamcheck to yes in openwebmail.conf
5. there are some other spamcheck related options in defaults/openwebmail.conf,
   please refer to openwebmail.conf.help for more detail

ps: If you have set 'allow_user_rules 1' in the local.cf of your spamassassin,
    you may set option 'enable_saprefs' to yes in your openwebmail.conf,
    this would allow users to set the test rules, whilelist and blacklist in
    the spamassassin userprefs file (~/.spamassassin/userprefs).

ps: How and when does openwebmail call the external programs to check messages?

    The pop3 messages are checked when they are fetched
    from remote pop3 server, the fetching and checking are done in background.
    Other new messages in INBOX (which is delivered by mail system) are checked
    at the time user accesses the mail folder. A mail filtering process will be
    forked at background to check the messages in INBOX.

ps: An option "wait time for background filtering" is provided in preference,
    which can be used to control how long user would like to wait for mail
    filtering before the folder message list or message content is returned.

    Please don't set it too short or some spam/virus may not get filtered
    in time before user accesses them.

ps: The viruscheck/spamcheck is majorly designed to check messages fetched
    from pop3 server since these messages won't be checked by scanners in
    MTA or local deliver.

    While viruscheck/spamcheck can also check all messages in INBOX, but
    we suggest that the sysadm should install antispam/antivurs softwares
    in either MTA or local deliver so mails can get checked before delivered
    into INBOX. It is more efficient than scanning all mails in Open WebMail.
    And the mails will get checked even the user is using client other than
    Open WebMail.


LEARNSPAM SUPPORT
-----------------
Openwebmail can call external programs to learn HAM/SPAM messages by storing
the tokens of messages in per user bayesian db..
To enable learn ham/spam support, you have to

1. install SpamAssassin (http://www.spamassassin.org)
2. modify option learnspam_pipe and learnham_pipe according to the location
   of sa-learn (it is the ham/psam learner of spamassassin)
3. set enable_learnspam to yes in openwebmail.conf

ps:The learned result are stored as per user bayesian db,
   and learnspam is useful only if the db is referenced.

   The two cases that the per user bayesian db is used:
   a. spamassassin check is called in local deliver, or
   b. spamassassin check is enabled in openwebmail


USER QUOTA
----------
The disk space used by webmail, webcalendar or webdisk are counted together as
the user quota usage. There are five options can be used to control the user
quota in defaults/openwebmail.conf. You may override the defaults by setting
them in openwebmail.conf.

1. quota_module

This option is used to choose the quota system for your openwebmail.
There are two quota modules available currently.

a. quota_unixfs.pl

This is the recommended quota module if the openwebmail user is the real
unix user and you system has enables the disk quota.
It has the minimal overhead.

ps:You have to install the Quota-1.4.10.tar.gz to use the module.

b. quota_du.pl

This is the recommended module only if quota_unixfs.pl could not be used on
your system (eg: openwebmail user is not standard unix user or unix quota
is not available.), because it uses the 'du -sk' to get the user quota usage.

Since running 'du -sk' on a large directory may be quote time consuming,
this module will cache the result of the 'du -sk' to avoid too much overhead.
The default cache lifetime is 60 seconds and could be changed in quota_du.pl

If you set this option to 'none', then no quota system will be used in openwebmail

2. quota_limit

This option sets the limit (in kb) for user quota usage.
The webmail and webdisk operation is limited to 'delete' if quota is hit.
This option won't prevent the operation taking the user over this limit
from completing but simply inhibits further saving of messages or files
until the user quota usage is brought down again.

ps: The value set in this option is used only if quota module doesn't support
    quotalimit. ( whose quota_info() routine returns the quotalimit as -1 )

ps: If you use the quota_unixfs.pl as the quota module,
    please be sure that there is some space between the softlimit and
    hardlimit (eg:5mb)

    eg: filesystem quota softlimit=25000, hardlimit=30000

3. quota_threshold

Normally, the user quota info will be put in the window title of the browser.
But if the user quota usage is more the threshold set by this option,
a big quota string will be displayed at the top of webmail and webdisk main menu

4. delmail_ifquotahit

Set this option to yes to make openwebmail remove oldest messages from user
mail folders automatically in case his quotalimit is hit. the new total
size will be cut down to apporximately 90% of option quota_limit

5. delfile_ifquotahit

Set this option to yes to make openwebmail remove oldest files from webdisk
/ automatically in case his quotalimit is hit. the new total
size will be cut down to apporximately 90% of option quota_limit

ps: The above options are used to control quota of user homedir.
    if you want to limit the size of user mail spool (the INBOX folder),
    you have to use the spool_limit option.
    Please refer to openwebmail.conf.help for more detail.

ps: Since openwebmail 20031128, you may set the option
    use_syshomedir_for_dotdir to no to have openwebmail put index db
    in ow_usersdir instead of user homedir, thus creating db won't be
    limited by user quota.
    This would fix the problem that user exceeding his quota was unable
    to login openwebmail because of corrupt index folder db


COMMAND TOOL openwebmail-tool.pl
--------------------------------
Since mail filtering is activated only in Open WebMail, it means messages
will stay in the INBOX until user reads their mail with Open WebMail.
So 'finger' or other mail status check utility may give you wrong
information since they don't know about the filter.

A command tool 'openwebmail-tool.pl' can be used as finger replacement.
It does mail filtering before reporting mail status.

Some fingerd allow you to specify the name of finger program by -p option
(eg: fingerd on FreeBSD). By changing the parameter to fingerd in
/etc/inetd.conf, users can get their mail status from remote host.

openwebmail-tool.pl can be also used in crontab to prefetch pop3mail or
do folder index verification for users. For example:

59 5 * * *  /usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl -q -a -p -i

The above line in crontab will do pop3mail prefetching, mail filtering and
folder index verification quietly for all users at 5:59 every morning.

If you have enabled the calendar_email_notifyinterval in openwebmail.conf,
you will also need to use openwebmail-tool.pl in crontab to check the calendar
events for sending the notification emails. For example:

0 */2 * * *  /usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl -q -a -n

The above line will use openwebmail-tool.pl to check the calendar events for all
users every two hours. Please note we use this frequency because the default
value of option calendar_email_notifyinterval is 120 (minute).
You have to set the crontab according to  your calendar_email_notifyinterval.


GLOBAL ADDRESSBOOK
--------------------------------------------
Open WebMail supports multiples global addressbooks, the location for global
addressbook files is specified in the option ow_addressbooksdir.

The sysadm have to create the empty global addressbooks manually with command
'touch addressbook_filename', then other user may read/write the global
addressbook from the web addressbook interface in openwebmail.

The global addressbook will be editable to a user only if:
1. the option abook_globaleditable is set to yes, and
2. the user has enough privilege to write the global addressbook file.


GLOBAL FILTERRULE and CALENDAR
--------------------------------------------
Current support for global filterrule/calendar is very limited.
The administrator has to make a copy of filterbook/calendar to the file
specified by global_filterbook or global_calendarbook by himself.

ps: An account may be created to maintain the global addressbook/filterbook,
    for example: 'global'

    ln -s your_global_filterbook   ~global/.openwebmail/webmail/filter.book
    ln -s your_global_calendarbook ~global/.openwebmail/webcal/calendar.book

    Please be sure that the global files are writeable by user 'global'
    and readable by others


SPELL CHECK SUPPORT
-------------------
To enable the spell check in openwebmail, you have to install the ispell or
aspell package.

1. download ispell-3.1.20.tar.gz from
   http://www.cs.ucla.edu/ficus-members/geoff/ispell.html and install it,
   or you can install binary from FreeBSD package or Linux rpm

ps: if you are compiling ispell from source, you may enhance your ispell
    by using a better dictionary source.
    a. download http://openwebmail.org/openwebmail/download/contrib/words.gz
    b. gzip -d words.gz
    c. mkdir /usr/dict; cp words /usr/dict/words
    d. start to make your ispell by reading README

2. check the openwebmail.conf to see if spellcheck is pointed to the
   ispell binary

3. If you have installed multiple dictionaries for your ispell/aspell,
   you may put them in option spellcheck_dictionaries in openwebmail.conf
   and these dictionary names should be separated with comma.

ps: To know if a specific dictionary is successfully installed on
    your system, you can do a test with following command

    ispell -d dictionaryname -a

4. If the language used by a dictionary has a different character set than
   English, you have to define the characters in %dictionary_letters in
   the openwebmail-spell.pl for that dictionary.


AUTOREPLY SUPPORT
-----------------
The auto reply function in Open WebMail is done with the vacation utility.
Since vacation utility is not available on some unix, a perl version of
vacation utility 'vacation.pl' is distributed with openwebmail.
This vacation.pl has the same syntax as the one on Solaris.

If the autoreply doesn't work on your system,
you can do debug with the -d option

1. choose a user, enable his autoreply in openwebmail user preference
2. edit the ~user/.forward file,
   add the '-d' option after vacation.pl
3. send a message to this user to test the autoreply
4. check the /tmp/vacation.debug for possible error information

Things you may find in /tmp/vacation.debug

'User ... not found in to: and cc:',

This tends to occur (assuming the address is legitimate) when your email
addresses don't match your system accounts.  For instance, when mail for
tim.wood@xyz.com is deposited in system account twood.  The error will look
something like this:

20040505 170028 User twood@xyz.com twood not found in to: and cc:, autoreply canceled

Vacation.pl assumes that the user part of the email address (e.g. tim.wood)
will match their account on the system (e.g. twood).  If they don't you can
work around this by

a. add the -j after vacation.pl in option vacationpipe in openwebmail.conf

vacationpipe            %ow_cgidir%/vacation.pl -j -t60s

ps: this modification won't take effect until user reset their .forward
    file by switching on and off the email forwarding in openwebmail,
    so you may wish to use the following modification instead

b. editing vacation.pl (in the openwebmail folder, typically at
   /var/www/cgi-bin/openwebmail/). At the top of the 'MAIN' section,
   you'll find a while that's used to parse options:

    # parse options, handle initialization or interactive mode
    while (defined($ARGV[0]) && $ARGV[0] =~ /^-/) {
       $_ = shift;
    [snip]
       }
    }

   Immeadiately after that section, add:

      $opt_j=1;

   This tells vacation.pl to not check that the email address and system
   account match.  Note: this means that everytime the user receives an email
   from a mailing list, everyone on the mailing list will know the user is
   out-of-office.  And if it's a busy list, they'll hear about it a lot.
   (by twood, tim.wood.AT.compucomfed.com)


WEBDISK SUPPORT
---------------
The webdisk module provides a web interface for user to use his home
directory as a virtual disk on the web. It is also designed as a
storage of the mail attachments, you can freely copy attachments
between mail messages and the webdisk.

The / of the virtual disk is mapped to the user's home directory,
any item displayed in the virtual disk is actually located under the
user home directory.

Webdisk supports basic file operation (mkdir, rmdir, copy, move, rm),
file upload and download (multiple files or directories download is supported,
webdisk compresses them into a zip stream on the fly when transmitting).
It can also handle many types of archives, including zip, arj, rar, tar.gz,
tar.bz, tar.bz2, tgz, tbz, gz, z...

Obviously, WebDisk have to call external program to provide all the above
features, it finds the external programs in /usr/local/bin, /usr/bin
and /bin respectively.

the external programs used by webdisk are:

basic file uty                 - cp, mv, rm,
file compression/decompression - gzip, bzip2,
archive uty                    - tar, zip, unzip, unrar, unarj, lha
image thumbnail uty            - convert (in ImageMagick package)

ps: You don't have to install all external programs to use WebDisk,
    a feature will be disabled if related external program is not available.

External commands are invoked with exec() and parameters are passed by
array, which prevents using /bin/sh for shell escaped character
interpretation and thus is quite secure.

To limit the WebDisk space used by the user, please refer to the
'USER QUOTA' section


VIRTUAL HOSTING
---------------
You can have as many virtual domains as you want on same server with only one
copy of openwebmail installed. Open Webmail supports per domain config file.
Each domain can have its own set of configuration options, including
domainname, authentication module, quota limit, mailspooldir ...

You can even setup mail accounts for users without creating real unix accounts
for them. Please refer to Kevin Ellis's webpage:
"How to setup virtual users on Open WebMail using Postfix & vm-pop3d"
(http://www.bluelavalamp.net/owmvirtual/)

eg: To create configuration file for virtualdomain 'sr1.domain.com'

1. cd cgi-bin/openwebmail/etc/sites.conf/
2. cp ../openwebmail.conf sr1.domain.com
3. edit options in file 'sr1.domain.com' for domain 'vr1.domain.com'


USER ALIAS MAPPING
------------------
Open Webmail can use the sendmail virtusertable for user alias mapping.
The loginname typed by user may be pure name or name@somedomain. And this
loginname can be mapped to another pure name or name@otherdomain in the
virtusertable. This gives you the great flexibility in account management.

Please refer to http://www.sendmail.org/virtual-hosting.html for more detail

When a user logins Open WebMail with a loginname,
this loginname will be checked in the following order:

if (loginname is in the form of 'someone@somedomain') {
   user=someone
   domain=somedomain
} else {  	# a purename
   user=loginname
   domain=HTTP_HOST	# hostname in url
}

is user@domain a virtualuser defined in virtusertable?
if not {
   if (domain is mail.somedomain) {
      is user@somedomain defined in virtusertable?
   } else {
      is user@mail.domain defined in virtusertable?
   }
}

if (no mapping found && loginname is pure name) {
   is loginname a virtualuser defined in virtusertable?
}

if (any mapping found) {
   if (mappedname is in the form of 'mappedone@mappeddomain') {
      user=mappedone
      domain=mappeddomain
   } else {
      user=mappedname
      domain=HTTP_HOST
   }
}

if (option auth_withdomain is on) {
   check_userpassword for user@domain
} else {
   if (domain == HTTP_HOST) {
      check_userpassword for user
   } else {
      user not found!
   }
}

ps: if any alias found in virtusertable,
    the alias will be used as default email address for user


Here is an example of /etc/virtusertable

projectmanager		pm
johnson@company1.com	john1
tom@company1.com	tom1
tom@company2.com	tom2
mary@company3.com	mary3

Assume the url of the webmail server is http://mail.company1.com/....

The above virtusertable means:
1. if a user logins as projectmanager,
   openwebmail checks  projectmanager@mail.company1.com
                       projectmanager@company1.com
                       projectmanager as virtualuser	---> pm

2. if a user logins as johnson@company1.com
   openwebmail checks  johnson@company1.com	---> john1

   if a user logins as johnson,
   openwebmail checks  johnson@mail.company1.com
                       johnson@company1.com	---> john1

3. if a user logins as tom@company1.com,
   openwebmail checks  tom@company1.com		---> tom1

   if a user logins as tom@company2.com,
   openwebmail checks  tom@company2.com		---> tom2

   if a user logins as tom,
   openwebmail checks  tom@mail.company1.com
                       tom@company1.com		---> tom1

4. if a user logins as mary,
   openwebmail checks  mary@mail.company1.com
                       mary@company1.com
                       mary as virtualuser	---> not an alias


PURE VIRTUAL USER SUPPORT
-------------------------
Pure virtual user means a mail user who can use pop3 or openwebmail
to access his mails on the mail server but actually has no unix account
on the server.

Openwebmail pure virtual user support is currently available for system
running vm-pop3d + postfix. The authentication module auth_vdomain.pl is
designed for this purpose. Openwebmail also provides the web interface
which can be used to manage(add/delete/edit) these virtual users under
various virtual domains.

Please refer to the description in auth_vdomain.pl and auth_vdomain.conf
for more detail.

ps: vm-pop3d : http://www.reedmedia.net/software/virtualmail-pop3d/
    PostFix  : http://www.postfix.org/

    Kevin L. Ellis (kevin.AT.bluelavalamp.net) has written a tutorial
    for openwebmail + vm-pop3d + postfix
    Iis available at http://www.bluelavalamp.net/owmvirtual/


PER USER CAPABILITY CONFIGURATION
---------------------------------
While options in system config file(openwebmail.conf) are applied to all
users, you may find it useful to set the options on per user basis sometimes.
For example, you may want to limit the client ip access for some users or
limit the domain which the user can sent to. This could be easily done with
the per user config file support in Open Webmail.

The user capability file is located in cgi-bin/openwebmail/etc/user.conf/
and named as the realusername of user. Options in this file are actually
a subset of options in openwebmail.conf. An example 'SAMPLE' is provided.

eg: To creat the capability file for user 'guest':

1. cd cgi-bin/openwebmail/etc/users.conf/
2. cp SAMPLE guest
3. edit options in file 'guest' for user guest

ps: Openwebmail loads configuration files in the following order

1. cgi-bin/openwebmail/etc/defaults/openwebmail.conf
2. cgi-bin/openwebmail/etc/openwebmail.conf
3. cgi-bin/openwebmail/etc/sites.conf/domainname if file exists

   a. authentication module is loaded
   b. user alias is mapped to real userid.
   c. userid is authenticated.

4. if (option auth_withdomain is yes) {
      user conf = cgi-bin/openwebmail/etc/users.conf/domain/username
   } else {
      user conf = cgi-bin/openwebmail/etc/users.conf/username
   }
   Then openwebmail will load user conf if file exists.

Options set in the later files will override the previous ones


PAM SUPPORT
-----------
PAM (Pluggable Authentication Modules) provides a flexible mechanism
for authenticating users. More detail is available at Linux-PAM webpage.
http://www.kernel.org/pub/linux/libs/pam/

Solaris 2.6, Linux and FreeBSD 3.1 are known to support PAM.
To make Open WebMail use the support of PAM, you have to:

1. download the Perl Authen::PAM module (Authen-PAM-0.14.tar.gz)
   It is available at http://www.cs.kuleuven.ac.be/~pelov/pam/
2. cd /tmp
   tar -zxvf Authen-PAM-0.14.tar.gz
   cd Authen-PAM-0.14
   perl Makefile.PL
   make
   make install

ps: Doing 'make test' is recommended when making the Authen::PAM,
    if you encounter error in 'make test', the PAM on your system
    will probable-ly not work.

3. change auth_module to 'auth_pam.pl' in the openwebmail.conf

4. check auth_pam.pl and auth_pam.conf for further information.

ps: Since the authentication module is loaded only once in persistent mode,
    you need to do 'touch openwebmail*pl' to make the modification active.
    To avoid this, you may change your openwebmail backto suid perl mode
    before you make the modifications.
ps: For more detail about PAM configuration, it is recommended to read
    "The Linux-PAM System Administrators' Guide"
    http://www.kernel.org/pub/linux/libs/pam/Linux-PAM-html/pam.html
    by Andrew G. Morgan, morgan.AT.kernel.org

ps: The script in cgi-bin/openwebmail/misc/test/authtest.pl can used to
    test if the a authentication module under cgi-bin/openwebmail/auth/ works
    on your system.

    eg: cd your_cgi-bin/openwebmail/
        perl authtest.pl auth_unix.pl someusername passwd
        perl authtest.pl auth_pam.pl someusername passwd

    ps: On some system, root is not allowed to login,
        and PAM will always return false for root login


ADD NEW AUTHENTICATION MODULE TO OPENWEBMAIL
--------------------------------------------
Various authentications are directly available for openwebmail, including

auth_ldap.pl
auth_mysql.pl
auth_mysql_vmail.pl
auth_pam.pl
auth_pg.pl
auth_pgsql.pl
auth_pop3.pl
auth_unix.pl
auth_vdomain.pl

In case you found these modules not suitable for your need,
you may write a new authentication module for your own.

To add new authentication module into openwebmail, you have to:

1. choose an abbreviation name for this new authentication, eg: xyz

2. declare the package name in the first line of file auth_xyz.pl

   package ow::auth_xyz;

3. implement the following 4 function:

   ($retcode, $errmsg, $realname, $uid, $gid, $homedir)=
    get_userinfo($r_config, $domain, $user);

   ($retcode, $errmsg, @userlist)=
    get_userlist($r_config, $domain);

   ($retcode, $errmsg)=
    check_userpassword($r_config, $domain, $user, $password);

   ($retcode, $errmsg)=
    change_userpassword($r_config, $domain, $user, $oldpassword, $newpassword);

   where $retcode means:
    -1 : function not supported
    -2 : parameter format error
    -3 : authentication system internal error
    -4 : username/password incorrect

   $errmsg is the message to be logged to openwebmail log file,
   this would ease the work for sysadm in debugging problem of openwebmail

   $r_config is the reference of the openwebmail %config,
   you may just leave it untouched

   ps: You may refer to auth_unix.pl or auth_pam.pl to start.
       And please read doc/auth_module.txt

4. modify option auth_module in openwebmail.conf to auth_xyz.pl

5. test your new authentication module :)

ps: If you wish your authentication module to be included in the next release
    of openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw.
ps: Since the authentication module is loaded only once in persistent mode,
    you need to do 'touch openwebmail*pl' to make the modification active.
    To avoid this, you may change your openwebmail backto suid perl mode
    before you make the modifications.


ADD SUPPORT FOR NEW LANGUAGE
-----------------------------
It is very simple to add support for your language into openwebmail

1. choose an abbreviation for your language, eg: xy

ps: You may choose the abbreviation by referencing the following url
    http://babel.alis.com/langues/iso639.en.htm
    http://www.unicode.org/unicode/onlinedat/languages.html
    http://www.w3.org/International/O-charset.html

2. cd cgi-bin/openwebmail/etc.
   cp lang/en lang/xy
   cp -R templates/en templates/xy

3. translate file lang/xy and templates/xy/* from English to your language

4. change the package name of you language file (in the first line)

   package ow::xy

5. add the name and charset of your language to %languagenames,
   %languagecharsets in modules/lang.pl, then set default_language
   to 'xy' in openwebmail.conf

6. check iconv.pl, if the charset is not listed, add a line for this charset
   in both %charset_localname and %charset_convlist.

7. translate the files used by HTML editor

   cd data/openwebmail/javascript/htmlarea.openwebmail/popups
   cp -R en xy
   cd xy

   then translate htmlarea-lang.js, insert_image.html, insert_sound.html,
   insert_table.html and select_color.html into language xy

   Some style sheel setting in insert*html may need to be adjusted to
   get the best layout for your language. They are

   a. the width and height of the pop window, defined in the first line
      <html style="width: 398; height: 243">

   b. the boxies for fieldsets, defined in middle of the file
      .fl { width: 9em; float: left; padding: 2px 5px; text-align: right; }
      .fr { width: 6em; float: left; padding: 2px 5px; text-align: right; }

      .fl is for box in the left and .fr is for box in the right,
      you may try wider width for better layout

8. If you want, you may create the holidays of your language with the
   openwebmail calendar, then copy the ~/.openwebmail/webcal/calendar.book into
   etc/holidaysdir/your_languagename. Them the holidays will be displayed
   to all users of this language

9. If you want, you may also translation help tutorial to your language
   the help files are located under data/openwebmail/help.

ps: if your language is Right-To-Left oriented and you can read Arabic,
    you can use the Arabic template instead of English as the start templates.
    And don't forget to mention it when you submit the templates
    to the openwebmail team.
ps: Since the language and templates are loaded only once in persistent mode,
    you need to do 'touch openwebmail*pl' to make the modification active.
    To avoid this, you may change your openwebmail backto suid perl mode
    before you make the modifications.

ps: If you just want support of different charset of existing language,
    you may try the openwebmail-tool.pl --langconv command

    a. choose a new name for the converted language
    b. add the new name and it charset to %languagenames,%languagecharsets
       in modules/lang.pl
    c. execute 'openwebmail-tool.pl --langconv oldlangname newlangname'
    d. if you see any error complaing directory doesn't exist,
       you may creat it manually and re-execute above command
    e. After conversion, don't forget to test the converted lang file by
       'perl etc/lang/newlangname' to ensure it is valid for perl parser.

ps: If you wish your translation to be included in the next release of
    openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw.

    IMPORTANT!!!
    Please be sure your translation is based on the template files in the
    latest openwebmail-current.tar.gz. And please send both your tranlsation
    and english version files it based on to us. So we can check if there
    is any latest modification should be added your translation.


ADD NEW CHARSET TO AUTO CONVERSION LIST
---------------------------------------
Openwebmail can do charset conversion automatically if a message is written
with charset other than the one you are using. Openwebmail does this by calling
the iconv() charset conversion function, as defined by the Single UNIX Specification.

To make openwebmail do auto-convert a new charset for your language:
1. find the charset used by your language in %charset_convlist in charset_iconv.pl
2. put this new charset to the convlist of the charset of your language
3. define the localname of the new charset on your OS to the %charset_localname.
   (It is always the same as the name of charset but in capitals.)

Note: The possible conversions and the quality of the conversions depend on the
      available iconv conversion tables and algorithms, which are in most cases
      supplied by the operating system vendor.


ADD MORE BACKGROUNDS TO OPENWEBMAIL
-----------------------------------
If you would like to add some background images into openwebmail for your
user, you can copy them into %ow_htmldir%/images/backgrounds.
Then the user can choose these backgrounds from user preference menu.

ps: If you wish to share your wonderful backgrounds with others,
    please email it to openwebmail.AT.turtle.ee.ncku.edu.tw


DESIGN YOUR OWN ICONSET IN OPENWEBMAIL
---------------------------------------
If you are interested in designing your own image iconset in the openwebmail,
you have to

1. create a new sub directory in the %ow_htmldir%/images/iconsets/,
   eg: MyIconSet
   ps: %ow_htmldir% is the dir where openwebmail could find its html objects,
       it is defined in openwebmail.conf
2. copy all images from %ow_htmldir%/images/iconsets/Default to MyIconSet
3. modify the image files in the %ow_htmldir%/images/iconsets/MyIconSet
   for your need

ps:In case you want to design iconsets with text inside, the default font used
   in Default.English and Cool3D.English is 'Arial Narrow'.

If you are interested in designing your own text iconset in the openwebmail,
you have to

1. create a new sub directory started with Text. in the %ow_htmldir%/images/iconsets/,
   eg: Text.MyLang
   ps: %ow_htmldir% is the dir where openwebmail could find its html objects,
       it is defined in openwebmail.conf
2. copy %ow_htmldir%/images/iconsets/Text.English/icontext to Text.MyLnag/icontext
3. modify the Text.MyLang/icontext for your language

ps: If your are going to make Cool3D iconset for your language with Photoshop,
    you may start with the psd file created by Jan Bilik <jan.AT.bilik.org>,
    it could save some of your time. The psd file is available at
    http://openwebmail.org/openwebmail/contrib/Cool3D.iconset.Photoshop.template.zip

ps: If you wish the your new iconset to be included in the next release of
    openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw


TEST
-----
1. chdir to openwebmail cgi dir (eg: /usr/local/www/cgi-bin/openwebmail)
   and check the owner, group and permission of the following files

   ~/openwebmail*.pl            - owner=root, group=mail, mode=4755
   ~/vacation.pl                - owner=root, group=mail, mode=0755
   ~/etc                        - owner=root, group=mail, mode=755
   ~/etc/sessions               - owner=root, group=mail, mode=771
   ~/etc/users                  - owner=root, group=mail, mode=771

   /var/log/openwebmail.log     - owner=root, group=mail, mode=660

2. test your webmail with http://your_server/cgi-bin/openwebmail/openwebmail.pl

If there is any problem, please check the faq.txt.
The latest version of FAQ will be available at
http://openwebmail.org/openwebmail/download/doc/faq.txt


PERSISTENT RUNNING through SpeedyCGI
------------------------------------
SpeedyCGI: http://www.daemoninc.com/SpeedyCGI/

"SpeedyCGI is a way to run perl scripts persistently, which can make
them run much more quickly." - Sam Horrocks.

Openwebmail can get almost 5x to 10x speedup when running with SpeedyCGI.
You can get a quite reactive openwebmail systems on a very old P133 machine :)

Note: Don't try to fly before you can walk...
      Please do this speedup modification only after
      your openwebmail is working with regular suidperl

1. install SpeedyCGI

   get the latest SpeedyCGI source from
   http://sourceforge.net/project/showfiles.php?group_id=2208
   http://daemoninc.com/SpeedyCGI/CGI-SpeedyCGI-2.22.tar.gz

   cd /tmp
   tar -zxvf path_to_source/CGI-SpeedyCGI-2.22.tar.gz
   cd CGI-SpeedyCGI-2.22
   perl Makefile.PL (ans 'no' with the default)

   then edit speedy/Makefile
   and add " -DIAMSUID" to the end of the line of "DEFINE = "

   make
   make install
   (If you encounter error complaining about install mod_speedy,
    that is okay, you can safely ignore it.)

2. set speedy to setuid root

   Find the speedy binary according to the messages in previous step,
   it is possible-ly at /usr/bin/speedy or /usr/local/bin/speedy.

   Assume it is installed in /usr/bin/speedy

   cp /usr/bin/speedy /usr/bin/speedy_suidperl
   chmod 4555 /usr/bin/speedy_suidperl

3. modify openwebmail for speedy

   The code of openwebmail has already been modified to work with SpeedyCGI,
   so all you have to do is to
   replace the first line of all cgi-bin/openwebmail/openwebmail*pl
   from
	#!/usr/bin/suidperl -T
   to
	#!/usr/bin/speedy_suidperl -T -- -T/tmp/speedy

   The first -T option (before --) is for perl interpreter.
   The second -T/tmp/speedy option is for SpeedyCGI system,
   which means the prefix of temporary files used by SpeedyCGI.

   ps: You will see a lot of /tmp/speedy.number files if your system is
       quite busy, so you may change this to value like /var/run/speedy

4. test you openwebmail for the speedup.

5. If you are installing openwebmail on a low end machine, then you may
   wish to eliminate the firsttime startup delay of the scripts for the user.
   You may use the preload.pl, it acts as a http client to start
   openwebmail on the web server automatically.

   a. through web interface
      http://your_server/cgi-bin/openwebmail/preload.pl
      Please refer to preload.pl for default password and how to change it.

   b. through command line or you can put the following line in crontab
      to preload the most frequently used scripts into mempry

      0 * * * *	/usr/local/www/cgi-bin/openwebmail/preload.pl -q openwebmail.pl openwebmail-main.pl openwebmail-read.pl

      If your machine has a lot of memory, you may choose to preload all
      openwebmail scripts

      0 * * * *	/usr/local/www/cgi-bin/openwebmail/preload.pl -q --all

6. Need more speedup?

   Yes, you can try to install the mod_speedycgi to your Apache,
   but you may need to recompile Apache to make it allow using root as euid
   Please refer to README in SpeedyCGI source tar ball..

   Another approach for speedup is to use some httpd that handles muliples
   connections with only one process, eg: http://www.acme.com/software/thttpd/,
   instead of the apache web server.

   Please refer to doc/thttpd.txt for some installation tips.

ps: Kevin L. Ellis (kevin.AT.bluelavalamp.net) has written a tutorial
    and benchmark for OWM + SpeedyCGI.
    It is available at http://www.bluelavalamp.net/owmspeedycgi/

7. Compatibility with perl 5.8.4

   The latest perl 5.8.4 does more strict check for suid scripts,
   and the following two may cause incompatibility for some users

   a. the name of the perl interpreter must has string 'perl'

      We used suggest 'speedy_suid' as the name of suid speedy perl interpreter,
      but we would like to suggest 'speedy_suidperl' as the name of speedy perl
      interpreter now.

   b. the parameter passed in the first line of the script must be the same
      as the one the perl interpreter get.

      This restirction stop us from using the following line in the script

	#!/usr/bin/speedy_suidperl -T -- -T/tmp/speedy

      All we can use is

	#!/usr/bin/speedy_suidperl

      In other words, we can't use "-- -parameter_for_speedy" to pass parameter
      to speedycgi itself

   ps: If you really need to change the tmpbase for SpeedyCGI, you may apply the
       patch in cgi-bin/openwebmail/misc/patches/speedycgi.tmpbase.patch to the
       SpeedyCGi 2.22 source, it changes tmpbase from /tmp/speedy to /var/run/speedy


HTTP COMPRESSION
----------------
To make this feature work, you have to install the Compress-Zlib-1.33.tar.gz.
HTTP Compression is very useful for users with slow connection to the
openwebmail server (eg: dialup user, PDA user).

Note: There are some compatibility issues for HTTP compression

1. Some proxy servers only support HTTP compression via HTTP 1.1,
   the user have to enable the use of HTTP1.1 for proxy in their browser
2. Some proxy servers don't support HTTP compression at all,
   the user have to list the webmail server as directly connected in
   the advanced proxy setting in their browser
3. Some browsers have problems when using HTTP compression with SSL,
4. Some browsers claim to support HTTP compression but actually not.

The login screen has a checkbox for HTTP compression.
So in case there is any problem, the user can relogin with checkbox unchecked.


INTEGRATION WITH HTML PAGES
---------------------------
A small script has been made to let static html page display the
user mail/calendar status dynamically.
All you need to do is to put the following text in html source code.

<table cellspacing=0 cellpadding=0><tr><td>
<script language="JavaScript"
src="http://you_server_domainname/cgi-bin/openwebmail/userstat.pl">
</script>
</td></tr></table>

or

<table cellspacing=0 cellpadding=0><tr><td>
<script language="JavaScript"
src="http://you_server_domainname/cgi-bin/openwebmail/userstat.pl?playsound=1">
</script>
</td></tr></table>

If the user has ever logined openwebmail successfully,
then his mail/calendar ststus would be displayed in this html page
as an link to the openwebmail login page.


TODO
----
Features that we would like to implement first...

1. web bookmark
2. PGP/GNUPG integration
3. shared folder/calendar

Features that people may also be interested

1. maildir support
2. online people sign in
3. log analyzer


Jan/06/2005

openwebmail.AT.turtle.ee.ncku.edu.tw

