#!/usr/bin/suidperl -T

#                              The BSD License
#
#  Copyright (c) 2008, The OpenWebMail Project
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

use strict;
use warnings;

use vars qw($SCRIPT_DIR);

if (-f "/etc/openwebmail_path.conf") {
   my $pathconf = "/etc/openwebmail_path.conf";
   open(F, $pathconf) or die("Cannot open $pathconf: $!");
   my $pathinfo = <F>;
   close(F) or die("Cannot close $pathconf: $!");
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die("SCRIPT_DIR cannot be set") if ($SCRIPT_DIR eq '');
push (@INC, $SCRIPT_DIR);

use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);
use HTML::Template 2.9;
use MIME::Base64;
use Socket;

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH}='/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load the OWM libraries
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
use vars qw($htmltemplatefilters);      # defined in ow-shared.pl
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




# BEGIN MAIN PROGRAM

openwebmail_requestbegin();

load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
loadlang($config{default_locale}); # so %lang... can be used in error msg

# check & create mapping table for solar/lunar, b2g, g2b convertion
foreach my $table ('b2g', 'g2b', 'lunar') {
   if ( $config{$table.'_map'} && !ow::dbm::exist("$config{ow_mapsdir}/$table")) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{execute_init_first}");
   }
}

if ($config{logfile}) {
   my $mailgid = getgrnam('mail');
   my ($fmode, $fuid, $fgid) = (stat($config{logfile}))[2,4,5];
   if ( !($fmode & 0100000) ) {
      sysopen(LOGFILE, $config{logfile}, O_WRONLY|O_APPEND|O_CREAT, 0660) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $lang_text{file} $config{logfile}! ($!)");
      close(LOGFILE);
   }
   chmod(0660, $config{logfile}) if (($fmode & 0660) != 0660);
   chown($>, $mailgid, $config{logfile}) if (($fuid != $>) || ($fgid != $mailgid));
}

