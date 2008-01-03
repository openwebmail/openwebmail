#!/usr/bin/suidperl -T
#################################################################
#                                                               #
# OpenWebMail - Provides a web interface to user mailboxes      #
#                                                               #
# Copyright (C) 2001-2005                                       #
# The OpenWebmail Team                                          #
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
require "shares/iconv.pl";
require "shares/pop3book.pl";
require "shares/upgrade.pl";

# optional module
ow::tool::has_module('IO/Socket/SSL.pm');
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);

# extern vars
use vars qw(@openwebmailrcitem);	# defined in ow-shared.pl
use vars qw(%lang_text %lang_err);	# defined in lang/xy

use vars qw(%action_redirect @actions);
%action_redirect= (
   listmessages_afterlogin => [1, 'enable_webmail',     'openwebmail-main.pl',    ['folder']],
   calmonth                => [2, 'enable_calendar',    'openwebmail-cal.pl',     ['year', 'month']],
   showdir                 => [3, 'enable_webdisk',     'openwebmail-webdisk.pl', ['currentdir']],
   addrlistview            => [4, 'enable_addressbook', 'openwebmail-abook.pl',   ['abookfolder']],
   callist                 => [5, 'enable_calendar',    'openwebmail-cal.pl',     ['year']],
   calyear                 => [6, 'enable_calendar',    'openwebmail-cal.pl',     ['year']],
   calday                  => [7, 'enable_calendar',    'openwebmail-cal.pl',     ['year', 'month', 'day']],
   readmessage             => [8, 'enable_webmail',     'openwebmail-read.pl',    ['folder', 'message_id']],
   composemessage          => [9, 'enable_webmail',     'openwebmail-send.pl',    ['to', 'cc', 'bcc', 'subject', 'body']],
);
@actions = sort { ${$action_redirect{$a}}[0] <=> ${$action_redirect{$b}}[0] } keys (%action_redirect);

########## MAIN ##################################################
openwebmail_requestbegin();

load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
loadlang($config{'default_locale'}); # so %lang... can be used in error msg

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
      sysopen(LOGFILE, $config{'logfile'}, O_WRONLY|O_APPEND|O_CREAT, 0660) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $lang_text{'file'} $config{'logfile'}! ($!)");
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

writelog("debug - request login begin - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ( param('loginname') && param('password') ) {
   login();
} elsif (matchlist_fromhead('allowed_autologinip', ow::tool::clientip()) &&
         cookie('ow-autologin')) {
   autologin();
} else {
   loginmenu();	# display login page if no login
}
writelog("debug - request login end - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## LOGINMENU #############################################
sub loginmenu {
   # clear vars that may have values from autologin
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)=('', '', '', '', '', '');

   $logindomain=param('logindomain')||lc($ENV{'HTTP_HOST'});
   $logindomain=~s/:\d+$//;	# remove port number
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined $config{'domainname_equiv'}{'map'}{$logindomain});

   matchlist_exact('allowed_serverdomain', $logindomain) or
      openwebmailerror(__FILE__, __LINE__, "Service is not available for domain  '$logindomain'");

   read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain") if ( -f "$config{'ow_sitesconfdir'}/$logindomain");
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
        !$config{'use_homedirspools'} &&
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; openwebmail_exit(0);
   }
