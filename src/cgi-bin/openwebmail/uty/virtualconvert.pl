#!/usr/bin/perl
#
#  virtualconvert.pl - convert a local domain real user to a virtual user
#
# 2003-06-02   Scott A. Mazur, scott@littlefish.ca
#
#  This script converts a Linux (unix?) real user into a virtual user under the 
#  Openwebmail-Postfix-vdomain setup.
#
#  The user password entry is copied to the virtual domain password file and optionally
#    deleted from the real password file.
#  The user home direcory is copied to the virtual domain directory and optionally deleted
#    from the real user home.
#  The user mail spool is copied to the virtual domain mail spool and optionally deleted
#    from the real user mail spool.
#  The user aliases are removed from the Postfix aliases file and created as virtual entries
#    in the Postfix virtual file.
#  The user is removed from the /etc/openwebmail.conf 'localusers' parameter list.
#
#  There are 2 command line arguments which can be used together, separate, or not at all:
#
#    notest - By default this script runs in test mode.  No file changes are made and all changes that would be
#                   made are reported only.  This is a safety feature.  When you're satisfied that the script will operate as 
#                   expected then add the 'notest' argument to the command line.
#
#    dryrun - This is the same as 'notest' only, the Postfix aliases and virtual files are first copied to test files (aliases.test and
#                   virtual.test respectively).  The conversion runs against the test Postfix files.  Thus all the user home/spool directories
#                   are copied, .forward is files are converted, the virtual password is setup but the Postfix config files are untouched.
#                   This is about as much as you can do without actually committing yourself to a final conversion.
#
#          ( The 'dryrun' option automatically enables 'notest' and disables 'delete' )
#
#    delete - This deletes the real user passwd entry, home directory, and spool file after conversion.
#                   This is leaves an easy way to recover should something go wrong.  Don't use this
#                   unless you're sure you want to completely remove the old real user.  You can run this script
#                   a second time with the 'delete' option to clean up users at a later time.
#                        
#  Requires ( OW 2.01 release 20030605 or better to work )
#
#  !! NOTE !!
#  This script must be run as root.  User directories and files may be deleted, Postfix aliases and
#  virtual files may be updated and the /etc/openwebmail.conf may be modified.
#
#  There is no file locking.  If conversion users are logged in (both locally or through OW), changing passwords, or
#  otherwise changing stuff,  files may get confused.  It's probably not as bad as all that, but you should be aware of it. 
#
#  You should stop the Postfix mail server before running this script with 'notest'.  Otherwise,
#  any incoming mail during the conversion might be sent to the wrong spool and not be copied.
#
#  There is a real risk that any in-comming email to a conversion user may get lost or bounced
#  during the conversion.
#
#  You should have OpenWebmail configured and running correctly before trying this script.
#  In particular, you should have OW configured correctly for both real and virtual users in the same
#  local domain as per the  virtualsetup.pl script. 
#
#  Local users are taken from the /etc/openwebmail.conf 'localusers' parameter list.  If they don't exist
#  here, they will not be converted.  So make sure this config parameter is up to date.
#
#  There are several variables which must be setup according to your site.  Be sure change
#   these before running the script.
#
#  USE AT YOUR OWN RISK!
#  No warranty, No guarantee, and by all means make backups first.
#
#  Comments, questions to scott@littlefish.ca
#

use strict;

# Change these values for your site.
#################################################################
# some of these values can be found in your existing openwebmail.conf file

# this is the local domain that will be setup for both real and virtual users
#my $domain = 'mydomain.com';
my $domain = 'littlefish.ca';

# this is the OpenWebmail etc directory
my $ow_cgi = '/var/www/cgi-bin/openwebmail';

# this is the list of users which will NOT be converted to virtual domain users.
# note - root is added to this list by default
my @exclude=();

# commands used in this script
# if your system does not have these equivalent commands, you'll need to make changes
my $userdel='/usr/sbin/userdel';
my $chown='/bin/chown';
my $cp='/bin/cp';

# you shouldn't have to modify anything below here
#################################################################
# main script
use File::Path;

chdir $ow_cgi;
push (@INC, $ow_cgi);
require "modules/tool.pl";

my (%config);
my $dryrun=0;
my $notest=0;
my $deletereal=0;

