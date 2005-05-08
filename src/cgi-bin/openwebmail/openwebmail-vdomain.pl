#!/usr/bin/suidperl -T
#
# openwebmail-vdomain.pl - virtual domain user management
#
# 2003/02/26 Bernd Bass, owm.AT.adminsquare.de
# 2003/05/09 Scott Mazur, scott.AT.littlefish.ca
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
#
# Version 0.61
#
#  + merge local users and local aliases into user display and edit checks if domain is local
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
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { local $1; $SCRIPT_DIR=$1 }
if ($SCRIPT_DIR eq '' && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { local $1; $SCRIPT_DIR=$1 }
}
if ($SCRIPT_DIR eq '') { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

foreach (qw(ENV BASH_ENV CDPATH IFS TERM)) {delete $ENV{$_}}; $ENV{PATH}='/bin:/usr/bin'; # secure ENV
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);
use File::Path;

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/execute.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($logindomain $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

# If this is a real user (not virtual) then switch to the virtual site config
# this allows real user to be administrator of the vdomains, tricky!
if ( $config{'auth_module'} ne 'auth_vdomain.pl' ) {
   read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   ow::auth::load($config{'auth_module'});
}

# $user has been determined by openwebmain_init()
if (!$config{'enable_vdomain'} || !is_vdomain_adm($user)) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'vdomain_usermgr'} $lang_err{'access_denied'}");
}

# $domain has been determined by openwebmain_init()
foreach ("$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}",
         @{$config{'vdomain_postfix_virtual'}},
         @{$config{'vdomain_postfix_aliases'}}) {
   openwebmailerror(__FILE__, __LINE__, "$_ $lang_err{'doesnt_exist'}") if (! -f $_);
}

