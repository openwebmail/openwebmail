#!/usr/bin/perl
#
#  fixvuser.pl - fix virtual users
#
# 2003-05-20   Scott A. Mazur, scott@littlefish.ca
#        
#  This script searches through the postfix aliases and virtual files and 
#  updates them according to the new virtual user aliases scheme
#
#  This will modify virtual users created prior to OW 2.01 release 20030520
#  Virtual users are modified as required (and left alone if not).
#  There are several configuration file paths below which should be set as required
#
#  !! NOTE !!
#  This script must be run as root, and it WILL modify the Postfix aliases and virtual files.
#  It will also modify/create virtual user homedirectorie, .forward files and .from .book files
#  as required.
#
#  USE AT YOUR OWN RISK!
#  and by all means make backups first.
#
#  There are two possible parameters you can pass to this script:
#
#  confirm	- Confirm each user change
#  force	- Make the user changes without confirmation
#
#  By default, if neither of the above parameters are passed to the script,
#  it will simply check and report the changes that are required.  I strongly suggest
#  that you run the script without additional parameters first to ensure everything is correct
#
#  As a side effect, if any virtual users are converted, both the aliases and virtual files will
#  Have ALL virtual users sorted and grouped by domain.  Of course, if you don't want that
#  then it's a bad thing and you shouldn't run this script.
#
#  Parsing the OW config files is very crude and simplistic.  Funky config files cause confusion.
#
#  Comments, questions to scott@littlefish.ca
#

use strict;
use File::Path;

# this is the OpenWebmail cgi-bin directory
# it will be scanned for config files to determine
# where the virtual user home directories are

my $ow_cgi = '/var/www/cgi-bin/openwebmail';

# this user to use creating virtual home directories

my $vuser = 'nobody';
#my $vuser = 'virtual';

# this group to use creating virtual home directories

my $vgroup = 'mail';

# you shouldn't have to modify anything below here
#################################################################

chdir $ow_cgi;
push (@INC, $ow_cgi);
require "modules/tool.pl";

my $ow_etc = "$ow_cgi/etc";
my (%config, %site);
my $uid = getpwnam( $vuser ) if ( $vuser !~ /^\d+$/ );
my $gid = getgrnam( $vgroup ) if ( $vgroup !~ /^\d+$/ );
my $tag = "# OW vdomain";

# taken from ow-shared.pl
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

my $parm;
foreach (@ARGV){
   if (/^(confirm|force)$/){ $parm=$_;last }
}

my ($ret,$err)=ow::tool::load_configfile("$ow_cgi/etc/openwebmail.conf.default", \%config);
ABORT($!) if ( $ret<0 );

my ($ret,$err)=ow::tool::load_configfile("$ow_cgi/etc/openwebmail.conf", \%config);
ABORT($!) if ( $ret<0 );

my ($postfix_aliases_file) = split(/[ ,]+/, $config{'vdomain_postfix_aliases'});
my ($postfix_virtual_file) = split(/[ ,]+/, $config{'vdomain_postfix_virtual'});

my $virtualhome=(getpwuid($uid))[7];
$virtualhome=$config{'ow_usersdir'} if (!$config{'use_syshomedir'});

my ($chg, @virtualfile, @aliasesfile);
my ($user, $domain, $alias, $dest);
my ( %virtual, %deletehome, %convertuser, %aliases, %vdomains, %vusers, %valiases );

