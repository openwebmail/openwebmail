#                              The BSD License
#
#  Copyright (c) 2009-2011, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# auth_unix.pl -  authenticate user with unix password
#
# 2002/07/16 Trevor.Paquette.AT.TeraGo.ca
#            add check for nologin, validshell, cobaltuser
# 2001/12/20 tung.AT.turtle.ee.ncku.edu.tw

package ow::auth_unix;

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

require "modules/filelock.pl";
require "modules/tool.pl";

my %conf = ();

if (($_ = ow::tool::find_configfile('etc/auth_unix.conf', 'etc/defaults/auth_unix.conf')) ne '') {
   my ($ret, $err) = ow::tool::load_configfile($_, \%conf);
   die $err if $ret < 0;
}

my $passwdfile_plaintext = $conf{passwdfile_plaintext} || '/etc/passwd';
my $passwdfile_encrypted = $conf{passwdfile_encrypted} || '/etc/master.passwd';
my $passwdmkdb           = $conf{passwdmkdb}           || '/usr/sbin/pwd_mkdb';

my $check_expire     = $conf{check_expire}     || 'no';
my $check_nologin    = $conf{check_nologin}    || 'no';
my $check_shell      = $conf{check_shell}      || 'no';
my $check_cobaltuser = $conf{check_cobaltuser} || 'no';
my $change_smbpasswd = $conf{change_smbpasswd} || 'no';

sub get_userinfo {
   #  0 : ok
   # -2 : parameter format error
   # -3 : authentication system/internal error
   # -4 : user does not exist
   my ($r_config, $user) = @_;

   return(-2, 'User is null') if !defined $user || $user eq '';

   my $uid      = '';
   my $gid      = '';
   my $realname = '';
   my $homedir  = '';

   if ($passwdfile_plaintext eq "/etc/passwd") {
      ($uid, $gid, $realname, $homedir)= (getpwnam($user))[2,3,6,7];
   } else {
      if ($passwdfile_plaintext =~ m/\|/) {
         # maybe NIS, try getpwnam first
         ($uid, $gid, $realname, $homedir) = (getpwnam($user))[2,3,6,7];
      }

      if (!defined $uid || $uid eq '') {
         # else, open file directly
         ($uid, $gid, $realname, $homedir) = (getpwnam_file($user, $passwdfile_plaintext))[2,3,6,7];
      }
   }

   return(-4, "User $user does not exist") if !defined $uid || $uid eq '';

   # get other gid for this user in /etc/group
   while (my @gr = getgrent()) {
      $gid .= ' ' . $gr[2] if $gr[3] =~ m/\b$user\b/ && $gid !~ m/\b$gr[2]\b/;
   }

   # use 1st field for realname
   $realname = (split(/,/, $realname))[0];

   # guess real homedir under sun's automounter
   $homedir = "/export$homedir" if -d "/export$homedir";

   $uid      = defined $uid      ? $uid      : '';
   $gid      = defined $gid      ? $gid      : '';
   $realname = defined $realname ? $realname : '';
   $homedir  = defined $homedir  ? $homedir  : '';

   return (0, '', $realname, $uid, $gid, $homedir);
}

sub get_userlist {
   # only used by openwebmail-tool.pl -a
   #  0 : ok
   # -1 : function not supported
   # -3 : authentication system/internal error
   my $r_config = shift;

   my @userlist = ();

   if (-f $passwdfile_plaintext) {
      # a file should be locked only if it is local accessable
      ow::filelock::lock($passwdfile_plaintext, LOCK_SH) or
         return (-3, "Could not get read lock on $passwdfile_plaintext", @userlist);
   }

   open(PASSWD, $passwdfile_plaintext);

   while (defined(my $line = <PASSWD>)) {
      next if $line =~ m/^#/ || $line =~ m/^\s*$/;
      chomp($line);
      push(@userlist, (split(/:/, $line))[0]);
   }

   close(PASSWD);

   ow::filelock::lock($passwdfile_plaintext, LOCK_UN) if -f $passwdfile_plaintext;

   return (0, '', @userlist);
}

