#!/usr/bin/suidperl -T
#################################################################
#                                                               #
# Open WebMail - Provides a web interface to user mailboxes     #
#                                                               #
# Copyright (C) 2001-2004                                       #
# The Open Webmail Team                                         #
#                                                               #
# Copyright (C) 2000                                            #
# Ernie Miller  (original GPL project: Neomail)                 #
#                                                               #
# This program is distributed under GNU General Public License  #
#                                                               #
#################################################################

#
# openwebmail.pl - entry point of openwebmail
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
use Socket;	# for gethostbyaddr() in ip2hostname
use MIME::Base64;

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/pop3book.pl";
require "shares/upgrade.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);

# extern vars
use vars qw(@openwebmailrcitem);	# defined in ow-shared.pl
use vars qw(%lang_text %lang_err);	# defined in lang/xy

########## MAIN ##################################################
openwebmail_requestbegin();

load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
loadlang($config{'default_language'});	# so %lang... can be used in error msg

# check & create mapping table for solar/lunar, b2g, g2b convertion
foreach my $table ('b2g', 'g2b', 'lunar') {
   if ( $config{$table.'_map'} && !ow::dbm::exist("$config{'ow_mapsdir'}/$table")) {
      print qq|Content-type: text/html\n\n|.
            qq|Please execute '$config{'ow_cgidir'}/openwebmail-tool.pl --init' on server first!|;
      openwebmail_exit(0);
   }
}

if ($config{'logfile'}) {
   my $mailgid=getgrnam('mail');
   my ($fmode, $fuid, $fgid) = (stat($config{'logfile'}))[2,4,5];
   if ( !($fmode & 0100000) ) {
      open (LOGFILE,">>$config{'logfile'}") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $lang_text{'file'} $config{'logfile'}! ($!)");
      close(LOGFILE);
   }
   chmod(0660, $config{'logfile'}) if (($fmode&0660)!=0660);
   chown($>, $mailgid, $config{'logfile'}) if ($fuid!=$>||$fgid!=$mailgid);
}

