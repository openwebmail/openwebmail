#
# auth_pam_cobalt.pl - authenticate user with PAM and check
#		       if user is valid under the HOST specified in the URL
#
# 2002/08/01 webmaster@pkgmaster.com,
#            based on parts auth_cobalt.pl by Trevor.Paquette@TeraGo.ca
# 2001/10/05 tung@turtle.ee.ncku.edu.tw (orig: auth_pam.pl)
#

#
# The code of check_userpassword and change_userpassword is from
# the example code of Authen::PAM by Nikolay Pelov <nikip@iname.com>
# Webpage is available at http://www.cs.kuleuven.ac.be/~pelov/pam
#
# $pam_servicename : service name for authentication in /etc/pam.conf
#                    refer to http://www.fazekas.hu/~sini/neomail_pam/
#                    for more detail
#
# $pam_passwdfile_plaintext : the plaintext file containing all usernames
#

#
# ***** IMPORTANT *****
#
# if you are going to use this auth module then the webmail on your
# cobalt MUST be accessed via the HOST.DOMAIN.COM. Only use of
# DOMAIN.COM will breaks the check.
#
# This auth takes advantage of the fact that Coablt puts all users
# under the following directory : /home/sites/URL_HOST/users
# This auth module will do the following checks:
# 1. the logined user has a directory in /home/sites/URL_HOST/users.
# 2. /etc/nologin doesn't exist
# 3. the user's shell is valid in /etc/shells
#
# Use this module in conjuntion with allowed_serverdomain to lock
# down which domains actually have access to webmail.

my $pam_servicename="openwebmail";
my $pam_passwdfile_plaintext="/etc/passwd";

################### No configuration required from here ###################

# routines get_userinfo() and get_userlist still depend on /etc/passwd
# you may have to write your own routines if your user are not form /etc/passwd

use strict;
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


sub get_userlist {	# only used by openwebmail-tool.pl -a
   my @userlist=();
   my $line;

   open(PASSWD, $pam_passwdfile_plaintext);
   while (defined($line=<PASSWD>)) {
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   return(@userlist);
}

# globals passed to inner function to avoid closure effect
use vars qw($pam_user $pam_password $pam_newpassword $pam_convstate);

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   local ($pam_user, $pam_password)=@_;	# localized global to make reentry safe
   my $pamh;
   my $ret=0;

   return -2 if ($pam_user eq "");

   sub checkpwd_conv_func {
      my @res;
      while ( @_ ) {
         my $code = shift;
         my $msg = shift;
         my $ans = "";

         if ($code == PAM_PROMPT_ECHO_ON() ) {
            $ans = $pam_user;
         } elsif ($code == PAM_PROMPT_ECHO_OFF() ) {
            $ans = $pam_password;
         }
         push @res, (PAM_SUCCESS(),$ans);
#         log_time("code:$code, msg:$msg, ans:$ans\n");	# debug
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   if ( ref($pamh = new Authen::PAM($pam_servicename, $pam_user, \&checkpwd_conv_func)) ) {
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

if ($ret == 0) {

   ##############################################
   # Cobalt security check
   ##############################################
   # before we return 0 we need to check to see of the user is
   # in the domain URL passed
   # this stops people 'piggybacking' their login from allowed domains.

   # construct home directory from info given
   my $cbhttphost=$ENV{'HTTP_HOST'}; $cbhttphost=~s/:\d+$//;    # remove port number
   my $cbhomedir="/home/sites/$cbhttphost/users/$user";
   if ( ! -d $cbhomedir ) {
      writelog("auth_cobalt - invalid access, user: $user, site: $cbhttphost");
      return -4;
   }

   # first.. make sure /etc/nologin is not there
   if ( -e "/etc/nologin" ) {
      writelog("auth_cobalt - /etc/nologin found, all logins suspended");
      return -4;
   }

   # Make sure that the user has not been 'suspended'
   # get the current shell
   my $shell = (getpwnam($user))[8];

   # assume an invalid shell until we get a match
   my $validshell = 0;

   # if we can't open /etc/shells; assume password is invalid
   if (!open(ES,  "/etc/shells")) {
      writelog("auth_cobalt - /etc/shells not found, all logins suspended");
      return(-4);
   }

   while(<ES>) {
      chop;
      if( $shell eq $_ ) {
         $validshell = 1;
      }
   }
   close(ES);

   if ($validshell) {
      # at this point we have a valid userid, under the url passwd,
      # and they have not been suspended
      return 0;
   }

   # the user has been suspended.. return bad password
   writelog("auth_cobalt - user suspended, user: $user, site: $cbhttphost");
   return -4;
}

   return($ret);
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   local ($pam_user, $pam_password, $pam_newpassword)=@_; # localized global to make reentry safe
   my $pamh;
   my $ret=0;

   return -2 if ($pam_user eq "");

   local $pam_convstate=0;	# localized global to make reentry safe
   sub changepwd_conv_func {
      my @res;

      while ( @_ ) {
         my $code = shift;
         my $msg = shift;
         my $ans = "";

         if ($code == PAM_PROMPT_ECHO_ON() ) {
            $ans = $pam_user;
         } elsif ($code == PAM_PROMPT_ECHO_OFF() ) {
            if ($pam_convstate>1 || $msg =~ /new/i ) {
               $ans = $pam_newpassword;
            } else {
               $ans = $pam_password;
            }
            $pam_convstate++;
         }
         push @res, (PAM_SUCCESS(),$ans);
#         log_time("code:$code, msg:$msg, ans:$ans\n");	# debug
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   if (ref($pamh = new Authen::PAM($pam_servicename, $pam_user, \&changepwd_conv_func)) ) {
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
