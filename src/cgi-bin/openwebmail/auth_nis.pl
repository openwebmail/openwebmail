package openwebmail::auth_nis;
use strict;
#
# auth_nis.pl - authenticate user through yppoppassd on NIS/YP server
#               To download yppoppassd by Ric Lister
#               http://cns.georgetown.edu/~ric/software/yppoppassd/
#
# 2003/11/05 Vladimir M Costa - vlad.AT.univap.br
#

#
# $ypcat_passwd : the command that gets passwd map from NIS/YP server
# -------------   --------------------------------
# platform        ypcat command
# -------------   --------------------------------
# NIS/YP          /usr/bin/ypcat passwd|
# NIS+            /usr/bin/niscat passwd.org_dir|
#
my $ypcat_passwd    = "/usr/bin/ypcat passwd|";
my $yppoppassd_host = "127.0.0.1";
my $yppoppassd_port = 106;

################### No configuration required from here ###################

use IO::Socket;

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : user doesn't exist
sub get_userinfo {
   my ($r_config, $user)=@_;
   my ($uid, $gid, $realname, $homedir);

   return(-2, 'User is null') if (!$user);
   ($uid, $gid, $realname, $homedir)= (getpwnam($user))[2,3,6,7];
   return(-4, "User $user doesn't exist") if ($uid eq "");

   # get other gid for this user in /etc/group
   while (my @gr=getgrent()) {
      $gid.=' '.$gr[2] if ($gr[3]=~/\b$user\b/ && $gid!~/\b$gr[2]\b/);
   }
   # use 1st field for realname
   $realname=(split(/,/, $realname))[0];
   # guess real homedir under sun's automounter
   $homedir="/export$homedir" if (-d "/export$homedir");

   return(0, "", $realname, $uid, $gid, $homedir);
}


#  0 : ok
# -1 : function not supported
# -3 : authentication system/internal error
sub get_userlist {	# only used by openwebmail-tool.pl -a
   my $r_config=$_[0];
   my @userlist=();
   my $line;

   open(PASSWD, $ypcat_passwd) || return(-3, $!, "");
   while (defined($line=<PASSWD>)) {
      next if ($line=~/^#/);
      chomp($line);
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   return(0, "", @userlist);
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
      alarm 10;
      $remote_sock=new IO::Socket::INET(   Proto=>'tcp',
                                           PeerAddr=>$yppoppassd_host,
                                           PeerPort=>$yppoppassd_port,);
      alarm 0;
   };
   if ($@) {                     # eval error, it means timeout
      return (-3, "yppoppassd server $yppoppassd_host timeout");
   }
   if (!$remote_sock) {         # connect error
      return (-3, "yppoppassd server $yppoppassd_host connection refused");
   }

   $remote_sock->autoflush(1);
   $_=<$remote_sock>;
   if (/^\-/) {
      close($remote_sock);
      return(-3, "yppoppassd server $yppoppassd_host not ready");
   }

   if (! /^\+/) {       # not supporting auth login or auth login failed
      print $remote_sock "user $user\r\n";
      $_=<$remote_sock>;
      if (/^\-/) {              # username error
         close($remote_sock);
         return(-2, "yppoppassd server $yppoppassd_host username error");
      }
      print $remote_sock "pass $password\r\n";
      $_=<$remote_sock>;
      if (/^\-/) {              # passwd error
         close($remote_sock);
         return(-4, "yppoppassd server $yppoppassd_host password error");
      }
   }

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
   return (-2, "Password too short") if (length($newpassword)<${$r_config}{'passwd_minlen'});

   my $remote_sock;
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 10;
      $remote_sock=new IO::Socket::INET(   Proto=>'tcp',
                                           PeerAddr=>$yppoppassd_host,
                                           PeerPort=>$yppoppassd_port,);
      alarm 0;
   };
   if ($@) {                     # eval error, it means timeout
      return (-3, "yppoppassd server $yppoppassd_host timeout");
   }
   if (!$remote_sock) {         # connect error
      return (-3, "yppoppassd server $yppoppassd_host connection refused");
   }

   $remote_sock->autoflush(1);
   $_=<$remote_sock>;
   if (/^\-/) {
      close($remote_sock);
      return(-3, "yppoppassd server $yppoppassd_host not ready");
   }

   if (! /^\+/) {       # not supporting auth login or auth login failed
      print $remote_sock "user $user\r\n";
      $_=<$remote_sock>;
      if (/^\-/) {              # username error
         close($remote_sock);
         return(-2, "yppoppassd server $yppoppassd_host username error");
      }
      print $remote_sock "pass $oldpassword\r\n";
      $_=<$remote_sock>;
      if (/^\-/) {              # passwd error
         close($remote_sock);
         return(-4, "yppoppassd server $yppoppassd_host oldpassword error");
      }
      print $remote_sock "newpass $newpassword\r\n";
      $_=<$remote_sock>;
      if (/^\-/) {              # passwd error
         close($remote_sock);
         return(-4, "yppoppassd server $yppoppassd_host newpassword error");
      }
   }

   close($remote_sock);
   return (0, "");
}

1;
