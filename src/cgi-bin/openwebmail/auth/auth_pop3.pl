package ow::auth_pop3;
use strict;
#
# auth_pop3.pl - authenticate user with POP3 server
#
# 2002/03/08 tung.AT.turtle.ee.ncku.edu.tw
#

########## No configuration required from here ###################

use IO::Socket;
use MIME::Base64;
require "modules/tool.pl";

my %conf;
if (($_=ow::tool::find_configfile('etc/auth_pop3.conf', 'etc/auth_pop3.conf.default')) ne '') {
   my ($ret, $err)=ow::tool::load_configfile($_, \%conf);
   die $err if ($ret<0);
} else {
   die "Config file auth_pop3.conf not found";
}

# global vars, the uid used for all pop3 users mails
# you may set it to uid of specific user, eg: $local_uid=getpwnam('nobody');
use vars qw($local_uid);
if ($conf{'effectiveuser'} ne '') {
   $local_uid=getpwnam($conf{'effectiveuser'});
} else {
   $local_uid=$>;	# use same euid as openwebmail euid
}

########## end init ##############################################

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
