#!/usr/bin/suidperl -T
#
# openwebmail-vdomain.pl - virtual domain user management
#
# 2003/02/26 Bernd Bass, owm@adminsquare.de
# 2003/05/09 Scott Mazur, scott@littlefish.ca
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
# Requirements:
#
# + Openwebmail with this module of course :)
# + Postfix and access to the postfix config files (/etc/postfix)
# + vm-pop3d and access to the passwd files (/etc/virtual/)
#
# + Postfix config file must include the following options:
#    allow_mail_to_commands = alias,forward,include
#    allow_mail_to_files = alias,forward,include
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
#  + include postfix aliases file in alias check when domain is local
#  + display aliases with user list
#
#
# Version 0.6
#
#  + rewrite to manage virtual user mail aliases
#  + use :include: mechanism in postifx aliases
#  + new language elements: set_passwd, reset_passwd, email_alias, vdomain_toomanyalias and vdomain_userrequired
#  + merged edit user and create user templates
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
use File::Path;

require "ow-shared.pl";
require "filelock.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($logindomain $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy

# local globals
use vars qw($sort $page);
use vars qw($messageid $escapedmessageid);
use vars qw($userfirsttime $prefs_caller);

########################## MAIN ############################
openwebmail_requestbegin();
userenv_init();

# If this is a real user (not virtual) then switch to the virtual site config
# this allows real user to be administrator of the vdomains, tricky!
if ( $config{'auth_module'} ne 'auth_vdomain.pl' ) {
   readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   loadauth($config{'auth_module'});
}

