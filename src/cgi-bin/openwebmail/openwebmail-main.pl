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

getfolders(\@validfolders, \$folderusage, 0);
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
if ($action eq "firsttimeuser") {
   firsttimeuser();
} elsif ($action eq "displayheaders_afterlogin") {
   cleantrash($prefs{'trashreserveddays'});
   displayheaders();
   if ($prefs{"autopop3"}==1 && $config{'enable_pop3'}) {
      _retrpop3s(0);
   }
} elsif ($action eq "displayheaders") {
   displayheaders();
} elsif ($action eq "readmessage") {
   readmessage();
} elsif ($action eq "viewattachment") {
   viewattachment();
} elsif ($action eq "viewattfile") {
   viewattfile();
} elsif ($action eq "replyreceipt") {
   replyreceipt();
} elsif ($action eq "composemessage") {
   composemessage();
} elsif ($action eq "sendmessage") {
   sendmessage();
} elsif ($action eq "movemessage") {
   movemessage();
} elsif ($action eq "retrpop3s" && $config{'enable_pop3'}) {
   retrpop3s();
} elsif ($action eq "retrpop3" && $config{'enable_pop3'}) {
   retrpop3();
} elsif ($action eq "emptytrash") {
   emptytrash();
} elsif ($action eq "logout") {
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
   my $base_url = "$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder";
   my $base_url_nokeyword = "$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder";

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

   $temphtml = "<a href=\"$base_url&amp;action=composemessage&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/compose.gif\" border=\"0\" ALT=\"$lang_text{'composenew'}\"></a> ";
   $temphtml .= "<a href=\"$base_url_nokeyword&amp;action=displayheaders&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/refresh.gif\" border=\"0\" ALT=\"$lang_text{'refresh'}\"></a> ";
   $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/prefs.gif\" border=\"0\" ALT=\"$lang_text{'userprefs'}\"></a> ";
   if ($config{'folderquota'}) {
      $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/folder.gif\" border=\"0\" ALT=\"$lang_text{'folders'} ($lang_text{'usage'} $folderusage%)\"></a> ";
   } else {
      $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/folder.gif\" border=\"0\" ALT=\"$lang_text{'folders'}\"></a> ";
   }
   $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/addresses.gif\" border=\"0\" ALT=\"$lang_text{'addressbook'}\"></a> ";
   $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/filtersetup.gif\" border=\"0\" ALT=\"$lang_text{'filterbook'}\"></a> &nbsp; ";
   if ($config{'enable_pop3'}) {
      $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/pop3setup.gif\" border=\"0\" ALT=\"$lang_text{'pop3book'}\"></a> ";
      $temphtml .= "<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?action=retrpop3s&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/pop3.gif\" border=\"0\" ALT=\"$lang_text{'retr_pop3s'}\"></a> &nbsp; ";
   }
   $temphtml .= "<a href=\"$base_url&amp;action=emptytrash&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/trash.gif\" border=\"0\" ALT=\"$lang_text{'emptytrash'}\" onclick=\"return confirm('$lang_text{emptytrash} ($trash_allmessages $lang_text{messages}) ?');\"></a> ";
   $temphtml .= "<a href=\"$base_url_nokeyword&amp;action=logout\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/logout.gif\" border=\"0\" ALT=\"$lang_text{'logout'} $prefs{'email'}\"></a> &nbsp; ";

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
      $temphtml1 = "<a href=\"$base_url&amp;action=displayheaders&amp;firstmessage=1\">";
      $temphtml1 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/first.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;&lt;\"></a>";
   } else {
      $temphtml1 = "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/first-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   if (($firstmessage - $prefs{'headersperpage'}) >= 1) {
      $temphtml1 .= "<a href=\"$base_url&amp;action=displayheaders&amp;firstmessage=" . ($firstmessage - $prefs{'headersperpage'}) . "\">";
      $temphtml1 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;\"></a>";
   } else {
      $temphtml1 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml1/g;

   if (($firstmessage + $prefs{'headersperpage'}) <= $numheaders) {
      $temphtml2 = "<a href=\"$base_url&amp;action=displayheaders&amp;firstmessage=" . ($firstmessage + $prefs{'headersperpage'}) . "\">";
      $temphtml2 .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/right.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;\"></a>";
   } else {
      $temphtml2 = "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/right-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   if (($firstmessage + $prefs{'headersperpage'}) <= $numheaders ) {
      $temphtml2 .= "<a href=\"$base_url&amp;action=displayheaders&amp;custompage=" . "$page_total\">";
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
   $temphtml .= "status\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/new.gif\" border=\"0\" alt=\"$lang_sortlabels{'status'}\"></a>";

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
         $temphtml .= "recipient_rev\">$lang_text{'recipient'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"v\"></a></B></td>";
      } elsif ($sort eq "recipient_rev") {
         $temphtml .= "recipient\">$lang_text{'recipient'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"^\"></a></B></td>";
      } else {
         $temphtml .= "recipient\">$lang_text{'recipient'}</a>";
      }
   } else {
      if ($sort eq "sender") {
         $temphtml .= "sender_rev\">$lang_text{'sender'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"v\"></a>";
      } elsif ($sort eq "sender_rev") {
         $temphtml .= "sender\">$lang_text{'sender'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"^\"></a>";
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
   if ($sort eq "thread") {
      $temphtml .= "thread_rev\">$lang_text{'thread'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/up.gif\" border=\"0\" alt=\"v\"></a>";
   } elsif ($sort eq "thread_rev") {
      $temphtml .= "thread\">$lang_text{'thread'} <IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/down.gif\" border=\"0\" alt=\"^\"></a>";
   } else {
      $temphtml .= "thread\">$lang_text{'thread'}</a>";
   }

   $html =~ s/\@\@\@THREAD\@\@\@/$temphtml/g;

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
   my ($offset, $from, $to, $date, $subject, $content_type, $status, $messagesize);
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
      ($offset, $from, $to, $date, $subject, 
	$content_type, $status, $messagesize)=split(/@@@/, $HDB{$messageid});

      # We aren't interested in the sender of SENT/DRAFT folder, 
      # but the recipient, so display $to instead of $from
      if ( $folder=~ m#sent-mail#i || 
           $folder=~ m#saved-drafts#i ||
           $folder=~ m#$lang_folders{'sent-mail'}#i ||
           $folder=~ m#$lang_folders{'saved-drafts'}#i ) {
         $from = (split(/,/, $to))[0];
      }

      my $from_name;
      my $from_address;
      if ($from =~ m/^"?(.+?)"?\s*<(.*)>$/) {
         $from_name = $1;
         $from_address = $2;
      } elsif ($from =~ m/<?(.*@.*)>?\s+\((.+?)\)/) {
         $from_name = $2;
         $from_address = $1;
      } elsif ($from =~ m/<(.+)>/) {
         $from_name = $1;
         $from_address = $1;
         $from_name =~ s/\@.*$//;
      } elsif ($from =~ m/(.+)/) {
         $from_name = $1;
         $from_address = $1;
         $from_name =~ s/\@.*$//;
      }
      $from = qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$from_address">$from_name</a>|;

      if ($from !~ /[^\s]/) {
         $from="&nbsp;";
      }

      $subject = str2html($subject);
      if ($subject !~ /[^\s]/) {	# Make sure there's SOMETHING clickable 
         $subject = "N/A";
      }

      my $subject_begin = "";
      my $subject_end = "";
      my $fill = "";
      for (my $i=0; $i<$messagedepth; $i++) {
         $fill .= "&nbsp;&nbsp;&nbsp;&nbsp;";
      }
      if ($messagedepth) { 
         $subject_begin = '<table cellpadding="0" cellspacing="0"><tr><td>' . $fill . "</td><td>";
         $subject_end = "</td></tr></table>";
      }

      if ( $messnum % 2 ) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }

      # Round message size and change to an appropriate unit for display
      if ($messagesize > 1048575){
         $messagesize = int(($messagesize/1048576)+0.5) . "MB";
      } elsif ($messagesize > 1023) {
         $messagesize =  int(($messagesize/1024)+0.5) . "KB";
      }

      $message_status = "<B>".($messnum+1)."</B> ";
      # Choose status icons based on Status: line and type of encoding
      $status =~ s/\s//g;	# remove blanks
      if ( $status =~ /r/i ) {
         $boldon = '';
         $boldoff = '';
      } else {
         $message_status .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/new.gif\" align=\"absmiddle\">";
         $boldon = "<B>";
         $boldoff = "</B>";
      }

      if ( ($content_type ne '') && 
           ($content_type ne 'N/A') && 
           ($content_type !~ /^text/i) ) {
         $message_status .= "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/attach.gif\" align=\"absmiddle\">";
      }

      if ($status =~ m/a/i) {
         $message_status .= "<B>A</B>";
      }

      $temphtml .= qq|<tr>|.
         qq|<td valign="middle" width="6%" nowrap bgcolor=$bgcolor>$message_status&nbsp;</td>|.
         qq|<td valign="middle" width="16%" bgcolor=$bgcolor>$boldon<font size=-1>$date</font>$boldoff</td>|.
         qq|<td valign="middle" width="25%" bgcolor=$bgcolor>$boldon$from$boldoff</td>|.
         qq|<td valign="middle" bgcolor=$bgcolor>|.
         $subject_begin .
         qq|$boldon<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=readmessage&amp;|.
         qq|firstmessage=$firstmessage&amp;sessionid=$thissession&amp;|.
         qq|status=$status&amp;folder=$escapedfolder&amp;sort=$sort&amp;|.
         qq|keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;|.
         qq|headers=|.($prefs{"headers"} || 'simple').qq|&amp;|.
         qq|message_id=$escapedmessageid">$subject </a>$boldoff|.
         $subject_end .
         qq|</td>|.
         qq|<td valign="middle" width="5%" bgcolor=$bgcolor>$boldon$messagesize$boldoff</td>|.
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

      $temphtml .= qq|</td></tr>|;

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

################# READMESSAGE ####################
sub readmessage {
   # filter junkmail at inbox beofre display any message in inbox
   filtermessage() if ($folder eq 'INBOX');

   my $messageid = param("message_id");
   my %message = %{&getmessage($messageid)};

   if (%message) {
      printheader();

      my $escapedmessageid = escapeURL($messageid);
      my $headers = param("headers") || $prefs{"headers"} || 'simple';
      my $attmode = param("attmode") || 'simple';

      my $html = '';
      my ($temphtml, $temphtml1, $temphtml2);
      open (READMESSAGE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/readmessage.template") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/readmessage.template!");
      while (<READMESSAGE>) {
         $html .= $_;
      }
      close (READMESSAGE);

      $html = applystyle($html);

      if ( $lang_folders{$folder} ) {
         $html =~ s/\@\@\@FOLDER\@\@\@/$lang_folders{$folder}/g;
      } else {
         $html =~ s/\@\@\@FOLDER\@\@\@/$folder/g;
      }

      # web-ified headers
      my ($from, $replyto, $to, $notificationto, $cc, $subject, $body);
      $from = str2html($message{from} || '');
      $replyto = str2html($message{replyto} || '');
      $to = str2html($message{to} || '');
      $cc = str2html($message{cc} || '');
      $subject = str2html($message{subject} || '');

      if ($message{header}=~/^Disposition-Notification-To:\s?(.*?)$/im ) {
         $notificationto=$1;
      }

      $body = $message{"body"} || '';

      if ($message{contenttype} =~ /^text/i) {
         if ($message{encoding} =~ /^quoted-printable/i) {
            $body= decode_qp($body);
         } elsif ($message{encoding} =~ /^base64/i) {
            $body= decode_base64($body);
         }
      }

      # convert between gb and big5
      if ( param('convert') eq 'b2g' ) {
         $subject= b2g($subject);
         $body= b2g($body);
      } elsif ( param('convert') eq 'g2b' ) {
         $subject= g2b($subject);
         $body= g2b($body);
      }

      my %smilies = (":)" => "FaceHappy",
		     ":>" => "FaceHappy",
		     ";)" => "FaceWinking",
		     ";>" => "FaceWinking",
		     ";(" => "FaceSad",
		     ";<" => "FaceSad",
		     ":(" => "FaceSad",
		     ":<" => "FaceSad",
		     ">:)" => "FaceDevilish",
		     ">;)" => "FaceDevilish",
		     "8)" => "FaceGrinning",
		     "8>" => "FaceGrinning",
		     ":D" => "FaceGrinning",
		     ";D" => "FaceGrinning",
		     "8D" => "FaceGrinning",
		     ":/" => "FaceIronic",
		     ";/" => "FaceIronic",
		     "8/" => "FaceIronic",
		     ":\\" => "FaceIronic",
		     ";\\" => "FaceIronic",
		     "8\\" => "FaceIronic",
		     ":P" => "FaceNyah",
		     ";P" => "FaceNyah",
		     "8P" => "FaceNyah",
		     ":d" => "FaceTasty",
		     ";d" => "FaceTasty",
		     "8d" => "FaceTasty",
		     ":o" => "FaceStartled",
		     ";o" => "FaceStartled",
		     "8o" => "FaceStartled",
		     ":O" => "FaceStartled",
		     ";O" => "FaceStartled",
		     "8O" => "FaceStartled",
		     ":|" => "FaceStraight",
		     ";|" => "FaceWry",
		     "8|" => "FaceKOed",
		     ":X" => "FaceYukky",
		     ";X" => "FaceYukky");

      $body =~ s/(>?)([:;8])[-^]?([\(\)\>\<\|PDdoOX\\\/\*])(\s)/___SMILE_$smilies{$1.$2.$3}___$4/g if $prefs{'usesmileicon'};

      if ($message{contenttype} =~ m#^text/html#i) { # convert into html table
         $body = html4nobase($body); 
         $body = html4mailto($body, "$config{'ow_cgiurl'}/openwebmail-main.pl", "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
         $body = html4disablejs($body) if ($prefs{'disablejs'}==1);
         $body = html2table($body); 
      } else { 					     # body must be html or text
      # remove odds space or blank lines
         $body =~ s/(\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;	
         $body =~ s/\n\s*$/\n/;
         $body = text2html($body);
      }

      $body =~ s/___SMILE_(\w*)___/<img border=\"0\" width=\"12\" height=\"12\" src=\"$config{'ow_htmlurl'}\/images\/smilies\/$1\.png\">/g if $prefs{'usesmileicon'};

      my $base_url = "$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;firstmessage=" . ($firstmessage) .
                     "&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid";
      my $base_url_noid = "$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;firstmessage=" . ($firstmessage) .
                          "&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder";

      # Set up the message to go to after move.
      my $messageaftermove;
      if (defined($message{"next"})) {
         $messageaftermove = $message{"next"};
      } elsif (defined($message{"prev"})) {
         $messageaftermove = $message{"prev"};
      }

      $html =~ s/\@\@\@MESSAGETOTAL\@\@\@/$message{"total"}/g;

      $temphtml = "<a href=\"$base_url&amp;action=displayheaders\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; ";
      $html =~ s/\@\@\@BACKTOLINK\@\@\@/$temphtml/g;

      # passing covnert parm for big5/gb to composemessage if readmessage is converted
      my $convertparm;
      if ( param('convert') eq 'b2g' ) {
         $convertparm="&amp;convert=b2g";
      } elsif ( param('convert') eq 'g2b' ) {
         $convertparm="&amp;convert=g2b";
      }

      if ($folder eq 'saved-drafts') {
         $temphtml .= "<a href=\"$base_url&amp;action=composemessage&amp;composetype=editdraft\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/editdraft.gif\" border=\"0\" ALT=\"$lang_text{'editdraft'}\"></a> &nbsp; ";
      } elsif ($folder eq 'sent-mail') {
         $temphtml .= "<a href=\"$base_url&amp;action=composemessage&amp;composetype=editdraft\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/editdraft.gif\" border=\"0\" ALT=\"$lang_text{'editdraft'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=reply$convertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/reply.gif\" border=\"0\" ALT=\"$lang_text{'reply'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=replyall$convertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/replyall.gif\" border=\"0\" ALT=\"$lang_text{'replyall'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=forward$convertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forward.gif\" border=\"0\" ALT=\"$lang_text{'forward'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=forwardasatt\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forwardasatt.gif\" border=\"0\" ALT=\"$lang_text{'forwardasatt'}\"></a> " .
         "&nbsp; ";
      } else {
         $temphtml .= "<a href=\"$base_url&amp;action=composemessage&amp;composetype=reply$convertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/reply.gif\" border=\"0\" ALT=\"$lang_text{'reply'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=replyall$convertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/replyall.gif\" border=\"0\" ALT=\"$lang_text{'replyall'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=forward$convertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forward.gif\" border=\"0\" ALT=\"$lang_text{'forward'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=forwardasatt\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forwardasatt.gif\" border=\"0\" ALT=\"$lang_text{'forwardasatt'}\"></a> " .
         "&nbsp; ";
      }

      if ($prefs{'language'} eq 'zh_CN.GB2312') {
         if (defined(param('convert'))) {
            $temphtml .= "<a href=\"$base_url&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif\" border=\"0\" alt=\"revert back\"></a> ";
         } else {
            $temphtml .= "<a href=\"$base_url&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode&amp;convert=b2g\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif\" border=\"0\" alt=\"Big5 to GB\"></a> ";
         }
      } elsif ($prefs{'language'} eq 'zh_TW.Big5') {
         if (defined(param('convert'))) {
            $temphtml .= "<a href=\"$base_url&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif\" border=\"0\" alt=\"revert back\"></a> ";
         } else {
            $temphtml .= "<a href=\"$base_url&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode&amp;convert=g2b\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif\" border=\"0\" alt=\"GB to Big5\"></a> ";
         }
      }

      $temphtml .= "<a href=\"$base_url&amp;action=logout\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/logout.gif\" border=\"0\" ALT=\"$lang_text{'logout'} $prefs{'email'}\"></a>";
   
      $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

      if (defined($message{"prev"})) {
         $temphtml1 = "<a href=\"$base_url_noid&amp;action=readmessage&amp;message_id=$message{'prev'}&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;&lt;\"></a>";
      } else {
         $temphtml1 = "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
      }
      $html =~ s/\@\@\@LEFTMESSAGECONTROL\@\@\@/$temphtml1/g;

      if (defined($message{"next"})) {
         $temphtml2 = "<a href=\"$base_url_noid&amp;action=readmessage&amp;message_id=$message{'next'}&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/right.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;&gt;\"></a>";
      } else {
         $temphtml2 = "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/right-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
      }
      $html =~ s/\@\@\@RIGHTMESSAGECONTROL\@\@\@/$temphtml2/g;

      $temphtml = $temphtml1 . "  " . $message{"number"} . "  " . $temphtml2;
      $html =~ s/\@\@\@MESSAGECONTROL\@\@\@/$temphtml/g;

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                             -name=>'moveform');
      my @movefolders;
      foreach my $checkfolder (@validfolders) {
#         if ( ($checkfolder ne 'INBOX') && ($checkfolder ne $folder) ) 
         if ($checkfolder ne $folder) {
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
      $temphtml .= hidden(-name=>'headers',
                          -default=>$headers,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_ids',
                          -default=>$messageid,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>$messageaftermove,
                          -override=>'1');
      if ($messageaftermove) {
         $temphtml .= hidden(-name=>'messageaftermove',
                             -default=>'1',
                             -override=>'1');
      }
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

      if ($prefs{'confirmmsgmovecopy'}) {
         $temphtml .= submit(-name=>"$lang_text{'move'}",
                       -onClick=>"document.moveform.message_id.value='$messageaftermove'; return confirm($lang_text{'msgmoveconf'})");
         if ($folderusage<100) {
            $temphtml .= submit(-name=>"$lang_text{'copy'}",
                       -onClick=>"document.moveform.message_id.value='$messageid'; return confirm($lang_text{'msgcopyconf'})");
         }
      } else {
         $temphtml .= submit(-name=>"$lang_text{'move'}",
                       -onClick=>"document.moveform.message_id.value='$messageaftermove'; return 1");
         if ($folderusage<100) {
            $temphtml .= submit(-name=>"$lang_text{'copy'}",
                       -onClick=>"document.moveform.message_id.value='$messageid'; return 1");
         }
      }

      $html =~ s/\@\@\@MOVECONTROLS\@\@\@/$temphtml/g;

      if ($headers eq "all") {
         $temphtml = decode_mimewords($message{'header'});
         $temphtml = text2html($temphtml);
         $temphtml =~ s/\n([-\w]+?:)/\n<B>$1<\/B>/g;
      } else {
         $temphtml = "<B>$lang_text{'date'}:</B> $message{date}<BR>\n";

         $temphtml .= "<B>$lang_text{'from'}:</B> $from &nbsp;";
         my ($realname, $email, $escapedemail);
         if  ( $message{from} =~ /^"?(.+?)"?\s*<(.*)>$/ ) {
            ($realname, $email)=($1, $2);
         } elsif ( $message{from} =~ /<?(.*@.*)>?\s+\((.+?)\)/ ) {
            ($realname, $email)=($2, $1);
         } else {
            ($realname, $email)=($from, $from);
         }
         $realname=escapeURL($realname);
         $escapedemail=escapeURL($email);
         $temphtml .= "&nbsp;<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addaddress&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;realname=$realname&amp;email=$escapedemail\">".
                      "<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/imports.gif\" align=\"absmiddle\" border=\"0\" ALT=\"$lang_text{'importadd'} $email\">".
                      "</a>";

         if ($message{smtprelay} !~ /^\s*$/) {
            $temphtml .= "&nbsp;<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;priority=20&amp;rules=smtprelay&amp;include=include&amp;text=$message{smtprelay}&amp;destination=mail-trash&amp;enable=1\">".
                      "<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/blockrelay.gif\" align=\"absmiddle\" border=\"0\" ALT=\"$lang_text{'blockrelay'} $message{smtprelay}\">".
                      "</a>";
         }

         $temphtml .= "<BR>";

         if ($replyto) {
            $temphtml .= "<B>$lang_text{'replyto'}:</B> $replyto<BR>\n";
         }

         if ($to) {
            if ( length($to)>96 && param('receivers') ne "all" ) {
              $to=substr($to,0,90)." ".
		  "<a href=\"$base_url&amp;action=readmessage&amp;message_id=$escapedmessageid&amp;attmode=$attmode&amp;receivers=all&amp;\">".
		  "<b>.....</b>"."</a>";
            }
            $temphtml .= "<B>$lang_text{'to'}:</B> $to<BR>\n";
         }

         if ($cc) {
            if ( length($cc)>96 && param('receivers') ne "all" ) {
              $cc=substr($cc,0,90)." ".
		  "<a href=\"$base_url&amp;action=readmessage&amp;message_id=$escapedmessageid&amp;attmode=$attmode&amp;receivers=all&amp;\">".
		  "<b>.....</b>"."</a>";
            }
            $temphtml .= "<B>$lang_text{'cc'}:</B> $cc<BR>\n";
         }

         if ($subject) {
            $temphtml .= "<B>$lang_text{'subject'}:</B> $subject\n";
         }

         # enable download the whole message
         my $dlicon;
         if ($message{'header'}=~/X\-Mailer:\s+Open WebMail/) {
            $dlicon="downloads.ow.gif";
         } else {
            $dlicon="downloads.gif";
         }
         $temphtml .= "&nbsp;<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl/Unknown.msg?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=all\">".
                      "<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/$dlicon\" align=\"absmiddle\" border=\"0\" ALT=\"$lang_text{'download'} $subject.msg\">".
                      "</a>\n";
      }

      $html =~ s/\@\@\@HEADERS\@\@\@/$temphtml/g;

      if ($headers eq "all") {
         $temphtml = "<a href=\"$base_url&amp;action=readmessage&amp;message_id=$escapedmessageid&amp;attmode=$attmode&amp;headers=simple\">$lang_text{'simplehead'}</a>";
      } else {
         $temphtml = "<a href=\"$base_url&amp;action=readmessage&amp;message_id=$escapedmessageid&amp;attmode=$attmode&amp;headers=all\">$lang_text{'allhead'}</a>";
      }
      $html =~ s/\@\@\@HEADERSTOGGLE\@\@\@/$temphtml/g;

      if ( $#{$message{attachment}} >=0 ) {
         if ($attmode eq "all") {
            $temphtml = "<a href=\"$base_url&amp;action=readmessage&amp;message_id=$escapedmessageid&amp;headers=$headers&amp;attmode=simple\">$lang_text{'simpleattmode'}</a>";
         } else {
            $temphtml = "<a href=\"$base_url&amp;action=readmessage&amp;message_id=$escapedmessageid&amp;headers=$headers&amp;attmode=all\">$lang_text{'allattmode'}</a>";
         }
      } else {
         $temphtml="&nbsp";
      }
      $html =~ s/\@\@\@ATTMODETOGGLE\@\@\@/$temphtml/g;

      $temphtml=$body;
      if ( $attmode eq 'all' ) {
         $temphtml .= hr() if ( $#{$message{attachment}}>=0 );
      } else {
         $temphtml="" if ( $message{contenttype} =~ /^multipart/i );
      }

      foreach my $attnumber (0 .. $#{$message{attachment}}) {
         next unless (defined(%{$message{attachment}[$attnumber]}));

         if ( $attmode eq 'all' ) {
            if ( ${$message{attachment}[$attnumber]}{filename}=~
							/\.(jpg|jpeg|gif|png|bmp)$/i) {
               $temphtml .= image_att2table($message{attachment}, $attnumber, $escapedmessageid);
            } else {
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
            }

         } else {	# attmode==simple

            # handle case to skip to next text/html attachment
            if ( defined(%{$message{attachment}[$attnumber+1]}) &&
                 (${$message{attachment}[$attnumber+1]}{boundary} eq 
		  ${$message{attachment}[$attnumber]}{boundary}) ) {

               # skip to next text/html attachment in the same alternative group
               if ( (${$message{attachment}[$attnumber]}{subtype} =~ /alternative/i) &&
                 (${$message{attachment}[$attnumber+1]}{subtype} =~ /alternative/i) &&
                 (${$message{attachment}[$attnumber+1]}{contenttype} =~ /^text/i) ) {
                  next;
               }
               # skip to next attachment if this=unknow.txt and next=unknow.html
               if ( (${$message{attachment}[$attnumber]}{contenttype}=~ /^text\/plain/i ) &&
                    (${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\./ ) &&
                    (${$message{attachment}[$attnumber+1]}{contenttype} =~ /^text\/html/i)  &&
                    (${$message{attachment}[$attnumber+1]}{filename}=~ /^Unknown\./ ) ) {
                  next;
               }
            }

            # handle display of attachments in simple mode
            if ( ${$message{attachment}[$attnumber]}{contenttype}=~ /^text\/html/i ) {
               if ( ${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\./ ) {
                  # convert between gb and big5
                  if ( param('convert') eq 'b2g' ) {
                     my $big5 = html_att2table($message{attachment}, $attnumber, $escapedmessageid);
                     $temphtml .= b2g($big5);
                  } elsif ( param('convert') eq 'g2b' ) {
                     my $gb = html_att2table($message{attachment}, $attnumber, $escapedmessageid);
                     $temphtml .= g2b($gb);
                  } else {
                     $temphtml .= html_att2table($message{attachment}, $attnumber, $escapedmessageid);
                  }
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
               }
            } elsif ( ${$message{attachment}[$attnumber]}{contenttype}=~ /^text/i ) {
               if ( ${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\./ ) {
                  # convert between gb and big5
                  if ( param('convert') eq 'b2g' ) {
                     my $big5 = text_att2table($message{attachment}, $attnumber);
                     $temphtml .= b2g($big5);
                  } elsif ( param('convert') eq 'g2b' ) {
                     my $gb = text_att2table($message{attachment}, $attnumber);
                     $temphtml .= g2b($gb);
                  } else {
                     $temphtml .= text_att2table($message{attachment}, $attnumber);
                  }
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
               }
            } elsif ( ${$message{attachment}[$attnumber]}{contenttype}=~ /^message/i ) {
               # always show message/... attachment
               $temphtml .= message_att2table($message{attachment}, $attnumber, $style{"window_dark"});
            } elsif ( ${$message{attachment}[$attnumber]}{filename}=~ /\.(jpg|jpeg|gif|png|bmp)$/i) {
               # show image only if it is not referenced by other html
               if ( ${$message{attachment}[$attnumber]}{referencecount} ==0 ) {
                  $temphtml .= image_att2table($message{attachment}, $attnumber, $escapedmessageid);
               }
            } else {
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
            }

         }
      }

      $html =~ s/\@\@\@BODY\@\@\@/$temphtml/g;
      print $html;

      # if this is unread message, confirm to transmit read receipt if requested
      if ($message{status} !~ /r/i && $notificationto ne '') {
         print qq|<script language="JavaScript">\n<!--\n|,
               qq|replyreceiptconfirm('$base_url&amp;action=replyreceipt');\n|,
               qq|//-->\n</script>\n|;
      }

      printfooter();

      # fork a child to do the status update and headerdb update
      if ($message{status} !~ /r/i) {
         $|=1; 				# flush all output
         $SIG{CHLD} = sub { wait };	# handle zombie
         if ( fork() == 0 ) {		# child
            close(STDOUT);
            close(STDIN);

            my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
            filelock($folderfile, LOCK_EX|LOCK_NB) or exit 1;
            update_message_status($messageid, $message{status}."R", $headerdb, $folderfile);
            filelock("$folderfile", LOCK_UN);
            exit 0;
         }
      }

   } else {
       displayheaders();
   }
}


sub html_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $temphtml;

   if (${$r_attachment}{encoding} =~ /^quoted-printable/i) {
      $temphtml = decode_qp(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{encoding} =~ /^base64/i) {
      $temphtml = decode_base64(${${$r_attachment}{r_content}});
   } else {
      $temphtml = ${${$r_attachment}{r_content}};
   }

   $temphtml = html4nobase($temphtml);
   $temphtml = html4attachments($temphtml, $r_attachments, "$config{'ow_cgiurl'}/openwebmail-main.pl", "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
   $temphtml = html4mailto($temphtml, "$config{'ow_cgiurl'}/openwebmail-main.pl", "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
   $temphtml = html4disablejs($temphtml) if ($prefs{'disablejs'}==1);
   $temphtml = html2table($temphtml);

   return($temphtml);
}

sub text_att2table {
   my ($r_attachments, $attnumber)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $temptext;

   if (${$r_attachment}{encoding} =~ /^quoted-printable/i) {
      $temptext = decode_qp(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{encoding} =~ /^base64/i) {
      $temptext = decode_base64(${${$r_attachment}{r_content}});
   } else {
      $temptext = ${${$r_attachment}{r_content}};
   }
 
   # remove odds space or blank lines
   $temptext =~ s/(\r?\n){2,}/\n\n/g;
   $temptext =~ s/^\s+//;	
   $temptext =~ s/\n\s*$/\n/;
   return(text2html($temptext). "<BR>");
}

sub message_att2table {
   my ($r_attachments, $attnumber, $headercolor)=@_;
   $headercolor='#dddddd' if ($headercolor eq '');

   my $r_attachment=${$r_attachments}[$attnumber];
   my ($header, $body)=split(/\n\r*\n/, ${${$r_attachment}{r_content}}, 2);
   my ($contenttype, $encoding)=get_contenttype_encoding_from_header($header);
   
   $header=text2html($header);
   $header=simpleheader($header);

   $header=~s!Date: !<B>$lang_text{'date'}:</B> !i;
   $header=~s!From: !<B>$lang_text{'from'}:</B> !i;
   $header=~s!Reply-To: !<B>$lang_text{'replyto'}:</B> !i;
   $header=~s!To: !<B>$lang_text{'to'}:</B> !i;
   $header=~s!Cc: !<B>$lang_text{'cc'}:</B> !i;
   $header=~s!Subject: !<B>$lang_text{'subject'}:</B> !i;

   if ($contenttype =~ /^text/i) {
      if ($encoding =~ /^quoted-printable/i) {
          $body = decode_qp($body);
      } elsif ($encoding =~ /^base64/i) {
          $body = decode_base64($body);
      }
   }
   if ($contenttype =~ m#^text/html#i) { # convert into html table
      $body = html4nobase($body); 
      $body = html4disablejs($body) if ($prefs{'disablejs'}==1);
      $body = html2table($body); 
   } else {	
      $body = text2html($body);
   }

   # be aware the message header are keep untouched here 
   # in order to make it easy for further parsing
   my $temphtml=qq|<table width="100%" border=0 cellpadding=2 cellspacing=0>\n|.
                qq|<tr bgcolor=$headercolor><td>\n|.
                qq|<font size=-1>\n|.
                qq|$header\n|.
                qq|</font>\n|.
                qq|</td></tr>\n|.
                qq|\n\n|.
                qq|<tr><td>\n|.
                qq|$body\n|.
                qq|</td></tr></table>|;
   return($temphtml);
}

sub image_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $escapedfilename = escapeURL(${$r_attachment}{filename});
   my $attlen=lenstr(${$r_attachment}{contentlength});
   my $nodeid=${$r_attachment}{nodeid};
   my $disposition=${$r_attachment}{disposition};
   $disposition=~s/^(.).*$/$1/;

   my $temphtml .= qq|<table border="0" align="center" cellpadding="2">|.
                   qq|<tr><td valign="middle" bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: ${$r_attachment}{filename} &nbsp;($attlen)&nbsp;&nbsp;<font color=$style{"attachment_dark"}  size=-2>$nodeid $disposition</font>|.
                   qq|</td></tr><td valign="middle" bgcolor=$style{"attachment_light"} align="center">|.
                   qq|<IMG BORDER="0" SRC="$config{'ow_cgiurl'}/openwebmail-main.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid">|.
                   qq|</td></tr></table>|;
   return($temphtml);
}

sub misc_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $escapedfilename = escapeURL(${$r_attachment}{filename});
   my $attlen=lenstr(${$r_attachment}{contentlength});
   my $nodeid=${$r_attachment}{nodeid};
   my $disposition=${$r_attachment}{disposition};
   $disposition=~s/^(.).*$/$1/;

   my $temphtml .= qq|<table border="0" width="40%" align="center" cellpadding="2">|.
                   qq|<tr><td nowrap colspan="2" valign="middle" bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: ${$r_attachment}{filename}&nbsp;($attlen)&nbsp;&nbsp;<font color=$style{"attachment_dark"}  size=-2>$nodeid $disposition|.
                   qq|</td></tr>|.
                   qq|<tr><td nowrap valign="middle" bgcolor= $style{"attachment_light"} align="center">|.
                   qq|$lang_text{'type'}: ${$r_attachment}{contenttype}<br>|.
                   qq|$lang_text{'encoding'}: ${$r_attachment}{encoding}|.
                   qq|</td><td nowrap width="10%" valign="middle" bgcolor= $style{"attachment_light"} align="center">|.
                   qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid">$lang_text{'download'}</a>|.
                   qq|</td></tr></table>|;
   return($temphtml);
}

sub lenstr {
   my $len=$_[0];

   if ($len >= 10485760){
      $len = int(($len/1048576)+0.5) . "MB";
   } elsif ($len > 10240) {
      $len =  int(($len/1024)+0.5) . "KB";
   } else {
      $len = $len . "byte";
   }
   return ($len);
}

sub g2b {
   my $gb=$_[0];
   my $big5="";
   
   my $prog=(split(/\s+/, $config{'g2b_converter'}))[0];
   if (! -x $prog ) {
      openwebmailerror("GB to Big5 conversion is not available.<br>( $prog not found )");
   }

   my $tmpfile="/tmp/.tmpfile-$thissession";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);   # bypass taint check
   open (TMP, ">$tmpfile");
   print TMP $gb;
   close(TMP);

   # required on linux since it execute shell with real uid (nobody),
   # thus $config{'g2b_converter'} won't be able to read $tmpfile if mode not set
   chmod(0644, $tmpfile);	

   open(CONV, "$config{'g2b_converter'} < $tmpfile |");
   while (<CONV>) {
      $big5 .= $_;
   }
   close(CONV);

   unlink $tmpfile;
   return($big5);
}

sub b2g {
   my $big5=$_[0];
   my $gb="";
   my $prog=(split(/\s+/, $config{'b2g_converter'}))[0];

   if (! -x $prog ) {
      openwebmailerror("Big5 to GB conversion is not available.<br>( $prog not found )");
   }

   my $tmpfile="/tmp/.tmpfile-$thissession";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);   # bypass taint check
   open (TMP, ">$tmpfile");
   print TMP $big5;
   close(TMP);

   # required on linux since it execute shell with real uid (nobody),
   # thus $config{'b2g_converter'} won't be able to read $tmpfile if mode not set
   chmod(0644, $tmpfile);

   open(CONV, "$config{'b2g_converter'} < $tmpfile |");
   while (<CONV>) {
      $gb .= $_;
   }
   close(CONV);

   unlink $tmpfile;
   return($gb);
}

############### END READMESSAGE ##################

################## REPLYRECEIPT ##################
sub replyreceipt {
   printheader();
   my $messageid = param("message_id");
   my $nodeid = param("attachment_nodeid");
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();
   my @attr;
   my %HDB;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen (%HDB, $headerdb, undef);
   @attr=split(/@@@/, $HDB{$messageid});
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
   
   if ($attr[$_SIZE]>0) {
      my $header;

      # get message header
      open ($folderhandle, "+<$folderfile") or 
          openwebmailerror("$lang_err{'couldnt_open'} $folderfile!");
      seek ($folderhandle, $attr[$_OFFSET], 0) or openwebmailerror("$lang_err{'couldnt_seek'} $folderfile!");
      $header="";
      while (<$folderhandle>) {
         last if ($_ eq "\n" && $header=~/\n$/);
         $header.=$_;
      }
      close($folderhandle);

      # get notification-to 
      if ($header=~/^Disposition-Notification-To:\s?(.*?)$/im ) {
         my $to=$1;
         my $from=$prefs{'email'};

         my %userfrom=get_userfrom($virtualuser, $user, $userrealname, "$folderdir/.from.book");
         foreach (sort keys %userfrom) {
            if ($header=~/$_/) {
               $from=$_; last;
            }
         }
         my $realname=$userfrom{$from};

         my $date = localtime();
         my @datearray = split(/ +/, $date);
         if ($datearray[0] =~ /[A-Za-z,]/) {
            shift @datearray; # Get rid of the day of the week
         }
         $date="$month{$datearray[0]}/$datearray[1]/$datearray[3] $datearray[2]";

         $to =~ s/^"?(.+?)"?\s*<(.*)>$/$2/ ||
         $to =~ s/<?(.*@.*)>?\s+\((.+?)\)/$1/ ||
         $to =~ s/<(.+)>/$1/;

         $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts
         $from =~ s/['"]/ /g;  # Get rid of shell escape attempts 

         ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
         ($from =~ /^(.+)$/) && ($from = $1);
         ($to =~ /^(.+)$/) && ($to = $1);
         ($date =~ /^(.+)$/) && ($date = $1);

         open (SENDMAIL, "|" . $config{'sendmail'} . " -oem -oi -F '$realname' -f '$from' -t 1>&2") or
            openwebmailerror("$lang_err{'couldnt_open'} $config{'sendmail'}!");

         print SENDMAIL "From: $realname <$from>\n";
         print SENDMAIL "To: $to\n";
         if ($prefs{"replyto"}) {
            print SENDMAIL "Reply-To: ",$prefs{"replyto"},"\n";
         }
         print SENDMAIL "Subject: $lang_text{'read'} - $attr[$_SUBJECT]\n";
         print SENDMAIL "X-Mailer: Open WebMail $config{'version'} $config{'releasedate'}\n";
         print SENDMAIL "X-OriginatingIP: ".get_clientip()." ($user)\n";

         print SENDMAIL "MIME-Version: 1.0\n";
         print SENDMAIL "Content-Type: text/plain; charset=$lang_charset\n\n";

         print SENDMAIL "$lang_text{'yourmsg'}\n\n";
         print SENDMAIL "  $lang_text{'to'}: $attr[$_TO]\n";
         print SENDMAIL "  $lang_text{'subject'}: $attr[$_SUBJECT]\n";
         print SENDMAIL "  $lang_text{'delivered'}: $attr[$_DATE]\n\n";
         print SENDMAIL "$lang_text{'wasreadon1'} $date $lang_text{'wasreadon2'}\n\n";
         print SENDMAIL $prefs{"signature"}, "\n\n" if (defined($prefs{"signature"}));

         close(SENDMAIL) or
            openwebmailerror("$lang_err{'sendmail_error'}");
      }
      # close the window that is processing confirm-reading-receipt 
      print qq|<script language="JavaScript">\n|,
            qq|<!--\n|,
            qq|window.close();\n|,
            qq|//-->\n|,
            qq|</script>\n|;
   } else {
      $messageid = str2html($messageid);
      print "What the heck? Message $messageid seems to be gone!";
   }
   printfooter();   
}
################ END REPLYRECEIPT ################

############### COMPOSEMESSAGE ###################
# 7 composetype: continue(used after adding attachment), 
#                reply, replyall, forward, forwardasatt, editdraft or none(newmail)
sub composemessage {
   no strict 'refs';
   my $html = '';
   my $temphtml;
   my ($savedattsize, $r_attnamelist, $r_attfilelist);

   open (COMPOSEMESSAGE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/composemessage.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/composemessage.template!");
   while (<COMPOSEMESSAGE>) {
      $html .= $_;
   }
   close (COMPOSEMESSAGE);

   $html = applystyle($html);
   
   if ( param("deleteattfile") ne '' ) { # user click 'del' link
      my $deleteattfile=param("deleteattfile");

      $deleteattfile =~ s/\///g;  # just in case someone gets tricky ...
      ($deleteattfile =~ /^(.+)$/) && ($deleteattfile = $1);   # bypass taint check
      # only allow to delete attfiles belongs the $thissession
      if ($deleteattfile=~/^$thissession/) {
         unlink ("$config{'ow_etcdir'}/sessions/$deleteattfile");
      }
      ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();

   } elsif (defined(param($lang_text{'add'}))) { # user press 'add' button
      ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();
      my $attachment = param("attachment");
      my $attname = $attachment;
      my $attcontents = '';

      if ($attachment) {
         if ( ($config{'attlimit'}) && ( ( $savedattsize + (-s $attachment) ) > ($config{'attlimit'} * 1048576) ) ) {
            openwebmailerror ("$lang_err{'att_overlimit'} $config{'attlimit'} MB!");
         }
         my $content_type;
         # Convert :: back to the ' like it should be.
         $attname =~ s/::/'/g;
         # Trim the path info from the filename
         $attname =~ s/^.*\\//;
         $attname =~ s/^.*\///;
         $attname =~ s/^.*://;

         if (defined(uploadInfo($attachment))) {
            $content_type = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
         } else {
            $content_type = 'application/octet-stream';
         }

         my $attserial = time();
         open (ATTFILE, ">$config{'ow_etcdir'}/sessions/$thissession-att$attserial");
         print ATTFILE "Content-Type: ", $content_type,";\n";
         print ATTFILE "\tname=\"$attname\"\nContent-Transfer-Encoding: base64\n\n";
         while (read($attachment, $attcontents, 600*57)) {
            $attcontents=encode_base64($attcontents);
            $savedattsize += length($attcontents);
            print ATTFILE $attcontents;
         }
         close ATTFILE;

         $attname = str2html($attname);
         $attname =~ s/^(.*)$/<em>$1<\/em>/;
         push (@{$r_attnamelist}, "$attname");
         push (@{$r_attfilelist}, "$thissession-att$attserial");
      }

   # usr press 'send' button but no receiver, keep editing
   } elsif ( defined(param($lang_text{'send'})) &&
             param("to") eq '' && param("cc") eq '' && param("bcc") eq '' ) {
      ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();

   } else {	# this is new message, remove previous aged attachments
      deleteattachments();
   }

   my $messageid = param("message_id");
   my %message;
   my $attnumber;
   my $from ='';
   my $to = '';
   my $cc = '';
   my $bcc = '';
   my $replyto = '';
   my $subject = '';
   my $body = '';

   my $composetype = param("composetype");

   my %userfrom=get_userfrom($virtualuser, $user, $userrealname, "$folderdir/.from.book");

   if ($userfrom{$prefs{'email'}} ne "") {
      $from=qq|"$userfrom{$prefs{'email'}}" <$prefs{'email'}>|;
   } else {
      $from=qq|$prefs{'email'}|;
   }

   if ($composetype) {
      $to = param("to") || '';
      $cc = param("cc") || '';
      $bcc = param("bcc") || '';
      $replyto = param("replyto") || '';
      $subject = param("subject") || '';
      $body = param("body") || '';

      if ($composetype eq "reply" || $composetype eq "replyall" ||
          $composetype eq "forward" || $composetype eq "editdraft" ) {

         if ($composetype eq "forward" || $composetype eq "editdraft") {
            %message = %{&getmessage($messageid, "all")};
         } else {
            %message = %{&getmessage($messageid, "")};
         }

         my $fromemail=$prefs{'email'};
         foreach (keys %userfrom) {
            if ($composetype eq "editdraft") {
               if ($message{'from'}=~/$_/) {
                  $fromemail=$_; last;
               }
            } else {	# reply/replyall/forward
               if ($message{'to'}=~/$_/ || $message{'cc'}=~/$_/ ) {
                  $fromemail=$_; last;
               }
            }
         }
         if ($userfrom{$fromemail}) {
            $from=qq|"$userfrom{$fromemail}" <$fromemail>|;
         } else {
            $from=qq|$fromemail|;
         }

         # make the body for new mesage from original mesage for different contenttype
         #
         # handle the messages generated if sendmail is set up to send MIME error reports
         if ($message{contenttype} =~ /^multipart\/report/i) {
            foreach my $attnumber (0 .. $#{$message{attachment}}) {
               if (defined(${${$message{attachment}[$attnumber]}{r_content}})) {
                  $body .= ${${$message{attachment}[$attnumber]}{r_content}};
                  shift @{$message{attachment}};
               }
            }
         } elsif ($message{contenttype} =~ /^multipart/i) {
            # If the first attachment is text, 
            # assume it's the body of a message in multi-part format
            if ( defined(${$message{attachment}[0]}{contenttype}) &&
                 ${$message{attachment}[0]}{contenttype} =~ /^text\/plain/i ) {
               if (${$message{attachment}[0]}{encoding} =~ /^quoted-printable/i) {
                  ${${$message{attachment}[0]}{r_content}} =
               		decode_qp(${${$message{attachment}[0]}{r_content}});
               } elsif (${$message{attachment}[$attnumber]}{encoding} =~ /^base64/i) {
                  ${${$message{attachment}[$attnumber]}{r_content}} = 
			decode_base64(${${$message{attachment}[$attnumber]}{r_content}});
               }
               $body = ${${$message{attachment}[0]}{r_content}};
               # remove this text attachment from the message's attachemnt list
               shift @{$message{attachment}};
            } else {
               $body = '';
            }
         } else {
            $body = $message{"body"} || '';
            # handle mail programs that send the body encoded
            if ($message{contenttype} =~ /^text/i) {
               if ($message{encoding} =~ /^quoted-printable/i) {
                  $body= decode_qp($body);
               } elsif ($message{encoding} =~ /^base64/i) {
                  $body= decode_base64($body);
               }
            }
            # convert to pure text since user is going to edit it
            if ($message{contenttype} =~ /^text\/html/i) {
               $body= html2txt($body);
            }
         }

         # remove odds space or blank lines from body
         $body =~ s/(\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;	
         $body =~ s/\s+$//;

         if ( $composetype eq "reply" || $composetype eq "replyall" ) {
            $subject = $message{"subject"} || '';
            $subject = "Re: " . $subject unless ($subject =~ /^re:/i);

            if (defined($message{"replyto"})) {
               $to = $message{"replyto"} || '';
            } else {
               $to = $message{"from"} || '';
            }
            if ($composetype eq "replyall") {
               $to .= "," . $message{"to"} if (defined($message{"to"}));
               $to .= "," . $message{"cc"} if (defined($message{"cc"}));
               # remove tab or space surrounding comma 
               # in case old 'to' or 'cc' has tab which make snedmail unhappy
               $to=join(",", split(/\s*,\s*/,$to));
            }
            $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));
            if ($body =~ /[^\s]/) {
               $body =~ s/\n/\n\> /g;
               $body = "> " . $body . "\n\n";
            }

         } elsif ($composetype eq "forward" || $composetype eq "editdraft") {
            # carry attachments from old mesage to the new one
            if (defined(${$message{attachment}[0]}{header})) {
               my $attserial=time();
               ($attserial =~ /^(.+)$/) && ($attserial = $1);   # bypass taint check
               foreach my $attnumber (0 .. $#{$message{attachment}}) {
                  $attserial++;
                  open (ATTFILE, ">$config{'ow_etcdir'}/sessions/$thissession-att$attserial") or 
                     openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$thissession-att$attserial!");
                  print ATTFILE ${$message{attachment}[$attnumber]}{header}, "\n\n", ${${$message{attachment}[$attnumber]}{r_content}};
                  close ATTFILE;
               }
               ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();
            }

            $subject = $message{"subject"} || '';

            if ($composetype eq "editdraft") {
               $to = $message{"to"} if (defined($message{"to"}));
               $cc = $message{"cc"} if (defined($message{"cc"}));
               $bcc = $message{"bcc"} if (defined($message{"bcc"}));
               if (defined($message{"replyto"})) {
                  $replyto = $message{"replyto"} 
               } else {
                  $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));
               }
            } elsif ($composetype eq "forward") {
               $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));
               $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);
               $body = "\n\n------------- Forwarded message -------------\n$body" if ($body =~ /[^\s]/);
            }
         }

      } elsif ($composetype eq 'forwardasatt') {
         my $messageid = param("message_id");
         my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
         my $folderhandle=FileHandle->new();
         my $atthandle=FileHandle->new();

         filelock($folderfile, LOCK_SH|LOCK_NB) or
            openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
         update_headerdb($headerdb, $folderfile);

         my @attr=get_message_attributes($messageid, $headerdb);

         my $fromemail=$prefs{'email'};
         foreach (keys %userfrom) {
            if ($attr{$_TO}=~/$_/) {
               $fromemail=$_; last;
            }
         }
         if ($userfrom{$fromemail}) {
            $from=qq|"$userfrom{$fromemail}" <$fromemail>|;
         } else {
            $from=qq|$fromemail|;
         }

         open($folderhandle, "$folderfile");
         my $attserial=time();
         ($attserial =~ /^(.+)$/) && ($attserial = $1);   # bypass taint check
         open ($atthandle, ">$config{'ow_etcdir'}/sessions/$thissession-att$attserial") or
            openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$thissession-att$attserial!");
         print $atthandle "Content-Type: message/rfc822;\n",
                          "Content-Disposition: attachment; filename=\"Forward.msg\"\n\n";
         copyblock($folderhandle, $attr[$_OFFSET], $atthandle, tell($atthandle), $attr[$_SIZE]);
         close $atthandle;
         close($folderhandle);

         filelock($folderfile, LOCK_UN);

         ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();

         $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));
         $subject = $attr[$_SUBJECT];
         $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);
         $body = "\n\n# Message forwarded as attachment\n";
      }     

   }

   # convert between gb and big5
   if ( param('convert') eq 'b2g' ) {
      $subject= b2g($subject);
      $body= b2g($body);
   } elsif ( param('convert') eq 'g2b' ) {
      $subject= g2b($subject);
      $body= g2b($body);
   }

   if ( (defined($prefs{"signature"})) && 
        ($composetype ne 'continue') &&
        ($composetype ne 'editdraft') ) {
      $body .= "\n\n".$prefs{"signature"};
   }

   printheader();
   
   $temphtml = "<a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;firstmessage=$firstmessage\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";
   if ($prefs{'language'} eq 'zh_CN.GB2312' ) {
       $temphtml .= " &nbsp; &nbsp; ".
                    "<a href=\"javascript:convert_b2g()\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif\" border=\"0\" ALT=\"Big5 to GB\"></a> ".
                    "<a href=\"javascript:convert_g2b()\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif\" border=\"0\" ALT=\"GB to Big5\"></a>";
   } elsif ($prefs{'language'} eq 'zh_TW.Big5' ) {
       $temphtml .= " &nbsp; &nbsp; ".
                    "<a href=\"javascript:convert_g2b()\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif\" border=\"0\" ALT=\"GB to Big5\"></a> ".
                    "<a href=\"javascript:convert_b2g()\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif\" border=\"0\" ALT=\"Big5 to GB\"></a>";
   }

   $html =~ s/\@\@\@BACKTOFOLDER\@\@\@/$temphtml/g;

   $temphtml = start_multipart_form(-name=>'composeform');

   $temphtml .= hidden(-name=>'action',
                       -default=>'sendmessage',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'composetype',
                       -default=>'continue',
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
   $temphtml .= hidden(-name=>'firstmessage',
                       -default=>$firstmessage,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');
   $temphtml .= hidden(-name=>'deleteattfile',
                       -default=>'',
                       -override=>'1');
   $temphtml .= hidden(-name=>'convert',
                       -default=>'',
                       -override=>'1');

   if (param("message_id")) {
      $temphtml .= hidden(-name=>'message_id',
                          -default=>param("message_id"),
                          -override=>'1');
   }
   $html =~ s/\@\@\@STARTCOMPOSEFORM\@\@\@/$temphtml/g;

   my @fromlist=();
   foreach (sort keys %userfrom) {
      if ($userfrom{$_}) {
         push(@fromlist, qq|"$userfrom{$_}" <$_>|);
      } else {
         push(@fromlist, qq|$_|);
      }
   }
   $temphtml = popup_menu(-name=>'from',
                          -"values"=>\@fromlist,
                          -default=>$from,
                          -override=>'1');

   $html =~ s/\@\@\@FROMMENU\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'to',
                         -default=>$to,
                         -size=>'70',
                         -override=>'1');
   $html =~ s/\@\@\@TOFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'cc',
                         -default=>$cc,
                         -size=>'70',
                         -override=>'1');
   $html =~ s/\@\@\@CCFIELD\@\@\@/$temphtml/g;
          
   $temphtml = textfield(-name=>'bcc',
                         -default=>$bcc,
                         -size=>'70',
                         -override=>'1');
   $html =~ s/\@\@\@BCCFIELD\@\@\@/$temphtml/g;
 
   $temphtml = textfield(-name=>'replyto',
                         -default=>$replyto,
                         -size=>'70',
                         -override=>'1');
   $html =~ s/\@\@\@REPLYTOFIELD\@\@\@/$temphtml/g;
   
   # table of attachment list 
   if ($#{$r_attnamelist}>=0) {
      $temphtml = "<table cellspacing='0' cellpadding='0' width='70%'><tr valign='bottom'>\n";

      $temphtml .= "<td><table cellspacing='0' cellpadding='0'>\n";
      for (my $i=0; $i<=$#{$r_attnamelist}; $i++) {
         my $attsize=int((-s "$config{'ow_etcdir'}/sessions/${$r_attfilelist}[$i]")/1024);
         $temphtml .= "<tr valign=top>".
                      "<td><a href=\"$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;action=viewattfile&amp;attfile=${$r_attfilelist}[$i]\">${$r_attnamelist}[$i]</a></td>".
                      "<td nowrap align='right'>&nbsp;$attsize KB &nbsp;</td>".
                      "<td nowrap><a href=\"javascript:DeleteAttFile('${$r_attfilelist}[$i]')\">[$lang_text{'delete'}]</a></td>".
                      "</tr>\n";
      }
      $temphtml .= "</table></td>\n";

      $temphtml .= "<td align='right'>\n";
      if ( $savedattsize ) {
         $temphtml .= "<em>" . int($savedattsize/1024) . "KB";
         $temphtml .= " $lang_text{'of'} $config{'attlimit'} MB" if ( $config{'attlimit'} );
         $temphtml .= "</em>";
      }
      $temphtml .= "</td>";

      $temphtml .= "</tr></table>\n";
   } else {
      $temphtml="";
   }

   $temphtml .= filefield(-name=>'attachment',
                         -default=>'',
                         -size=>'60',
                         -override=>'1',
                         -tabindex=>'-1');
   $temphtml .= submit(-name=>"$lang_text{'add'}",
                       -value=>"$lang_text{'add'}",
                       -tabindex=>'-1'
                      );
   $html =~ s/\@\@\@ATTACHMENTFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'subject',
                         -default=>$subject,
                         -size=>'60',
                         -override=>'1');
   $html =~ s/\@\@\@SUBJECTFIELD\@\@\@/$temphtml/g;


   $temphtml = checkbox(-name=>'confirmreading',
                        -value=>'1',
                        -label=>'');

   $html =~ s/\@\@\@CONFIRMREADINGCHECKBOX\@\@\@/$temphtml/;

   $temphtml = textarea(-name=>'body',
                        -default=>$body,
                        -rows=>$prefs{'editrows'}||'20',
                        -columns=>$prefs{'editcolumns'}||'78',
                        -wrap=>'hard',
                        -override=>'1');
   $html =~ s/\@\@\@BODYAREA\@\@\@/$temphtml/g;

   $temphtml = submit(-name=>"$lang_text{'send'}",
                      -value=>"$lang_text{'send'}",
                      -onClick=>'return sendcheck();',
                      -override=>'1');
   $html =~ s/\@\@\@SENDBUTTON\@\@\@/$temphtml/g;

   $temphtml = submit("$lang_text{'savedraft'}");
   $html =~ s/\@\@\@SAVEDRAFTBUTTON\@\@\@/$temphtml/g;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/spellcheck.pl",
                          -name=>'spellcheckform',
                          -target=>'SpellChecker').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'form',
                      -default=>'',
                      -override=>'1').
               hidden(-name=>'field',
                      -default=>'',
                      -override=>'1').
               hidden(-name=>'string',
                      -default=>'',
                      -override=>'1');
   $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@/$temphtml/g;

   $temphtml = popup_menu(-name=>'dictionary',
                          -"values"=>$config{'spellcheck_dictionaries'},
                          -default=>$prefs{'dictionary'},
                          -override=>'1');

   $html =~ s/\@\@\@DICTIONARYMENU\@\@\@/$temphtml/;

   $temphtml = submit(-name=>'spellcheckbutton', 
                      -value=> $lang_text{'spellcheck'},
                      -onClick=>'spellcheck();',
                      -override=>'1');
   $html =~ s/\@\@\@SPELLCHECKBUTTON\@\@\@/$temphtml/g;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl");
   
   if (param("message_id")) {
      $temphtml .= hidden(-name=>'action',
                          -default=>'readmessage',
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
      $temphtml .= hidden(-name=>'headers',
                          -default=>$prefs{"headers"} || 'simple',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>param("message_id"),
                          -override=>'1');
   } else {
      $temphtml .= hidden(-name=>'action',
                          -default=>'displayheaders',
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
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
   }
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/g;

   $temphtml = submit("$lang_text{'cancel'}");
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/g;

   $html =~ s/\@\@\@SESSIONID\@\@\@/$thissession/g;

   print $html;

   printfooter();
}
############# END COMPOSEMESSAGE #################

############### SENDMESSAGE ######################
sub sendmessage {
   no strict 'refs';
   # user press 'add' button or click 'delete' link
   if (defined(param($lang_text{'add'})) 
    || param("deleteattfile") ne '' 
    || param("convert") ne ''
    || ( defined(param($lang_text{'send'}))
         && param("to") eq '' 
         && param("cc") eq '' 
         && param("bcc") eq '') ) {
      composemessage();

   } else {
      my $localtime = scalar(localtime);
      my $date = localtime();
      my @datearray = split(/ +/, $date);
      $date = "$datearray[0], $datearray[2] $datearray[1] $datearray[4] $datearray[3] ".dst_adjust($config{'timeoffset'});

      my %userfrom=get_userfrom($virtualuser, $user, $userrealname, "$folderdir/.from.book");
      my $from=param('from') || $prefs{'email'};
      my $realname = $userfrom{$prefs{'email'}} || '';
      if  ( $from =~ /^"?(.+?)"?\s*<(.*)>$/ ) {
         ($realname, $from)=($1, $2);
      } elsif ( $from =~ /<?(.*@.*)>?\s+\((.+?)\)/ ) {
         ($realname, $from)=($2, $1);
      } elsif ( $from =~ /\s*(.+)@(.+)\s*/ ) {
         $realname="$1" if ($realname eq "");
         $from="$1\@$2";
      }
      $from =~ s/['"]/ /g;  # Get rid of shell escape attempts
      $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts
      ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
      ($from =~ /^(.+)$/) && ($from = $1);

      my $boundary = "----=OPENWEBMAIL_ATT_" . rand();
      my $to = param("to");
      my $cc = param("cc");
      my $bcc = param("bcc");
      my $replyto = param("replyto") || $prefs{"replyto"};
      my $subject = param("subject");
      my $inreplyto = param("message_id");
      my $references = "";
      my $folder = param("folder");
      my $confirmreading = param("confirmreading");
      my $body = param("body");
      my $oldstatus = "";

      $body =~ s/\r//g;  # strip ^M characters from message. How annoying!

      if ($inreplyto) {
         my %HDB;
         my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);

         dbmopen(%HDB, $headerdb, 0600);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);

         if (defined($HDB{$inreplyto})) {
            my @oldheaders=split(/@@@/, $HDB{$inreplyto});
            $oldstatus = $oldheaders[$_STATUS];
            if ($oldheaders[$_REFERENCES]) { 
               $references = $oldheaders[$_REFERENCES];
            } else { 
               $references = $inreplyto;
            }
         }

         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
         dbmclose(%HDB);
      }

      my $attachment = param("attachment");
      if ( $attachment ) {
         my $savedattsize=(getattlistinfo())[0];
         if ( ($config{'attlimit'}) && ( ( $savedattsize + (-s $attachment) ) > ($config{'attlimit'} * 1048576) ) ) {
            openwebmailerror ("$lang_err{'att_overlimit'} $config{'attlimit'} MB!");
         }
      }
      my $attname = $attachment;
      # Convert :: back to the ' like it should be.
      $attname =~ s/::/'/g;
      # Trim the path info from the filename
      $attname =~ s/^.*\\//;
      $attname =~ s/^.*\///;
      $attname =~ s/^.*://;

      my @attfilelist=();
      opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");
      while (defined(my $currentfile = readdir(SESSIONSDIR))) {
         if ($currentfile =~ /^($thissession-att\d+)$/) {
            push (@attfilelist, "$config{'ow_etcdir'}/sessions/$1");
         }
      }
      closedir (SESSIONSDIR);

      my $do_savefolder=1;
      my $savefolder_errorstr="";
      my $do_sendmail=1;
      my $sendmail_errorstr="";
      my ($savefolder, $savefile, $savedb);

      if (defined(param($lang_text{'savedraft'}))) { # save message to draft folder
         $savefolder = 'saved-drafts';
         $do_sendmail=0;
      } else {				# sent message and save it to sent folder
         open (SENDMAIL, "|" . $config{'sendmail'} . " -oem -oi -F '$realname' -f '$from' -t 1>&2") or
            openwebmailerror("$lang_err{'couldnt_open'} $config{'sendmail'}!");
         $savefolder = 'sent-mail';
         $do_sendmail=1;
      }
      ($savefile, $savedb)=get_folderfile_headerdb($user, $savefolder);

      if ( ! -f $savefile) {
         if (open (FOLDER, ">$savefile")) {
            close (FOLDER);
            $do_savefolder=1;
         } else {
            $savefolder_errorstr="$lang_err{'couldnt_open'} $savefile!";
            $do_savefolder=0;
            if ($do_savefolder==0 && $do_sendmail==0) {
               openwebmailerror($savefolder_errorstr);
            }
         }
      }

      my $messagestart=0;
      my $messagesize=0;

      if  ($folderusage>=100) {
         $do_savefolder=0;
      } else {
         if (filelock($savefile, LOCK_EX|LOCK_NB)) {
            update_headerdb($savedb, $savefile);

            if ( $savefolder eq 'saved-drafts' && defined(param("message_id")) ) {
               my $removeoldone=0;
               my $messageid=param("message_id");
               my %HDB;

               filelock("$savedb$config{'dbm_ext'}", LOCK_EX);
               dbmopen(%HDB, $savedb, undef);
               if (defined($HDB{$messageid})) {
                  my @oldheaders=split(/@@@/, $HDB{$messageid});
                  if ($oldheaders[$_SUBJECT] eq $subject) {
                     $removeoldone=1;
                  }
               }
               dbmclose(%HDB);
               filelock("$savedb$config{'dbm_ext'}", LOCK_UN);

               if ($removeoldone) {
                  my @ids;
                  push (@ids, $messageid);
                  operate_message_with_ids("delete", \@ids, $savefile, $savedb);
               }
            }

            if (open (FOLDER, ">>$savefile") ) {
               $messagestart=tell(FOLDER);
            } else {
               $savefolder_errorstr="$lang_err{'couldnt_open'} $savefile!";
               $do_savefolder=0;
            }
         } else {
            $savefolder_errorstr="$lang_err{'couldnt_lock'} $savefile!";
            $do_savefolder=0;
         }
      }

      # nothing to do, return error msg immediately
      if ($do_savefolder==0 && $do_sendmail==0) {
         openwebmailerror($savefolder_errorstr);
      }

      # Add a 'From ' as the message delimeter before save a message
      # into sent-mail/saved-drafts folder 
      print FOLDER "From $user $localtime\n" if ($do_savefolder);

      my $tempcontent="";
      $tempcontent .= "From: $realname <$from>\n";
      $tempcontent .= "To: $to\n";
      $tempcontent .= "CC: $cc\n" if ($cc);
      $tempcontent .= "Bcc: $bcc\n" if ($bcc);
      $tempcontent .= "Reply-To: ".$replyto."\n" if ($replyto);
      $tempcontent .= "Subject: $subject\n";
      $tempcontent .= "In-Reply-To: " . $inreplyto . "\n" if ($inreplyto);
      $tempcontent .= "References: " . $references . "\n" if ($references);
      $tempcontent .= "X-Mailer: Open WebMail $config{'version'} $config{'releasedate'}\n";
      $tempcontent .= "X-OriginatingIP: ".get_clientip()." ($user)\n";
      if ($confirmreading) {
         if ($replyto) {
            $tempcontent .= "X-Confirm-Reading-To: $replyto\n";
            $tempcontent .= "Disposition-Notification-To: $replyto\n";
         } else {
            $tempcontent .= "X-Confirm-Reading-To: $from\n";
            $tempcontent .= "Disposition-Notification-To: $from\n";
         }
      }
      print SENDMAIL $tempcontent if ($do_sendmail);
      print FOLDER     $tempcontent if ($do_savefolder);

      # fake a messageid for the local copy in sent folder
      my $messageid="<OpenWebMail-saved-".rand().">";
      print FOLDER     "Message-Id: $messageid\nDate: $date\nStatus: R\n" if ($do_savefolder);

      print SENDMAIL "MIME-Version: 1.0\n" if ($do_sendmail);
      print FOLDER     "MIME-Version: 1.0\n" if ($do_savefolder);

      my $contenttype;
      if ($attachment || $#attfilelist>=0 ) {
         $contenttype="multipart/mixed;";

         $tempcontent = "";
         $tempcontent .= "Content-Type: multipart/mixed;\n";
         $tempcontent .= "\tboundary=\"$boundary\"\n\n";
         $tempcontent .= "This is a multi-part message in MIME format.\n\n";
         $tempcontent .= "--$boundary\n";
         $tempcontent .= "Content-Type: text/plain; charset=$lang_charset\n\n";

         print SENDMAIL $tempcontent if ($do_sendmail);
         print FOLDER   $tempcontent if ($do_savefolder);

         print SENDMAIL "$body\n" if ($do_sendmail);
         $body =~ s/^From />From /gm;
         print FOLDER   "$body\n" if ($do_savefolder);

         my $buff='';
         foreach (@attfilelist) {
            print SENDMAIL "\n--$boundary\n" if ($do_sendmail);
            print FOLDER   "\n--$boundary\n" if ($do_savefolder);
            open(ATTFILE, $_);

            while (read(ATTFILE, $buff, 32768)) {
               print SENDMAIL $buff if ($do_sendmail);
               print FOLDER   $buff if ($do_savefolder);
            }
            close(ATTFILE);
         }

         print SENDMAIL "\n" if ($do_sendmail);
         print FOLDER   "\n" if ($do_savefolder);

         if ($attachment) {
            my $attcontenttype;
            if (defined(uploadInfo($attachment))) {
               $attcontenttype = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
            } else {
               $attcontenttype = 'application/octet-stream';
            }
            $tempcontent ="";
            $tempcontent .= "--$boundary\nContent-Type: $attcontenttype;\n";
            $tempcontent .= "\tname=\"$attname\"\nContent-Transfer-Encoding: base64\n\n";

            print SENDMAIL $tempcontent if ($do_sendmail);
            print FOLDER   $tempcontent if ($do_savefolder);
            
            while (read($attachment, $buff, 600*57)) {
               $tempcontent=encode_base64($buff);
               print SENDMAIL $tempcontent if ($do_sendmail);
               print FOLDER   $tempcontent if ($do_savefolder);
            }

            print SENDMAIL "\n" if ($do_sendmail);
            print FOLDER   "\n" if ($do_savefolder);
         }
         print SENDMAIL "--$boundary--" if ($do_sendmail);
         print FOLDER   "--$boundary--" if ($do_savefolder);

         print SENDMAIL "\n" if ($do_sendmail);
         print FOLDER   "\n\n" if ($do_savefolder);

      } else {
         $contenttype="text/plain; charset=$lang_charset";

         print SENDMAIL "Content-Type: text/plain; charset=$lang_charset\n\n", $body, "\n" if ($do_sendmail);
         $body =~ s/^From />From /gm;
         print FOLDER   "Content-Type: text/plain; charset=$lang_charset\n\n", $body, "\n\n" if ($do_savefolder);
      }

      $messagesize=tell(FOLDER)-$messagestart if ($do_savefolder);
      close(FOLDER);
      if ($do_sendmail) {
         close(SENDMAIL) or $sendmail_errorstr=$lang_err{'sendmail_error'};
      }
      
      deleteattachments();

      # fork a child to do the status update (mark message as answered) and headerdb update
      if (($inreplyto) && ($oldstatus !~ /a/i)) {
         $|=1; 				# flush all output
         $SIG{CHLD} = sub { wait };	# handle zombie
         if ( fork() == 0 ) {		# child
            close(STDOUT);
            close(STDIN);

            my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
            filelock($folderfile, LOCK_EX|LOCK_NB) or exit 1;
            update_message_status($inreplyto, $oldstatus."A", $headerdb, $folderfile);
            filelock("$folderfile", LOCK_UN);
            exit 0;
         }
      }
      
      if ($do_savefolder) {
         my @attr;
         my @datearray = split(/\s+/, $date);
         if ($datearray[0] =~ /[A-Za-z,]/) {
            shift @datearray; # Get rid of the day of the week
         }

         $attr[$_OFFSET]=$messagestart;
         $attr[$_TO]=$to;
         $attr[$_FROM]="$realname <$from>";
         # we store localtime on dbm, so day offset is not needed
         $attr[$_DATE]="$month{$datearray[1]}/$datearray[0]/$datearray[2] $datearray[3]";
         $attr[$_SUBJECT]=$subject;
         $attr[$_CONTENT_TYPE]=$contenttype;
         $attr[$_STATUS]="R";
         $attr[$_SIZE]=$messagesize;

         my %HDB;
         filelock("$savedb$config{'dbm_ext'}", LOCK_EX);
         dbmopen(%HDB, $savedb, 0600);
         $HDB{$messageid}=join('@@@', @attr);
         $HDB{'ALLMESSAGES'}++;
         $HDB{'METAINFO'}=metainfo($savefile);
         dbmclose(%HDB);
         filelock("$savedb$config{'dbm_ext'}", LOCK_UN);

         filelock($savefile, LOCK_UN);
      }

      if ($sendmail_errorstr) {
         openwebmailerror($sendmail_errorstr);
      } elsif ($savefolder_errorstr) {
         openwebmailerror($savefolder_errorstr);
      } else {	
         # call getfolders to recalc used quota
         getfolders(\@validfolders, \$folderusage, 0); 

         displayheaders();
      }
   }
}
############## END SENDMESSAGE ###################

