# 
# auth_pam.pl - authenticate user with PAM
# 
# The code of check_userpassword and change_userpassword is from
# the example code of Authen::PAM by Nikolay Pelov <nikip@iname.com>
# Webpage is available at http://www.cs.kuleuven.ac.be/~pelov/pam
#
# $pam_servicename : service name for authentication in /etc/pam.conf
#                    refer to http://www.fazekas.hu/~sini/neomail_pam/ 
#                    for more detail
#
# $pam_passwdfile  : the location of the file containing all usernames 
#
# 2001/10/05 tung@turtle.ee.ncku.edu.tw
# 

my $pam_servicename="openwebmail";
my $pam_passwdfile="/etc/passwd";

################### No configuration required from here ###################

# routines get_userinfo() and get_userlist still depend on /etc/passwd
# you may have to write your own routines if your user are not form /etc/passwd

use Authen::PAM;

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $homedir) = (getpwnam($user))[2,3,6,7];

   # use first field only
   $realname=(split(/,/, $realname))[0];
   # guess real homedir under sun's automounter
   if ($uid) {
      $homedir="/export$homedir" if (-d "/export$homedir");
   }
   return($realname, $uid, $gid, $homedir);
}


sub get_userlist {	# only used by checkmail.pl -a
   my @userlist=();
   my $line;   

   open(PASSWD, $pam_passwdfile);
   while (defined($line=<PASSWD>)) {
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   return(@userlist);
}


#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($user, $password)=@_;
   my $pamh;
   my $ret=0;
   
   return -2 if ($user eq "");

   sub checkpwd_conv_func {
      my @res;
      while ( @_ ) {
         my $code = shift;
         my $msg = shift;
         my $ans = "";

         if ($code == PAM_PROMPT_ECHO_ON() ) {
            $ans = $user;
         } elsif ($code == PAM_PROMPT_ECHO_OFF() ) {
            $ans = $password;
         }
         push @res, (PAM_SUCCESS(),$ans);
#         log_time("code:$code, msg:$msg, ans:$ans\n");	# debug
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   if ( ref($pamh = new Authen::PAM($pam_servicename, $user, \&checkpwd_conv_func)) ) {
      my $error=$pamh->pam_authenticate();
      if ($error==0) {
         $ret=0;
      } else {
#         log_time("authticate err $error");		# debug
         $ret=-4;
      }
   } else {
#      log_time("init error $pamh");			# debug
      $ret=-3;
   }
   $pamh = 0;  # force Destructor (per docs) (invokes pam_close())

   return($ret);
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($user, $oldpassword, $newpassword)=@_;
   my $pamh;
   my $ret=0;

   return -2 if ($user eq "");

   local $state=0;
   sub changepwd_conv_func {
      my @res;

      while ( @_ ) {
         my $code = shift;
         my $msg = shift;
         my $ans = "";

         if ($code == PAM_PROMPT_ECHO_ON() ) {
            $ans = $user;
         } elsif ($code == PAM_PROMPT_ECHO_OFF() ) {
            if ($state>1 || $msg =~ /new/i ) {
               $ans = $newpassword;
            } else {
               $ans = $oldpassword;
            }
            $state++;
         }
         push @res, (PAM_SUCCESS(),$ans);
#         log_time("code:$code, msg:$msg, ans:$ans\n");	# debug
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   if (ref($pamh = new Authen::PAM($pam_servicename, $user, \&changepwd_conv_func)) ) {
      my $error=$pamh->pam_chauthtok();
      if ( $error==0 ) {
         $ret=0;
      } else {
#         log_time("authtok err $error");			# debug
         $ret=-4;
      }
   } else {
#      log_time("init error $pamh");			# debug
      $ret=-3;
   }
   $pamh = 0;  # force Destructor (per docs) (invokes pam_close())
   return($ret);
}

1;