sub check_userpassword {
   #  0 : ok
   # -2 : parameter format error
   # -3 : authentication system/internal error
   # -4 : password incorrect
   my ($r_config, $user, $password) = @_;

   return (-2, "User or password is null") if ($user eq '' || $password eq '');

   # a file should be locked only if it is local accessable
   if (-f $passwdfile_encrypted) {
      ow::filelock::lock($passwdfile_encrypted, LOCK_SH) or
         return (-3, "Could not get read lock on $passwdfile_encrypted");
   }
   if ( ! open(PASSWD, $passwdfile_encrypted) ) {
      ow::filelock::lock($passwdfile_encrypted, LOCK_UN) if ( -f $passwdfile_encrypted);
      return (-3, "Could not open $passwdfile_encrypted");
   }

   my $u      = '';
   my $p      = '';
   my $expire = '';

   # 6 = /etc/master.passwd (*bsd)
   # 7 = /etc/shadow (linux, solaris)
   my $expirefield = $passwdfile_encrypted =~ m/master\.passwd/ ? 6 : 7;

   if ($passwdfile_encrypted =~ m/master\.passwd/) {
      $expirefield = 6; # /etc/master.passwd (*bsd)
   } else {
      $expirefield = 7; # /etc/shadow (linux, solaris)
   }

   while (defined(my $line = <PASSWD>)) {
      next if $line =~ m/^\s*$/;

      chomp($line);

      ($u, $p, $expire) = (split(/:/, $line))[0,1, $expirefield];

      $u      = '' unless defined $u;
      $p      = '' unless defined $p;
      $expire = '' unless defined $expire;

      last if $u eq $user; # We found the user in /etc/passwd
   }

   close(PASSWD);
   ow::filelock::lock($passwdfile_encrypted, LOCK_UN) if -f $passwdfile_encrypted;

   return(-4, "User $user does not exist") if $u ne $user;
   return(-4, "Password incorrect") if crypt($password,$p) ne $p;

   # check expiration
   if ($check_expire=~/yes/i && $expire=~/^\d\d\d\d+$/) {
      # linux/solaris use expire days, *bsd use expire seconds
      $expire*=86400 if ($passwdfile_encrypted!~/master\.passwd/);
      if (time()>$expire) {
         return(-4, "User $user is expired");
      }
   }
   # emulate pam_nologin.so
   if ($check_nologin=~/yes/i && -e "/etc/nologin") {
      return (-4, "/etc/nologin found, all logins are suspended");
   }
   # emulate pam_shells.so
   if ($check_shell=~/yes/i && !has_valid_shell($user)) {
      return (-4, "user $user does not have valid shell");
   }
   # valid user on cobalt ?
   if ($check_cobaltuser=~/yes/i) {
      my $cbhttphost=$ENV{'HTTP_HOST'}; $cbhttphost=~s/:\d+$//;	# remove port number
      my $cbhomedir="/home/sites/$cbhttphost/users/$user";
      if (!-d $cbhomedir) {
         return (-4, "This cobalt user $user does not has homedir $cbhomedir");
      }
   }

   return (0, "");
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($r_config, $user, $oldpassword, $newpassword) = @_;

   my $u         = '';
   my $p         = '';
   my $misc      = '';
   my $encrypted = '';
   my $content   = '';

   return (-2, "User or password is null") if ($user eq '' || $oldpassword eq '' || $newpassword eq '');
   return (-2, "Password too short") if (length($newpassword)<${$r_config}{'passwd_minlen'});

   # a passwdfile could be modified only if it is local accessable
   return (-1, "$passwdfile_encrypted does not exist on local") if (! -f $passwdfile_encrypted);

   ow::filelock::lock($passwdfile_encrypted, LOCK_EX) or
      return (-3, "Could not get write lock on $passwdfile_encrypted");

   if (!open(PASSWD, $passwdfile_encrypted)) {
      ow::filelock::lock($passwdfile_encrypted, LOCK_UN);
      return (-3, "Could not open $passwdfile_encrypted");
   }

   while (defined(my $line = <PASSWD>)) {
      next if $line =~ m/^\s*$/;

      $content .= $line;

      chomp($line);

      ($u, $p, $misc) = split(/:/, $line, 3) if $u ne $user;

      $u    = '' unless defined $u;
      $p    = '' unless defined $p;
      $misc = '' unless defined $misc;
   }

   close(PASSWD);

   if ($u ne $user) {
      ow::filelock::lock($passwdfile_encrypted, LOCK_UN);
      return (-4, "User $user does not exist");
   }

   if (crypt($oldpassword,$p) ne $p) {
      ow::filelock::lock($passwdfile_encrypted, LOCK_UN);
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
      ow::filelock::lock($passwdfile_encrypted, LOCK_UN);
      return (-3, "Unable to match entry for modification");
   }

   my $tmpfile=ow::tool::untaint("$passwdfile_encrypted.tmp.$$.".rand());
   sysopen(TMP, $tmpfile, O_WRONLY|O_TRUNC|O_CREAT) or goto authsys_error;
   print TMP $content or goto authsys_error;
   close(TMP) or goto authsys_error;

   if ($passwdmkdb ne "" && $passwdmkdb ne "none" ) {
      # disable $SIG{CHLD} temporarily for system() return value
      # local $SIG{CHLD}; undef $SIG{CHLD};	# already done in auth.pl

      # update passwd and db with pwdmkdb program
      if ( system("$passwdmkdb $tmpfile")!=0 ) {
         goto authsys_error;
      }
   } else {
      # automic update passwd by rename
      my ($fmode, $fuid, $fgid) = (stat($passwdfile_encrypted))[2,4,5];
      chown($fuid, $fgid, $tmpfile);
      chmod($fmode, $tmpfile);
      rename($tmpfile, $passwdfile_encrypted) or goto authsys_error;
   }
   ow::filelock::lock($passwdfile_encrypted, LOCK_UN);

   if ($change_smbpasswd=~/yes/i) {
      change_smbpasswd($user, $newpassword);
   }
   return (0, "");

authsys_error:
   unlink($tmpfile);
   ow::filelock::lock($passwdfile_encrypted, LOCK_UN);
   return (-3, "Unable to write $passwdfile_encrypted");
}


