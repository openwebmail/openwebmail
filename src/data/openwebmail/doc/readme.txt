
Open WebMail is a webmail system based on 
the Neomail version 1.14 from Ernie Miller. 

Open WebMail is targeted on dealing with very big mail folder files in a 
memory efficient way. It also provides many features to help users to 
switch from Microsoft Outlook smoothly. 


FEATURES
---------
Open WebMail has the following enhanced features:

1.  fast folder access
2.  efficient messages movement
3.  smaller memory footprint
4.  convenient folder and message operation
5.  graceful filelock
6.  remote SMTP relaying
7.  virtual hosting
8.  user alias
9.  per user capability configuration
10. various authentication modules
11. pam support
12. full content search
13. strong MIME message capability
14. draft folder support
15. spelling check support
16. calendar support
17. POP3 mail support
18. mail filter support
19. message count preview
20. confirm reading support
21. BIG5/GB conversion (for Chinese only)


REQUIREMENT
-----------
Apache web server with cgi enabled
Perl 5.005 or above

CGI.pm-2.74.tar.gz       (required)
MIME-Base64-2.12.tar.gz  (required)
libnet-1.0901.tar.gz     (required)
Authen-PAM-0.12.tar.gz   (optional)
ispell-3.1.20.tar.gz     (optional)


INSTALL REQUIRED PACKAGES
-------------------------
First, you have to download required packages from
http://turtle.ee.ncku.edu.tw/openwebmail/download/packages/
and copy them to /tmp


For CGI.pm do the following:

   cd /tmp
   tar -zxvf CGI.pm-2.74.tar.gz
   cd CGI.pm-2.74
   perl Makefile.PL
   make
   make install

ps: It is reported that Open Webmail will hang in attachment uploading 
    when used with older version of CGI module. We recommend using CGI 
    version 2.74 or above for Open WebMail.
    To check the version of your CGI module :

    perldoc -m CGI.pm | grep CGI::VERSION 


For MIME-Base64 do the following:

   cd /tmp
   tar -zxvf MIME-Base64-2.12.tar.gz
   cd MIME-Base64-2.12
   perl Makefile.PL
   make
   make install

ps: Though you may already have the MIME-Base64 perl module,
    we recommended you install MIME-Base64 module from source.
    This would enable the XS support in this module which greatly
    improves the encoding/decoding speed of MIME attachment.


For libnet do the following:

   cd /tmp
   tar -zxvf libnet-1.0901.tar.gz
   cd libnet-1.0901
   perl Makefile.PL (ans 'no' if asked to update configuration)
   make
   make install


INSTALL OPENWEBMAIL
-------------------
The latest released or current version is available at
http://turtle.ee.ncku.edu.tw/openwebmail/ 

If you are using FreeBSD and install apache with pkg_add,
then just

1. cd /usr/local/www
   tar -zxvBpf openwebmail-X.XX.tgz

2. modify /usr/local/www/cgi-bin/openwebmail/etc/openwebmail.conf for your need.

3. If your FreeBSD is 4.2 or later
   a. chmod 4555 /usr/bin/suidperl
   b. change #!/usr/bin/perl to #!/usr/bin/suidperl in

      openwebmail.pl, openwebmail-main.pl, 
      openwebmail-read.pl, openwebmail-viewatt.pl, 
      openwebmail-send.pl, openwebmail-spell.pl,
      openwebmail-prefs.pl, openwebmail-folder.pl, 
      openwebmail-abook.pl, openwebmail-advsearch.pl
      and checkmail.pl

If you are using RedHat 6.2/CLE 0.9p1(or most Linux) with apache
(by clarinet.AT.totoro.cs.nthu.edu.tw)

1. cd /home/httpd
   tar -zxvBpf openwebmail-X.XX.tgz
   mv data/openwebmail html/
   rmdir data

2. cd /home/httpd/cgi-bin/openwebmail
   modify auth_unix.pl
   a. set variable $unix_passwdfile to '/etc/shadow'
   b  set variable $unix_passwdmkdb to 'none'

3. modify /home/httpd/cgi-bin/openwebmail/etc/openwebmail.conf
   a. set mailspooldir to '/var/spool/mail'
   b. set ow_htmldir to '/home/httpd/html/openwebmail'
      set ow_cgidir  to '/home/httpd/cgi-bin/openwebmail'
   c. set spellcheck to '/usr/bin/ispell'
   d. change default_signature for your need
   e. other changes you want

