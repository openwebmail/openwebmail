#!/usr/bin/suidperl -T
#################################################################
#                                                               #
# Open WebMail - Provides a web interface to user mailboxes     #
#                                                               #
# Copyright (C) 2001-2003                                       #
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
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1; }
}
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use Socket;
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "ow-shared.pl";
require "filelock.pl";
require "mime.pl";

# common globals
use vars qw(%config %config_raw %default_config);
use vars qw($thissession);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir);

# extern vars
use vars qw(@openwebmailrcitem);	# defined in ow-shared.pl
use vars qw(%lang_text %lang_err);	# defined in lang/xy

####################### MAIN ##########################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop

load_rawconf(\%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
readlang($config{'default_language'});	# so %lang... can be used in error msg

# check & create mapping table for solar/lunar, b2g, g2b convertion
foreach my $table ('b2g', 'g2b', 'lunar') {
   if ( $config{$table.'_map'} && ! -f "$config{'ow_etcdir'}/$table$config{'dbm_ext'}") {
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
} else {
   loginmenu();	# display login page if no login
}

openwebmail_requestend();
##################### END MAIN ########################

##################### LOGINMENU ######################
sub loginmenu {
   $logindomain=param('logindomain')||lc($ENV{'HTTP_HOST'});
   $logindomain=~s/:\d+$//;	# remove port number
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined($config{'domainname_equiv'}{'map'}{$logindomain}));
   if (!is_serverdomain_allowed($logindomain)) {
      openwebmailerror(__FILE__, __LINE__, "Service is not available for domain  '$logindomain'");
   }

   readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain") if ( -f "$config{'ow_sitesconfdir'}/$logindomain");
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; openwebmail_exit(0);
   }

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   readlang($prefs{'language'});

   my ($html, $temphtml);
   $html = applystyle(readtemplate("login.template"));

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail.pl",
                         -name=>'login');
   if (defined(param('action'))) {
      $temphtml .= hidden("action", param('action'));
      $temphtml .= hidden("to", param('to')) if (defined(param('to')));
      $temphtml .= hidden("subject", param('subject')) if (defined(param('subject')));
   }
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'loginname',
                         -default=>'',
                         -size=>'12',
                         -onChange=>'focuspwd()',
                         -override=>'1');
   $html =~ s/\@\@\@LOGINNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'password',
                              -default=>'',
                              -size=>'12',
                              -onChange=>'focusloginbutton()',
                              -override=>'1');
   $html =~ s/\@\@\@PASSWORDFIELD\@\@\@/$temphtml/;

   if ( $ENV{'HTTP_ACCEPT_ENCODING'}=~/\bgzip\b/ && has_zlib() ) {
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

   if ( $#{$config{'domainnames'}} >0 && $config{'enable_domainselectmenu'} ) {
      $temphtml = popup_menu(-name=>'logindomain',
                             -default=>$logindomain,
                             -values=>[@{$config{'domainselmenu_list'}}] );
      $html =~ s/\@\@\@DOMAINMENU\@\@\@/$temphtml/;
      $html =~ s/\@\@\@DOMAINSTART\@\@\@//;
      $html =~ s/\@\@\@DOMAINEND\@\@\@//;
   } else {
      $temphtml = hidden("logindomain", param('logindomain'));
      $html =~ s/\@\@\@DOMAINSTART\@\@\@/$temphtml<!--/;
      $html =~ s/\@\@\@DOMAINEND\@\@\@/-->/;
   }

   $temphtml = submit(-name =>"loginbutton",
		      -value=>"$lang_text{'login'}" );
   $html =~ s/\@\@\@LOGINBUTTON\@\@\@/$temphtml/;
   $temphtml = reset("$lang_text{'clear'}");
   $html =~ s/\@\@\@CLEARBUTTON\@\@\@/$temphtml/;
   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   # undef env to prevent httpprint() doing compression on login page
   undef $ENV{'HTTP_ACCEPT_ENCODING'};
   httpprint([], [htmlheader(), $html, htmlfooter(1)]);
}
################### END LOGINMENU ####################

