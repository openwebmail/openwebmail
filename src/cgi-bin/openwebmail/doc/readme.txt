
Open WeMail is a webmail system based on 
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
7.  full content search
8.  better MIME message display
9.  draft folder support
10. spelling check support
11. POP3 mail support
12. mail filter support
13. message count preview
14. confirm reading support


REQUIREMENT
-----------
Apache web server with cgi enabled
Perl 5.005 or above


INSTALL
-------
If you are using FreeBSD and install apache with packages,
then just

1. cd /usr/local/www
   tar -zxvBpf openwebmail-X.XX.tgz
2. modify /usr/local/www/cgi-bin/openwebmail/etc/openwebmail.conf for your need.
3. add 'Tnobody' to the 'Trusted users' session in your sendmail.cf


If you are using Redhat 6.2/CLE 0.9p1(or most Linux) with apache
(by clarinet@totoro.cs.nthu.edu.tw)

1. cd /home/httpd
   tar -zxvBpf openwebmail-X.XX.tgz
   mv data/openwebmail html/
   rmdir data
2. modify /home/httpd/cgi-bin/openwebmail/etc/openwebmail.conf
   for your need
   a. change the $spellcheck to '/usr/bin/ispell'
   b. change the $passwdfile to '/etc/shadow'
   c. search all '/usr/local/www' and replace to '/home/httpd'
   d. change the $mailspooldir to '/var/spool/mail'
   e. change the $defaultsignature as your need
   f. other changes as your needed
3. cd /home/httpd/cgi-bin/openwebmail
   modify checkmail.pl openwebmail-prefs.pl openwebmail.pl spellcheck.pl
   a. change the '/usr/local/www/cgi-bin/openwebmail'
              to '/home/httpd/cgi-bin/openwebmail'
4. add 'Tnobody' to the 'Trusted users' session in your /etc/sendmail.cf
5. add
   /var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }  
   to /etc/logrotate.d/syslog to enable logrotate on openwebmail.log

ps: if you are using RedHat 7.1, please use /var/www instead of /home/httpd
    (by danguba@usa.net)

If you are upgrading from old openwebmail on Redhat 6.2/CLE 0.9p1

1. move original openwebmail dir (cgi-bin/openwebmail and html/openwebmail) 
    to different name (eg: something like openwebmail.old)
2. install the new version of openwebmail
3. migrate the old settings from openwebmail.old to openwebmail with
   uty/migrate.pl
4. delete the old original openwebmail dir (openwebmail.old)


If you are using other UNIX with apache, that is okay

Try to find the parent directory of both your data and cgi-bin directory,
eg: /usr/local/apache/share, then

1. cd /usr/local/apache/share
   tar -zxvBpf openwebmail-X.XX.tgz
   mv data/openwebmail htdocs/
   rmdir data
2. modify /usr/local/apache/share/cgi-bin/openwebmail/etc/openwebmail.conf 
   for your need
3. cd /usr/local/apache/share/cgi-bin/openwebmail
   modify openwebmail*.pl and checkmail.pl
   a. change the #!/usr/bin/perl to the location where your perl is.
   b. change the '/usr/local/www/cgi-bin/openwebmail'
              to '/usr/local/apache/share/cgi-bin/openwebmail'
4. add 'Tnobody' to the 'Trusted users' session in your sendmail.cf


FILTER SUPPORT
--------------
The mailfilter checks if messages in INBOX folder matches the filters rules 
defined by user. If matches, move/copy the message to the target folder.
If you move a message to the DELETE folder, which means deleting messages 
from a folder. If you use INBOX as the destination in a filter rule, 
any message matching this rule will be kept in the INBOX folder and 
other rules will be ignored.

Mail filtering is activated only in Open WebMail. It means messages 
will stay in the INBOX until user reads their mail with Open WebMail. 
So 'finger' or other mail status check utility may give you wrong 
information since they don't know about the filter.

A command tool 'checkmail.pl' can be used as finger replacement.
It does mail filtering before report mail status. 

Some fingerd allow you specify the name of finger program by -p option
(ex: fingerd on FreeBSD). By changing the parameter to fingerd in 
/etc/inetd.conf, users can get their mail status from remote host.


