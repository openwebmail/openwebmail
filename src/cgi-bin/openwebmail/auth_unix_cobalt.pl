#
# auth_unix_cobalt.pl - authenticate user with unix password and check
#                       if user is valid under the HOST specified in the URL
#
# Version 1.15 Aug 6, 2002
#
# 2002/08/06 Trevor.Paquette@TeraGo.ca
#            Fix comments
# 2002/07/16 Trevor.Paquette@TeraGo.ca (add check for cobalt security)
# 2001/12/20 tung@turtle.ee.ncku.edu.tw (orig: auth_unix.pl)
#

#
# ***** IMPORTANT *****
#
# If you are going to use this auth module then the webmail on your
# Cobalt MUST be accessed via the the FQDN 'http://HOST.DOMAIN.COM'.
#
# Using 'http://DOMAIN.COM' will fail the user security check.
#
# This auth takes advantage of the fact that Cobalt puts all users
# under the following directory : /home/sites/FQDN_HOST/users
#
# This auth module will do the following checks:
# 1. the authenticated user has a directory in /home/sites/FQDN_HOST/users
#    (This is valid user in an allowed_serverdomain
# 2. /etc/nologin doesn't exist
#    if the file exists, then all logins (including webmail) should be disabled
# 3. the user's shell is valid in /etc/shells
#    If the user's shell is not in /etc/shells, assume the user has been
#    suspended
#
# Use this module in conjunction with allowed_serverdomain to lock
# down which domains actually have access to webmail.
#
# $unix_passwdfile_plaintext : the plaintext file containing all usernames
#                              and related uid, gid, homedir, shell info.
#                              The deault is /etc/passwd on most unix systems.
# $unix_passwdfile_encrypted : the file containing all usernames and
#                              their corresponding encrypted passwords.
# $unix_passwdmkdb : The command executed after any password modification
#                    to update the changes of passwdfile to passwd database.
# $check_shell : whether to check if the user's shell is listed in /etc/shells. 

my $unix_passwdfile_plaintext="/etc/passwd";
my $unix_passwdfile_encrypted="/etc/shadow";
my $unix_passwdmkdb="none";
my $check_shell=1;

################### No configuration required from here ###################

use strict;
use Fcntl qw(:DEFAULT :flock);

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $homedir);

   if ($unix_passwdfile_plaintext eq "/etc/passwd") {
      ($uid, $gid, $realname, $homedir)= (getpwnam($user))[2,3,6,7];
   } else {
      ($uid, $gid, $realname, $homedir)= (getpwnam_file($user, $unix_passwdfile_plaintext))[2,3,6,7];
   }

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

   # a file should be locked only if it is local accessable
   filelock("$unix_passwdfile_encrypted", LOCK_SH) if ( -f $unix_passwdfile_encrypted);
   open(PASSWD, $unix_passwdfile_encrypted);
   while (defined($line=<PASSWD>)) {
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   filelock("$unix_passwdfile_encrypted", LOCK_UN) if ( -f $unix_passwdfile_encrypted);
   return(@userlist);
}