################ VIEWATTACHMENT ##################
sub viewattachment {	# view attachments inside a message
   my $messageid = param("message_id");
   my $nodeid = param("attachment_nodeid");
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();

   filelock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   update_headerdb($headerdb, $folderfile);
   open($folderhandle, "$folderfile");
   my $r_block= get_message_block($messageid, $headerdb, $folderhandle);
   close($folderhandle);
   filelock($folderfile, LOCK_UN);

   if ( !defined(${$r_block}) ) {
      printheader();
      $messageid = str2html($messageid);
      print "What the heck? Message $messageid seems to be gone!";
      printfooter();
      return;
   }

   if ( $nodeid eq 'all' ) { 
      # return whole msg as an message/rfc822 object
      my $subject = (get_message_attributes($messageid, $headerdb))[$_SUBJECT];
      $subject =~ s/\s+/_/g;
      my $length = length(${$r_block});
      # disposition:attachment default to save
      print qq|Content-Length: $length\n|,
            qq|Content-Transfer-Coding: binary\n|,
            qq|Connection: close\n|,
            qq|Content-Type: message/rfc822; name="$subject.msg"\n|;

      # ugly hack since ie5.5 is broken with disposition: attchment
      if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
         print qq|Content-Disposition: attachment; filename="$subject.msg"\n|;
      }
      print qq|\n|, ${$r_block};

   } else {
      # return a specific attachment
      my ($header, $body, $r_attachments)=parse_rfc822block($r_block, "0", $nodeid);
      undef(${$r_block});
      undef($r_block);

      my $r_attachment;
      for (my $i=0; $i<=$#{$r_attachments}; $i++) {
         if ( ${${$r_attachments}[$i]}{nodeid} eq $nodeid ) {
            $r_attachment=${$r_attachments}[$i];
         }
      }

      if (defined($r_attachment)) {
         my $content;

         if (${$r_attachment}{encoding} =~ /^base64$/i) {
            $content = decode_base64(${${$r_attachment}{r_content}});
         } elsif (${$r_attachment}{encoding} =~ /^quoted-printable$/i) {
            $content = decode_qp(${${$r_attachment}{r_content}});
#         } elsif (${$r_attachment}{encoding} =~ /^uuencode$/i) {
#            $content = uudecode(${${$r_attachment}{r_content}});
         } else { ## Guessing it's 7-bit, at least sending SOMETHING back! :)
            $content = ${${$r_attachment}{r_content}};
         }

         if (${$r_attachment}{contenttype} =~ m#^text/html#i ) {
            my $escapedmessageid = escapeURL($messageid);
            $content = html4nobase($content);
            $content = html4attachments($content, $r_attachments, "$config{'ow_cgiurl'}/openwebmail-main.pl", "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
            $content = html4mailto($content, "$config{'ow_cgiurl'}/openwebmail-main.pl", "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
            $content = html4disablejs($content) if ($prefs{'disablejs'}==1);
         }

         my $length = length($content);
         my $contenttype = ${$r_attachment}{contenttype}; 
         my $filename = ${$r_attachment}{filename};

         # we send message with contenttype text/plain for easy view
         if ($contenttype =~ /^message\//i) {
            $contenttype = "text/plain";
         }

         # we change the filename of an attachment 
         # from *.exe, *.com *.pif, *.lnk, *.scr to *.file
         # if its contenttype is not application/octet-stream
         # to avoid this attachment is referenced by html and executed directly ie
         if ( ( $filename =~ /\.exe$/i || 
                $filename =~ /\.com$/i ||
                $filename =~ /\.pif$/i || 
                $filename =~ /\.lnk$/i ||
                $filename =~ /\.scr$/i )  &&
               $contenttype !~ /application\/octet-stream/i ) {
            $filename="$filename.file";
         }

         # disposition:attachment default to save
         print qq|Content-Length: $length\n|,
               qq|Content-Transfer-Coding: binary\n|,
               qq|Connection: close\n|,
               qq|Content-Type: $contenttype; name="$filename"\n|;

         # ugly hack since ie5.5 is broken with disposition: attchment
         if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
            if ($contenttype =~ /^text/i) {
               print qq|Content-Disposition: inline; filename="$filename"\n|;
            } else {
               print qq|Content-Disposition: attachment; filename="$filename"\n|;
            }
         }

         # use undef to free memory before attachment transfer
         undef %{$r_attachment};
         undef $r_attachment;
         undef @{$r_attachments};
         undef $r_attachments;
         print qq|\n|, $content;
      } else {
         printheader();
         $messageid = str2html($messageid);
         print "What the heck? Message $messageid attachmment $nodeid seems to be gone!";
         printfooter();
      }
      return;

   }
}
################### END VIEWATTACHMENT ##################

