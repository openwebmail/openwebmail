
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

1. folder access speedup with dbm
2. efficient movement of messages
3. more graceful filelock
4. full content search with regular expression support
5. much better support for mime message display
6. POP3 mail support
7. mail filter support
8. message count preview
9. 'confirm reading' support


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


If you are using Redhat 6.2/CLE 0.9p1 with apache(or most Linux system),

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
3. cd /home/httpd/cgi-bin/openwebmail
   modify openwebmail*.pl and checkmail.pl
   a. change the '/usr/local/www/cgi-bin/openwebmail'
      to '/home/httpd/cgi-bin/openwebmail'
4. add 'Tnobody' to the 'Trusted users' session in your /etc/sendmail.cf


If you are using other UNIX with apache, that is okay

1. cd /usr/local/apache/share
   tar -zxvBpf openwebmail-X.XX.tgz
   mv data/openwebmail htdocs/
   rmdir data
2. modify /usr/local/apache/share/cgi-bin/openwebmail/etc/openwebmail.conf 
   for your need
3. cd /usr/local/apache/share/cgi-bin/openwebmail
   modify openwebmail*.pl and checkmail.pl
   a. change the #!/usr/bin/perl to the location your perl is.
   b. change the '/usr/local/www/cgi-bin/openwebmail'
      to '/usr/local/apache/share/cgi-bin/openwebmail'
4. add 'Tnobody' to the 'Trusted users' session in your sendmail.cf


FILTER SUPPORT
--------------
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

ps: an account may be created for the maintainance of global 
    addressbook/filterbook, for example: 'global'

    ln -s your_global_addressbook ~global/mail/.address.book
    ln -s your_global_filterbook  ~global/mail/.filter.book

    Please be sure that the global files are writeable by user 'global'
    and readable by others


SPEEDUP ENCODING/DECODING OF MIME ATTACHMENTS
---------------------------------------------
The encoding/decoding speed would be much faster if you install thr 
MIME-Base64 module from CPAN with XS support

1. download MIME-Base64-2.12.tar.gz from CPAN 
2. install the tar file by reading MIME-Base64-2.12.readme


MIGRATE FROM NEOMAIL
--------------------
1. For get better compatiability with pine(an unix email reader)
   user folderdir is changed from ~/neomail to ~/mail
   folder saved_messages is changed to saved-messages
   folder sent_mail      is changed to sent-mail
   folder neomail_trash  is changed to mail-trash

ps. a script 'migrate.pl' is provided in uty/ for administor 
    to migrate user folders from neomail easily


TEST
-----      
test your webmail with http://your_server/cgi-bin/openwebmail/openwebmail.pl


04/12/2001

Ebola@turtle.ee.ncku.edu.tw
eddie@turtle.ee.ncku.edu.tw
tung@turtle.ee.ncku.edu.tw

