#!/bin/sh
# Install OWM under SuSE Script Version 0.01
#
# This script is written by torsten brumm for easier installation of owm under suse linux
# You can use this script at your own risk!
#
# If you have any questions or problems, feel free to contact me tob@brummi.dyn.ee
# At this moment this script is in an very early version, without any error solutions
# but if i find the time, i will beautify this script
#
# If you have any suggestions or hints, feel free to contact me: ich.AT.torsten-brumm.de
# or visit my homepage under www.torsten-brumm.de
#
#
#########################################################################################

echo '#########################################################'
echo '# This is the very first version of this script, please #'
echo '# keep in mind, you use this script at your own risk!   #'
echo '# If you have any questions, feel free to contact me!   #'
echo '#########################################################'

#########################################################################################
#
# Setting tmp directory and creating a owm dir in /tmp
#
#########################################################################################

cd ~
mkdir tmp
mkdir ~/tmp/owm
cd ~/tmp/owm
OWM_TMP=~/tmp/owm

#########################################################################################
#
# downloading required components
#
#########################################################################################

clear
echo '#########################################'
echo '# start downloading required components #'
echo '#########################################'

wget http://openwebmail.com/openwebmail/download/openwebmail-current.tgz
wget http://openwebmail.com/openwebmail/download/packages/CGI.pm-2.74.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/MIME-Base64-2.12.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/libnet-1.0901.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/Text-Iconv-1.2.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/libiconv-1.8.tar.gz

sleep 5

#########################################################################################
#
# downloading optional components
#
#########################################################################################

clear
echo '#########################################'
echo '# start downloading optional components #'
echo '#########################################'

wget http://openwebmail.com/openwebmail/download/packages/Authen-PAM-0.12.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/CGI-SpeedyCGI-2.21.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/Compress-Zlib-1.21.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/Quota-1.4.6.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/Convert-ASN1-0.07.tar.gz
wget http://openwebmail.com/openwebmail/download/packages/ispell-3.1.20.tar.gz

sleep 5

#########################################################################################
#
# untar all files
#
#########################################################################################

clear

echo '#########################################'
echo '# untaring all files                    #'
echo '#########################################'
cd $OWM_TMP

for i in *.gz; do
tar -zxvf $i
done

tar -zxvBpf openwebmail-current.tgz

##########################################################################################
#
# Cleanup tar files
#
##########################################################################################