#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($user, $password)=@_;
   my ($line, $u, $p);

   return -2 unless ( $user ne "" && $password ne "");

   # a file should be locked only if it is local accessable
   filelock("$unix_passwdfile_encrypted", LOCK_SH) if ( -f $unix_passwdfile_encrypted);
   if ( ! open (PASSWD, "$unix_passwdfile_encrypted") ) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN) if ( -f $unix_passwdfile_encrypted);
      return -3;
   }
   while (defined($line=<PASSWD>)) {
      ($u, $p) = (split(/:/, $line))[0,1];
      last if ($u eq $user); # We've found the user in /etc/passwd
   }
   close (PASSWD);
   filelock("$unix_passwdfile_encrypted", LOCK_UN) if ( -f $unix_passwdfile_encrypted);

   return -4 if ($u ne $user || crypt($password,$p) ne $p);


   ##############################################
   # Cobalt security check
   ##############################################
   # before we return 0 we need to check to see if
   # the user is in the domain URL passed.
   #  This stops people 'piggybacking' their login
   #  from allowed domains.

   # construct home directory from info given
   my $cbhttphost=$ENV{'HTTP_HOST'}; $cbhttphost=~s/:\d+$//;	# remove port number
   my $cbhomedir="/home/sites/$cbhttphost/users/$user";
   if ( ! -d $cbhomedir ) {
      writelog("auth_cobalt - invalid access, user: $user, site: $cbhttphost");
      return -4;
   }

   # ----------------------------------------
   # emulate pam_nologin.so
   # first.. make sure /etc/nologin is not there
   if ( -e "/etc/nologin" ) {
      writelog("auth_cobalt - /etc/nologin found, all pop logins suspended");
      return -4;
   }

   # ----------------------------------------
   # emulate pam_shells.so
   # Make sure that the user has not been 'suspended'

   return 0 if (!$check_shell);

   # get the current shell
   my $shell;
   if ($unix_passwdfile_plaintext eq "/etc/passwd") {
      $shell = (getpwnam($user))[8];
   } else {
      $shell = (getpwnam_file($user, $unix_passwdfile_plaintext))[8];
   }

   # assume an invalid shell until we get a match
   my $validshell = 0;

   # if we can't open /etc/shells; assume password is invalid
   if (!open(ES, "/etc/shells")) {
     writelog("auth_cobalt - /etc/shells not found, all pop logins suspended");
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


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($user, $oldpassword, $newpassword)=@_;
   my ($u, $p, $misc, $encrypted);
   my $content="";
   my $line;

   return -2 unless ( $user ne "" && $oldpassword ne "" && $newpassword ne "" );
   return -2 if (length($newpassword)<4);

   # a passwdfile could be modified only if it is local accessable
   return -1 if (! -f $unix_passwdfile_encrypted);

   filelock("$unix_passwdfile_encrypted", LOCK_EX);
   open (PASSWD, $unix_passwdfile_encrypted) or return -3;
   while (defined($line=<PASSWD>)) {
      $content .= $line;
      if ($u ne $user) {
         ($u, $p, $misc) = split(/:/, $line, 3);
      }
   }
   close (PASSWD);

   if ($u ne $user || crypt($oldpassword,$p) ne $p) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN);
      return -4;
   }

   srand();
   my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
   my $salt=substr($table, int(rand(length($table))), 1).
            substr($table, int(rand(length($table))), 1);

   if ($p =~ /^\$1\$/) {	# if orig encryption is MD5, keep using it
      $salt = '$1$'. $salt;
   }

   $encrypted= crypt($newpassword, $salt);

   my $oldline=join(":", $u, $p, $misc);
   my $newline=join(":", $u, $encrypted, $misc);

   if ($content !~ s/\Q$oldline\E/$newline/) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN);
      return -3;
   }

   open(TMP, ">$unix_passwdfile_encrypted.tmp.$$") || goto authsys_error;
   print TMP $content || goto authsys_error;
   close(TMP) || goto authsys_error;

   if ($unix_passwdmkdb ne "" && $unix_passwdmkdb ne "none" ) {
      # update passwd and db with pwdmkdb program
      if ( system("$unix_passwdmkdb $unix_passwdfile_encrypted.tmp.$$")!=0 ) {
         goto authsys_error;
      }
   } else {
      # automic update passwd by rename
      my ($fmode, $fuid, $fgid) = (stat($unix_passwdfile_encrypted))[2,4,5];
      chown($fuid, $fgid, "$unix_passwdfile_encrypted.tmp.$$");
      chmod($fmode, "$unix_passwdfile_encrypted.tmp.$$");
      rename("$unix_passwdfile_encrypted.tmp.$$", $unix_passwdfile_encrypted) || goto authsys_error;
   }
   filelock("$unix_passwdfile_encrypted", LOCK_UN);
   return(0);

authsys_error:
   unlink("$unix_passwdfile_encrypted.tmp.$$");
   filelock("$unix_passwdfile_encrypted", LOCK_UN);
   return(-3);
}

# this routie is slower than system getpwnam() but can work with file
# other than /etc/passwd. ps: it always return '*' for passwd field.
sub getpwnam_file {
   my ($user, $passwdfile_plaintext)=@_;
   my ($name, $passwd, $uid, $gid, $gcos, $dir, $shell);

   return("", "", "", "", "", "", "", "", "") if ($user eq "" || ! -f $passwdfile_plaintext);

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
