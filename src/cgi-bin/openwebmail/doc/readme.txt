
Open WeMail is a webmail system based on 
the Neomail version 1.14 from Ernie Miller. 

While the original neomail has a good user interface and many neat features, 
it suffers from slow response for big folder files and large memory usage. 

Open WebMail is targeted on dealing with very big mail folder 
files in a memory efficient way to make it the fastest webmail in the world. 
It also provides many features to help users to switch from Microsoft 
Outlook smoothly. 


FEATURES
---------
The enhanced feature over neomail 1.14 are

1.  faster folder access
2.  efficient messages movement
3.  smaller memory footprint
4.  additional message operation, like copy, delete, download
5.  graceful filelock
6.  full content search
7.  better MIME message display
8.  Draft folder support
9.  POP3 mail support
10. mail filter support
11. message count preview
12. 'confirm reading' support


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
   a. change the $passwdfile to '/etc/shadow'
   b. search all '/usr/local/www' and replace to '/home/httpd'
   c. change the $mailspooldir to '/var/spool/mail'
   d. change the $defaultsignature as your need
   e. other changes as your needed
3. cd /home/httpd/cgi-bin/openwebmail
   modify openwebmail*.pl and checkmail.pl
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

If you are upgrading from old openwebmail on Redhat 6.2/CLE 0.9p1

1. move original openwebmail dir (cgi-bin/openwebmail and html/openwebmail) 
    to different name (eg: something like openwebmail.old)
2. install the new version of openwebmail
3. migrate the old settings from openwebmail.old to openwebmail with
   uty/migrate.pl
4. delete the old original openwebmail dir (openwebmail.old)


If you are using other UNIX with apache, that is okay

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
defined by user. If matches, move/copy the message to the specific folder.
If you move a message to the DELETE folder, which means delete messages 
from a folder. If you use INBOX as the destination in a filter rule, 
the message will be kept in the INBOX folder and skip other rule.

Mail filtering is activated only in Open WebMail. It means messages 
will stay in the INBOX until user reads their mail with Open WebMail. 
So 'finger' or other mail status check utility may give you wrong 
information since they don't know about the filter.

A command tool 'checkmail.pl' can be used as finger replacement.
It does mail filtering before report mail status. 

Some fingerd allow you specify the name of finger program by -p option
(ex: fingerd on FreeBSD). By changing the parameter to fingerd in 
/etc/inetd.conf, users can get their mail status from remote host.


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

ps. a script 'migrate.pl' is provided in uty/ for administer 
    to migrate user folders from neomail easily


TEST
-----      
Test your webmail with http://your_server/cgi-bin/openwebmail/openwebmail.pl

If there are any problem, please check the faq.txt.


04/24/2001

Ebola@turtle.ee.ncku.edu.tw
eddie@turtle.ee.ncku.edu.tw
tung@turtle.ee.ncku.edu.tw

