#!/usr/bin/suidperl -T
#
# openwebmail-vdomain.pl - virtual domain user management
#
# 2003/02/26 Bernd Bass, owm@adminsquare.de
#

#
#    THIS MODULE MODIFIES IMPORTANT CONFIG FILES OF YOUR SERVER.
# !!!USE THIS MODULE ON YOUR OWN RISK, THERE IS NO WARRANTY AT ALL!!!
#
# Description:
#
# This module provides the ability for users of virtual domains to manage
# their 'own' domain space without any direct access by ssh or telnet
# to the server itself. At the current state a user can only manage
# the domain accounts of his current logged on e-mail account.
# For example, admin@foo.bar can manage all e-mail accounts
# of the domain foo.bar :)
#
# Requierements:
#
# + Openwebmail with this module of course :)
# + Postfix and access to the postfix config files (/etc/postfix)
# + vm-pop3d and access to the passwd files (/etc/virtual/)
#
# !Backup your config files before using this module the firsttime !
#
# Configuration:
#
# 1. enable vdomain module in your openwebmail.conf
#
# enable_vdomain		yes
#
# 2. override the following option in openwebmail.conf 
#    if any one of them is not appropriate for your system
#
# vdomain_vmpop3_pwdpath	/etc/virtual/
# vdomain_vmpop3_pwdname	passwd
# vdomain_vmpop3_mailpath	/var/spool/virtual
# vdomain_postfix_virtual	/etc/postfix/virtual
# vdomain_postfix_aliases	/etc/postfix/aliases
# vdomain_postfix_postmap	/usr/sbin/postmap 
# vdomain_postfix_postalias	/usr/sbin/postalias
#
# With the above default setting:
#
# virtual map  for each DOMAIN will be /etc/postfix/virtual
# aliases map  for each DOMAIN will be /etc/postfix/aliases
# passwd file  for each DOMAIN will be /etc/virtual/DOMAIN/passwd
# the mail spool  for USER@DOMAIN will be /var/spool/virtual/DOMAIN/USER
#
# ps: this program won't create virtual, aliases or password file for you
#     you have to create them explicitly by yourself
#
# 3. add this line to the openwebmail per domain config 
#    (cgi-bin/openwebmail/etc/site.conf/DOMAINANME)
#
# vdomain_admlist                admin foo bar webmaster
#
# ps: You can specify more "admins" per domain in the site specific config file.
#
# Thats it ! After these modifications you will get another icon beside
# the password change icon of the preferences page.
#
# Limitations:
#
# E-Mail address must have an entry in the vm-pop3d passwd file to be
# recognized by the module.
#
# Future wishlist:
#
#  + specify admin users for more than one domain at the same time
#  + modification of email addresses without an password account
#

#
# Version 0.5
#
#  + fixed wrong display of usermail settings with duplicate usernames
#
# Version 0.4 ( initial release )
#
#  + create, modify, delete users of the current logged on domain
#  + specify "Admin" users per domain which can use this module
#  + set passwords for virtual user accounts
#  + supported languages German, English (any translations are welcome)
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(.*?)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^([^\s]*)/) { $SCRIPT_DIR=$1; }
}
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "ow-shared.pl";
require "filelock.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy

########################## MAIN ############################