#
#use Data::Dumper;
#use CGI qw(:standard);
#$Data::Dumper::Sortkeys++;
#print header();
#print Dumper(\%prefs, \%config);
#exit 0;
#
#
   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   loadlang($prefs{'locale'});
   $prefs{'charset'} = (ow::lang::localeinfo($prefs{'locale'}))[6];
   $prefs{'language'} = join("_", (ow::lang::localeinfo($prefs{'locale'}))[0,2]);
   charset($prefs{'charset'}) if ($CGI::VERSION>=2.58); # setup charset of CGI module

   my ($html, $temphtml);
   $html = applystyle(readtemplate("login.template"));

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail.pl",
                          -name=>'login');

   # remember params for redirection after login
   my $action=param('action');
   $action='listmessages_afterlogin' if ($action eq 'listmessages');
   if (defined $action_redirect{$action}) {
      $temphtml .= ow::tool::hiddens(action=>$action);
      foreach my $name (@{${$action_redirect{$action}}[3]}) {
         $temphtml .= ow::tool::hiddens($name=>param($name));
      }
   }
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   # we set onChange to '' if browser is gecko based (eg:mozilla, firefox) to avoid the following warning in js console
   # "Permission denied to get property XULElement.selectedIndex' when calling method: [nsIAutoCompletePopup::selectedIndex]"

   $temphtml = textfield(-name=>'loginname',
                         -default=>'',
                         -size=>$config{'login_fieldwidth'},
                         -onChange=>($ENV{HTTP_USER_AGENT}=~/Gecko/)?'':'focuspwd()',
                         -override=>'1');
   $html =~ s/\@\@\@LOGINNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'password',
                              -default=>'',
                              -size=>$config{'login_fieldwidth'},
                              -onChange=>($ENV{HTTP_USER_AGENT}=~/Gecko/)?'':'focusloginbutton()',
                              -override=>'1');
   $html =~ s/\@\@\@PASSWORDFIELD\@\@\@/$temphtml/;

   if ($ENV{'HTTP_ACCEPT_ENCODING'}=~/\bgzip\b/ &&
       ow::tool::has_module('Compress/Zlib.pm') ) {
      my $use_httpcompress=cookie("ow-httpcompress");
      if ($use_httpcompress eq '') {	# use http compress by default
         $use_httpcompress=1;
      }
      $temphtml = checkbox(-name=>'httpcompress',
                           -value=>'1',
                           -checked=>$use_httpcompress||0,
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
                           -checked=>cookie("ow-autologin")||0,
                           -onClick=>'autologinhelp()',
                           -label=>'');
      $html =~ s/\@\@\@AUTOLOGINCHECKBOX\@\@\@/$temphtml/;
   } else {
      $temphtml = '';
      templateblock_disable($html, 'AUTOLOGIN', $temphtml);
   }

   if ($config{'enable_domainselectmenu'}) {
      templateblock_enable($html, 'DOMAIN');
      $temphtml = popup_menu(-name=>'logindomain',
                             -default=>$logindomain,
                             -values=>[@{$config{'domainselectmenu_list'}}] );
      $html =~ s/\@\@\@DOMAINMENU\@\@\@/$temphtml/;
   } else {
      $temphtml = ow::tool::hiddens(logindomain=>$logindomain||'');
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
   $loginname=~s/\s//g; # remove space,\t,\n,\r
   $default_logindomain=safedomainname(param('logindomain')||'');

   ($logindomain, $loginuser)=login_name2domainuser($loginname, $default_logindomain);

   matchlist_exact('allowed_serverdomain', $logindomain) or
      openwebmailerror(__FILE__, __LINE__, "Service is not available for domain  '$logindomain'");

   if (!is_localuser("$loginuser\@$logindomain") && -f "$config{'ow_sitesconfdir'}/$logindomain") {
      read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   }
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
        !$config{'use_homedirspools'} &&
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
         sysopen(LOGFILE, $config{'logfile'}, O_WRONLY|O_APPEND|O_CREAT, 0660) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $lang_text{'file'} $config{'logfile'}! ($!)");
         close(LOGFILE);
      }
      chmod(0660, $config{'logfile'}) if (($fmode&0660)!=0660);
      chown($>, $mailgid, $config{'logfile'}) if ($fuid!=$>||$fgid!=$mailgid);
   }

   update_virtuserdb();	# update index db of virtusertable

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   loadlang($prefs{'locale'});
   $prefs{'charset'} = (ow::lang::localeinfo($prefs{'locale'}))[6];
   $prefs{'language'} = join("_", (ow::lang::localeinfo($prefs{'locale'}))[0,2]);
   charset($prefs{'charset'}) if ($CGI::VERSION>=2.58); # setup charset of CGI module

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
      openwebmailerror(__FILE__, __LINE__, $lang_err{'disallowed_client'}." ( ip: $clientip )");

   if (!matchlist_all('allowed_clientdomain')) {
      my $clientdomain=ip2hostname($clientip);
      matchlist_fromtail('allowed_clientdomain', $clientdomain) or
         openwebmailerror(__FILE__, __LINE__, $lang_err{'disallowed_client'}." ( host: $clientdomain )");
   }

   # keep this for later use
   my $syshomedir=$homedir;
   my $owuserdir = ow::tool::untaint("$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user));
   $homedir = $owuserdir if ( !$config{'use_syshomedir'} );

   $user=ow::tool::untaint($user);
   $uuid=ow::tool::untaint($uuid);
   $ugid=ow::tool::untaint($ugid);
   $homedir=ow::tool::untaint($homedir);

   my $password = param('password') || '';
   my ($errorcode, $errormsg);
   if ($config{'auth_withdomain'}) {
      ($errorcode, $errormsg)=ow::auth::check_userpassword(\%config, "$user\@$domain", $password);
   } else {
      ($errorcode, $errormsg)=ow::auth::check_userpassword(\%config, $user, $password);
   }
   if ( $errorcode!=0 ) { # Password is INCORRECT
      writelog("login error - $config{'auth_module'}, ret $errorcode, $errormsg");
      umask(0077);
      if ( $>==0 ) {	# switch to uuid:mailgid if script is setuid root.
         my $mailgid=getgrnam('mail');
         ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
      }
      my $historyfile=ow::tool::untaint(dotpath('history.log'));
      if (-f $historyfile ) {
         writehistory("login error - $config{'auth_module'}, ret $errorcode, $errormsg");
      }

      my %err = (
         -1 => $lang_err{'func_notsupported'},
         -2 => $lang_err{'param_fmterr'},
         -3 => $lang_err{'auth_syserr'},
         -4 => $lang_err{'pwd_incorrect'},
      );
      my $webmsg=$err{$errorcode} || "Unknown error code $errorcode";
      my $html = applystyle(readtemplate("loginfailed.template"));
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$webmsg/;

      sleep $config{'loginerrordelay'};	# delayed response
      $user='';				# to remove userinfo in htmlheader
      httpprint([], [htmlheader(), $html, htmlfooter(1)]);
      return;
   }

   # try to load lang and style based on user's preference (for error msg)
   if ($>==0 || $>== $uuid) {
      %prefs = readprefs();
      %style = readstyle($prefs{'style'});
      loadlang($prefs{'locale'});
      $prefs{'charset'} = (ow::lang::localeinfo($prefs{'locale'}))[6];
      $prefs{'language'} = join("_", (ow::lang::localeinfo($prefs{'locale'}))[0,2]);
      charset($prefs{'charset'}) if ($CGI::VERSION>=2.58); # setup charset of CGI module
   }

   # create domainhome for stuff not put in syshomedir
   if (!$config{'use_syshomedir'} || !$config{'use_syshomedir_for_dotdir'}) {
      if ($config{'auth_withdomain'}) {
         my $domainhome=ow::tool::untaint("$config{'ow_usersdir'}/$domain");
         if (!-d $domainhome) {
            mkdir($domainhome, 0750);
            openwebmailerror(__FILE__, __LINE__, "Couldn't create domain homedir $domainhome") if (! -d $domainhome);
            my $mailgid=getgrnam('mail');
            chown($uuid, $mailgid, $domainhome) if ($>==0);
         }
      }
   }
   upgrade_20030323();

   # create owuserdir for stuff not put in syshomedir
   # this must be done before changing to the user's uid.
   if ( !$config{'use_syshomedir'} || !$config{'use_syshomedir_for_dotdir'} ) {
      if (!-d $owuserdir) {
         if (mkdir($owuserdir, 0700)) {
            if ($>==0) {
               chown($uuid, (split(/\s+/,$ugid))[0], $owuserdir);
               writelog("create owuserdir - $owuserdir, uid=$uuid, gid=".(split(/\s+/,$ugid))[0]);
            } else {
               writelog("create owuserdir - $owuserdir");
            }
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $owuserdir ($!)");
         }
      }
   }

   # create the user's syshome directory if necessary.
   # this must be done before changing to the user's uid.
   if (!-d $homedir && $config{'create_syshomedir'}) {
      if (mkdir($homedir, 0700)) {
         if ($>==0) {
            chown($uuid, (split(/\s+/,$ugid))[0], $homedir);
            writelog("create homedir - $homedir, uid=$uuid, gid=".(split(/\s+/,$ugid))[0]);
         } else {
            writelog("create homedir - $homedir");
         }
      } else {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $homedir ($!)");
      }
   }

   # search old alive session and deletes old expired sessionids
   my @sessioncount;
   ($thissession, @sessioncount) = search_clean_oldsessions
	($loginname, $default_logindomain, $uuid, cookie("ow-sessionkey-$domain-$user"));
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

   # set umask, switch to uuid:mailgid if script is setuid root.
   umask(0077);
   if ( $>==0 ) {
      my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
      ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
      if ( $)!~/\b$mailgid\b/) {	# group mail doesn't exist?
         openwebmailerror(__FILE__, __LINE__, "Set effective gid to mail($mailgid) failed!");
      }
   }

   # locate existing .openwebmail
   find_and_move_dotdir($syshomedir, $owuserdir) if (!-d dotpath('/'));

   # get user release date
   my $user_releasedate=read_releasedatefile();

   # create folderdir if it doesn't exist
   my $folderdir="$homedir/$config{'homedirfolderdirname'}";
   if (! -d $folderdir ) {
      if (mkdir ($folderdir, 0700)) {
         writelog("create folderdir - $folderdir, euid=$>, egid=$)");
      } else {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $folderdir ($!)");
      }
      upgrade_20021218($user_releasedate);
   }

   # create dirs under ~/.openwebmail/
   check_and_create_dotdir(dotpath('/'));

   # create system spool file /var/mail/xxxx
   my $spoolfile=ow::tool::untaint((get_folderpath_folderdb($user, 'INBOX'))[0]);
   if ( !-f "$spoolfile" ) {
      sysopen(F, $spoolfile, O_WRONLY|O_APPEND|O_CREAT, 0600); close(F);
      chown($uuid, (split(/\s+/,$ugid))[0], $spoolfile) if ($>==0);
   }

   # create session file
   my $sessionkey;
   if ( -f "$config{'ow_sessionsdir'}/$thissession" ) { # continue an old session?
      $sessionkey = cookie("ow-sessionkey-$domain-$user");
   } else {						       # a brand new sesion?
      $sessionkey = crypt(rand(),'OW');
   }
   sysopen(SESSION, "$config{'ow_sessionsdir'}/$thissession", O_WRONLY|O_TRUNC|O_CREAT) or # create sessionid
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $config{'ow_sessionsdir'}/$thissession! ($!)");
   print SESSION $sessionkey, "\n";
   print SESSION $clientip, "\n";
   print SESSION join("\@\@\@", $domain, $user, $userrealname, $uuid, $ugid, $homedir), "\n";
   close(SESSION);
   writehistory("login - $thissession");

   # symbolic link ~/mbox to ~/mail/saved-messages if ~/mbox is not spoolfile
   if ( $config{'symboliclink_mbox'} &&
        $spoolfile ne "$homedir/mbox" &&
        ((lstat("$homedir/mbox"))[2] & 07770000) eq 0100000) { # ~/mbox is regular file
      if (ow::filelock::lock("$folderdir/saved-messages", LOCK_EX|LOCK_NB)) {
         writelog("symlink mbox - $homedir/mbox -> $folderdir/saved-messages");

         if (sysopen(F, "$folderdir/saved-messages", O_WRONLY|O_APPEND|O_CREAT)) {
            seek(F, 0, 2);	# seek to end;
            rename("$homedir/mbox", "$homedir/mbox.old.$$");
            symlink("$folderdir/saved-messages", "$homedir/mbox");
            if (sysopen(T, "$homedir/mbox.old.$$", O_RDONLY)) {
               while(<T>) { print F $_; }
               close(T);
               unlink("$homedir/mbox.old.$$");
            }
            close(F);
         }
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

   my $prefscharset = (ow::lang::localeinfo($prefs{'locale'}))[6];
   my @header=(-Charset=>$prefscharset);
   my @cookies=();
   # cookie for autologin switch, expired until 1 month later
   my $autologin=param('autologin')||0;
   if ($autologin && matchlist_fromhead('allowed_autologinip', $clientip)) {
      $autologin=autologin_add();
   } else {
      autologin_rm();
      $autologin=0;
   }
   push(@cookies, cookie(-name  => 'ow-autologin',
                         -value => $autologin,
                         -path  => '/',
                         -expires => '+1M') );

   # if autologin then expired until 1 week, else expired until browser close
   my @expire=(); @expire=(-expires => '+7d') if ($autologin);

   # cookie for openwebmail to verify session,
   push(@cookies, cookie(-name  => "ow-sessionkey-$domain-$user",
                         -value => $sessionkey,
                         -path  => '/',
                         @expire) );
   # cookie for ssl session, expired if browser closed
   push(@cookies, cookie(-name  => 'ow-ssl',
                         -value => ($ENV{'HTTPS'}=~/on/i ||
                                    $ENV{'SERVER_PORT'}==443 ||
                                    0),
                         @expire) );

   # cookie for autologin other other ap to find openwebmail loginname, default_logindomain,
   # expired until 1 month later
   push(@cookies, cookie(-name  => 'ow-loginname',
                         -value => $loginname,
                         -path  => '/',
                         -expires => '+1M') );
   push(@cookies, cookie(-name  => 'ow-default_logindomain',
                         -value => $default_logindomain,
                         -path  => '/',
                         -expires => '+1M') );

   # cookie for httpcompress switch, expired until 1 month later
   push(@cookies, cookie(-name  => 'ow-httpcompress',
                         -value => param('httpcompress')||0,
                         -path  => '/',
                         -expires => '+1M') );
   push(@header, -cookie=>\@cookies);

   my ($js, $repeatstr)=('', 'no-repeat');
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
      $softwarestr.=qq| $config{'version'}.$config{'revision'} $config{'releasedate'}|;
   }

   my $countstr='';
   if ($config{'session_count_display'}) {
      $countstr=qq|<br><br><br>\n|.
                qq|<a href=# title="number of active sessions in the past 1, 5, 15 minutes">Sessions&nbsp; :&nbsp; |.
                qq|$sessioncount[0],&nbsp; $sessioncount[1],&nbsp; $sessioncount[2]</a>\n|;
   }

   # display copyright. Don't touch it, please.
   httpprint(\@header, [
	qq|<html>\n|.
	qq|<head>\n|.
	qq|<title>$config{'name'} - Copyright</title>\n|.
	qq|<meta http-equiv="Content-Type" content="text/html; charset=$prefscharset">\n|.
	qq|</head>\n|.
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
	qq|Copyright (C) 2001-2008<br>\n|.
	qq|Thomas Chung, Alex Teslik, Scott Mazur, Joao S Veiga, Marian &#270;urkovi&#269;<br><br>\n|.
	qq|Copyright (C) 2000<br>\n|.
	qq|Ernie Miller  (original GPL project: Neomail)<br><br>\n|.
	qq|Special Thanks to Retired Developers<br>\n|.
	qq|Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric,<br>|.
	qq|Dattola Filippo, Bernd Bass<br><br>\n|.
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
	qq|</center></body></html>\n| ]);
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
   $loginname=param('loginname')||cookie('ow-loginname');
   $loginname=~s/\s//g; # remove space,\t,\n,\r
   $default_logindomain=safedomainname(param('logindomain')||cookie('ow-default_logindomain'));
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
       cookie("ow-sessionkey-$domain-$user") eq '') {
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
		($loginname, $default_logindomain, $uuid, cookie("ow-sessionkey-$domain-$user")))[0];
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
   $action='listmessages_afterlogin' if ($action eq 'listmessages');

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
   my ($loginname, $default_logindomain, $owner_uid, $client_sessionkey)=@_;
   my $oldsessionid="";
   my @sessioncount=(0,0,0);	# active sessions in 1, 5, 15 minutes
   my @delfiles;

   opendir(D, "$config{'ow_sessionsdir'}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_sessionsdir'}! ($!)");
      my @sessfiles=readdir(D);
   closedir(D);

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
            my ($sessionkey, $ip, $userinfo)=sessioninfo($sessfile);
            if ($client_sessionkey ne '' &&
                $client_sessionkey eq $sessionkey  &&
                $clientip eq $ip &&
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

   # clear stale file for ow::tool::mktmpdir ow::tool:mktmpfile
   @delfiles=();
   if (opendir(D, "/tmp")) {
      my @tmpfiles=readdir(D); closedir(D);
      foreach my $tmpfile (@tmpfiles) {
         next if ($tmpfile!~/^\.ow\./);
         push(@delfiles, ow::tool::untaint("/tmp/$tmpfile")) if ($t-(stat("/tmp/$tmpfile"))[9]>3600);
      }
      if ($#delfiles>=0) {
         my $rmbin=ow::tool::findbin("rm");
         system($rmbin, "-Rf", @delfiles);
      }
   }

   return($oldsessionid, @sessioncount);
}

########## END SEARCH_AND_CLEANOLDSESSIONS #######################