# taken from ow-shared.pl
##############################
########## DOTDIR RELATED ########################################
use vars qw(%_is_dotpath);
foreach (qw(
   openwebmailrc release.date history.log
)) { $_is_dotpath{'root'}{$_}=1; }
foreach (qw(
   filter.book filter.check
   from.book address.book stationery.book
   trash.check search.cache signature
)) { $_is_dotpath{'webmail'}{$_}=1; }
foreach (qw(
   calendar.book notify.check
)) { $_is_dotpath{'webcal'}{$_}=1; }
foreach (qw(
   webdisk.cache
)) { $_is_dotpath{'webdisk'}{$_}=1; }
foreach (qw(
   pop3.book pop3.check authpop3.book
)) { $_is_dotpath{'pop3'}{$_}=1; }

# This _ version of routine is used by dotpath() and openwebmail-vdomain.pl
# When vdomain adm has to determine dotpath for vusers,
# the param of vuser($vdomain, $vuser, $vhomedir) will be passed
# instead of the globals($domain, $user, $homedir), which are param of vdomain adm himself
sub _dotpath {
   my ($name, $domain, $user, $homedir)=@_;
   my $dotdir;
   if ($config{'use_syshomedir_for_dotdir'}) {
      $dotdir = "$homedir/$config{'homedirdotdirname'}";
   } else {
      my $owuserdir = "$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user);
      $dotdir = "$owuserdir/$config{'homedirdotdirname'}";
   }
   return(ow::tool::untaint($dotdir)) if ($name eq '/');

   return(ow::tool::untaint("$dotdir/$name"))         if ($_is_dotpath{'root'}{$name});
   return(ow::tool::untaint("$dotdir/webmail/$name")) if ($_is_dotpath{'webmail'}{$name} || $name=~/^filter\.book/);
   return(ow::tool::untaint("$dotdir/webcal/$name"))  if ($_is_dotpath{'webcal'}{$name});
   return(ow::tool::untaint("$dotdir/webdisk/$name")) if ($_is_dotpath{'webdisk'}{$name});
   return(ow::tool::untaint("$dotdir/pop3/$name"))    if ($_is_dotpath{'pop3'}{$name} || $name=~/^uidl\./);

   $name=~s!^/+!!;
   return(ow::tool::untaint("$dotdir/$name"));
}

foreach ( @ARGV ) {
  if ( /^dryrun$/i ) { $dryrun = 1 }
  if ( /^delete$/i ) { $deletereal = 1 }
  if ( /^notest$/i ) { $notest = 1 }
}

if ($dryrun){ $notest=1; $deletereal=0 }
my $test=!$notest;

print "virtualconvert.pl\n";

my ($ss, $mm, $hh, $dd, $mon, $yy) = localtime;$mon++;$yy-=100;
my $stamp=sprintf("%02d-%02d-%02d.%02d.%02d.%02d",$yy,$mon,$dd,$hh,$mm,$ss);

# clean up exclude users
my %ex;$ex{'root'}=1;
foreach (@exclude) {
   s/@.*//;s/^\s*//;s/\s*$//;
   $ex{$_}=1 if (! /^$/);
}

# get default config file
my ($ret,$err)=ow::tool::load_configfile("$ow_cgi/etc/openwebmail.conf.default", \%config);
ABORT($!) if ( $ret<0 );

print "Found Openwebmail version $config{'version'}  releasedate $config{'releasedate'}\n";

# verify version
ABORT(  "Mixing virtual and real users on the same domain requires Openwebmail version 2.01 release 20030605 or newer.") if ( $config{'releasedate'} < 20030605 );

# get the local config file
my ($ret,$err)=ow::tool::load_configfile("$ow_cgi/etc/openwebmail.conf", \%config);
ABORT($!) if ( $ret<0 );

ABORT(  "The main config file is already using auth_module 'auth_vdomain.pl'.  Real and virtual users can't be mixed here.") if ( $config{'auth_module'} eq 'auth_vdomain.pl' );

# fill out config values
foreach (keys %config) { while ( $config{$_}=~/%(\S+)%/ ) { my $parm=$1; $config{$_}=~s/\%$parm\%/$config{$parm}/g } }

my $mailspooldir=$config{'mailspooldir'};

my $localusers=$config{'localusers'} ;

my $siteconf="$config{'ow_sitesconfdir'}\/$domain";
ABORT("There is no $siteconf file.") if (! -e $siteconf);
my ($ret,$err)=ow::tool::load_configfile($siteconf, \%config);
ABORT($!) if ( $ret<0 );

