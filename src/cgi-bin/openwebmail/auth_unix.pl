package openwebmail::auth_unix;
use strict;
#
# auth_unix.pl - authenticate user with unix password
#
# 2002/07/19 tung@turtle.ee.ncku.edu.tw
#

#
# $unix_passwdfile_plaintext : the plaintext file containing all usernames
#                              and related uid, gid, homedir, shell info.
#                              The deault is /etc/passwd on most unix systems.
#
# $unix_passwdfile_encrypted : the file containing all usernames and
#                              their corresponding encrypted passwords.
# ------------------------------   --------------------------------
# platform                         passwdfile encrypted
# ------------------------------   --------------------------------
# Shadow Passwd (linux/solaris)    /etc/shadow
# FreeBSD                          /etc/master.passwd
# Mac OS X                         /usr/bin/nidump passwd .|
# NIS/YP                           /usr/bin/ypcat passwd|
# NIS+                             /usr/bin/niscat passwd.org_dir|
# else...                          /etc/passwd
# ------------------------------   --------------------------------
#
# $unix_passwdmkdb : The command executed after any password modification
#                    to update the changes of passwdfile to passwd database.
# ------------------------------   --------------------------------
# platform                         passwd mkdb command
# ------------------------------   --------------------------------
# Free/Net/OpenBSD                 /usr/sbin/pwd_mkdb
# Linux/Solaris	                   none
# else...                          none
# ------------------------------   --------------------------------
#
# $check_shell : whether to check if the user's shell is listed in /etc/shells.
#

my $unix_passwdfile_plaintext="/etc/passwd";
my $unix_passwdfile_encrypted="/etc/master.passwd";
my $unix_passwdmkdb="/usr/sbin/pwd_mkdb";
my $check_shell=0;

################### No configuration required from here ###################

use Fcntl qw(:DEFAULT :flock);
require "filelock.pl";

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : user doesn't exist
sub get_userinfo {
   my ($r_config, $user)=@_;
   my ($uid, $gid, $realname, $homedir);

   return(-2, 'User is null') if (!$user);
   if ($unix_passwdfile_plaintext eq "/etc/passwd") {
      ($uid, $gid, $realname, $homedir)= (getpwnam($user))[2,3,6,7];
   } else {
      if ($unix_passwdfile_plaintext=~/\|/) { # maybe NIS, try getpwnam first
         ($uid, $gid, $realname, $homedir)= (getpwnam($user))[2,3,6,7]; 
      }
      if ($uid eq "") { # else, open file directly
         ($uid, $gid, $realname, $homedir)= (getpwnam_file($user, $unix_passwdfile_plaintext))[2,3,6,7];
      }
   }
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

   # a file should be locked only if it is local accessable
   if ( -f $unix_passwdfile_plaintext) {
      filelock("$unix_passwdfile_plaintext", LOCK_SH) or 
         return (-3, "Couldn't get read lock on $unix_passwdfile_plaintext", @userlist);
   }
   open(PASSWD, $unix_passwdfile_plaintext);
   while (defined($line=<PASSWD>)) {
      next if ($line=~/^#/);
      chomp($line);
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   filelock("$unix_passwdfile_plaintext", LOCK_UN) if ( -f $unix_passwdfile_plaintext);
   return(0, "", @userlist);
}


#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($r_config, $user, $password)=@_;
   return (-2, "User or password is null") if (!$user||!$password);

   # a file should be locked only if it is local accessable
   if ( -f $unix_passwdfile_encrypted) {
      filelock("$unix_passwdfile_encrypted", LOCK_SH) or
         return (-3, "Couldn't get read lock on $unix_passwdfile_encrypted");
   }
   if ( ! open (PASSWD, "$unix_passwdfile_encrypted") ) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN) if ( -f $unix_passwdfile_encrypted);
      return (-3, "Couldn't open $unix_passwdfile_encrypted");
   }
   my ($line, $u, $p);
   while (defined($line=<PASSWD>)) {
      chomp($line);
      ($u, $p) = (split(/:/, $line))[0,1];
      last if ($u eq $user); # We've found the user in /etc/passwd
   }
   close (PASSWD);
   filelock("$unix_passwdfile_encrypted", LOCK_UN) if ( -f $unix_passwdfile_encrypted);

   return(-4, "User $user doesn't exist") if ($u ne $user);
   return(-4, "Password incorrect") if (crypt($password,$p) ne $p);
   return (0, "") if (!$check_shell);

   my ($name, $shell);
   if ($unix_passwdfile_plaintext eq "/etc/passwd") {
      $shell = (getpwnam($user))[8];
   } else {
      if ($unix_passwdfile_plaintext=~/\|/) { # maybe NIS, try getpwnam first
         ($name, $shell)= (getpwnam($user))[0,8];
      }
      if ($name eq "") { # else, open file directly
         ($name, $shell) = (getpwnam_file($user, $unix_passwdfile_plaintext))[0,8];
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
   my ($r_config, $user, $oldpassword, $newpassword)=@_;
   my ($u, $p, $misc, $encrypted);
   my ($content, $line);
   return (-2, "User or password is null") if (!$user||!$oldpassword||!$newpassword);
   return (-2, "Password too short") if (length($newpassword)<${$r_config}{'passwd_minlen'});

   # a passwdfile could be modified only if it is local accessable
   return (-1, "$unix_passwdfile_encrypted doesn't exist on local") if (! -f $unix_passwdfile_encrypted);

   filelock("$unix_passwdfile_encrypted", LOCK_EX) or
      return (-3, "Couldn't get write lock on $unix_passwdfile_encrypted");
   if ( ! open (PASSWD, "$unix_passwdfile_encrypted") ) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN);
      return (-3, "Couldn't open $unix_passwdfile_encrypted");
   }
   while (defined($line=<PASSWD>)) {
      $content .= $line;
      chomp($line);
      ($u, $p, $misc) = split(/:/, $line, 3) if ($u ne $user);
   }
   close (PASSWD);

   if ($u ne $user) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN);
      return (-4, "User $user doesn't exist");
   }
   if (crypt($oldpassword,$p) ne $p) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN);
      return (-4, "Password incorrect");
   }

   my @salt_chars = ('a'..'z','A'..'Z','0'..'9');
   my $salt = $salt_chars[rand(62)] . $salt_chars[rand(62)];
   if ($p =~ /^\$1\$/) {	# if orig encryption is MD5, keep using it
      $salt = '$1$'. $salt;
   }
   $encrypted= crypt($newpassword, $salt);

   my $oldline=join(":", $u, $p, $misc);
   my $newline=join(":", $u, $encrypted, $misc);

   if ($content !~ s/\Q$oldline\E/$newline/) {
      filelock("$unix_passwdfile_encrypted", LOCK_UN);
      return (-3, "Unable to match entry for modification");
   }

   open(TMP, ">$unix_passwdfile_encrypted.tmp.$$") || goto authsys_error;
   print TMP $content || goto authsys_error;
   close(TMP) || goto authsys_error;

   if ($unix_passwdmkdb ne "" && $unix_passwdmkdb ne "none" ) {
      # disable outside $SIG{CHLD} handler temporarily for system() return value
      local $SIG{CHLD}; undef $SIG{CHLD}; 
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
   return (0, "");

authsys_error:
   unlink("$unix_passwdfile_encrypted.tmp.$$");
   filelock("$unix_passwdfile_encrypted", LOCK_UN);
   return (-3, "Unable to write $unix_passwdfile_encrypted");
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
