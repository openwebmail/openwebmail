package openwebmail::auth_pam_cobalt;
use strict;
#
# auth_pam_cobalt.pl - authenticate user with PAM and check
#		       if user is valid under the HOST specified in the URL
#
# 2002/08/01 webmaster.AT.pkgmaster.com,
#            based on parts auth_cobalt.pl by Trevor.Paquette@TeraGo.ca
# 2001/10/05 tung.AT.turtle.ee.ncku.edu.tw (orig: auth_pam.pl)
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

use Authen::PAM;
use Fcntl qw(:DEFAULT :flock);
require "filelock.pl";

# routines get_userinfo() and get_userlist still get data from a passwdfile 
# instead of PAM, you may have to rewrite if it does notfit your requirement

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : user doesn't exist
sub get_userinfo {
   my ($r_config, $user)=@_;
   return(-2, 'User is null') if (!$user);

   my ($uid, $gid, $realname, $homedir);
   if ($pam_passwdfile_plaintext eq "/etc/passwd") {
      ($uid, $gid, $realname, $homedir)= (getpwnam($user))[2,3,6,7];
   } else {
      if ($pam_passwdfile_plaintext=~/\|/) { # maybe NIS, try getpwnam first
         ($uid, $gid, $realname, $homedir)= (getpwnam($user))[2,3,6,7]; 
      }
      if ($uid eq "") { # else, open file directly
         ($uid, $gid, $realname, $homedir)= (getpwnam_file($user, $pam_passwdfile_plaintext))[2,3,6,7];
      }
   }
   return(-4, "User $user doesn't exist") if ($uid eq "");

   # get other gid for this user in /etc/group
   while (my @gr=getgrent()) {
      $gid.=' '.$gr[2] if ($gr[3]=~/\b$user\b/ && $gid!~/\b$gr[2]\b/);
   }
   # use first field only
   $realname=(split(/,/, $realname))[0];
   # guess real homedir under sun's automounter
   $homedir="/export$homedir" if (-d "/export$homedir");

   return(0, "", $realname, $uid, $gid, $homedir);
}


