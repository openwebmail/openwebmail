
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
6.  virtual hosting and account alias
7.  pam support
8.  full content search
9.  better MIME message display
10. draft folder support
11. spelling check support
12. POP3 mail support
13. mail filter support
14. message count preview
15. confirm reading support
16. BIG5/GB conversion (for Chinese only)


REQUIREMENT
-----------
Apache web server with cgi enabled
Perl 5.005 or above

CGI.pm-2.74.tar.gz
MIME-Base64-2.12.tar.gz
Authen-PAM-0.12.tar.gz
ispell-3.1.20.tar.gz
hc-30.tar.gz


INSTALL
-------
First, please connect to http://turtle.ee.ncku.edu.tw/openwebmail/ 
to get the latest released openwebmail and required packages.


If you are using FreeBSD and install apache with pkg_add,
then just

1. cd /usr/local/www
   tar -zxvBpf openwebmail-X.XX.tgz

2. modify /usr/local/www/cgi-bin/openwebmail/etc/openwebmail.conf for your need.

3. add 'Thttpd_user' to the 'Trusted users' session in your sendmail.cf,
   where 'httpd_user' is the effective user your httpd runs as.
   it is 'nobody' or 'apache', please check it in the httpd configuration file

4. If your FreeBSD is 4.2 or later
   a. chmod 4555 /usr/bin/suidperl
   b. change #!/usr/bin/perl to #!/usr/bin/suidperl in
      openwebmail.pl, openwebmail-main.pl, openwebmail-prefs.pl
      spellcheck.pl and checkmail.pl


If you are using RedHat 6.2/CLE 0.9p1(or most Linux) with apache
(by clarinet@totoro.cs.nthu.edu.tw)

1. cd /home/httpd
   tar -zxvBpf openwebmail-X.XX.tgz
   mv data/openwebmail html/
   rmdir data

2. cd /home/httpd/cgi-bin/openwebmail
   modify openwebmail.pl, openwebmail-main.pl, openwebmail-prefs.pl, 
          spellcheck.pl and checkmail.pl
   a. change all '/usr/local/www/cgi-bin/openwebmail'
              to '/home/httpd/cgi-bin/openwebmail'
      or make a symbolic link with 'ln -s /home/httpd /usr/local/www'
   modify auth_unix.pl
   a. set variable $unix_passwdfile to '/etc/shadow'
   b  set variable $unix_passwdmkdb to 'none'

3. modify /home/httpd/cgi-bin/openwebmail/etc/openwebmail.conf
   a. set mailspooldir to '/var/spool/mail'
   b. if /usr/local/www is not link to /home/httpd at 2.a
         set ow_htmldir to '/home/httpd/html/openwebmail'
         set ow_cgidir  to '/home/httpd/cgi-bin/openwebmail'
      else 
         set ow_htmldir to '/usr/local/www/html/openwebmail'
   c. set spellcheck to '/usr/bin/ispell'
   d. change default_signature for your need
   e. other changes you want

4. add 'Thttpd_user' to the 'Trusted users' session in your sendmail.cf,
   where 'httpd_user' is the effective user your httpd runs as.
   it is 'nobody' or 'apache', please check it in the httpd configuration file

5. add
   /var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }  
   to /etc/logrotate.d/syslog to enable logrotate on openwebmail.log

ps: if you are using RedHat 7.1, please use /var/www instead of /home/httpd
    It is highly recommended to read the doc/RedHat-README.txt(contributed by 
    elitric@yahoo.com) if you are installing Open WebMail on RedHat Linux.

ps: Thomas Chung (tchung@pasadena.oao.com) maintains a tarbal packed 
    with an install script special for RedHat 7.x. It is available at
    http://openwebmail.org/openwebmail/download/


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
   modify openwebmail.pl, openwebmail-main.pl, openwebmail-prefs.pl, 
          spellcheck.pl and checkmail.pl
   a. change the #!/usr/bin/perl to the location where your perl is.
   b. change all '/usr/local/www/cgi-bin/openwebmail'
              to '/usr/local/apache/share/cgi-bin/openwebmail'
   modify auth_unix.pl
   a. set variable $unix_passwdfile to '/etc/shadow'
   b  set variable $unix_passwdmkdb to 'none'

4. add 'Thttpd_user' to the 'Trusted users' session in your sendmail.cf,
   where 'httpd_user' is the effective user your httpd runs as.
   it is 'nobody' or 'apache', please check it in the httpd configuration file



