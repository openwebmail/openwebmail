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
require "mime.pl";
require "filelock.pl";
require "maildb.pl";
require "pop3mail.pl";
require "mailfilter.pl";

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
local (@validfolders, $folderusage);

local ($folder, $printfolder, $escapedfolder);
local ($searchtype, $keyword, $escapedkeyword);
local $firstmessage;
local $sort;

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

if ( defined(param("sessionid")) ) {
   $thissession = param("sessionid");

   my $loginname = $thissession || '';
   $loginname =~ s/\-session\-0.*$//; # Grab loginname from sessionid

   ($virtualuser, $user, $userrealname, $uuid, $ugid, $homedir)=get_virtualuser_user_userinfo($loginname);
   if ($user eq "") {
      sleep 10;	# delayed response
      openwebmailerror("User $loginname doesn't exist!");
   }
   if ( -f "$config{'ow_etcdir'}/users.conf/$user") { # read per user conf
      readconf(\%config, "$config{'ow_etcdir'}/users.conf/$user");
   }

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

   ($user =~ /^(.+)$/) && ($user = $1);  # untaint ...
   ($uuid =~ /^(.+)$/) && ($uuid = $1);
   ($ugid =~ /^(.+)$/) && ($ugid = $1);
   ($homedir =~ /^(.+)$/) && ($homedir = $1);
   ($folderdir =~ /^(.+)$/) && ($folderdir = $1);

} else {
   sleep 10;	# delayed response
   openwebmailerror("No user specified!");
}

%prefs = %{&readprefs};
%style = %{&readstyle};

($prefs{'language'} =~ /^([\w\d\._]+)$/) && ($prefs{'language'} = $1);
require "etc/lang/$prefs{'language'}";
$lang_charset ||= 'iso-8859-1';

getfolders(\@validfolders, \$folderusage);
if (param("folder")) {
   my $isvalid = 0;
   $folder = param("folder");
   foreach my $checkfolder (@validfolders) {
      if ($folder eq $checkfolder) {
         $isvalid = 1;
         last;
      }
   }
   ($folder = 'INBOX') unless ( $isvalid );
} else {
   $folder = "INBOX";
}
$printfolder = $lang_folders{$folder} || $folder || '';
$escapedfolder = escapeURL($folder);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{"sort"} || 'date';

$keyword = param("keyword") || '';
$escapedkeyword = escapeURL($keyword);
$searchtype = param("searchtype") || 'subject';

########################## MAIN ##############################

verifysession();