if ( $config{forced_ssl_login} && !($ENV{HTTPS} =~ /on/i || $ENV{SERVER_PORT} == 443) ) {
   my ($start_url, $refresh, $js) = ();

   $start_url = $config{start_url};
   $start_url = "https://$ENV{HTTP_HOST}$start_url" if ($start_url !~ s#^https?://#https://#i);

   my $template = HTML::Template->new(
                                        filename          => get_template("init_sslredirect.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param( start_url => $start_url );

   httpprint([], [$template->output]);

   openwebmail_exit(0);
}

writelog("debug - request login begin - " .__FILE__.":". __LINE__) if ($config{debug_request});

if ( param('loginname') && param('password') ) {
   login();
} elsif (matchlist_fromhead('allowed_autologinip', ow::tool::clientip()) && cookie('ow-autologin')) {
   autologin();
} else {
   loginmenu();
}

writelog("debug - request login end - " .__FILE__.":". __LINE__) if ($config{debug_request});

openwebmail_requestend();




# BEGIN SUBROUTINES

sub loginmenu {
   # clear vars that may have values from autologin
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)=('', '', '', '', '', '');

   # logindomain options
   $logindomain = param('logindomain') || lc($ENV{HTTP_HOST});
   $logindomain =~ s#:\d+$##;	# remove port number
   $logindomain = lc(safedomainname($logindomain));
   $logindomain = $config{domainname_equiv}{map}{$logindomain} if (defined $config{domainname_equiv}{map}{$logindomain});

   unless (matchlist_exact('allowed_serverdomain', $logindomain)) {
      my $error = $lang_err{domain_service_unavailable};
      $error =~ s#\@\@\@DOMAIN\@\@\@#$logindomain#;
      openwebmailerror(__FILE__, __LINE__, $error);
   }

   read_owconf(\%config, \%config_raw, "$config{ow_sitesconfdir}/$logindomain") if ( -f "$config{ow_sitesconfdir}/$logindomain");

   # setuid is required if spool is located in system dir
   if ( $> != 0 && !$config{use_homedirspools}
        && ($config{mailspooldir} eq "/var/mail" || $config{mailspooldir} eq "/var/spool/mail")) {
      openwebmailerror(__FILE__, __LINE__, "$0 $lang_err{must_setuid_root}");
   }

   %prefs = readprefs();

   loadlang($prefs{locale});
   $prefs{charset}  = (ow::lang::localeinfo($prefs{locale}))[6];
   $prefs{language} = join("_", (ow::lang::localeinfo($prefs{locale}))[0,2]);

   # compile parameters for redirect after login loop
   my $redirectloop = [ { name => "action", value => (param('action') || '') } ];
   $redirectloop->[0]{value} = "listmessages_afterlogin" if (defined $redirectloop->[0]{value} && $redirectloop->[0]{value} eq "listmessages");
   if (defined $redirectloop->[0]{value} && defined $action_redirect{$redirectloop->[0]{value}}) {
      foreach my $name (@{$action_redirect{$redirectloop->[0]{value}}->[3]}) {
         push(@{$redirectloop}, { name => $name, value => (param($name) || '') });
      }
   } else {
      $redirectloop = []; # invalid redirect action
   }

   # domainselect options
   my $enable_domainselect = $config{enable_domainselectmenu}?1:0;
   my $domainselectloop    = [ map { { option => $_, selected => ($_ eq $logindomain?1:0), label => $_ } } @{$config{domainselectmenu_list}}];
   $domainselectloop       = [] unless $enable_domainselect;

   # http compression options
   my $enable_httpcompression = 1;
   my $use_httpcompression    = 1;
   if ($ENV{HTTP_ACCEPT_ENCODING} =~ m/\bgzip\b/ && ow::tool::has_module('Compress/Zlib.pm') ) {
      $use_httpcompression = cookie("ow-httpcompress");
      $use_httpcompression = 1 if ($use_httpcompression eq '');
   } else {
      $enable_httpcompression = 0;
      $use_httpcompression    = 0;
   }

   # autologin options
   my $enable_autologin = 1;
   my $use_autologin    = 0;
   if (matchlist_fromhead('allowed_autologinip', ow::tool::clientip()) ) {
      $use_autologin = cookie("ow-autologin") || 0;
   } else {
      $enable_autologin = 0;
      $use_autologin    = 0;
   }

   # undef env to prevent httpprint() doing compression on login page
   delete $ENV{HTTP_ACCEPT_ENCODING} if (exists $ENV{HTTP_ACCEPT_ENCODING} && defined $ENV{HTTP_ACCEPT_ENCODING});

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("login.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template        => get_header($config{header_template_file}),

                      # login.tmpl
                      logo_link              => $config{logo_link},
                      url_logo               => $config{logo_url},
                      url_cgi                => $config{ow_cgiurl},
                      url_html               => $config{ow_htmlurl},
                      redirectloop           => $redirectloop,
                      logindomain            => $logindomain,
                      loginfieldwidth        => $config{login_fieldwidth},
                      enable_domainselect    => $enable_domainselect,
                      domainselectloop       => $domainselectloop,
                      enable_httpcompression => $enable_httpcompression,
                      use_httpcompression    => $use_httpcompression,
                      enable_autologin       => $enable_autologin,
                      use_autologin          => $use_autologin,

                      # footer.tmpl
                      footer_template        => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub login {
   my $clientip = ow::tool::clientip();

   $loginname = param('loginname') || '';
   $loginname =~ s#\s##g; # remove any whitespace
   $default_logindomain = safedomainname(param('logindomain') || '');

   ($logindomain, $loginuser) = login_name2domainuser($loginname, $default_logindomain);

   unless (matchlist_exact('allowed_serverdomain', $logindomain)) {
      my $error = $lang_err{domain_service_unavailable};
      $error =~ s#\@\@\@DOMAIN\@\@\@#$logindomain#;
      openwebmailerror(__FILE__, __LINE__, $error);
   }

   if (!is_localuser("$loginuser\@$logindomain") && -f "$config{ow_sitesconfdir}/$logindomain") {
      read_owconf(\%config, \%config_raw, "$config{ow_sitesconfdir}/$logindomain");
   }

   # setuid is required if spool is located in system dir
   if ( $> != 0 && !$config{use_homedirspools}
        && ($config{mailspooldir} eq "/var/mail" || $config{mailspooldir} eq "/var/spool/mail")) {
      openwebmailerror(__FILE__, __LINE__, "$0 $lang_err{must_setuid_root}");
   }

   ow::auth::load($config{auth_module});

   # create domain logfile
   if ($config{logfile}) {
      my $mailgid = getgrnam('mail');
      my ($fmode, $fuid, $fgid) = (stat($config{logfile}))[2,4,5];
      if ( !($fmode & 0100000) ) {
         sysopen(LOGFILE, $config{logfile}, O_WRONLY|O_APPEND|O_CREAT, 0660) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $lang_text{file} $config{logfile}! ($!)");
         close(LOGFILE);
      }
      chmod(0660, $config{logfile}) if (($fmode & 0660) != 0660);
      chown($>, $mailgid, $config{logfile}) if ($fuid != $> || $fgid != $mailgid);
   }

   update_virtuserdb();	# update index db of virtusertable

   %prefs = readprefs();

   loadlang($prefs{locale});
   $prefs{charset}  = (ow::lang::localeinfo($prefs{locale}))[6];
   $prefs{language} = join("_", (ow::lang::localeinfo($prefs{locale}))[0,2]);

   ($domain, $user, $userrealname, $uuid, $ugid, $homedir) = get_domain_user_userinfo($logindomain, $loginuser);

   if ($user eq "") {
      writelog("login error - no such user - loginname=$loginname");
      return loginfailed();
   }

   if (!matchlist_fromhead('allowed_rootloginip', $clientip)) {
      if ($user eq 'root' || $uuid == 0) {
         writelog("login error - root login attempt");
         return loginfailed();
      }
   }

   my $userconf = "$config{ow_usersconfdir}/$user";
   $userconf    = "$config{ow_usersconfdir}/$domain/$user" if $config{auth_withdomain};
   read_owconf(\%config, \%config_raw, "$userconf") if (-f "$userconf");

   unless (matchlist_exact('allowed_serverdomain', $logindomain)) {
      my $error = $lang_err{user_at_domain_service_unavailable};
      $error =~ s#\@\@\@USER\@\@\@#$loginuser#;
      $error =~ s#\@\@\@DOMAIN\@\@\@#$logindomain#;
      openwebmailerror(__FILE__, __LINE__, $error);
   }

   matchlist_fromhead('allowed_clientip', $clientip) or
      openwebmailerror(__FILE__, __LINE__, $lang_err{disallowed_client}." ( ip: $clientip )");

   if (!matchlist_all('allowed_clientdomain')) {
      my $clientdomain = ip2hostname($clientip);
      matchlist_fromtail('allowed_clientdomain', $clientdomain) or
         openwebmailerror(__FILE__, __LINE__, $lang_err{disallowed_client}." ( host: $clientdomain )");
   }

   # keep this for later use
   my $syshomedir = $homedir;
   my $owuserdir  = ow::tool::untaint("$config{ow_usersdir}/" . ($config{auth_withdomain}?"$domain/$user":$user));
   $homedir = $owuserdir if ( !$config{use_syshomedir} );

   $user    = ow::tool::untaint($user);
   $uuid    = ow::tool::untaint($uuid);
   $ugid    = ow::tool::untaint($ugid);
   $homedir = ow::tool::untaint($homedir);

   my $password = param('password') || '';

   my ($errorcode, $errormsg) = ();

   if ($config{auth_withdomain}) {
      ($errorcode, $errormsg)=ow::auth::check_userpassword(\%config, "$user\@$domain", $password);
   } else {
      ($errorcode, $errormsg)=ow::auth::check_userpassword(\%config, $user, $password);
   }

   if ( $errorcode != 0 ) {
      # password is incorrect
      writelog("login error - $config{auth_module}, ret $errorcode, $errormsg");

      umask(0077);

      if ( $> == 0 ) {
         # switch to uuid:mailgid if script is setuid root.
         my $mailgid = getgrnam('mail');
         ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
      }

      my $historyfile = ow::tool::untaint(dotpath('history.log'));
      if (-f $historyfile ) {
         writehistory("login error - $config{auth_module}, ret $errorcode, $errormsg");
      }

      my %err = (
         -1 => $lang_err{func_notsupported},
         -2 => $lang_err{param_fmterr},
         -3 => $lang_err{auth_syserr},
         -4 => '', # password is incorrect
      );

      my $message = defined $err{$errorcode}?$err{$errorcode}:"Unknown error code $errorcode";
      return loginfailed($message);
   }

   # try to load lang and style based on user's preference for error msg
   if ($> == 0 || $> == $uuid) {
      %prefs = readprefs();
      loadlang($prefs{locale});
      $prefs{charset}  = (ow::lang::localeinfo($prefs{locale}))[6];
      $prefs{language} = join("_", (ow::lang::localeinfo($prefs{locale}))[0,2]);
   }

   # create domainhome for stuff not put in syshomedir
   if (!$config{use_syshomedir} || !$config{use_syshomedir_for_dotdir}) {
      if ($config{auth_withdomain}) {
         my $domainhome = ow::tool::untaint("$config{ow_usersdir}/$domain");
         if (!-d $domainhome) {
            mkdir($domainhome, 0750);
            if (! -d $domainhome) {
               my $error = $lang_err{domain_homedir};;
               $error =~ s#\@\@\@DOMAINHOME\@\@\@#$domainhome#;
               openwebmailerror(__FILE__, __LINE__, $error);
            }
            my $mailgid = getgrnam('mail');
            chown($uuid, $mailgid, $domainhome) if ($> == 0);
         }
      }
   }

   # move homedir if needed
   upgrade_20030323();

   # create owuserdir for stuff not put in syshomedir
   # this must be done before changing to the user's uid.
   if ( !$config{use_syshomedir} || !$config{use_syshomedir_for_dotdir} ) {
      if (!-d $owuserdir) {
         if (mkdir($owuserdir, 0700)) {
            if ($> == 0) {
               my $firstusergroup = (split(/\s+/,$ugid))[0];
               chown($uuid, $firstusergroup, $owuserdir);
               writelog("create owuserdir - $owuserdir, uid=$uuid, gid=$firstusergroup");
            } else {
               writelog("create owuserdir - $owuserdir");
            }
         } else {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $owuserdir ($!)");
         }
      }
   }

   # create the user's syshome directory if necessary.
   # this must be done before changing to the user's uid.
   if (!-d $homedir && $config{create_syshomedir}) {
      if (mkdir($homedir, 0700)) {
         if ($> == 0) {
            my $firstusergroup = (split(/\s+/,$ugid))[0];
            chown($uuid, $firstusergroup, $homedir);
            writelog("create homedir - $homedir, uid=$uuid, gid=$firstusergroup");
         } else {
            writelog("create homedir - $homedir");
         }
      } else {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $homedir ($!)");
      }
   }

   # search old alive session and deletes old expired sessionids
   my ($activelastminute, $activelastfiveminute, $activelastfifteenminute) = ();
   ($thissession, $activelastminute, $activelastfiveminute, $activelastfifteenminute)
      = search_clean_oldsessions($loginname, $default_logindomain, $uuid, cookie("ow-sessionkey-$domain-$user"));

   # name the new sessionid
   if ($thissession eq "") {
      my $n = rand();
      # cover bug if rand return too small value
      for (1..5) {
         last if $n >= 0.1;
         $n *= 10;
      }
      $thissession = $loginname."*".$default_logindomain."-session-$n";
   }

   $thissession =~ s#\.\.+##g;  # remove ..

   if ($thissession =~ /^([\w\.\-\%\@]+\*[\w\.\-]*\-session\-0\.\d+)$/) {
      local $1;          # fix perl $1 taintness propagation bug
      $thissession = $1; # untaint
   } else {
      my $error = $lang_err{session_illegal_chars};
      $error =~ s#\@\@\@THISSESSION\@\@\@#$thissession#;
      openwebmailerror(__FILE__, __LINE__, $error);
   }

   writelog("login - $thissession - active=$activelastminute,$activelastfiveminute,$activelastfifteenminute");

   # set umask, switch to uuid:mailgid if script is setuid root.
   umask(0077);
   if ($> == 0) {
      my $mailgid = getgrnam('mail'); # for better compatibility with other mail progs
      ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
      if ( $) !~ m/\b$mailgid\b/) {    # group mail doesn't exist?
         my $error = $lang_err{setgid_failed};
         $error =~ s#\@\@\@MAILGID\@\@\@#$mailgid#;
         openwebmailerror(__FILE__, __LINE__, $error);
      }
   }

   # locate existing .openwebmail
   find_and_move_dotdir($syshomedir, $owuserdir) if (!-d dotpath('/'));

   # get user release date
   my $user_releasedate = read_releasedatefile();

   # create folderdir if it doesn't exist
   my $folderdir = "$homedir/$config{homedirfolderdirname}";
   if (! -d $folderdir ) {
      if (mkdir ($folderdir, 0700)) {
         writelog("create folderdir - $folderdir, euid=$>, egid=$)");
      } else {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $folderdir ($!)");
      }
      upgrade_20021218($user_releasedate);
   }

   # create dirs under ~/.openwebmail/
   check_and_create_dotdir(dotpath('/'));

   # create system spool file /var/mail/xxxx
   my $spoolfile = ow::tool::untaint((get_folderpath_folderdb($user, 'INBOX'))[0]);
   if ( !-f "$spoolfile" ) {
      sysopen(F, $spoolfile, O_WRONLY|O_APPEND|O_CREAT, 0600) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $spoolfile! ($!)");
      close(F);
      chown($uuid, (split(/\s+/,$ugid))[0], $spoolfile) if ($> == 0);
   }

   # create session key
   my $sessionkey;
   if ( -f "$config{ow_sessionsdir}/$thissession" ) {      # continue an old session?
      $sessionkey = cookie("ow-sessionkey-$domain-$user");
   } else {                                                # a brand new session
      $sessionkey = crypt(rand(),'OW');
   }

   # create sessionid file
   sysopen(SESSION, "$config{ow_sessionsdir}/$thissession", O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $config{ow_sessionsdir}/$thissession! ($!)");
   print SESSION $sessionkey, "\n";
   print SESSION $clientip, "\n";
   print SESSION join("\@\@\@", $domain, $user, $userrealname, $uuid, $ugid, $homedir), "\n";
   close(SESSION);
   writehistory("login - $thissession");

   # symbolic link ~/mbox to ~/mail/saved-messages if ~/mbox is not spoolfile
   my $homedirmbox = "$homedir/mbox";
   my $savedfolder = "$folderdir/saved-messages";
   if ( $config{symboliclink_mbox}
        && -e $homedirmbox
        && $spoolfile ne $homedirmbox
        && ((lstat($homedirmbox))[2] & 07770000) eq 0100000) { # ~/mbox is regular file
      if (ow::filelock::lock($savedfolder, LOCK_EX|LOCK_NB)) {
         writelog("symlink mbox - $homedirmbox -> $savedfolder");

         if (sysopen(F, $savedfolder, O_WRONLY|O_APPEND|O_CREAT)) {
            my $homedirmboxold = "$homedir/mbox.old.$$";
            seek(F, 0, 2);	# seek to end;
            rename($homedirmbox, $homedirmboxold);
            symlink($savedfolder, $homedirmbox);
            if (sysopen(T, $homedirmboxold, O_RDONLY)) {
               print F while(<T>);
               close(T);
               unlink($homedirmboxold);
            }
            close(F);
         }
         ow::filelock::lock($savedfolder, LOCK_UN);
      }
   }

   # check if releaseupgrade() is required
   if ($user_releasedate ne $config{releasedate}) {
      upgrade_all($user_releasedate) if ($user_releasedate ne "");
      update_releasedatefile();
   }
   update_openwebmailrc($user_releasedate);

   # remove stale folder db
   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);
   del_staledb($user, \@validfolders);

   # create authpop3 book if auth_pop3.pl or auth_ldap_vpopmail.pl
   if ($config{auth_module} eq 'auth_pop3.pl' || $config{auth_module} eq 'auth_ldap_vpopmail.pl') {
      update_authpop3book(dotpath('authpop3.book'), $domain, $user, $password);
   }

   # redirect page to openwebmail main/calendar/webdisk/prefs
   my $refreshurl = refreshurl_after_login(param('action'));
   if ( ! -f dotpath('openwebmailrc')) {
      $refreshurl = "$config{ow_cgiurl}/openwebmail-prefs.pl?sessionid=$thissession&action=userfirsttime";
   }
   if ( !$config{stay_ssl_afterlogin} && ($ENV{HTTPS} =~ /on/i || $ENV{SERVER_PORT} == 443)) {
      $refreshurl = "http://$ENV{HTTP_HOST}$refreshurl" if ($refreshurl !~ s#^https?://#http://#i);
   }

   my $prefscharset = (ow::lang::localeinfo($prefs{locale}))[6];
   my @header       = (-Charset=>$prefscharset);
   my @cookies      = ();

   # cookie for autologin switch, expired until 1 month later
   my $autologin = param('autologin') || 0;
   if ($autologin && matchlist_fromhead('allowed_autologinip', $clientip)) {
      $autologin = autologin_add();
   } else {
      autologin_rm();
      $autologin = 0;
   }
   push(@cookies, cookie(
                           -name    => 'ow-autologin',
                           -value   => $autologin,
                           -path    => '/',
                           -expires => '+1M',
                        ));

   # if autologin, then expire in 1 week, else expire at browser close
   my @expire = ();
   @expire    = (-expires => '+7d',) if ($autologin);

   # cookie for openwebmail to verify session
   push(@cookies, cookie(
                           -name  => "ow-sessionkey-$domain-$user",
                           -value => $sessionkey,
                           -path  => '/',
                           @expire
                        ));

   # cookie for ssl session, expires if browser closed
   push(@cookies, cookie(
                           -name  => 'ow-ssl',
                           -value => (
                                        (defined $ENV{HTTPS} && $ENV{HTTPS} =~ /on/i) ||
                                        (defined $ENV{SERVER_PORT} && $ENV{SERVER_PORT} == 443) || 0
                                     ),
                           @expire
                        ));

   # cookie for autologin and other apps to find openwebmail loginname
   # and default_logindomain. Expires 1 month later
   push(@cookies, cookie(
                           -name    => 'ow-loginname',
                           -value   => $loginname,
                           -path    => '/',
                           -expires => '+1M',
                        ));

   push(@cookies, cookie(
                           -name    => 'ow-default_logindomain',
                           -value   => $default_logindomain,
                           -path    => '/',
                           -expires => '+1M',
                        ));

   # cookie for httpcompress switch, expires 1 month later
   push(@cookies, cookie(
                           -name    => 'ow-httpcompress',
                           -value   => param('httpcompress') || 0,
                           -path    => '/',
                           -expires => '+1M',
                        ));
   push(@header, -cookie=>\@cookies);

   # in case the javascript refresh does not work
   push(@header, -refresh=>"2;URL=$refreshurl");

   delete $ENV{HTTP_ACCEPT_ENCODING} unless param('httpcompress');

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("login_pass.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template         => get_header($config{header_template_file}),

                      # login_pass.tmpl
                      url_html                => $config{ow_htmlurl},
                      url_refresh             => $refreshurl,
                      enable_about            => $config{enable_about},
                      about_info_software     => $config{about_info_software},
                      programname             => $config{name},
                      programversion          => $config{version},
                      programrevision         => $config{revision},
                      programreleasedate      => $config{releasedate},
                      session_count_display   => $config{session_count_display},
                      activelastminute        => $activelastminute,
                      activelastfiveminute    => $activelastfiveminute,
                      activelastfifteenminute => $activelastfifteenminute,

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint(\@header, [$template->output]);
}

sub loginfailed {
   my $message = shift;

   # delay response
   sleep $config{loginerrordelay};

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("login_fail.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );
   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # loginfailed.tmpl
                      url_start       => $config{start_url},
                      message         => $message,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
   return 0;
}

sub ip2hostname {
   my $ip = shift;
   my $hostname;
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" };          # NB: \n required
      alarm 10;                                          # timeout 10sec
      $hostname = gethostbyaddr(inet_aton($ip),AF_INET); # function provided by Socket.pm
      alarm 0;
   };
   return($ip) if ($@);	                                 # eval error, it means timeout
   return($hostname);
}

sub autologin {
   # auto login with cgi parm or cookie
   $loginname = param('loginname') || cookie('ow-loginname');
   $loginname =~ s#\s##g;
   $default_logindomain = safedomainname(param('logindomain') || cookie('ow-default_logindomain'));
   return loginmenu() if ($loginname eq '');

   ($logindomain, $loginuser) = login_name2domainuser($loginname, $default_logindomain);
   if (!is_localuser("$loginuser\@$logindomain") && -f "$config{ow_sitesconfdir}/$logindomain") {
      read_owconf(\%config, \%config_raw, "$config{ow_sitesconfdir}/$logindomain");
   }
   ow::auth::load($config{auth_module});

   ($domain, $user, $userrealname, $uuid, $ugid, $homedir) = get_domain_user_userinfo($logindomain, $loginuser);

   if ($user eq ''
       || ($uuid == 0 && !matchlist_fromhead('allowed_rootloginip', ow::tool::clientip()))
       || cookie("ow-sessionkey-$domain-$user") eq '') {
      return loginmenu();
   }

   my $userconf = "$config{ow_usersconfdir}/$user";
   $userconf    = "$config{ow_usersconfdir}/$domain/$user" if ($config{auth_withdomain});
   read_owconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   my $owuserdir = ow::tool::untaint("$config{ow_usersdir}/".($config{auth_withdomain}?"$domain/$user":$user));
   $homedir = $owuserdir if ( !$config{use_syshomedir} );
   return loginmenu() if (!autologin_check());	# db won't be created if it doesn't exist as euid has not been switched

   # load user prefs for search_clean_oldsessions, it  will check $prefs{sessiontimeout}
   %prefs = readprefs();
   $thissession = (search_clean_oldsessions($loginname, $default_logindomain, $uuid, cookie("ow-sessionkey-$domain-$user")))[0];
   $thissession =~ s#\.\.+##g;
   return loginmenu() if ($thissession !~ m/^([\w\.\-\%\@]+\*[\w\.\-]*\-session\-0\.\d+)$/);

   # redirect page to openwebmail main/calendar/webdisk
   my $refreshurl = refreshurl_after_login(param('action'));
   if ( !$config{stay_ssl_afterlogin} && ($ENV{HTTPS} =~ /on/i || $ENV{SERVER_PORT} == 443)) {
      $refreshurl="http://$ENV{HTTP_HOST}$refreshurl" if ($refreshurl !~ s#^https?://#http://#i);
   }
   print redirect(-location => $refreshurl);
}

sub refreshurl_after_login {
   my $action = shift;
   $action = 'listmessages_afterlogin' if (defined $action && $action eq 'listmessages');

   my $validaction = '';

   foreach (@actions) {
      my $enable = $config{$action_redirect{$_}->[1]};
      if (defined $action && $action eq $_) {
         $validaction = $_ if ($enable);
         last;
      }
   }

   if ($validaction eq '') {
      foreach (@actions) {
         my $enable = $config{$action_redirect{$_}->[1]};
         if ($enable) {
           $validaction = $_;
           last;
         }
      }
   }

   if ($validaction eq '') {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{all_module_disabled}, $lang_err{access_denied}");
   }

   my $script     = $action_redirect{$validaction}->[2];
   my @parms      = @{$action_redirect{$validaction}->[3]};
   my $refreshurl = "$config{ow_cgiurl}/$script?sessionid=$thissession&action=$validaction";
   foreach my $parm ( @parms ) {
      if (param($parm)) {
         $refreshurl .= '&' . $parm . '=' . ow::tool::escapeURL(param($parm));
      }
   }
   return $refreshurl;
}

sub search_clean_oldsessions {
   # try to find old session that is still valid for the
   # same user cookie and delete expired session files
   my ($loginname, $default_logindomain, $owner_uid, $client_sessionkey) = @_;
   my $oldsessionid = "";
   my @sessioncount = (0,0,0); # active sessions in 1, 5, 15 minutes
   my @delfiles;

   opendir(D, $config{ow_sessionsdir}) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $config{ow_sessionsdir}! ($!)");
      my @sessfiles = readdir(D);
   closedir(D);

   my $t = time();
   my $clientip = ow::tool::clientip();
   foreach my $sessfile (@sessfiles) {
      next if ($sessfile !~ /^([\w\.\-\%\@]+)\*([\w\.\-]*)\-session\-(0\.\d+)(-.*)?$/);

      my ($sess_loginname, $sess_default_logindomain, $serial, $misc) = ($1, $2, $3, $4); # param from sessfile
      my $modifyage = $t-(stat("$config{ow_sessionsdir}/$sessfile"))[9];

      if ($loginname eq $sess_loginname && $default_logindomain eq $sess_default_logindomain) {
         # remove user old session if timeout
         if ( $modifyage > $prefs{sessiontimeout} * 60 ) {
            push(@delfiles, $sessfile);
         } elsif ($misc eq '') {
            # this is a session info file
            my ($sessionkey, $ip, $userinfo) = sessioninfo($sessfile);
            if ($client_sessionkey ne ''
                && $client_sessionkey eq $sessionkey
                && $clientip eq $ip
                && (stat("$config{ow_sessionsdir}/$sessfile"))[4] == $owner_uid ) {
               $oldsessionid = $sessfile;
            } elsif (!$config{session_multilogin}) {
               # remove old session of this user
               push(@delfiles, $sessfile);
            }
         }
      } else {
         # remove old session of other user if more than 1 day
         push(@delfiles, $sessfile) if ( $modifyage > 86400 );
      }

      if (defined $misc && $misc eq '') {
         $sessioncount[0]++ if ($modifyage <= 60);
         $sessioncount[1]++ if ($modifyage <= 300);
         $sessioncount[2]++ if ($modifyage <= 900);
      }
   }

   foreach my $sessfile (@delfiles) {
      writelog("session cleanup - $sessfile");
      unlink ow::tool::untaint("$config{ow_sessionsdir}/$sessfile");
   }

   # clear stale file for ow::tool::mktmpdir ow::tool:mktmpfile
   @delfiles = ();
   if (opendir(D, "/tmp")) {
      my @tmpfiles = readdir(D);
      closedir(D);
      foreach my $tmpfile (@tmpfiles) {
         next if ($tmpfile !~ /^\.ow\./);
         push(@delfiles, ow::tool::untaint("/tmp/$tmpfile")) if ($t-(stat("/tmp/$tmpfile"))[9]>3600);
      }
      if ($#delfiles >= 0) {
         # TODO: rewrite this in perl to make portable and provide error checking
         my $rmbin = ow::tool::findbin("rm");
         system($rmbin, "-Rf", @delfiles);
      }
   }

   return($oldsessionid, @sessioncount);
}
