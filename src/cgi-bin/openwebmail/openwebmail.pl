#!/usr/bin/suidperl -T
#################################################################
#                                                               #
# Open WebMail - Provides a web interface to user mailboxes     #
#                                                               #
# Copyright (C) 2001-2002                                       #
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
if ( $ENV{'SCRIPT_FILENAME'} =~ m!^(.*?)/[\w\d\-\.]+\.pl! || $0 =~ m!^(.*?)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\n\$SCRIPT_DIR not set in CGI script!\n"; exit 0; }
push (@INC, $SCRIPT_DIR, ".");

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use Socket;
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

require "ow-shared.pl";
require "filelock.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir);

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy
use vars qw($pop3_authserver);	# defined in auth_pop3.pl

readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");

# setuid is required if mails is located in user's dir
if ( $>!=0 && ($config{'use_homedirspools'}||$config{'use_homedirfolders'}) ) {
   print "Content-type: text/html\n\n'$0' must setuid to root"; exit 0;
}

# check & create mapping table for solar/lunar, b2g, g2b convertion
if ( ! -f "$config{'ow_etcdir'}/lunar$config{'dbm_ext'}" ||
     ! -f "$config{'ow_etcdir'}/g2b$config{'dbm_ext'}" ||
     ! -f "$config{'ow_etcdir'}/b2g$config{'dbm_ext'}" ) {
   print "Content-type: text/html\n\nPlease execute  '$config{'ow_cgidir'}/openwebmail-tool.pl --init' on server first!"; exit 0;
}

# validate allowed_serverdomain
my $httphost=lc($ENV{'HTTP_HOST'}); $httphost=~s/:\d+$//;	# remove port number
if (! is_serverdomain_allowed($httphost) ) {
   print "Content-type: text/html\n\nService is not available for domain  ' $httphost '";
   exit 0;
}

if ( ($config{'logfile'} ne 'no') ) {
   my $mailgid=getgrnam('mail');
   my ($fmode, $fuid, $fgid) = (stat($config{'logfile'}))[2,4,5];
   if ( !($fmode & 0100000) ) {
      open (LOGFILE,">>$config{'logfile'}") or
         openwebmailerror("Can't open log file $config{'logfile'}!");
      close(LOGFILE);
   }
   chmod(0660, $config{'logfile'}) if (($fmode&0660)!=0660);
   chown($>, $mailgid, $config{'logfile'}) if ($fuid!=$>||$fgid!=$mailgid);
}

####################### MAIN ##########################

if ( param("loginname") && param("password") ) {
   $loginname=param("loginname");
   $loginname.='@'.param("logindomain") if ($loginname!~/\@/ && param("logindomain") ne "");
   if ($config{'case_insensitive_login'}) {
      $loginname=lc($loginname);
   } else {
      $loginname=$1.'@'.lc($2) if ($loginname=~/^(.+)\@(.+)$/);
   }

   my $siteconf;
   if ($loginname=~/\@(.+)$/) {
       my $domain=$1;
       if (! is_serverdomain_allowed($domain)) {
          openwebmailerror("Service is not available for domain  ' $domain '");
       }
       $siteconf="$config{'ow_etcdir'}/sites.conf/$domain";
   } else {
       my $httphost=lc($ENV{'HTTP_HOST'}); $httphost=~s/:\d+$//;	# remove port number
       $siteconf="$config{'ow_etcdir'}/sites.conf/$httphost";
   }
   readconf(\%config, \%config_raw, "$siteconf") if ( -f "$siteconf");

   require $config{'auth_module'} or
      openwebmailerror("Can't open authentication module $config{'auth_module'}");

   if ( ($config{'logfile'} ne 'no') ) {
      my $mailgid=getgrnam('mail');
      my ($fmode, $fuid, $fgid) = (stat($config{'logfile'}))[2,4,5];
      if ( !($fmode & 0100000) ) {
         open (LOGFILE,">>$config{'logfile'}") or
            openwebmailerror("Can't open log file $config{'logfile'}!");
         close(LOGFILE);
      }
      chmod(0660, $config{'logfile'}) if (($fmode&0660)!=0660);
      chown($>, $mailgid, $config{'logfile'}) if ($fuid!=$>||$fgid!=$mailgid);
   }

   my $virtname=$config{'virtusertable'};
   $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   update_virtusertable("$config{'ow_etcdir'}/$virtname", $config{'virtusertable'});

   %prefs = %{&readprefs};
   %style = %{&readstyle};
   ($prefs{'language'} =~ /^([\w\d\._]+)$/) && ($prefs{'language'} = $1);
   require "etc/lang/$prefs{'language'}";

   login();

} else {            # no action has been taken, display login page
   my $httphost=lc($ENV{'HTTP_HOST'}); $httphost=~s/:\d+$//;	# remove port number
   my $siteconf="$config{'ow_etcdir'}/sites.conf/$httphost";
   readconf(\%config, \%config_raw, "$siteconf") if ( -f "$siteconf");

   %prefs = %{&readprefs};
   %style = %{&readstyle};
   ($prefs{'language'} =~ /^([\w\d\._]+)$/) && ($prefs{'language'} = $1);
   require "etc/lang/$prefs{'language'}";

   loginmenu();
}

exit 0;
##################### END MAIN ########################

##################### LOGINMENU ######################
sub loginmenu {
   my $html='';
   my $temphtml;

   $html=readtemplate("login.template");
   $html = applystyle($html);

   printheader(),

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail.pl",
                         -name=>'login');
   if (defined(param('action'))) {
      $temphtml .= hidden("action", param('action'));
      $temphtml .= hidden("to", param('to')) if (defined(param('to')));
      $temphtml .= hidden("subject", param('subject')) if (defined(param('subject')));
   }
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   if (cookie("openwebmail-rememberme")) {
      $temphtml = textfield(-name=>'loginname',
                            -default=>cookie("openwebmail-loginname"),
                            -size=>'12',
                            -onChange=>'focuspwd()',
                            -override=>'1');
   } else {
      $temphtml = textfield(-name=>'loginname',
                            -default=>'' ,
                            -size=>'12',
                            -onChange=>'focuspwd()',
                            -override=>'1');
   }
   $html =~ s/\@\@\@LOGINNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'password',
                              -default=>'',
                              -size=>'12',
                              -onChange=>'focusloginbutton()',
                              -override=>'1');
   $html =~ s/\@\@\@PASSWORDFIELD\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'rememberme',
                        -value=>'1',
                        -checked=>cookie("openwebmail-rememberme")||0,
                        -label=>'');
   $html =~ s/\@\@\@REMEMBERMECHECKBOX\@\@\@/$temphtml/;

   if ( $#{$config{'domainnames'}} >0 && $config{'enable_domainselectmenu'} ) {
      $temphtml = popup_menu(-name=>'logindomain',
                             -values=>[@{$config{'domainnames'}}] );
      $html =~ s/\@\@\@DOMAINMENU\@\@\@/$temphtml/;
      $html =~ s/\@\@\@DOMAINSTART\@\@\@//;
      $html =~ s/\@\@\@DOMAINEND\@\@\@//;
   } else {
      $html =~ s/\@\@\@DOMAINSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@DOMAINEND\@\@\@/-->/;
   }

   $temphtml = submit(-name =>"loginbutton",
		      -value=>"$lang_text{'login'}" );

   $html =~ s/\@\@\@LOGINBUTTON\@\@\@/$temphtml/;
   $temphtml = reset("$lang_text{'clear'}");
   $html =~ s/\@\@\@CLEARBUTTON\@\@\@/$temphtml/;
   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;
   print $html;
}
################### END LOGINMENU ####################