my $action = param("action");
if ($action eq "displayheaders_afterlogin") {
   cleantrash($prefs{'trashreserveddays'});
   if ($config{'forced_moveoldmsgfrominbox'} || $prefs{'moveoldmsgfrominbox'}) {
      moveoldmsg2saved();
   }
   displayheaders();
   if ($config{'enable_pop3'} && $prefs{"autopop3"}) {
      _retrpop3s(0);
   }
} elsif ($action eq "displayheaders") {
   displayheaders();
} elsif ($action eq "markasread") {
   markasread();
} elsif ($action eq "markasunread") {
   markasunread();
} elsif ($action eq "movemessage") {
   movemessage();
} elsif ($action eq "retrpop3s" && $config{'enable_pop3'}) {
   retrpop3s();
} elsif ($action eq "retrpop3" && $config{'enable_pop3'}) {
   retrpop3();
} elsif ($action eq "emptytrash") {
   emptytrash();
} elsif ($action eq "logout") {
   cleantrash($prefs{'trashreserveddays'});
   if ($config{'forced_moveoldmsgfrominbox'} || $prefs{'moveoldmsgfrominbox'}) {
      moveoldmsg2saved();
   }
   logout();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

###################### END MAIN ##############################

################ DISPLAYHEADERS #####################
sub displayheaders {
   my $orig_inbox_newmessages=0;
   my $now_inbox_newmessages=0;
   my $now_inbox_allmessages=0;
   my $trash_allmessages=0;
   my %HDB;

   if ( -f "$folderdir/.$user$config{'dbm_ext'}") {
      filelock("$folderdir/.$user$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, "$folderdir/.$user", undef);	# dbm for INBOX
      $orig_inbox_newmessages=$HDB{'NEWMESSAGES'};	# new msg in INBOX
      dbmclose(%HDB);
      filelock("$folderdir/.$user$config{'dbm_ext'}", LOCK_UN);
   }

   filtermessage();

   my ($totalsize, $newmessages, $r_messageids, $r_messagedepths)=getinfomessageids();

   my $numheaders;
   if ($#{$r_messageids}>=0) {
      $numheaders=$#{$r_messageids}+1;
   } else {
      $numheaders=0;
   }

   my $page_total = $numheaders/$prefs{'headersperpage'} || 1;
   $page_total = int($page_total) + 1 if ($page_total != int($page_total));

   if (defined(param("custompage"))) {
      my $pagenumber = param("custompage");
      $pagenumber = 1 if ($pagenumber < 1);
      $pagenumber = $page_total if ($pagenumber > $page_total);
      $firstmessage = (($pagenumber-1)*$prefs{'headersperpage'}) + 1;	# global
   }

   # Perform verification of $firstmessage, make sure it's within bounds
   if ($firstmessage > $numheaders) {
      $firstmessage = $numheaders - $prefs{'headersperpage'};
   }
   if ($firstmessage < 1) {
      $firstmessage = 1;
   }
   my $lastmessage = $firstmessage + $prefs{'headersperpage'} - 1;
   if ($lastmessage > $numheaders) {
       $lastmessage = $numheaders;
   }

   my $main_url = "$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder";
   my $main_url_with_keyword = "$main_url&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype";

   # since some browser always treat refresh directive as realtive url.
   # we use relative path for refresh
   my $refreshinterval=$config{'refreshinterval'}*60;
   my $refresh=param("refresh")+1;
   my $relative_url="$config{'ow_cgiurl'}/openwebmail-main.pl"; 
   $relative_url=~s!/.*/!!g;
   printheader(-Refresh=>"$refreshinterval;URL=$relative_url?sessionid=$thissession&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=INBOX&action=displayheaders&firstmessage=1&refresh=$refresh");

   my $page_nb;
   if ($numheaders > 0) {
      $page_nb = ($firstmessage) * ($numheaders / $prefs{'headersperpage'}) / $numheaders;
      ($page_nb = int($page_nb) + 1) if ($page_nb != int($page_nb));
   } else {
      $page_nb = 1;
   }

   if ($totalsize > 1048575){
      $totalsize = int(($totalsize/1048576)+0.5) . " MB";
   } elsif ($totalsize > 1023) {
      $totalsize =  int(($totalsize/1024)+0.5) . " KB";
   } else {
      $totalsize = $totalsize . " B";
   }

   my $html = '';
   my $temphtml;
   open (VIEWFOLDER, "$config{'ow_etcdir'}/templates/$prefs{'language'}/viewfolder.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/viewfolder.template!");
   while (<VIEWFOLDER>) {
      $html .= $_;
   }
   close (VIEWFOLDER);

   $html = applystyle($html);

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   ### we don't keep keyword between folders,
   ### thus the keyword will be cleared when user change folder
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                         -name=>'FolderForm');
   $temphtml .= hidden(-name=>'sessionid',
                       -value=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'sort',
                       -value=>$sort,
                       -override=>'1');
   $temphtml .= hidden(-name=>'action',
                       -value=>'displayheaders',
                       -override=>'1');
   $temphtml .= hidden(-name=>'firstmessage',
                       -value=>$firstmessage,
                       -override=>'1');
   $html =~ s/\@\@\@STARTFOLDERFORM\@\@\@/$temphtml/;

   my %folderlabels;
   foreach my $foldername (@validfolders) {
      my ($folderfile, $headerdb);

      if (defined $lang_folders{$foldername}) {
         $folderlabels{$foldername}=$lang_folders{$foldername};
      } else {
         $folderlabels{$foldername}=$foldername;
      }

      # add message count in folderlabel
      ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldername);
      if ( -f "$headerdb$config{'dbm_ext'}" ) {
         my ($newmessages, $allmessages);

         filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
         dbmopen (%HDB, $headerdb, undef);
         $allmessages=$HDB{'ALLMESSAGES'};
         $allmessages-=$HDB{'INTERNALMESSAGES'} if ($prefs{'hideinternal'});
         $newmessages=$HDB{'NEWMESSAGES'};
         if ($foldername eq 'INBOX') {
            $now_inbox_allmessages=$allmessages;
            $now_inbox_newmessages=$newmessages;
         } elsif ($foldername eq 'mail-trash')  {
            $trash_allmessages=$allmessages;
         }
         dbmclose(%HDB);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

         if ( $newmessages ne "" && $allmessages ne "" ) {
            $folderlabels{$foldername}.= " ($newmessages/$allmessages)";
         }
      }

   }

   $temphtml = popup_menu(-name=>'folder',
                          -"values"=>\@validfolders,
                          -default=>$folder,
                          -labels=>\%folderlabels,
                          -onChange=>'JavaScript:document.FolderForm.submit();',
                          -override=>'1');
   if ( $ENV{'HTTP_USER_AGENT'} =~ /lynx/i || # take care for text browser...
        $ENV{'HTTP_USER_AGENT'} =~ /w3m/i ) {
      $temphtml .= submit(-name=>"$lang_text{'read'}",
                          -class=>"medtext");
   }
   $html =~ s/\@\@\@FOLDERPOPUP\@\@\@/$temphtml/;

   if ($numheaders>0) {
      $temphtml = ($firstmessage) . " - " . ($lastmessage) . " $lang_text{'of'} " .
                  $numheaders . " $lang_text{'messages'} ";
      if ($newmessages) {
         $temphtml .= "($newmessages $lang_text{'unread'})";
      }
      $temphtml .= " - $totalsize";
   } else {
      $temphtml = $lang_text{'nomessages'};
   }

   if ($folderusage>=100) {
      $temphtml .= " [ $lang_text{'quota_hit'} ]";
   }

   $html =~ s/\@\@\@NUMBEROFMESSAGES\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/compose.gif\" border=\"0\" ALT=\"$lang_text{'composenew'}\"></a> ";
   $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/prefs.gif\" border=\"0\" ALT=\"$lang_text{'userprefs'}\"></a> ";
   if ($config{'folderquota'}) {
      $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/folder.gif\" border=\"0\" ALT=\"$lang_text{'folders'} ($lang_text{'usage'} $folderusage%)\"></a> ";
   } else {
      $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/folder.gif\" border=\"0\" ALT=\"$lang_text{'folders'}\"></a> ";
   }
   $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/addrbook.gif\" border=\"0\" ALT=\"$lang_text{'addressbook'}\"></a> ";
   $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/filtersetup.gif\" border=\"0\" ALT=\"$lang_text{'filterbook'}\"></a> ";
   $temphtml .= "&nbsp; ";
   if ($config{'enable_pop3'}) {
      $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/pop3setup.gif\" border=\"0\" ALT=\"$lang_text{'pop3book'}\"></a> ";
      $temphtml .= "<a href=\"$main_url_with_keyword&amp;action=retrpop3s\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/pop3.gif\" border=\"0\" ALT=\"$lang_text{'retr_pop3s'}\"></a> ";
      $temphtml .= "&nbsp; ";
   }
   $temphtml .= "<a href=\"$main_url&amp;action=displayheaders&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/refresh.gif\" border=\"0\" ALT=\"$lang_text{'refresh'}\"></a> ";
   $temphtml .= "<a href=\"$main_url_with_keyword&amp;action=emptytrash&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/trash.gif\" border=\"0\" ALT=\"$lang_text{'emptytrash'}\" onclick=\"return confirm('$lang_text{emptytrash} ($trash_allmessages $lang_text{messages}) ?');\"></a> ";
   $temphtml .= "<a href=\"$main_url&amp;action=logout\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/logout.gif\" border=\"0\" ALT=\"$lang_text{'logout'} $prefs{'email'}\"></a> &nbsp; ";

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl");
   $temphtml .= hidden(-name=>'action',
                       -default=>'displayheaders',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'sort',
                       -default=>$sort,
                       -override=>'1');
   $temphtml .= hidden(-name=>'keyword',
                       -default=>$keyword,
                       -override=>'1');
   $temphtml .= hidden(-name=>'searchtype',
                       -default=>$searchtype,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');

   $html =~ s/\@\@\@STARTPAGEFORM\@\@\@/$temphtml/g;
   
   my ($temphtml1, $temphtml2);

   if ($firstmessage != 1) {
      $temphtml1 = "<a href=\"$main_url_with_keyword&amp;action=displayheaders&amp;firstmessage=1\">";
      $temphtml1 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/first.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;&lt;\"></a>";
   } else {
      $temphtml1 = "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/first-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   if (($firstmessage - $prefs{'headersperpage'}) >= 1) {
      $temphtml1 .= "<a href=\"$main_url_with_keyword&amp;action=displayheaders&amp;firstmessage=" . ($firstmessage - $prefs{'headersperpage'}) . "\">";
      $temphtml1 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;\"></a>";
   } else {
      $temphtml1 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml1/g;

   if (($firstmessage + $prefs{'headersperpage'}) <= $numheaders) {
      $temphtml2 = "<a href=\"$main_url_with_keyword&amp;action=displayheaders&amp;firstmessage=" . ($firstmessage + $prefs{'headersperpage'}) . "\">";
      $temphtml2 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/right.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;\"></a>";
   } else {
      $temphtml2 = "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/right-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   if (($firstmessage + $prefs{'headersperpage'}) <= $numheaders ) {
      $temphtml2 .= "<a href=\"$main_url_with_keyword&amp;action=displayheaders&amp;custompage=" . "$page_total\">";
      $temphtml2 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/last.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;&gt;\"></a>";
   } else {
      $temphtml2 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/last-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   $html =~ s/\@\@\@RIGHTPAGECONTROL\@\@\@/$temphtml2/g;

   $temphtml = $temphtml1."&nbsp;&nbsp;"."[$lang_text{'page'} " .
                textfield(-name=>'custompage',
                          -default=>$page_nb,
                          -size=>'2',
                          -override=>'1') .
                " $lang_text{'of'} " . $page_total . ']'."&nbsp;&nbsp;".$temphtml2;

   $html =~ s/\@\@\@PAGECONTROL\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                          -name=>'moveform');
   my @movefolders;
   foreach my $checkfolder (@validfolders) {
      if ( $checkfolder ne $folder ) {
         push (@movefolders, $checkfolder);
      }
   }
   # option to del message directly from folder
   if ($folderusage>=100) {
      @movefolders=('DELETE');
   } else {
      push(@movefolders, 'DELETE');   
   }

   $temphtml .= hidden(-name=>'action',
                       -default=>'movemessage',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'firstmessage',
                       -default=>$firstmessage,
                       -override=>'1');
   $temphtml .= hidden(-name=>'sort',
                       -default=>$sort,
                       -override=>'1');
   $temphtml .= hidden(-name=>'keyword',
                       -default=>$keyword,
                       -override=>'1');
   $temphtml .= hidden(-name=>'searchtype',
                       -default=>$searchtype,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');
   $html =~ s/\@\@\@STARTMOVEFORM\@\@\@/$temphtml/g;
   
   my $defaultdestination;
   if ($folderusage>=100 || $folder eq 'mail-trash') {
      $defaultdestination='DELETE';
   } elsif ($folder eq 'sent-mail' || $folder eq 'saved-drafts') {
      $defaultdestination='mail-trash';
   } else {
      $defaultdestination=$prefs{'defaultdestination'} || 'mail-trash';
      $defaultdestination='mail-trash' if ( $folder eq $defaultdestination);
   }
   $temphtml = popup_menu(-name=>'destination',
                          -"values"=>\@movefolders,
                          -default=>$defaultdestination,
                          -labels=>\%lang_folders,
                          -override=>'1');

   $temphtml .= submit(-name=>"$lang_text{'move'}",
                       -class=>"medtext",
                       -onClick=>"return OpConfirm($lang_text{'msgmoveconf'}, $prefs{'confirmmsgmovecopy'})");
   if ($folderusage<100) {
      $temphtml .= submit(-name=>"$lang_text{'copy'}",
                       -class=>"medtext",
                       -onClick=>"return OpConfirm($lang_text{'msgcopyconf'}, $prefs{'confirmmsgmovecopy'})");
   }

   $html =~ s/\@\@\@MOVECONTROLS\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;firstmessage=".
               ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;sort=";
   $temphtml .= "status\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/unread.gif\" border=\"0\" alt=\"$lang_sortlabels{'status'}\"></a>";

   $html =~ s/\@\@\@STATUS\@\@\@/$temphtml/g;
   
   $temphtml = "<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;firstmessage=".
               ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;sort=";
   if ($sort eq "date") {
      $temphtml .= "date_rev\">$lang_text{'date'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"^\"></a>";
   } elsif ($sort eq "date_rev") {
      $temphtml .= "date\">$lang_text{'date'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"v\"></a>";
   } else {
      $temphtml .= "date\">$lang_text{'date'}</a>";
   }

   $html =~ s/\@\@\@DATE\@\@\@/$temphtml/g;
   
   $temphtml = "<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;firstmessage=".
                ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;sort=";

   if ( $folder=~ m#sent-mail#i || 
        $folder=~ m#saved-drafts#i ||
        $folder=~ m#$lang_folders{'sent-mail'}#i ||
        $folder=~ m#$lang_folders{'saved-drafts'}#i ) {
      if ($sort eq "recipient") {
         $temphtml .= "recipient_rev\">$lang_text{'recipient'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"v\"></a></B></td>";
      } elsif ($sort eq "recipient_rev") {
         $temphtml .= "recipient\">$lang_text{'recipient'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"^\"></a></B></td>";
      } else {
         $temphtml .= "recipient\">$lang_text{'recipient'}</a>";
      }
   } else {
      if ($sort eq "sender") {
         $temphtml .= "sender_rev\">$lang_text{'sender'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"v\"></a>";
      } elsif ($sort eq "sender_rev") {
         $temphtml .= "sender\">$lang_text{'sender'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"^\"></a>";
      } else {
         $temphtml .= "sender\">$lang_text{'sender'}</a>";
      }
   }

   $html =~ s/\@\@\@SENDER\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;firstmessage=".
                ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;sort=";
   if ($sort eq "subject") {
      $temphtml .= "subject_rev\">$lang_text{'subject'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"v\"></a>";
   } elsif ($sort eq "subject_rev") {
      $temphtml .= "subject\">$lang_text{'subject'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"^\"></a>";
   } else {
      $temphtml .= "subject\">$lang_text{'subject'}</a>";
   }

   $html =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;firstmessage=".
                ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;sort=";

   if ($sort eq "size") {
      $temphtml .= "size_rev\">$lang_text{'size'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"^\"></a>";
   } elsif ($sort eq "size_rev") {
      $temphtml .= "size\">$lang_text{'size'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"v\"></a>";
   } else {
      $temphtml .= "size\">$lang_text{'size'}</a>";
   }

   $html =~ s/\@\@\@SIZE\@\@\@/$temphtml/g;

   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my ($messageid, $messagedepth, $escapedmessageid);
   my ($offset, $from, $to, $dateserial, $subject, $content_type, $status, $messagesize);
   my ($bgcolor, $message_status);
   my ($boldon, $boldoff); # Used to control whether text is bold for new mails

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen (%HDB, $headerdb, undef);

   $temphtml = '';
   foreach my $messnum (($firstmessage - 1) .. ($lastmessage - 1)) {

      $messageid=${$r_messageids}[$messnum];
      $messagedepth=${$r_messagedepths}[$messnum];
      next if (! defined($HDB{$messageid}) );

      $escapedmessageid = escapeURL($messageid);
      ($offset, $from, $to, $dateserial, $subject, 
	$content_type, $status, $messagesize)=split(/@@@/, $HDB{$messageid});

      # convert between gb and big5
      if ( ($content_type=~/charset="?gb2312"?/i || $status=~/G/i)
           && $lang_charset eq "big5" ) {
         $from= g2b($from);
         $subject= g2b($subject);
      } elsif ( ($content_type=~/charset="?big5"?/i || $status=~/B/i)
           && $lang_charset eq "gb2312" ) {
         $from= b2g($from);
         $subject= b2g($subject);
      }

      # We aren't interested in the sender of SENT/DRAFT folder, 
      # but the recipient, so display $to instead of $from
      if ( $folder=~ m#sent-mail#i || 
           $folder=~ m#saved-drafts#i ||
           $folder=~ m#$lang_folders{'sent-mail'}#i ||
           $folder=~ m#$lang_folders{'saved-drafts'}#i ) {
         my @recvlist = str2list($to);
         my (@namelist, @addrlist);
         foreach my $recv (@recvlist) {
            my ($n, $a)=email2nameaddr($recv);
            push(@namelist, $n);
            push(@addrlist, $a);
         }
         my ($to_name, $to_address)=(join(",", @namelist), join(",", @addrlist));
         if (length($to_name)>32) {
            $to_name=substr($to_name, 0, 29)."...";
         }
         my $escapedto=escapeURL($to);
         $from = qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedto" title="$to_address">$to_name</a>|;
      } else {
         my ($from_name, $from_address)=email2nameaddr($from);
         my $escapedfrom=escapeURL($from);
         $from = qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedfrom" title="$from_address">$from_name</a>|;
      }

      $subject = str2html($subject);
      if ($subject !~ /[^\s]/) {	# Make sure there's SOMETHING clickable 
         $subject = "N/A";
      }

      my $subject_begin = "";
      my $subject_end = "";
      my $fill = "";
      for (my $i=1; $i<$messagedepth; $i++) {
         $fill .= "&nbsp; &nbsp; ";
      }
      if ( $messagedepth>0 && $sort eq "subject" ) {
         $fill .=qq|&nbsp; <img src="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/follow.up.gif" align="absmiddle" border="0">&nbsp;|;
      } elsif ( $messagedepth>0 && $sort eq "subject_rev") {
         $fill .=qq|&nbsp; <img src="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/follow.down.gif" align="absmiddle" border="0">&nbsp;|;
      }

      if ($messagedepth) { 
         $subject_begin = '<table cellpadding="0" cellspacing="0"><tr><td nowrap>' . $fill . "</td><td>";
         $subject_end = "</td></tr></table>";
      }

      if ( $messnum % 2 ) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }

      $message_status = "<B>".($messnum+1)."</B> ";
      # Choose status icons based on Status: line and type of encoding
      $status =~ s/\s//g;	# remove blanks
      if ( $status =~ /r/i ) {
         my $icon="read.gif";
         $icon="read.a.gif" if ($status =~ m/a/i);
         $message_status .= qq|<a href="$main_url_with_keyword&amp;action=markasunread&amp;message_id=$escapedmessageid&amp;status=$status&amp;firstmessage=$firstmessage">|.
                            qq|<img src="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/$icon" align="absmiddle" border="0" ALT="$lang_text{'markasunread'}"></a>|;
         $boldon = '';
         $boldoff = '';
      } else {
         my $icon="unread.gif";
         $icon="unread.a.gif" if ($status =~ m/a/i);
         $message_status .= qq|<a href="$main_url_with_keyword&amp;action=markasread&amp;message_id=$escapedmessageid&amp;status=$status&amp;firstmessage=$firstmessage">|.
                            qq|<img src="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/$icon" align="absmiddle" border="0" ALT="$lang_text{'markasread'}"></a>|;
         $boldon = "<B>";
         $boldoff = "</B>";
      }

#      if ( ($content_type ne '') && 
#           ($content_type ne 'N/A') && 
#           ($content_type !~ /^text/i) ) {
      # T flag is only supported by openwebmail internally
      # see routine update_headerdb in maildb.pl for detail
      if ($status =~ /T/i) { 
         $message_status .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/attach.gif\" align=\"absmiddle\">";
      }

      if ($status =~ /I/i) { 
         $message_status .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/important.gif\" align=\"absmiddle\">";
      }

      # Round message size and change to an appropriate unit for display
      if ($messagesize > 1048575){
         $messagesize = int(($messagesize/1048576)+0.5) . "MB";
      } elsif ($messagesize > 1023) {
         $messagesize =  int(($messagesize/1024)+0.5) . "KB";
      }

      # convert GMT to localtime for non draft/sent folder
      my $datestr;
      if ( $config{'deliver_use_GMT'} &&
           $folder!~ m#sent-mail#i && 
           $folder!~ m#saved-drafts#i &&
           $folder!~ m#$lang_folders{'sent-mail'}#i &&
           $folder!~ m#$lang_folders{'saved-drafts'}#i ) {
         $datestr=dateserial2str(add_dateserial_timeoffset($dateserial, $config{'timeoffset'}), $prefs{'dateformat'});
      } else {
         $datestr=dateserial2str($dateserial, $prefs{'dateformat'});
      }

      $temphtml .= qq|<tr>|.
         qq|<td valign="middle" width="6%" nowrap bgcolor=$bgcolor>$message_status&nbsp;</td>|.
         qq|<td valign="middle" width="18%" bgcolor=$bgcolor>$boldon<font size=-1>$datestr</font>$boldoff</td>|.
         qq|<td valign="middle" width="25%" bgcolor=$bgcolor>$boldon$from$boldoff</td>|.
         qq|<td valign="middle" bgcolor=$bgcolor>|.
         $subject_begin .
         qq|$boldon<a href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;|.
         qq|firstmessage=$firstmessage&amp;sessionid=$thissession&amp;|.
         qq|status=$status&amp;folder=$escapedfolder&amp;sort=$sort&amp;|.
         qq|keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;|.
         qq|headers=|.($prefs{"headers"} || 'simple').qq|&amp;|.
         qq|message_id=$escapedmessageid">\n$subject \n</a>$boldoff|.
         $subject_end .
         qq|</td>|.
         qq|<td valign="middle" align="right" width="5%" bgcolor=$bgcolor>$boldon$messagesize$boldoff</td>|.
         qq|<td align="center" valign="middle" width="3%" bgcolor=$bgcolor>|;

      if ( $numheaders==1 ) {
         # make this msg selected if it is the only one
         $temphtml .= checkbox(-name=>'message_ids',
                               -value=>$messageid,
                               -checked=>1,
                               -label=>'');
      } else {
         $temphtml .= checkbox(-name=>'message_ids',
                               -value=>$messageid,
                               -label=>'');
      }

      $temphtml .= qq|</td></tr>\n\n|;

   }

   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);


   $html =~ s/\@\@\@HEADERS\@\@\@/$temphtml/;


   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl");
   $temphtml .= hidden(-name=>'action',
                       -default=>'displayheaders',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'sort',
                       -default=>$sort,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');

   $html =~ s/\@\@\@STARTSEARCHFORM\@\@\@/$temphtml/g;

   my %searchtypelabels = ('from'=>$lang_text{'from'},
                           'to'=>$lang_text{'to'},
                           'subject'=>$lang_text{'subject'},
                           'date'=>$lang_text{'date'},
                           'attfilename'=>$lang_text{'attfilename'},
                           'header'=>$lang_text{'header'},
                           'textcontent'=>$lang_text{'textcontent'},
                           'all'=>$lang_text{'all'});
   $temphtml = popup_menu(-name=>'searchtype',
                           -default=>'subject',
                           -values=>['from', 'to', 'subject', 'date', 'attfilename', 'header', 'textcontent' ,'all'],
                           -labels=>\%searchtypelabels);
   $temphtml .= textfield(-name=>'keyword',
                          -default=>$keyword,
                          -size=>'25',
                          -override=>'1');
   $temphtml .= "&nbsp;";
   $temphtml .= submit(-name=>"$lang_text{'search'}",
		       -class=>'medtext');

   $html =~ s/\@\@\@SEARCH\@\@\@/$temphtml/g;

   print $html;

   # show 'you have new messages' at status line
   if ($folder ne 'INBOX' ) {
      my $msg;

      if ($now_inbox_newmessages>1) {
         $msg="$now_inbox_newmessages new messages";
      } elsif ($now_inbox_newmessages==1) {
         $msg="1 new message";
      } elsif ($now_inbox_allmessages>1) {
         $msg="$now_inbox_allmessages messages";
      } elsif ($now_inbox_allmessages==1) {
         $msg="1 message";
      } else {
         $msg="No message";
      }

      print qq|<script language="JavaScript">\n<!--\n|.
            qq|window.defaultStatus = "$msg in INBOX"\n|.
            qq|//-->\n</script>\n|;
   }


   # fetch pop3 mail in refresh mode
   if (defined(param("refresh")) &&
       $prefs{"autopop3"}==1 && 
       $config{'autopop3_at_refresh'} &&
       $config{'enable_pop3'} ) {
      _retrpop3s(0);
   }

   # play sound if 
   # a. INBOX has new msg and in refresh mode
   # b. user is viewing other folder and new msg increases in INBOX
   if ( (defined(param("refresh")) && $now_inbox_newmessages>0) ||
        ($folder ne 'INBOX' && $now_inbox_newmessages>$orig_inbox_newmessages) ) {
      if ($prefs{'newmailsound'}==1 && $config{'sound_url'} ne "" ) {
         # only enable sound on Windows platform
         if ( $ENV{'HTTP_USER_AGENT'} =~ /Win/ ) {
            print "<embed src=\"$config{'sound_url'}\" autostart=true hidden=true>";
         }
      }
   }

   printfooter();

}
############### END DISPLAYHEADERS ##################

################# MARKASREAD ####################
sub markasread {
   my $messageid = param("message_id");
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);

   my @attr=get_message_attributes($messageid, $headerdb);

   if ($attr[$_STATUS] !~ /r/i) {
      filelock($folderfile, LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} $folderfile!");
      update_message_status($messageid, $attr[$_STATUS]."R", $headerdb, $folderfile);
      filelock("$folderfile", LOCK_UN);
   }

   displayheaders();
}
################# END MARKASREAD ####################

################# MARKASUNREAD ####################
sub markasunread {	
   my $messageid = param("message_id");
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);

   my @attr=get_message_attributes($messageid, $headerdb);

   if ($attr[$_STATUS] =~ /r/i) {

      # clear R(read) flag
      my $newstatus=$attr[$_STATUS];
      $newstatus=~s/r//ig;

      filelock($folderfile, LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} $folderfile!");
      update_message_status($messageid, $newstatus, $headerdb, $folderfile);
      filelock("$folderfile", LOCK_UN);
   }

   displayheaders();
}
################# END MARKASUNREAD ####################