rm -f $OWM_TMP/*.gz
rm -f $OWM_TMP/*.tgz

##########################################################################################
#
# Installation of Components
#
##########################################################################################

clear

echo '###################################'
echo '# Installation of Authen-PAM-0.12 #'
echo '###################################'

cd $OWM_TMP/Authen-PAM-0.12
perl Makefile.PL
make
make install

clear

echo '#####################################'
echo '# Installation of CGI-SpeedyCGI-2.2 #'
echo '#####################################'

cd $OWM_TMP/CGI-SpeedyCGI-2.21
perl Makefile.PL
make
make install

clear

echo '###############################'
echo '# Installation of CGI.pm-2.74 #'
echo '###############################'

cd $OWM_TMP/CGI.pm-2.74
perl Makefile.PL
make
make install

clear

echo '######################################'
echo '# Installation of Compress-Zlib-1.21 #'
echo '######################################'

cd $OWM_TMP/Compress-Zlib-1.21
perl Makefile.PL
make
make install

clear

echo '#####################################'
echo '# Installation of Convert-ASN1-0.07 #'
echo '#####################################'

cd $OWM_TMP/Convert-ASN1-0.07
perl Makefile.PL
make
make install

clear

echo '####################################'
echo '# Installation of MIME-Base64-2.12 #'
echo '####################################'

cd $OWM_TMP/MIME-Base64-2.12
perl Makefile.PL
make
make install

clear

echo '###############################'
echo '# Installation of Quota-1.4.6 #'
echo '###############################'

cd $OWM_TMP/Quota-1.4.6
perl Makefile.PL
make
make install

clear

echo '###################################'
echo '# Installation of Text-Iconv-1.2  #'
echo '###################################'

cd $OWM_TMP/Text-Iconv-1.2
perl Makefile.PL
make
make install

clear

echo '#############################################'
echo '# Installation of libnet-1.0901             #'
echo '# ans 'no' if asked to update configuration #'
echo '#############################################'
cd $OWM_TMP/libnet-1.0901
perl Makefile.PL
make
make install

##########################################################################################
#
# Installation of Openwebmail
#
##########################################################################################

echo '###############################'
echo '# Installation of Openwebmail #'
echo '###############################'

mv $OWM_TMP/data/openwebmail /srv/www/htdocs
mv $OWM_TMP/cgi-bin/openwebmail /srv/www/cgi-bin

chown root.root /srv/www/cgi-bin/openwebmail
chown -R root.root /srv/www/htdocs/openwebmail
chown root.mail /srv/www/cgi-bin/openwebmail/*

chmod 4555 /srv/www/cgi-bin/openwebmail/openwebmail*.pl
chown root.mail /srv/www/cgi-bin/openwebmail/openwebmail*.pl

echo '##################################################'
echo '# suidperl is placed in the following directory: #'
echo '##################################################'

ls -la $(which suidperl)

echo '#####################################################'
echo '# it will be set to 4555 for propper working of OWM #'
echo '#####################################################'

chmod 4555 $(which suidperl)

##########################################################################################
#
# Changing OWM Configuration
#
# In the following step the /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf and also
# the /srv/www/cgi-bin/auth_unix.pl must be changed to get OWM work propperly
#
##########################################################################################

rm -f /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf

echo "#" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "# Open WebMail configuration file" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "#" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "# This file contains just the overrides from openwebmail.conf.default" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "# please make all changes to this file." >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "#" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "# This file sets options for all domains and all users." >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "# To set options on per domain basis, please put them in sites.conf/domainname" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "# To set options on per user basis, please put them in users.conf/username" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "#" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "domainnames             auto" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "auth_module             auth_unix.pl" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "mailspooldir            /var/mail" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "dbm_ext                 .pag" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "dbmopen_ext             none" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "dbmopen_haslock         no" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "ow_cgidir               /srv/www/cgi-bin/openwebmail" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "ow_cgiurl               /cgi-bin/openwebmail" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "ow_htmldir              /srv/www/htdocs/openwebmail" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "ow_htmlurl              /openwebmail" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "logfile                 /var/log/openwebmail.log" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "spellcheck              /usr/bin/aspell" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "<default_signature>" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "-- " >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "Open WebMail Project (http://openwebmail.org)" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf
echo "</default_signature>" >> /srv/www/cgi-bin/openwebmail/etc/openwebmail.conf

cd /srv/www/cgi-bin/openwebmail/
mv auth_unix.pl auth_unix.pl.orig
head -39 auth_unix.pl.orig > auth_unix.pl
echo 'my $unix_passwdfile_plaintext="/etc/passwd";' >> auth_unix.pl
echo 'my $unix_passwdfile_encrypted="/etc/shadow";' >> auth_unix.pl
echo 'my $unix_passwdmkdb="";' >> auth_unix.pl
echo 'my $check_shell=0;' >> auth_unix.pl
echo '' >> auth_unix.pl
tail -232 auth_unix.pl.orig >> auth_unix.pl
chown root.mail auth_unix.pl

sleep 5
clear

##########################################################################################
#
# initialising owm
#
##########################################################################################

echo '#########################################'
echo '# Initialising OWM for this system      #'
echo '#########################################'

/srv/www/cgi-bin/openwebmail/openwebmail-tool.pl --init

sleep 5

##########################################################################################
#
# and now its time to start owm for the first time
#
##########################################################################################

clear

echo '#########################################'
echo '# Starting OWM in text Browser for Test #'
echo '#########################################'
/etc/init.d/apache restart
links $(hostname -f)/cgi-bin/openwebmail/openwebmail.pl

##########################################################################################
#
# Done, if you have no errors!
#
##########################################################################################

echo '#########################################'
echo '# If you can login, then it works :-)   #'
echo '#########################################'

