package openwebmail::auth_vdomain;
use strict;
#
# auth_vdomain.pl - authenticate virtual user on vm-pop3d+postfix system
#
# 2003/03/03 tung@turtle.ee.ncku.edu.tw
#

# This module is used to authenticate users of virtual domain on system running
# vm-pop3d and postfix. These user won't have any unix account on the server, 
# they are mail only users.
#
# This module has the following assumptions:
#
# 1. the virtual user have to login openwebmail with USERNAME@VIRTUALDOMAIN
# 2. passwd file for each virtual domain is /etc/virtual/VIRTUALDOMAIN/passwd
# 3. mailspool   for each user           is /var/spool/virtual/VIRTUALDOMAIN/USERNAME
# 4. homedir     for each user           is $config{ow_usersdir}/USERNAME@VIRTUALDOMAIN

# Configure PostFix 
# -----------------
# Assume postfix conf is located at /etc/postfix
# and we want to set 2 virtual domains: sample1.com and sample2.com
# and we have users sysadm@sample1.com, sysadm@sample2.com
#
# 1. put the following option in /etc/postfix/main.cf
#
#    virtual_maps=hash:/etc/postfix/virtual
#    alias_maps=hash:/etc/postfix/alias, $alias_database
#    default_privs=nobody
#
# ps: if your postfix is 2.00 or above
#     use virtual_alias_maps instead of virtual_maps in the above 
#
# 2. put the virtual user mapping in /etc/postfix/virtual
#    to map an email address to a virtual user
#
#    sample1.com		# any notes for sample1.com
#    sample2.com		# any notes for sample2.com
#    sysadm@sample1.com		sysadm.sample1.com
#    sysadm@sample2.com		sysadm.sample2.com
#
#    then run 'cd /etc/postfix/; postmap virtual'
#
# ps: the first two lines of the virtual domain are required for postfix 
#     style virtual domain, please refer to man page virtual.5 for more detail
#
# 3. put the alias mapping in /etc/postfix/aliases
#    to redirect mails for the virtual user to related mailbox
#
#    sysadm.sample1.com:	/var/spool/virtual/sample1.com/sysadm
#    sysadm.sample2.com:	/var/spool/virtual/sample2.com/sysadm
#
#    then run 'cd /etc/postfix/; postalias aliases'
#
# ps: When postfix creating the mailbox for a virtual user,
#     the gid of this mailbox will be 'mail' and 
#     the uid will be determined by the following order:
#
#  a. if the alias.db (created by 'postalias alias') is owned by user other than root,
#     then the owner uid will be used
#  b. if alias.db is owned by root,
#     then the uid of the user defined in option default_privs in main.cf will be used.
#
#  Since alias.db is owned by root in most case and 
#  option default_privs in main.cf is defined to 'nobody',
#  the virtual user mailbox will be owned by uid 'nobody' and gid 'mail'.

# Configure vm-pop3d 
# ------------------
# Assume vm-pop3s is installed in /usr/local/sbin/vm-pop3d)
#
# 1. if you are using inetd, put the following line in /etc/inetd.conf
#
# pop3	stream	tcp	nowait	root	/usr/local/sbin/vm-pop3d	vm-pop3d -u nobody
#
# 2. if you are using xinetd, create /etc/xinetd.d/vmpop3 with following content
#
# service pop3
#     {
#             socket_type     = stream
#             protocol        = tcp 
#             wait            = no  
#             user            = root
#             instances       = 25
#             server          = /usr/local/sbin/vm-pop3d
#             server_args     = -u nobody
#             log_type        = SYSLOG local4 info
#             log_on_success  = PID HOST EXIT DURATION
#             log_on_failure  = HOST ATTEMPT
#             disable         = no
#     }
#
# ps: if the pop3 client login as username,
#     vm-pop3d will query /etc/passwd for authentication.
#     if the pop3 client login as username@virtualdomain
#     vm-pop3d will query /etc/virtual/virtualdomain/passwd for authentication
#
#     And the -u nobody is to tell vm-pop3d to use euid nobody 
#     while accessing the mailbox of virtual users

# Configure Open WebMail
# ----------------------
# For each virtual domain,creat per domain conf file 
# ($config{ow_siteconfdir}/VIRTUALDOMAIN) with the following options
#
# auth_module		auth_vdomain.pl
# auth_withdomain	yes
# mailspooldir		/var/spool/virtual/VIRTUALDOMAIN
# use_syshomedir	no
# use_homedirspools	no
# enable_autoreply	no
# enable_setforward	no
# enable_vdomain		yes
# vdomain_admlist		sysadm, john
# vdomain_maxuser		100
# vdomain_vmpop3_pwdpath	/etc/virtual
# vdomain_vmpop3_pwdname	passwd
# vdomain_vmpop3_mailpath	/var/spool/virtual
# vdomain_postfix_aliases	/etc/postfix/aliases
# vdomain_postfix_virtual	/etc/postfix/virtual
# vdomain_postfix_postalias	/usr/sbin/postalias
# vdomain_postfix_postmap	/usr/sbin/postmap
# 
# ps: vdomain_admlist defines the users who can create/delete/modify accounts 
#     of this virtual domain in openwebmail

