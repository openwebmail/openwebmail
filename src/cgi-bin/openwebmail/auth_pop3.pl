# 
# auth_pop3.pl - authenticate user with POP3 server
# 
# This module assumes that users are located on remote pop3 server,
# so it uses the same uid for all users on the local machine.
#
# You have to do the following things to make the whole system work
#
# 1. create an user for the openwebmail runtime, ex: owmail
#
# 2. make the *.pl to be executed by user 'owmail'
#    a. set all *.pl to be setuid script of 'owmail', or
#    b. move whole openwebmail tree to the cgi dir under user 'owmail'
#    ps: You may need to reference the manpage/document of your httpd to know 
#        how to do user specific CGI
#
# 3. set the following options in openwebmail.conf
#
#    auth_module		auth_pop3.pl
#    mailspooldir		any directory that the user 'owmail' could write
#    use_homedirspools		no
#    use_homedirfolders		no
#    log_file			any file that user 'owmail' could write
#    enable_changepwd		no
#    enable_autoreply		no
#    enable_setforward		no
#    autopop3_at_refresh	no
#
# $pop3_authserver: the server used to authenticate pop3 user
# $pop3_authport: the port which pop3 server is listening to
# $local_uid: uid used on this machine
#
# 2002/02/12 tung@turtle.ee.ncku.edu.tw
# 

my $pop3_authserver="localhost";
my $pop3_authport='110';
my $local_uid=$>;

################### No configuration required from here ###################

# routines get_userinfo() and get_userlist still depend on /etc/passwd
# you may have to write your own routines if your user are not form /etc/passwd

use FileHandle;
use IO::Socket;

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


sub get_userlist {	# only used by checkmail.pl -a
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
      alarm 5;
      $remote_sock=new IO::Socket::INET(   Proto=>'tcp',
                                           PeerAddr=>$pop3_authserver,
                                           PeerPort=>$pop3_authport,);
      alarm 0;
   };
   return(-3) if ($@);			# eval error, it means timeout
   return(-3) if (!$remote_sock);	# connect error

   $remote_sock->autoflush(1);
   $_=<$remote_sock>;
   return(-3) if (/^\-/);		# server not ready

   print $remote_sock "user $user\r\n";
   $_=<$remote_sock>;
   return(-2) if (/^\-/);		# username error

   print $remote_sock "pass $password\r\n";
   $_=<$remote_sock>;
   return (-4) if (/^\-/);		# passwd error

   print $remote_sock "quit\r\n";
   close($remote_sock);

   return(0);
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