################ VIEWATTFILE ##################
sub viewattfile {	# view attachments uploaded to openwebmail/etc/sessions/
   my $attfile=param("attfile");
   $attfile =~ s/\///g;  # just in case someone gets tricky ...
   # only allow to view attfiles belongs the $thissession
   if ($attfile!~/^$thissession/  || !-f "$config{'ow_etcdir'}/sessions/$attfile") {
      printheader();
      print "What the heck? Attfile $config{'ow_etcdir'}/sessions/$attfile seems to be gone!";
      printfooter();
      return;
   }

   my ($attsize, $attheader, $attheaderlen, $attcontent);
   my ($attcontenttype, $attencoding, $attdisposition, 
       $attid, $attlocation, $attfilename);
   
   $attsize=(-s("$config{'ow_etcdir'}/sessions/$attfile"));

   open(ATTFILE, "$config{'ow_etcdir'}/sessions/$attfile") or 
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$attfile!");
   read(ATTFILE, $attheader, 512);
   $attheaderlen=index($attheader,  "\n\n", 0);
   $attheader=substr($attheader, 0, $attheaderlen);
   seek(ATTFILE, $attheaderlen+2, 0);
   read(ATTFILE, $attcontent, $attsize-$attheaderlen-2);
   close(ATTFILE);

   my $lastline='NONE';
   foreach (split(/\n/, $attheader)) {
      if (/^\s/) {
         if ($lastline eq 'TYPE') { $attcontenttype .= $_ }
      } elsif (/^content-type:\s+(.+)$/ig) {
         $attcontenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $attencoding = $1;
         $lastline = 'NONE';
      } elsif (/^content-disposition:\s+(.+)$/ig) {
         $attdisposition = $1;
         $lastline = 'NONE';
      } elsif (/^content-id:\s+(.+)$/ig) {
         $attid = $1; 
         $attid =~ s/^\<(.+)\>$/$1/;
         $lastline = 'NONE';
      } elsif (/^content-location:\s+(.+)$/ig) {
         $attlocation = $1;
         $lastline = 'NONE';
      } else {
         $lastline = 'NONE';
      }
   }

   $attfilename = $attcontenttype;
   $attcontenttype =~ s/^(.+);.*/$1/g;
   unless ($attfilename =~ s/^.+name[:=]"?([^"]+)"?.*$/$1/ig) {
      $attfilename = $attdisposition || '';
      unless ($attfilename =~ s/^.+filename="?([^"]+)"?.*$/$1/ig) {
         $attfilename = "Unknown.".contenttype2ext($attcontenttype);
      }
   }
   $attdisposition =~ s/^(.+);.*/$1/g;

   if ($attencoding =~ /^base64$/i) {
      $attcontent = decode_base64($attcontent);
   } elsif ($attencoding =~ /^quoted-printable$/i) {
      $attcontent = decode_qp($attcontent);
   }

   my $length = length($attcontent);
   # disposition:inline default to open
   print qq|Content-Length: $length\n|,
         qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: $attcontenttype; name="$attfilename"\n|,
         qq|Content-Disposition: inline; filename="$attfilename"\n|,
         qq|\n|, $attcontent;

   return;
}
################### END VIEWATTATTFILE ##################

