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

my $SCRIPT_DIR="";
if ( $ENV{'SCRIPT_FILENAME'} =~ m!^(.*?)/[\w\d\-]+\.pl! || $0 =~ m!^(.*?)/[\w\d\-]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\n\$SCRIPT_DIR not set in CGI script!"; exit 0; }

use strict;
no strict 'vars';
use Fcntl qw(:DEFAULT :flock);
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

$ENV{PATH} = ""; # no PATH should be needed
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0007); # make sure the openwebmail group can write

push (@INC, $SCRIPT_DIR, ".");
require "openwebmail-shared.pl";
require "mime.pl";
require "filelock.pl";
require "maildb.pl";
require "mailfilter.pl";

local %config;
readconf(\%config, "$SCRIPT_DIR/etc/openwebmail.conf");
require $config{'auth_module'} or
   openwebmailerror("Can't open authentication module $config{'auth_module'}");

local $thissession;
local ($virtualuser, $user, $userrealname, $uuid, $ugid, $homedir);

local %prefs;
local %style;
local ($lang_charset, %lang_folders, %lang_sortlabels, %lang_text, %lang_err);

local $folderdir;
local (@validfolders, $folderusage);

local ($folder, $printfolder, $escapedfolder);
local ($searchtype, $keyword, $escapedkeyword);
local $firstmessage;
local $sort;

# setuid is required if mails is located in user's dir
if ( $>!=0 && ($config{'use_homedirspools'}||$config{'use_homedirfolders'}) ) {
   print "Content-type: text/html\n\n'$0' must setuid to root"; exit 0;
}

