
Date: 09/13/2003
Last Revision: 09/13/2003
Author:  Torsten Brumm
File: Mandrake-README.txt

------------------------------------------------------------------------------
          Installation Guide Openwebmail 2.1x under SuSE Linux 8.2
------------------------------------------------------------------------------


Why do i write this guidline?

I'm using Openwebmail since Version 1.6 under Redhat Linux,
but now i must switch my System to SuSE Linux and i got a lot of
trouble installing OWM under SuSE 8.2.
After reading a lot of newsgroups and many Sites found by Google
i had no success finding a guidline to make OWM running under SuSE :-(

Sure, this Document is written for me,
if i must install OWM next time on a SuSE Box ;-)
but hopefully, you can use it also for your System installation.


What do i need to install?

1. A SuSE Linux Box
2. Time
3. A lot of Coffee
4. Some Cigaretts (optional)
5. Openwebmail (openwebmail.org)
6. Needed Packages


1. Make sure your SuSE 8.2 is installed and configured correctly.
   Check all sendmail and Apache settings!

2. Take your wife/family out for a night or weekend

3. Make sure you have enough coffee at home !

4. No comment ;-)

5. Get Openwebmail from the official OWM Site
	wget http://openwebmail.org/openwebmail/download/current/openwebmail-current.tar.gz