################### GETINFOMESSAGEIDS ###################
sub getinfomessageids {
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $index_complete=0;

   # do new indexing in background if folder > 10 M && empty db
   if ( (stat("$headerdb$config{'dbm_ext'}"))[7]==0 && 
        (stat($folderfile))[7] >= 10485760 ) {
      $|=1; 				# flush all output
      $SIG{CHLD} = sub { wait; $index_complete=1 if ($?==0) };	# handle zombie
      if ( fork() == 0 ) {		# child
         close(STDOUT);
         close(STDIN);
         filelock($folderfile, LOCK_SH|LOCK_NB) or exit 1;
         update_headerdb($headerdb, $folderfile);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
         exit 0;
      }

      for (my $i=0; $i<120; $i++) {	# wait index to complete for 120 seconds
         sleep 1;
         if ($index_complete==1) {
            last;
         }
      }   
      if ($index_complete==0) {
         openwebmailerror("$folderfile $lang_err{'under_indexing'}");
      }
   } else {	# do indexing directly if small folder
      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      update_headerdb($headerdb, $folderfile);
      filelock($folderfile, LOCK_UN);
   }

   # Since recipients are displayed instead of sender in folderview of 
   # SENT/DRAFT folder, the $sort must be changed from 'sender' to 
   # 'recipient' in this case
   if ( $folder=~ m#sent-mail#i || 
        $folder=~ m#saved-drafts#i ||
        $folder=~ m#$lang_folders{'sent-mail'}#i ||
        $folder=~ m#$lang_folders{'saved-drafts'}#i ) {
      $sort='recipient' if ($sort eq 'sender');
   }

   if ( $keyword ne '' ) {
      my $folderhandle=FileHandle->new();
      my ($totalsize, $new, $r_haskeyword, $r_messageids, $r_messagedepths);
      my @messageids=();
      my @messagedepths=();
      
      ($totalsize, $new, $r_messageids, $r_messagedepths)=get_info_messageids_sorted($headerdb, $sort, "$headerdb.cache", $prefs{'hideinternal'});

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      open($folderhandle, $folderfile);
      ($totalsize, $new, $r_haskeyword)=search_info_messages_for_keyword($keyword, $searchtype, $headerdb, $folderhandle, "$folderdir/.search.cache", $prefs{'hideinternal'});
      close($folderhandle);
      filelock($folderfile, LOCK_UN);

      for (my $i=0; $i<@{$r_messageids}; $i++) {
	my $id = ${$r_messageids}[$i];
	if ( ${$r_haskeyword}{$id} == 1 ) {
	  push (@messageids, $id);
	  push (@messagedepths, ${$r_messagedepths}[$i]);
        }
      }
#      foreach (@{$r_messageids}) {
#         push (@messageids, $_) if ( ${$r_haskeyword}{$_} == 1 ); 
#      }
      return($totalsize, $new, \@messageids, \@messagedepths);

   } else { # return: $totalsize, $new, $r_messageids for whole folder

      return(get_info_messageids_sorted($headerdb, $sort, "$headerdb.cache", $prefs{'hideinternal'}))

   }
}
################# END GETINFOMESSAGEIDS #################

