#
# auth_pop3.pl - authenticate user with POP3 server
#
# 2002/03/08 tung@turtle.ee.ncku.edu.tw
#

#
# This module assumes that
#
#   a. users are located on remote pop3 server, or
#   b. users are virtual users on this machine
#
# so it uses the same uid for all openwebmail users on the local machine.
#
# You have to do the following things to make the whole system work
#
# 1. decide the user openwebmail runtime to be executed as.
#
#    a. if you have root permission on this machine.
#       1> install openwebmail as readme.txt described
#       2> cd cgi-bin/openwebmail
#       3> chmod u-s *pl to remove setuid bit from scripts
#       4> chown -R nobody.nobody ./etc
#       Then the openwebmail runtime user will be the same as your web server,
#       normally 'nobody'
#
#    b. if you have root permission on this machine.
#       1> install openwebmail as readme.txt described
#       2> cd cgi-bin/openwebmail
#       3> change the $local_uid in this script
#       Then the openwebmail runtime user will be the $local_uid
#
#    c. if you don't have root permission on this machine
#       1> create an user for the openwebmail runtime, ex: owmail
#          login as owmail
#       2> mkdir public_html; cd public_html
#       3> tar -zxvBpf openwebmail-x.yy.tgz
#       4> cd cgi-bin/openwebmail
#       5> chmod u-s *pl to remove setuid bit from scripts
#       6> make the *.pl to be executed by user 'owmail'
#       ps: You may need to reference the manpage/document of your httpd to
#           know how to do user specific CGI
#       The openwebmail runtime user will be 'owmail'
#
# 2. set the following options in openwebmail.conf
#
#    auth_module		auth_pop3.pl
#    mailspooldir		any directory that the runtime user could write
#    use_homedirspools		no
#    use_homedirfolders		no
#    log_file			any file that runtime user could write
#    enable_changepwd		no
#    enable_autoreply		no
#    enable_setforward		no
#    getmail_from_pop3_authserver	yes
#
# 3. if your users are not on remote server but virtual users on this machine
#    (eg: you use vm-pop3d on this machine for authentication)
#
#    a. you need to install openwebmail as described in step 1.b or 1.c
#       and the user must be the same as the vm-pop3d is.
#    b. replace the following two options in step 2
#
#       mailspooldir			the mailspool used by vmpop3d
#       getmail_from_pop3_authserver	no
#
# $pop3_authserver: the server used to authenticate pop3 user
# $pop3_authport: the port which pop3 server is listening to
# $local_uid: uid used on this machine
#

# global vars, also used by openwebmail.pl
use vars qw($pop3_authserver $pop3_authport $local_uid);

$pop3_authserver="localhost";
$pop3_authport='110';
$local_uid=$>;

################### No configuration required from here ###################

# routines get_userinfo() and get_userlist still depend on /etc/passwd
# you may have to write your own routines if your user are not form /etc/passwd

use strict;
use FileHandle;
use IO::Socket;
require "mime.pl";

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $homedir) = (getpwuid($local_uid))[2,3,6,7];

   # use first field only
   $realname=(split(/,/, $realname))[0];
   # guess real homedir under sun's automounter
   if ($uid) {
      $homedir="/export$homedir" if (-d "/export$homedir");
   }
   return($realname, $uid, $gid, $homedir);
}


sub get_userlist {	# only used by openwebmail-tool.pl -a
   return();		# not supported, return empty
}


#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($user, $password)=@_;
   my $remote_sock;

   return -2 if ($user eq "");

   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 10;
      $remote_sock=new IO::Socket::INET(   Proto=>'tcp',
                                           PeerAddr=>$pop3_authserver,
                                           PeerPort=>$pop3_authport,);
      alarm 0;
   };
   return -3 if ($@);			# eval error, it means timeout
   return -3 if (!$remote_sock);	# connect error

   $remote_sock->autoflush(1);
   $_=<$remote_sock>;
   (close($remote_sock) && return -3) if (/^\-/);	# server not ready

   # try if server supports auth login(base64 encoding) first
   print $remote_sock "auth login\r\n";
   $_=<$remote_sock>;
   if (/^\+/) {
      print $remote_sock &encode_base64($user);
      $_=<$remote_sock>;
      (close($remote_sock) && return -2) if (/^\-/);		# username error
      print $remote_sock &encode_base64($password);
      $_=<$remote_sock>;
   }
   if (! /^\+/) {	# not supporting auth login or auth login failed
      print $remote_sock "user $user\r\n";
      $_=<$remote_sock>;
      (close($remote_sock) && return -2) if (/^\-/);		# username error
      print $remote_sock "pass $password\r\n";
      $_=<$remote_sock>;
      (close($remote_sock) && return -4) if (/^\-/);		# passwd error
   }

   print $remote_sock "quit\r\n";
   close($remote_sock);

   return 0;
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($user, $oldpassword, $newpassword)=@_;

   return -2 if ($user eq "");
   return -1;			# not supported
}

1;
