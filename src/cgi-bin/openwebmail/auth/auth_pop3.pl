package ow::auth_pop3;
#
# auth_pop3.pl - authenticate user with POP3 server
#
# 2002/03/08 tung.AT.turtle.ee.ncku.edu.tw
#

########## No configuration required from here ###################

use strict;
use IO::Socket;
use MIME::Base64;
require "modules/tool.pl";

my %conf;
if (($_=ow::tool::find_configfile('etc/auth_pop3.conf', 'etc/defaults/auth_pop3.conf')) ne '') {
   my ($ret, $err)=ow::tool::load_configfile($_, \%conf);
   die $err if ($ret<0);
}

my $effectiveuser= $conf{'effectiveuser'} || 'nobody';

########## end init ##############################################

# routines get_userinfo() and get_userlist still depend on /etc/passwd
# you may have to write your own routines if your user are not form /etc/passwd

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : user doesn't exist
sub get_userinfo {
   my ($r_config, $user)=@_;
   return(-2, 'User is null') if ($user eq '');

   my ($uid, $gid, $realname, $homedir) = (getpwnam($effectiveuser))[2,3,6,7];
   return(-4, "User $user doesn't exist") if ($uid eq "");

   # get other gid for this effective in /etc/group
   while (my @gr=getgrent()) {
      $gid.=' '.$gr[2] if ($gr[3]=~/\b$effectiveuser\b/ && $gid!~/\b$gr[2]\b/);
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
   return (-2, "User or password is null") if ($user eq '' || $password eq '');

   my ($server, $port, $usessl)=(ow::tool::untaint(${$r_config}{'authpop3_server'}),
                                 ow::tool::untaint(${$r_config}{'authpop3_port'}),
                                 ${$r_config}{'authpop3_usessl'});

   my $socket;
   eval {
      alarm 30; local $SIG{ALRM}= sub {die "alarm\n"};
      if ($usessl && ow::tool::has_module('IO/Socket/SSL.pm')) {
         $socket=new IO::Socket::SSL (PeerAddr=>$server, PeerPort=>$port, Proto=>'tcp',);
      } else {
         $port=110 if ($usessl && $port==995);
         $socket=new IO::Socket::INET (PeerAddr=>$server, PeerPort=>$port, Proto=>'tcp',);
      }
      alarm 0;
   };
   return (-3, "pop3 server $server:$port connect error") if ($@ or !$socket); # timeout or refused
   eval {
      alarm 10; local $SIG{ALRM}= sub {die "alarm\n"};
      $socket->autoflush(1);
      $_=<$socket>;
      alarm 0;
   };
   return (-3, "pop3 server $server:$port server not ready") if ($@ or /^\-/);	# timeout or server not ready

   my @result;
   # try auth login first
   if (sendcmd($socket, "auth login\r\n", \@result) &&
       sendcmd($socket, &encode_base64($user), \@result) &&
       sendcmd($socket, &encode_base64($password), \@result)) {
      sendcmd($socket, "quit\r\n", \@result); close($socket);
      return (0, '');
   }
   # try normal login
   if (sendcmd($socket, "user $user\r\n", \@result) &&
       sendcmd($socket, "pass $password\r\n", \@result)) {
      sendcmd($socket, "quit\r\n", \@result); close($socket);
      return (0, '');
   }

   sendcmd($socket, "quit\r\n", \@result); close($socket);
   return(-4, "pop3 server $server:$port bad login");
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($r_config, $user, $oldpassword, $newpassword)=@_;
   return (-2, "User or password is null") if ($user eq '' || $oldpassword eq '' || $newpassword eq '');
   return (-1, "change_password() is not available in authpop3.pl");
}


########## misc support routine ##################################

sub sendcmd {
   my ($socket, $cmd, $r_result)=@_;
   my $ret;

   print $socket $cmd; $ret=<$socket>;
   @{$r_result}=split(/\s+/, $ret);
   shift @{$r_result} if (${$r_result}[0]=~/^[\+\-]/); # rm str +OK or -ERR from @result

   return 1 if ($ret!~/^\-/);
   return 0;
}

1;