# $user has been determined by openwebmain_init()
my $is_adm=0;
foreach my $adm (@{$config{'vdomain_admlist'}}) {
   if ($user eq $adm) { $is_adm=1; last; }
}
if (!$is_adm) {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

# $domain has been determined by openwebmain_init()
foreach ("$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}",
         $config{'vdomain_postfix_virtual'},
         $config{'vdomain_postfix_aliases'}) {
   openwebmailerror("$_ $lang_err{'doesnt_exist'}") if (! -f $_);
}   

my $action = param("action");
if ($action eq "display_vuserlist") {
   display_vuserlist();
} elsif ($action eq "edit_vuser") {	# html
   edit_vuser();
} elsif ($action eq "change_vuser") {
   change_vuser();
} elsif ($action eq "delete_vuser") {
   delete_vuser();
} elsif ($action eq "edit_new_vuser") {	# html
   edit_new_vuser();
} elsif ($action eq "create_vuser") {
   create_vuser();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

# back to root if possible, required for setuid under persistent perl
$<=0; $>=0;
###################### END MAIN ############################

##################### DISPLAY_VUSERLIST ##################
sub display_vuserlist {
   my ($html, $temphtml);
   $html = readtemplate("vdomain_userlist.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"indexform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'display_vuserlist',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   $html =~ s/\@\@\@DOMAINNAME\@\@\@/$domain/;

   # USERLIST FROM VMPOP3D PASSWD
   my $pwdfile="$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}";
   ($pwdfile =~ /^(.+)$/) && ($pwdfile = $1);		# untaint
   my @vusers;
   # set ruid/euid to root before change files
   my ($origruid, $origeuid)=($<, $>);
   $>=0; $<=0;

   filelock("$pwdfile", LOCK_SH) or 
      openwebmailerror("$lang_err{'couldnt_locksh'} $pwdfile");
   open (PASSWD, $pwdfile) or
      openwebmailerror("$lang_err{'couldnt_open'} $pwdfile");
   while (<PASSWD>) {
      next if (/^#/);
      s/:.*//;
      push(@vusers, $_) if ($_);
   }
   close (PASSWD);
   filelock("$pwdfile", LOCK_UN);

   # go back to orignal uid
   $<=$origruid; $>=$origeuid;

   @vusers=sort(@vusers);

   $temphtml  = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
   if ($config{'vdomain_maxuser'}==0 || 
       $#vusers+1<$config{'vdomain_maxuser'}) {
      $temphtml .= qq|&nbsp;\n|;
      $temphtml .= iconlink("adduser.gif", $lang_text{'vdomain_createuser'}, qq|accesskey="A" href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=edit_new_vuser&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
   }
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $bgcolor=$style{'tablerow_light'};
   $temphtml = '';
   my $i;
   for ($i=0; $i<=$#vusers; $i++) {
      $temphtml .= qq|<tr>| if ($i%4==0);
      $temphtml .= qq|<td bgcolor=$bgcolor>|.
                   qq|<a href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=edit_vuser&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;vuser=$vusers[$i]" title="$lang_text{'vdomain_changeuser'} $vusers[$i]">$vusers[$i]</a>|.
                   qq|</td>|;
      if ($i%4==3) {
         $temphtml .= qq|</tr>|;
         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"};
         } else {
            $bgcolor = $style{"tablerow_dark"};
         }
      }
   }
   if ($i%4 !=0) {
      while ($i%4 != 0) {
         $temphtml .= qq|<td bgcolor=$bgcolor>&nbsp;</td>|;
         $i++;
      }
      $temphtml .= qq|</tr>|;
   }
   $html =~ s/\@\@\@USERS\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   print htmlheader(), $html,  htmlfooter(2);
}
##################### END DISPLAY_VUSERLIST #####################

##################### EDIT USER ##################
sub edit_vuser {
   my $vuser = param('vuser');
   my $redirect;

   my ($user_email, $user_alias, $user_virtual, $usertype);

   # set ruid/euid to root before change files
   my ($origruid, $origeuid)=($<, $>);
   $>=0; $<=0;

   # POSTFIX VIRTUAL=> john@sample.com    john.sample.com
   my $virtualfile=$config{'vdomain_postfix_virtual'};
   ($virtualfile =~ /^(.+)$/) && ($virtualfile = $1);		# untaint
   filelock($virtualfile, LOCK_SH) or 
      openwebmailerror("$lang_err{'couldnt_locksh'} $virtualfile");
   open (VIRTUAL, $virtualfile) or
      openwebmailerror("$lang_err{'couldnt_open'} $virtualfile");
   while (<VIRTUAL>) {
      s/^\s*//; s/\s*$//;
      my @a=split(/\s+/);
      if ($a[0] eq "$vuser\@$domain") {	# virtual user for this user@domain found
         ($user_email, $user_virtual)=@a; last;
      }
   }
   close (VIRTUAL);
   filelock($virtualfile, LOCK_UN);

   # POSTFIX ALIASES=> john.sample.com: /var/spool/virtual/sample.com/john
   #                   john.sample.com: tom@sample.org
   my $aliasfile=$config{'vdomain_postfix_aliases'};
   ($aliasfile =~ /^(.+)$/) && ($aliasfile = $1);		# untaint
   if ($user_virtual ne "") {
      filelock("$aliasfile", LOCK_SH) or 
         openwebmailerror("$lang_err{'couldnt_locksh'} $aliasfile");
      open (ALIASES, "$aliasfile") or
         openwebmailerror("$lang_err{'couldnt_open'} $aliasfile");
      while (<ALIASES>) {
         s/^\s*//; s/\s*$//;
         my @a=split(/[\s:]+/);
         if ($a[0] eq "$user_virtual") {		# alias for the virtual user found
            $user_alias=$a[1]; last;
         }
      }
      close (ALIASES);
      filelock("$aliasfile", LOCK_UN);
   }

   # go back to orignal uid
   $<=$origruid; $>=$origeuid;

   # check user type
   if ( $user_alias =~ /\@/ ) { 
      $usertype="external";
   } else { 
      $usertype="local";
   }

   my ($html, $temphtml);
   $html = readtemplate("vdomain_edituser.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"userform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'change_vuser',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'vuser',
                      -default=>$vuser,
                      -override=>'1') .
               hidden(-name=>'usertype',
                      -default=>$usertype,
                      -override=>'1');
   $html =~ s/\@\@\@STARTUSERFORM\@\@\@/$temphtml/;

   $html =~ s/\@\@\@VUSER\@\@\@/$vuser/;
   $html =~ s/\@\@\@DOMAINNAME\@\@\@/$domain/;

   $temphtml = password_field(-name=>'newpassword',
                              -default=>'*********',
                              -size=>'16',
                              -override=>'1');
   $html =~ s/\@\@\@NEWPASSWORDFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'confirmnewpassword',
                              -default=>'*********',
                              -size=>'16',
                              -override=>'1');
   $html =~ s/\@\@\@CONFIRMNEWPASSWORDFIELD\@\@\@/$temphtml/;

   my %typelabels=( local    => "$lang_text{'vdomain_usertype_localmbox'}", 
                    external => "$lang_text{'vdomain_usertype_redirected'}" );
   $temphtml = radio_group(-name => 'usertype_new',
                           -values => ['local','external'],
                           -default => $usertype,
                           -labels => \%typelabels);
   $html =~ s/\@\@\@USERTYPEFIELD\@\@\@/$temphtml/;

   my $redirect='';
   $redirect=$user_alias if ($usertype eq 'external');
   $temphtml = textfield(-name=>'redirect',
                         -default=>$redirect,
                         -size=>'40',
                         -override=>'1');
   $html =~ s/\@\@\@REDIRECTFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name => 'changebutton',
                      -value => $lang_text{'vdomain_changeuser'},
                      -onClick =>"return changecheck()");
   $html =~ s/\@\@\@CHANGEBUTTON\@\@\@/$temphtml/;

   # delete user button
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'delete_vuser',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'vuser',
                      -default=>$vuser,
                      -override=>'1');
   $html =~ s/\@\@\@STARTDELFORM\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'vdomain_deleteuser'}");
   $html =~ s/\@\@\@DELETEBUTTON\@\@\@/$temphtml/;

   # cancel button
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'display_vuserlist',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'cancel'}");
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $html =~ s/\@\@\@PASSWDMINLEN\@\@\@/$config{'passwd_minlen'}/g;

   print htmlheader(), $html, htmlfooter(2);
}
##################### END EDIT USER #####################

