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

my $unix_passwdfile_plaintext="/etc/passwd";
my $unix_passwdfile_encrypted="/etc/master.passwd";
my $unix_passwdmkdb="/usr/sbin/pwd_mkdb";

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


sub get_userlist {	# only used by checkmail.pl -a
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

   if ($u eq $user && crypt($password,$p) eq $p) {
      return 0;
   } else {
      return -4;
   }
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