sub get_userlist {	# only used by openwebmail-tool.pl -a
   my $r_config=$_[0];

   my @userlist=();
   my $line;

   # a file should be locked only if it is local accessable
   if ( -f $pam_passwdfile_plaintext) {
      filelock("$pam_passwdfile_plaintext", LOCK_SH) or 
         return (-3, "Couldn't get read lock on $pam_passwdfile_plaintext", @userlist);
   }
   open(PASSWD, $pam_passwdfile_plaintext);
   while (defined($line=<PASSWD>)) {
      next if ($line=~/^#/);
      chomp($line);
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   filelock("$pam_passwdfile_plaintext", LOCK_UN) if ( -f $pam_passwdfile_plaintext);
   return(0, "", @userlist);
}

# globals passed to inner function to avoid closure effect
use vars qw($pam_user $pam_password $pam_newpassword $pam_convstate);

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my $r_config;
   local ($pam_user, $pam_password);	# localized global to make reentry safe
   ($r_config, $pam_user, $pam_password)=@_;
   return (-2, "User or password is null") if (!$pam_user||!$pam_password);

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
#main::log_time("code:$code, msg:$msg, ans:$ans\n");	# debug
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   # disable SIG CHLD since authsys in PAM may fork process
   local $SIG{CHLD}; undef $SIG{CHLD};

   my ($pamh, $ret, $errmsg);
   if ( ref($pamh = new Authen::PAM($pam_servicename, $pam_user, \&checkpwd_conv_func)) ) {
      my $error=$pamh->pam_authenticate();
      if ($error==0) {
         ($ret, $errmsg)= (0, "");
      } else {
         ($ret, $errmsg)= (-4, "pam_authticate() err $error, ".pam_strerror($pamh, $error));
      }
   } else {
      ($ret, $errmsg)= (-3, "PAM init error $pamh");
   }
   $pamh = 0;  # force Destructor (per docs) (invokes pam_close())
   return($ret, $errmsg) if ($ret<0);

   ##############################################
   # Cobalt security check
   ##############################################
   # check to see if the user is in the domain URL passed.
   # This stops people 'piggybacking' their login from allowed domains.

   # construct home directory from info given
   my $cbhttphost=$ENV{'HTTP_HOST'}; $cbhttphost=~s/:\d+$//;	# remove port number
   my $cbhomedir="/home/sites/$cbhttphost/users/$pam_user";
   if ( ! -d $cbhomedir ) {
      return (-4, "invalid access, homedir /home/sites/$cbhttphost/users/$pam_user doesn't exist");
   }

   # ----------------------------------------
   # emulate pam_nologin.so
   # first.. make sure /etc/nologin is not there
   if ( -e "/etc/nologin" ) {
      return (-4, "/etc/nologin found, all pop logins suspended");
   }

   # ----------------------------------------
   # emulate pam_shells.so
   # Make sure that the user has not been 'suspended'
   my ($name, $shell);
   if ($pam_passwdfile_plaintext eq "/etc/passwd") {
      $shell = (getpwnam($pam_user))[8];
   } else {
      if ($pam_passwdfile_plaintext=~/\|/) { # maybe NIS, try getpwnam first
         ($name, $shell)= (getpwnam($pam_user))[0,8];
      }
      if ($name eq "") { # else, open file directly
         ($name, $shell) = (getpwnam_file($pam_user, $pam_passwdfile_plaintext))[0,8];
      }
   }
   # if we can't open /etc/shells; assume password is invalid
   if (!open(ES, "/etc/shells")) {
     return (-4, "/etc/shells not found, all pop logins suspended");
   }
   if ($shell) {
      # assume an invalid shell until we get a match
      my $validshell = 0;
      while(<ES>) {
         chop;
         if( $shell eq $_ ) {
            $validshell = 1; last;
         }
      }
      close(ES);
      if (!$validshell) {
         # the user has been suspended.. return bad password
         return (-4, "user $pam_user doesn't have valid shell");
      }
   }

   # at this point we have a valid userid, under the url passwd,
   # and they have not been suspended
   return (0, "");
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   local ($pam_user, $pam_password, $pam_newpassword); # localized global to make reentry safe
   my $r_config;
   ($r_config, $pam_user, $pam_password, $pam_newpassword)=@_;
   return (-2, "User or password is null") if (!$pam_user||!$pam_password||!$pam_newpassword);

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
#main::log_time("code:$code, msg:$msg, ans:$ans\n");	# debug
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   # disable SIG CHLD since authsys in PAM may fork process
   local $SIG{CHLD}; undef $SIG{CHLD};

   my ($pamh, $ret, $errmsg);
   if (ref($pamh = new Authen::PAM($pam_servicename, $pam_user, \&changepwd_conv_func)) ) {
      my $error=$pamh->pam_chauthtok();
      if ( $error==0 ) {
         ($ret, $errmsg)= (0, "");
      } else {
         ($ret, $errmsg)= (-4, "pam_authtok() err $error, ".pam_strerror($pamh, $error));
      }
   } else {
      ($ret, $errmsg)= (-3, "PAM init error $pamh");
   }
   $pamh = 0;  # force Destructor (per docs) (invokes pam_close())
   return($ret, $errmsg);
}


################### misc support routine ###################
# use flock since what we modify here are local system files
sub filelock () {
   return(openwebmail::filelock::flock_lock(@_));
}

# this routie is slower than system getpwnam() but can work with file
# other than /etc/passwd. ps: it always return '*' for passwd field.
sub getpwnam_file {
   my ($user, $passwdfile_plaintext)=@_;
   my ($name, $passwd, $uid, $gid, $gcos, $dir, $shell);

   return("", "", "", "", "", "", "", "", "") if ($user eq "");

   open(PASSWD, "$passwdfile_plaintext");
   while(<PASSWD>) {
      next if (/^#/);
      chomp;
      ($name, $passwd, $uid, $gid, $gcos, $dir, $shell)=split(/:/);
      last if ($name eq $user);
   }
   close(PASSWD);

   if ($name eq $user) {
      return($name, "*", $uid, $gid, 0, "", $gcos, $dir, $shell);
   } else {
      return("", "", "", "", "", "", "", "", "");
   }
}

1;