if ( defined(param("sessionid")) ) {
   $thissession = param("sessionid");

   my $loginname = $thissession || '';
   $loginname =~ s/\-session\-0.*$//; # Grab loginname from sessionid

   my $siteconf;
   if ($loginname=~/\@(.+)$/) {
       $siteconf="$config{'ow_etcdir'}/sites.conf/$1";
   } else {
       $siteconf="$config{'ow_etcdir'}/sites.conf/$ENV{'HTTP_HOST'}";
   }
   readconf(\%config, "$siteconf") if ( -f "$siteconf"); 

   ($virtualuser, $user, $userrealname, $uuid, $ugid, $homedir)=get_virtualuser_user_userinfo($loginname);
   if ($user eq "") {
      sleep 10;	# delayed response
      openwebmailerror("User $loginname doesn't exist!");
   }
   if ( -f "$config{'ow_etcdir'}/users.conf/$user") { # read per user conf
      readconf(\%config, "$config{'ow_etcdir'}/users.conf/$user");
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

if ($action eq "readmessage") {
   readmessage(param("message_id"));
} elsif ($action eq "rebuildmessage") {
   rebuildmessage(param("partialid"));
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

###################### END MAIN ##############################

################# READMESSAGE ####################
sub readmessage {
   my $messageid = $_[0];

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
		  ":d" => "FaceTasty",
		  ";d" => "FaceTasty",
		  "8d" => "FaceTasty",
		  ":P" => "FaceNyah",
		  ";P" => "FaceNyah",
		  "8P" => "FaceNyah",
		  ":p" => "FaceNyah",
		  ";p" => "FaceNyah",
		  "8p" => "FaceNyah",
		  ":O" => "FaceStartled",
		  ";O" => "FaceStartled",
		  "8O" => "FaceStartled",
		  ":o" => "FaceStartled",
		  ";o" => "FaceStartled",
		  "8o" => "FaceStartled",
		  ":/" => "FaceIronic",
		  ";/" => "FaceIronic",
		  "8/" => "FaceIronic",
		  ":\\" => "FaceIronic",
		  ";\\" => "FaceIronic",
		  "8\\" => "FaceIronic",
		  ":|" => "FaceStraight",
		  ";|" => "FaceWry",
		  "8|" => "FaceKOed",
		  ":X" => "FaceYukky",
		  ";X" => "FaceYukky");

   # filter junkmail at inbox beofre display any message in inbox
   filtermessage() if ($folder eq 'INBOX');

   my %message = %{&getmessage($messageid)};

   if (%message) {
      if ( int($message{'number'}/$prefs{'headersperpage'})
           == $message{'number'}/$prefs{'headersperpage'}   ) {
         $firstmessage = $message{'number'} - $prefs{'headersperpage'} + 1;
      } else {
         $firstmessage = int($message{'number'}/$prefs{'headersperpage'})
                           * $prefs{'headersperpage'} + 1;
      }

      printheader();

      my $escapedmessageid = escapeURL($messageid);
      my $headers = param("headers") || $prefs{"headers"} || 'simple';
      my $attmode = param("attmode") || 'simple';

      my $main_url = "$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;firstmessage=$firstmessage".
                     "&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder";
      my $read_url = "$config{'ow_cgiurl'}/openwebmail-read.pl?sessionid=$thissession&amp;firstmessage=$firstmessage".
                     "&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder";
      my $read_url_with_id = "$read_url&amp;message_id=$escapedmessageid";
      my $send_url_with_id = "$config{'ow_cgiurl'}/openwebmail-send.pl?sessionid=$thissession&amp;firstmessage=$firstmessage".
                             "&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid";

      my $printfriendly = param("printfriendly");
      my $templatefile="readmessage.template";
      if ($printfriendly eq 'yes') {
         $templatefile="printmessage.template";
      }

      my $html = '';
      my ($temphtml, $temphtml1, $temphtml2);
      open (READMESSAGE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/$templatefile") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/$templatefile!");
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
         } elsif ($message{encoding} =~ /^x-uuencode/i) {
            $body= uudecode($body);
         }
      }

      my $zhconvert=param('zhconvert');
      if ($zhconvert eq "") {
         if ($lang_charset eq "big5") {
            if ($message{contenttype}=~/charset="?gb2312"?/i) {
               $zhconvert="g2b";
            } else {
               foreach my $attnumber (0 .. $#{$message{attachment}}) {
                  if (${$message{attachment}[$attnumber]}{contenttype}=~/charset="?gb2312"?/i) {
                     $zhconvert="g2b"; last;
                  }
               }
            }
            if ($zhconvert eq "g2b" &&
                ! -x (split(/\s+/, $config{'g2b_converter'}))[0] ) {
               $zhconvert="";
            }
         } elsif ($lang_charset eq "gb2312") {
            if ($message{contenttype}=~/charset="?big5"?/i) {
               $zhconvert="b2g";
            } else {
               foreach my $attnumber (0 .. $#{$message{attachment}}) {
                  if (${$message{attachment}[$attnumber]}{contenttype}=~/charset="?big5"?/i) {
                     $zhconvert="b2g"; last;
                  }
               }
            }
            if ($zhconvert eq "b2g" &&
                ! -x (split(/\s+/, $config{'b2g_converter'}))[0] ) {
               $zhconvert="";
            }
         }
      }
      # convert between gb and big5
      if ( $zhconvert eq 'b2g' ) {
         $from= b2g($from);
         $to= b2g($to);
         $subject= b2g($subject);
         $body= b2g($body);
      } elsif ( $zhconvert eq 'g2b' ) {
         $from= g2b($from);
         $to= g2b($to);
         $subject= g2b($subject);
         $body= g2b($body);
      }

      if ($message{contenttype} =~ m#^message/partial#i && 
          $message{contenttype} =~ /;\s*id="(.+?)";?/i  ) { # is this a partial msg?
         my $escapedpartialid=escapeURL($1);
         # display rebuild link
         $body = qq|<table width="100%"><tr><td>|.
                 qq|$lang_text{'thisispartialmsg'}&nbsp; |.
                 qq|<a href=\"$read_url_with_id&amp;action=rebuildmessage&amp;partialid=$escapedpartialid&amp;attmode=$attmode&amp;headers=$headers\">[$lang_text{'msgrebuild'}]</a>|.
                 qq|</td></tr></table>|;
      } elsif ($message{contenttype} =~ m#^text/html#i) { # convert into html table
         $body = html4nobase($body); 
         $body = html4link($body);
         $body = html4disablejs($body) if ($prefs{'disablejs'}==1);
         $body = html4disableembcgi($body) if ($prefs{'disableembcgi'}==1);
         $body = html4mailto($body, "$config{'ow_cgiurl'}/openwebmail-send.pl", "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
         $body = html2table($body); 
      } else { 					     # body must be html or text
         # remove odds space or blank lines
         $body =~ s/(\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;	
         $body =~ s/\n\s*$/\n/;
         # remove bbs control char
         $body =~ s/\x1b\[(\d|\d\d|\d;\d\d)?m//g if ($from=~/bbs/i || $body=~/bbs/i); 
         $body = text2html($body);
         $body =~ s/<a href=/<a class=msgbody href=/ig;
         $body =~ s/(>?)([:;8])[-^]?([\(\)\>\<\|PpDdOoX\\\/])([\s\<])/<img border=\"0\" width=\"12\" height=\"12\" src=\"$config{'ow_htmlurl'}\/images\/smilies\/$smilies{"$1$2$3"}\.png\" alt=\"$1$2$3\">$4/g if $prefs{'usesmileicon'};
      }

      # Set up the message to go to after move.
      my $messageaftermove;
      if (defined($message{"next"})) {
         $messageaftermove = $message{"next"};
      } elsif (defined($message{"prev"})) {
         $messageaftermove = $message{"prev"};
      }

      $html =~ s/\@\@\@MESSAGETOTAL\@\@\@/$message{"total"}/g;

      $temphtml = "<a href=\"$main_url&amp;action=displayheaders\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; ";
      $html =~ s/\@\@\@BACKTOLINK\@\@\@/$temphtml/g;

      # passing zhcovnert to composemessage if message is zhconverted in reading
      my $zhconvertparm;
      if ( $zhconvert eq 'b2g' ) {
         $zhconvertparm="&amp;zhconvert=b2g";
      } elsif ( $zhconvert eq 'g2b' ) {
         $zhconvertparm="&amp;zhconvert=g2b";
      }

      if ($folder eq 'saved-drafts') {
         $temphtml .= "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=editdraft\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/editdraft.gif\" border=\"0\" ALT=\"$lang_text{'editdraft'}\"></a> ";
      } elsif ($folder eq 'sent-mail') {
         $temphtml .= "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=editdraft\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/editdraft.gif\" border=\"0\" ALT=\"$lang_text{'editdraft'}\"></a> " .
         "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=forward$zhconvertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forward.gif\" border=\"0\" ALT=\"$lang_text{'forward'}\"></a> " .
         "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=forwardasatt\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forwardasatt.gif\" border=\"0\" ALT=\"$lang_text{'forwardasatt'}\"></a> ";
      } else {
         $temphtml .= "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=reply$zhconvertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/reply.gif\" border=\"0\" ALT=\"$lang_text{'reply'}\"></a> " .
         "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=replyall$zhconvertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/replyall.gif\" border=\"0\" ALT=\"$lang_text{'replyall'}\"></a> " .
         "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=forward$zhconvertparm\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forward.gif\" border=\"0\" ALT=\"$lang_text{'forward'}\"></a> " .
         "<a href=\"$send_url_with_id&amp;action=composemessage&amp;composetype=forwardasatt\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/forwardasatt.gif\" border=\"0\" ALT=\"$lang_text{'forwardasatt'}\"></a> ";
      }
      $temphtml .= "&nbsp;";

      if ($lang_charset eq 'gb2312') {
         if ($zhconvert eq "b2g" ) {
            $temphtml .= "<a href=\"$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode&amp;zhconvert=none\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif\" border=\"0\" alt=\"revert back\"></a> ";
         } else {
            $temphtml .= "<a href=\"$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode&amp;zhconvert=b2g\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif\" border=\"0\" alt=\"Big5 to GB\"></a> ";
         }
      } elsif ($lang_charset eq 'big5') {
         if ($zhconvert eq "g2b" ) {
            $temphtml .= "<a href=\"$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode&amp;zhconvert=none\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif\" border=\"0\" alt=\"revert back\"></a> ";
         } else {
            $temphtml .= "<a href=\"$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode&amp;zhconvert=g2b\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif\" border=\"0\" alt=\"GB to Big5\"></a> ";
         }
      }
      $temphtml .= "<a onclick=\"javascript:window.open('$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=simple&amp;zhconvert=$zhconvert&amp;printfriendly=yes','PrintWindow', 'width=720,height=360,resizable=yes,menubar=yes,scrollbars=yes')\">".
                   "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/print.gif\" border=\"0\" alt=\"$lang_text{'printfriendly'}\"></a> ";
      $temphtml .= "<a href=\"$main_url&amp;action=logout\"><IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/logout.gif\" border=\"0\" ALT=\"$lang_text{'logout'} $prefs{'email'}\"></a>";
   
      $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

      if (defined($message{"prev"})) {
         $temphtml1 = "<a href=\"$read_url&amp;action=readmessage&amp;message_id=$message{'prev'}&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;&lt;\"></a>";
      } else {
         $temphtml1 = "<img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/left-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
      }
      $html =~ s/\@\@\@LEFTMESSAGECONTROL\@\@\@/$temphtml1/g;

      if (defined($message{"next"})) {
         $temphtml2 = "<a href=\"$read_url&amp;action=readmessage&amp;message_id=$message{'next'}&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/right.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;&gt;\"></a>";
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
      if ($messageaftermove && $prefs{'viewnextaftermsgmovecopy'}) {
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
         
         if ( $zhconvert eq 'b2g' ) {		# convert between gb and big5
            $temphtml= b2g($temphtml);
         } elsif ( $zhconvert eq 'g2b' ) {
            $temphtml= g2b($temphtml);
         }

         $temphtml = text2html($temphtml);
         $temphtml =~ s/\n([-\w]+?:)/\n<B>$1<\/B>/g;
      } else {
         $temphtml = "<B>$lang_text{'date'}:</B> $message{date}<BR>\n";

         my ($ename, $eaddr)=email2nameaddr($message{from});
         $temphtml .= "<B>$lang_text{'from'}:</B> <a href='http://www.google.com/search?q=$eaddr' title='google $lang_text{'search'}...' target=_blank>$from</a> &nbsp;";
         if ($printfriendly ne "yes") {
            $temphtml .= "&nbsp;<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addaddress&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;realname=".escapeURL($ename)."&amp;email=".escapeURL($eaddr)."\">".
                         "<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/import.s.gif\" align=\"absmiddle\" border=\"0\" ALT=\"$lang_text{'importadd'} $eaddr\" onclick=\"return confirm('$lang_text{importadd} $eaddr ?');\">".
                         "</a>";
            $temphtml .= "&nbsp;<a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;priority=20&amp;rules=from&amp;include=include&amp;text=$eaddr&amp;destination=mail-trash&amp;enable=1\">".
                         "<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/blockemail.gif\" align=\"absmiddle\" border=\"0\" ALT=\"$lang_text{'blockemail'} $eaddr\" onclick=\"return confirm('$lang_text{blockemail} $eaddr ?');\">".
                         "</a>";
            if ($message{smtprelay} !~ /^\s*$/) {
               $temphtml .= "&nbsp; <a href=\"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;priority=20&amp;rules=smtprelay&amp;include=include&amp;text=$message{smtprelay}&amp;destination=mail-trash&amp;enable=1\">".
                         "<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/blockrelay.gif\" align=\"absmiddle\" border=\"0\" ALT=\"$lang_text{'blockrelay'} $message{smtprelay}\" onclick=\"return confirm('$lang_text{blockrelay} $message{smtprelay} ?');\">".
                         "</a>";
            }
         }

         $temphtml .= "<BR>";

         if ($replyto) {
            $temphtml .= "<B>$lang_text{'replyto'}:</B> $replyto<BR>\n";
         }

         if ($to) {
            if ( length($to)>96 && param('receivers') ne "all" ) {
              $to=substr($to,0,90)." ".
		  "<a href=\"$read_url_with_id&amp;action=readmessage&amp;attmode=$attmode&amp;receivers=all\">".
		  "<b>.....</b>"."</a>";
            }
            $temphtml .= "<B>$lang_text{'to'}:</B> $to<BR>\n";
         }

         if ($cc) {
            if ( length($cc)>96 && param('receivers') ne "all" ) {
              $cc=substr($cc,0,90)." ".
		  "<a href=\"$read_url_with_id&amp;action=readmessage&amp;attmode=$attmode&amp;receivers=all&amp;\">".
		  "<b>.....</b>"."</a>";
            }
            $temphtml .= "<B>$lang_text{'cc'}:</B> $cc<BR>\n";
         }

         if ($subject) {
            $temphtml .= "<B>$lang_text{'subject'}:</B> $subject\n";
         }

         if ($printfriendly ne "yes") {
            # display import icon
            if ($message{'priority'} eq 'urgent') {
               $temphtml .= "&nbsp<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/important.gif\" align=\"absmiddle\" border=\"0\">";
            }     
            # enable download the whole message
            my $dlicon;
            if ($message{'header'}=~/X\-Mailer:\s+Open WebMail/) {
               $dlicon="download.s.ow.gif";
            } else {
               $dlicon="download.s.gif";
            }
            $temphtml .= "&nbsp;<a href=\"$config{'ow_cgiurl'}/openwebmail-viewatt.pl/Unknown.msg?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=all\">".
                         "<IMG SRC=\"$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/$dlicon\" align=\"absmiddle\" border=\"0\" ALT=\"$lang_text{'download'} $subject.msg\">".
                         "</a>\n";
         }

      }

      $html =~ s/\@\@\@HEADERS\@\@\@/$temphtml/g;

      if ($headers eq "all") {
         $temphtml = "<a href=\"$read_url_with_id&amp;action=readmessage&amp;attmode=$attmode&amp;headers=simple\">$lang_text{'simplehead'}</a>";
      } else {
         $temphtml = "<a href=\"$read_url_with_id&amp;action=readmessage&amp;attmode=$attmode&amp;headers=all\">$lang_text{'allhead'}</a>";
      }
      $html =~ s/\@\@\@HEADERSTOGGLE\@\@\@/$temphtml/g;

      if ( $#{$message{attachment}}>=0 || 
           $message{contenttype}=~/^multipart/i ) {
         if ($attmode eq "all") {
            $temphtml = "<a href=\"$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=simple\">$lang_text{'simpleattmode'}</a>";
         } else {
            $temphtml = "<a href=\"$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=all\">$lang_text{'allattmode'}</a>";
         }
      } else {
         $temphtml="&nbsp";
      }
      $html =~ s/\@\@\@ATTMODETOGGLE\@\@\@/$temphtml/g;

      $temphtml=$body;
      # Note: attachment count >=0 is not necessary to be multipart!!!
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
                    (${$message{attachment}[$attnumber+1]}{contenttype} =~ /^text/i) &&
                    (${$message{attachment}[$attnumber+1]}{filename}=~ /^Unknown\./ ) ) {
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
                  if ( $zhconvert eq 'b2g' ) {
                     my $content = html_att2table($message{attachment}, $attnumber, $escapedmessageid);
                     $temphtml .= b2g($content);
                  } elsif ( $zhconvert eq 'g2b' ) {
                     my $content = html_att2table($message{attachment}, $attnumber, $escapedmessageid);
                     $temphtml .= g2b($content);
                  } else {
                     $temphtml .= html_att2table($message{attachment}, $attnumber, $escapedmessageid);
                  }
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
               }
            } elsif ( ${$message{attachment}[$attnumber]}{contenttype}=~ /^text/i ) {
               if ( ${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\./ ) {
                  # convert between gb and big5
                  if ( $zhconvert eq 'b2g' ) {
                     my $content = text_att2table($message{attachment}, $attnumber);
                     $content =~ s/(>?)([:;8])[-^]?([\(\)\>\<\|PpDdOoX\\\/])([\s\<])/<img border=\"0\" width=\"12\" height=\"12\" src=\"$config{'ow_htmlurl'}\/images\/smilies\/$smilies{"$1$2$3"}\.png\" alt=\"$1$2$3\">$4/g if $prefs{'usesmileicon'};
                     $temphtml .= b2g($content);
                  } elsif ( $zhconvert eq 'g2b' ) {
                     my $content = text_att2table($message{attachment}, $attnumber);
                     $content =~ s/(>?)([:;8])[-^]?([\(\)\>\<\|PpDdOoX\\\/])([\s\<])/<img border=\"0\" width=\"12\" height=\"12\" src=\"$config{'ow_htmlurl'}\/images\/smilies\/$smilies{"$1$2$3"}\.png\" alt=\"$1$2$3\">$4/g if $prefs{'usesmileicon'};
                     $temphtml .= g2b($content);
                  } else {
                     my $content = text_att2table($message{attachment}, $attnumber);
                     $content =~ s/(>?)([:;8])[-^]?([\(\)\>\<\|PpDdOoX\\\/])([\s\<])/<img border=\"0\" width=\"12\" height=\"12\" src=\"$config{'ow_htmlurl'}\/images\/smilies\/$smilies{"$1$2$3"}\.png\" alt=\"$1$2$3\">$4/g if $prefs{'usesmileicon'};
                     $temphtml .= $content;
                  }
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
               }
            } elsif ( ${$message{attachment}[$attnumber]}{contenttype}=~ /^message\/external\-body/i ) {
               # attachment external reference, not an real message
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
            } elsif ( ${$message{attachment}[$attnumber]}{contenttype}=~ /^message\/partial/i ) {
               # fragmented message
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
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
         if ($prefs{'sendreceipt'} eq 'ask') {
            print qq|<script language="JavaScript">\n<!--\n|,
                  qq|replyreceiptconfirm('$send_url_with_id&amp;action=replyreceipt', 0);\n|,
                  qq|//-->\n</script>\n|;
         } elsif ($prefs{'sendreceipt'} eq 'yes') {
            print qq|<script language="JavaScript">\n<!--\n|,
                  qq|replyreceiptconfirm('$send_url_with_id&amp;action=replyreceipt', 1);\n|,
                  qq|//-->\n</script>\n|;
         }
      }

      if ($printfriendly eq "yes") {
         print qq|</body></html>\n|;
      } else {
         printfooter();
      }

      # fork a child to do the status update and headerdb update
      # thus the result of readmessage can be returned as soon as possible
      if ($message{status} !~ /r/i) {
         $|=1; 				# flush all output
         $SIG{CHLD} = sub { wait };	# handle zombie
         if ( fork() == 0 ) {		# child
            close(STDOUT);
            close(STDIN);

            my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
            filelock($folderfile, LOCK_EX|LOCK_NB) or exit 1;

            # since status in headerdb may has flags not found in msg header
            # we must read the status from headerdb and then update it back
            my $status=(get_message_attributes($messageid, $headerdb))[$_STATUS];
            update_message_status($messageid, $status."R", $headerdb, $folderfile);

            filelock("$folderfile", LOCK_UN);
            exit 0;
         }
      }

   } else {
#      displayheaders();
      print "Location: $config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&firstmessage=$firstmessage&sessionid=$thissession&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder\n\n";
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
   } elsif (${$r_attachment}{encoding} =~ /^x-uuencode/i) {
      $temphtml = uudecode(${${$r_attachment}{r_content}});
   } else {
      $temphtml = ${${$r_attachment}{r_content}};
   }

   $temphtml = html4nobase($temphtml);
   $temphtml = html4link($temphtml);
   $temphtml = html4disablejs($temphtml) if ($prefs{'disablejs'}==1);
   $temphtml = html4disableembcgi($temphtml) if ($prefs{'disableembcgi'}==1);
   $temphtml = html4attachments($temphtml, $r_attachments, "$config{'ow_cgiurl'}/openwebmail-viewatt.pl", "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
   $temphtml = html4mailto($temphtml, "$config{'ow_cgiurl'}/openwebmail-send.pl", "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
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
   } elsif (${$r_attachment}{encoding} =~ /^x-uuencode/i) {
      $temptext = uudecode(${${$r_attachment}{r_content}});
   } else {
      $temptext = ${${$r_attachment}{r_content}};
   }

   # remove odds space or blank lines
   $temptext =~ s/(\r?\n){2,}/\n\n/g;
   $temptext =~ s/^\s+//;	
   $temptext =~ s/\n\s*$/\n/;
   $temptext = text2html($temptext);
   $temptext =~ s/<a href=/<a class=msgbody href=/ig;
   return($temptext. "<BR>");
}

sub message_att2table {
   my ($r_attachments, $attnumber, $headercolor)=@_;
   $headercolor='#dddddd' if ($headercolor eq '');

   my $r_attachment=${$r_attachments}[$attnumber];
   my ($header, $body)=split(/\n\r*\n/, ${${$r_attachment}{r_content}}, 2);
   my ($contenttype, $encoding, $description)=get_contenttype_encoding_from_header($header);
   
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
      } elsif ($encoding =~ /^x-uuencode/i) {
          $body = uudecode($body);
      }
   }
   if ($contenttype =~ m#^text/html#i) { # convert into html table
      $body = html4nobase($body); 
      $body = html4disablejs($body) if ($prefs{'disablejs'}==1);
      $body = html4disableembcgi($body) if ($prefs{'disableembcgi'}==1);
      $body = html2table($body); 
   } else {	
      $body = text2html($body);
      $body =~ s/<a href=/<a class=msgbody href=/ig;
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
                qq|<tr><td class=msgbody>\n|.
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
                   qq|<img border="0" |;
   if (${$r_attachment}{description} ne "") {
      $temphtml .= qq|alt="${$r_attachment}{description}" |;
   }
   $temphtml .=    qq|SRC="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid">|.
                   qq|</td></tr></table>|;
   return($temphtml);
}

sub misc_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid)=@_;
   my $r_attachment=${$r_attachments}[$attnumber];
   my $escapedfilename = escapeURL(${$r_attachment}{filename});
   my $attlen=lenstr(${$r_attachment}{contentlength});
   my $nodeid=${$r_attachment}{nodeid};
   my $contenttype=${$r_attachment}{contenttype};
   my $disposition=${$r_attachment}{disposition};

   $contenttype =~ s/^(.+?);.*/$1/g;
   $disposition=~s/^(.).*$/$1/;

   my $temphtml .= qq|<table border="0" width="40%" align="center" cellpadding="2">|.
                   qq|<tr><td nowrap colspan="2" valign="middle" bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: ${$r_attachment}{filename}&nbsp;($attlen)&nbsp;&nbsp;<font color=$style{"attachment_dark"}  size=-2>$nodeid $disposition|.
                   qq|</td></tr>|.
                   qq|<tr><td nowrap valign="middle" bgcolor= $style{"attachment_light"} align="center">|.
                   qq|$lang_text{'type'}: $contenttype<br>|.
                   qq|$lang_text{'encoding'}: ${$r_attachment}{encoding}|;
   if (${$r_attachment}{description} ne "") {
      $temphtml .= qq|<br>$lang_text{'description'}: ${$r_attachment}{description}|;
   }
   my $blank="";
   if ($contenttype=~/^text/ ||
       ${$r_attachment}{filename}=~/\.(jpg|jpeg|gif|png|bmp)$/i) {
      $blank="target=_blank";
   }
   $temphtml .=    qq|</td><td nowrap width="10%" valign="middle" bgcolor= $style{"attachment_light"} align="center">|.
                   qq|<a href="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid" $blank>$lang_text{'download'}</a>|.
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

############### END READMESSAGE ##################

################# REBUILDMESSAGE ####################
sub rebuildmessage {
   my $partialid = $_[0];
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);

   ($folderfile =~ /^(.+)$/) && ($folderfile = $1);	# bypass taint
   ($headerdb =~ /^(.+)$/) && ($headerdb = $1);

   filelock($folderfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $folderfile!");

   my ($errorcode, $rebuildmsgid)=rebuild_message_with_partialid($folderfile, $headerdb, $partialid);

   filelock("$folderfile", LOCK_UN);

   if ($errorcode==0) {
      readmessage($rebuildmsgid);
      writelog("rebuildmsg - rebuild $rebuildmsgid in $folder");
      writehistory("rebuildmsg - rebuild $rebuildmsgid from $folder");
   } else {
      my $html = '';
      my $temphtml;
      my $errormsg;

      if ($errorcode==-1) {
         $errormsg=$lang_err{'no_endpart'};
      } elsif ($errorcode==-2) {
         $errormsg=$lang_err{'part_missing'};
      } elsif ($errorcode==-3) {
         $errormsg=$lang_err{'rebuild_fmterr'};
      } elsif ($errorcode==-4) {
         $errormsg=$lang_err{'rebuild_sizeerr'};
      }

      open (FAILED, "$config{'ow_etcdir'}/templates/$prefs{'language'}/rebuildfailed.template") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/rebuildfailed.template!");
      while (<FAILED>) {
         $html .= $_;
      }
      close (FAILED);
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$errormsg/;

      $html = applystyle($html);

      printheader();

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl");
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
                          -default=>$headers ||$prefs{"headers"} || 'simple',
                          -override=>'1');
      $temphtml .= hidden(-name=>'attmode',
                          -default=>param("attmode") || 'simple',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>param("message_id"),
                          -override=>'1');
      $temphtml .= submit("$lang_text{'continue'}").
                   end_form();

      $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

      print $html;

      printfooter();
   }
}
################# END REBUILDMESSGAE ####################

