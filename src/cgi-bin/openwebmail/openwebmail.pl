#!/usr/bin/perl -T
#############################################################################
# Open WebMail - Provides a web interface to user mailboxes                 #
#                                                                           #
# Copyright (C) 2001                                                        #
# Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric                 #
# Copyright (C) 2000                                                        #
# Ernie Miller  (original GPL project: Neomail)                             #
#                                                                           #
# This program is distributed under GNU General Public License              #
#############################################################################

use strict;
no strict 'vars';
use Fcntl qw(:DEFAULT :flock);
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

$ENV{PATH} = ""; # no PATH should be needed
$ENV{BASH_ENV} = ""; # no startup sciprt for bash
umask(0007); # make sure the openwebmail group can write

push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
require "openwebmail-shared.pl";
require "filelock.pl";

local %config;
readconf(\%config, "/usr/local/www/cgi-bin/openwebmail/etc/openwebmail.conf");
require $config{'auth_module'} or
   openwebmailerror("Can't open authentication module $config{'auth_module'}");

local $thissession;
local ($virtualuser, $user, $userrealname, $uuid, $ugid, $mailgid, $homedir);

local %prefs;
local %style;
local ($lang_charset, %lang_folders, %lang_sortlabels, %lang_text, %lang_err);

local $folderdir;

$mailgid=getgrnam('mail');

# setuid is required if mails is located in user's dir
if ( $config{'use_homedirspools'} || $config{'use_homedirfolders'} ) {
   if ( $> != 0 ) {
      my $suidperl=$^X;
      $suidperl=~s/perl/suidperl/;
      openwebmailerror("<b>$0 must setuid to root!</b><br>".
                       "<br>1. check if script is owned by root with mode 4555".
                       "<br>2. use '#!$suidperl' instead of '#!$^X' in script");
   }  
}

if ( ($config{'logfile'} ne 'no') && (! -f $config{'logfile'})  ) {
   open (LOGFILE,">>$config{'logfile'}") or 
      openwebmailerror("Can't open log file $config{'logfile'}!");
   close(LOGFILE);
   chmod(0660, $config{'logfile'});
   chown($>, $mailgid, $config{'logfile'});
}

%prefs = %{&readprefs};
%style = %{&readstyle};

($prefs{'language'} =~ /^([\w\d\._]+)$/) && ($prefs{'language'} = $1);
require "etc/lang/$prefs{'language'}";
$lang_charset ||= 'iso-8859-1';

####################### MAIN ##########################
if ( param("loginname") && param("password") ) {
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
   my $loginname = param("loginname") || '';
   my $password = param("password") || '';

   $loginname =~ /^(.*)$/; # accept any characters for loginname/pass auth info
   $loginname = $1;
   $password =~ /^(.*)$/;
   $password = $1;

   ($virtualuser, $user, $userrealname, $uuid, $ugid, $homedir)=get_virtualuser_user_userinfo($loginname);
   if ($user eq "") {
      sleep 10;	# delayed response
      openwebmailerror("$lang_err{'user_not_exist'}");
   }
   if (! $config{'enable_rootlogin'}) {
      if ($user eq 'root' || $uuid==0) {
         sleep 10;	# delayed response
         writelog("login error - root login attempt");
         openwebmailerror ("$lang_err{'norootlogin'}");
      }
   }

   my $errorcode=check_userpassword($user, $password);
   if ( $errorcode==0 ) {
      $thissession = $loginname. "-session-" . rand(); # name the sessionid
      writelog("login - $thissession");
      cleanupoldsessions(); # Deletes sessionids that have expired

      if ( $config{'use_homedirspools'} || $config{'use_homedirfolders'} ) {
         set_euid_egid_umask($uuid, $mailgid, 0077);	
      } else {
         set_euid_egid_umask($>, $mailgid, 0077);	
      }
      # egid must be mail since this is a mail program...
      if ( $) != $mailgid) { 
         openwebmailerror("Set effective gid to mail($mailgid) failed!");
      }

      if ( $config{'use_homedirfolders'} ) {
         $folderdir = "$homedir/$config{'homedirfolderdirname'}";
      } else {
         $folderdir = "$config{'ow_etcdir'}/users/$user";
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
      if ( -f "$folderdir/.release.date" ) {
         open(D, "$folderdir/.release.date");
         $user_releasedate=<D>;
         chomp($user_releasedate);
         close(D);
      }
      if ($user_releasedate ne $config{'releasedate'}) {
         releaseupgrade($folderdir, $user_releasedate);
         open(D, ">$folderdir/.release.date");
         print D $config{'releasedate'};
         close(D);
      }

      # set cookie in header and redirect page to openwebmail-main
      if ( -f "$folderdir/.openwebmailrc" ) {
         $action='displayheaders_afterlogin';
      } else {
         $action='firsttimeuser';
      }

      my @headers=();
      push(@headers, -pragma=>'no-cache');
      $cookie = cookie( -name    => "$user-sessionid",
                        -value   => "$setcookie",
                        -path    => '/' );
      push(@headers, -cookie=>$cookie);
      push(@headers, -charset=>$lang_charset) if ($CGI::VERSION>=2.57);
      push(@headers, -Refresh=>"0;URL=$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&action=$action");
      print header(@headers);

      # display copyright. Don't touch it, please.
      print	qq|<html>\n|,
		qq|<head><title>Copyright</title></head>\n|,
		qq|<body bgcolor="#ffffff" background="$prefs{'bgurl'}">\n|,
                qq|<center><br><br><br>\n|,
                qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&action=$action" style="text-decoration: none">|,
		qq|<font color="#888888"> &nbsp; Loading . . .</font></a>\n|,
		qq|<br><br><br>\n\n|.
                qq|<a href="http://turtle.ee.ncku.edu.tw/openwebmail/" style="text-decoration: none">\n|,
		qq|<font color="#cccccc" face="arial,helvetica,sans-serif" size=-1>\n|,
                qq|Open WebMail $config{'version'} $config{'releasedate'}<br><br>\n|,
		qq|Copyright (C) 2001<br>\n|,
		qq|Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric<br><br>\n|,
		qq|Copyright (C) 2000<br>\n|,
		qq|Ernie Miller  (original GPL project: Neomail)<br><br>\n|,
		qq|</font></a>\n\n|,
                qq|<a href="http://turtle.ee.ncku.edu.tw/openwebmail/download/doc/copyright.txt" style="text-decoration: none">\n|,
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
         set_euid_egid_umask($uuid, $mailgid, 0077);	
      } else {
         set_euid_egid_umask($>, $mailgid, 0077);	
      }
      if ( $config{'use_homedirfolders'} ) {
         $folderdir = "$homedir/$config{'homedirfolderdirname'}";
      } else {
         $folderdir = "$config{'ow_etcdir'}/users/$user";
      }

      if ( -d $folderdir) {
         if ( ! -f "$folderdir/.history.log" ) {
            open(HISTORYLOG, ">>$folderdir/.history.log");
            close(HISTORYLOG);
            chown($uuid, $mailgid, "$folderdir/.history.log");
         }
         writehistory("login error - $errorcode - loginname=$loginname");
      }

      sleep 10;	# delayed response 

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

}

#################### END RELEASEUPGRADE ####################