USING OPENWEBMAIL WITH POSTFIX
------------------------------
If you are using postfix instead of sendmail as the MTA(mail transport agent):

1. chmod 644 /etc/postfix/main.cf
2. Use postfix 'sendmail' wrapper for the option sendmail in the 
   openwebmail.conf. In most case, postfix installs the wrapper
   where the original sendmail lives (/usr/lib/sendmail or /usr/sbin/sendmail)


CHECK VERSION OF CGI MODULE
---------------------------
It is reported that Open Webmail will hang in attachment uploading when used 
with older version of CGI module. We recommend using CGI version 2.74 or 
above for Open WebMail.

To check the version of your CGI module :

perldoc -m CGI.pm | grep CGI::VERSION 

To install the newer CGI module:

1. download new CGI module (CGI.pm-2.74.tar.gz)
2. cd /tmp
   tar -zxvf CGI.pm-2.74.tar.gz
   cd CGI.pm-2.74
   perl Makefile.PL
   make
   make install


SPEEDUP ENCODING/DECODING OF MIME ATTACHMENTS
---------------------------------------------
The encoding/decoding speed would be much faster if you install the 
MIME-Base64 module from CPAN with XS support

1. download MIME-Base64 module (MIME-Base64-2.12.tar.gz)
2. cd /tmp
   tar -zxvf MIME-Base64-2.12.tar.gz
   cd MIME-Base64-2.12
   perl Makefile.PL
   make
   make install


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
   you can add them to specllcheck_dictionaries in openwebmail.conf

ps: To know if a specific dictionary is successfully installed on
    your system, you can do a test with following command

    ispell -d dictionaryname -a


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

(on Linux without /etc/pam.conf, by protech@protech.net.tw)
If you don't have /etc/pam.conf but the directory /etc/pam.d/,
please create a file /etc/pam.d/openwebmail with the following content

auth       required	/lib/security/pam_unix.so
account    required	/lib/security/pam_unix.so
password   required	/lib/security/pam_unix.so

(on FreeBSD)
openwebmail   auth	required	/usr/lib/pam_unix.so
openwebmail   account	required	/usr/lib/pam_unix.so
openwebmail   password	required	/usr/lib/pam_unix.so    

ps: PAM support on some release of FreeBSD seems broken (ex:4.1)

4. change auth_module to 'auth_pam.pl' in the openwebmail.conf

5. check auth_pam.pl for further modification required for your system.

ps: For more detail about PAM configuration, it is recommended to read 
    "The Linux-PAM System Administrators' Guide"
    http://www.kernel.org/pub/linux/libs/pam/Linux-PAM-html/pam.html
    by Andrew G. Morgan, morgan@kernel.org


ADD NEW AUTHENTICATION TO OPENWEBMAIL
-------------------------------------
In case you found auth_unix.pl and auth_pam.pl are not suitable for your 
need, you may want to write new authentication for your own.
To add new authentication into openwebmail, you have to:

1. choose an abbreviation name for this new authentication, eg: xyz
2. write auth_xyz.pl with the following 4 function defined,

   ($realname, $uid, $gid, $homedir)=get_userinfo($user);
   @userlist=get_userlist($user);
   $retcode=check_userpassword($user, $password);
   $retcode=change_userpassword($user, $oldpassword, $newpassword);
   
   where $retcode means:
    -1 : function not supported
    -2 : parameter format error
    -3 : authentication system internal error
    -4 : password incorrect

   You may refer to auth_unix.pl or auth_pam.pl to start.

3. modify option auth_module in openwebmail.conf to auth_xyz.pl
4. test your new authentication module :)

ps: If you wish your authentication to be included in the next release of 
    openwebmail, please submit it to openwebmail@turtle.ee.ncku.edu.tw.


VIRTUAL USER SUPPORT
--------------------
Open WebMail uses sendmail virtusertable to map a virtualuser to the real 
userid in a system. A virtualuser can be either in the form of a pure 
virtualusername or virtualusername@somedomain. Please refer to 
http://www.sendmail.org/virtual-hosting.html for more detail

When a user logins Open WebMail with a loginname, 
this loginname will be checked in the following order:
1. Is this loginname@HTTP_HOST a virtualuser defined in virtusertable?
2. Is this loginname a virtualuser defined in virtusertable?
3. Is this loginname matched by the username part of a specific virtualuser?
4. Is this loginname a real userid in system?