####################### LOGIN ########################
sub login {
   my $password = param("password") || '';

   $loginname =~ /^(.*)$/; # accept any characters for loginname/pass auth info
   $loginname = $1;
   $password =~ /^(.*)$/;
   $password = $1;

   ($loginname, $domain, $user, $userrealname, $uuid, $ugid, $homedir)
					=get_domain_user_userinfo($loginname);

   ($user =~ /^(.+)$/) && ($user = $1);		# untaint...
   ($uuid =~ /^(.+)$/) && ($uuid = $1);
   ($ugid =~ /^(.+)$/) && ($ugid = $1);
   ($homedir =~ /^(.+)$/) && ($homedir = $1);

   if ($user eq "") {
      sleep $config{'loginerrordelay'};	# delayed response
      openwebmailerror("$lang_err{'user_not_exist'}");
   }
   if (! $config{'enable_rootlogin'}) {
      if ($user eq 'root' || $uuid==0) {
         sleep $config{'loginerrordelay'};	# delayed response
         writelog("login error - root login attempt");
         openwebmailerror ("$lang_err{'norootlogin'}");
      }
   }

   my $errorcode;
   if ($config{'auth_withdomain'}) {
      $errorcode=check_userpassword("$user\@$domain", $password);
   } else {
      $errorcode=check_userpassword($user, $password);
   }
   if ( $errorcode==0 ) {
      my $userconf="$config{'ow_etcdir'}/users.conf/$user";
      $userconf .= "\@$domain" if ($config{'auth_withdomain'});
      readconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

      my $clientip=get_clientip();
      # validate client ip
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
            openwebmailerror($lang_err{'disallowed_client'}." ( ip:$clientip )");
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
            openwebmailerror($lang_err{'disallowed_client'}." ( hotname:$clientdomain )");
         }
      }

      # search old alive session and deletes old expired sessionids
      $thissession = search_and_cleanoldsessions(cookie("$user-sessionid"));
      if ($thissession eq "") {
         $thissession = $loginname. "-session-" . rand(); # name the sessionid
      }
      writelog("login - $thissession");
      ($thissession =~ /^(.+)$/) && ($thissession = $1);  # untaint

      # create the user's home directory if necessary.
      # this must be done before changing to the user's uid.
      if ( $config{'create_homedir'} && ! -d "$homedir" ) {
         if (mkdir ("$homedir", oct(700)) and chown($uuid, $ugid, $homedir)) {
            writelog("mkdir - $homedir, uid=$uuid, gid=$ugid");
         } else {
            openwebmailerror("$lang_err{'cant_create_dir'} $homedir");
         }
      }

      if ( $config{'use_homedirspools'} || $config{'use_homedirfolders'} ) {
         my $mailgid=getgrnam('mail');
         set_euid_egid_umask($uuid, $mailgid, 0077);
         if ( $) != $mailgid) {	# egid must be mail since this is a mail program...
            openwebmailerror("Set effective gid to mail($mailgid) failed!");
         }
      }

      if ( $config{'use_homedirfolders'} ) {
         $folderdir = "$homedir/$config{'homedirfolderdirname'}";
      } else {
         $folderdir = "$config{'ow_etcdir'}/users/$user";
         $folderdir .= "\@$domain" if ($config{'auth_withdomain'});
      }
      ($folderdir =~ /^(.+)$/) && ($folderdir = $1);	# untaint

      # create folderdir if it doesn't exist
      if (! -d "$folderdir" ) {
         if (mkdir ("$folderdir", oct(700))) {
            writelog("mkdir - $folderdir, euid=$>, egid=$)");
         } else {
            openwebmailerror("$lang_err{'cant_create_dir'} $folderdir");
         }
      }

      # create system spool file /var/mail/xxxx
      my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
      if ( ! -f "$spoolfile" ) {
         ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); # untaint ...
         open (F, ">>$spoolfile"); close(F);
         chown($uuid, $ugid, $spoolfile);
      }

      # create session file
      my $sessioncookie_value;
      if ( -f "$config{'ow_etcdir'}/sessions/$thissession" ) { # continue an old session?
         $sessioncookie_value = cookie("$user-sessionid");
      } else {						       # a brand new sesion?
         $sessioncookie_value = crypt(rand(),'OW');
      }
      open (SESSION, "> $config{'ow_etcdir'}/sessions/$thissession") or # create sessionid
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$thissession!");
      print SESSION $sessioncookie_value, "\n";
      print SESSION get_clientip(), "\n";
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

      # check ~/mail/.release.date to see if releaseupgrade() is required
      my $user_releasedate;
      my $rc_upgrade=0;	# .openwebmailrc upgrade will be requested if 1

      if ( -f "$folderdir/.release.date" ) {
         open(D, "$folderdir/.release.date");
         $user_releasedate=<D>;
         chomp($user_releasedate);
         close(D);
      }
      if ($user_releasedate ne $config{'releasedate'}) {
         $rc_upgrade=releaseupgrade($folderdir, $user_releasedate);
         open(D, ">$folderdir/.release.date");
         print D $config{'releasedate'};
         close(D);
      }

      # create .authpop3.book
      if (defined($pop3_authserver)) {
         my $authpop3book="$folderdir/.authpop3.book";
         ($authpop3book =~ /^(.+)$/) && ($authpop3book = $1);  # untaint ...

         if ($config{'getmail_from_pop3_authserver'}) {
            my ($pop3host, $pop3user, $pop3pass, $pop3lastid, $pop3del, $enable);
            my $login=$user;
            $login .= "\@$domain" if ($config{'auth_withdomain'});

            if ( -f "$authpop3book") {
               open(F, "$authpop3book");
               $_=<F>; chomp;
               ($pop3host,$pop3user,$pop3pass,$pop3lastid,$pop3del,$enable)=split(/\@\@\@/, $_);
               close(F);
            }

            if ($pop3host ne $pop3_authserver ||
                $pop3user ne $login ||
                $pop3pass ne $password) {
               if ($pop3host ne $pop3_authserver || $pop3user ne $login) {
                  $pop3lastid="none";
                  $pop3del=$config{'delpop3mail_by_default'};
                  $enable=1;
               }
               open(F, ">$authpop3book");
               print F "$pop3_authserver\@\@\@$login\@\@\@$password\@\@\@$pop3lastid\@\@\@$pop3del\@\@\@$enable";
               close(F);
            }
         } else {
            unlink("$authpop3book");
         }
      }

      # set cookie in header and redirect page to openwebmail-main
      my $url;
      if ( ! -f "$folderdir/.openwebmailrc" ) {
         $url="$config{'ow_cgiurl'}/openwebmail-prefs.pl?sessionid=$thissession&action=firsttimeuser";
      } elsif ( $rc_upgrade ) {
         $url="$config{'ow_cgiurl'}/openwebmail-prefs.pl?sessionid=$thissession&action=editprefs";
      } elsif ( param('action') eq 'composemessage' ) {
         my $to=param("to");
         my $subject=param("subject");
         $url="$config{'ow_cgiurl'}/openwebmail-send.pl?sessionid=$thissession&action=composemessage&to=$to&subject=$subject";
      } elsif ( param('action') eq 'calyear' || param('action') eq 'calmonth' ||
                param('action') eq 'calweek' || param('action') eq 'calday' ) {
         my $action=param('action');
         $url="$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&action=$action";
      } else {
         $url="$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&action=displayheaders_afterlogin";
      }

      if ( ($ENV{'HTTPS'}=~/on/i || $ENV{'SERVER_PORT'}==443) && !$config{'stay_ssl_afterlogin'}) {
         $url="http://$ENV{'HTTP_HOST'}$url" if ($url !~ m!https?://! );
      }

      my @headers=();
      push(@headers, -pragma=>'no-cache');

      # cookie for openwebmail to verify session, expired if browser closed
      my $cookie1 = cookie( -name  => "$user-sessionid",
                            -value => "$sessioncookie_value",
                            -path  => '/');
      # cookie for other ap to find openwebmail loginname, expired until 1 month later
      my $cookie2 = cookie( -name  => "openwebmail-loginname",
                            -value => "$loginname",
                            -path  => '/',
                            -expires => "+1M" );
      # cookie for remember loginname switch, expired until 1 month later
      my $cookie3 = cookie( -name  => "openwebmail-rememberme",
                            -value => param("rememberme")||'',
                            -path  => '/',
                            -expires => "+1M" );
      # cookie for ssl session, expired if not same session
      my $cookie4 = cookie( -name  => "openwebmail-ssl",
                            -value => ($ENV{'HTTPS'}=~/on/i ||
                                       $ENV{'SERVER_PORT'}==443 ||
                                       0),
                            -path  => '/');

      push(@headers, -cookie=>[$cookie1, $cookie2, $cookie3, $cookie4]);
      push(@headers, -charset=>$prefs{'charset'}) if ($CGI::VERSION>=2.57);

      # load page with Refresh header only if not MSIE on Mac
      my $refresh;
      if ($ENV{'HTTP_USER_AGENT'} !~ /MSIE.+Mac/) {
         # push(@headers, -Refresh=>"0;URL=$url");
         $refresh=qq|<meta http-equiv="refresh" content="0;URL=$url">|;
      }

      print header(@headers);

      # display copyright. Don't touch it, please.
      print	qq|<html>\n|,
		qq|<head><title>Copyright</title>$refresh</head>\n|,
		qq|<body bgcolor="#ffffff" background="$prefs{'bgurl'}">\n|,
		qq|<style type="text/css"><!--\n|,
		qq|body { background-image: url($prefs{'bgurl'}); background-repeat: no-repeat; }\n|,
		qq|--></style>\n|,
                qq|<center><br><br><br>\n|,
                qq|<a href="$url" title="click to next page..." style="text-decoration: none">|,
		qq|<font color="#888888"> &nbsp; Loading . . .</font></a>\n|,
		qq|<br><br><br>\n\n|.
                qq|<a href="http://openwebmail.org/" title="click to home of $config{'name'}" style="text-decoration: none">\n|,
		qq|<font color="#cccccc" face="arial,helvetica,sans-serif" size=-1>\n|,
                qq|$config{'name'} $config{'version'} $config{'releasedate'}<br><br>\n|,
		qq|Copyright (C) 2001-2002<br>\n|,
		qq|Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric, Thomas Chung, Dattola Filippo<br><br>\n|,
		qq|Copyright (C) 2000<br>\n|,
		qq|Ernie Miller  (original GPL project: Neomail)<br><br>\n|,
		qq|</font></a>\n\n|,
                qq|<a href="http://openwebmail.org/openwebmail/download/doc/copyright.txt" title="click to see GPL version 2 licence" style="text-decoration: none">\n|,
		qq|<font color="#cccccc" face="arial,helvetica,sans-serif" size=-1>\n|,
		qq|This program is free software; you can redistribute it and/or modify<br>\n|,
		qq|it under the terms of the version 2 of GNU General Public License<br>\n|,
		qq|as published by the Free Software Foundation<br><br>\n|,
		qq|This program is distributed in the hope that it will be useful,<br>\n|,
		qq|but WITHOUT ANY WARRANTY; without even the implied warranty of<br>\n|,
		qq|MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.<br>\n|,
		qq|See the GNU General Public License for more details.<br><br>\n|,
		qq|Removal or change of this copyright is prohibited.\n|,
		qq|</font></a>\n\n|;

      # load page with java script if MSIE on Mac
      if ($ENV{'HTTP_USER_AGENT'}=~/MSIE.+Mac/) {
         print  qq|<script language="JavaScript">\n<!--\n|,
		qq|setTimeout("window.open('$url','_self')", 1*1000);\n|,
		qq|//-->\n</script>\n|;
      }

      print     qq|</center></body></html>\n|;
      exit(0);

   } else { # Password is INCORRECT
      my $errormsg;
      if ($errorcode==-1) {
         $errormsg=$lang_err{'func_notsupported'};
      } elsif ($errorcode==-2) {
         $errormsg=$lang_err{'param_fmterr'};
      } elsif ($errorcode==-3) {
         $errormsg=$lang_err{'auth_syserr'};
      } elsif ($errorcode==-4) {
         $errormsg=$lang_err{'pwd_incorrect'};
      } else {
         $errormsg="Unknow error code $errorcode";
      }

      writelog("login error - $errorcode - loginname=$loginname");

      if ( $config{'use_homedirspools'} || $config{'use_homedirfolders'} ) {
         my $mailgid=getgrnam('mail');
         set_euid_egid_umask($uuid, $mailgid, 0077);
      }

      if ( $config{'use_homedirfolders'} ) {
         $folderdir = "$homedir/$config{'homedirfolderdirname'}";
      } else {
         $folderdir = "$config{'ow_etcdir'}/users/$user";
         $folderdir .= "\@$domain" if ($config{'auth_withdomain'});
      }

      if ( -d $folderdir) {
         if ( ! -f "$folderdir/.history.log" ) {
            open(HISTORYLOG, ">>$folderdir/.history.log");
            close(HISTORYLOG);
            chown($uuid, $ugid, "$folderdir/.history.log");
         }
         writehistory("login error - $errorcode - loginname=$loginname");
      }

      sleep $config{'loginerrordelay'};	# delayed response

      my $html=readtemplate("loginfailed.template");
      $html = applystyle($html);
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$errormsg/;

      printheader();
      print $html;
      printfooter(1);
      exit 0;
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
   my $oldcookie=$_[0];
   my $oldsessionid="";
   my $sessionid;
   my @delfiles;

   opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");
   while (defined($sessionid = readdir(SESSIONSDIR))) {
      if ($sessionid =~ /^(.+\-session\-0.*)$/) {
         $sessionid = $1;
         if ($sessionid =~ /^$loginname\-session\-0./) { # remove user old session if timeout
            if ( -M "$config{'ow_etcdir'}/sessions/$sessionid" > $prefs{'sessiontimeout'}/60/24 ) {
               writelog("session cleanup - $sessionid");
               push(@delfiles, "$config{'ow_etcdir'}/sessions/$sessionid");
            } else {	# remove user old session from same client
               open (SESSION, "$config{'ow_etcdir'}/sessions/$sessionid");
               my $cookie = <SESSION>; chomp $cookie;
               my $ip = <SESSION>; chomp $ip;
               close (SESSION);
               if ($ip eq get_clientip()) {
                  if ($cookie eq $oldcookie && $oldcookie ne "") {
                     $oldsessionid=$sessionid;
                  } else {
                     writelog("session cleanup - $sessionid");
                     push(@delfiles, "$config{'ow_etcdir'}/sessions/$sessionid");
                  }
               }
            }
         } else {	# remove others old session if more than 1 day
            if ( -M "$config{'ow_etcdir'}/sessions/$sessionid" > 1 ) {
               writelog("session cleanup - $sessionid");
               push(@delfiles, "$config{'ow_etcdir'}/sessions/$sessionid");
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
   my $rc_upgrade=0;
   my ($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE, $_REFERENCES, $_CHARSET)
       =(0,1,2,3,4,5,6,7,8,9);

   if ( $user_releasedate lt "20011101" ) {
      if ( -f "$folderdir/.filter.book" ) {
         $content="";
         filelock("$folderdir/.filter.book", LOCK_EX);
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
         filelock("$folderdir/.pop3.book", LOCK_EX);
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
            $content.="$pop3host\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3lastid\@\@\@$pop3del\@\@\@$enable\n";
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
            filelock("$folderdir/$book", LOCK_EX);
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
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir");
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

         filelock($folderfile, LOCK_SH);
         open (FOLDER, $folderfile);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
         dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

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
         dbmclose(%HDB);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
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

         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
         dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

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
         dbmclose(%HDB);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

         my $cachefile="$headerdb.cache";
         ($cachefile =~ /^(.+)$/) && ($cachefile = $1);  # untaint ...
         unlink($cachefile); # remove cache possiblely for old dbm
      }
      writehistory("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20020108.02");
      writelog("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20020108.02");
   }

   if ( $user_releasedate lt "20020601" ) {
      my $timeoffset=gettimeoffset();
      $timeoffset=~s/\+/-/ || $timeoffset=~s/\-/+/;	# switch +/-
      my (@validfolders, $folderusage);
      getfolders(\@validfolders, \$folderusage);

      foreach my $foldername (@validfolders) {
         my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldername);
         my (%HDB, @messageids, @attr);
         next if ( ! -f "$headerdb$config{'dbm_ext'}" || -z "$headerdb$config{'dbm_ext'}" );

         filelock($folderfile, LOCK_SH);
         open (FOLDER, $folderfile);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
         dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

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
               my $deliserial=delimiter2dateserial($delimiter, $config{'deliver_use_GMT'});
               if ($dateserial eq "" ||
                   ($deliserial ne "" && dateserial2daydiff($dateserial)-dateserial2daydiff($deliserial)>1) ) {
                  $dateserial=$deliserial; # use receiving time if sending time is newer than receiving time
               }
               $dateserial=gmtime2dateserial() if ($dateserial eq "");
               $attr[$_DATE]=$dateserial;
            } else {
               $attr[$_DATE]=add_dateserial_timeoffset($attr[$_DATE], $timeoffset);
            }
            $HDB{$id}=join('@@@', @attr);
         }
         dbmclose(%HDB);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
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

         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
         dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

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
         dbmclose(%HDB);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
      }
      writehistory("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20021111.02");
      writelog("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20021111.02");
   }

   if ( $user_releasedate lt "20021116" ) {
      $rc_upgrade=1;	# .openwebmailrc upgrade will be requested
   }

   return($rc_upgrade);
}
#################### END RELEASEUPGRADE ####################