########## misc support routine ##################################

# this routine is slower than system getpwnam() but can work with file
# other than /etc/passwd. ps: it always return '*' for passwd field.
sub getpwnam_file {
   my ($user, $passwdfile_plaintext) = @_;

   my $name   = '';
   my $passwd = '';
   my $uid    = '';
   my $gid    = '';
   my $gcos   = '';
   my $dir    = '';
   my $shell  = '';

   return('', '', '', '', '', '', '', '', '') if $user eq '';

   open(PASSWD, $passwdfile_plaintext);

   while(defined(my $line = <PASSWD>)) {
      next if $line =~ m/^#/ || $line =~ m/^\s*$/;

      chomp($line);

      ($name, $passwd, $uid, $gid, $gcos, $dir, $shell) = split(/:/,$line);

      $name   = '' unless defined $name;
      $passwd = '' unless defined $passwd;
      $uid    = '' unless defined $uid;
      $gid    = '' unless defined $gid;
      $gcos   = '' unless defined $gcos;
      $dir    = '' unless defined $dir;
      $shell  = '' unless defined $shell;

      last if $name eq $user;
   }

   close(PASSWD);

   if ($name eq $user) {
      return($name, '*', $uid, $gid, 0, '', $gcos, $dir, $shell);
   } else {
      return('', '', '', '', '', '', '', '', '');
   }
}

sub has_valid_shell {
   my $user=$_[0];

   my ($name, $shell);
   if ($passwdfile_plaintext eq "/etc/passwd") {
      $shell = (getpwnam($user))[8];
   } else {
      if ($passwdfile_plaintext=~/\|/) { # maybe NIS, try getpwnam first
         ($name, $shell)= (getpwnam($user))[0,8];
      }
      if ($name eq "") { # else, open file directly
         ($name, $shell) = (getpwnam_file($user, $passwdfile_plaintext))[0,8];
      }
   }
   return 0 if ($shell eq '');

   my $validshell = 0;
   if (open(ES, "/etc/shells")) {
      while(<ES>) {
         chomp;
         if( $shell eq $_ ) {
            $validshell = 1; last;
         }
      }
      close(ES);
   }
   return 0 if (!$validshell);

   return 1;
}

sub change_smbpasswd {
   my $user=ow::tool::untaint($_[0]);
   my $newpassword=$_[1];
   return 0 if ($user=~/[^A-Za-z0-9_\.\-]/);

   foreach ( '/usr/local/bin/smbpasswd',
             '/usr/bin/smbpasswd') {
      my $cmd=$_; $cmd=ow::tool::untaint($cmd);
      if (-x $cmd) {
         open(P, "|-") or
           do { open(STDERR, ">/dev/null"); exec($cmd, "-L", "-a", "-s", "$user"); exit 9 };
         print P "$newpassword\n$newpassword\n";
         close(P) || return 0;	# broken child pipe?
         return 0 if ($?>>8);	# abnormal exit?
         return 1;
      }
   }
   return 0;
}

1;
