# 
# auth.pl are functions related to authentication
# it uses global variables defined in openwebmail.conf
# 
# $use_pam - whether to use pam or passwdfile for authentication
# $pamservicename - service name for authentication in /etc/pam.conf
# $passwdfile - passwd file containing the encrypted passwords
# $passwdmkdb - command used to update $passwdfile into system database
#
# 2001/07/29 tung@turtle.ee.ncku.edu.tw
# 

sub check_userpassword {
   my ($user, $password)=@_;
   if ($use_pam eq 'yes') {
      return(check_userpassword_by_pam($user, $password));
   } else {
      return(check_userpassword_by_file($user, $password));
   }
}

sub change_userpassword {
   my ($user, $oldpassword, $newpassword)=@_;
   if ($use_pam eq 'yes') {
      return(change_userpassword_by_pam($user, $oldpassword, $newpassword));
   } else {
      return(change_userpassword_by_file($user, $oldpassword, $newpassword));
   }
}

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $homedir) = (getpwnam($user))[2,3,6,7];

   # guess real homedir under sun's automounter
   if ($uid) {
      $homedir="/export$homedir" if (-d "/export$homedir");
   }
   return($realname, $uid, $gid, $homedir);
}


sub get_userlist {
   my @userlist=();
   my $line;   

   open(PASSWD, $passwdfile);
   while (defined($line=<PASSWD>)) {
      push(@userlist, (split(/:/, $line))[0]);
   }
   close(PASSWD);
   return(@userlist);
}


# internal routines ###########################################################

sub check_userpassword_by_file {
   my ($user, $password)=@_;
   my ($line, $u, $p);

   return 0 unless ( $user ne "" && $password ne "");

   open (PASSWD, $passwdfile) or return 0;
   while (defined($line=<PASSWD>)) {
      ($u, $p) = (split(/:/, $line))[0,1];
      last if ($u eq $user); # We've found the user in /etc/passwd
   }
   close (PASSWD);

   if ($u eq $user && crypt($password,$p) eq $p) {
      return 1;
   } else { 
      return 0;
   }
}

sub change_userpassword_by_file {
   my ($user, $oldpassword, $newpassword)=@_;
   my ($u, $p, $misc, $encrypted);
   my $content="";
   my $line;

   return 0 unless ( $user ne "" && $oldpassword ne "" && $newpassword ne "" );
   return 0 if (length($newpassword)<4);

   open (PASSWD, $passwdfile) or return 0;
   while (defined($line=<PASSWD>)) {
      $content .= $line;
      if ($u ne $user) {
         ($u, $p, $misc) = split(/:/, $line, 3);
      }
   }
   close (PASSWD);

   return 0 if ($u ne $user || crypt($oldpassword,$p) ne $p);

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

   return 0 if ($content !~ s/\Q$oldline\E/$newline/);

   open(PASSWD, ">$passwdfile.tmp") || return 0;
   print PASSWD $content || return 0;
   close(PASSWD) || return 0;

   chown(0,0, "$passwdfile.tmp");
   chmod(0600, "$passwdfile.tmp");

   if (rename("$passwdfile.tmp", $passwdfile) ) {
      if ($passwdmkdb ne "" && $passwdmkdb ne "none" ) {
         system("$passwdmkdb");	# update passwd db
      }
      return(1);
   } else {
      return(0);
   }
}

sub check_userpassword_by_pam {
   my ($user, $password)=@_;
   my $pamh;
   my $ret=0;
   
   # use Authen::PAM;
   require Authen::PAM;
   import Authen::PAM;
  
   sub checkpwd_conv_func {
      my @res;
      while ( @_ ) {
         my $code = shift;
         my $msg = shift;
         my $ans = "";

         $ans = $user     if ($code == PAM_PROMPT_ECHO_ON() );
         $ans = $password if ($code == PAM_PROMPT_ECHO_OFF() );

         push @res, (PAM_SUCCESS(),$ans);
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   if ( ref($pamh = new Authen::PAM($pamservicename, $user, \&checkpwd_conv_func)) ) {
      if ($pamh->pam_authenticate()==0) {
         $ret=1;
      }
   }
   $pamh = 0;  # force Destructor (per docs) (invokes pam_close())

   return($ret);
}

sub change_userpassword_by_pam {
   my ($user, $oldpassword, $newpassword)=@_;
   my $pamh;
   my $ret=0;

   # use Authen::PAM;
   require Authen::PAM;
   import Authen::PAM;

   sub changepwd_conv_func {
      my @res;
      my $state=0;
      while ( @_ ) {
         my $code = shift;
         my $msg = shift;
         my $ans = "";

         $ans = $user if ($code == PAM_PROMPT_ECHO_ON() );
         if ($code == PAM_PROMPT_ECHO_OFF() ) {
            $ans = $oldpassword if ($state == 0);
            $ans = $newpassword if ($state == 1);
            $ans = $newpassword if ($state == 2);
            $state++;
         }
         push @res, (PAM_SUCCESS(),$ans);
      }
      push @res, PAM_SUCCESS();
      return @res;
   }

   if (ref($pamh = new Authen::PAM($pamservicename, $user, \&changepwd_conv_func)) ) {
      if ( $pamh->pam_chauthtok()==0 ) {
         $ret=1;
      }
   }
   $pamh = 0;  # force Destructor (per docs) (invokes pam_close())
   return($ret);
}

1;