ABORT("The site config file is not using auth_module 'auth_vdomain.pl'.  Real and virtual users can't be mixed here.") if ( $config{'auth_module'} ne 'auth_vdomain.pl' );

# fill out siteconf values
foreach (keys %config) { while ( $config{$_}=~/%(\S+)%/ ) { my $parm=$1; $config{$_}=~s/\%$parm\%/$config{$parm}/g } }

my $pwddir="$config{'vdomain_vmpop3_pwdpath'}\/$domain";
my $pwdfile="$pwddir/$config{'vdomain_vmpop3_pwdname'}";
my ($postfix_aliases_file) = split(/[ ,]+/, $config{'vdomain_postfix_aliases'});
my ($postfix_virtual_file) = split(/[ ,]+/, $config{'vdomain_postfix_virtual'});

print " - running in dryrun mode (no updates to Postfix, no delete real users)\n\n" if ( $dryrun );
print " - running in test mode (no updates)\n" if ( $test );
print " - delete real users when done\n" if ( $deletereal );

if ($dryrun){
   CMD("copy $postfix_aliases_file to $postfix_aliases_file.test", "$cp -fp $postfix_aliases_file $postfix_aliases_file.test");
   $postfix_aliases_file="$postfix_aliases_file.test";
   CMD("copy $postfix_virtual_file to $postfix_virtual_file.test", "$cp -fp $postfix_virtual_file $postfix_virtual_file.test");
   $postfix_virtual_file="$postfix_virtual_file.test";
}

my $Postfixreload = $config{'vdomain_postfix_postalias'};
$Postfixreload=~s/postalias$/Postfix reload/;