#################### GETMESSAGE ###########################
sub getmessage {
   my ($messageid, $mode) = @_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();
   my %message = ();

   my ($currentheader, $currentbody, $r_currentattachments, $currentfrom, $currentdate,
       $currentsubject, $currentid, $currenttype, $currentto, $currentcc,
       $currentreplyto, $currentencoding, $currentstatus, $currentreceived,
       $currentinreplyto, $currentreferences);

   filelock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   update_headerdb($headerdb, $folderfile);
   open($folderhandle, "$folderfile");

   # $r_attachment is a reference to attachment array!
   if ($mode eq "all") {
      ($currentheader, $currentbody, $r_currentattachments)
		=parse_rfc822block(get_message_block($messageid, $headerdb, $folderhandle), "0", "all");
   } else {
      ($currentheader, $currentbody, $r_currentattachments)
		=parse_rfc822block(get_message_block($messageid, $headerdb, $folderhandle), "0", "");
   }

   close($folderhandle);
   filelock($folderfile, LOCK_UN);

   return \%message if ( $currentheader eq "" );

   $currentfrom = $currentdate = $currentsubject = $currenttype = 
   $currentto = $currentcc = $currentreplyto = $currentencoding = 'N/A';
   $currentstatus = '';
   $currentinreplyto = $currentreferences = '';

   my $lastline = 'NONE';
   my @smtprelays=();
   foreach (split(/\n/, $currentheader)) {
      if (/^\s/) {
         if    ($lastline eq 'FROM') { $currentfrom .= $_ }
         elsif ($lastline eq 'REPLYTO') { $currentreplyto .= $_ }
         elsif ($lastline eq 'DATE') { $currentdate .= $_ }
         elsif ($lastline eq 'SUBJ') { $currentsubject .= $_ }
         elsif ($lastline eq 'MESSID') { s/^\s+//; $currentid .= $_ }
         elsif ($lastline eq 'TYPE') { $currenttype .= $_ }
         elsif ($lastline eq 'ENCODING') { $currentencoding .= $_ }
         elsif ($lastline eq 'TO')   { $currentto .= $_ }
         elsif ($lastline eq 'CC')   { $currentcc .= $_ }
         elsif ($lastline eq 'INREPLYTO') { $currentinreplyto .= $_ }
         elsif ($lastline eq 'REFERENCES') { $currentreferences .= $_ }
         elsif ($lastline eq 'RECEIVED') { $currentreceived .= $_ }
      } elsif (/^from:\s+(.+)$/ig) {
         $currentfrom = $1;
         $lastline = 'FROM';
      } elsif (/^reply-to:\s+(.+)$/ig) {
         $currentreplyto = $1;
         $lastline = 'REPLYTO';
      } elsif (/^to:\s+(.+)$/ig) {
         $currentto = $1;
         $lastline = 'TO';
      } elsif (/^cc:\s+(.+)$/ig) {
         $currentcc = $1;
         $lastline = 'CC';
      } elsif (/^date:\s+(.+)$/ig) {
         $currentdate = $1;
         $lastline = 'DATE';
      } elsif (/^subject:\s+(.+)$/ig) {
         $currentsubject = $1;
         $lastline = 'SUBJ';
      } elsif (/^message-id:\s+(.*)$/ig) {
         $currentid = $1;
         $lastline = 'MESSID';
      } elsif (/^content-type:\s+(.+)$/ig) {
         $currenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $currentencoding = $1;
         $lastline = 'ENCODING';
      } elsif (/^status:\s+(.+)$/ig) {
         $currentstatus = $1;
         $lastline = 'NONE';
      } elsif (/^references:\s+(.+)$/ig) {
         $currentreferences = $1;
         $lastline = 'REFERENCES';
      } elsif (/^in-reply-to:\s+(.+)$/ig) {
         $currentinreplyto = $1;
         $lastline = 'INREPLYTO';
      } elsif (/^Received:(.+)$/ig) {
         my $tmp=$1;
         if ($currentreceived=~ /.*\sby\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1) if ($smtprelays[0] ne $1);
         }
         if ($currentreceived=~ /.*\sfrom\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1);
         } elsif ($currentreceived=~ /.*\(from\s([^\s]+)\).*/is) {
            unshift(@smtprelays, $1);
         }
         $currentreceived=$tmp;
         $lastline = 'RECEIVED';
      } else {
         $lastline = 'NONE';
      }
   }
   # capture last Received: block
   if ($currentreceived=~ /.*\sby\s([^\s]+)\s.*/) {
      unshift(@smtprelays, $1) if ($smtprelays[0] ne $1);
   }
   if ($currentreceived=~ /.*\sfrom\s([^\s]+)\s.*/) {
      unshift(@smtprelays, $1);
   } elsif ($currentreceived=~ /.*\(from\s([^\s]+)\).*/is) {
      unshift(@smtprelays, $1);
   }
   # count first fromhost as relay only if there are just 2 host on relaylist 
   # since it means sender pc uses smtp to talk to our mail server directly
   shift(@smtprelays) if ($#smtprelays>1);

search_smtprelay:
   foreach my $relay (@smtprelays) {
      next if ($relay !~ /[\w\d\-_]+\.[\w\d\-_]+/);
      foreach (@{$config{'domainnames'}}) {
         next search_smtprelay if ($realy =~ $_);
      }
      $relay=~s/[\[\]]//g;	# remove [] around ip addr in mailheader
				# since $message{smtprelay} may be put into filterrule
                        	# and we don't want [] be treat as regular expression
      $message{smtprelay} = $relay;
      last;
   }

   $message{header} = $currentheader;
   $message{body} = $currentbody;
   $message{attachment} = $r_currentattachments;

   $message{from}    = decode_mimewords($currentfrom);
   $message{replyto} = decode_mimewords($currentreplyto) unless ($currentreplyto eq "N/A");
   $message{to}      = decode_mimewords($currentto) unless ($currentto eq "N/A");
   $message{cc}      = decode_mimewords($currentcc) unless ($currentcc eq "N/A");
   $message{subject} = decode_mimewords($currentsubject);

   $message{date} = $currentdate;
   $message{status} = $currentstatus;
   $message{messageid} = $currentid;
   $message{contenttype} = $currenttype;
   $message{encoding} = $currentencoding;
   $message{inreplyto} = $currentinreplyto;
   $message{references} = $currentreferences;

   # Determine message's number and previous and next message IDs.
   my ($totalsize, $newmessages, $r_messageids)=getinfomessageids();
   foreach my $i (0..$#{$r_messageids}) {
      if (${$r_messageids}[$i] eq $messageid) {
         $message{"prev"} = ${$r_messageids}[$i-1] if ($i > 0);
         $message{"next"} = ${$r_messageids}[$i+1] if ($i < $#{$r_messageids});
         $message{"number"} = $i+1;
         $message{"total"}=$#{$r_messageids}+1;
         last;
      }
   }
   return \%message;
}
#################### END GETMESSAGE #######################

#################### MOVEMESSAGE ########################
sub movemessage {
   my @messageids = param("message_ids");
   if ( $#messageids<0 ) {	# no message ids to delete, return immediately
      if (param("messageaftermove")) {
         readmessage();
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
   getfolders(\@validfolders, \$folderusage, 0); 

   if (param("messageaftermove")) {
      readmessage();
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
   getfolders(\@validfolders, \$folderusage, 0); 

   displayheaders();
}
#################### END EMPTYTRASH #######################

##################### GETATTLISTINFO ###############################
sub getattlistinfo {
   my $currentfile;
   my @namelist=();
   my @filelist=();
   my $totalsize = 0;

   opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");

   my $attnum=-1;
   while (defined($currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         $attnum++;
         $currentfile = $1;
         $totalsize += ( -s "$config{'ow_etcdir'}/sessions/$currentfile" );

         push (@filelist, $currentfile);

         open (ATTFILE, "$config{'ow_etcdir'}/sessions/$currentfile");
         while (defined(my $line = <ATTFILE>)) {
            if ($line =~ s/^.+name="?([^"]+)"?.*$/$1/i) {
               $line = str2html($line);
               $line =~ s/^(.*)$/<em>$1<\/em>/;
               push (@namelist, $line);
               last;
            } elsif ($line =~ /^\s+$/ ) {
               push (@namelist, "<em>attachment.$attnum</em>");
               last; 
            }
         }
         close (ATTFILE);
      }
   }

   closedir (SESSIONSDIR);
   return ($totalsize, \@namelist, \@filelist);
}
##################### END GETATTLISTINFO ###########################

##################### DELETEATTACHMENTS ############################
sub deleteattachments {
   my $currentfile;
   opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");
   while (defined($currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         $currentfile = $1;
         unlink ("$config{'ow_etcdir'}/sessions/$currentfile");
      }
   }
   closedir (SESSIONSDIR);
}
#################### END DELETEATTACHMENTS #########################

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
      print "Location:  $config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\n\n";
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
      print "Location: $config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\n\n";
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

################# FILTERMESSAGE ###########################
sub filtermessage {
   my $filtered=mailfilter($user, 'INBOX', $folderdir, \@validfolders, 
	$prefs{'filter_repeatlimit'}, $prefs{'filter_fakedsmtp'}, $prefs{'filter_fakedexecontenttype'});
   if ($filtered > 0) {
      writelog("filtermsg - filter $filtered msgs from INBOX");
      writehistory("filtermsg - filter $filtered msgs from INBOX");
   } elsif ($filtered == -1 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   } elsif ($filtered == -2 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
   } elsif ($filtered == -3 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} INBOX!");
   } elsif ($filtered == -4 ) {
      openwebmailerror("$lang_err{'couldnt_open'} INBOX!");
   } elsif ($filtered == -5 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} mail-trash!");
   } elsif ($filtered == -6 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   }
}
################# END FILTERMESSAGE #######################

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

##################### FIRSTTIMEUSER ################################
sub firsttimeuser {
   my $html = '';
   my $temphtml;
   open (FTUSER, "$config{'ow_etcdir'}/templates/$prefs{'language'}/firsttimeuser.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/firsttimeuser.template!");
   while (<FTUSER>) {
      $html .= $_;
   }
   close (FTUSER);
   
   $html = applystyle($html);

   printheader();

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl");
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'firsttimeuser',
                       -default=>'yes',
                       -override=>'1');
   $temphtml .= hidden(-name=>'realname',
                       -default=>$userrealname || "Your Name",
                       -override=>'1');
   $temphtml .= submit("$lang_text{'continue'}");
   $temphtml .= end_form();

   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;
   
   print $html;

   printfooter();
}
################### END FIRSTTIMEUSER ##############################

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
                  submit("$lang_text{'continue'}").
                  "&nbsp; &nbsp;".
                  button(-name=>"exit",
                         -value=>$lang_text{'exit'},
                         -onclick=>'window.close();',
                         -override=>'1').
                  end_form();
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/;
      
   print $html;

   printfooter();
}
################## END LOGOUT ######################