####################### LOGIN ########################
sub login {
   $loginname=param('loginname');
   $default_logindomain=param('logindomain');

   ($logindomain, $loginuser)=login_name2domainuser($loginname, $default_logindomain);
   if (!is_serverdomain_allowed($logindomain)) {
      openwebmailerror(__FILE__, __LINE__, "Service is not available for domain  '$logindomain'");
   }

   if (!is_localuser("$loginuser\@$logindomain") && -f "$config{'ow_sitesconfdir'}/$logindomain") {
      readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   }
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; openwebmail_exit(0);
   }
   loadauth($config{'auth_module'});

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

   # update virtusertable
   my $virtname=$config{'virtusertable'}; $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   update_virtusertable("$config{'ow_etcdir'}/$virtname", $config{'virtusertable'});

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   readlang($prefs{'language'});

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
   if (! $config{'enable_rootlogin'}) {
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
   readconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   if (!is_serverdomain_allowed($logindomain)) {
      openwebmailerror(__FILE__, __LINE__, "Service is not available for $loginuser at '$logindomain'");
   }

   if ( !$config{'use_syshomedir'} ) {
      $homedir="$config{'ow_usersdir'}/$user";
      if ($config{'auth_withdomain'}) {
         my $domainhome="$config{'ow_usersdir'}/$domain";
         # mkdir domainhome so openwebmail.pl can create user homedir under this domainhome
         if (!-d $domainhome) {
            my $mailgid=getgrnam('mail');
            $domainhome=untaint($domainhome);
            mkdir($domainhome, 0750);
            openwebmailerror(__FILE__, __LINE__, "Couldn't create domain homedir $domainhome") if (! -d $domainhome);
            chown($uuid, $mailgid, $domainhome);
         }
         $homedir = "$domainhome/$user";
      }
   }
   $folderdir = "$homedir/$config{'homedirfolderdirname'}";

   $user=untaint($user);
   $uuid=untaint($uuid);
   $ugid=untaint($ugid);
   $homedir=untaint($homedir);
   $folderdir=untaint($folderdir);

   # validate client ip
   my $clientip=get_clientip();
   if ($#{$config{'allowed_clientip'}}>=0) {
      my $allowed=0;
      foreach my $token (@{$config{'allowed_clientip'}}) {
         if (lc($token) eq 'all' || $clientip=~/^\Q$token\E/) {
            $allowed=1; last;
         } elsif (lc($token) eq 'none') {
            last;
         }
      }
      if (!$allowed) {
         openwebmailerror(__FILE__, __LINE__, $lang_err{'disallowed_client'}." ( ip:$clientip )");
      }
   }
   # validate client domain
   if ($#{$config{'allowed_clientdomain'}}>=0) {
      my $clientdomain;
      my $allowed=0;
      foreach my $token (@{$config{'allowed_clientdomain'}}) {
         if (lc($token) eq 'all') {
            $allowed=1; last;
         } elsif (lc($token) eq 'none') {
            last;
         }
         $clientdomain=ip2hostname($clientip) if ($clientdomain eq "");
         if ($clientdomain=~/\Q$token\E$/ || # matched
             $clientdomain!~/\./) { 		# shortname in /etc/hosts
            $allowed=1; last;
         }
      }
      if (!$allowed) {
         openwebmailerror(__FILE__, __LINE__, $lang_err{'disallowed_client'}." ( hotname:$clientdomain )");
      }
   }

   my ($errorcode, $errormsg);
   my $password = param('password') || '';
   if ($config{'auth_withdomain'}) {
      ($errorcode, $errormsg)=check_userpassword(\%config, "$user\@$domain", $password);
   } else {
      ($errorcode, $errormsg)=check_userpassword(\%config, $user, $password);
   }
   if ( $errorcode==0 ) {
      # search old alive session and deletes old expired sessionids
      $thissession = search_and_cleanoldsessions(cookie("$user-sessionid"), $uuid);
      if ($thissession eq "") {	# name the new sessionid
         $thissession = $loginname."*".$default_logindomain."-session-".rand();
      }
      $thissession =~ s!\.\.+!!g;  # remove ..
      if ($thissession =~ /^([\w\.\-\%\@]+\*[\w\.\-]*\-session\-0\.\d+)$/) {
         $thissession = $1; # untaint
      } else {
         openwebmailerror(__FILE__, __LINE__, "Session ID $thissession $lang_err{'has_illegal_chars'}");
      }
      writelog("login - $thissession");

      if (!$config{'use_syshomedir'} && $config{'auth_withdomain'} &&
          !-d "$homedir" && -d "$config{'ow_usersdir'}/$user\@$domain") {
         # rename old homedir
         my $olddir="$config{'ow_usersdir'}/$user\@$domain";
         ($olddir =~ /^(.+)$/) && ($olddir = $1);
         rename($olddir, $homedir) or
            openwebmailerror(__FILE__, __LINE__, "$lang_text{'rename'} $olddir to $homedir $lang_text{'failed'} ($!)");
         writelog("release upgrade - rename $olddir to $homedir by 20030323");
      }

      # get user release date
      my $user_releasedate;
      my $releasedate_file="$folderdir/.release.date";
      $releasedate_file="$homedir/.release.date" if (! -f $releasedate_file);
      if (open(D, $releasedate_file)) {
         $user_releasedate=<D>; chomp($user_releasedate); close(D);
      }

      # change the owner of files under ow_usersdir/username from root to $uuid
      if ($user_releasedate lt "20030312") {
         if( !$config{'use_syshomedir'} && -d $homedir) {
            my $chown_bin;
            foreach ("/bin/chown", "/usr/bin/chown", "/sbin/chown", "/usr/sbin/chown") {
               $chown_bin=$_ if (-x $_);
            }
            system($chown_bin, '-R', $uuid, $homedir);
            writelog("release upgrade - chown -R $uuid $homedir/* by 20030312");
         }
      }

      # create the user's home directory if necessary.
      # this must be done before changing to the user's uid.
      if (($config{'create_syshomedir'} || !$config{'use_syshomedir'})
          && !-d $homedir ) {
         if (mkdir ("$homedir", oct(700)) && chown($uuid, (split(/\s+/,$ugid))[0], $homedir)) {
            writelog("create homedir - $homedir, uid=$uuid, gid=".(split(/\s+/,$ugid))[0]);
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $homedir ($!)");
         }
      }

      umask(0077);
      if ( $>==0 ) {			# switch to uuid:mailgid if script is setuid root.
         my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
         set_euid_egids($uuid, $mailgid, split(/\s+/,$ugid));
         if ( $)!~/\b$mailgid\b/) {	# group mail doesn't exist?
            openwebmailerror(__FILE__, __LINE__, "Set effective gid to mail($mailgid) failed!");
         }
      }

      # create folderdir if it doesn't exist
      if (! -d "$folderdir" ) {
         if (mkdir ("$folderdir", oct(700))) {
            writelog("create folderdir - $folderdir, euid=$>, egid=$)");
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $folderdir ($!)");
         }

         # mv folders from $homedir to $folderdir($homedir/mail/) for old ow_usersdir
         if ($user_releasedate lt "20021218") {
            if ( !$config{'use_syshomedir'} &&
                 -f "$homedir/.openwebmailrc" && !-f "$folderdir/.openwebmailrc") {
               opendir (HOMEDIR, $homedir);
               my @files=readdir(HOMEDIR);
               closedir(HOMEDIR);
               foreach my $file (@files) {
                  next if ($file eq "." || $file eq ".." || $file eq $config{'homedirfolderdirname'});
                  $file=untaint($file);
                  rename("$homedir/$file", "$folderdir/$file");
               }
               writelog("release upgrade - mv $homedir/* to $folderdir/* by 20021218");
            }
         }
      }

      # create system spool file /var/mail/xxxx
      my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
      if ( ! -f "$spoolfile" ) {
         $spoolfile=untaint($spoolfile);
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
      print SESSION get_clientip(), "\n";
      print SESSION join("\@\@\@", $domain, $user, $userrealname, $uuid, $ugid, $homedir), "\n";
      close (SESSION);
      writehistory("login - $thissession");

      # symbolic link ~/mbox to ~/mail/saved-messages
      if ( $config{'symboliclink_mbox'} &&
           ((lstat("$homedir/mbox"))[2] & 07770000) eq 0100000) { # regular file
         if (filelock("$folderdir/saved-messages", LOCK_EX|LOCK_NB)) {
            writelog("symlink mbox - $homedir/mbox -> $folderdir/saved-messages");

            rename("$homedir/mbox", "$homedir/mbox.tmp.$$");
            symlink("$folderdir/saved-messages", "$homedir/mbox");

            open(T,"$homedir/mbox.tmp.$$");
            open(F,">>$folderdir/saved-messages");
            while(<T>) { print F $_; }
            close(F);
            close(T);

            unlink("$homedir/mbox.tmp.$$");
            filelock("$folderdir/saved-messages", LOCK_UN);
         }
      }

      # check if releaseupgrade() is required
      if ($user_releasedate ne $config{'releasedate'}) {
         releaseupgrade($folderdir, $user_releasedate);
         open(D, ">$folderdir/.release.date");
         print D $config{'releasedate'};
         close(D);
      }

      # create authpop3 book if auth_pop3.pl  & getmail_from_pop3_authserver is yes
      if ($config{'auth_module'} eq 'auth_pop3.pl') {
         my $authpop3book=untaint("$folderdir/.authpop3.book");

         if ($config{'getmail_from_pop3_authserver'}) {
            my ($pop3host,$pop3port, $pop3user,$pop3passwd, $pop3del,$enable);
            my $login=$user; $login .= "\@$domain" if ($config{'auth_withdomain'});
            if ( -f "$authpop3book") {
                my %accounts;
                readpop3book("$authpop3book", \%accounts);
                ($pop3host,$pop3port, $pop3user,$pop3passwd, ,$pop3del,$enable)
                   =split(/\@\@\@/, $accounts{"$config{'pop3_authserver'}:$config{'pop3_authport'}\@\@\@$login"});
            }

            if ($pop3host ne $config{'pop3_authserver'} ||
                $pop3port ne $config{'pop3_authport'} ||
                $pop3user ne $login ||
                $pop3passwd ne $password ||
                $pop3del ne $config{'delpop3mail_by_default'} ) {
               if ($pop3host ne $config{'pop3_authserver'} ||
                   $pop3port ne $config{'pop3_authport'} ||
                   $pop3user ne $login ) {
                  $enable=1;
               }
               my %accounts;
               $accounts{"$config{'pop3_authserver'}:$config{'pop3_authport'}\@\@\@$login"}
                  ="$config{'pop3_authserver'}\@\@\@$config{'pop3_authport'}\@\@\@$login\@\@\@$password\@\@\@$config{'delpop3mail_by_default'}\@\@\@$enable";
               writepop3book("$authpop3book", \%accounts);
            }
         } else {
            unlink("$authpop3book");
         }
      }

      # set cookie in header and redirect page to openwebmail-main
      my $action=param('action');
      my $refreshurl;
      if ( ! -f "$folderdir/.openwebmailrc" ) {
         $refreshurl="$config{'ow_cgiurl'}/openwebmail-prefs.pl?sessionid=$thissession&action=userfirsttime";
      } elsif ( $action eq 'composemessage' ) {
         my $to=param('to');
         $to =~ s!^mailto\:!!; # IE passes mailto: with mailaddr to mail client
         my $subject=param('subject');
         $refreshurl="$config{'ow_cgiurl'}/openwebmail-send.pl?sessionid=$thissession&action=composemessage&to=$to&subject=$subject";
      } elsif ( $action eq 'calyear' || $action eq 'calmonth' ||
                $action eq 'calweek' || $action eq 'calday' ) {
         $refreshurl="$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&action=$action";
      } elsif ( $action eq 'showdir' ) {
         $refreshurl="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?sessionid=$thissession&action=$action";
      } elsif ( $action eq 'editfolders' ) {
         $refreshurl="$config{'ow_cgiurl'}/openwebmail-folder.pl?sessionid=$thissession&action=$action";
      } else {
         if ($config{'enable_webmail'}) {
            $refreshurl="$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&action=listmessages_afterlogin";
         } elsif ($config{'enable_calendar'}) {
            $refreshurl="$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&action=calmonth";
         } elsif ($config{'enable_webdisk'}) {
            $refreshurl="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?sessionid=$thissession&action=showdir";
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'all_module_disabled'}, $lang_err{'access_denied'}");
         }
      }

      if ( !$config{'stay_ssl_afterlogin'} &&	# leave SSL
           ($ENV{'HTTPS'}=~/on/i || $ENV{'SERVER_PORT'}==443) ) {
         $refreshurl="http://$ENV{'HTTP_HOST'}$refreshurl" if ($refreshurl!~s!^https?://!http://!i);
      }

      # cookie for openwebmail to verify session, expired if browser closed
      my $cookie1 = cookie( -name  => "$user-sessionid",
                            -value => "$sessioncookie_value",
                            -path  => '/');
      # cookie for other ap to find openwebmail loginname, expired until 1 month later
      my $cookie2 = cookie( -name  => "openwebmail-loginname",
                            -value => "$loginname",
                            -path  => '/',
                            -expires => "+1M" );
      # cookie for httpcompress switch, expired until 1 month later
      my $cookie3 = cookie( -name  => "openwebmail-httpcompress",
                            -value => param('httpcompress')||'',
                            -path  => '/',
                            -expires => "+1M" );
      # cookie for ssl session, expired if not same session
      my $cookie4 = cookie( -name  => "openwebmail-ssl",
                            -value => ($ENV{'HTTPS'}=~/on/i ||
                                       $ENV{'SERVER_PORT'}==443 ||
                                       0),
                            -path  => '/');

      my ($js, $repeatstr)=('', 'no-repeat');
      my @header=(-cookie=>[$cookie1, $cookie2, $cookie3, $cookie4]);
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
                 qq|A:hover   { color: #666666; text-decoration: none }\n|.
		 qq|--></style>\n|.
		 qq|<center><br><br><br>\n|.
		 qq|<a href="$refreshurl" title="click to next page" style="text-decoration: none">|.
		 qq|<font color="#666666"> &nbsp; $lang_text{'loading'} ...</font></a>\n|.
		 qq|<br><br><br>\n\n|.
		 qq|<a href="http://openwebmail.org/" title="click to home of $config{'name'}" target="_blank" style="text-decoration: none">\n|.
		 qq|$config{'name'} $config{'version'} $config{'releasedate'}<br><br>\n|.
		 qq|Copyright (C) 2001-2003<br>\n|.
		 qq|Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric,<br>|.
                 qq|Thomas Chung, Dattola Filippo, Bernd Bass, Scott Mazur<br><br>\n|.
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
		 qq|$js\n|.
		 qq|</center></body></html>\n|] );

   } else { # Password is INCORRECT
      writelog("login error - $config{'auth_module'}, ret $errorcode, $errormsg");
      umask(0077);
      if ( $>==0 ) {	# switch to uuid:mailgid if script is setuid root.
         my $mailgid=getgrnam('mail');
         set_euid_egids($uuid, $mailgid, split(/\s+/,$ugid));
      }
      if ( -d $folderdir) {
         if ( ! -f "$folderdir/.history.log" ) {
            open(HISTORYLOG, ">>$folderdir/.history.log");
            close(HISTORYLOG);
            chown($uuid, (split(/\s+/,$ugid))[0], "$folderdir/.history.log");
         }
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
#################### END LOGIN #####################

############### IS_SERVERDOMAIN_ALLOWED ###################
sub is_serverdomain_allowed {
   my $domain=$_[0];
   if ($#{$config{'allowed_serverdomain'}}>=0) {
      foreach my $token (@{$config{'allowed_serverdomain'}}) {
         if (lc($token) eq 'all' || lc($domain) eq lc($token)) {
            return 1;
         } elsif (lc($token) eq 'none') {
            return 0;
         }
      }
      return 0;
   } else {
      return 1;
   }
}
############### END IS_SERVERDOMAIN_ALLOWED ###################

################ SEARCH_AND_CLEANOLDSESSIONS ##################
# delete expired session files and
# try to find old session that is still valid for the same user cookie
sub search_and_cleanoldsessions {
   my ($oldcookie, $owner_uid)=@_;
   my $oldsessionid="";
   my ($sessionid, $modifyage);
   my @delfiles;

   opendir (SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}! ($!)");
   my $t=time();
   while (defined($sessionid = readdir(SESSIONSDIR))) {
      if ($sessionid =~ /^(.+\-session\-0.*)$/) {
         $sessionid = $1;
         $modifyage = $t-(stat("$config{'ow_sessionsdir'}/$sessionid"))[9];

         $sessionid =~ /^([\w\.\-\%\@]+)\*([\w\.\-]*)\-session\-(0\.\d+)$/;
         my ($sess_loginname, $sess_default_logindomain)=($1, $2); # param from sessionid

         if ($loginname eq $sess_loginname &&
             $default_logindomain eq $sess_default_logindomain) {
            # remove user old session if timeout
            if ( $modifyage > $prefs{'sessiontimeout'}*60 ) {
               writelog("session cleanup - $sessionid");
               push(@delfiles, "$config{'ow_sessionsdir'}/$sessionid");
            } else {
               my ($cookie, $ip, $userinfo)=sessioninfo($sessionid);
               if ($oldcookie && $cookie eq $oldcookie && $ip eq get_clientip() &&
                   (stat("$config{'ow_sessionsdir'}/$sessionid"))[4] == $owner_uid ) {
                  $oldsessionid=$sessionid;
               } elsif (!$config{'session_multilogin'}) { # remove old session of this user
                  writelog("session cleanup - $sessionid");
                  push(@delfiles, "$config{'ow_sessionsdir'}/$sessionid");
               }
            }
         } else {	# remove old session of other user if more than 1 day
            if ( $modifyage > 86400 ) {
               writelog("session cleanup - $sessionid");
               push(@delfiles, "$config{'ow_sessionsdir'}/$sessionid");
            }
         }
      }
   }
   closedir (SESSIONSDIR);

   unlink(@delfiles) if ($#delfiles>=0);
   return($oldsessionid);
}
############## END SEARCH_AND_CLEANOLDSESSIONS ################

#################### RELEASEUPGRADE ####################
# convert file format from old release for backward compatibility
sub releaseupgrade {
   my ($folderdir, $user_releasedate)=@_;
   my $content;
   my ($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE, $_REFERENCES, $_CHARSET)
       =(0,1,2,3,4,5,6,7,8,9);

   if ( $user_releasedate lt "20011101" ) {
      if ( -f "$folderdir/.filter.book" ) {
         $content="";
         filelock("$folderdir/.filter.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.filter.book");
         open(F, "$folderdir/.filter.book");
         while (<F>) {
            chomp;
            my ($priority, $rules, $include, $text, $op, $destination, $enable) = split(/\@\@\@/);
            if ( $enable eq '') {
               ($priority, $rules, $include, $text, $destination, $enable) = split(/\@\@\@/);
               $op='move';
            }
            $rules='textcontent' if ($rules eq 'body');
            $content.="$priority\@\@\@$rules\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.filter.book by 20011101");
            writelog("release upgrade - $folderdir/.filter.book by 20011101");
            open(F, ">$folderdir/.filter.book");
            print F $content;
            close(F);
         }
         filelock("$folderdir/.filter.book", LOCK_UN);
      }

      if ( -f "$folderdir/.pop3.book" ) {
         $content="";
         filelock("$folderdir/.pop3.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.pop3.book");
         open(F, "$folderdir/.pop3.book");
         while (<F>) {
            chomp;
            my @a=split(/:/);
            my ($pop3host, $pop3user, $pop3passwd, $pop3lastid, $pop3del, $enable);
            if ($#a==4) {
               ($pop3host, $pop3user, $pop3passwd, $pop3del, $pop3lastid) = @a;
               $enable=1;
            } elsif ($a[3]=~/\@/) {
               my $pop3email;
               ($pop3host, $pop3user, $pop3passwd, $pop3email, $pop3del, $pop3lastid) = @a;
               $enable=1;
            } else {
               ($pop3host, $pop3user, $pop3passwd, $pop3lastid, $pop3del, $enable) =@a;
            }
            $content.="$pop3host\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@RESERVED\@\@\@$pop3del\@\@\@$enable\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.pop3.book by 20011101");
            writelog("release upgrade - $folderdir/.pop3.book by 20011101");
            open(F, ">$folderdir/.pop3.book");
            print F $content;
            close(F);
         }
         filelock("$folderdir/.pop3.book", LOCK_UN);
      }
   }

   if ( $user_releasedate lt "20011117" ) {
      for my $book (".from.book", ".address.book", ".pop3.book") {
         if ( -f "$folderdir/$book" ) {
            $content="";
            filelock("$folderdir/$book", LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/$book");
            open(F, "$folderdir/$book");
            while (<F>) {
               last if (/\@\@\@/);
               s/:/\@\@\@/g;
               $content.=$_
            }
            close(F);
            if ($content ne "") {
               writehistory("release upgrade - $folderdir/$book by 20011117");
               writelog("release upgrade - $folderdir/$book by 20011117");
               open(F, ">$folderdir/$book");
               print F $content;
               close(F);
            }
            filelock("$folderdir/$book", LOCK_UN);
         }
      }
   }

   if ( $user_releasedate lt "20011216" ) {
      my @cachefiles;
      my $file;
      opendir (FOLDERDIR, "$folderdir") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir ($!)");
      while (defined($file = readdir(FOLDERDIR))) {
         if ($file=~/^(\..+\.cache)$/) {
            $file="$folderdir/$1";
            push(@cachefiles, $file);
         }
      }
      closedir (FOLDERDIR);
      if ($#cachefiles>=0) {
         writehistory("release upgrade - $folderdir/*.cache by 20011216");
         writelog("release upgrade - $folderdir/*.cache by 20011216");
         # remove old .cache since its format is not compatible with new one
         unlink(@cachefiles);
      }
   }

   if ( $user_releasedate lt "20020108.02" ) {
      my (@validfolders, $folderusage);
      getfolders(\@validfolders, \$folderusage);

      foreach my $foldername (@validfolders) {
         my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldername);
         my (%HDB, @messageids, @attr);
         next if ( ! -f "$headerdb$config{'dbm_ext'}" || -z "$headerdb$config{'dbm_ext'}" );

         filelock($folderfile, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile");
         open (FOLDER, $folderfile);
         open_dbm(\%HDB, $headerdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $headerdb$config{'dbm_ext'}");

         if ( $HDB{'METAINFO'} eq metainfo($folderfile) ) { # upgrade only if hdb is uptodate
            @messageids=keys %HDB;
            foreach my $id (@messageids) {
               next if ( $id eq 'METAINFO'
                || $id eq 'NEWMESSAGES'
                || $id eq 'INTERNALMESSAGES'
                || $id eq 'ALLMESSAGES'
                || $id eq "" );

               @attr=split( /@@@/, $HDB{$id} );

               next if ( ($attr[$_CONTENT_TYPE] eq '' ||
                          $attr[$_CONTENT_TYPE] eq 'N/A' ||
                          $attr[$_CONTENT_TYPE] =~ /^text/i)
                       && $attr[$_SIZE]<4096 );

               next if ($attr[$_STATUS] =~ /T/i);

               if ($attr[$_SIZE]>65536) { # assume message > 64k has attachments
                  $attr[$_STATUS].="T";
               } else {
                  my $buff;
                  seek(FOLDER, $attr[$_OFFSET], 0);
                  read(FOLDER, $buff, $attr[$_SIZE]);
                  if ( $buff =~ /\ncontent\-type:.*;\s+name\s*=(.+?)\n/ims ||
                       $buff =~ /\n\s+name\s*=(.+?)\n/ims ||
                       $buff =~ /\ncontent\-disposition:.*;\s+filename\s*=(.+?)\n/ims ||
                       $buff =~ /\n\s+filename\s*=(.+?)\n/ims ||
                       $buff =~ /\nbegin [0-7][0-7][0-7][0-7]? [^\n\r]+\n/ims ) {
                     my $misc=$1;
                     if ($misc !~ /[\<\>]/ && $misc !~ /type=/i) {
                        $attr[$_STATUS].="T";
                     } else {
                        next;
                     }
                  } else {
                     next;
                  }
               }
               $HDB{$id}=join('@@@', @attr);
            }
         }
         close_dbm(\%HDB, $headerdb);
         close(FOLDER);
         filelock($folderfile, LOCK_UN);
      }
      writehistory("release upgrade - $folderdir/* by 20020108.02");
      writelog("release upgrade - $folderdir/* by 20020108.02");
   }

   if ( $user_releasedate lt "20020108.02" ) {
      my (@validfolders, $folderusage);
      getfolders(\@validfolders, \$folderusage);

      foreach my $foldername (@validfolders) {
         my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldername);
         my (%HDB, @messageids, @attr);
         next if ( ! -f "$headerdb$config{'dbm_ext'}" || -z "$headerdb$config{'dbm_ext'}" );

         open_dbm(\%HDB, $headerdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $headerdb$config{'dbm_ext'}");
         @messageids=keys %HDB;
         foreach my $id (@messageids) {
            next if ( $id eq 'METAINFO'
             || $id eq 'NEWMESSAGES'
             || $id eq 'INTERNALMESSAGES'
             || $id eq 'ALLMESSAGES'
             || $id eq "" );

            @attr=split( /@@@/, $HDB{$id} );
            next if ( $attr[$_DATE] !~ m!(\d+)/(\d+)/(\d\d+)\s+(\d+):(\d+):(\d+)! );
            my @d = ($1, $2, $3, $4, $5, $6);
            if ($d[2]<50) {
               $d[2]+=2000;
            } elsif ($d[2]<=1900) {
               $d[2]+=1900;
            }
            $attr[$_DATE]=sprintf("%4d%02d%02d%02d%02d%02d",
					$d[2],$d[0],$d[1], $d[3],$d[4],$d[5]);
            $HDB{$id}=join('@@@', @attr);
         }
         close_dbm(\%HDB, $headerdb);

         my $cachefile=untaint("$headerdb.cache");
         unlink($cachefile); # remove cache possiblely for old dbm
      }
      writehistory("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20020108.02");
      writelog("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20020108.02");
   }

   if ( $user_releasedate lt "20020601" ) {
      my $timeoffset=gettimeoffset();
      my (@validfolders, $folderusage);
      getfolders(\@validfolders, \$folderusage);

      foreach my $foldername (@validfolders) {
         my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldername);
         my (%HDB, @messageids, @attr);
         next if ( ! -f "$headerdb$config{'dbm_ext'}" || -z "$headerdb$config{'dbm_ext'}" );

         filelock($folderfile, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile");
         open (FOLDER, $folderfile);
         open_dbm(\%HDB, $headerdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $headerdb$config{'dbm_ext'}");

         @messageids=keys %HDB;
         foreach my $id (@messageids) {
            next if ( $id eq 'METAINFO'
                   || $id eq 'NEWMESSAGES'
                   || $id eq 'INTERNALMESSAGES'
                   || $id eq 'ALLMESSAGES'
                   || $id eq "" );
            my ($buff, $delimiter, $datefield, $dateserial);
            @attr=split( /@@@/, $HDB{$id} );
            seek(FOLDER, $attr[$_OFFSET], 0);
            if (length($attr[$_FROM].$attr[$_TO].$attr[$_SUBJECT].$attr[$_CONTENT_TYPE].$attr[$_REFERENCES])>384) {
                read(FOLDER, $buff, 2048);
            } else {
                read(FOLDER, $buff, 1024);
            }
            if ( $buff =~ /^From (.+?)\n/ims) {
               $delimiter=$1;
               if ( $buff =~ /\nDate: (.+?)\n/ims ) {
                  $datefield=$1;
               }
               my $dateserial=datefield2dateserial($datefield);
               my $deliserial=delimiter2dateserial($delimiter, $config{'deliver_use_GMT'}) ||
                              gmtime2dateserial();
               if ($dateserial eq "") {
                  $dateserial=$deliserial;
               } elsif ($deliserial ne "") {
                   my $t=dateserial2gmtime($deliserial)-dateserial2gmtime($dateserial);
                   if ($t>86400*7 || $t<-86400) { # msg transmission time
                      # use deliverytime in case sender host may have wrong time configuration
                      $dateserial=$deliserial;
                   }
               }
               $attr[$_DATE]=$dateserial;
            } else {
               my $t=dateserial2gmtime($attr[$_DATE])-timeoffset2seconds($timeoffset);	# local -> gm
               $t-=3600 if (is_dst($t, $timeoffset));
               $attr[$_DATE]=gmtime2dateserial($t);
            }
            $HDB{$id}=join('@@@', @attr);
         }
         close_dbm(\%HDB, $headerdb);
         close(FOLDER);
         filelock($folderfile, LOCK_UN);
      }
      writehistory("release upgrade - $folderdir/* by 20020601");
      writelog("release upgrade - $folderdir/* by 20020601");
   }

   if ( $user_releasedate lt "20021111" ) {
      my (@validfolders, $folderusage);
      getfolders(\@validfolders, \$folderusage);

      foreach my $foldername (@validfolders) {
         my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldername);
         my (%HDB, @messageids, @attr);
         next if ( ! -f "$headerdb$config{'dbm_ext'}" || -z "$headerdb$config{'dbm_ext'}" );

         open_dbm(\%HDB, $headerdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $headerdb$config{'dbm_ext'}");
         @messageids=keys %HDB;
         foreach my $id (@messageids) {
            next if ( $id eq 'METAINFO'
             || $id eq 'NEWMESSAGES'
             || $id eq 'INTERNALMESSAGES'
             || $id eq 'ALLMESSAGES'
             || $id eq "" );
            @attr=split( /@@@/, $HDB{$id} );
            if ( $attr[$_CHARSET] eq "" &&
                 $attr[$_CONTENT_TYPE]=~/charset="?([^\s"';]*)"?\s?/i) {
               $attr[$_CHARSET]=$1;
               $HDB{$id}=join('@@@', @attr);
            }
         }
         close_dbm(\%HDB, $headerdb);
      }
      writehistory("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20021111.02");
      writelog("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20021111.02");
   }

   if ( $user_releasedate lt "20021201" ) {
      if ( -f "$folderdir/.calendar.book" ) {
         my $content='';
         filelock("$folderdir/.calendar.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.calendar.book");
         open(F, "$folderdir/.calendar.book");
         while (<F>) {
            next if (/^#/);
            chomp;
            # fields: idate, starthourmin, endhourmin, string, link, email, color
            my @a=split(/\@\@\@/, $_);
            if ($#a==7) {
               $content.=join('@@@', @a);
            } elsif ($#a==6) {
               $content.=join('@@@', @a, 'none');
            } elsif ($#a==5) {
               $content.=join('@@@', @a, ,'0', 'none');
            } elsif ($#a<5) {
               $content.=join('@@@', $a[0], $a[1], $a[2], '0', $a[3], $a[4], '0', 'none');
            }
            $content.="\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.calendar.book by 20021201");
            writelog("release upgrade - $folderdir/.calendar.book by 20021201");
            open(F, ">$folderdir/.calendar.book");
            print F $content;
            close(F);
         }
         filelock("$folderdir/.calendar.book", LOCK_UN);
      }
   }

   if ( $user_releasedate lt "20030528" ) {
      if ( -f "$folderdir/.pop3.book" ) {
         $content="";
         filelock("$folderdir/.pop3.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.pop3.book");
         open(F, "$folderdir/.pop3.book");
         while (<F>) {
            chomp;
            my @a=split(/\@\@\@/);
            my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable)=@a;
            if ($pop3port!~/^\d+$/||$pop3port>65535) {	# not port number? old format!
               ($pop3host, $pop3user, $pop3passwd, $pop3del, $enable)=@a[0,1,2,4,5];
               $pop3port=110;
               # not secure, but better than plaintext
               $pop3passwd=$pop3passwd ^ substr($pop3host,5,length($pop3passwd));
               $pop3passwd=encode_base64($pop3passwd, '');
            }
            $content.="$pop3host\@\@\@$pop3port\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.pop3.book by 20030528");
            writelog("release upgrade - $folderdir/.pop3.book by 20030528");
            open(F, ">$folderdir/.pop3.book");
            print F $content;
            close(F);
         }
         filelock("$folderdir/.pop3.book", LOCK_UN);
      }
   }

   my $saverc=0;
   if (-f "$folderdir/.openwebmailrc") {
      $saverc=1 if ( $user_releasedate lt "20031027" );	# rc upgrade
      %prefs = readprefs() if ($saverc);		# load user old prefs + sys defaults
   } else {
      $saverc=1 if ($config{'auto_createrc'});		# rc auto create
   }
   if ($saverc) {
      open (RC, ">$folderdir/.openwebmailrc") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.openwebmailrc! ($!)");
      foreach my $key (@openwebmailrcitem) {
         print RC "$key=$prefs{$key}\n";
      }
      close (RC) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.openwebmailrc!");
   }

   return;
}
#################### END RELEASEUPGRADE ####################