# create domain specific directory and files
# ------------------------------------------
# 1. mkdir /etc/virtual
#    mkdir /var/spool/virtual
#
# 2. for each virtual domain
#
#    a. create domain passwd file
#       mkdir     /etc/virtual/DOMAIN
#       touch     /etc/virtual/DOMAIN/passwd
#       chmod 644 /etc/virtual/DOMAIN/passwd
#
#    b. create domain mailspool dir so user mailbox can be created under it.
#       mkdir        /var/spool/virtual/DOMAIN
#       chown nobody /var/spool/virtual/DOMAIN
#       chgrp mail   /var/spool/virtual/DOMAIN
#
# 3. add user 'sysadm' to the virtual domain password file
#
#    htpasswd /etc/virtual/DOMAIN/passwd sysadm

# change the user for all virtual domain mails
# ---------------------------------------------
# If you wish to use other username, eg: vmail, 
# instead of 'nobody' for the virtual domain mails
#
# 1. set default_privs=vmail in postfix main.cf
# 2. use '-u vmail' for vmpop3d
# 3  chown vmail /var/spool/virtual/DOMAIN
# 4. set $localuid to getpwnam('vmail');
# 5. if you wish to use homdir of 'vmail' for all virtual domain mails,
#    a. set 'use_syshomedir yes' in openwebmail per domain conf.
#    b. create vmail homedir with vmail uid, gid
#    c. then homedir for virtual user will be vmail_homedir/VIRTUALDOMAIN/USERNAME

# That's all! Now you can
#
# 1. send mail to sysadm@sample1.com and sysadm@sample2.com
# 2. login openwebmail with username=sysadm@sample1.com or sysadm@sample2.com
# 3. click the  'Virtual Domain management' button in user preference,
#    then add/delete virtual users in the same virtual domain

# use nobody for all virtual users mailbox by default
my $local_uid=getpwnam('nobody');

################### No configuration required from here ###################

use Fcntl qw(:DEFAULT :flock);
require "filelock.pl";

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : user doesn't exist
sub get_userinfo {
   my ($r_config, $user_domain)=@_;
   return(-2, 'Not valid user@domain format') if ($user_domain !~ /(.+)[\@:!](.+)/);
   my ($user, $domain)=($1, $2);

   my ($uid, $gid, $realname, $homedir) = (getpwuid($local_uid))[2,3,6,7];
   return(-4, "User $user_domain doesn't exist") if ($uid eq "");

   my $domainhome="$homedir/$domain";
   if ( ${$r_config}{'use_syshomedir'} && -d $homedir) {	
      # mkdir domainhome so openwebmail.pl can create user homedir under this domainhome
      if (! -d $domainhome) {
         my $mailgid=getgrnam('mail');
         ($domainhome =~ /^(.+)$/) && ($domainhome = $1);	# untaint...
         mkdir($domainhome, 0750);
         return(-3, "Couldn't create domain homedir $domainhome") if (! -d $domainhome);
         chown($uid, $mailgid, $domainhome);
      }
   }
   return(0, '', $user, $uid, $gid, "$domainhome/$user");
}


