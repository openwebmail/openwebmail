#!/usr/bin/perl -T
#############################################################################
# Open WebMail - Provides a web interface to user mailboxes                 #
#                                                                           #
# Copyright (C) 2001-2002                                                   #
# Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric                 #
# Copyright (C) 2000                                                        #
# Ernie Miller  (original GPL project: Neomail)                             #
#                                                                           #
# This program is distributed under GNU General Public License              #
#############################################################################

local $SCRIPT_DIR="";
if ( $ENV{'SCRIPT_FILENAME'} =~ m!^(.*?)/[\w\d\-]+\.pl! || $0 =~ m!^(.*?)/[\w\d\-]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\n\$SCRIPT_DIR not set in CGI script!\n"; exit 0; }

use strict;
no strict 'vars';
use Fcntl qw(:DEFAULT :flock);
use Socket;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

$ENV{PATH} = ""; # no PATH should be needed
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0007); # make sure the openwebmail group can write

push (@INC, $SCRIPT_DIR, ".");
require "openwebmail-shared.pl";
require "filelock.pl";

local (%config, %config_raw);
local $thissession;
local ($loginname, $domain, $user, $userrealname, $uuid, $ugid, $homedir);
local (%prefs, %style);
local ($lang_charset, %lang_folders, %lang_sortlabels, %lang_text, %lang_err);
local $folderdir;

readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");

if ( $config{'logfile'} ne 'no' && ! -f $config{'logfile'} ) {
   my $mailgid=getgrnam('mail');
   open (LOGFILE,">>$config{'logfile'}") or 
      openwebmailerror("Can't open log file $config{'logfile'}!");
   close(LOGFILE);
   chmod(0660, $config{'logfile'});
   chown($>, $mailgid, $config{'logfile'});
}

# setuid is required if mails is located in user's dir
if ( $>!=0 && ($config{'use_homedirspools'}||$config{'use_homedirfolders'}) ) {
   print "Content-type: text/html\n\n'$0' must setuid to root"; exit 0;
}

%prefs = %{&readprefs};
%style = %{&readstyle};

($prefs{'language'} =~ /^([\w\d\._]+)$/) && ($prefs{'language'} = $1);
require "etc/lang/$prefs{'language'}";
$lang_charset ||= 'iso-8859-1';

####################### MAIN ##########################
if ( param("loginname") && param("password") ) {
   $loginname=param("loginname");
   my $siteconf;
   if ($loginname=~/\@(.+)$/) {
       $siteconf="$config{'ow_etcdir'}/sites.conf/$1";
   } else {
       $siteconf="$config{'ow_etcdir'}/sites.conf/$ENV{'HTTP_HOST'}";
   }
   readconf(\%config, \%config_raw, "$siteconf") if ( -f "$siteconf"); 

   require $config{'auth_module'} or
      openwebmailerror("Can't open authentication module $config{'auth_module'}");

   if ( ($config{'logfile'} ne 'no') && (! -f $config{'logfile'})  ) {
      my $mailgid=getgrnam('mail');
      open (LOGFILE,">>$config{'logfile'}") or 
         openwebmailerror("Can't open log file $config{'logfile'}!");
      close(LOGFILE);
      chmod(0660, $config{'logfile'});
      chown($>, $mailgid, $config{'logfile'});
   }

   update_virtusertable("$config{'ow_etcdir'}/virtusertable", $config{'virtusertable'});

   login();
} else {            # no action has been taken, display login page
   loginmenu();
}

exit 0;
##################### END MAIN ########################