##################### CHANGE USER SETTINGS ##################
sub change_vuser {
   my $vuser = param('vuser');
   my $pwd   = param('newpassword');
   my $pwd2  = param('confirmnewpassword');
   my $usertype = param('usertype');
   my $usertype_new = param('usertype_new');
   my $redirect = param('redirect');

   # changed password ?
   my $encrypted = '';
   if ( $pwd !~ /\*\*/ ) {
      if ( $pwd eq $pwd2 ) {
         srand();
         my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
         my $salt=substr($table, int(rand(length($table))), 1).
                  substr($table, int(rand(length($table))), 1);
         $encrypted= crypt($pwd, $salt);
      } else {
         openwebmailerror($lang_err{'pwd_confirmmismatch'});
      }
   }
   if ( $encrypted ne "" ) {
      # set ruid/euid to root before change files
      my ($origruid, $origeuid)=($<, $>);
      $>=0; $<=0;

      # CHNAGE VMPOP3D PASSWD FILE
      # get the complete path for the vm-pop3d passwd file
      my $pwdfile="$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}";
      ($pwdfile =~ /^(.+)$/) && ($pwdfile = $1);		# untaint
      my $tmpfile="$pwdfile.tmp.$$";
      ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);		# untaint

      filelock($pwdfile, LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} $pwdfile");
      open (PWD, $pwdfile) or
         openwebmailerror("$lang_err{'couldnt_open'} $pwdfile");
      open (TMP, ">$tmpfile") or
         openwebmailerror("$lang_err{'couldnt_open'} $tmpfile");
      my $found=0;
      while (defined(my $line=<PWD>)) {	# write the tmp pwd file
         if ($line =~ /^$vuser:/g) {
            print TMP "$vuser:$encrypted\n"; $found=1;
         } else {
            print TMP $line;
         }
      }
      close (TMP);
      close (PWD);
      if (!$found) {
         unlink($tmpfile);
         openwebmailerror("$vuser\@$domain $lang_err{'doesnt_exist'}");
      }

      my ($fmode, $fuid, $fgid) = (stat($pwdfile))[2,4,5];
      chown($fuid, $fgid, $tmpfile); 
      chmod($fmode, $tmpfile);
      rename ($tmpfile, $pwdfile);	# move the tmp over the orig

      filelock($pwdfile, LOCK_UN);

      # go back to orignal uid
      $<=$origruid; $>=$origeuid;
   }

   # change the type of virtual user ?
   my $account  = '';
   if ( $usertype_new ne $usertype ) {
      if ( $usertype_new eq "external" && $redirect ne '') {
         $account = "$vuser.$domain: $redirect";
      } else {	# usertyoe_new eq 'local'
         $account = "$vuser.$domain: $config{'vdomain_vmpop3_mailpath'}/$domain/$vuser";
      }
   }
   if ( $account ne "" ) {
      # set ruid/euid to root before change files
      my ($origruid, $origeuid)=($<, $>);
      $>=0; $<=0;

      # CHNAGE POSTFIX ALIAS
      my $aliasfile = $config{'vdomain_postfix_aliases'};
      ($aliasfile =~ /^(.+)$/) && ($aliasfile = $1);		# untaint
      my $tmpfile ="$aliasfile.tmp.$$";
      ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);		# untaint

      filelock($aliasfile, LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} $aliasfile");
      open (ALIASES, $aliasfile) or
         openwebmailerror("$lang_err{'couldnt_open'} $aliasfile");
      open (TMP, ">$tmpfile") or
         openwebmailerror("$lang_err{'couldnt_open'} $tmpfile");
      my $printed=0;
      while (defined(my $line=<ALIASES>)) {	# write the tmp aliases file
         $line=~s/^\s*//; $line=~s/\s*$//;
         my @a=split(/\s+/, $line);
         if ($a[0] eq "$vuser\@$domain") {	# old virtual user entry for this user@domain found
            print TMP "$account\n"; $printed=1;
         } else {
            print TMP "$line\n";
         }
      }
      print TMP "$account\n" if (!$printed);
      close (TMP);
      close (ALIASES);

      my ($fmode, $fuid, $fgid) = (stat($aliasfile))[2,4,5];
      chown($fuid, $fgid, $tmpfile); 
      chmod($fmode, $tmpfile);
      rename ($tmpfile, $aliasfile);	# move the tmp over the orig

      filelock($aliasfile, LOCK_UN);

      # rebuid postfix aliases
      my $postalias_bin=$config{'vdomain_postfix_postalias'};
      ($postalias_bin =~ /^(.+)$/) && ($postalias_bin = $1);		# untaint
      system ("$postalias_bin $aliasfile");
      $<=$origruid; $>=$origeuid;       # fall back to original ruid/euid
   }

   display_vuserlist();
}
##################### END CHANGE USER #####################

