package openwebmail::auth_pop3;
use strict;
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
#    use_syshomedir		no
#    use_homedirspools		no
#    logfile			any file that runtime user could write
#    enable_changepwd		no
#    enable_autoreply		no
#    enable_setforward		no
#    pop3_authserver		pop3 server for authentication (default:localhost)
#    pop3_authport		110
#    getmail_from_pop3_authserver	yes
#
# 3. if your users are not on remote server but virtual users on this machine
#    (eg: you use vm-pop3d on this machine for authentication)
#
#    a. you need to install openwebmail as described in step 1.b or 1.c
#       and the user must be the same as the vm-pop3d.
#    b. replace the following two options in step 2
#
#       mailspooldir			the mailspool used by vmpop3d
#       getmail_from_pop3_authserver	no
#
# $local_uid: uid used on this machine
#

# global vars, the uid used for all pop3 users mails
# you may set it to uid of specific user, eg: $local_uid=getpwnam('nobody');
use vars qw($local_uid);
$local_uid=$>;

################### No configuration required from here ###################

use IO::Socket;
use MIME::Base64;

# routines get_userinfo() and get_userlist still depend on /etc/passwd
# you may have to write your own routines if your user are not form /etc/passwd

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : user doesn't exist
sub get_userinfo {
   my ($r_config, $user)=@_;
   return(-2, 'User is null') if (!$user);

   my ($localuser, $uid, $gid, $realname, $homedir) = (getpwuid($local_uid))[0,2,3,6,7];
   return(-4, "User $user doesn't exist") if ($uid eq "");

   # get other gid for this localuser in /etc/group
   while (my @gr=getgrent()) {
      $gid.=' '.$gr[2] if ($gr[3]=~/\b$localuser\b/ && $gid!~/\b$gr[2]\b/);
   }
   # use first field only
   $realname=(split(/,/, $realname))[0];
   # guess real homedir under sun's automounter
   $homedir="/export$homedir" if (-d "/export$homedir");

   return(0, '', $realname, $uid, $gid, $homedir);
}


#  0 : ok
# -1 : function not supported
# -3 : authentication system/internal error
sub get_userlist {	# only used by openwebmail-tool.pl -a
   my $r_config=$_[0];
   return(-1, "userlist() is not available in auth_pop3.pl");
}


#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($r_config, $user, $password)=@_;
   return (-2, "User or password is null") if (!$user||!$password);

   my $remote_sock;
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 30;
      $remote_sock=new IO::Socket::INET(   Proto=>'tcp',
                                           PeerAddr=>${$r_config}{'pop3_authserver'},
                                           PeerPort=>${$r_config}{'pop3_authport'});
      alarm 0;
   };
   if ($@){ 			# eval error, it means timeout
      return (-3, "pop3 server ${$r_config}{'pop3_authserver'}:${$r_config}{'pop3_authport'} timeout");
   }
   if (!$remote_sock) { 	# connect error
      return (-3, "pop3 server ${$r_config}{'pop3_authserver'}:${$r_config}{'pop3_authport'} connection refused");
   }

   $remote_sock->autoflush(1);
   $_=<$remote_sock>;
   if (/^\-/) {
      close($remote_sock);
      return(-3, "pop3 server ${$r_config}{'pop3_authserver'}:${$r_config}{'pop3_authport'} not ready");
   }

   # try if server supports auth login(base64 encoding) first
   print $remote_sock "auth login\r\n";
   $_=<$remote_sock>;
   if (/^\+/) {
      print $remote_sock &encode_base64($user);
      $_=<$remote_sock>;
      if (/^\-/) {
         close($remote_sock);
         return(-2, "pop3 server ${$r_config}{'pop3_authserver'}:${$r_config}{'pop3_authport'} username error");
      }
      print $remote_sock &encode_base64($password);
      $_=<$remote_sock>;
   }
   if (! /^\+/) {	# not supporting auth login or auth login failed
      print $remote_sock "user $user\r\n";
      $_=<$remote_sock>;
      if (/^\-/) {		# username error
         close($remote_sock);
         return(-2, "pop3 server ${$r_config}{'pop3_authserver'}:${$r_config}{'pop3_authport'} username error");
      }
      print $remote_sock "pass $password\r\n";
      $_=<$remote_sock>;
      if (/^\-/) {		# passwd error
         close($remote_sock);
         return(-4, "pop3 server ${$r_config}{'pop3_authserver'}:${$r_config}{'pop3_authport'} password error");
      }
   }

   print $remote_sock "quit\r\n";
   close($remote_sock);

   return (0, "");
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($r_config, $user, $oldpassword, $newpassword)=@_;
   return (-2, "User or password is null") if (!$user||!$oldpassword||!$newpassword);
   return (-1, "change_password() is not available in authpop3.pl");
}

1;