4. add
   /var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }  
   to /etc/logrotate.d/syslog to enable logrotate on openwebmail.log

ps: If you are using RedHat 7.1, please use /var/www instead of /home/httpd
    It is highly recommended to read the doc/RedHat-README.txt(contributed by 
    elitric.AT.yahoo.com) if you are installing Open WebMail on RedHat Linux.

ps: Thomas Chung (tchung.AT.pasadena.oao.com) maintains a tarbal packed 
    with an install script special for RedHat 7.x. It is available at
    http://openwebmail.org/openwebmail/download/redhat-7x-installer/.
    You can get openwebmail to work in 5 minutes with this :)

If you are using other UNIX with apache, that is okay

Try to find the parent directory of both your data and cgi-bin directory,
eg: /usr/local/apache/share, then

1. cd /usr/local/apache/share
   tar -zxvBpf openwebmail-X.XX.tgz
   mv data/openwebmail htdocs/
   rmdir data

2. modify /usr/local/apache/share/cgi-bin/openwebmail/etc/openwebmail.conf 
   a. set mailspooldir to where your system mail spool is
   b. set ow_htmldir to '/usr/local/apache/share/htdocs'
      set ow_cgidir  to '/usr/local/apache/share/cgi-bin'
   c. set spellcheck to '/usr/local/bin/ispell'
   d. change default_signature for your need
   e. other changes you want

3. cd /usr/local/apache/share/cgi-bin/openwebmail
   modify 

      openwebmail.pl, openwebmail-main.pl, 
      openwebmail-read.pl, openwebmail-viewatt.pl, 
      openwebmail-send.pl, openwebmail-spell.pl,
      openwebmail-prefs.pl, openwebmail-folder.pl, openwebmail-abook.pl
      and checkmail.pl

   change the #!/usr/bin/perl to the location where your suidperl is.

   modify auth_unix.pl
   a. set variable $unix_passwdfile to '/etc/shadow'
   b  set variable $unix_passwdmkdb to 'none'


CHECK YOUR DBM SYSTEM
---------------------
Some unix has different dbm system than others does, so you may have to 
change the dbm_ext and dbmopen_ext option in openwebmail.conf to make 
openwebmail work on your server. (eg: Cobalt, Solaris, Linux/Slackware)

To find the correct setting for the two options: 

perl cgi-bin/openwebmail/uty/dbmtest.pl [enter]

and you will get output like this:

dbm_ext         .db
dbmopen_ext     none

Then put the two lines into your openwebmail.conf.


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


COMMAND TOOL checkmail.pl
-------------------------
Since mail filtering is activated only in Open WebMail, it means messages 
will stay in the INBOX until user reads their mail with Open WebMail. 
So 'finger' or other mail status check utility may give you wrong 
information since they don't know about the filter.

A command tool 'checkmail.pl' can be used as finger replacement.
It does mail filtering before report mail status. 

Some fingerd allow you to specify the name of finger program by -p option
(eg: fingerd on FreeBSD). By changing the parameter to fingerd in 
/etc/inetd.conf, users can get their mail status from remote host.

checkmail.pl can be also used in crontab to prefetch pop3mail or do folder 
index verification for users. For example:

59 23 * * *      /usr/local/www/cgi-bin/openwebmail/checkmail.pl -a -p -i -q

The above line in crontab will do pop3mail prefetching, mail filtering and
folder index verification quietly for all users at 23:59 every day .


GLOBAL ADDRESSBOOK, FILTERRULE and CALENDAR
--------------------------------------------
Current support for global addressbook/filterrule/calendar is very limited.
The administrator has to make a copy of addressbook/filterbook/calendar to
the file specified by global_addressbook, global_filterbook or 
global_calendarbook by himself.

ps: An account may be created to maintain the global addressbook/filterbook, 
    for example: 'global'

    ln -s your_global_addressbook  ~global/mail/.address.book
    ln -s your_global_filterbook   ~global/mail/.filter.book
    ln -s your_global_calendarbook ~global/mail/.calendar.book

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
    a. download http://turtle.ee.ncku.edu.tw/openwebmail/download/contrib/words.gz
    b. gzip -d words.gz
    c. mkdir /usr/dict; cp words /usr/dict/words
    d. start to make your ispell by reading README