##################### LOGINMENU ######################
sub loginmenu {
   printheader(),
   my $html='';
   my $temphtml;
   open (LOGIN, "$config{'ow_etcdir'}/templates/$prefs{'language'}/login.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/login.template!");
   while (<LOGIN>) {
      $html .= $_;
   }
   close (LOGIN);

   $html = applystyle($html);

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail.pl",
                         -name=>'login');
   $temphtml .= hidden("action","login");
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;
   $temphtml = textfield(-name=>'loginname',
                         -default=>'',
                         -size=>'10',
                         -onChange=>'focuspwd()', 
                         -override=>'1');
   $html =~ s/\@\@\@USERIDFIELD\@\@\@/$temphtml/;
   $temphtml = password_field(-name=>'password',
                              -default=>'',
                              -size=>'10',
                              -onChange=>'focuslogin()', 
                              -override=>'1');
   $html =~ s/\@\@\@PASSWORDFIELD\@\@\@/$temphtml/;
   $temphtml = submit(-name =>"login",
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
      if ($domain eq $ENV{'HTTP_HOST'}) {
         $errorcode=check_userpassword($user, $password);
      } else {
         sleep $config{'loginerrordelay'};	# delayed response
         openwebmailerror("$lang_err{'user_not_exist'}");
      }
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
            if ($token eq 'ALL' || $clientip=~/^\Q$token\E/) {
               $allowed=1; last;
            } elsif ($token eq 'NONE') {
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
            if ($token eq 'ALL') {
               $allowed=1; last;
            } elsif ($token eq 'NONE') {
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

      $thissession = $loginname. "-session-" . rand(); # name the sessionid
      writelog("login - $thissession");
      cleanupoldsessions(); # Deletes sessionids that have expired

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

      ($thissession =~ /^(.+)$/) && ($thissession = $1);  # untaint ...
      ($user =~ /^(.+)$/) && ($user = $1);
      ($uuid =~ /^(.+)$/) && ($uuid = $1);
      ($ugid =~ /^(.+)$/) && ($ugid = $1);
      ($homedir =~ /^(.+)$/) && ($homedir = $1);
      ($folderdir =~ /^(.+)$/) && ($folderdir = $1);

      # create folderdir if it doesn't exist
      if (! -d "$folderdir" ) {
         mkdir ("$folderdir", oct(700)) or
            openwebmailerror("$lang_err{'cant_create_dir'} $folderdir");
      }

      # create system spool file /var/mail/xxxx
      my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
      if ( ! -f "$spoolfile" ) {
         ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); # bypass taint check
         open (F, ">>$spoolfile"); close(F);
         chown($uuid, $ugid, $spoolfile);
      }

      # create session file
      my $setcookie = crypt(rand(),'OW');
      open (SESSION, "> $config{'ow_etcdir'}/sessions/$thissession") or # create sessionid
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$thissession!");
      print SESSION $setcookie;
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
      } elsif ( defined(param("to")) ) {
         my $to=param("to");
         my $subject=param("subject");
         $url="$config{'ow_cgiurl'}/openwebmail-send.pl?sessionid=$thissession&action=composemessage&to=$to&subject=$subject";
      } else {
         $url="$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&action=displayheaders_afterlogin";
      }

      my @headers=();
      push(@headers, -pragma=>'no-cache');
      my $cookie = cookie( -name    => "$user-sessionid",
                           -value   => "$setcookie",
                           -path    => '/' );
      push(@headers, -cookie=>$cookie);
      push(@headers, -charset=>$lang_charset) if ($CGI::VERSION>=2.57);
      push(@headers, -Refresh=>"0;URL=$url");
      print header(@headers);

      # display copyright. Don't touch it, please.
      print	qq|<html>\n|,
		qq|<head><title>Copyright</title></head>\n|,
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
		qq|Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric<br><br>\n|,
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
		qq|</font></a>\n\n|,
                qq|<script language="JavaScript">\n<!--\n|,
                qq|window.open('$url','_self')\n|,
                qq|//-->\n</script>\n|,
		qq|</center></body></html>\n|;
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

      my $html = '';
      printheader();
      open (LOGINFAILED, "$config{'ow_etcdir'}/templates/$prefs{'language'}/loginfailed.template") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/loginfailed.template!");
      while (<LOGINFAILED>) {
         $html .= $_;
      }
      close (LOGINFAILED);
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$errormsg/;

      $html = applystyle($html);
      
      print $html;
      printfooter();
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

################ CLEANUPOLDSESSIONS ##################
sub cleanupoldsessions {
   my $sessionid;
   opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");
   while (defined($sessionid = readdir(SESSIONSDIR))) {
      if ($sessionid =~ /^(.+\-session\-0.*)$/) {
         $sessionid = $1;
         if ( -M "$config{'ow_etcdir'}/sessions/$sessionid" > $config{'sessiontimeout'}/60/24 ) {
            writelog("session cleanup - $sessionid");
            unlink "$config{'ow_etcdir'}/sessions/$sessionid";
         }
      }
   }
   closedir (SESSIONSDIR);
}
############## END CLEANUPOLDSESSIONS ################

#################### RELEASEUPGRADE ####################
# convert file format from old release for backward compatibility
sub releaseupgrade {
   my ($folderdir, $user_releasedate)=@_;
   my $content;
   my $rc_upgrade=0;
   local ($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE, $_REFERENCES)
       =(0,1,2,3,4,5,6,7,8);


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
         if ($file=~/^\..*.cache$/) {
            $file="$folderdir/$file";
            ($file=~/^(.*)$/) && ($file=$1);
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

         next if ( ! -f "$headerdb$config{'dbm_ext'}");

         filelock($folderfile, LOCK_SH);
         open (FOLDER, $folderfile);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
         dbmopen (%HDB, $headerdb, undef);

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
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
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

         next if ( ! -f "$headerdb$config{'dbm_ext'}");

         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
         dbmopen (%HDB, $headerdb, undef);

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
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

         my $cachefile="$headerdb.cache";
         ($cachefile =~ /^(.+)$/) && ($cachefile = $1);  # untaint ...
         unlink($cachefile); # remove cache possiblely for old dbm
      }
      writehistory("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20020108.02");
      writelog("release upgrade - $folderdir/.*$config{'dbm_ext'} by 20020108.02");
   }

   if ( $user_releasedate lt "20020220" ) {
      $rc_upgrade=1;	# .openwebmailrc upgrade will be requested
   }

   return($rc_upgrade);
}
#################### END RELEASEUPGRADE ####################
