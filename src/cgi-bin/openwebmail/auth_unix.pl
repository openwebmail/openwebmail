# 
# auth_unix.pl - authenticate user with unix password
#
# $unix_passwdfile : the location of the file containing all usernames 
#                    and their corresponding encrypted passwords. 
# ------------------------------   --------------------------------
# platform                         passwdfile
# ------------------------------   --------------------------------
# Shadow Passwd (linux/solaris)    /etc/shadow
# FreeBSD                          /etc/master.passwd
# NIS/YP                           /usr/bin/ypcat passwd|
# NIS+                             /usr/bin/niscat passwd.org_dir|
# else....                         /etc/passwd
# ------------------------------   --------------------------------
#
# $unix_passwdmkdb : The command executed after any password modification 
#                    to update the changes of passwdfile to passwd database.
# ------------------------------   --------------------------------
# platform                         passwd mkdb command
# ------------------------------   --------------------------------
# Free/Net/OpenBSD                 /usr/sbin/pwd_mkdb
# Linux	                           none
# Solaris                          none
# ------------------------------   --------------------------------
#
# 2001/12/20 tung@turtle.ee.ncku.edu.tw
#

my $unix_passwdfile="/etc/master.passwd";
my $unix_passwdmkdb="/usr/sbin/pwd_mkdb";

################### No configuration required from here ###################

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

   # a file should be locked only if it is local accessable
   filelock("$unix_passwdfile", LOCK_SH) if ( -f $unix_passwdfile);
   open(PASSWD, $unix_passwdfile);
   while (defined($line=<PASSWD>)) {
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   filelock("$unix_passwdfile", LOCK_UN) if ( -f $unix_passwdfile);
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
   filelock("$unix_passwdfile", LOCK_SH) if ( -f $unix_passwdfile);
   if ( ! open (PASSWD, "$unix_passwdfile") ) {
      filelock("$unix_passwdfile", LOCK_UN) if ( -f $unix_passwdfile);
      return -3;
   }
   while (defined($line=<PASSWD>)) {
      ($u, $p) = (split(/:/, $line))[0,1];
      last if ($u eq $user); # We've found the user in /etc/passwd
   }
   close (PASSWD);
   filelock("$unix_passwdfile", LOCK_UN) if ( -f $unix_passwdfile);

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
   return -1 if (! -f $unix_passwdfile);

   filelock("$unix_passwdfile", LOCK_EX);
   open (PASSWD, $unix_passwdfile) or return -3;
   while (defined($line=<PASSWD>)) {
      $content .= $line;
      if ($u ne $user) {
         ($u, $p, $misc) = split(/:/, $line, 3);
      }
   }
   close (PASSWD);

   if ($u ne $user || crypt($oldpassword,$p) ne $p) {
      filelock("$unix_passwdfile", LOCK_UN);
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
      filelock("$unix_passwdfile", LOCK_UN);
      return -3;
   }

   open(TMP, ">$unix_passwdfile.tmp.$$") || goto authsys_error;
   print TMP $content || goto authsys_error;
   close(TMP) || goto authsys_error;

   if ($unix_passwdmkdb ne "" && $unix_passwdmkdb ne "none" ) {
      # update passwd and db with pwdmkdb program
      if ( system("$unix_passwdmkdb $unix_passwdfile.tmp.$$")!=0 ) {
         goto authsys_error;
      }
   } else {
      # automic update passwd by rename
      chown(0,0, "$unix_passwdfile.tmp.$$");
      chmod(0600, "$unix_passwdfile.tmp.$$");
      rename("$unix_passwdfile.tmp.$$", $unix_passwdfile) || goto authsys_error;
   }
   filelock("$unix_passwdfile", LOCK_UN);
   return(0);

authsys_error:
   unlink("$unix_passwdfile.tmp.$$");
   filelock("$unix_passwdfile", LOCK_UN);
   return(-3);
}

1;