#  0 : ok
# -1 : function not supported
# -3 : authentication system/internal error
sub get_userlist {	# only used by openwebmail-tool.pl -a
   my $r_config=$_[0];

   my @userlist=();
   my $line;
   foreach my $domain (vdomainlist($r_config)) {
      my $pwdfile="${$r_config}{'vdomain_vmpop3_pwdpath'}/$domain/${$r_config}{'vdomain_vmpop3_pwdname'}";

      filelock($pwdfile, LOCK_SH) or
         return (-3, "Couldn't get read lock on $pwdfile");
      if (! open(PASSWD, $pwdfile)) {
         filelock($pwdfile, LOCK_UN);
         return (-3, "Couldn't get open $pwdfile");
      }
      while (defined($line=<PASSWD>)) {
         next if ($line=~/^#/);
         chomp($line);
         push(@userlist, (split(/:/, $line))[0]."\@$domain");
      }
      close(PASSWD);
      filelock($pwdfile, LOCK_UN);
   }
   return(0, '', @userlist);
}


#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($r_config, $user_domain, $password)=@_;
   return (-2, "User or password is null") if (!$user_domain||!$password);
   return (-2, 'Not valid user@domain format') if ($user_domain !~ /(.+)[\@:!](.+)/);
   my ($user, $domain)=($1, $2);

   my $pwdfile="${$r_config}{'vdomain_vmpop3_pwdpath'}/$domain/${$r_config}{'vdomain_vmpop3_pwdname'}";
   return (-4, "Passwd file $pwdfile doesn't exist") if (! -f $pwdfile);

   filelock($pwdfile, LOCK_SH) or
      return (-3, "Couldn't get read lock on $pwdfile");
   if ( ! open (PASSWD, $pwdfile) ) {
      filelock($pwdfile, LOCK_UN);
      return (-3, "Couldn't open $pwdfile");
   }
   my ($line, $u, $p);
   while (defined($line=<PASSWD>)) {
      chomp($line);
      ($u, $p) = (split(/:/, $line))[0,1];
      last if ($u eq $user); # We've found the user in virtual domain passwd file
   }
   close (PASSWD);
   filelock($pwdfile, LOCK_UN);

   return(-4, "User $user_domain doesn't exist") if ($u ne $user);
   return(-4, "Password incorrect") if (crypt($password,$p) ne $p);
   return (0, '');
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($r_config, $user_domain, $oldpassword, $newpassword)=@_;
   return (-2, "User or password is null") if (!$user_domain||!$oldpassword||!$newpassword);
   return (-2, 'Not valid user@domain format') if ($user_domain !~ /(.+)[\@:!](.+)/);
   my ($user, $domain)=($1, $2);

   my $pwdfile="${$r_config}{'vdomain_vmpop3_pwdpath'}/$domain/${$r_config}{'vdomain_vmpop3_pwdname'}";
   return (-4, "Passwd file $pwdfile doesn't exist") if (! -f $pwdfile);

   my ($u, $p, $encrypted);
   my $content="";
   my $line;

   filelock($pwdfile, LOCK_EX) or
      return (-3, "Couldn't get write lock on $pwdfile");
   if ( ! open (PASSWD, $pwdfile) ) {
      filelock($pwdfile, LOCK_UN);
      return (-3, "Couldn't open $pwdfile");
   }
   while (defined($line=<PASSWD>)) {
      $content .= $line;
      chomp($line);
      ($u, $p) = split(/:/, $line) if ($u ne $user);
   }
   close (PASSWD);

   if ($u ne $user) {
      filelock("$pwdfile", LOCK_UN);
      return (-4, "User $user_domain doesn't exist");
   }
   if (crypt($oldpassword,$p) ne $p) {
      filelock("$pwdfile", LOCK_UN);
      return (-4, "Incorrect password");
   }

   my @salt_chars = ('a'..'z','A'..'Z','0'..'9');
   my $salt = $salt_chars[rand(62)] . $salt_chars[rand(62)];
   if ($p =~ /^\$1\$/) {	# if orig encryption is MD5, keep using it
      $salt = '$1$'. $salt;
   }
   $encrypted= crypt($newpassword, $salt);

   my $oldline="$u:$p";
   my $newline="$u:$encrypted";
   if ($content !~ s/\Q$oldline\E/$newline/) {
      filelock("$pwdfile", LOCK_UN);
      return (-3, "Unable to match entry for modification");
   }

   open(TMP, ">$pwdfile.tmp.$$") || goto authsys_error;
   print TMP $content || goto authsys_error;
   close(TMP) || goto authsys_error;

   # automic update passwd by rename
   my ($fmode, $fuid, $fgid) = (stat($pwdfile))[2,4,5];
   chown($fuid, $fgid, "$pwdfile.tmp.$$");
   chmod($fmode, "$pwdfile.tmp.$$");
   rename("$pwdfile.tmp.$$", $pwdfile) || goto authsys_error;

   filelock("$pwdfile", LOCK_UN);
   return (0, '');

authsys_error:
   unlink("$pwdfile.tmp.$$");
   filelock("$pwdfile", LOCK_UN);
   return (-3, "Unable to write $pwdfile");
}


################### misc support routine ###################
# use flock since what we modify here are local system files
sub filelock () {
   return(openwebmail::filelock::flock_lock(@_));
}

sub vdomainlist {
   my $r_config=$_[0];
   my (@domainlist, $dir);
   opendir (D, ${$r_config}{'vdomain_vmpop3_pwdpath'});
   while (defined($dir=readdir(D))) {
      next if ($dir eq "." || $dir eq "..");
      # does domain passwd  file exist?
      if ( -f "${$r_config}{'vdomain_vmpop3_pwdpath'}/$dir/${$r_config}{'vdomain_vmpop3_pwdname'}" ) {
         push(@domainlist, $dir);
      }
   }
   closedir(D);
}

1;