Here is an example of /etc/virtusertable

projectmanager		pm		
johnson@company1.com	john1
tom@company1.com	tom1
tom@company2.com	tom2
mary@company3.com	mary3

Assume the url of the webmail server is http://mail.company1.com/....

The above virtusertable means:
1. if a user logins as projectmanager, 
   openwebmail checks  project@mail.company1.com
                       project@company1.com
                       project as virtualuser	---> pm

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
                       mary as virtualuser
                       mary as real user
                       mary as username part of a specific virtualuser ---> mary3
   

AUTOREPLY SUPPORT
-----------------
The auto reply function in Open WebMail is done with the vacation utility.
Since vacation utility is not available on some unix, a perl version of
vacation utility 'vacation.pl' is distributed with openwebmail.
This vacation.pl has the same syntax as the one on Solaris.
To make it work properly, be sure to modify $myname, $sendmail definition
in the vacation.pl.

If the autoreply doesn't work on your system, 
you can do debug with the -d option

1. choose a user, enable his autoreply in openwebmail user preference
2. edit the ~user/.forward file,
   add the '-d' option after vacation.pl
3. send a message to this user to test the autoreply
4. check the /var/tmp/vacation.debug for possible error information


BIG5<->GB CONVERSION
--------------------
Openwebmail supports chinese charset conversion between Big5 encoding
(used in taiwan, hongkong) and GB encoding(used in mainland) in both message 
reading and writing.
To make the conversion work properly, you have to 

1. download the Hanzi Converter (hc-30.tar.gz) 
   by Ricky Yeung(Ricky.Yeung@eng.sun.com) and 
      Fung F. Lee (lee@umunhum.stanford.edu).
2. tar -zxvf hc-30.tar.gz
   cd hc-30
   make
3. copy 'hc' and 'hc.tab' to cgi-bin/openwebmail or /usr/local/bin
4. modify the openwebmail.conf g2b_converter and b2g_converter.


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
(ex: fingerd on FreeBSD). By changing the parameter to fingerd in 
/etc/inetd.conf, users can get their mail status from remote host.

checkmail.pl can be also used in crontab to prefetch pop3mail or do folder 
index verification for users. For example:

59 23 * * *      /usr/local/www/cgi-bin/openwebmail/checkmail.pl -a -p -i -q

The above line in crontab will do pop3mail prefetching, mail filtering and
folder index verification quietly for all users at 23:59 every day .


GLOBAL ADDRESSBOOK and FILTERRULE
---------------------------------
Current support for global addressbook/filterrule is very limited.
The administrator has to make a copy of addressbook/filterbook to
the file specified by global_addressbook or global_filterbook by himself.

ps: An account may be created to maintain the global addressbook/filterbook, 
    for example: 'global'

    ln -s your_global_addressbook ~global/mail/.address.book
    ln -s your_global_filterbook  ~global/mail/.filter.book

    Please be sure that the global files are writeable by user 'global'
    and readable by others


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
4. add your language to %languagenames in openwebmail-shared.pl,
   then you can set default_language to 'xy' in openwebmail.conf

ps: If you wish your translation to be included in the next release of 
    openwebmail, please submit it to openwebmail@turtle.ee.ncku.edu.tw.


ADD MORE BACKGROUNDS TO OPENWEBMAIL
--------------------------------------------
If you would like to add some background images into openwebmail for your 
user, you can copy them into %ow_htmldir%/images/backgrounds.
Then the user can choose these backgrounds from user preference menu.

ps: If you wish to share your wonderful backgrounds with others,
    please email it to openwebmail@turtle.ee.ncku.edu.tw


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
   openwebmail, please submit it to openwebmail@turtle.ee.ncku.edu.tw


TEST
-----      
1. chdir to openwebmail cgi dir (eg: /usr/local/www/cgi-bin/openwebmail)
   and check the owner, group and permission of the following files

   ~/openwebmail.pl             - owner=root, group=mail, mode=4755
   ~/openwebmail-main.pl        - owner=root, group=mail, mode=4755
   ~/openwebmail-prefs.pl       - owner=root, group=mail, mode=4755
   ~/spellcheck.pl              - owner=root, group=mail, mode=4755
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


12/16/2001

openwebmail@turtle.ee.ncku.edu.tw