if ( $config{'forced_ssl_login'} &&	# check the forced use of SSL
     !($ENV{'HTTPS'}=~/on/i||$ENV{'SERVER_PORT'}==443) ) {
   my ($start_url, $refresh, $js);
   $start_url=$config{'start_url'};
   $start_url="https://$ENV{'HTTP_HOST'}$start_url" if ($start_url!~s!^https?://!https://!i);
   if ($ENV{'HTTP_USER_AGENT'}!~/MSIE.+Mac/) {
      # reload page with Refresh header only if not MSIE on Mac
      $refresh=qq|<meta http-equiv="refresh" content="5;URL=$start_url">|;
   } else {
      # reload page with java script if MSIE on Mac
      $js=qq|<script language="JavaScript">\n<!--\n|.
          qq|setTimeout("window.location.href='$start_url'", 5000);\n|.
          qq|//-->\n</script>|;
   }
   print qq|Content-type: text/html\n\n|.
         qq|<html><head>$refresh</head><body>\n|.
         qq|Service is available over SSL only,<br>\n|.
         qq|you will be redirected to <a href="$start_url">SSL login</a> page in 5 seconds...\n|.
         qq|$js\n|.
         qq|</body></html>\n|;
   openwebmail_exit(0);
}

if ( param('loginname') && param('password') ) {
   login();
} elsif (matchlist_fromhead('allowed_autologinip', ow::tool::clientip()) &&
         cookie('openwebmail-autologin')) {
   autologin();
} else {
   loginmenu();	# display login page if no login
}

openwebmail_requestend();
########## END MAIN ##############################################

########## LOGINMENU #############################################
sub loginmenu {
   # clear vars that may have values from autologin
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)=('', '', '', '', '', '');

   $logindomain=param('logindomain')||lc($ENV{'HTTP_HOST'});
   $logindomain=~s/:\d+$//;	# remove port number
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined($config{'domainname_equiv'}{'map'}{$logindomain}));

   matchlist_exact('allowed_serverdomain', $logindomain) or
      openwebmailerror(__FILE__, __LINE__, "Service is not available for domain  '$logindomain'");

   read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain") if ( -f "$config{'ow_sitesconfdir'}/$logindomain");
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; openwebmail_exit(0);
   }

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   loadlang($prefs{'language'});

   my ($html, $temphtml);
   $html = applystyle(readtemplate("login.template"));

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail.pl",
                         -name=>'login');
   if (defined(param('action'))) {
      $temphtml .= ow::tool::hiddens(action=>param('action'));
      $temphtml .= ow::tool::hiddens(to=>param('to')) if (defined(param('to')));
      $temphtml .= ow::tool::hiddens(subject=>param('subject')) if (defined(param('subject')));
   }
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'loginname',
                         -default=>'',
                         -size=>'14',
                         -onChange=>'focuspwd()',
                         -override=>'1');
   $html =~ s/\@\@\@LOGINNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'password',
                              -default=>'',
                              -size=>'14',
                              -onChange=>'focusloginbutton()',
                              -override=>'1');
   $html =~ s/\@\@\@PASSWORDFIELD\@\@\@/$temphtml/;

   if ($ENV{'HTTP_ACCEPT_ENCODING'}=~/\bgzip\b/ &&
       ow::tool::has_module('Compress/Zlib.pm') ) {
      $temphtml = checkbox(-name=>'httpcompress',
                           -value=>'1',
                           -checked=>cookie("openwebmail-httpcompress")||0,
                           -onClick=>'httpcompresshelp()',
                           -label=>'');
   } else {
      $temphtml = checkbox(-name=>'httpcompress',
                           -value=>'1',
                           -checked=>0,
                           -disabled=>1,
                           -label=>'');
   }
   $html =~ s/\@\@\@HTTPCOMPRESSIONCHECKBOX\@\@\@/$temphtml/;

   if (matchlist_fromhead('allowed_autologinip', ow::tool::clientip()) ) {
      templateblock_enable($html, 'AUTOLOGIN');
      $temphtml = checkbox(-name=>'autologin',
                           -value=>'1',
                           -checked=>cookie("openwebmail-autologin")||0,
                           -onClick=>'autologinhelp()',
                           -label=>'');
      $html =~ s/\@\@\@AUTOLOGINCHECKBOX\@\@\@/$temphtml/;
   } else {
      $temphtml = '';
      templateblock_disable($html, 'AUTOLOGIN', $temphtml);
   }

   if ($config{'enable_domainselectmenu'} && $#{$config{'domainnames'}} >0) {
      templateblock_enable($html, 'DOMAIN');
      $temphtml = popup_menu(-name=>'logindomain',
                             -default=>$logindomain,
                             -values=>[@{$config{'domainselmenu_list'}}] );
      $html =~ s/\@\@\@DOMAINMENU\@\@\@/$temphtml/;
   } else {
      $temphtml = ow::tool::hiddens(logindomain=>param('logindomain')||'');
      templateblock_disable($html, 'DOMAIN', $temphtml);
   }

   $temphtml = submit(-name =>"loginbutton",
		      -value=>$lang_text{'login'} );
   $html =~ s/\@\@\@LOGINBUTTON\@\@\@/$temphtml/;
   $temphtml = reset("$lang_text{'clear'}");
   $html =~ s/\@\@\@CLEARBUTTON\@\@\@/$temphtml/;
   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   # undef env to prevent httpprint() doing compression on login page
   undef $ENV{'HTTP_ACCEPT_ENCODING'};
   httpprint([], [htmlheader(), $html, htmlfooter(1)]);
}
########## END LOGINMENU #########################################