# read all Postfix aliases
my (%aliases, @aliasfile);
foreach ( READFILE($postfix_aliases_file) ){
   push @aliasfile, $_;
   s/^\s+//;s/\s+$//;
   $aliases{$1}=$2 if( ! /^#/ and /^(\S+)\s*:\s*(.+)$/ );
}
# compact the aliases of aliases
foreach (keys %aliases) {
   my $brkloop=500; # carefull of alias loops!
   while ($aliases{$aliases{$_}} and $aliases{$_} ne $aliases{$aliases{$_}} and $brkloop) { $brkloop--; $aliases{$_}=$aliases{$aliases{$_}} }
   ABORT( "Alias $_ is stuck in an alias loop.") if (! $brkloop);
}

# create reverse user to alias mapping
my %raliases; foreach (keys %aliases) {push @{$raliases{$aliases{$_}}},$_}

# read all Postfix virtual users (for local domain)
my (%virtual, @virtualfile);
foreach ( READFILE($postfix_virtual_file) ){
   push @virtualfile, $_;
   s/^\s+//;s/\s+$//;
   $virtual{$1}=$2 if( ! /^#/ and /^([^\s@]+)\@$domain\s+(.+)$/ );
}

# compact the virtual aliases of virtual aliases
foreach (keys %virtual) {
   my $brkloop=500; # carefull of alias loops!
   my $map=$virtual{$_}; $map=~s/\.$domain$/\@$domain/;
   while ($virtual{$map} and $brkloop) { $brkloop--; $virtual{$_}=$virtual{$map}; $map=$virtual{$_}; $map=~s/\.$domain$/\@$domain/; }
   ABORT( "Virtual alias $_ is stuck in an alias loop.") if (! $brkloop);
}

my @virtusers = sort (READVIRTPASS());  # existing virtual users

if (keys %ex) {print "\nExclude users:\n";foreach(sort keys %ex){print"  $_\n"};}

print "\n";

my (%realuser,%convert,%keep);
# clean up local users
my $flg=0;
foreach ( split( /[,;\s]+/, $localusers ) ) {
   s/@.*//;s/^\s*//;s/\s*$//;
   next if ( /^$/ );
   if ( $ex{$_} ) {$keep{$_}=1}
   else {
      if ( $aliases{$_}=~/[\/\|"'@,\s]/ ) {
         print "Fishy aliases entry user $_ aliases entry: $aliases{$_}\n!! User $_ excluded from conversion\n";
         $keep{$_}=1; $flg=1; next;
      }
      my ($pass,$home)=(getpwnam($_))[1,7];
      if ( ! $home) {
         print "Real user $_ not found.  User $_ excluded from conversion\n";
         $flg=1; next;
      }
      ($realuser{$_}{'passwd'},$realuser{$_}{'home'})=($pass,$home);
      $convert{$_}=1;
   }
}
print "\n" if ($flg);

# convert these users
if (keys %convert) {
   my @users=sort keys %convert;
   my ($homedir,$uid,$gid)=MAKE_DOMDIR(); # get the current working environment for virtual users

   # This is the safest way I can think of to convert users without disruption.
   # update openwebmail.conf - this will stop webmail users from logging in with their old real accounts
   # remove the password file entries - this will stop real user from logging in directly and mail from going to user real spool
   # remove Postfix aliases entries - this will stop mail aliases from going to real user
   # copy home directories and spool files
   # add Postfix virtual and alias entires
   # add virtual passwords.

   BACKUP_POSTFIX();
   UPDT_CONF( keys %keep );
   DEL_REALPASSWD( @users ) if ($deletereal);
   DEL_ALIASES( @users );
   COPY_USERS( $homedir,$uid,$gid, @users );
   ADD_ALIASES( @users );
   ADD_VIRTUAL( @users );
   ADD_VIRTUALPASSWD( @users );
}  else { print "No users to convert\n"; }

# clean up old real users
if ($deletereal) {
   foreach ( @virtusers ) { $convert{$_}=1 } # check ALL virtual users, not just the converted list
   DEL_REALUSERS( sort keys %convert );
}

print "\ndone\n";

exit 0;

###########################################################
sub CMD { my ($text, $cmd)=@_;
   SKIPTXT($text);
   if ($notest) {
      my $result=`$cmd  2>&1`;
      print "WARNING - $result" if ($result);
   }
}
sub BACKUP_POSTFIX {
   # backup the Postfix aliases and virtual files
   print "\n";
   CMD("backup $postfix_aliases_file to $postfix_aliases_file.$stamp.bak", "$cp -fp $postfix_aliases_file $postfix_aliases_file.$stamp.bak");
   CMD("backup $postfix_virtual_file to $postfix_virtual_file.$stamp.bak\n", "$cp -fp $postfix_virtual_file $postfix_virtual_file.$stamp.bak");
}
sub UPDATE_POSTFIX_ALIASES { my (@lines)=@_;
   SKIPTXT("update $postfix_aliases_file");
   UPDATEFILE( $postfix_aliases_file, @lines) if ($notest);
   CMD("rebuild Postfix aliases database", "$config{'vdomain_postfix_postalias'} $postfix_aliases_file");
   @aliasfile=@lines;
   chomp @aliasfile;
}
sub MAKE_DOMDIR {
   ow::tool::loadmodule('main',
                        "$config{'ow_cgidir'}/auth", $config{'auth_module'},
                        "get_userinfo",
                        "get_userlist",
                        "check_userpassword",
                        "change_userpassword");

   # create domain password file, domain home directory
   my ($errcode, $errmsg, $realname, $uid, $gid, $homedir, $dummy, @paths, $new);

   if (@virtusers) { #password file must already exist
      CMD("backup $pwdfile to $pwdfile.$stamp.bak", "$cp -fp $pwdfile $pwdfile.$stamp.bak");
      # use any virtual user to get the proper $uid, $gid and $homedir
      $dummy=$virtusers[0];
      print "Determine virtual user environment from existing user '$dummy'\n";
      ($errcode, $errmsg, $realname, $uid, $gid, $homedir)=get_userinfo( \%config, "$dummy\@$domain" );
   }
   else {
      # create a dummy virtual user to get the proper $uid, $gid and $homedir
      $dummy='dummy';
      my $tuid=getpwnam('nobody');
      my $tgid=getgrnam('mail');
      # create the password file
      $new=0;
      if (! -e $pwdfile) {
         $new=1;
         @paths=NEWDIR( $pwddir, $tuid, $tgid, 0710, 'virtual domain passwd' ) if ($notest);
      }

      SKIPTXT("  create virtual password file $pwdfile with temporary dummy user");
      if ($test) { $uid=$tuid;$gid=$tgid;$homedir="$config{'ow_usersdir'}\/$domain/$dummy"; }
      else {
         WRITEFILE( $pwdfile, 0, $tgid, 0660, ("$dummy:dummy:\n") );
         ($errcode, $errmsg, $realname, $uid, $gid, $homedir)=get_userinfo(\%config, "$dummy\@$domain");
      }

      if ($new) {
         if ($errcode) {
            SKIPTXT("remove temporary password file");
            if ($notest) {
               if (@paths){
                  ABORT("failed to delete ${paths[0]} $!") if ( ! rmtree( $paths[0] ) );
               } else {
                  ABORT("failed to delete $pwdfile $!") if ( ! rmtree( $pwdfile ) );
               }
            }
         } else {
            if ( $tuid ne $uid or $tgid ne $gid and @paths ) {
               SKIPTXT("  correct the virtual password domain owner");
               SETFILESTAT( $uid, $gid, 0710, @paths ) if ($notest);
            }
            SKIPTXT("  remove the temporary virtual user");
            WRITEFILE( $pwdfile, 0, $gid, 0660, ("#  virtual domain $domain\n") ) if ($notest);
         }
      }
   }
   ABORT( "Couldn't determine virtual user environment.  Error code: $errcode $errmsg." ) if ($errcode);
   $homedir=~s/\/$dummy$//;
   $homedir="$config{'ow_usersdir'}\/$domain" if ( ! $config{'use_syshomedir'} );
   NEWDIR( $homedir, $uid, $gid, 0710, 'virtual domain home' ) if ($notest);
   NEWDIR( "$config{'vdomain_vmpop3_mailpath'}/$domain", $uid, $gid, 0770, 'virtual domain spool' ) if ($notest);

   print "\nvirtual domain home directory: $homedir\n";
   print "virtual user uid: $uid,  virtual group gid: $gid\n";
   print "( the virtual uid may not be correct in test mode)\n" if ($new and $test);

   return $homedir,$uid,$gid;
}

sub UPDT_CONF { my (@userlist)=@_;
   SKIPTXT("update $ow_cgi/etc/openwebmail.conf with new user list\n");
   return if ($test);

   my $localusers = join("\@$domain, ",(sort @userlist));
   $localusers .= "\@$domain";
   my @lines;
   foreach ( READFILE( "$ow_cgi/etc/openwebmail.conf") ) {
      s/^(\s*localusers\s+)(.*)/$1$localusers/;
      push @lines,"$_\n";
   }
   UPDATEFILE( "$ow_cgi/etc/openwebmail.conf",@lines);
   return;
}

sub DEL_REALPASSWD { my (@users)=@_;
   foreach my $user(@users) {
       CMD("delete passwd $user  $realuser{$user}{'passwd'}:$realuser{$user}{'home'}", "$userdel $user");
   }
}

sub DEL_ALIASES { my (@users)=@_;
   my %aliaslist;
   foreach my $user (@users){
      $aliaslist{$user}=$user;
      if ($raliases{$user}) { foreach (@{$raliases{$user}}) { $aliaslist{$_}=$user }}
   }
   my $chg=0; my @result;
   foreach my $line (@aliasfile) {
      $_=$line;s/^\s+//;s/\s+$//;
      if( ! /^#/ and /^(\S+)\s*:\s*(.+)$/ and $aliaslist{$1} ) {
         $chg=1;
         SKIPTXT("delete aliases $1  (user $aliaslist{$1})");
      } else { push @result,"$line\n"; }
   }
   if ($chg) {
      UPDATE_POSTFIX_ALIASES(@result) if ($chg);
      CMD("reload Postfix", $Postfixreload);
   }
}

sub COPY_USERS { my ($homedir, $uid, $gid, @users)=@_;
   foreach my $user (@users) {
      my $home="$homedir/$user";
      if (-e $realuser{$user}{'home'} ) {
         CMD("copy $user home from $realuser{$user}{'home'} to $home", "$cp -fr $realuser{$user}{'home'} $home");
         CMD("reset $user home permissions", "$chown -R $uid:$gid $home");
      } else {
         NEWDIR( $home, $uid, $gid, 0710, 'virtual user home' ) if ($notest);
      }
      my $spool="$config{'vdomain_vmpop3_mailpath'}/$domain/$user";
      if (-e "$mailspooldir/$user") {
         CMD("copy $user spool from $mailspooldir/$user to $spool", "$cp -fr $mailspooldir/$user $spool");
         SKIPTXT("reset $user spool permissions");
         SETFILESTAT($uid, $gid, 0660,($spool)) if ($notest);
      } else {
         SKIPTXT('create empty virtual user spool file');
         WRITEFILE( $spool, $uid, $gid, 0660 ) if ($notest);
      }

      my $forward="$home/.forward";
      $realuser{$user}{'forward'} = $forward;
      SKIPTXT("convert $user $forward file");
      my @forwards; my $self=0; my $vac=0;
      if (-f $forward){
         my @temp=split(/[,;\n\r]+/, join("\n",READFILE($forward)));
         foreach (@temp) {
            s/^\s+//; s/\s+$//;
            next if ( /^$/ );
            if (/$config{'vacationpipe'}/) { $vac=1; }
            elsif ( /$user\@.*$domain$/i or $_ eq "\\$user" or $_ eq $user) { $self=1; }
            else { push(@forwards, "$_\n"); }
         }
      }
      if ($self or ! $vac) {
         my $dest=$spool;
         if ( $config{'vdomain_mailbox_command'} ne "none" ) {
            $dest = qq!| "$config{'vdomain_mailbox_command'}"!;
            $dest =~ s/<domain>/$domain/g;
            $dest =~ s/<user>/$user/g;
            $dest =~ s/<homedir>/$home/g;
            $dest =~ s/<spoolfile>/$spool/g;
         }
         push(@forwards, "$dest\n");
      }
      if ($vac) {
         my $aliasparm="-a $user\@$domain";
         my $fromsfile=_dotpath('from.book', $domain, $user, $home);
         if (-f $fromsfile) { foreach ( READFILE($fromsfile) ) { if ( /^(.+\@$domain)+\@\@\@/ and $1 ne "$user\@$domain"){$aliasparm .= " -a $1"; } } }
         my $vacationuser = "-p$home nobody";
         if (length("xxx$config{'vacationpipe'} $aliasparm $vacationuser")<250) {
            push(@forwards, qq!| "$config{'vacationpipe'} $aliasparm $vacationuser"\n!);
         } else {
            push(@forwards, qq!| "$config{'vacationpipe'} -j $vacationuser"\n!);
         }
      } 
      WRITEFILE($forward,$uid,$gid,0600,@forwards) if ($notest);
   }
}

sub ADD_ALIASES { my (@users)=@_;
   my $hdr=0; my $chg=0; my @result;
   my $hdrtxt="# OW vdomain $domain";
   my @list = ( "# virtual user conversion $domain $stamp\n" );
   foreach my $user (@users){
      SKIPTXT("add alias entry:  $user.$domain:	:include:$realuser{$user}{'forward'}");
      push @list,"$user.$domain:	:include:$realuser{$user}{'forward'}\n";
   }

# add the new users under any existing users

   foreach my $line (@aliasfile) {
      $_=$line;s/^\s+//;s/\s+$//;
      $chg=1 if ($chg<2 and $hdr);
      if ( $chg<2 and /^$hdrtxt/ ) { $hdr=1 }
      if ( ! /^#/ and ! /^$/ ) {
         if( $chg<2 and /^\S+\.$domain\s*:/ ) { $chg=1 }
         elsif ($chg==1) {
            push @result, "\n$hdrtxt\n" if (! $hdr);
            push @result, @list; $chg=2;
         }
      }
      push @result,"$line\n";
   }
   if ($chg<2) {
      push @result, "\n$hdrtxt\n" if (! $hdr);
      push @result, @list;
   }
   UPDATE_POSTFIX_ALIASES(@result);
}

sub ADD_VIRTUAL { my (@users)=@_;
   my $hdr=0; my $chg=0; my @result;
   my $hdrtxt="# OW vdomain $domain";
   my @list = ( "# virtual user conversion $domain $stamp\n" );
   foreach my $user (@users){
      my $vuser="$user\.$domain";
      SKIPTXT("add virtual entry: $user\@$domain	$vuser");
      push @list,"$user\@$domain	$vuser\n";
      if ( $raliases{$user} ) {
         foreach ( @{$raliases{$user}} ) {
            if ($_ ne $user) {
               SKIPTXT( "add virtual alias: $_\@$domain	$vuser" );
               push @list,"$_\@$domain	$vuser\n";
            }
         }
      }
   }
# add the new users under any existing users
   foreach my $line (@virtualfile) {
      $_=$line;s/^\s+//;s/\s+$//;
      $chg=1 if ($chg<2 and $hdr);
      if ( $chg<2 and /^$hdrtxt/ ) { $hdr=1 }
      if ( ! /^#/ and ! /^$/ ) {
         if( $chg<2 and /^\S+\@$domain\s+/ ) { $chg=1 }
         elsif ($chg==1) {
            push @result, "\n$hdrtxt\n" if (! $hdr);
            push @result, @list; $chg=2;
         }
      }
      push @result,"$line\n";
   }
   if ($chg<2) {
      push @result, "\n$hdrtxt\n" if (! $hdr);
      push @result, @list;
   }
   SKIPTXT("update $postfix_virtual_file");
   UPDATEFILE( $postfix_virtual_file, @result) if ($notest);
   CMD("rebuild Postfix virtual database", "$config{'vdomain_postfix_postmap'} $postfix_virtual_file");
   CMD("reload Postfix", $Postfixreload);
}

sub ADD_VIRTUALPASSWD { my (@users)=@_;
   my @lines;
   if (-e $pwdfile) {
      foreach my $line ( READFILE($pwdfile) ) {
         $_=$line;s/^\s+//;s/\s+$//;
         if ( ! /^#/ and /([^:]+):/ and $realuser{$1}{'home'} ) {
            SKIPTXT("remove existing virtual password entry for user $1");
         } else { push @lines, "$line\n"; }
      }
   }
   foreach (@users){
      SKIPTXT("add virtual passwd entry: $_");
      push @lines, "$_:$realuser{$_}{'passwd'}\n";
   }
   UPDATEFILE($pwdfile,@lines) if ($notest);
}

sub DEL_REALUSERS { my (@users)=@_;
   foreach (@users){
      my ($pass,$home)=(getpwnam($_))[1,7];
      ($realuser{$_}{'passwd'},$realuser{$_}{'home'})=($pass,$home) if ($home);
      if ( $home ) { DEL_REALPASSWD($_) }
      elsif (! $realuser{$_}{'home'} ) { print "No real user found for $_\n"; next; }
      if ( -e "$realuser{$_}{'home'}" ) {
         SKIPTXT("delete real user home $realuser{$_}{'home'}");
         ABORT("failed to delete $realuser{$_}{'home'}  $!") if ( $notest and ! rmtree( $realuser{$_}{'home'}  ) );
      }
      if ( -e "$mailspooldir/$_" ) {
         SKIPTXT("delete real user spool $mailspooldir/$_");
         ABORT("failed to delete $mailspooldir/$_  $!") if ( $notest and ! rmtree( "$mailspooldir/$_" ) );
      }
   }
   return;
}

sub ABORT { my ($msg)=@_;
   print "$msg\nScript Aborted.\n";
   exit 1;
}
sub SKIPTXT { my ($msg)=@_;
   if ($test) {print "testmode (no action)  $msg\n"}
   else {print "$msg\n"}
}

sub READVIRTPASS {
   my @users=();
   my $pwdfile="$config{'vdomain_vmpop3_pwdpath'}\/$domain\/$config{'vdomain_vmpop3_pwdname'}";
   if ( -e $pwdfile ) {
      foreach ( READFILE( $pwdfile ) ) {
         push @users,$1 if (! /^\s*#/ and /^\s*([^\s:]+)/ );
      }
   }
   return @users;
}

sub NEWDIR { my ($dir, $uid, $gid, $perm, $desc) = @_;
  my @paths;
  if ( -l $dir ) { $_=readlink($dir); if ( defined ( $_=readlink($dir) ) ){ $dir = $_; } }
  if ( ! -e $dir ) {
    print "create $desc directory: $dir\n";
    if ( @paths = mkpath($dir,0,$perm) ) {
       SETFILESTAT( $uid, $gid, $perm, @paths );
    } else { ABORT( "failed to create $desc directory: $dir $!" ); }
  }
  return @paths;
}

sub SETFILESTAT { my ($uid, $gid, $perm, @paths)=@_;
   foreach (@paths) { chmod $perm,$_; chown $uid,$gid,$_; }
}

sub READFILE { my ($file) = @_;
   ABORT(  "failed to open file: $file $!") if ( ! open( MYFILE, $file ) );
   my @lines = <MYFILE>;
   close MYFILE;
   chomp @lines;
   return @lines;
}

sub WRITEFILE { my ($file, $uid, $gid, $perm, @lines) = @_;
  ABORT( "failed to write file: $file $!") if ( ! open( FILE, ">$file" ) );
  print FILE @lines;
  close FILE;
  chmod $perm,$file;
  chown $uid,$gid,$file;
  return;
}

sub UPDATEFILE { my ($file, @lines) = @_;
  ABORT(  "failed to update file: $file $!" ) if ( ! open( FILE, ">$file" ) );
  print FILE @lines;
  close FILE;
  return;
}