# $user has been determined by openwebmain_init()
if (!$config{'enable_vdomain'} || !is_vdomain_adm($user)) {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

# $domain has been determined by openwebmain_init()
foreach ("$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}",
         $config{'vdomain_postfix_virtual'},
         $config{'vdomain_postfix_aliases'}) {
   openwebmailerror(__FILE__, __LINE__, "$_ $lang_err{'doesnt_exist'}") if (! -f $_);
}   

my $action = param("action");
if ($action eq 'display_vuserlist') {
   display_vuserlist();
} elsif ($action eq 'edit_vuser' ||
         $action eq 'edit_new_vuser') {
   edit_vuser();
} elsif ($action eq 'change_vuser' ||
         $action eq 'change_new_vuser') {
   change_vuser();
} elsif ($action eq 'delete_vuser') {
   delete_vuser();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

openwebmail_requestend();
###################### END MAIN ############################

##################### DISPLAY_VUSERLIST ##################
sub display_vuserlist {
   my $html = applystyle(readtemplate("vdomain_userlist.template"));

   my $temphtml = startform(-name=>"indexform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'display_vuserlist',
                      -override=>'1') ;
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   $html =~ s/\@\@\@DOMAINNAME\@\@\@/$domain/;

   my @vusers=vuser_list();

   $temphtml  = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession"|);
   if ($config{'vdomain_maxuser'}==0 || 
       $#vusers+1<$config{'vdomain_maxuser'}) {
      $temphtml .= qq|&nbsp;\n|;
      $temphtml .= iconlink("adduser.gif", $lang_text{'vdomain_createuser'}, qq|accesskey="A" href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=edit_new_vuser&amp;sessionid=$thissession"|);
   }
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $bgcolor=$style{'tablerow_light'};
   $temphtml = '';
   my $i;
   for ($i=0; $i<=$#vusers; $i++) {
      $temphtml .= qq|<tr>| if ($i%4==0);
      $temphtml .= qq|<td bgcolor=$bgcolor>|.
                   qq|<a href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=edit_vuser&amp;vuser=$vusers[$i]&amp;sessionid=$thissession" title="$lang_text{'vdomain_changeuser'} $vusers[$i]">$vusers[$i]</a>|.
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

   httpprint([], [htmlheader(), $html,  htmlfooter(2)]);
}
##################### END DISPLAY_VUSERLIST #####################

##################### EDIT USER ##################
sub edit_vuser {
   my ($focus, $alert, $pwd, $pwd2, @alias_list)=@_;
   my $vuser = param('vuser');
   my $action = param('action');
   my $enter_alias=valias_allowed(@alias_list);

   my ($new, $title_txt, $setpass_txt, $del_txt, $chg_txt, $user_txt);
   $new=1 if ($action=~/new/);
   if ($action=~/edit/) {
      if ($new) {
         $focus='vuser';
      } else {
         $pwd = '*********';
         $pwd2=$pwd;
         @alias_list = valias_list(lc($vuser));
         $enter_alias=valias_allowed(@alias_list);
         if ($enter_alias) {
            $focus='aliasnew';
         } else {
            $focus='newpassword';
         }
      }
      $action=~s/edit/change/;
   }

   if ($new) {
      $title_txt=$lang_text{'vdomain_createuser'};
      $setpass_txt=$lang_text{'set_passwd'};
      $del_txt='';
      $chg_txt=$lang_text{'vdomain_createuser'};
      $user_txt = textfield(-name=>'vuser',
                            -default=>$vuser,
                            -size=>'20',
                            -override=>'1');
   } else {
      $title_txt="$lang_text{'vdomain_changeuser'} $vuser";
      $setpass_txt=$lang_text{'reset_passwd'};
      if (is_vdomain_adm($vuser)){
         $del_txt = '';
      } else {
         $del_txt = submit(-name => 'deletebutton',
                           -value => $lang_text{'vdomain_deleteuser'});
      }
      $chg_txt=$lang_text{'vdomain_changeuser'};
      $user_txt = "<b>$vuser</b>";
   }

   my $html = applystyle(readtemplate("vdomain_edituser.template"));
   $html =~ s/\@\@\@DOMAINNAME\@\@\@/$domain/;
   $html =~ s/\@\@\@VDOMAINTITLE\@\@\@/$title_txt/;

   my $temphtml = startform(-name=>"userform",
                            -action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>$action,
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'addmod',
                      -default=>'',
                      -override=>'1') .
               hidden(-name=>'aliasdel',
                      -default=>'',
                      -override=>'1') .
               hidden(-name=>'aliaslist',
                      -default=>[@alias_list],
                      -override=>'1');
   if (! $new) {
      $temphtml .= hidden(-name=>'vuser',
                          -default=>$vuser,
                          -override=>'1');
   }

   $html =~ s/\@\@\@STARTUSERFORM\@\@\@/$temphtml/;

   $html =~ s/\@\@\@FOCUS\@\@\@/$focus/;
   $html =~ s/\@\@\@VUSER\@\@\@/$user_txt/;

   $html =~ s/\@\@\@SETPASS\@\@\@/$setpass_txt/;
   $temphtml = password_field(-name=>'newpassword',
                              -default=>$pwd,
                              -size=>'16',
                              -override=>'1');
   $html =~ s/\@\@\@NEWPASSWORDFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'confirmnewpassword',
                              -default=>$pwd2,
                              -size=>'16',
                              -override=>'1');
   $html =~ s/\@\@\@CONFIRMNEWPASSWORDFIELD\@\@\@/$temphtml/;

   if ($enter_alias) {
      $temphtml = qq|<tr><td>\n|.
                  qq|<table><tr><td>$lang_text{'email_alias'}: </td><td>| .
                  textfield(-name=>'aliasnew',
                            -default=>'',
                            -size=>'20',
                            -override=>'1') .
                  qq|</td><td> \@ $domain</td></tr></table>\n|.
                  qq|</td><td align="center">| .
                        submit(-name=>'addmod_button',
                           -value=>$lang_text{'add'},
                           -onClick=>'AddMod()',
                           -class=>'medtext') .
                  qq|</td></tr>\n|;
   } else {
      $temphtml = qq|<tr><td colspan="2" align="center">$lang_err{'vdomain_toomanyalias'}</td></tr>\n|;
   }

   my $bgcolor = $style{"tablerow_dark"};
   foreach ( sort @alias_list ) {
      my $a=$_;
      $a=~s/'/\\'/;	# escape ' for javascript
      $temphtml .= qq|<tr bgcolor=$bgcolor><td>$_\@$domain</td>| .
                           qq|<td align="center">| .
                           submit(-name=>'aliasdel_button',
                                  -value=>$lang_text{'delete'},
                                  -onClick=>"Delete('$a')",
                                  -class=>'medtext') .
                            '</td></tr>';
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   $html =~ s/\@\@\@ALIASENTRIES\@\@\@/$temphtml/;

   $temphtml = submit(-name => 'changebutton',
                        -value => $chg_txt);
   $html =~ s/\@\@\@CHANGEBUTTON\@\@\@/$temphtml/;

   # delete button
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'delete_vuser',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'vuser',
                      -default=>$vuser,
                      -override=>'1');
   $html =~ s/\@\@\@STARTDELFORM\@\@\@/$temphtml/;
   $html =~ s/\@\@\@DELETEBUTTON\@\@\@/$del_txt/;

   # cancel button
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl") .
               hidden(-name=>'action',
                      -default=>'display_vuserlist',
                      -override=>'1').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1');
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;
   $temphtml = submit("$lang_text{'cancel'}");
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   if ($alert) {
      $html.= qq|<script language="JavaScript">\n<!--\n|.
              qq|alert('$alert');\n|.
              qq|//-->\n</script>\n|;
   }

   httpprint([], [htmlheader(), $html,  htmlfooter(2)]);
}
##################### END EDIT USER #####################

##################### CHANGE USER SETTINGS ##################
sub change_vuser {
   my $vuser_original = param('vuser');
   my $vuser=lc($vuser_original);
   my $action=param('action');
   my $pwd=param('newpassword');
   my $pwd2=param('confirmnewpassword');
   my $aliasnew=lc(param('aliasnew'));$aliasnew=~s/\s*//g;$aliasnew=~s/@.*//;$aliasnew=safedomainname($aliasnew);

   my @vuser_list = vuser_list();
   my $new=0;
   $new=1 if ($action=~/new/);
   my $focus='aliasnew';
   my (%hash,$alert);

   if ($new) {
      openwebmailerror(__FILE__, __LINE__, $lang_err{'vdomain_toomanyuser'}) if ($config{'vdomain_maxuser'}>0 and @vuser_list>$config{'vdomain_maxuser'});
      if ( $pwd =~ /\*\*/ ) {
         $pwd='';
         $pwd2=$pwd;
      }
   } else {
      openwebmailerror(__FILE__, __LINE__, "$vuser\@$domain $lang_err{'doesnt_exist'}") if (! vuser_exists($vuser,@vuser_list) );
   }

   foreach ( param("aliaslist") ) {
      $hash{lc($_)}=1;
   }

   delete $hash{lc(param('aliasdel'))} if ( param('aliasdel') );

   if ( $aliasnew ) {
      if ( $aliasnew ne $vuser and ! $hash{$aliasnew}) {
         if ( valias_list_exists($vuser,$aliasnew) ) {
            $alert="$aliasnew\@$domain $lang_err{'already_exists'}";
         } else {
            $hash{$aliasnew}=1;
         }
      }
   }
   my @alias_list = sort keys %hash;

   $focus='newpassword' if (! valias_allowed(@alias_list));

   # changed password ?
   if ( $pwd !~ /\*\*/ and $pwd ne $pwd2 ) {
      $alert=$lang_err{'pwd_confirmmismatch'};
      $focus='newpassword';
   }

   # check password length
   if ( length($pwd) < $config{'passwd_minlen'} ) {
      $alert=$lang_err{'pwd_tooshort'};
      $alert=~s/\@\@\@PASSWDMINLEN\@\@\@/$config{'passwd_minlen'}/;
      $focus='newpassword';
   }

   if ($new) {
      openwebmailerror(__FILE__, __LINE__, $lang_err{'vdomain_toomanyalias'}) if (@alias_list > $config{'vdomain_maxalias'});
      if (! $vuser ) {
         $alert = $lang_err{'vdomain_userrequired'};
         $focus='vuser';
      }
      elsif (vuser_exists($vuser,@vuser_list) or valias_list_exists($vuser,$vuser)) {
         $alert = "$vuser\@$domain $lang_err{'already_exists'}";
         $focus='vuser';
      }
   }

   if ( $alert or param('addmod') or param('aliasdel') ) {
      edit_vuser($focus, $alert, $pwd, $pwd2, @alias_list);
      return;
   }

   if ( $new ) { # CREATE NEW USER
      writelog("vdomain $user: create vuser - $vuser  aliases: @alias_list");
      # CREATE USER IN VIRTUAL PASSWD
      vpasswd_update($vuser_original,0,$pwd);

      # need $vuid and $vgid here, so don't skip get_userinfo() if 'use_syshomedir'
      my ($vuid, $vhomedir) = (get_userinfo(\%config, "$vuser_original\@$domain"))[3,5];
      my $vgid=getgrnam('mail');	# for better compatibility with other mail progs
      $vhomedir="$config{'ow_usersdir'}/$domain/$user" if (!$config{'use_syshomedir'});

      # switch to root
      my ($origruid, $origeuid)=($<, $>);
      $>=0; $<=0;

      # CREATE USER HOME DIRECTORY
      if ( !-d $vhomedir ) {
         if (mkdir ($vhomedir, 0700) && chown($vuid, $vgid, $vhomedir)) {
            writelog("vdomain $user: create vuser homedir - $vhomedir, uid=$vuid, gid=$vgid");
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $vhomedir ($!)");
         }
      }
      # CREATE USER .forward
      my $vforward = "$vhomedir/.forward";
      my $spool = vdomain_userspool($vuser, $vhomedir);
      my ($fh, $vforward) = root_open(">$vhomedir/.forward");
      print $fh "$spool\n";
      root_close($fh, $vforward, 0, 0);
      chown($vuid, $vgid, $vforward);
      writelog("vdomain $user: write vuser .forward - $vforward, uid=$vuid, gid=$vgid");

      # CREATE USER MAIL DIRECTORY
      my $folderdir = "$vhomedir/$config{'homedirfolderdirname'}";
      if ( !-d $folderdir ) {
         if (mkdir ($folderdir, 0700) && chown($vuid, $vgid, $folderdir)) {
            writelog("vdomain $user: create vuser folderdir - $folderdir, uid=$vuid, gid=$vgid");
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $folderdir ($!)");
         }
      }
      # CREATE USER .from.book
      my ($fh, $fromfile) = root_open(">$folderdir/.from.book");
      root_close($fh, $fromfile, 0, 0);
      chown($vuid, $vgid, $fromfile);
      writelog("vdomain $user: create vuser .from.book - $fromfile, uid=$vuid, gid=$vgid");


      # CREATE USER IN POSTFIX VIRTUAL
      vuser_update($vuser, 0, $fromfile, @alias_list);

      # CREATE USER IN POSTFIX ALIASES
      valias_update($vuser, 0, ":include:$vforward", $fromfile);

   } else { # UPDATE EXISTING USER
      # changed password ?
      if ( $pwd !~ /\*\*/ ) {
         vpasswd_update($vuser_original,0,$pwd);
         writelog("vdomain $user: update vuser password - $vuser_original");
      }

      # changed alias?
      my @orig_alias_list = valias_list($vuser);
      my $match=1;
      foreach (@alias_list) {
         if ($_ ne $orig_alias_list[0]) { $match=0; last }
         shift @orig_alias_list;
      }
      $match=0 if ( @orig_alias_list );
      if ( ! $match ) {
         my $vhomedir;
         if ($config{'use_syshomedir'}) {
            $vhomedir = (get_userinfo(\%config, "$vuser\@$domain"))[5];
         } else {
            $vhomedir="$config{'ow_usersdir'}/$domain/$user";
         }
         writelog("vdomain $user: update vuser aliases - $vuser  aliases: @alias_list");
         vuser_update($vuser,0,"$vhomedir/$config{'homedirfolderdirname'}/.from.book",@alias_list);
      }
   }

   display_vuserlist();
}
##################### END CHANGE USER #####################

##################### DELETE USER  ##################
sub delete_vuser {
   my $vuser_original = param('vuser');
   my $vuser=lc($vuser_original);

   if ( vuser_exists($vuser,vuser_list()) ) {
      # get the home directory before we remove the user from password file or trouble later!
      my $vhomedir;
      if ($config{'use_syshomedir'}) {
         $vhomedir = (get_userinfo(\%config, "$vuser\@$domain"))[5];
      } else {
         $vhomedir="$config{'ow_usersdir'}/$domain/$user";
      }
 
      writelog("vdomain $user: delete vuser - $vuser_original");
      # DELETE USER IN VMPOP3D PASSWD
      vpasswd_update($vuser_original,1); 
      # DELETE USER IN POSTFIX VIRTUAL
      vuser_update($vuser, 1);
      # DELETE USER IN POSTFIX ALIASES
      valias_update($vuser, 1);

      # switch to root
      my ($origruid, $origeuid)=($<, $>); $>=0; $<=0;

      # DELETE MAILBOX FILE
      my $spoolfile="$config{'vdomain_vmpop3_mailpath'}/$domain/$vuser";
      ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1);		# untaint
      if (-e $spoolfile) {
         writelog("vdomain $user: remove spool file - $vuser $spoolfile");
         rmtree ($spoolfile);
      }

      # DELETE OWM USER SETTINGS
      my $userconf="$config{'ow_cgidir'}/etc/users/$vuser\@$domain";
      ($userconf =~ /^(.+)$/) && ($userconf = $1);		# untaint
      writelog("vdomain $user: remove userconf file - $vuser $userconf");
      if (-e $userconf) {
         writelog("vdomain $user: remove userconf file - $vuser $userconf");
         rmtree ($userconf);
      }

      # DELETE HOME DIRECTORY
      if (-e $vhomedir) {
         writelog("vdomain $user: remove vhomedir file - $vuser $vhomedir");
         rmtree ($vhomedir);
      }

      # go back to orignal uid
      $<=$origruid; $>=$origeuid;
   }

   # go back to start and display index
   display_vuserlist();
}
##################### END DELETE USER #####################

##################### VUSER_LIST ##################
sub vuser_list {
   my @vusers;

   # USERLIST FROM VMPOP3D PASSWD
   my ($fh, $file, $origruid, $origeuid) = root_open("$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}");
   while (<$fh>) {
      next if (/^#/);
      chomp; s/:.*//;
      push(@vusers, $_) if ($_);
   }
   root_close($fh, $file, $origruid, $origeuid);
   return (sort @vusers);
}
##################### END VUSER_LIST ##################

##################### VALIAS_LIST ##################
sub valias_list {
   my ($vuser)=@_;
   my (@alias_list, $alias);

   # POSTFIX VIRTUAL=> john@sample.com    john.sample.com
   my ($fh, $file, $origruid, $origeuid) = root_open($config{'vdomain_postfix_virtual'});
   while (<$fh>) {
      next if (/^#/);
      if ( /^\s*([^@]+)\@$domain\s+$vuser\.$domain\s*$/ ) {
         if ( $1 ne $vuser ) {
            $alias=lc($1);
            push @alias_list, $alias;
         }
      }
   }
   root_close($fh, $file, $origruid, $origeuid);
   return (sort @alias_list);
}
##################### END VALIAS_LIST ##################

##################### VUSER_ALIAS_EXISTS ##################
sub valias_list_exists {
   my ($vuser,$alias)=@_;
   my $fnd=0;
   my ($fh, $file, $origruid, $origeuid) = root_open($config{'vdomain_postfix_virtual'});
   while (<$fh>) {
      next if (/^#/);
      chomp; s/^\s*//; s/\s*$//;
      if ( /^$alias\@$domain\s*(\S+)\.$domain\s*$/ and $1 ne $vuser ) {
         $fnd=1; last;
      }
   }
   root_close($fh, $file, $origruid, $origeuid);
   return ($fnd);
}
##################### END VUSER_ALIAS_EXISTS ##################

##################### VUSER_ALIAS_EXISTS ##################
sub valias_allowed {
   my (@alias_list)=@_;
   my $flag=1;
   $flag=0 if (@alias_list >= $config{'vdomain_maxalias'});
   return ($flag);
}
##################### END VUSER_ALIAS_EXISTS ##################

##################### VUSER_EXISTS ##################
sub vuser_exists {
   my ($vuser,@vuser_list)=@_;
   my $fnd=0;
   foreach (@vuser_list) {
      if ( $vuser eq lc($_) ) {
         $fnd=1; last;
      }
   }
   return ($fnd);
}
##################### END VUSER_EXISTS ##################

##################### VUSER_UPDATE ##################
sub vuser_update {
   my ($vuser,$delete,$fromfile,@alias_list)=@_;
   my ($fh, $file, $origruid, $origeuid) = root_open($config{'vdomain_postfix_virtual'});

   my $fnd=0;
   my @lines;
   while (<$fh>) {	# read the virtual user file
      if (/^#/) {
         push @lines, $_;
      } elsif ( /^\s*\S+\s+$vuser\.$domain\s*$/ ) { # remove existing entries for this user
         if ($delete) {
            s/\n//g; writelog("vdomain $user: remove virtual entry - $_");
         }
         $fnd=1;
      } else {
         if ($fnd == 1) {
            $fnd=2;
            if (! $delete) {
               push @lines,"$vuser\@$domain\t$vuser.$domain\n";
               foreach my $alias (@alias_list) {
                  push @lines,"$alias\@$domain\t$vuser.$domain\n";
               }
            }
         }
         push @lines, $_;
      }
   }
   close ( $fh );

   if ($fnd < 2 and ! $delete) {
      push @lines,"$vuser\@$domain\t$vuser.$domain\n";
      writelog("vdomain $user: add virtual entry - $vuser\@$domain  vuser.$domain") if (! $fnd);
      foreach my $alias (@alias_list) {
         push @lines,"$alias\@$domain\t$vuser.$domain\n";
         writelog("vdomain $user: add virtual entry - $alias\@$domain  $vuser.$domain") if (! $fnd);
      }
   }

   open ($fh, ">$file") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $file ($!)");

   print $fh @lines;

   root_close($fh, $file, $origruid, $origeuid);

   # rebuild postfix virtual map index
   vpostfix_cmd('postmap',$file);

   if (! $delete) { # update .from.book with aliases
      my %froms=get_userfrom($domain,$vuser,$vuser,$fromfile);
      my @newfroms;
      foreach (@alias_list) {
         if (! $froms{"$_\@$domain"}) {
            push @newfroms, "$_\@$domain\@\@\@$_\n";
            writelog("vdomain $user: add from.book entry - $_\@$domain\@\@\@$_");
         }
      }
      if (@newfroms) {
         my ($fh, $fromfile, $origruid, $origeuid) = root_open(">>$fromfile");
         print $fh @newfroms;
         root_close($fh, $fromfile, $origruid, $origeuid);
      }
   }
   return;
}
##################### END VUSER_UPDATE ##################

##################### VALIAS_UPDATE ##################
sub valias_update {
   my ($vuser,$delete,$entry)=@_;
   my ($fh, $file, $origruid, $origeuid) = root_open($config{'vdomain_postfix_aliases'});

   my $fnd=0;
   $fnd=1 if ($delete);
   my @lines;
   while (<$fh>) {	# read the alias file
      if ( /^\s*$vuser\.$domain\s*:/ ) { # replace existing entry for this alias
         if ($delete) {
            s/\n//g; writelog("vdomain $user: remove aliases entry - $_");
         } else {
            push @lines, "$vuser.$domain: $entry\n"; $fnd=1;
         }
      } else {
         push @lines, $_;
      }
   }
   close ( $fh );
   if (! $fnd) {
      push @lines, "$vuser.$domain: $entry\n";
      writelog("vdomain $user: add alias entry - $vuser.$domain: $entry");
   }

   open ($fh, ">$file") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $file ($!)");

   print $fh @lines;

   root_close($fh, $file, $origruid, $origeuid);

   # rebuild postfix virtual map index
   vpostfix_cmd('postalias',$file);
   return;
}
##################### END VALIAS_UPDATE ##################

##################### VPASSWD_UPDATE ##################
sub vpasswd_update {
   my ($vuser,$delete,$pwd)=@_;
   my $encrypted;
   if (! $delete) {
      srand();
      my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
      my $salt=substr($table, int(rand(length($table))), 1).
                     substr($table, int(rand(length($table))), 1);
      $encrypted=crypt($pwd, $salt);
   }

   # update the passwd file directly without copying to .tmp file
   # why?  Password file is only used to validate login by vm-pop3d
   # A lock here at worst will only momentarily delay another user pop login.
   # We should be in and out of this file fast enough to not be noticed.

   my ($fh, $file, $origruid, $origeuid) = root_open("$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}");

   my $fnd=0;
   $fnd=1 if ($delete);
   my @lines;
   while (<$fh>) {	# read the pwd file
      if (/^$vuser:/g) {
         if ($delete) {
            writelog("vdomain $user: remove password entry - $vuser");
         } else {
            push @lines, "$vuser:$encrypted\n"; $fnd=1;
         }
      } else {
         push @lines, $_;
      }
   }
   close ( $fh );
   if ( ! $fnd ) {
      push @lines, "$vuser:$encrypted\n";
      writelog("vdomain $user: add passwd entry - $vuser");
   }

   open ($fh, ">$file") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $file ($!)");

   print $fh @lines;

   root_close($fh, $file, $origruid, $origeuid);
   return;
}
##################### END VPASSWD_UPDATE ##################

##################### VPOSTFIX_CMD ##################
sub vpostfix_cmd {
   my ($cmd, $file)=@_;
   my $postalias_bin=$config{"vdomain_postfix_$cmd"};
   $postalias_bin =~ s/^(.+)$/$1/;	# untaint
   
   # set ruid/euid to root before calling command
   my ($origruid, $origeuid)=($<, $>); $>=0; $<=0;

   system ("$postalias_bin $file");
   
   # go back to orignal uid
   $<=$origruid; $>=$origeuid;
   return;
}
##################### END VPOSTFIX_CMD ##################

##################### ROOT_OPEN ##################
sub root_open {
   $_[0]=~/^\s*([|><+]*)\s*(\S+)/;
   my ($action, $file)=($1, $2);

   # create a file handle
   my $fh = do { local *FH };

   # set ruid/euid to root before change files
   my ($origruid, $origeuid)=($<, $>); 
   $>=0; $<=0;

   if ($action) {
      filelock($file, LOCK_EX) or 
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $file");
   } else {
      filelock($file, LOCK_SH|LOCK_NB) or 
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $file");
   }
   open ($fh, "$action$file") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $file ($!)");

   return ($fh, $file, $origruid, $origeuid);
}
##################### END ROOT_OPEN ##################

##################### ROOT_CLOSE ##################
sub root_close {
   my ($fh, $file, $origruid, $origeuid)=@_;

   close ($fh);
   filelock($file, LOCK_UN);

   if (defined($origruid) && defined($origeuid)) {
      # go back to orignal uid
      $<=$origruid; $>=$origeuid;
   }
   return;
}
##################### END ROOT_CLOSE ##################