########## LOGIN #################################################
sub login {
   my $clientip=ow::tool::clientip();

   $loginname=param('loginname')||'';
   $default_logindomain=param('logindomain')||'';

   ($logindomain, $loginuser)=login_name2domainuser($loginname, $default_logindomain);

   matchlist_exact('allowed_serverdomain', $logindomain) or
      openwebmailerror(__FILE__, __LINE__, "Service is not available for domain  '$logindomain'");

   if (!is_localuser("$loginuser\@$logindomain") && -f "$config{'ow_sitesconfdir'}/$logindomain") {
      read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   }
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; openwebmail_exit(0);
   }
   ow::auth::load($config{'auth_module'});

   # create domain logfile
   if ($config{'logfile'}) {
      my $mailgid=getgrnam('mail');
      my ($fmode, $fuid, $fgid) = (stat($config{'logfile'}))[2,4,5];
      if ( !($fmode & 0100000) ) {
         open (LOGFILE,">>$config{'logfile'}") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $lang_text{'file'} $config{'logfile'}! ($!)");
         close(LOGFILE);
      }
      chmod(0660, $config{'logfile'}) if (($fmode&0660)!=0660);
      chown($>, $mailgid, $config{'logfile'}) if ($fuid!=$>||$fgid!=$mailgid);
   }

   update_virtuserdb();	# update index db of virtusertable

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   loadlang($prefs{'language'});

   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
				=get_domain_user_userinfo($logindomain, $loginuser);
   if ($user eq "") {
      sleep $config{'loginerrordelay'};	# delayed response
      writelog("login error - no such user - loginname=$loginname");
      # show 'pwd incorrect' instead of 'user not exist' for better security
      my $html = applystyle(readtemplate("loginfailed.template"));
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$lang_err{'pwd_incorrect'}/;
      httpprint([], [htmlheader(), $html, htmlfooter(1)]);
      return;
   }

   if (!matchlist_fromhead('allowed_rootloginip', $clientip)) {
      if ($user eq 'root' || $uuid==0) {
         sleep $config{'loginerrordelay'};	# delayed response
         writelog("login error - root login attempt");
         my $html = applystyle(readtemplate("loginfailed.template"));
         $html =~ s/\@\@\@ERRORMSG\@\@\@/$lang_err{'norootlogin'}/;
         httpprint([], [htmlheader(), $html, htmlfooter(1)]);
         return;
      }
   }

   my $userconf="$config{'ow_usersconfdir'}/$user";
   $userconf="$config{'ow_usersconfdir'}/$domain/$user" if ($config{'auth_withdomain'});
   read_owconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   matchlist_exact('allowed_serverdomain', $logindomain) or
      openwebmailerror(__FILE__, __LINE__, "Service is not available for $loginuser at '$logindomain'");

   matchlist_fromhead('allowed_clientip', $clientip) or
      openwebmailerror(__FILE__, __LINE__, $lang_err{'disallowed_client'}."<br> ( ip: $clientip )");

   if (!matchlist_all('allowed_clientdomain')) {
      my $clientdomain=ip2hostname($clientip);
      matchlist_fromtail('allowed_clientdomain', $clientdomain) or
         openwebmailerror(__FILE__, __LINE__, $lang_err{'disallowed_client'}."<br> ( host: $clientdomain )");
   }

   my $owuserdir = ow::tool::untaint("$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user));
   $homedir = $owuserdir if ( !$config{'use_syshomedir'} );

   $user=ow::tool::untaint($user);
   $uuid=ow::tool::untaint($uuid);
   $ugid=ow::tool::untaint($ugid);
   $homedir=ow::tool::untaint($homedir);

   # create domainhome for stuff not put in syshomedir
   if (!$config{'use_syshomedir'} || !$config{'use_syshomedir_for_dotdir'}) {
      if ($config{'auth_withdomain'}) {
         my $domainhome=ow::tool::untaint("$config{'ow_usersdir'}/$domain");
         if (!-d $domainhome) {
            mkdir($domainhome, 0750);
            openwebmailerror(__FILE__, __LINE__, "Couldn't create domain homedir $domainhome") if (! -d $domainhome);
            my $mailgid=getgrnam('mail');
            chown($uuid, $mailgid, $domainhome);
         }
      }
   }
   upgrade_20030323();

   # try to load lang and style based on user's preference (for error msg)
   if ($>==0 || $>== $uuid) {
      %prefs = readprefs();
      %style = readstyle($prefs{'style'});
      loadlang($prefs{'language'});
   }

   my ($errorcode, $errormsg, @sessioncount);
   my $password = param('password') || '';
   if ($config{'auth_withdomain'}) {
      ($errorcode, $errormsg)=ow::auth::check_userpassword(\%config, "$user\@$domain", $password);
   } else {
      ($errorcode, $errormsg)=ow::auth::check_userpassword(\%config, $user, $password);
   }
   if ( $errorcode==0 ) {
      # search old alive session and deletes old expired sessionids
      ($thissession, @sessioncount) = search_clean_oldsessions
		($loginname, $default_logindomain, $uuid, cookie("$user-sessionid"));
      if ($thissession eq "") {	# name the new sessionid
         my $n=rand(); for (1..5) { last if $n>=0.1; $n*=10; }	# cover bug if rand return too small value
         $thissession = $loginname."*".$default_logindomain."-session-$n";
      }
      $thissession =~ s!\.\.+!!g;  # remove ..
      if ($thissession =~ /^([\w\.\-\%\@]+\*[\w\.\-]*\-session\-0\.\d+)$/) {
         local $1; # fix perl $1 taintness propagation bug
         $thissession = $1; # untaint
      } else {
         openwebmailerror(__FILE__, __LINE__, "Session ID $thissession $lang_err{'has_illegal_chars'}");
      }
      writelog("login - $thissession - active=$sessioncount[0],$sessioncount[1],$sessioncount[2]");

      # create owuserdir for stuff not put in syshomedir
      # this must be done before changing to the user's uid.
      if ( !$config{'use_syshomedir'} || !$config{'use_syshomedir_for_dotdir'} ) {
         if (!-d $owuserdir) {
            if (mkdir ($owuserdir, oct(700)) && chown($uuid, (split(/\s+/,$ugid))[0], $owuserdir)) {
               writelog("create owuserdir - $owuserdir, uid=$uuid, gid=".(split(/\s+/,$ugid))[0]);
            } else {
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $owuserdir ($!)");
            }
         }
      }

      # create the user's syshome directory if necessary.
      # this must be done before changing to the user's uid.
      if (!-d $homedir && $config{'create_syshomedir'}) {
         if (mkdir ($homedir, oct(700)) && chown($uuid, (split(/\s+/,$ugid))[0], $homedir)) {
            writelog("create homedir - $homedir, uid=$uuid, gid=".(split(/\s+/,$ugid))[0]);
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $homedir ($!)");
         }
      }

      umask(0077);
      if ( $>==0 ) {			# switch to uuid:mailgid if script is setuid root.
         my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
         ow::suid::set_euid_egids($uuid, $mailgid, split(/\s+/,$ugid));
         if ( $)!~/\b$mailgid\b/) {	# group mail doesn't exist?
            openwebmailerror(__FILE__, __LINE__, "Set effective gid to mail($mailgid) failed!");
         }
      }

      # get user release date
      my $user_releasedate=read_releasedatefile();

      # create folderdir if it doesn't exist
      my $folderdir="$homedir/$config{'homedirfolderdirname'}";
      if (! -d $folderdir ) {
         if (mkdir ($folderdir, 0700)) {
            writelog("create folderdir - $folderdir, euid=$>, egid=$)");
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $folderdir ($!)");
         }
         upgrade_20021218($user_releasedate);
      }

      # create dirs under ~/.openwebmail/
      check_and_create_dotdir(dotpath('/'));

      # create system spool file /var/mail/xxxx
      my $spoolfile=ow::tool::untaint((get_folderpath_folderdb($user, 'INBOX'))[0]);
      if ( ! -f "$spoolfile" ) {
         open (F, ">>$spoolfile"); close(F);
         chown($uuid, (split(/\s+/,$ugid))[0], $spoolfile);
      }

      # create session file
      my $sessioncookie_value;
      if ( -f "$config{'ow_sessionsdir'}/$thissession" ) { # continue an old session?
         $sessioncookie_value = cookie("$user-sessionid");
      } else {						       # a brand new sesion?
         $sessioncookie_value = crypt(rand(),'OW');
      }
      open (SESSION, "> $config{'ow_sessionsdir'}/$thissession") or # create sessionid
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}/$thissession! ($!)");
      print SESSION $sessioncookie_value, "\n";
      print SESSION $clientip, "\n";
      print SESSION join("\@\@\@", $domain, $user, $userrealname, $uuid, $ugid, $homedir), "\n";
      close (SESSION);
      writehistory("login - $thissession");

      # symbolic link ~/mbox to ~/mail/saved-messages
      if ( $config{'symboliclink_mbox'} &&
           ((lstat("$homedir/mbox"))[2] & 07770000) eq 0100000) { # regular file
         if (ow::filelock::lock("$folderdir/saved-messages", LOCK_EX|LOCK_NB)) {
            writelog("symlink mbox - $homedir/mbox -> $folderdir/saved-messages");

            if (! -f "$folderdir/saved-messages") {
               open(F,">>$folderdir/saved-messages"); close(F);
            }
            rename("$homedir/mbox", "$homedir/mbox.tmp.$$");
            symlink("$folderdir/saved-messages", "$homedir/mbox");

            open(T,"$homedir/mbox.tmp.$$");
            open(F,"+<$folderdir/saved-messages");
            seek(F, 0, 2);	# seek to end;
            while(<T>) { print F $_; }
            close(F);
            close(T);

            unlink("$homedir/mbox.tmp.$$");
            ow::filelock::lock("$folderdir/saved-messages", LOCK_UN);
         }
      }

      # check if releaseupgrade() is required
      if ($user_releasedate ne $config{'releasedate'}) {
         upgrade_all($user_releasedate) if ($user_releasedate ne "");
         update_releasedatefile();
      }
      update_openwebmailrc($user_releasedate);

      # remove stale folder db
      my (@validfolders, $inboxusage, $folderusage);
      getfolders(\@validfolders, \$inboxusage, \$folderusage);
      del_staledb($user, \@validfolders);

      # create authpop3 book if auth_pop3.pl or auth_ldap_vpopmail.pl
      if ($config{'auth_module'} eq 'auth_pop3.pl' ||
          $config{'auth_module'} eq 'auth_ldap_vpopmail.pl') {
         update_authpop3book(dotpath('authpop3.book'), $domain, $user, $password);
      }

      # redirect page to openwebmail main/calendar/webdisk/prefs
      my $refreshurl=refreshurl_after_login(param('action'));
      if ( ! -f dotpath('openwebmailrc') ) {
         $refreshurl="$config{'ow_cgiurl'}/openwebmail-prefs.pl?sessionid=$thissession&action=userfirsttime";
      }
      if ( !$config{'stay_ssl_afterlogin'} &&	# leave SSL
           ($ENV{'HTTPS'}=~/on/i || $ENV{'SERVER_PORT'}==443) ) {
         $refreshurl="http://$ENV{'HTTP_HOST'}$refreshurl" if ($refreshurl!~s!^https?://!http://!i);
      }

      my @cookies=();

      # cookie for autologin switch, expired until 1 month later
      my $autologin=param('autologin')||0;
      if ($autologin && matchlist_fromhead('allowed_autologinip', $clientip)) {
         $autologin=autologin_add();
      } else {
         autologin_rm();
         $autologin=0;
      }
      push(@cookies, cookie(-name  => 'openwebmail-autologin',
                            -value => $autologin,
                            -path  => '/',
                            -expires => '+1M') );

      # if autologin then expired until 1 week, else expired until browser close
      my @expire=(); @expire=(-expires => '+7d') if ($autologin);
      # cookie for openwebmail to verify session,
      push(@cookies, cookie(-name  => "$user-sessionid",
                            -value => $sessioncookie_value,
                            -path  => '/',
                            @expire) );
      # cookie for ssl session, expired if browser closed
      push(@cookies, cookie(-name  => 'openwebmail-ssl',
                            -value => ($ENV{'HTTPS'}=~/on/i ||
                                       $ENV{'SERVER_PORT'}==443 ||
                                       0),
                            @expire) );

      # cookie for autologin other other ap to find openwebmail loginname, default_logindomain,
      # expired until 1 month later
      push(@cookies, cookie(-name  => 'openwebmail-loginname',
                            -value => $loginname,
                            -path  => '/',
                            -expires => '+1M') );
      push(@cookies, cookie(-name  => 'openwebmail-default_logindomain',
                            -value => $default_logindomain,
                            -path  => '/',
                            -expires => '+1M') );
      # cookie for httpcompress switch, expired until 1 month later
      push(@cookies, cookie(-name  => 'openwebmail-httpcompress',
                            -value => param('httpcompress')||0,
                            -path  => '/',
                            -expires => '+1M') );

      my ($js, $repeatstr)=('', 'no-repeat');
      my @header=(-cookie=>\@cookies);
      if ($ENV{'HTTP_USER_AGENT'}!~/MSIE.+Mac/) {
         # reload page with Refresh header only if not MSIE on Mac
         push(@header, -refresh=>"0.1;URL=$refreshurl");
      } else {
         # reload page with java script in 0.1 sec
         $js=qq|<script language="JavaScript">\n<!--\n|.
             qq|setTimeout("window.location.href='$refreshurl'", 100);\n|.
             qq|//-->\n</script>|;
      }
      $repeatstr='repeat' if ($prefs{'bgrepeat'});

      my $softwarestr=$config{'name'};
      if ($config{'enable_about'} && $config{'about_info_software'}) {
         $softwarestr.=qq| $config{'version'} $config{'releasedate'}|;
      }

      my $countstr='';
      if ($config{'session_count_display'}) {
         $countstr=qq|<br><br><br>\n|.
                   qq|<a href=# title="number of active sessions in the past 1, 5, 15 minutes">Sessions&nbsp; :&nbsp; |.
                   qq|$sessioncount[0],&nbsp; $sessioncount[1],&nbsp; $sessioncount[2]</a>\n|;
      }

      # display copyright. Don't touch it, please.
      httpprint(\@header,
      		[qq|<html>\n|.
		 qq|<head><title>Copyright</title></head>\n|.
		 qq|<body bgcolor="#ffffff" background="$prefs{'bgurl'}">\n|.
		 qq|<style type="text/css"><!--\n|.
		 qq|body {\n|.
                 qq|background-image: url($prefs{'bgurl'});\n|.
                 qq|background-repeat: $repeatstr;\n|.
                 qq|font-family: Arial,Helvetica,sans-serif; font-size: 10pt; font-color: #cccccc\n|.
                 qq|}\n|.
                 qq|A:link    { color: #cccccc; text-decoration: none }\n|.
                 qq|A:visited { color: #cccccc; text-decoration: none }\n|.
                 qq|A:hover   { color: #333333; text-decoration: none }\n|.
		 qq|--></style>\n|.
		 qq|<center><br><br><br>\n|.
		 qq|<a href="$refreshurl" title="click to next page" style="text-decoration: none">|.
		 qq|<font color="#333333"> &nbsp; $lang_text{'loading'} ...</font></a>\n|.
		 qq|<br><br><br>\n\n|.
		 qq|<a href="http://openwebmail.org/" title="click to home of $config{'name'}" target="_blank" style="text-decoration: none">\n|.
		 qq|$softwarestr<br><br>\n|.
		 qq|Copyright (C) 2001-2004<br>\n|.
		 qq|Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric,<br>|.
                 qq|Thomas Chung, Dattola Filippo, Bernd Bass, Scott Mazur, Alex Teslik<br><br>\n|.
		 qq|Copyright (C) 2000<br>\n|.
		 qq|Ernie Miller  (original GPL project: Neomail)<br><br>\n|.
		 qq|</a>\n\n|.
		 qq|<a href="$config{'ow_htmlurl'}/doc/copyright.txt" title="click to see GPL version 2 licence" target="_blank" style="text-decoration: none">\n|.
		 qq|This program is free software; you can redistribute it and/or modify<br>\n|.
		 qq|it under the terms of the version 2 of GNU General Public License<br>\n|.
		 qq|as published by the Free Software Foundation<br><br>\n|.
		 qq|This program is distributed in the hope that it will be useful,<br>\n|.
		 qq|but WITHOUT ANY WARRANTY; without even the implied warranty of<br>\n|.
		 qq|MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.<br>\n|.
		 qq|See the GNU General Public License for more details.<br><br>\n|.
		 qq|Removal or change of this copyright is prohibited.\n|.
		 qq|</a>\n|.
		 qq|$countstr$js\n|.
		 qq|</center></body></html>\n|] );

   } else { # Password is INCORRECT
      writelog("login error - $config{'auth_module'}, ret $errorcode, $errormsg");
      umask(0077);
      if ( $>==0 ) {	# switch to uuid:mailgid if script is setuid root.
         my $mailgid=getgrnam('mail');
         ow::suid::set_euid_egids($uuid, $mailgid, split(/\s+/,$ugid));
      }
      my $historyfile=ow::tool::untaint(dotpath('history.log'));
      if (-f $historyfile ) {
         writehistory("login error - $config{'auth_module'}, ret $errorcode, $errormsg");
      }

      my $html = applystyle(readtemplate("loginfailed.template"));

      my $webmsg;
      if ($errorcode==-1) {
         $webmsg=$lang_err{'func_notsupported'};
      } elsif ($errorcode==-2) {
         $webmsg=$lang_err{'param_fmterr'};
      } elsif ($errorcode==-3) {
         $webmsg=$lang_err{'auth_syserr'};
      } elsif ($errorcode==-4) {
         $webmsg=$lang_err{'pwd_incorrect'};
      } else {
         $webmsg="Unknow error code $errorcode";
      }
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$webmsg/;

      sleep $config{'loginerrordelay'};	# delayed response
      httpprint([], [htmlheader(), $html, htmlfooter(1)]);
   }
}

sub ip2hostname {
   my $ip=$_[0];
   my $hostname;
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 10; # timeout 10sec
      $hostname=gethostbyaddr(inet_aton($ip),AF_INET);
      alarm 0;
   };
   return($ip) if ($@);	# eval error, it means timeout
   return($hostname);
}
########## END LOGIN #############################################

########## AUTOLOGIN #############################################
sub autologin {
   # auto login with cgi parm or cookie
   $default_logindomain=param('default_logindomain')||cookie('openwebmail-default_logindomain');
   $loginname=param('loginname')||cookie('openwebmail-loginname');
   return loginmenu() if ($loginname eq '');

   ($logindomain, $loginuser)=login_name2domainuser($loginname, $default_logindomain);
   if (!is_localuser("$loginuser\@$logindomain") && -f "$config{'ow_sitesconfdir'}/$logindomain") {
      read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   }
   ow::auth::load($config{'auth_module'});

   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
				=get_domain_user_userinfo($logindomain, $loginuser);
   if ($user eq '' ||
       ($uuid==0 && !matchlist_fromhead('allowed_rootloginip', ow::tool::clientip())) ||
       cookie("$user-sessionid") eq '') {
      return loginmenu();
   }

   my $userconf="$config{'ow_usersconfdir'}/$user";
   $userconf="$config{'ow_usersconfdir'}/$domain/$user" if ($config{'auth_withdomain'});
   read_owconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   my $owuserdir = ow::tool::untaint("$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user));
   $homedir = $owuserdir if ( !$config{'use_syshomedir'} );
   return loginmenu() if (!autologin_check());	# db won't be created if it doesn't exist as euid has not been switched

   # load user prefs for search_clean_oldsessions, it  will check $prefs{sessiontimeout}
   %prefs = readprefs();	
   $thissession = (search_clean_oldsessions
		($loginname, $default_logindomain, $uuid, cookie("$user-sessionid")))[0];
   $thissession =~ s!\.\.+!!g;  # remove ..
   return loginmenu() if ($thissession !~ /^([\w\.\-\%\@]+\*[\w\.\-]*\-session\-0\.\d+)$/);

   # redirect page to openwebmail main/calendar/webdisk
   my $refreshurl=refreshurl_after_login(param('action'));
   if ( !$config{'stay_ssl_afterlogin'} &&	# leave SSL
        ($ENV{'HTTPS'}=~/on/i || $ENV{'SERVER_PORT'}==443) ) {
      $refreshurl="http://$ENV{'HTTP_HOST'}$refreshurl" if ($refreshurl!~s!^https?://!http://!i);
   }
   print redirect(-location=>$refreshurl);
}
########## END AUTOLOGIN #########################################

########## REFRESHURL_AFTER_LOGIN ################################
sub refreshurl_after_login {
   my $action=$_[0];

   my %action_redirect= (
      listmessages   => [1, 'enable_webmail',     'openwebmail-main.pl',    ['folder']],
      calmonth       => [2, 'enable_calendar',    'openwebmail-cal.pl',     ['year', 'month']],
      showdir        => [3, 'enable_webdisk',     'openwebmail-webdisk.pl', ['currentdir']],
      addrlistview   => [4, 'enable_addressbook', 'openwebmail-abook.pl',   ['abookfolder']],
      callist        => [5, 'enable_calendar',    'openwebmail-cal.pl',     ['year']],
      calyear        => [6, 'enable_calendar',    'openwebmail-cal.pl',     ['year']],
      calday         => [7, 'enable_calendar',    'openwebmail-cal.pl',     ['year', 'month', 'day']],
      readmessage    => [8, 'enable_webmail',     'openwebmail-read.pl',    ['folder', 'message_id']],
      composemessage => [9, 'enable_webmail',     'openwebmail-send.pl',    ['to', 'cc', 'bcc', 'subject']],
   );
   my @actions = sort { ${$action_redirect{$a}}[0] <=> ${$action_redirect{$b}}[0] } keys (%action_redirect);

   my $validaction;
   foreach (@actions) {
      my $enable=$config{${$action_redirect{$_}}[1]};
      if ($action eq $_) { $validaction=$_ if ($enable); last }
   }
   if ($validaction eq '') {
      foreach (@actions) {
         my $enable=$config{${$action_redirect{$_}}[1]};
         if ($enable) { $validaction=$_; last }
      }
   }
   if ($validaction eq '') {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'all_module_disabled'}, $lang_err{'access_denied'}");
   }

   my $script= ${$action_redirect{$validaction}}[2];
   my @parms = @{${$action_redirect{$validaction}}[3]};
   my $refreshurl="$config{'ow_cgiurl'}/$script?sessionid=$thissession&action=$validaction";
   foreach my $parm ( @parms ) {
      $refreshurl.='&'.$parm.'='.ow::tool::escapeURL(param($parm)) if (param($parm) ne '');
   }
   return $refreshurl;
}
########## END REFRESHURL_AFTER_LOGIN ############################

########## SEARCH_AND_CLEANOLDSESSIONS ###########################
# try to find old session that is still valid for the same user cookie
# and delete expired session files
sub search_clean_oldsessions {
   my ($loginname, $default_logindomain, $owner_uid, $oldcookie)=@_;
   my $oldsessionid="";
   my @sessioncount=(0,0,0);	# active sessions in 1, 5, 15 minutes
   my @delfiles;

   opendir(SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}! ($!)");
      my @sessfiles=readdir(SESSIONSDIR);
   closedir(SESSIONSDIR);

   my $t=time();
   my $clientip=ow::tool::clientip();
   foreach my $sessfile (@sessfiles) {
      next if ($sessfile !~ /^([\w\.\-\%\@]+)\*([\w\.\-]*)\-session\-(0\.\d+)(-.*)?$/);

      my ($sess_loginname, $sess_default_logindomain, $serial, $misc)=($1, $2, $3, $4); # param from sessfile
      my $modifyage = $t-(stat("$config{'ow_sessionsdir'}/$sessfile"))[9];

      if ($loginname eq $sess_loginname &&
          $default_logindomain eq $sess_default_logindomain) {
         # remove user old session if timeout
         if ( $modifyage > $prefs{'sessiontimeout'}*60 ) {
            push(@delfiles, $sessfile);
         } elsif ($misc eq '') {	# this is a session info file
            my ($cookie, $ip, $userinfo)=sessioninfo($sessfile);
            if ($oldcookie && $cookie eq $oldcookie && $ip eq $clientip &&
                (stat("$config{'ow_sessionsdir'}/$sessfile"))[4] == $owner_uid ) {
               $oldsessionid=$sessfile;
            } elsif (!$config{'session_multilogin'}) { # remove old session of this user
               push(@delfiles, $sessfile);
            }
         }

      } else {	# remove old session of other user if more than 1 day
         push(@delfiles, $sessfile) if ( $modifyage > 86400 );
      }

      if ($misc eq '') {
         $sessioncount[0]++ if ($modifyage <= 60);
         $sessioncount[1]++ if ($modifyage <= 300);
         $sessioncount[2]++ if ($modifyage <= 900);
      }
   }

   foreach my $sessfile (@delfiles) {
      writelog("session cleanup - $sessfile");
      unlink ow::tool::untaint("$config{'ow_sessionsdir'}/$sessfile");
   }

   return($oldsessionid, @sessioncount);
}

########## END SEARCH_AND_CLEANOLDSESSIONS #######################