SPELL CHECK SUPPORT
-------------------
To enable the spell check in openwebmail, you have to install a spell check 
program and a perl module that interfaces with the program.

1. download ispell-3.1.20.tar.gz from 
   http://www.cs.ucla.edu/ficus-members/geoff/ispell.html and install it,
   or you can install binary from freebsd package or linux rpm

ps: if you are compiling ispell from source, you may enhance your ispell 
    by using a better dictionary source.
    a. download http://turtle.ee.ncku.edu.tw/openwebmail/download/contrib/words.gz
    b. gzip -d words.gz
    c. mkdir /usr/dict; cp words /usr/dict/words
    d. start to make your ispell by reading README

2. download Lingua-Ispell-0.07.tar.gz from CPAN, then
   tar -zxvf Lingua-Ispell-0.07.tar.gz
   cd Lingua-Ispell-0.07
   perl Makefile.PL; make; make install

3. check the openwebmail.conf to see if $spellcheck is pointed to the 
   ispell binary


GLOBAL ADDRESSBOOK and FILTERRULE
---------------------------------
Current support for global addressbook/filterrule is very limited.
The administrator has to make a copy of addressbook/filterbook to
the file specified by $global_addressbook/$global_filterbook by himself.

ps: An account may be created to maintain the global addressbook/filterbook, 
    for example: 'global'

    ln -s your_global_addressbook ~global/mail/.address.book
    ln -s your_global_filterbook  ~global/mail/.filter.book

    Please be sure that the global files are writeable by user 'global'
    and readable by others


SPEEDUP ENCODING/DECODING OF MIME ATTACHMENTS
---------------------------------------------
The encoding/decoding speed would be much faster if you install the 
MIME-Base64 module from CPAN with XS support

1. download MIME-Base64-2.12.tar.gz from CPAN 
2. install the tar file by reading MIME-Base64-2.12.readme


MIGRATE FROM NEOMAIL
--------------------
1. For get better compatibility with pine(an unix email reader)
   user folderdir is changed from ~/neomail to ~/mail
   folder saved_messages is changed to saved-messages
   folder sent_mail      is changed to sent-mail
   folder neomail_trash  is changed to mail-trash

ps: a script 'migrate.pl' is provided in uty/ for administer 
    to migrate user folders from neomail easily


ADD SUPPORT FOR NEW LANGUEAGE
-----------------------------
It is very simple to add support for your language into openwebmail

1. chooes an 2 character abbreviation for your language, eg: xy
2. cd cgi-bin/openwebmail/etc. 
   cp lang/en lang/xy
   cp -R templates/en templates/xy
3. translate file lang/xy and templates/xy/* from english to your language
4. add your language to @availablelanguages and %languagenames in 
   openwebmail.conf

ps: If you wish the translation is put into the next release of openwebmail,
    please submit it to me.


TEST
-----      
1. chdir to openwebmail cgi dir (eg: /usr/local/www/cgi-bin/openwebmail)
   and check the owner, group and permission of the following files

   ~/openwebmail.pl		- owner=root, group=mail, mode=4755
   ~/openwebmail-prefs.pl	- owner=root, group=mail, mode=4755
   ~/spellcheck.pl		- owner=root, group=mail, mode=4755
   ~/check.pl			- owner=root, group=mail, mode=4755
   ~/vacation.pl		- owner=root, group=mail, mode=0755
   ~/etc            	 	- owner=root, group=mail, mode=750
   ~/etc/sessions   	 	- owner=root, group=mail, mode=770
   ~etc/users      	 	- owner=root, group=mail, mode=770

   /var/log/openwebmail.conf	- owner=root, group=mail, mode=660

2. test your webmail with http://your_server/cgi-bin/openwebmail/openwebmail.pl

If there are any problem, please check the faq.txt.
The latest version of FAQ will be available at
http://turtle.ee.ncku.edu.tw/openwebmail/download/doc/faq.txt


TODO
----
Features that we would like to implement first...

1. web calendar
2. web disk
3. shared folder

Features that people may also be interested

1. LDAP support
2. maildir support
3. password change
4. online people sign in
5. log analyzer


06/20/2001

openwebmail@turtle.ee.ncku.edu.tw