##################### DELETE USER  ##################
sub delete_vuser {
   my $vuser = param('vuser');
   if ( $vuser eq "" ) {
      return(display_vuserlist());
   }

   # set ruid/euid to root before change files
   my ($origruid, $origeuid)=($<, $>);
   $>=0; $<=0;

   # DELETE USER IN VMPOP3D PASSWD
   # get the complete path for the vm-pop3d passwd file
   my $pwdfile="$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}";
   ($pwdfile =~ /^(.+)$/) && ($pwdfile = $1);		# untaint
   my $tmpfile="$pwdfile.tmp.$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);		# untaint

   filelock($pwdfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $pwdfile");
   open (PWD, $pwdfile) or
      openwebmailerror("$lang_err{'couldnt_open'} $pwdfile");
   open (TMP, ">$tmpfile") or
      openwebmailerror("$lang_err{'couldnt_open'} $tmpfile");
   while (defined(my $line=<PWD>)) {	# write the tmp pwd file
      next if ($line =~ /^$vuser:/g);
      print TMP $line;
   }
   close (TMP);
   close (PWD);

   my ($fmode, $fuid, $fgid) = (stat($pwdfile))[2,4,5];
   chown($fuid, $fgid, $tmpfile); 
   chmod($fmode, $tmpfile);
   rename ($tmpfile, $pwdfile);	# move the tmp over the orig

   filelock($pwdfile, LOCK_UN);

   # DELETE USER IN POSTFIX VIRTUAL
   my $virtualfile = $config{'vdomain_postfix_virtual'};
   ($virtualfile =~ /^(.+)$/) && ($virtualfile = $1);	# untaint
   my $tmpfile ="$virtualfile.tmp.$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);		# untaint

   filelock($virtualfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $virtualfile");
   open (VIRTUAL, $virtualfile) or
      openwebmailerror("$lang_err{'couldnt_open'} $virtualfile");
   open (TMP, ">$tmpfile") or
      openwebmailerror("$lang_err{'couldnt_open'} $tmpfile");
   while (defined(my $line=<VIRTUAL>)) {	# write the tmp virtual file
      $line=~s/^\s*//; $line=~s/\s*$//;
      my @a=split(/\s+/, $line);
      next if ($a[0] eq "$vuser\@$domain");	# skip old virtual user entry for this user@domain
      print TMP "$line\n";
   }
   close (TMP);
   close (VIRTUAL);

   my ($fmode, $fuid, $fgid) = (stat($virtualfile))[2,4,5];
   chown($fuid, $fgid, $tmpfile); 
   chmod($fmode, $tmpfile);
   rename ($tmpfile, $virtualfile);	# move the tmp over the orig

   filelock($virtualfile, LOCK_UN);

   # rebuid postfix virtual map index
   my $postmap_bin=$config{'vdomain_postfix_postmap'};
   ($postmap_bin =~ /^(.+)$/) && ($postmap_bin = $1);	# untaint
   system ("$postmap_bin $virtualfile");

   # DELETE USER IN POSTFIX ALIASES
   my $aliasfile = $config{'vdomain_postfix_aliases'};
   ($aliasfile =~ /^(.+)$/) && ($aliasfile = $1);	# untaint
   my $tmpfile ="$aliasfile.tmp.$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);		# untaint

   filelock($aliasfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $aliasfile");
   open (ALIASES, $aliasfile) or
      openwebmailerror("$lang_err{'couldnt_open'} $aliasfile");
   open (TMP, ">$tmpfile") or
      openwebmailerror("$lang_err{'couldnt_open'} $tmpfile");
   while (defined(my $line=<ALIASES>)) {	# write the tmp aliases file
      $line=~s/^\s*//; $line=~s/\s*$//;
      my @a=split(/[\s:]+/, $line);
      next if ($a[0] eq "$vuser.$domain");	# skip old alias entry for this virtual user
      print TMP "$line\n";
   }
   close (TMP);
   close (ALIASES);

   my ($fmode, $fuid, $fgid) = (stat($aliasfile))[2,4,5];
   chown($fuid, $fgid, $tmpfile); 
   chmod($fmode, $tmpfile);
   rename ($tmpfile, $aliasfile);	# move the tmp over the orig

   filelock($aliasfile, LOCK_UN);

   # rebuid postfix aliases index
   my $postalias_bin=$config{'vdomain_postfix_postalias'};
   ($postalias_bin =~ /^(.+)$/) && ($postalias_bin = $1);	# untaint
   system ("$postalias_bin $aliasfile");

   # DELETE MAILBOX FILE
   my $spoolfile="$config{'vdomain_vmpop3_mailpath'}/$domain/$vuser";
   ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1);		# untaint
   unlink ("$spoolfile") if (-e $spoolfile);

   # DELETE OWM USER SETTINGS
   my $userconf="$config{'ow_cgidir'}/etc/users/$vuser\@$domain";
   ($userconf =~ /^(.+)$/) && ($userconf = $1);		# untaint
   unlink ("$userconf") if (-e $userconf);

   # go back to orignal uid
   $<=$origruid; $>=$origeuid;       # fall back to original ruid/euid

   # go back to start and display index
   display_vuserlist();
}
##################### END DELETE USER #####################

##################### CREATE NEW USER ##################
sub edit_new_vuser {
   my ($html, $temphtml);
   $html = readtemplate("vdomain_newuser.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"userform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'create_vuser',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');
   $html =~ s/\@\@\@STARTUSERFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'vuser',
                         -default=>'',
                         -size=>'20',
                         -override=>'1');
   $html =~ s/\@\@\@VUSER\@\@\@/$temphtml/;
   $html =~ s/\@\@\@DOMAINNAME\@\@\@/$domain/;

   $temphtml = password_field(-name=>'newpassword',
                              -default=>'',
                              -size=>'16',
                              -override=>'1');
   $html =~ s/\@\@\@NEWPASSWORDFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'confirmnewpassword',
                              -default=>'',
                              -size=>'16',
                              -override=>'1');
   $html =~ s/\@\@\@CONFIRMNEWPASSWORDFIELD\@\@\@/$temphtml/;

   my %typelabels=( local   =>"$lang_text{'vdomain_usertype_localmbox'}", 
                    external=>"$lang_text{'vdomain_usertype_redirected'}" );
   $temphtml = radio_group(-name=>'usertype',
                               values=>['local','external'],
                               default=>'local',
                               labels=>\%typelabels);
   $html =~ s/\@\@\@USERTYPEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'redirect',
                         -default=>'',
                         -size=>'40',
                         -override=>'1');
   $html =~ s/\@\@\@REDIRECTFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name => 'changebutton',
                      -value => $lang_text{'vdomain_createuser'},
                      -onClick =>"return changecheck()");
   $html =~ s/\@\@\@CREATEBUTTON\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'display_vuserlist',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'cancel'}");
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $html =~ s/\@\@\@PASSWDMINLEN\@\@\@/$config{'passwd_minlen'}/g;

   print htmlheader(), $html, htmlfooter(2);
}
##################### END CREATE NEW USER #####################

