
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
10.  draft folder support
11. spelling check support
12. POP3 mail support
13. mail filter support
14. message count preview
15. confirm reading support
16. BIG5/GB convertion (for chinese only)


REQUIREMENT
-----------
Apache web server with cgi enabled
Perl 5.005 or above
Ispell package (ispell-3.1.20.tar.gz)


INSTALL
-------
First, please connect to http://turtle.ee.ncku.edu.tw/openwebmail/ to
get the latest released openwebmail.

If you are using FreeBSD and install apache with packages,
then just

1. cd /usr/local/www
   tar -zxvBpf openwebmail-X.XX.tgz
2. modify /usr/local/www/cgi-bin/openwebmail/etc/openwebmail.conf for your need.
3. add 'Tnobody' to the 'Trusted users' session in your sendmail.cf


If you are using RedHat 6.2/CLE 0.9p1(or most Linux) with apache
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
    (by elitric@hotmail.com)

If you are upgrading from old openwebmail on RedHat 6.2/CLE 0.9p1

1. move original openwebmail dir (cgi-bin/openwebmail and html/openwebmail) 
    to different name (eg: something like openwebmail.old)
2. install the new version of openwebmail
3. migrate the old settings from openwebmail.old to openwebmail with
   uty/migrate.pl
4. delete the old original openwebmail dir (openwebmail.old)

ps: It is highly recommended to read the doc/RedHat-README.txt(contributed by 
    elitric@hotmail.com) if you are installing Open WebMail on RedHat Linux.


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


SPEEDUP ENCODING/DECODING OF MIME ATTACHMENTS
---------------------------------------------
The encoding/decoding speed would be much faster if you install the 
MIME-Base64 module from CPAN with XS support

1. download MIME-Base64-2.12.tar.gz from CPAN 
2. install the tar file by reading MIME-Base64-2.12.readme


SPELL CHECK SUPPORT
-------------------
To enable the spell check in openwebmail, you have to install a spell check 
program and a perl module that interfaces with the program.

1. download ispell-3.1.20.tar.gz from 
   http://www.cs.ucla.edu/ficus-members/geoff/ispell.html and install it,
   or you can install binary from FreeBSD package or Linux rpm

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


PAM SUPPORT
-----------
PAM (Pluggable Authentication Modules) provides a flexible mechanism 
for authenticating users. More detail is available at Linux-PAM webpage.
http://www.kernel.org/pub/linux/libs/pam/ 

Solaris 2.6, Linux and FreeBSD 3.1 are known to support PAM.
To make Open WebMail use the support of PAM, you have to install the 
Perl Authen::PAM module. It is available at 
http://www.cs.kuleuven.ac.be/~pelov/pam/

ps: Doing 'make test' is recommended when making the Authen::PAM,
    if you encounter error in 'make test', the PAM on your system
    will probablely not work.

Then you have to add the following 2 lines to your /etc/pam.conf 

(on FreeBSD)
openwebmail auth    required    pam_unix.so         try_first_pass
openwebmail account required    pam_unix.so         try_first_pass

(on Linux)
openwebmail auth    required    /lib/security/pam_unix.so                                                                            
openwebmail account required    /lib/security/pam_unix.so                                                                            

Finally, change $use_pam to 'yes' in the openwebmail.conf

ps: It is recommended to reference the PAM webpage for Neomail by 
    Peter Sinoros Szabo, sini@fazekas.hu
    http://www.fazekas.hu/~sini/neomail_pam/


AUTOREPLY SUPPORT
-----------------
The auto reply function in Open WebMail is done with the vacation utility.
Since vacation utility is not available on some unix, a perl version of
vacation utility 'vacation.pl' is distributed with openwebmail.
This vacation.pl has the same syntax as the one on Solaris.
To make it work properly, be sure to modify $myname, $sendmail definition
in the vacation.pl.


FILTER SUPPORT
--------------
The mailfilter checks if messages in INBOX folder matches the filters rules 
defined by user. If matches, move/copy the message to the target folder.
If you move a message to the DELETE folder, which means deleting messages 
from a folder. If you use INBOX as the destination in a filter rule, 
any message matching this rule will be kept in the INBOX folder and 
other rules will be ignored.


BIG5<->GB CONVERSION
--------------------
Openwebmail supports chinese charset conversion between Big5 encoding
(used in taiwan, hongkong) and GB encoding(used in mainland) in both message 
reading and writing.
To make the conversion work properly, you have to 

1. download the Hanzi Converter hc-30.tar.gz 
   by Ricky Yeung(Ricky.Yeung@eng.sun.com) and 
      Fung F. Lee (lee@umunhum.stanford.edu).
2. tar -zxvf hc-30.tar.gz
   cd hc-30
   make
3. copy 'hc' and 'hc.tab' to cgi-bin/openwebmail or /usr/local/bin
4. modify the openwebmail.conf $g2b_converter and $b2g_converter.


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
the file specified by $global_addressbook/$global_filterbook by himself.

ps: An account may be created to maintain the global addressbook/filterbook, 
    for example: 'global'

    ln -s your_global_addressbook ~global/mail/.address.book
    ln -s your_global_filterbook  ~global/mail/.filter.book

    Please be sure that the global files are writeable by user 'global'
    and readable by others


ADD SUPPORT FOR NEW LANGUAGE
-----------------------------
It is very simple to add support for your language into openwebmail

1. choose an 2 character abbreviation for your language, eg: xy
2. cd cgi-bin/openwebmail/etc. 
   cp lang/en lang/xy
   cp -R templates/en templates/xy
3. translate file lang/xy and templates/xy/* from English to your language
4. add your language to %languagenames in openwebmail.conf

ps: If you wish the translation to be included in the next release of 
    openwebmail, please submit it to openwebmail@turtle.ee.ncku.edu.tw.


DESIGN YOUR OWN IMAGESET IN OPENWEBMAIL
---------------------------------------
If you are interested in designing your own image set in the openwebmail,
you have to

1. create a new sub directory in the $imagedir (which is defined in 
   openwebmail.conf) ex: MyImageSet
2. copy all images from $imagedir/Default to $imagedir/MyImageSet
3. modify the image files in the $imagedir/MyImageSet for your need
4. If you wish the new imageset to be included in the next release of 
   openwebmail, please submit it to openwebmail@turtle.ee.ncku.edu.tw


TEST
-----      
1. chdir to openwebmail cgi dir (eg: /usr/local/www/cgi-bin/openwebmail)
   and check the owner, group and permission of the following files

   ~/openwebmail.pl		- owner=root, group=mail, mode=4755
   ~/openwebmail-prefs.pl	- owner=root, group=mail, mode=4755
   ~/spellcheck.pl		- owner=root, group=mail, mode=4755
   ~/checkmail.pl		- owner=root, group=mail, mode=4755
   ~/vacation.pl		- owner=root, group=mail, mode=0755
   ~/etc            	 	- owner=root, group=mail, mode=750
   ~/etc/sessions   	 	- owner=root, group=mail, mode=770
   ~/etc/users      	 	- owner=root, group=mail, mode=770

   /var/log/openwebmail.log	- owner=root, group=mail, mode=660

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

Features that people may also be interested

1. maildir support
2. online people sign in
3. log analyzer


08/16/2001

openwebmail@turtle.ee.ncku.edu.tw