2. check the openwebmail.conf to see if spellcheck is pointed to the 
   ispell binary

3. If you have installed multiple dictionaries for your ispell/aspell,
   you may put them in option spellcheck_dictionaries in openwebmail.conf
   and these dictionary names should be seperated with comma.

ps: To know if a specific dictionary is successfully installed on
    your system, you can do a test with following command

    ispell -d dictionaryname -a

4. If the language used by a dictionary has a differnet character set than
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
virtusertable. This gives you the great flexsibility in account management. 

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

1. cgi-bin/openwebmail/etc/openwebmail.conf.default
2. cgi-bin/openwebmail/etc/openwebmail.conf
3. cgi-bin/openwebmail/etc/sites.conf/domainname if file exists

   a. authentication module is loaded
   b. user alias is mapped to real userid.
   c. userid is authenticated.

4. cgi-bin/openwebmail/etc/users.conf/username if file exists

Options set in the later files will override the previous ones


PAM SUPPORT
-----------
PAM (Pluggable Authentication Modules) provides a flexible mechanism 
for authenticating users. More detail is available at Linux-PAM webpage.
http://www.kernel.org/pub/linux/libs/pam/ 

Solaris 2.6, Linux and FreeBSD 3.1 are known to support PAM.
To make Open WebMail use the support of PAM, you have to:

1. download the Perl Authen::PAM module (Authen-PAM-0.12.tar.gz)
   It is available at http://www.cs.kuleuven.ac.be/~pelov/pam/
2. cd /tmp
   tar -zxvf Authen-PAM-0.12.tar.gz
   cd Authen-PAM-0.12
   perl Makefile.PL
   make
   make install

ps: Doing 'make test' is recommended when making the Authen::PAM,
    if you encounter error in 'make test', the PAM on your system
    will probablely not work.

3. add the following 3 lines to your /etc/pam.conf 

(on Solaris)
openwebmail   auth	required	/usr/lib/security/pam_unix.so.1
openwebmail   account	required	/usr/lib/security/pam_unix.so.1
openwebmail   password	required	/usr/lib/security/pam_unix.so.1

(on Linux)
openwebmail   auth	required	/lib/security/pam_unix.so
openwebmail   account	required	/lib/security/pam_unix.so
openwebmail   password	required	/lib/security/pam_unix.so

(on Linux without /etc/pam.conf, by protech.AT.protech.net.tw)
If you don't have /etc/pam.conf but the directory /etc/pam.d/,
please create a file /etc/pam.d/openwebmail with the following content

auth       required	/lib/security/pam_unix.so
account    required	/lib/security/pam_unix.so
password   required	/lib/security/pam_unix.so

(on FreeBSD)
openwebmail   auth	required	/usr/lib/pam_unix.so
openwebmail   account	required	/usr/lib/pam_unix.so
openwebmail   password	required	/usr/lib/pam_unix.so    

ps: PAM support on some release of FreeBSD seems broken (eg:4.1)

4. change auth_module to 'auth_pam.pl' in the openwebmail.conf

5. check auth_pam.pl for further modification required for your system.

ps: For more detail about PAM configuration, it is recommended to read 
    "The Linux-PAM System Administrators' Guide"
    http://www.kernel.org/pub/linux/libs/pam/Linux-PAM-html/pam.html
    by Andrew G. Morgan, morgan.AT.kernel.org


ADD NEW AUTHENTICATION MODULE TO OPENWEBMAIL
--------------------------------------------
Various authentications are directly available for openwebmail, including
auth_unix.pl, auth_ldap.pl, auth_mysql, auth_mysql_vmail.pl,
auth_pgsql, auth_pop3.pl and auth_pam.pl. In case you found these modules 
not suitable for your need, you may write a new authentication module for 
your own.

To add new authentication module into openwebmail, you have to:

1. choose an abbreviation name for this new authentication, eg: xyz
2. write auth_xyz.pl with the following 4 function defined,

   ($realname, $uid, $gid, $homedir)=get_userinfo($domain, $user);
   @userlist=get_userlist($domain);
   $retcode=check_userpassword($domain, $user, $password);
   $retcode=change_userpassword($domain, $user, $oldpassword, $newpassword);
   
   where $retcode means:
    -1 : function not supported
    -2 : parameter format error
    -3 : authentication system internal error
    -4 : password incorrect

   You may refer to auth_unix.pl or auth_pam.pl to start.

3. modify option auth_module in openwebmail.conf to auth_xyz.pl
4. test your new authentication module :)

ps: If you wish your authentication module to be included in the next release
    of openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw.


ADD SUPPORT FOR NEW LANGUAGE
-----------------------------
It is very simple to add support for your language into openwebmail

1. choose an abbreviation for your language, eg: xy

ps: You may choose the abbreviation by referencing the following url
    http://i18n.kde.org/stats/gui/i18n-table-KDE_2_2_BRANCH.html
    http://babel.alis.com/langues/iso639.en.htm
    http://www.unicode.org/unicode/onlinedat/languages.html

2. cd cgi-bin/openwebmail/etc. 
   cp lang/en lang/xy
   cp -R templates/en templates/xy
3. translate file lang/xy and templates/xy/* from English to your language
4. add the name and charset of your language to %languagenames, %languagecharsets 
   in openwebmail-shared.pl, then set default_language to 'xy' in openwebmail.conf

ps: If you wish your translation to be included in the next release of 
    openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw.


ADD MORE BACKGROUNDS TO OPENWEBMAIL
--------------------------------------------
If you would like to add some background images into openwebmail for your 
user, you can copy them into %ow_htmldir%/images/backgrounds.
Then the user can choose these backgrounds from user preference menu.

ps: If you wish to share your wonderful backgrounds with others,
    please email it to openwebmail.AT.turtle.ee.ncku.edu.tw


DESIGN YOUR OWN ICONSET IN OPENWEBMAIL
---------------------------------------
If you are interested in designing your own image set in the openwebmail,
you have to

1. create a new sub directory in the %ow_htmldir%/images/iconsets/, 
   eg: MyIconSet
   ps: %ow_htmldir% is the dir where openwebmail could find its html objects,
       it is defined in openwebmail.conf
2. copy all images from %ow_htmldir%/images/iconsets/Default to MyIconSet
3. modify the image files in the %ow_htmldir%/images/iconsets/MyIconSet 
   for your need

ps: If you wish the your new iconset to be included in the next release of 
   openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw


TEST
-----      
1. chdir to openwebmail cgi dir (eg: /usr/local/www/cgi-bin/openwebmail)
   and check the owner, group and permission of the following files

   ~/openwebmail.pl             - owner=root, group=mail, mode=4755
   ~/openwebmail-main.pl        - owner=root, group=mail, mode=4755
   ~/openwebmail-read.pl        - owner=root, group=mail, mode=4755
   ~/openwebmail-viewatt.pl     - owner=root, group=mail, mode=4755
   ~/openwebmail-send.pl        - owner=root, group=mail, mode=4755
   ~/openwebmail-spell.pl       - owner=root, group=mail, mode=4755
   ~/openwebmail-prefs.pl       - owner=root, group=mail, mode=4755
   ~/openwebmail-folder.pl      - owner=root, group=mail, mode=4755
   ~/openwebmail-abook.pl       - owner=root, group=mail, mode=4755
   ~/checkmail.pl               - owner=root, group=mail, mode=4755
   ~/vacation.pl                - owner=root, group=mail, mode=0755
   ~/etc                        - owner=root, group=mail, mode=755
   ~/etc/sessions               - owner=root, group=mail, mode=770
   ~/etc/users                  - owner=root, group=mail, mode=770

   /var/log/openwebmail.log     - owner=root, group=mail, mode=660

2. test your webmail with http://your_server/cgi-bin/openwebmail/openwebmail.pl

If there is any problem, please check the faq.txt.
The latest version of FAQ will be available at
http://turtle.ee.ncku.edu.tw/openwebmail/download/doc/faq.txt


TODO
----
Features that we would like to implement first...

1. web calendar
2. web disk
3. shared folder
4. mod_perl compatibility

Features that people may also be interested

1. maildir support
2. online people sign in
3. log analyzer


03/14/2002

openwebmail.AT.turtle.ee.ncku.edu.tw