my $action = param('action');
writelog("debug - request vdomain begin, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
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
writelog("debug - request vdomain end, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## DISPLAY_VUSERLIST #####################################
sub display_vuserlist {
   my $view = param('view')||'';
   my %vusers=vuser_list();
   my @vusers_list = sort (keys %vusers);
   my $html = applystyle(readtemplate("vdomain_userlist.template"));

   my $temphtml = start_form(-name=>'indexform',
                             -action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl").
                  ow::tool::hiddens(action=>'display_vuserlist',
                                    sessionid=>$thissession,
                                    view=>$view);
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;
   $html =~ s/\@\@\@DOMAINNAME\@\@\@/$domain/;

   $temphtml  = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession"|);
   if ($config{'vdomain_maxuser'}==0 ||
       $#vusers_list+1<$config{'vdomain_maxuser'}) {
      $temphtml .= qq|&nbsp;\n|;
      $temphtml .= iconlink("adduser.gif", $lang_text{'vdomain_createuser'}, qq|accesskey="A" href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=edit_new_vuser&amp;sessionid=$thissession&amp;view=$view"|);
   }
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $txtuonly = qq|<a href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=display_vuserlist&amp;sessionid=$thissession&amp;view=users"|.
                             qq| title="$lang_text{'vdomain_changeview'} $lang_text{'vdomain_usersonly'}">$lang_text{'vdomain_usersonly'}</a>|;
   my $txtua = qq|<a href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=display_vuserlist&amp;sessionid=$thissession&amp;view=useralias"|.
                             qq| title="$lang_text{'vdomain_changeview'} $lang_text{'vdomain_useralias'}">$lang_text{'vdomain_useralias'}</a>|;
   my $txtuaf = qq|<a href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=display_vuserlist&amp;sessionid=$thissession&amp;view=default"|.
                             qq| title="$lang_text{'vdomain_changeview'} $lang_text{'vdomain_fmtuseralias'}">$lang_text{'vdomain_fmtuseralias'}</a>|;

   my %vuseralias=vuser_alias_list(%vusers);
   my %vuserfwd=vuser_fwd_list(@vusers_list);

   $temphtml = '';
   my %cell=(); my @order=();
   if ( $view eq 'users' ) {
      # list only users
      $temphtml = "$lang_text{'vdomain_usersonly'}, $txtua, $txtuaf";
      foreach (@vusers_list) {
         $cell{$_}=displaycell($_,$_,$view,\%vusers,\%vuserfwd);
         push @order, $_;
      }
   } elsif ( $view eq 'useralias' ) {
      # list users and aliases together
      $temphtml = "$txtuonly, $lang_text{'vdomain_useralias'}, $txtuaf";
      foreach (sort keys %{$vuseralias{'list'}}) {
         $cell{$_}=displaycell($_,$vuseralias{'list'}{$_},$view,\%vusers,\%vuserfwd);
         push @order, $_;
      }
   } else {
      # list users and aliases grouped by user, formatted
      $temphtml = "$txtuonly, $txtua, $lang_text{'vdomain_fmtuseralias'}";
      my $i=0;
      foreach (@vusers_list) {
         if (defined $vuseralias{'aliases'}{$_}) {
            while ($i%4 != 0) {
               push @order,'@blank@';
               $i++;
            }
            $cell{$_}=displaycell($_,$_,$view,\%vusers,\%vuserfwd);
            push @order, $_;
            $i++;
            foreach my $alias (sort @{$vuseralias{'aliases'}{$_}}) {
               if ($i%4 == 0) {
                  push @order,'@blank@';
                  $i++;
               }
               $cell{$alias}=$alias;
               push @order, $alias;
               $i++;
            }
            while ($i%4 != 0) {
               push @order,'@blank@';
               $i++;
            }
         } else {
            $cell{$_}=displaycell($_,$_,$view,\%vusers,\%vuserfwd);
            push @order, $_;
            $i++;
         }
      }
   }
   $html =~ s/\@\@\@VIEWFMT\@\@\@/$temphtml/;

   $temphtml = '';
   my $bgcolor=$style{'tablerow_dark'};
   my $i=0;
   foreach (@order) {
      if ($i%4==0 and $_ ne '@blank@' ) {
         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"};
         } else {
            $bgcolor = $style{"tablerow_dark"};
         }
      }
      $temphtml .= qq|<tr bgcolor=$bgcolor>| if ($i%4==0);
      $temphtml .= qq|<td width="25%">$cell{$_}</td>|;
      $temphtml .= qq|</tr>| if ($i%4==3);
      $i++;
   }
   if ($i%4 != 0) {
      while ($i%4 != 0) {
         $temphtml .= qq|<td></td>|;
         $i++;
      }
      $temphtml .= qq|</tr>|;
   }
   $html =~ s/\@\@\@USERS\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html,  htmlfooter(2)]);

}
########## END DISPLAY_VUSERLIST #################################

########## DISPLAYCELL ###########################################
sub displaycell {
      my ($useralias,$useredit,$view,$vusers,$vuserfwd)=@_;
      my $oldchklogin=0;
      my $oldchkfwd=0;
      my $olddirect='';
      my $userdisp='';

      $userdisp = $lang_text{'vdomain_admin'} if is_vdomain_adm($useredit);
      if ($$vusers{$useredit}=~/^%/) {
          $userdisp .= ', ' if ($userdisp);
          $userdisp .= $lang_text{'vdomain_localuser'};
      }
      $oldchklogin=1 if ($$vusers{$useredit}=~/^#/);
       if ( $$vuserfwd{$useredit} ) {
          $oldchkfwd=1;
          $olddirect=$$vuserfwd{$useredit};
      }
      my $note='';
      $note = $lang_text{'disable'} if ($oldchklogin);
      if ($oldchkfwd) {
         $note .= ', ' if ($note);
         $note .= $lang_text{'forward'}
      }
      $userdisp= " <I>- $userdisp</I>" if ($userdisp);
      if ($useralias ne $useredit) {
         $useralias.=" ($useredit)";
      } else {
         $useralias = "$useredit$userdisp";
      }
      $useralias="<I>($note)</I> $useralias" if ($note);
      return $useralias if ($$vusers{$useredit}=~/^%/);
      return qq|<a href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=edit_vuser&amp;vuser=$useredit&amp;sessionid=$thissession&amp;view=$view| .
                  qq|&amp;oldchklogin=$oldchklogin&amp;oldchkfwd=$oldchkfwd&amp;olddirect=$olddirect" title="$lang_text{'vdomain_changeuser'} $useredit">$useralias</a>|;
}
########## END DISPLAYCELL #######################################

########## EDIT USER #############################################
sub edit_vuser {
   my ($focus, $alert, $pwd, $pwd2, $emailkey, $e_realnm, $realnm, %from_list)=@_;
   my $vuser = param('vuser')||'';
   my $action = param('action')||'';
   my $view = param('view')||'';
   my $oldchklogin=param('oldchklogin')||'';
   my $oldchkfwd=param('oldchkfwd')||'';
   my $olddirect=param('olddirect')||'';
   my $chklogin=$oldchklogin;
   my $chkfwd=$oldchkfwd;
   my $direct=$olddirect;
   $chklogin=param('chklogin') if (param('chklogin'));
   $chkfwd=param('chkfwd') if (param('chkfwd'));
   $direct=param('direct') if (param('direct'));

   my ($title_txt, $setpass_txt, $del_txt, $chg_txt, $user_txt);
   my $new=0;
   $new=1 if ($action=~/new/);
   my $admn=is_vdomain_adm($vuser);
   if ($action=~/edit/) {
      if ($new) {
         $focus='vuser';
      } else {
         $pwd = '*********';
         $pwd2=$pwd;
         ($realnm,%from_list) = from_list(lc($vuser));
         $focus='emailaddr';
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
      if ($admn){
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

   my $temphtml = start_form(-name=>'userform',
                             -action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl").
                  ow::tool::hiddens(action=>$action,
                                    sessionid=>$thissession,
                                    view=>$view,
                                    oldchklogin=>$oldchklogin,
                                    oldchkfwd=>$oldchkfwd,
                                    olddirect=>$olddirect,
                                    addmod=>'',
                                    aliasdel=>'').
                  hidden(-name=>'fromlist',
                         -default=>[%from_list],
                         -override=>'1');
   $temphtml .= ow::tool::hiddens(vuser=>$vuser) if (! $new);
   $html =~ s/\@\@\@STARTUSERFORM\@\@\@/$temphtml/;

   $html =~ s/\@\@\@FOCUS\@\@\@/$focus/;
   $html =~ s/\@\@\@VUSER\@\@\@/$user_txt/;
   $temphtml = textfield(-name=>'realnm',
                            -default=>$realnm,
                            -size=>'50',
                            -override=>'1');
   $html =~ s/\@\@\@REALNAME\@\@\@/$temphtml/;

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

   if ( $admn ) {
      $html =~ s/\@\@\@CHKLOGIN\@\@\@//;
      $html =~ s/\@\@\@DISABLECHKLOGIN\@\@\@/<I>($lang_text{'disable'}) <\/I>/;
   } else {
      $temphtml = checkbox(-name=>'chklogin',
                     -value=>'1',
                     -checked=>$chklogin,
                     -label=>'');
      $html =~ s/\@\@\@CHKLOGIN\@\@\@/$temphtml/;
      $html =~ s/\@\@\@DISABLECHKLOGIN\@\@\@//;
   }
   $temphtml = checkbox(-name=>'chkfwd',
                  -value=>'1',
                  -checked=>$chkfwd,
                  -label=>'');
   $html =~ s/\@\@\@CHKFWD\@\@\@/$temphtml/;
   $temphtml = textfield(-name=>'direct',
                           -default=>$direct,
                           -size=>'40',
                           -override=>'1');
   $html =~ s/\@\@\@DIRECT\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'emailaddr',
                            -default=>$emailkey,
                            -size=>'40',
                            -override=>'1');
   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'e_realnm',
                            -default=>$e_realnm,
                            -size=>'50',
                            -override=>'1');
   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=>'addmod_button',
                           -value=>$lang_text{'addmod'},
                           -onClick=>'AddMod()',
                           -class=>'medtext');
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach ( sort keys %from_list ) {
      my $key=$_;$key=~s/'/\\'/;      # escape ' for javascript
      my $val=$from_list{$_};$val=~s/'/\\'/;
      my $txt=$_;
      $txt .= " ($lang_text{'email_alias'})" if (/\@$domain$/);
      $temphtml .= qq|<tr bgcolor=$bgcolor |.
                   qq|onMouseOver='this.style.backgroundColor=$style{tablerow_hicolor};' |.
                   qq|onMouseOut='this.style.backgroundColor=$bgcolor;' |.
                   qq|>\n|.
                   qq|<td><a href="Javascript:Update('$key','$val')">$txt</a></td>|.
                   qq|<td>$from_list{$_}</td>|.
                   qq|<td align="center">|.
                   submit(-name=>'aliasdel_button',
                          -value=>$lang_text{'delete'},
                          -onClick=>"Delete('$key')",
                          -class=>'medtext') .
                   qq|</td></tr>\n|;
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
   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl").
               ow::tool::hiddens(action=>'delete_vuser',
                                 sessionid=>$thissession,
                                 view=>$view,
                                 vuser=>$vuser);
   $html =~ s/\@\@\@STARTDELFORM\@\@\@/$temphtml/;
   $html =~ s/\@\@\@DELETEBUTTON\@\@\@/$del_txt/;

   # cancel button
   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-vdomain.pl").
               ow::tool::hiddens(action=>'display_vuserlist',
                                 sessionid=>$thissession,
                                 view=>$view);
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
########## END EDIT USER #########################################

########## CHANGE USER SETTINGS ##################################
sub change_vuser {
   my $vuser_original=param('vuser')||'';
   my $realnm=param('realnm')||'';
   my $vuser=ow::tool::untaint(lc($vuser_original));

   my $action=param('action')||'';
   my $pwd=param('newpassword')||'';
   my $pwd2=param('confirmnewpassword')||'';
   my $emailkey=clean_email(param('emailaddr'));
   my $alias=$emailkey;
   $alias=~s/\@.*// if ($emailkey=~/\@$domain$/);

   my $e_realnm=param('e_realnm')||'';
   $e_realnm=~s/^\s*//;$e_realnm=~s/\s*$//;

   my $oldchklogin=param('oldchklogin')||'';
   my $oldchkfwd=param('oldchkfwd')||'';
   my $olddirect=param('olddirect')||'';
   my $chklogin=param('chklogin')||'';
   $chklogin=0 if (is_vdomain_adm($vuser));

   my $chkfwd=param('chkfwd')||'';
   my $direct=param('direct')||'';
   my %from_list=param('fromlist');

   my %vusers=vuser_list();
   my @vuser_list = sort (keys %vusers);
   my @alias_list=from_2_valias($vuser,%from_list);
   my $new=0;
   $new=1 if ($action=~/new/);
   my $focus='emailaddr';
   my $alert;

   if ($new) {
      openwebmailerror(__FILE__, __LINE__, $lang_err{'vdomain_toomanyuser'}) if ($config{'vdomain_maxuser'}>0 and @vuser_list>$config{'vdomain_maxuser'});
      if ( $pwd =~ /\*\*/ ) {
         $pwd='';
         $pwd2=$pwd;
      }
   } else {
      openwebmailerror(__FILE__, __LINE__, "$vuser\@$domain $lang_err{'doesnt_exist'}") if (! vuser_exists($vuser,@vuser_list) );
   }

   delete $from_list{lc(param('aliasdel'))} if ( param('aliasdel') );

   if ( $emailkey ) {
      if ( $alias ne $emailkey and $alias ne $vuser) {
         # alias entry needs additional edit checks.
         if ( ! defined $from_list{$emailkey} and $config{'vdomain_maxalias'} < ($#alias_list + 2) ) {
            $alert=$lang_err{'vdomain_toomanyalias'};
         } elsif ( valias_list_exists($vuser,$alias) ) {
             $alert="$alias\@$domain $lang_err{'already_exists'}";
         }
      }
      if (! $alert) {
         if ( $alias eq $vuser ) {$realnm=$e_realnm}
         else {
            $from_list{$emailkey}=$e_realnm;
            @alias_list=from_2_valias($vuser,%from_list);    # refresh the alias list
         }
         $emailkey='';
         $e_realnm='';
      }
   }

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
      if (! $vuser ) {
         $alert = $lang_err{'vdomain_userrequired'};
         $focus='vuser';
      }
      elsif (vuser_exists($vuser,@vuser_list) or valias_list_exists($vuser,$vuser)) {
         $alert = "$vuser\@$domain $lang_err{'already_exists'}";
         $focus='vuser';
      }
   }

   if ( $chkfwd ) {
      if ( $direct =~ /[&;\`\<\>\(\)\{\}]/) {
         $alert = "$lang_text{'forward'} $lang_text{'email'} $lang_err{'has_illegal_chars'}";
         $focus='direct';
      } else {
         # remove self email from forward list
         my @forwards=();
         foreach ( split(/[,;\n\r]+/, $direct ) ) {
            $_=clean_email($_);
            next if ( /^$/ or /^$vuser\@$domain$/ );
            push @forwards,$_;
         }
         my $tempdirect=join(', ',@forwards);
         if ( ! $tempdirect ) {
            $alert = $lang_err{'vdomain_fwdrequired'};
            $focus='direct';
         } else { $direct = $tempdirect; }
      }
   }

   if ( $alert or param('addmod') or param('aliasdel') ) {
      edit_vuser($focus, $alert, $pwd, $pwd2, $emailkey, $e_realnm, $realnm, %from_list);
      return;
   }

   my $vgid=getgrnam('mail');	# for better compatibility with other mail progs

   if ( $new ) { # CREATE NEW USER
      my $aliastxt='';
      $aliastxt=" - aliases: @alias_list" if (@alias_list);
      writelog("vdomain $user: create vuser $vuser\@$domain$aliastxt" );
      # CREATE USER IN VIRTUAL PASSWD
      vpasswd_update($vuser_original,0,$pwd,$chklogin);

      my ($vuid, $vhomedir, $release) = get_uid_home_release($vuser,$domain);

      # switch to root
      my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();

      # CREATE USER HOME DIRECTORY
      if ( !-d $vhomedir ) {
         if (mkdir ($vhomedir, 0700) && chown($vuid, $vgid, $vhomedir)) {
            writelog("vdomain $user: $vuser\@$domain  create homedir - $vhomedir, uid=$vuid, gid=$vgid");
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $vhomedir ($!)");
         }
      }

      # switch to virtual user
      ow::suid::set_euid_egids($vuid, $vgid);

      # create dot directory structure
      check_and_create_dotdir(_dotpath('/', $domain, $vuser, $vhomedir));

      # default a new release date file
      my $releasedatefile=_dotpath('release.date', $domain, $vuser, $vhomedir);
      writelog("vdomain $user: $vuser\@$domain  create release.date - $releasedatefile, uid=$vuid, gid=$vgid");
      sysopen(RD, $releasedatefile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $releasedatefile ($!)");
      print RD "$config{'releasedate'}\n";
      close(RD);
      chmod(0700, $releasedatefile);

      # CREATE USER .forward
      my $dotforward="$vhomedir/.forward";
      writelog("vdomain $user: $vuser\@$domain  create .forward - $dotforward, uid=$vuid, gid=$vgid");
      sysopen(DF, $dotforward, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $dotforward ($!)");
      print DF vdomain_userspool($vuser, $vhomedir)."\n";
      close(DF);
      chmod(0700, $dotforward);

      # return to orignal uid
      ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

      # CREATE USER .FROM.BOOK
      from_update($vuser, $vhomedir, $config{'releasedate'}, $vuid, $vgid, $realnm, %from_list);

      # CREATE USER IN POSTFIX VIRTUAL
      vuser_update($vuser, 0, @alias_list);

      # CREATE USER IN POSTFIX ALIASES
      if ($chkfwd) {
         writelog("vdomain $user: $vuser\@$domain  forward to $direct");
         $dotforward=$direct;
      } else { $dotforward=":include:$dotforward" }
      valias_update($vuser, 0, $dotforward);

   } else { # UPDATE EXISTING USER
      # changed password ?
      if ( $pwd !~ /\*\*/ or $chklogin != $oldchklogin ) {
         my $action=0;
         $action=2 if ($pwd =~ /\*\*/);
         vpasswd_update($vuser_original,$action,$pwd,$chklogin);
      }

      my ($vuid, $vhomedir, $release) = get_uid_home_release($vuser,$domain);
      my ($orig_realnm,%orig_from_list) = from_list($vuser); # original values
      my @orig_alias_list=from_2_valias($vuser,%orig_from_list);

      my $match = 1;
      # changed virtual alias?
      if ($#orig_alias_list == $#alias_list) {
         foreach (@alias_list) {
            if ($_ ne $orig_alias_list[0] ) {
               $match=0;
               last;
            }
            shift @orig_alias_list;
         }
         $match=0 if ( $#orig_alias_list >= 0 );
      } else { $match=0; }
      if (! $match) {
         vuser_update($vuser, 0, @alias_list);
      } else {
         # changed froms?
         if ($orig_realnm eq $realnm) {
            foreach (keys %from_list) {
               if (!defined $orig_from_list{$_} or $orig_from_list{$_} ne $from_list{$_} ) {
                  $match=0;
                  last;
               }
               delete $orig_from_list{$_};
            }
            $match=0 if ( keys %orig_from_list );
         } else { $match=0; }
      }
      from_update($vuser, $vhomedir, $release, $vuid, $vgid, $realnm, %from_list) if ( ! $match );

      # changed fwd to
      if ($chkfwd != $oldchkfwd or $direct ne $olddirect) {
         if ($chkfwd) {
            writelog("vdomain $user: $vuser\@$domain  forward to $direct");
            valias_update($vuser, 0, $direct);
         } else {
            writelog("vdomain $user: $vuser\@$domain  remove forward");
            valias_update($vuser, 0, ":include:$vhomedir/.forward");
         }
      }
   }

   display_vuserlist();
}

########## END CHANGE USER #######################################

########## DELETE USER  ##########################################
sub delete_vuser {
   my $vuser_original = param('vuser')||'';
   my $vuser=ow::tool::untaint(lc($vuser_original));

   if ( vuser_exists($vuser,vuser_list()) ) {
      # get the home directory before we remove the user from password file or trouble later!
      my ($vuid, $vhomedir, $release) = get_uid_home_release($vuser,$domain);

      writelog("vdomain $user: $vuser\@$domain  delete $vuser_original");
      # DELETE USER IN VMPOP3D PASSWD
      vpasswd_update($vuser_original,1);
      # DELETE USER IN POSTFIX VIRTUAL
      vuser_update($vuser, 1);
      # DELETE USER IN POSTFIX ALIASES
      valias_update($vuser, 1);

      # switch to root
      my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();

      # DELETE MAILBOX FILE
      my $spoolfile=ow::tool::untaint("$config{'vdomain_vmpop3_mailpath'}/$domain/$vuser");
      if (-e $spoolfile) {
         writelog("vdomain $user: $vuser\@$domain  remove spool file - $spoolfile");
         rmtree ($spoolfile);
      }

      # DELETE OWM USER SETTINGS
      my $userconf=ow::tool::untaint("$config{'ow_cgidir'}/etc/users.conf/$domain/$vuser");
      if (-e $userconf) {
         writelog("vdomain $user: $vuser\@$domain  remove userconf file - $userconf");
         rmtree ($userconf);
      }

      # DELETE HOME DIRECTORY
      if (-e $vhomedir) {
         writelog("vdomain $user: $vuser\@$domain  remove vhomedir - $vhomedir");
         rmtree ($vhomedir);
      }

      # return to orignal uid
      ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   }

   # go back to start and display index
   display_vuserlist();
}
########## END DELETE USER #######################################

########## VUSER_LIST ############################################
sub vuser_list {
   my %vusers;

   # USERLIST FROM VMPOP3D PASSWD
   my ($fh, $file, $origruid, $origeuid, $origegid) = root_open("$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}");
   while (<$fh>) {
      next if (/^#/);
      chomp;
      $vusers{$1}=$2 if (/([^:]+):([^\s:]+)/);
   }
   root_close($fh, $file, $origruid, $origeuid, $origegid);

   # include users from localusers if this is the local domain
   foreach  ( @{$config{'localusers'}} ) {
      $vusers{$1} = '%' if (/^([^@]+)\@$domain$/);
   }
   return (%vusers);
}
########## END VUSER_LIST ########################################

########## VUSER_ALIAS_LIST ######################################
sub vuser_alias_list {
   my (%vuser_list)=@_;
   my %vusers=();
   my %temp=();
   my %alias=();

   # include the user list as default aliases
   foreach (keys %vuser_list) {
      $temp{$_}=$_;
      $vusers{"$_.$domain"}=1if ($vuser_list{$_}!~/^%/);
   }

   # load up the virtual aliases
   foreach my $virtualfile (@{$config{'vdomain_postfix_virtual'}}) {
      my ($fh, $file, $origruid, $origeuid, $origegid) = root_open($virtualfile);
      while (<$fh>) {
         next if (/^#/);
         $temp{lc($1)}=lc($2) if ( /^\s*([^@]+)\@$domain\s+(\S+)\.$domain\s*$/i );
      }
      root_close($fh, $file, $origruid, $origeuid, $origegid);
   }

   # add in the local user aliases
   if (is_localdomain()) {
      foreach my $aliasfile (@{$config{'vdomain_postfix_aliases'}}) {
         my ($fh, $file, $origruid, $origeuid, $origegid) = root_open($aliasfile);
         while (<$fh>) {
            s/^\s+//;s/\s+$//;
            $temp{lc($1)}=lc($2) if( ! /^#/ and /^([^\s:]+)\s*:\s*(.+)$/ and ! $vusers{$1});
         }
         root_close($fh, $file, $origruid, $origeuid, $origegid);
      }
      # compact the aliases of aliases
      foreach (keys %temp) {
         my $brkloop=500; # carefull of alias loops!
         while ($temp{$temp{$_}} and $temp{$_} ne $temp{$temp{$_}} and $brkloop) { $brkloop--; $temp{$_}=$temp{$temp{$_}} }
         writelog( "vdomain $user $_ is stuck in an alias loop.") if (! $brkloop);
      }
   }

   foreach ( keys %temp ) {
      $alias{'list'}{$_}=$temp{$_};
      push @{$alias{'aliases'}{$temp{$_}}}, $_  if ( $temp{$_} ne $_ );
   }
   return %alias;
}
########## END VUSER_ALIAS_LIST ##################################

########## VUSER_FWD_LIST ########################################
sub vuser_fwd_list {
   my @vusers=@_;
   my %fwd;
   foreach (@vusers){$fwd{$_}=0}
   my ($fh, $file, $origruid, $origeuid, $origegid) = root_open(${$config{'vdomain_postfix_aliases'}}[0]);
   while (<$fh>) {
      next if (/^#/);
      if ( /^\s*(\S+)\.$domain\s*:\s*(.+)/i and defined $fwd{lc($1)}) {
         my ($user,$entry)=(lc($1),$2);
         $entry=~s/\s*$//;
         $fwd{$user}=$entry if ( $entry !~ /:include:/ );
      }
   }
   root_close($fh, $file, $origruid, $origeuid, $origegid);
   return %fwd;
}
########## END VUSER_FWD_LIST ####################################

########## VALIAS_LIST ###########################################
sub valias_list {
   my ($vuser)=@_;
   my (@alias_list, $alias);

   # POSTFIX VIRTUAL=> john@sample.com    john.sample.com
   foreach my $virtualfile (@{$config{'vdomain_postfix_virtual'}}) {
      my ($fh, $file, $origruid, $origeuid, $origegid) = root_open($virtualfile);
      while (<$fh>) {
         next if (/^#/);
         if ( /^\s*([^@]+)\@$domain\s+$vuser\.$domain\s*$/ ) {
            if ( $1 ne $vuser ) {
               $alias=lc($1);
               push @alias_list, $alias;
            }
         }
      }
      root_close($fh, $file, $origruid, $origeuid, $origegid);
   }
   return (sort @alias_list);
}
########## END VALIAS_LIST #######################################

########## VALIAS_LIST_EXISTS ####################################
sub valias_list_exists {
   my ($vuser,$alias)=@_;
   my $fnd=0;

   foreach my $virtualfile (@{$config{'vdomain_postfix_virtual'}}) {
      my ($fh, $file, $origruid, $origeuid, $origegid) = root_open($virtualfile);
      while (<$fh>) {
         next if (/^#/);
         chomp; s/^\s*//; s/\s*$//;
         if ( /^$alias\@$domain\s*(\S+)\.$domain\s*$/ and $1 ne $vuser ) {
            $fnd=1; last;
         }
      }
      root_close($fh, $file, $origruid, $origeuid, $origegid);
      last if ($fnd);
   }

   # check local aliases if localdomain
   if (! $fnd and is_localdomain()) {
      foreach my $aliasfile (@{$config{'vdomain_postfix_aliases'}}) {
         my ($fh, $file, $origruid, $origeuid, $origegid) = root_open($aliasfile);
         while (<$fh>) {
            if( /^\s*$alias\s*:/ ) {
               $fnd=1; last;
            }
         }
         root_close($fh, $file, $origruid, $origeuid, $origegid);
         last if ($fnd);
      }
   }
   return ($fnd);
}
########## END VALIAS_LIST_EXISTS ################################

########## IS_LOCALDOMAIN ########################################
sub is_localdomain {
   foreach  ( @{$config{'localusers'}} ) {
      return 1 if (/^([^@]+)\@$domain$/);
   }
   return 0;
}
########## END IS_LOCALDOMAIN ####################################

########## FROM_2_VALIAS #########################################
sub from_2_valias {
   my ($vuser, %from_list)=@_;
   my %alias_list=();
   foreach (keys %from_list) {
      $alias_list{$1}=1 if (/([^@]+)\@$domain$/ and $1 ne $vuser);
   }
   return (sort keys %alias_list);
}
########## END FROM_2_VALIAS #####################################

########## FROM_LIST #############################################
# merge the from address book with the postfix aliases
# If the Real user (not an alias) has an entry in the from.book then
# Use the name value to set the user $realnm (don't include with the rest
# of the from names).
sub from_list {
   my ($vuser)=@_;
   my $realnm='';
   my ($vuid, $vhomedir, $release) = get_uid_home_release($vuser,$domain);
   my $frombook=_dotpath('from.book',$domain,$vuser,$vhomedir);

   # the user home directory structure changed pre 20031128
   # better try to get the correct frombook path
   if ($release lt "20031128") {
      $frombook="$vhomedir/$config{'homedirfolderdirname'}/.from.book";
      $frombook=ow::tool::untaint($frombook);
   }

   my %fromlist=();
   if ( root_exists($frombook) ) {
      my ($fh, $file, $origruid, $origeuid, $origegid) = root_open($frombook);
      while (<$fh>) {
         chomp;
         if ( /^\s*(\S+)\@\@\@(.*)\s*$/ ) {
            my ($mail, $name)=(lc($1),$2);
            $mail .= "\@$domain" if ($mail !~/\@/);
            if ($mail=~/^$vuser\@$domain$/) {$realnm=$name;}
            else {$fromlist{$mail}=$name;}
         }
      }
      root_close($fh, $file, $origruid, $origeuid, $origegid);
   }

   # add in the email aliases
   foreach ( valias_list($vuser) ){
      $fromlist{"$_\@$domain"}='' if (!defined $fromlist{"$_\@$domain"});
   }
   return $realnm,%fromlist;
}
########## END FROM_LIST #########################################

########## VUSER_EXISTS ##########################################
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
########## END VUSER_EXISTS ######################################

########## VUSER_UPDATE ##########################################
sub vuser_update {
   my ($vuser,$delete, @alias_list)=@_;
   my ($fh, $file, $origruid, $origeuid, $origegid) = root_open(${$config{'vdomain_postfix_virtual'}}[0]);

   my $fnd=0;
   my @lines;
   while (<$fh>) {	# read the virtual user file
      if (/^#/) {
         push @lines, $_;
      } elsif ( /^\s*\S+\s+$vuser\.$domain\s*$/ ) { # remove existing entries for this user
         if ($delete) {
            s/\n//g; writelog("vdomain $user: $vuser\@$domain  remove virtual entry - $_");
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
               writelog("vdomain $user: $vuser\@$domain  update aliases: @alias_list") if (@alias_list);
            }
         }
         push @lines, $_;
      }
   }
   close( $fh );

   if ($fnd < 2 and ! $delete) {
      push @lines,"$vuser\@$domain\t$vuser.$domain\n";
      writelog("vdomain $user: $vuser\@$domain  add virtual entry - $vuser.$domain") if (! $fnd);
      foreach my $alias (@alias_list) {
         push @lines,"$alias\@$domain\t$vuser.$domain\n";
         writelog("vdomain $user: $vuser\@$domain  add virtual entry - $alias\@$domain  $vuser.$domain") if (! $fnd);
      }
   }

   sysopen($fh, $file, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $file ($!)");

   print $fh @lines;

   root_close($fh, $file, $origruid, $origeuid, $origegid);

   # rebuild postfix virtual map index
   root_execute($config{'vdomain_postfix_postmap'}, $file);

   return;
}
########## END VUSER_UPDATE ######################################

########## FROM_UPDATE ###########################################
sub from_update {
   my ($vuser, $vhomedir, $releasedate, $vuid, $vgid, $realnm, %from_list)=@_;
   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   ow::suid::set_euid_egids($vuid, $vgid);

   my $frombook=_dotpath('from.book', $domain, $vuser, $vhomedir);

  # the user home directory structure changed pre 20031128
  # better try to get the correct frombook path
   if ($releasedate lt "20031128") {
      $frombook="$vhomedir/$config{'homedirfolderdirname'}/.from.book";
      $frombook=ow::tool::untaint($frombook);
   }

   if (-e $frombook) { writelog("vdomain $user: $vuser\@$domain  update from.book - $frombook"); }
   else { writelog("vdomain $user: $vuser\@$domain  create from.book - $frombook, uid=$<, gid=$>"); }

   ow::filelock::lock($frombook, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $frombook");
   sysopen(FB, $frombook, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $frombook ($!)");

   print FB "$vuser\@$domain\@\@\@$realnm\n" if ($realnm);
   foreach (sort keys %from_list) {
      print FB "$_\@\@\@$from_list{$_}\n";
   }
   close(FB);
   ow::filelock::lock($frombook, LOCK_UN);

   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return;
}
########## END FROM_UPDATE #######################################

########## VALIAS_UPDATE #########################################
sub valias_update {
   my ($vuser,$delete,$entry)=@_;
   my ($fh, $file, $origruid, $origeuid, $origegid) = root_open(${$config{'vdomain_postfix_aliases'}}[0]);

   my $fnd=0;
   $fnd=1 if ($delete);
   my @lines;
   while (<$fh>) {	# read the alias file
      if ( /^\s*$vuser\.$domain\s*:/ ) { # replace existing entry for this alias
         if ($delete) {
            s/\n//g; writelog("vdomain $user: $vuser\@$domain  remove aliases entry - $_");
         } else {
            push @lines, "$vuser.$domain:\t$entry\n"; $fnd=1;
            writelog("vdomain $user: $vuser\@$domain  update alias entry - $vuser.$domain: $entry");
         }
      } else {
         push @lines, $_;
      }
   }
   close( $fh );
   if (! $fnd) {
      push @lines, "$vuser.$domain:\t$entry\n";
      writelog("vdomain $user: $vuser\@$domain  add alias entry - $vuser.$domain: $entry");
   }

   sysopen($fh, $file, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $file ($!)");

   print $fh @lines;

   root_close($fh, $file, $origruid, $origeuid, $origegid);

   # rebuild postfix virtual map index
   root_execute($config{'vdomain_postfix_postalias'}, $file);

   return;
}
########## END VALIAS_UPDATE #####################################

########## VPASSWD_UPDATE ########################################
sub vpasswd_update {
   my ($vuser,$action,$pwd,$disable)=@_;
   # $action = 0  encrypt and change password
   # $action = 1  delete password entry
   # $action = 2  switch enable/disable on existing password
   my $encrypted;
   if ( $action==0 ) {
      srand();
      my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
      my $salt=substr($table, int(rand(length($table))), 1).
                     substr($table, int(rand(length($table))), 1);
      $encrypted=crypt($pwd, $salt);
      $encrypted="#$encrypted" if ($disable);
   }

   # update the passwd file directly without copying to .tmp file
   # why?  Password file is only used to validate login by vm-pop3d
   # A lock here at worst will only momentarily delay another user pop login.
   # We should be in and out of this file fast enough to not be noticed.

   my ($fh, $file, $origruid, $origeuid, $origegid) = root_open("$config{'vdomain_vmpop3_pwdpath'}/$domain/$config{'vdomain_vmpop3_pwdname'}");

   my $fnd=0;
   $fnd=1 if ($action==1);
   my @lines;
   while (<$fh>) {	# read the pwd file
      if (/^$vuser:(.)/) {
         if ($action==1) {
            writelog("vdomain $user: $vuser\@$domain  remove password entry");
         } else {
            $fnd=1;
            if ($action==2) {
               if ( $1 eq '#' and ! $disable ) {
                  s/:#/:/;
                  writelog("vdomain $user: $vuser\@$domain  restore user login");
               }
               s/:/:#/ if ( $1 ne '#' and $disable );
               push @lines, $_;
            } else {
               push @lines, "$vuser:$encrypted\n";
               writelog("vdomain $user: $vuser\@$domain  update vuser password");
            }
         }
      } else {
         push @lines, $_;
      }
   }
   close( $fh );
   if ( ! $fnd ) {
      push @lines, "$vuser:$encrypted\n";
      writelog("vdomain $user: $vuser\@$domain  create passwd entry");
   }
   writelog("vdomain $user: $vuser\@$domain  disable user login") if ($disable);

   sysopen($fh, $file, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $file ($!)");

   print $fh @lines;

   root_close($fh, $file, $origruid, $origeuid, $origegid);
   return;
}
########## END VPASSWD_UPDATE ####################################

########## GET_UID_HOME_RELEASE ##########################################
sub get_uid_home_release {
   my ($user, $domain)=@_;
   my $releasedate='';

   # switch to root
   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();

   my ($ret,$err,$uid,$homedir) = (ow::auth::get_userinfo(\%config, "$user\@$domain"))[0,1,3,5];
   openwebmailerror(__FILE__, __LINE__, "$lang_err{'auth_syserr'} ret $ret, $err") if ($ret!=0);

   if ( !$config{'use_syshomedir'} ) {
      $homedir = "$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/".$user:$user);
   }
   $homedir=ow::tool::untaint($homedir);

   my $releasedatefile=_dotpath('release.date', $domain, $user, $homedir);
   $releasedatefile="$homedir/$config{'homedirfolderdirname'}/.release.date" if (! -f $releasedatefile);
   $releasedatefile="$homedir/.release.date" if (! -f $releasedatefile);
   $releasedatefile=ow::tool::untaint($releasedatefile);

   # the release date file may very well not exist!
   if (sysopen(D, $releasedatefile, O_RDONLY)) {
      $releasedate=<D>;
      chomp($releasedate);
      close(D);
   }

   # return to original user
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

   return ($uid,$homedir,$releasedate);
}

########## ROOT_EXECUTE ##########################################
sub root_execute {
   my @cmd;
   foreach my $arg (@_) {
      foreach (split(/\s+/, $arg)) {
         /^(.+)$/ && push(@cmd, $1);
      }
   }

   # switch to root
   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();

   # use execute.pl instead of system() to avoid shell escape chars in @cmd
   my ($stdout, $stderr, $exit, $sig)=ow::execute::execute(@cmd);

   # return to original user
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

   return;
}
########## END ROOT_EXECUTE ######################################

########## ROOT_OPEN #############################################
# open a file using root permissions
sub root_open {
   $_[0]=~/^\s*([|><+]*)\s*(\S+)/;
   my ($action, $file)=($1, $2);

   # create a file handle
   my $fh = do { local *FH };

   # switch to root
   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();

   if ($action ne '') {
      ow::filelock::lock($file, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $file");
   } else {
      ow::filelock::lock($file, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} $file");
   }
   sysopen($fh, "$action$file", O_RDONLY) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $file ($!)");

   return ($fh, $file, $origruid, $origeuid, $origegid);
}
########## END ROOT_OPEN #########################################

########## ROOT_CLOSE ############################################
# close a file using root permissions
sub root_close {
   my ($fh, $file, $origruid, $origeuid, $origegid)=@_;

   close($fh);
   ow::filelock::lock($file, LOCK_UN);

   # return to original user
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

   return;
}
########## END ROOT_CLOSE ########################################

########## ROOT_EXISTS ###########################################
# check if file exists using root permissions
sub root_exists {
   my ($file)=@_;
   my $exist=0;

   # switch to root
   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();

   $exist=1 if (-e $file);

   # return to original user
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

   return $exist;
}
########## END FILE_EXISTS #######################################

########## CLEAN_EMAIL ###########################################
sub clean_email {
   my $email=lc($_[0]);
   $email=~s/\s*//g;                                            # remove spaces
   if ($email ne '') {
      my @temp=split(/\@/,$email);                     # split user domain
      $temp[1]=$domain if (! $temp[1]);               # default local domain
      $temp[0]=safedomainname($temp[0]);     # cleanup user
      $temp[1]=safedomainname($temp[1]);     # cleanup domain
      $email=join( '@',@temp[0,1]);
   }
   return $email;
}
########## END CLEAN_EMAIL #######################################