# parse virtual file
foreach ( READFILE( $postfix_virtual_file ) ) {
   if (/^\s*([^\s#]+)\s+([^\s#]+)/){
      $user=$1; $domain=$2;
      if ( $user=~/^(.+)@(.+)/ ) {
         $virtual{$2}{$1}=$domain;
         $aliases{$domain}=1;
      }
      else { $vdomains{$user}=$domain }
   } else { push @virtualfile, "$_\n" }
}
# clear trailing blank lines
while ( $#virtualfile and $virtualfile[$#virtualfile]=~/^\s*\n$/ ) { pop @virtualfile }

# parse alises file
foreach ( READFILE($postfix_aliases_file) ) {
   next if (/^$tag /);
   if (/^\s*([^\s#:]+)\s*:\s*(.*)/ and $aliases{$1} ) {
      $aliases{$1}=$2;
      next;
   }
   push @aliasesfile, "$_\n";
}
# clear trailing blank lines
while ( $#aliasesfile and $aliasesfile[$#aliasesfile]=~/^\s*\n$/ ) { pop @aliasesfile }

# convert re-directs to virtual aliases
foreach $alias ( keys %aliases ) {
   if ( $aliases{$alias} =~/^(\S+)@(\S+)$/ ) {
      if ( $virtual{$2}{$1} ) {
         $dest=$1;
         $domain=$2;
         $user=$alias;
         if ( $user=~s/\.$domain// and CONFIRM("convert redirect from $user\@$domain to $dest\@$domain into virtual alias") ) {
            $chg=1;
            $virtual{$domain}{$user}="$dest.$domain";
            my $vhome = "$virtualhome/$domain/$user";
            if ( -d $vhome and CONFIRM("  delete user home directory $vhome") and $parm ) {
               if ( ! rmtree( $vhome ) ) { print "failed to delete $vhome $!\nScript aborted\n"; exit 1;}
            }
         }
      }
   }
}

# split main user and alias users
foreach $domain ( keys %vdomains ) {
   foreach ( keys %{$virtual{$domain}} ) {
      if ( $virtual{$domain}{$_} eq "$_.$domain" ) {
         $vusers{$domain}{$_} = $aliases{"$_.$domain"}
      } else {
         $user=$virtual{$domain}{$_};
         if ( $user=~s/\.$domain// ) { push@{$valiases{$domain}{$user}},$_ }
      }
   }
}

my ($warn,%skipdomain, %skipuser);

# rebuild the virtual and aliase files
foreach $domain (sort keys %vdomains ) {
   push @virtualfile, "\n$tag $domain\n$domain	$vdomains{$domain}\n";
   push @aliasesfile, "\n$tag $domain\n";
   foreach $user (sort keys %{$vusers{$domain}} ) {
      push @virtualfile, "$user\@$domain	$user.$domain\n";
      if ( $vusers{$domain}{$user} !~ /:include:.*\/\.forward/ ) {
         if ( CONVERTUSER($virtualhome,$domain,$user,$vusers{$domain}{$user}) ) {
            $vusers{$domain}{$user} = ":include:$virtualhome/$domain/$user/.forward";
            $chg=1;
         }
      }
      push @aliasesfile, "$user.$domain:	$vusers{$domain}{$user}\n";
      if ( $valiases{$domain}{$user} ) {
         UPDATEFROMS($virtualhome,$domain,$user,@{$valiases{$domain}{$user}});
         foreach (sort @{$valiases{$domain}{$user}} ) {
            push @virtualfile, "$_\@$domain	$user.$domain\n";
         }
      }
   }
}

if ( $chg and CONFIRM("update postfix aliases and virtual files") and $parm ) {
   print `cp -fa $postfix_aliases_file $postfix_aliases_file.OWbak`;
   print `cp -fa $postfix_virtual_file $postfix_virtual_file.OWbak`;
   UPDATEFILE($postfix_aliases_file, @aliasesfile);
   UPDATEFILE($postfix_virtual_file, @virtualfile);
   print `$config{'vdomain_postfix_postalias'} $postfix_aliases_file`;
   print `$config{'vdomain_postfix_postmap'} $postfix_virtual_file`;
}

print "\ndone\n";
exit;

###########################################################
sub CONFIRM { my ($msg)=@_;
   print $msg;
   if ( $parm eq 'confirm' ) {
      print " (yes|no)? no";
      my $ans=<STDIN>;
      print "\n" if ( $ans !~ /\n/ );
      return 0 if ( $ans !~/y(es)*/i );
   } else { print "\n" }
   return 1;
}

sub UPDATEFROMS { my ($vhome,$domain,$user,@useraliases)=@_;

   my (%hash,@froms);

   # convert useraliases to hash
   foreach (@useraliases) { $hash{"$_\@$domain"}=$_ }

   my $frombook=_dotpath('from.book', $domain, $user, $vhome);

   if ( -f $frombook ) {
      foreach (READFILE($frombook)) {
         push @froms, "$_\n";
         delete $hash{$1} if (/^(.+)@@@(.+)/ and $hash{$1} );
      }
   }
   if (keys %hash and CONFIRM("  add $user\@$domain aliases to $frombook") ) {
      foreach (sort keys %hash) {
         push @froms, "$_\@\@\@$hash{$_}\n";
      }
      print "  update user from.book file $frombook\n";
      REPLACEFILE($frombook,$uid,$gid, 0600, @froms) if ($parm);
   }
}

sub CONVERTUSER { my ($vhome,$domain,$user,$forward)=@_;
   return 0 if ( ! CONFIRM("convert $user\@$domain to new format") );

   $vhome .= "/$domain";
   # domain root
   if ( ! -d $vhome ) {
      return 0 if ( ! CONFIRM("create domain root $vhome") );
      NEWDIR($vhome,$uid,$gid, 0750) if ($parm);
   }

   $vhome .= "/$user";
   # user home
   if (! -d $vhome ) {
      return 0 if ( ! CONFIRM("create user home $vhome") );
      NEWDIR($vhome, $uid, $gid, 0700) if ($parm);
   }

   # replace the .forward file, don't bother confirming
   # under the old format it was never used, and under
   # the new format it has to change anyway.
   print "  replace .forward file $vhome/.forward\n";
   $forward=~s/^"\| /| "/;
   REPLACEFILE("$vhome/.forward",$uid,$gid, 0600, "$forward\n") if ($parm);

   return 1;
}

sub NEWDIR { my ($dir, $uid, $gid, $perm) = @_;
  if ( ! -e $dir ) {
    if ( my @paths = mkpath($dir,0,$perm) ) {
      foreach (@paths) {
        chmod $perm,$_;
        chown $uid,$gid,$_;
      }
    } else { print "failed to create directory: $dir $!\nScript aborted\n"; exit; }
  }
  return;
}

sub READFILE { my ($file) = @_;
   if ( ! open( MYFILE, $file ) ) { print "failed to open file: $file $!\nScript aborted\n"; exit;}
   my @lines = <MYFILE>;
   close MYFILE;
   chomp @lines;
   return @lines;
}

sub REPLACEFILE { my ($file, $uid, $gid, $perm, @lines) = @_;
  if ( ! open( FILE, ">$file" ) ) { print "failed to replace file: $file $!\nScript aborted\n"; exit 1;}
  print FILE @lines;
  close FILE;
  chmod $perm,$file;
  chown $uid,$gid,$file;
  return;
}

sub UPDATEFILE { my ($file, @lines) = @_;
  if ( ! open( FILE, ">$file" ) ) { print "failed to update file: $file $!\nScript aborted\n"; exit 1;}
  print FILE @lines;
  close FILE;
  return;
}

sub ABORT { my ($msg)=@_;
   print "$msg\nScript Aborted.\n";
   exit 1;
}

sub READDIR { my ($dir) = @_;
  if ( ! opendir( MYDIR, $dir ) ) { print "failed to read directory: $dir $!\nScript aborted\n"; exit;}
  my @files;
  while ( $_ = readdir(MYDIR) ) {
    if ( /^\.\.?$/ ) { next }
    push @files, "$dir/$_";
  }
  closedir MYDIR;
  return @files;
}


