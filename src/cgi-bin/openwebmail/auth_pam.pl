package openwebmail::auth_pam;
use strict;
#
# auth_pam.pl - authenticate user with PAM
#
# 2001/10/05 tung.AT.turtle.ee.ncku.edu.tw
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

my $pam_servicename="openwebmail";
my $pam_passwdfile_plaintext="/etc/passwd";
my $check_shell=0;

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


#  0 : ok
# -1 : function not supported
# -3 : authentication system/internal error
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
   return (0, "") if (!$check_shell);

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
   if ($shell && open(ES, "/etc/shells")) {
      my $validshell = 0;   # assume an invalid shell until we get a match
      while(<ES>) {
         chop;
         if( $shell eq $_ ) {
            $validshell = 1; last;
         }
      }
      close(ES);
      return (-4, "user doesn't have valid shell") if (!$validshell);
   }
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