#################### MOVEMESSAGE ########################
sub movemessage {
   my @messageids = param("message_ids");

   if ( $#messageids<0 ) {	# no message ids to delete, return immediately
      if (param("messageaftermove")) {
#         readmessage();
         my $messageid = param("message_id");
         my $escapedmessageid=escapeURL($messageid);
         print "Location: $config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&firstmessage=$firstmessage&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&message_id=$escapedmessageid&headers=$headers&attmode=$attmode\n\n";
      } else {
         displayheaders();
      }
      return;
   }

   my $destination = param("destination");
#   if ($destination eq $folder || $destination eq 'INBOX') 
   if ($destination eq $folder) {
      openwebmailerror ("$lang_err{'shouldnt_move_here'}") 
   }

   $destination =~ s/\.\.+//g;
   $destination =~ s/[\s\/\`\|\<\>;]//g;		# remove dangerous char
   ($destination =~ /(.+)/) && ($destination = $1);	# bypass taint check

   my $op;
   if ( defined(param($lang_text{copy})) ) {	# copy button pressed
      if ($destination eq 'DELETE') {
         return(0);	# copy to DELETE is meaningless, so return
      } else {
         $op='copy';
      }
   } else {					# move button pressed
      if ($destination eq 'DELETE') {
         $op='delete';
      } else {
         $op='move';
      }
   }
   if ($folderusage>=100 && $op ne "delete") {
      openwebmailerror("$lang_err{'folder_hitquota'}");
   }

   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   if (! -f "$folderfile" ) {
      openwebmailerror("$folderfile $lang_err{'doesnt_exist'}");
   }
   my ($dstfile, $dstdb)=get_folderfile_headerdb($user, $destination);
   if ($destination ne 'DELETE' && ! -f "$dstfile" ) {
      open (F,">>$dstfile") or openwebmailerror("$lang_err{'couldnt_open'} $lang_err{'destination_folder'} $dstfile!");
      close(F);
   }

   filelock("$folderfile", LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $folderfile!");
   if ($destination ne 'DELETE') {
      filelock($dstfile, LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} $dstfile!");
   }

   my $counted=0;
   if ($op eq "delete") {
      $counted=operate_message_with_ids($op, \@messageids, $folderfile, $headerdb);
   } else {
      $counted=operate_message_with_ids($op, \@messageids, $folderfile, $headerdb, 
							$dstfile, $dstdb);
   }

   filelock($dstfile, LOCK_UN);
   filelock($folderfile, LOCK_UN);

   if ($counted>0){
      my $msg;
      if ( $op eq 'move') {
         $msg="movemsg - move $counted msgs from $folder to $destination - ids=".join(", ", @messageids);
      } elsif ($op eq 'copy' ) {
         $msg="copymsg - copy $counted msgs from $folder to $destination - ids=".join(", ", @messageids);
      } else {
         $msg="delmsg - delete $counted msgs from $folder - ids=".join(", ", @messageids);
      }
      writelog($msg);
      writehistory($msg);
   } elsif ($counted==-1) {
      openwebmailerror("$lang_err{'inv_msg_op'}");
   } elsif ($counted==-2) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderfile");
   } elsif ($counted==-3) {
      openwebmailerror("$lang_err{'couldnt_open'} $dstfile!");
   }
    
   # call getfolders to recalc used quota
   getfolders(\@validfolders, \$folderusage); 

   if (param("messageaftermove")) {
#      readmessage();
      my $messageid = param("message_id");
      my $escapedmessageid=escapeURL($messageid);
      print "Location: $config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&firstmessage=$firstmessage&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&message_id=$escapedmessageid&headers=$headers&attmode=$attmode\n\n";
      return;
   } else {
      displayheaders();
   }
}
#################### END MOVEMESSAGE #######################

#################### EMPTYTRASH ########################
sub emptytrash {
   my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'mail-trash');
   open (TRASH, ">$trashfile") or
      openwebmailerror ("$lang_err{'couldnt_open'} $trashfile!");
   close (TRASH) or openwebmailerror("$lang_err{'couldnt_close'} $trashfile!");
   update_headerdb($trashdb, $trashfile);

   writelog("empty trash");
   writehistory("empty trash");

   # call getfolders to recalc used quota
   getfolders(\@validfolders, \$folderusage); 

   displayheaders();
}
#################### END EMPTYTRASH #######################

################## RETRIVE POP3 ###########################
sub retrpop3 {
   my ($spoolfile, $header)=get_folderfile_headerdb($user, 'INBOX');
   my ($pop3host, $pop3user);
   my (%accounts, $response);
   my %pop3error=( -1=>"pop3book read error",
                   -2=>"connect error",
                   -3=>"server not ready",
                   -4=>"'user' error",
                   -5=>"'pass' error",
                   -6=>"'stat' error",
                   -7=>"'retr' error",
                   -8=>"spoolfile write error",
                   -9=>"pop3book write error");

   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); # bypass taint check
      open (F, ">>$spoolfile");
      close(F);
      chown ($uuid, $ugid, $spoolfile);
   }

   $pop3host = param("pop3host") || '';
   $pop3user = param("pop3user") || '';

   if ( ! -f "$folderdir/.pop3.book" ) {
      print "Location:  $config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&sessionid=$thissession&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
      return;
   }
   if (getpop3book("$folderdir/.pop3.book", \%accounts) <0) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.pop3.book!");
   }

   foreach ( @{$config{'disallowed_pop3servers'}} ) {
      if ($pop3host eq $_) {
         openwebmailerror("$lang_err{'disallowed_pop3'} $pop3host");
      }
   }

   # since pop3 fetch may be slow, the spoolfile lock is done inside routine.
   # the spoolfile is locked when each one complete msg is retrieved
   $response = retrpop3mail($pop3host, $pop3user, "$folderdir/.pop3.book", $spoolfile);

   if ($response>=0) {	# new mail found
      $folder="INBOX";
      print "Location: $config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&sessionid=$thissession&sort=$sort&firstmessage=$firstmessage&folder=$folder\n\n";
      return;
   } else {
      writelog("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
      writehistory("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
      if ($response == -1 || $response==-9) {
   	  openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.pop3.book!");
      } elsif ($response == -8) {
   	  openwebmailerror("$lang_err{'couldnt_open'} $spoolfile");
      } elsif ($response == -2 || $response == -3) {
   	  openwebmailerror("$pop3user\@$pop3host $lang_err{'couldnt_open'}");
      } elsif ($response == -4) {
    	  openwebmailerror("$pop3user\@$pop3host $lang_err{'user_not_exist'}");
      } elsif ($response == -5) {
      	  openwebmailerror("$pop3user\@$pop3host $lang_err{'pwd_incorrect'}");
      } elsif ($response == -6 || $sreponse == -7) {
   	  openwebmailerror("$pop3user\@$pop3host $lang_err{'network_server_error'}");
      }
   }
}
################## END RETRIVE POP3 ###########################

################## RETRIVE ALL POP3 ###########################
sub retrpop3s {
   if ( ! -f "$folderdir/.pop3.book" ) {
      print "Location: $config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&sessionid=$thissession&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
      return;
   }
  
   _retrpop3s(10);

   $folder="INBOX";
   print "Location: $config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&sessionid=$thissession&sort=$sort&firstmessage=$firstmessage&folder=$folder\n\n";
}

sub _retrpop3s {
   my $timeout=$_[0];
   my ($spoolfile, $header)=get_folderfile_headerdb($user, 'INBOX');
   my (%accounts, $response);
   my $fetch_complete=0;
   my $i;
   my %pop3error=( -1=>"pop3book read error",
                   -2=>"connect error",
                   -3=>"server not ready",
                   -4=>"'user' error",
                   -5=>"'pass' error",
                   -6=>"'stat' error",
                   -7=>"'retr' error",
                   -8=>"spoolfile write error",
                   -9=>"pop3book write error");

   if ( ! -f "$folderdir/.pop3.book" ) {
      return;
   }

   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); # bypass taint check
      open (F, ">>$spoolfile");
      close(F);
      chown($uuid, $ugid, $spoolfile);
   }

   if (getpop3book("$folderdir/.pop3.book", \%accounts) <0) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.pop3.book!");
   }

   # fork a child to do fetch pop3 mails and return immediately
   if (%accounts >0) {
      $|=1; 				# flush all output
      $SIG{CHLD} = sub { wait; $fetch_complete=1; };	# handle zombie

      if ( fork() == 0 ) {		# child
         close(STDOUT);
         close(STDIN);

         foreach (values %accounts) {
            my ($pop3host, $pop3user, $enable);
            my ($response, $dummy, $h);

            ($pop3host, $pop3user, $dummy, $dummy, $dummy, $enable) = split(/\@\@\@/,$_);
            next if (!$enable);

            foreach $h ( @{$config{'disallowed_pop3servers'}} ) {
               last if ($pop3host eq $h);
            }
            next if ($pop3host eq $h);

            $response = retrpop3mail($pop3host, $pop3user, 
         				"$folderdir/.pop3.book",  $spoolfile);
            if ( $response<0) {
               writelog("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
               writehistory("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
            }
         }
         exit;
      }
   }

   for ($i=0; $i<$timeout; $i++) {	# wait fetch to complete for $timeout seconds
      sleep 1;
      if ($fetch_complete==1) {
         last;
      }
   }   
   return;
}
################## END RETRIVE ALL POP3 ###########################

################## MOVEOLDMSG2SAVED ########################
sub moveoldmsg2saved {
   my ($srcfile, $srcdb)=get_folderfile_headerdb($user, 'INBOX');
   my ($dstfile, $dstdb)=get_folderfile_headerdb($user, 'saved-messages');
   my $counted;
 
   filelock($srcfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $srcfile!");
   filelock($dstfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $dstfile!");

   $counted=move_oldmsg_from_folder($srcfile, $srcdb, $dstfile, $dstdb);

   filelock($dstfile, LOCK_UN);
   filelock($srcfile, LOCK_UN);

   if ($counted>0){
      my $msg="movemsg - move $counted old msgs from INBOX to saved-messages";
      writelog($msg);
      writehistory($msg);
   } elsif ($counted==-1) {
      openwebmailerror("$lang_err{'inv_msg_op'}");
   } elsif ($counted==-2) {
      openwebmailerror("$lang_err{'couldnt_open'} $srcfile");
   } elsif ($counted==-3) {
      openwebmailerror("$lang_err{'couldnt_open'} $dstfile!");
   }
}
################ END MOVEOLDMSG2SAVED ########################

################# CLEANTRASH ################
sub cleantrash {
   my $days=$_[0];
   return if ($days<=0);

   # check only if last check has passed for more than one day
   my $m=(-M "$folderdir/.trash.check");
   return if ( $m && $m<1 );

   my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'mail-trash');
   filelock($trashfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $trashfile!");
   my $deleted=delete_message_by_age($days, $trashdb, $trashfile);
   if ($deleted >0) {
      writelog("delmsg - delete $deleted msgs from mail-trash");
      writehistory("delmsg - delete $deleted msgs from mail-trash");
   }
   filelock($trashfile, LOCK_UN);

   open (TRASHCHECK, ">$folderdir/.trash.check" ) or 
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.trash.check!");
   my $t=localtime();
   print TRASHCHECK "checktime=", $t;
   close (TRASHCHECK);

   return;
}
################# END CLEANTRASH ################

#################### LOGOUT ########################
sub logout {
   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^(.+?\-\d?\.\d+)$/) && ($thissession = $1));
   $thissession =~ s/\///g;  # just in case someone gets tricky ...

   unlink "$config{'ow_etcdir'}/sessions/$thissession";
   writelog("logout - $thissession");
   writehistory("logout - $thissession");

   printheader();

   my $html = '';
   open (LOGINOUT, "$config{'ow_etcdir'}/templates/$prefs{'language'}/logout.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/logout.template!");
   while (<LOGINOUT>) {
      $html .= $_;
   }
   close (LOGINOUT);
   $html = applystyle($html);

   my $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail.pl") .
                  submit("$lang_text{'loginagain'}").
                  "&nbsp; &nbsp;".
                  button(-name=>"exit",
                         -value=>$lang_text{'exit'},
                         -onclick=>'javascript:window.close();',
                         -override=>'1').
                  end_form();
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/;
      
   print $html;

   printfooter();
}
################## END LOGOUT ######################