##################### WRITE NEW USER  ##################
sub create_vuser {
   my $vuser = param('vuser');
   my $pwd   = param('newpassword');
   my $pwd2  = param('confirmnewpassword');
   my $usertype = param('usertype');
   my $redirect = param('redirect');

   my $encrypted = '';
   if ( $pwd !~ /\*\*/ ) {
      if ( $pwd eq $pwd2 ) {
         srand();
         my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
         my $salt=substr($table, int(rand(length($table))), 1).
                  substr($table, int(rand(length($table))), 1);
         $encrypted= crypt($pwd, $salt);
      } else {
         openwebmailerror($lang_err{'pwd_confirmmismatch'});
      }
   }

   # usertype of virtual user ?
   my $account  = '';
   if ( $usertype eq "external" && $redirect ne '') {
      $account = "$vuser.$domain: $redirect";
   } else {	# tyep eq 'local'
      $account = "$vuser.$domain: $config{'vdomain_vmpop3_mailpath'}/$domain/$vuser";
   }

   # set ruid/euid to root before change files
   my ($origruid, $origeuid)=($<, $>);
   $>=0; $<=0;

   # CREATE USER IN VMPOP3D PASSWD
   # get the complete path for the vm-pop3d passwd file
   my $pwdfile="$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}";
   ($pwdfile =~ /^(.+)$/) && ($pwdfile = $1);		# untaint

   my $usercount=0;
   filelock($pwdfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $pwdfile");
   open (PWD, $pwdfile) or
      openwebmailerror("$lang_err{'couldnt_open'} $pwdfile");
   while (defined(my $line=<PWD>)) {	# write the tmp pwd file
      next if ($line=~/^#/);
      if ($line =~ /^$vuser:/g) {
        openwebmailerror("$vuser\@$domain $lang_err{'already_exists'}");
      }
      $usercount++; 
   }
   close (PWD);
   if ($config{'vdomain_maxuser'}>0 && 
       $usercount>$config{'vdomain_maxuser'}) {
      openwebmailerror($lang_err{'vdomain_toomanyuser'});
   }

   open (PWD, ">>$pwdfile") or
      openwebmailerror("$lang_err{'couldnt_open'} $pwdfile");
   seek(PWD, 0, 2);	# seek to tail
   print PWD "$vuser:$encrypted\n";
   close (PWD);
   filelock($pwdfile, LOCK_UN);

   # CREATE USER IN POSTFIX VIRTUAL
   my $virtualfile = $config{'vdomain_postfix_virtual'};
   ($virtualfile =~ /^(.+)$/) && ($virtualfile = $1);	# untaint

   filelock($virtualfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $virtualfile");
   open (VIRTUAL, ">>$virtualfile") or
      openwebmailerror("$lang_err{'couldnt_open'} $virtualfile");
   seek(VIRTUAL, 0, 2);	# seek to tail
   print VIRTUAL "$vuser\@$domain\t$vuser.$domain\n";
   close (VIRTUAL);
   filelock($virtualfile, LOCK_UN);

   # rebuid postfix virtual map index
   my $postmap_bin=$config{'vdomain_postfix_postmap'};
   ($postmap_bin =~ /^(.+)$/) && ($postmap_bin = $1);	# untaint
   system ("$postmap_bin $virtualfile");

   # CREATE USER IN POSTFIX ALIASES
   my $aliasfile = $config{'vdomain_postfix_aliases'};
   ($aliasfile =~ /^(.+)$/) && ($aliasfile = $1);	# untaint

   filelock($aliasfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $aliasfile");
   open (ALIASES, ">>$aliasfile") or
      openwebmailerror("$lang_err{'couldnt_open'} $aliasfile");
   seek(ALIASES, 0, 2);	#seek to tail
   print ALIASES "$account\n";
   close (ALIASES);
   filelock($aliasfile, LOCK_UN);

   # rebuid postfix aliases index
   my $postalias_bin=$config{'vdomain_postfix_postalias'};
   ($postalias_bin =~ /^(.+)$/) && ($postalias_bin = $1);	# untaint
   system ("$postalias_bin $aliasfile");

   # go back to orignal uid
   $<=$origruid; $>=$origeuid;

   display_vuserlist();
}
##################### END WRITE NEW USER #####################