6. Get optional  and required Components (needed by OWM)

	cd ~
	mkdir tmp
	cd tmp

	absolutly needed components

	CGI.pm-3.05.tar.gz        (required)
	MIME-Base64-3.01.tar.gz   (required)
	libnet-1.19.tar.gz        (required)
	Text-Iconv-1.2.tar.gz     (required)
	libiconv-1.9.1.tar.gz     (required if system doesn't support iconv)

	wget http://openwebmail.org/openwebmail/download/packages/CGI.pm-3.05.tar.gz
  	wget http://openwebmail.org/openwebmail/download/packages/MIME-Base64-3.01.tar.gz
  	wget http://openwebmail.org/openwebmail/download/packages/libnet-1.19.tar.gz
    	wget http://openwebmail.org/openwebmail/download/packages/Text-Iconv-1.2.tar.gz
  	wget http://openwebmail.org/openwebmail/download/packages/libiconv-1.9.1.tar.gz


	optional components

	CGI-SpeedyCGI-2.22.tar.gz (optional)
	Compress-Zlib-1.33.tar.gz (optional)
	Quota-1.4.10.tar.gz       (optional)
	ispell-3.1.20.tar.gz      (optional)
	Authen-PAM-0.14.tar.gz    (optional)

  	wget http://openwebmail.org/openwebmail/download/packages/CGI-SpeedyCGI-2.22.tar.gz
  	wget http://openwebmail.org/openwebmail/download/packages/Compress-Zlib-1.33.tar.gz
  	wget http://openwebmail.org/openwebmail/download/packages/Quota-1.4.10.tar.gz
  	wget http://openwebmail.org/openwebmail/download/packages/Convert-ASN1-0.18.tar.gz
  	wget http://openwebmail.org/openwebmail/download/packages/ispell-3.1.20.tar.gz
 	wget http://openwebmail.org/openwebmail/download/packages/Authen-PAM-0.14.tar.gz

   Not all are needed, but download it, its possible that you need it later... who knows ???


INSTALLATION

1. untar all files

	1.1 needed Modules


  	tar -zxvBpf ~/tmp/CGI.pm-3.05.tar.gz
  	tar -zxvBpf ~/tmp/MIME-Base64-3.01.tar.gz
  	tar -zxvBpf ~/tmp/libnet-1.19.tar.gz
  	tar -zxvBpf ~/tmp/Text-Iconv-1.2.tar.gz
  	tar -zxvBpf ~/tmp/libiconv-1.9.1.tar.gz
  	tar -zxvBpf ~/tmp/CGI-SpeedyCGI-2.22.tar.gz
  	tar -zxvBpf ~/tmp/Compress-Zlib-1.33.tar.gz
  	tar -zxvBpf ~/tmp/Quota-1.4.10.tar.gz
  	tar -zxvBpf ~/tmp/Convert-ASN1-0.18.tar.gz
	tar -zxvBpf ~/tmp/Authen-PAM-0.14.tar.gz

  	1.2 Openwebmail Programm

  	tar -zxvBpf ~/tmp/openwebmail-current.tar.gz

 2. compile all modules

 	switch to each created subdir and type:
 		perl Makefile.PL
 		make
 		make install


 	some special questions during installation:

 	For libnet do the following:

		perl Makefile.PL (ans 'no' if asked to update configuration)
   		make
   		make install

3. Special environment settings:
	- check the permissions of your suidperl binary (/usr/bin/suidperl)
	- change the permissions if needed (chmod 4555 /usr/bin/suidperl)

4. Installation of OWM

In step 1.2. we have untared the OWM programm to ~/tmp,
now its time to move the programm to its right location.

Under SuSE the default apache document dir is under /srv/www
not like Redhat (/var/www) or BSD (/usr/local/www)
so we must move the cgi-bin/openwebmail to /srv/www/cgi-bin and
the data/openwebmail to /srv/www/htdocs/ !

	mv ~/tmp/cgi-bin/openwebmail /srv/www/cgi-bin
	mv ~/tmp/data/openwebmail /srv/www/htdocs/

File & Folder Permissions:

Under SuSE the owner of the www dir is root,
so user and group root must be set for folder permissions! For all
Files is absolutly needed to set the rights to user root and group mail.

	chown root.root /srv/www/cgi-bin/openwebmail
	chown root.mail /srv/www/cgi-bin/openwebmail/*

Check the Filepermisiions for SUIDPERL:

Each file of /srv/www/cgi-bin/openwebmail with openwebmail*.pl
must be set to: 4555 owned by root.mail

	chmod 4555 /srv/www/cgi-bin/openwebmail/openwebmail*.pl
	chown root.mail /srv/www/cgi-bin/openwebmail/openwebmail*.pl

(better double check!!!!)

Thats it !!!! -> Now start configuring:


5. Configuring Openwebmail

	5.1. check and change setting of
	     /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf

	domainnames             auto
	auth_module             auth_unix.pl
	mailspooldir            /var/mail
	ow_cgidir               /srv/www/cgi-bin/openwebmail
	ow_cgiurl               /cgi-bin/openwebmail
	ow_htmldir              /srv/www/htdocs/openwebmail
	ow_htmlurl              /openwebmail
	logfile                 /var/log/openwebmail.log
	spellcheck              /usr/bin/aspell

	These are the settings working well for me !

        5.2. check and change setting of
             /srv/www/cgi-bin/openwebmail/etc/dbm.conf

	dbm_ext                 .pag
	dbmopen_ext             none
	dbmopen_haslock         no

	5.3. check and change settings of
	     /srv/www/cgi-bin/openwebmail/etc/auth_unix.conf

	passwdfile_plaintext	/etc/passwd
	passwdfile_encrypted	/etc/shadow
	passwdmkdb		none
	check_nologin           no
	check_shell             no
	check_cobaltuser        no

	These are the settings working well for me under SuSE!

	5.3. Initialising Openwebmail

	/srv/www/cgi-bin/openwebmail/openwebmail-tool --init

	This Script is setting up openwebmail and generating some files,
	if this work without errors, you won!

6. Starting Openwebmail

	Now its time to start the first time. Point your preferred Browser to:

	http://your.server.com/cgi-bin/openwebmail/openwebmail.pl

	Now the OWM Login Screen will be viewed.
	If not, check on the documentation for troubleshooting.


7. What comes next?

	If i find the time, i will write a installation script to
	make the installation easier!

