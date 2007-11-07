#!/usr/bin/suidperl -T
#
# openwebmail-read.pl - message reading program
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
use MIME::Base64;
use MIME::QuotedPrint;

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/htmlrender.pl";
require "modules/htmltext.pl";
require "modules/enriched.pl";
require "modules/mime.pl";
require "modules/tnef.pl";
require "modules/mailparse.pl";
require "modules/spamcheck.pl";
require "modules/viruscheck.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/cut.pl";
require "shares/getmsgids.pl";
require "shares/getmessage.pl";
require "shares/lockget.pl";
require "shares/statbook.pl";
require "shares/filterbook.pl";
require "shares/mailfilter.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_wdbutton %lang_text %lang_err);	# defined in lang/xy
use vars qw(%charset_convlist);							# defined in iconv.pl
use vars qw($_SIZE $_HEADERSIZE $_HEADERCHKSUM $_STATUS);			# defined in maildb.pl

# local globals
use vars qw($folder);
use vars qw($sort $msgdatetype $page $longpage);
use vars qw($searchtype $keyword);
use vars qw($escapedfolder $escapedkeyword);
use vars qw($urlparm);

use vars qw(%smilies);
%smilies = (
   ":)" => "FaceHappy",
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
   ";X" => "FaceYukky"   );

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = ow::tool::unescapeURL(param('folder'))||'INBOX';
$sort = param('sort') || $prefs{'sort'} || 'date_rev';
$msgdatetype = param('msgdatetype') || $prefs{'msgdatetype'};
$page = param('page') || 1;
$longpage = param('longpage') || 0;

$searchtype = param('searchtype') || 'subject';
$keyword = param('keyword') || '';

$escapedfolder = ow::tool::escapeURL($folder);
$escapedkeyword = ow::tool::escapeURL($keyword);

$urlparm="sessionid=$thissession&amp;folder=$escapedfolder&amp;".
         "page=$page&amp;longpage=$longpage&amp;".
         "sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype";

my $action = param('action')||'';
writelog("debug - request read begin, action=$action, folder=$folder - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "readmessage") {
   readmessage(param('message_id')||'');
} elsif ($action eq "rebuildmessage") {
   rebuildmessage(param('partialid')||'');
} elsif ($action eq "deleteattachment") {
   del_attachment_from_message($user, $folder, param('message_id')||'', param('nodeid')) if (param('nodeid') ne '');
   readmessage(param('message_id')||'');
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request read end, action=$action, folder=$folder - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## READMESSAGE ###########################################
sub readmessage {
   my $messageid = $_[0];

   my $orig_inbox_newmessages=0;
   my $now_inbox_newmessages=0;
   my $now_inbox_allmessages=0;
   my $inboxsize_k=0;
   my %FDB;

   my $spooldb=(get_folderpath_folderdb($user, 'INBOX'))[1];
   if (ow::dbm::exist($spooldb)) {
      ow::dbm::open(\%FDB, $spooldb, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db $spooldb");
      $orig_inbox_newmessages=$FDB{'NEWMESSAGES'};	# new msg in INBOX
      ow::dbm::close(\%FDB, $spooldb);
   }

   # filtermessage in background, hope junk is removed before displayed to user
   filtermessage($user, 'INBOX', \%prefs) if ($folder eq 'INBOX');

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   my $quotahit_deltype='';
   if ($quotalimit>0 && $quotausage>$quotalimit &&
       ($config{'delmail_ifquotahit'}||$config{'delfile_ifquotahit'}) ) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      if ($quotausage>$quotalimit) {
         if ($config{'delmail_ifquotahit'} && $folderusage > $quotausage*0.5) {
            $quotahit_deltype='quotahit_delmail';
            cutfoldermails(($quotausage-$quotalimit*0.9)*1024, $user, @validfolders);
         } elsif ($config{'delfile_ifquotahit'}) {
            $quotahit_deltype='quotahit_delfile';
            my $webdiskrootdir=$homedir.absolute_vpath("/", $config{'webdisk_rootpath'});
            cutdirfiles(($quotausage-$quotalimit*0.9)*1024, $webdiskrootdir);
         }
         $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      }
   }

   my $escapedmessageid = ow::tool::escapeURL($messageid);

   # Determine message's number and previous and next message IDs.
   my ($totalsize, $newmessages, $r_messageids)=getinfomessageids($user, $folder, $sort, $msgdatetype, $searchtype, $keyword);
   my ($message_num, $message_total, $messageid_prev, $messageid_next)=(-1, 0, '', '');
   foreach my $i (0..$#{$r_messageids}) {
      if (${$r_messageids}[$i] eq $messageid) {
         $message_num = $i+1;
         $message_total = $#{$r_messageids}+1;
         $messageid_prev = ${$r_messageids}[$i-1] if ($i > 0);
         $messageid_next = ${$r_messageids}[$i+1] if ($i < $#{$r_messageids});
         last;
      }
   }
   if ($message_num<0) {	# message id not found
      print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&page=$page&sessionid=$thissession&sort=$sort&msgdatetype=$msgdatetype&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder");
      return;
   }

   my %message = %{&getmessage($user, $folder, $messageid)};
   if ($message{status} !~ /R/i) {	# current msg is new and counted as old after this read
      $orig_inbox_newmessages-- if ($folder eq 'INBOX' && $orig_inbox_newmessages>0);
      $newmessages-- if ($newmessages>0);
   }

   $page=int($message_num/($prefs{'msgsperpage'}||10)+0.999999)||$page;

   my $headers = param('headers') || $prefs{'headers'} || 'simple';
   my $attmode = param('attmode') || 'simple';
   my $printfriendly = param('printfriendly') ||'';

   my $showhtmlastext=$prefs{'showhtmlastext'};
   $showhtmlastext=param('showhtmlastext') if (param('showhtmlastext') ne "");

   my $convfrom=param('convfrom');
   if ($convfrom eq '') {
      $convfrom=official_charset($message{'charset'});
      if ($convfrom eq '' && $prefs{'charset'} eq 'utf-8') {
         # assume msg is from sender using same language as the recipient's browser
         my $browserlocale = ow::lang::guess_browser_locale($config{available_locales});
         $convfrom = (ow::lang::localeinfo($browserlocale))[6];
      }
      $convfrom="none.$convfrom" if ($prefs{'readwithmsgcharset'} && ow::lang::is_charset_supported($convfrom));
   }
   $convfrom="none.$prefs{'charset'}" if ($convfrom !~ m/^none\./ && !is_convertible($convfrom, $prefs{'charset'}));
   my $readcharset=$prefs{'charset'};               # charset choosed by user to read current message
   $readcharset=$1 if ($convfrom=~/^none\.(.+)$/);  # read msg with no conversion


   my ($html, $temphtml, @tmp);
   my $templatefile="readmessage.template";
   $templatefile="printmessage.template" if ($printfriendly eq 'yes');

   # temporarily switch lang/charset if user want original charset.
   # we switch to an English UTF-8 interface because it shows correctly in all charsets.
   # we tried converting the message to UTF-8 and using the user's language UTF-8 locale,
   # but it turns out that iconv does not convert everything to UTF-8 correctly. So, we
   # use UTF-8 for the interface and display the page in the native charset of the message.
   if ($readcharset ne $prefs{'charset'}) {
      @tmp=($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'});
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'}) = ("en_US", $readcharset, "en_US.UTF-8");
      loadlang($prefs{'locale'});
      charset($prefs{'charset'}) if ($CGI::VERSION>=2.58); # setup charset of CGI module
   }

   $html=applystyle(readtemplate($templatefile));

   if ($#tmp>=1) {
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=@tmp;
   }

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;


   ### we don't keep keyword, firstpage between folders,
   ### thus the keyword, firstpage will be cleared when user change folder
   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                          -name=>'FolderForm').
               ow::tool::hiddens(sessionid=>$thissession,
                                 sort=>$sort,
                                 action=>'listmessages');
   $html =~ s/\@\@\@STARTFOLDERFORM\@\@\@/$temphtml/;

   # this popup_menu is done with pure html code
   # because we want to set font style for options in the select menu
   my $select_str=qq|\n<SELECT name="folder" accesskey="L" onChange="JavaScript:document.FolderForm.submit();">\n|;

   foreach my $foldername (@validfolders) {
      my ($folderfile, $folderdb, $newmessages, $allmessages);

      # find message count for folderlabel
      ($folderfile, $folderdb)=get_folderpath_folderdb($user, $foldername);
      if (ow::dbm::exist($folderdb)) {
         ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db ".f2u($folderdb));
         $allmessages=$FDB{'ALLMESSAGES'}-$FDB{'ZAPMESSAGES'};
         $allmessages-=$FDB{'INTERNALMESSAGES'} if ($prefs{'hideinternal'});
         $newmessages=$FDB{'NEWMESSAGES'};
         # current message is turned from new to old after this read
         $newmessages-- if ($foldername eq $folder && $message{status} !~ /R/i && $newmessages>0);

         if ($foldername eq 'INBOX') {
            $now_inbox_allmessages=$allmessages;
            $now_inbox_newmessages=$newmessages;
            $inboxsize_k=(-s $folderfile)/1024;
         }
         ow::dbm::close(\%FDB, $folderdb);
      }

      my $option_str=qq|<OPTION value="|.ow::tool::escapeURL($foldername).qq|"|;
      $option_str.=qq| selected| if ($foldername eq $folder);
      if ($newmessages>0) {
         $option_str.=qq| class="hilighttext">|;
      } else {
         $option_str.=qq|>|;
      }
      if (defined $lang_folders{$foldername}) {
         $option_str.=$lang_folders{$foldername};
      } else {
         $option_str.=ow::htmltext::str2html((iconv($prefs{'fscharset'}, $readcharset, $foldername))[0]);
      }
      $option_str.=" ($newmessages/$allmessages)" if ( $newmessages ne "" && $allmessages ne "");

      $select_str.="$option_str</OPTION>\n";
   }
   $select_str.="</SELECT>\n";

   $temphtml=$select_str;
   if ( $ENV{'HTTP_USER_AGENT'} =~ /lynx/i || # take care for text browser...
        $ENV{'HTTP_USER_AGENT'} =~ /w3m/i ) {
      $temphtml .= submit(-name=>$lang_text{'read'},
                          -class=>"medtext");
   }
   $html =~ s/\@\@\@FOLDERPOPUP\@\@\@/$temphtml/;

   if ($config{'quota_module'} ne "none") {
      $temphtml='';
      my $overthreshold=($quotalimit>0 && $quotausage/$quotalimit>$config{'quota_threshold'}/100);
      if ($config{'quota_threshold'}==0 || $overthreshold) {
         $temphtml = "$lang_text{'quotausage'}: ".lenstr($quotausage*1024,1);
      }
      if ($overthreshold) {
         $temphtml.=" (".(int($quotausage*1000/$quotalimit)/10)."%) ";
      }
   } else {
      $temphtml="&nbsp;";
   }
   $html =~ s/\@\@\@QUOTAUSAGE\@\@\@/$temphtml/;

   $temphtml=lenstr($message{'size'},1);
   $html =~ s/\@\@\@MESSAGESIZE\@\@\@/$temphtml/;

   my $main_url = "$config{'ow_cgiurl'}/openwebmail-main.pl?$urlparm";
   my $read_url = "$config{'ow_cgiurl'}/openwebmail-read.pl?$urlparm";
   my $send_url = "$config{'ow_cgiurl'}/openwebmail-send.pl?$urlparm";
   my $read_url_with_id = "$read_url&amp;message_id=$escapedmessageid";
   my $send_url_with_id = "$send_url&amp;message_id=$escapedmessageid".
                          "&amp;showhtmlastext=$showhtmlastext&amp;compose_caller=read";

   my $is_htmlmsg=0;

   my $from = $message{from}||'';
   my $replyto = $message{'reply-to'}||'';
   my $to = $message{to}||'';
   my $notificationto = $message{'disposition-notification-to'}||'';
   my $cc = $message{cc}||'';
   my $bcc = $message{bcc}||'';
   my $subject = $message{subject}||'';
   my $body = $message{"body"} || '';
   if ($message{'content-type'} =~ /^text/i) {
      if ($message{'content-transfer-encoding'} =~ /^quoted-printable/i) {
         $body= decode_qp($body);
      } elsif ($message{'content-transfer-encoding'} =~ /^base64/i) {
         $body= decode_base64($body);
      } elsif ($message{'content-transfer-encoding'} =~ /^x-uuencode/i) {
         $body= ow::mime::uudecode($body);
      }
   }

   ($from,$replyto,$to,$cc,$bcc,$subject)
	=iconv('utf-8', $readcharset, $from,$replyto,$to,$cc,$bcc,$subject);
   ($body) = iconv($convfrom, $readcharset, $body);

   # web-ified headers
   foreach ($from, $replyto, $to, $cc, $bcc, $subject) { $_=ow::htmltext::str2html($_); }

   if ($message{'content-type'} =~ m#^message/partial#i &&
       $message{'content-type'} =~ /;\s*id="(.+?)";?/i  ) { # is this a partial msg?
      my $escapedpartialid=ow::tool::escapeURL($1);
      # display rebuild link
      $body = qq|<table width="100%"><tr><td>|.
              qq|$lang_text{'thisispartialmsg'}&nbsp; |.
              qq|<a href="$read_url_with_id&amp;action=rebuildmessage&amp;partialid=$escapedpartialid&amp;attmode=$attmode&amp;headers=$headers">[$lang_text{'msgrebuild'}]</a>|.
              qq|</td></tr></table>|;
   } elsif ($message{'content-type'} =~ m#^text/(html|enriched)#i) { # convert html msg into table
      my $subtype=$1;
      $body = ow::enriched::enriched2html($body) if ($subtype eq 'enriched');
      if ($showhtmlastext) {	# html -> text -> html
         $body = ow::htmltext::html2text($body);
         $body = ow::htmltext::text2html($body);
         # change color for quoted lines
         $body =~ s!^(&gt;.*<br>)$!<font color=#009900>$1</font>!img;
         $body =~ s/<a href=/<a class=msgbody href=/ig;
      } elsif ($subtype eq 'html') {			# html rendering
         $body = ow::htmlrender::html4nobase($body);
         $body = ow::htmlrender::html4noframe($body);
         $body = ow::htmlrender::html4link($body);
         $body = ow::htmlrender::html4disablejs($body) if ($prefs{'disablejs'});
         $body = ow::htmlrender::html4disableembcode($body) if ($prefs{'disableembcode'});
         $body = ow::htmlrender::html4disableemblink($body, $prefs{'disableemblink'}, "$config{'ow_htmlurl'}/images/backgrounds/Transparent.gif") if ($prefs{'disableemblink'} ne 'none');
         $body = ow::htmlrender::html4mailto($body, "$config{'ow_cgiurl'}/openwebmail-send.pl", "$urlparm&amp;action=composemessage&amp;message_id=$escapedmessageid&amp;compose_caller=read");
      }
      $body = ow::htmlrender::html2table($body);
      $is_htmlmsg=1;
   } else { 					     # body other than html, enriched is displayed as pure text
      # remove odds space or blank lines
      $body =~ s/(\r?\n){2,}/\n\n/g;
      $body =~ s/^\s+//;
      $body =~ s/\n\s*$/\n/;

      # remove bbs control char
      $body =~ s/\x1b\[(\d|\d\d|\d;\d\d)?m//g if ($from=~/bbs/i || $body=~/bbs/i);
      if ($prefs{'usesmileicon'}) {
         $body =~ s/(^|\D)(>?)([:;8])[-^]?([\(\)\>\<\|PpDdOoX\\\/])([\s\<])/$1 SMILY_$smilies{"$2$3$4"}\.png $5/g;
         $body = ow::htmltext::text2html($body);
         $body =~ s/SMILY_(.+?\.png)/<img border="0" width="12" height="12" src="$config{'ow_htmlurl'}\/images\/smilies\/$1">/g;
      } else {
         $body = ow::htmltext::text2html($body);
      }
      # change color for quoted lines
      $body =~ s!^(&gt;.*<br>)$!<font color=#009900>$1</font>!img;
      $body =~ s/<a href=/<a class=msgbody href=/ig;
   }

   # Set up the message to go to after move.
   my $messageaftermove = $messageid_next || $messageid_prev;;
   my $escapedmessageaftermove = ow::tool::escapeURL($messageaftermove);

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'msglist'}", qq|accesskey="B" href="$main_url&amp;action=listmessages"|);
   $temphtml .= "&nbsp;\n";

   # quota or spool over the limit
   my $limited=(($quotalimit>0 && $quotausage>$quotalimit) ||			   # quota
                ($config{'spool_limit'}>0 && $inboxsize_k>$config{'spool_limit'})); # spool

   if (!$limited) {
      if ($folder eq 'saved-drafts') {
         $temphtml .= iconlink("editdraft.gif",    $lang_text{'editdraft'},    qq|accesskey="E" href="$send_url_with_id&amp;action=composemessage&amp;composetype=editdraft&amp;convfrom=$convfrom"|);
      } elsif ($folder eq 'sent-mail') {
         $temphtml .= iconlink("editdraft.gif",    $lang_text{'editdraft'},    qq|accesskey="E" href="$send_url_with_id&amp;action=composemessage&amp;composetype=editdraft&amp;convfrom=$convfrom"|).
                      iconlink("forward.gif",      $lang_text{'forward'},      qq|accesskey="F" href="$send_url_with_id&amp;action=composemessage&amp;composetype=forward&amp;convfrom=$convfrom"|).
                      iconlink("forwardasatt.gif", $lang_text{'forwardasatt'}, qq|accesskey="M" href="$send_url_with_id&amp;action=composemessage&amp;composetype=forwardasatt"|).
                      iconlink("forwardasorig.gif",$lang_text{'forwardasorig'},qq|accesskey="O" href="$send_url_with_id&amp;action=composemessage&amp;composetype=forwardasorig&amp;convfrom=$convfrom"|);
      } else {
         $temphtml .= iconlink("compose.gif",      $lang_text{'composenew'},   qq|accesskey="C" href="$send_url_with_id&amp;action=composemessage"|).
                      iconlink("reply.gif",        $lang_text{'reply'},        qq|accesskey="R" href="$send_url_with_id&amp;action=composemessage&amp;composetype=reply&amp;convfrom=$convfrom"|).
                      iconlink("replyall.gif",     $lang_text{'replyall'},     qq|accesskey="A" href="$send_url_with_id&amp;action=composemessage&amp;composetype=replyall&amp;convfrom=$convfrom"|).
                      iconlink("forward.gif",      $lang_text{'forward'},      qq|accesskey="F" href="$send_url_with_id&amp;action=composemessage&amp;composetype=forward&amp;convfrom=$convfrom"|).
                      iconlink("forwardasatt.gif", $lang_text{'forwardasatt'}, qq|accesskey="M" href="$send_url_with_id&amp;action=composemessage&amp;composetype=forwardasatt"|).
                      iconlink("forwardasorig.gif",$lang_text{'forwardasorig'},qq|accesskey="O" href="$send_url_with_id&amp;action=composemessage&amp;composetype=forwardasorig&amp;convfrom=$convfrom"|);
                      # TODO: this is stub code for a future feature that allows editing any received message
                      # iconlink("editdraft.gif",    $lang_text{'editdraft'},    qq|accesskey="E" href="$send_url_with_id&amp;action=composemessage&amp;composetype=editdraft&amp;convfrom=$convfrom"|).
      }
      $temphtml .= "&nbsp;\n";
   }

   $temphtml .= iconlink("print.gif", $lang_text{'printfriendly'}, qq|href=#here onClick="javascript:window.open('$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=simple&amp;convfrom=$convfrom&amp;printfriendly=yes','_print', 'width=720,height=360,resizable=yes,menubar=yes,scrollbars=yes')"|);
   $temphtml .= "&nbsp;\n";

   if ($config{'enable_addressbook'}) {
      $temphtml .= iconlink("addrbook.gif", $lang_text{'addressbook'}, qq|accesskey="A" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   }
   if ($config{'enable_calendar'}) {
      $temphtml .= iconlink("calendar.gif", $lang_text{'calendar'}, qq|accesskey="K" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=$prefs{'calendar_defaultview'}&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   }
   if ($config{'enable_webdisk'}) {
      $temphtml .= iconlink("webdisk.gif", $lang_text{'webdisk'}, qq|accesskey="E" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   }
   if ( $config{'enable_sshterm'}) {
      if ( -r "$config{'ow_htmldir'}/applet/mindterm2/mindterm.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm2/ssh2.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      } elsif ( -r "$config{'ow_htmldir'}/applet/mindterm/mindtermfull.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm/ssh.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      }
   }
   if ( $config{'enable_preference'}) {
      $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;page=$page&amp;prefs_caller=read"|);
   }
   $temphtml .= iconlink("logout.gif","$lang_text{'logout'} $prefs{'email'}", qq|accesskey="Q" href="$main_url&amp;action=logout"|) . qq| \n|;

   $html =~ s/\@\@\@LEFTMENUBARLINKS\@\@\@/$temphtml/;

   $temphtml='';
   if ($config{'enable_learnspam'}) {
      my ($dest, $gif, $title);
      if ($folder eq 'spam-mail') {
         ($dest, $gif, $title)=('LEARNHAM', "learnham.gif", $lang_text{'learnham'});
      } elsif ($folder ne 'saved-drafts' && $folder ne 'sent-mail' &&
               $folder ne 'spam-mail' && $folder ne 'virus-mail') {
         ($dest, $gif, $title)=('LEARNSPAM', "learnspam.gif", $lang_text{'learnspam'});
      }
      if ($dest ne '') {
         my $url=qq|accesskey="Z" href="$main_url&amp;action=movemessage&amp;message_ids=$escapedmessageid&amp;message_id=$escapedmessageaftermove&amp;destination=$dest&amp;headers=$headers&amp;attmode=$attmode|;
         $url .= qq|&amp;messageaftermove=1| if ($messageaftermove && $prefs{'viewnextaftermsgmovecopy'});
         $url .= qq|" |;
         $url .= qq|onClick="return confirm($lang_text{'msgmoveconf'})"| if ($prefs{'confirmmsgmovecopy'});
         $temphtml .= iconlink($gif, $title, $url);
      }
   }
   if ($folder ne 'mail-trash') {
      my $trashfolder='mail-trash';
      $trashfolder='DELETE' if ($quotalimit>0 && $quotausage>=$quotalimit);
      my $url=qq|accesskey="Z" href="$main_url&amp;action=movemessage&amp;message_ids=$escapedmessageid&amp;message_id=$escapedmessageaftermove&amp;destination=$trashfolder&amp;headers=$headers&amp;attmode=$attmode|;
      $url .= qq|&amp;messageaftermove=1| if ($messageaftermove && $prefs{'viewnextaftermsgmovecopy'});
      $url .= qq|" |;
      $url .= qq|onClick="return confirm($lang_text{'msgmoveconf'})"| if ($prefs{'confirmmsgmovecopy'});
      $temphtml .= iconlink("totrash.gif", $lang_text{'totrash'}, $url);
   }
   $temphtml .= "&nbsp;\n";

   $html =~ s/\@\@\@RIGHTMENUBARLINKS\@\@\@/$temphtml/;

   my $gif;
   $temphtml='';
   if ($messageid_prev ne '') {
      $gif="left.s.gif"; $gif="right.s.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "&lt;", qq|accesskey="U" href="$read_url&amp;message_id=|.ow::tool::escapeURL($messageid_prev).qq|&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode"|);
   } else {
      $gif="left-grey.s.gif"; $gif="right-grey.s.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "-", "");
   }
   $temphtml.=qq|$message_num/|.($#{$r_messageids}+1);
   if ($messageid_next ne '') {
      my $gif="right.s.gif"; $gif="left.s.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "&gt;", qq|accesskey="D" href="$read_url&amp;message_id=|.ow::tool::escapeURL($messageid_next).qq|&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode"|);
   } else {
      my $gif="right-grey.s.gif"; $gif="left-grey.s.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "-", "");
   }
   $html =~ s/\@\@\@MESSAGECONTROL\@\@\@/$temphtml/g;

   $temphtml = iconlink("gotop.gif", "^", qq|href="#"|);
   $html =~ s/\@\@\@TOPCONTROL\@\@\@/$temphtml/;


   my ($htmlconv, $htmlstat, $htmlmove);

   # charset conversion menu
   if(defined $ow::lang::charactersets{(ow::lang::localeinfo($prefs{'locale'}))[4]} ) {
      my (@cflist, %cflabels, %allsets, $cf);
      foreach ((map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets), keys %charset_convlist) {
         $allsets{$_}=1 if (!defined $allsets{$_});
      }

      $cf="none.".lc($message{'charset'}); # readmsg with orig charset and no conversion
      push(@cflist, $cf);
      $cflabels{$cf}=(lc($message{'charset'})||$lang_text{'none'})." *";
      delete $allsets{$cf};

      $cf="none.$prefs{'charset'}";        # readmsg with prefs charset and no conversion
      if (!defined $cflabels{$cf}) {
         push(@cflist, $cf);
         $cflabels{$cf}=$prefs{'charset'};
         delete $allsets{$prefs{'charset'}};
      }

      $cf=lc($message{'charset'});         # readmsg with prefs charset and conversion
      if (is_convertible($cf, $prefs{'charset'})) {
         push(@cflist, $cf);
         $cflabels{$cf}="$cf > $prefs{'charset'}";
         delete $allsets{$cf};
      }
      foreach $cf (@{$charset_convlist{$prefs{'charset'}}}) {
         if (!defined $cflabels{$cf}) {
            push(@cflist, $cf);
            $cflabels{$cf}="$cf > $prefs{'charset'}";
            delete $allsets{$cf};
         }
      }

      foreach (sort keys %allsets) {       # readmsg with other charset and no conversion
         $cf="none.$_";
         next if (defined $cflabels{$cf});
         push(@cflist, $cf); $cflabels{$cf}=$_;
      }

      $htmlconv = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl").
                  ow::tool::hiddens(action=>'readmessage',
                                    page=>$page,
                                    sort=>$sort,
                                    keyword=>$keyword,
                                    searchtype=>$searchtype,
                                    folder=>$escapedfolder,
                                    headers=>param('headers') ||$prefs{'headers'} || 'simple',
                                    attmode=>param('attmode') || 'simple',
                                    sessionid=>$thissession,
                                    message_id=>param('message_id')||'');
      $htmlconv = qq|<table cellspacing=0 cellpadding=0 border=0><tr>$htmlconv|.
                  qq|<td nowrap>$lang_text{'charset'}&nbsp;</td><td>|.
                  popup_menu(-name=>'convfrom',
                             -values=>\@cflist,
                             -labels=>\%cflabels,
                             -default=>$convfrom,
                             -onChange=>'javascript:submit();',
                             -accesskey=>'I',	# i18n
                             -override=>'1').
                  qq|</td>|.end_form().qq|</tr></table>|;
   }

   # reply with stationery selection
   if ( $folder ne 'saved-drafts' && $folder ne 'sent-mail' &&
        $config{'enable_stationery'} ) {

      my (@statvalues, %statlabels);
      push(@statvalues, $lang_text{'statreply'});
      my $statbookfile=dotpath('stationery.book');
      if (-f $statbookfile) {
         my %stationery;
         my ($ret, $errmsg)=read_stationerybook($statbookfile, \%stationery);
         openwebmailerror($errmsg) if ($ret<0);
         foreach (sort keys %stationery) {
            my $statname=$_;
            my $escapedstatname=ow::tool::escapeURL($statname);
            my $label=ow::htmltext::str2html((iconv($stationery{$statname}{charset}, $readcharset, $statname))[0]);
            push(@statvalues, $escapedstatname);
            $statlabels{$escapedstatname} = $label;
         }
      }

      $htmlstat = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-send.pl",
                             -name=>'ReplyWith').
                  ow::tool::hiddens(sessionid=>$thissession,
                                    message_id=>$messageid,
                                    folder=>$escapedfolder,
                                    sort=>$sort,
                                    page=>$page,
                                    convfrom=>$convfrom,
                                    action=>'composemessage',
                                    composetype=>'reply',
                                    compose_caller=>'read').
                  qq|<table cellspacing=0 cellpadding=0 border=0><tr vlign=center>$htmlstat<td>|.
                  popup_menu(-name=>'statname',
                             -values=>\@statvalues,
                             -labels=>\%statlabels,
                             -onChange=>'JavaScript:document.ReplyWith.submit();',
                             -override=>'1').
                  qq|</td><td>|.
                  iconlink("editst.s.gif", $lang_text{'editstat'}, qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editstat&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;page=$page"|).
                  qq|</td>|.end_form().qq|</tr></table>|;
   }

   # move control menu
   $htmlmove = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                          -name=>'moveform').
               ow::tool::hiddens(action=>'movemessage',
                                 sessionid=>$thissession,
                                 page=>$page,
                                 sort=>$sort,
                                 keyword=>$keyword,
                                 searchtype=>$searchtype,
                                 folder=>$escapedfolder,
                                 headers=>$headers,
                                 message_ids=>$messageid,
                                 message_id=>$messageaftermove);
   if ($messageaftermove && $prefs{'viewnextaftermsgmovecopy'}) {
      $htmlmove .= ow::tool::hiddens(messageaftermove=>'1');
   }

   my (@movefolders, %movelabels); %movelabels=%lang_folders;
   # option to del message directly from folder
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      @movefolders=('DELETE');
   } else {
      foreach my $f (@validfolders) {
         my ($value, $label)=(ow::tool::escapeURL($f), $f);
         if (defined $lang_folders{$f}) {
            $label=$lang_folders{$f};
         } else {
            $label=(iconv($prefs{'fscharset'}, $readcharset, $label))[0];
         }
         push(@movefolders, $value); $movelabels{$value}=$label if ($value ne $label);
      }
      push(@movefolders, 'LEARNSPAM', 'LEARNHAM') if ($config{'enable_learnspam'});
      push(@movefolders, 'FORWARD', 'DELETE');
   }
   my $defaultdestination;
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      $defaultdestination='DELETE';
   } elsif ($folder eq 'mail-trash' || $folder eq 'spam-mail' || $folder eq 'virus-mail') {
      $defaultdestination='saved-messages';
   } elsif ($folder eq 'sent-mail' || $folder eq 'saved-drafts') {
      $defaultdestination='mail-trash';
   } else {
      my $smartdestination;
      if ($prefs{'smartdestination'}) {
         my $subject=(iconv('utf-8', $readcharset, $message{'subject'}))[0]; $subject=~s/\s//g;
         my $from=(iconv('utf-8', $readcharset, $message{'from'}))[0];
         foreach (@validfolders) {	# use validfolders instead of movefolders because validfolders are real folders and it is not escaped
            if ($subject=~/\Q$_\E/i || $from=~/\Q$_\E/i) {
               $smartdestination=$_; last;
            }
         }
      }
      $defaultdestination=$smartdestination || $prefs{'defaultdestination'} || 'mail-trash';
      $defaultdestination='mail-trash' if ( $folder eq $defaultdestination);
   }

   $htmlmove = qq|<table cellspacing=0 cellpadding=0 border=0><tr>$htmlmove<td nowrap>|.
               popup_menu(-name=>'destination',
                          -default=>ow::tool::escapeURL($defaultdestination),
                          -values=>\@movefolders,
                          -labels=>\%movelabels,
                          -accesskey=>'T',	# target folder
                          -override=>'1');
   if ($prefs{'confirmmsgmovecopy'}) {
      $htmlmove .= submit(-name=>'movebutton',
                          -value=>$lang_text{'move'},
                          -onClick=>"return confirm($lang_text{'msgmoveconf'})");
      if (!$limited) {
         $htmlmove .= submit(-name=>'copybutton',
                             -value=>$lang_text{'copy'},
                             -onClick=>"return confirm($lang_text{'msgcopyconf'})");
      }
   } else {
      $htmlmove .= submit(-name=>'movebutton',
                          -value=>$lang_text{'move'});
      if (!$limited) {
         $htmlmove .= submit(-name=>'copybutton',
                             -value=>$lang_text{'copy'});
      }
   }
   $htmlmove .= qq|</td></tr>|.end_form().qq|</table>|;

   if ($prefs{'ctrlposition_msgread'} eq "top") {
      templateblock_enable($html, 'CONTROLBAR1');
      templateblock_disable($html, 'CONTROLBAR2');
      $html =~ s/\@\@\@CONVFROMMENU1\@\@\@/$htmlconv/;
      $html =~ s/\@\@\@STATIONERYMENU1\@\@\@/$htmlstat/;
      $html =~ s/\@\@\@MOVECONTROLS1\@\@\@/$htmlmove/;
   } else {
      templateblock_disable($html, 'CONTROLBAR1');
      templateblock_enable($html, 'CONTROLBAR2');
      $html =~ s/\@\@\@CONVFROMMENU2\@\@\@/$htmlconv/;
      $html =~ s/\@\@\@STATIONERYMENU2\@\@\@/$htmlstat/;
      $html =~ s/\@\@\@MOVECONTROLS2\@\@\@/$htmlmove/;
   }

   if ($headers eq "all") {
      $temphtml = decode_mimewords_iconv($message{header}, $readcharset);
      $temphtml = ow::htmltext::text2html($temphtml);
      $temphtml =~ s/\n([-\w]+?:)/\n<B>$1<\/B>/g;
   } else {
      $temphtml = "<B>$lang_text{'date'}:</B> $message{date}";
      if ($printfriendly ne "yes") {
         # enable download the whole message
         my $dlicon;
         if ($message{'x-mailer'}=~/Open WebMail/) {
            $dlicon="download.s.ow.gif";
         } else {
            $dlicon="download.s.gif";
         }
         $temphtml .= qq|&nbsp; | . iconlink($dlicon, "$lang_text{'download'} $subject.msg", qq|href="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/Unknown.msg?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=all&amp;convfrom=$convfrom"|). qq|\n|;
      }
      $temphtml .= "<BR>\n";

      my ($ename, $eaddr)=ow::tool::email2nameaddr($message{from});
      my $jseaddr = $eaddr; $jseaddr=~ s/'/\\'/g; # escape ' with \'
      $temphtml .= qq|<B>$lang_text{'from'}:</B> <a href="http://www.google.com/search?q=|.ow::tool::escapeURL($eaddr).qq|" title="google $lang_text{'search'}..." target="_blank">$from</a>&nbsp; \n|;
      if ($printfriendly ne "yes") {
         if ($config{'enable_addressbook'}) {
            my $is_writableabook_found=0;
            for my $dir (dotpath('webaddr'),  $config{'ow_addressbooksdir'}) {
               opendir(D, $dir) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $dir ($!)");
               while (defined(my $fname=readdir(D))) {
                  next if ($fname=~/^\./ || $fname=~/^categories\.cache$/);
                  if (-w "$dir/$fname") {
                     $is_writableabook_found=1; last;
                  }
               }
               closedir(D);
               last if ($is_writableabook_found);
            }

            if ($is_writableabook_found) {
               my $fullname=(iconv('utf-8', $prefs{charset}, $ename))[0];
               my ($firstname, $lastname) = split(/\s+/, $fullname, 2);
               $temphtml .= qq|&nbsp;|. iconlink("import.s.gif",  qq|$lang_text{'importadd'} |.ow::htmltext::str2html($eaddr), qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addreditform&amp;editformcaller=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;N.0.VALUE.GIVENNAME=|.ow::tool::escapeURL($firstname).qq|&amp;N.0.VALUE.FAMILYNAME=|.ow::tool::escapeURL($lastname).qq|&amp;FN.0.VALUE=|.ow::tool::escapeURL($fullname).qq|&amp;EMAIL.0.VALUE=|.ow::tool::escapeURL($eaddr).qq|&amp;formchange=1" onclick="return confirm('$lang_text{importadd} |.ow::htmltext::str2html($jseaddr).qq| ?');"|) . qq|\n|;
            } else {
               $temphtml .= qq|&nbsp;|. iconlink("import.s.gif",  qq|$lang_text{'importadd'} |.ow::htmltext::str2html($eaddr), qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrbookedit&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid" onclick="return confirm('$lang_err{abook_all_readonly}');"|) . qq|\n|;
            }
         }
         if ($config{'enable_userfilter'}) {
            $temphtml .= qq|&nbsp;|. iconlink("blockemail.gif", qq|$lang_text{'blockemail'} |.ow::htmltext::str2html($eaddr), qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;priority=20&amp;ruletype=from&amp;include=include&amp;text=|.ow::tool::escapeURL($eaddr).qq|&amp;destination=mail-trash&amp;enable=1" onclick="return confirm('$lang_text{blockemail} |.ow::htmltext::str2html($jseaddr).qq| ?');"|) . qq|\n|;
            if ($message{smtprelay} !~ /^\s*$/) {
               $temphtml .= qq|&nbsp; |.iconlink("blockrelay.gif", "$lang_text{'blockrelay'} $message{smtprelay}", qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;priority=20&amp;ruletype=smtprelay&amp;include=include&amp;text=$message{smtprelay}&amp;destination=mail-trash&amp;enable=1" onclick="return confirm('$lang_text{blockrelay} $message{smtprelay} ?');"|) . qq|\n|;
            }
         }
      }
      $temphtml .= "<BR>";

      if ($replyto ne '') {
         $temphtml .= "<B>$lang_text{'replyto'}:</B> $replyto<BR>\n";
      }

      my $dotstr=qq| <a href="$read_url_with_id&amp;action=readmessage&amp;attmode=$attmode&amp;receivers=all"><b>.....</b></a>|;
      if ($to ne '') {
         $to=substr($to,0,90).$dotstr if (length($to)>96 && param('receivers') ne "all");
         $temphtml .= qq|<B>$lang_text{'to'}:</B> $to<BR>\n|;
      }
      if ($cc ne '') {
         $cc=substr($cc,0,90).$dotstr if (length($cc)>96 && param('receivers') ne "all");
         $temphtml .= qq|<B>$lang_text{'cc'}:</B> $cc<BR>\n|;
      }
      if ($bcc ne '') {
         $bcc=substr($bcc,0,90).$dotstr if (length($bcc)>96 && param('receivers') ne "all");
         $temphtml .= qq|<B>$lang_text{'bcc'}:</B> $bcc<BR>\n|;
      }

      if ($subject ne '') {
         $temphtml .= qq|<B>$lang_text{'subject'}:</B> $subject\n|;
      }

      if ($printfriendly ne "yes") {
         if ($message{'priority'} eq 'urgent') {# display import icon
            $temphtml .= qq|&nbsp;|. iconlink("important.gif", "", "");
         }
         if ($message{'status'} =~ /a/i) {	# display read and answered icon
            $temphtml .= qq|&nbsp; |. iconlink("read.a.gif", "", "");
         }
      }
   }
   $html =~ s/\@\@\@HEADERS\@\@\@/$temphtml/;

   if ($headers eq "all") {
      $temphtml = qq|<a href="$read_url_with_id&amp;action=readmessage&amp;attmode=$attmode&amp;headers=simple&amp;convfrom=$convfrom">$lang_text{'simplehead'}</a>|;
   } else {
      $temphtml = qq|<a href="$read_url_with_id&amp;action=readmessage&amp;attmode=$attmode&amp;headers=all&amp;convfrom=$convfrom">$lang_text{'allhead'}</a>|;
   }
   $html =~ s/\@\@\@HEADERSTOGGLE\@\@\@/$temphtml/;

   if ( $#{$message{attachment}}>=0 ||
        $message{'content-type'}=~/^multipart/i ) {
      if ($attmode eq "all") {
         $temphtml = qq|<a href="$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=simple&amp;convfrom=$convfrom">$lang_text{'simpleattmode'}</a>|;
      } else {
         $temphtml = qq|<a href="$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=all&amp;convfrom=$convfrom">$lang_text{'allattmode'}</a>|;
      }
   } else {
      $temphtml="&nbsp;";
   }
   $html =~ s/\@\@\@ATTMODETOGGLE\@\@\@/$temphtml/;

   $temphtml=$body;
   # Note: attachment count >=0 is not necessary to be multipart!!!
   if ( $attmode eq 'all' ) {
      $temphtml .= hr() if ( $#{$message{attachment}}>=0 );
   } else {
      $temphtml="" if ( $message{'content-type'} =~ /^multipart/i );
   }

   my $onlyone_att=0; $onlyone_att=1 if ($#{$message{attachment}}==0);
   my $has_nontext_att=0;

   foreach my $attnumber (0 .. $#{$message{attachment}}) {
      next unless (defined %{$message{attachment}[$attnumber]});
      $has_nontext_att++ if (defined ${$message{attachment}[$attnumber]}{'content-type'} &&
                             ${$message{attachment}[$attnumber]}{'content-type'}!~/^text/i);
      my $attcharset=$convfrom;
      # if convfrom eq msgcharset, we try to get attcharset from attheader since it may differ from msgheader
      # but if convfrom ne msgcharset, which means user has spsecified other charset in interpreting the msg
      # which means the charset in attheader may be wrong either, then we use convfrom as attcharset
      if ($convfrom eq lc($message{'charset'})) {
         $attcharset=lc(${$message{attachment}[$attnumber]}{filenamecharset})||
                     lc(${$message{attachment}[$attnumber]}{charset})||
                     $convfrom;
      }

      if ( $attmode eq 'all' ) {
         if ( ${$message{attachment}[$attnumber]}{filename}=~/\.(?:jpg|jpeg|gif|png|bmp)$/i
            && !$prefs{'showimgaslink'} ) {
            $temphtml .= image_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
					$escapedmessageid, "&amp;convfrom=$convfrom");
         } else {
            $temphtml .= misc_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
					$escapedmessageid, "&amp;convfrom=$convfrom", 0);
         }

      } else {	# attmode==simple
         # handle case to skip to next text/html attachment
         if ( defined %{$message{attachment}[$attnumber+1]} &&
              (${$message{attachment}[$attnumber+1]}{boundary} eq
		  ${$message{attachment}[$attnumber]}{boundary}) ) {

            # skip to next text/(html|enriched) attachment in the same alternative group
            if ( (${$message{attachment}[$attnumber]}{subtype} =~ /alternative/i) &&
                 (${$message{attachment}[$attnumber+1]}{subtype} =~ /alternative/i) &&
                 (${$message{attachment}[$attnumber+1]}{'content-type'} =~ /^text/i) &&
                 (${$message{attachment}[$attnumber+1]}{filename}=~ /^Unknown\./ ) ) {
               next;
            }
            # skip to next attachment if this=unknown.(txt|enriched) and next=unknown.(html|enriched)
            if ( (${$message{attachment}[$attnumber]}{'content-type'}=~ /^text\/(?:plain|enriched)/i ) &&
                 (${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\./ ) &&
                 (${$message{attachment}[$attnumber+1]}{'content-type'} =~ /^text\/(?:html|enriched)/i)  &&
                 (${$message{attachment}[$attnumber+1]}{filename}=~ /^Unknown\./ ) ) {
               next;
            }
         }

         # handle display of attachments in simple mode
         if ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^text/i ) {
            if ( ${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\./ ||
                 $onlyone_att ) {
               my $content;
               if ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^text\/html/i ) {
                  $content=html_att2table($message{attachment}, $attnumber, $attcharset||$convfrom, $readcharset,
					$escapedmessageid, $showhtmlastext);
                  $is_htmlmsg=1;
               } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^text\/enriched/i ) {
                  $content=enriched_att2table($message{attachment}, $attnumber, $attcharset||$convfrom, $readcharset,
					$showhtmlastext);
                  $is_htmlmsg=1;
               } else {
                  $content=text_att2table($message{attachment}, $attnumber, $attcharset||$convfrom, $readcharset);
               }
               $temphtml .= $content;
            } else {
               # show misc attachment only if it is not referenced by other html
               if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
						$escapedmessageid, "&amp;convfrom=$convfrom");
               }
            }
         } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^message\/external\-body/i ) {
            # attachment external reference, not an real message
            $temphtml .= misc_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
					$escapedmessageid);
         } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^message\/partial/i ) {
            # fragmented message
            $temphtml .= misc_att2table($message{attachment}, $attnumber, $attcharset||$convfrom, $readcharset,
					$escapedmessageid);
         } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^message/i ) {
            # always show message/... attachment
            $temphtml .= message_att2table($message{attachment}, $attnumber, $attcharset||$convfrom, $readcharset,
					$style{"window_dark"});
         } elsif ( ${$message{attachment}[$attnumber]}{filename}=~ /\.(?:jpg|jpeg|gif|png|bmp)$/i ) {
            # show image only if it is not referenced by other html
            if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
               if (!$prefs{'showimgaslink'}) {
                  $temphtml .= image_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
						$escapedmessageid, "&amp;convfrom=$convfrom");
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
						$escapedmessageid, "&amp;convfrom=$convfrom");
               }
            }
         } elsif ( ${$message{attachment}[$attnumber]}{filename}=~ /\.(?:midi?|wav|mp3|ra|au|snd)$/i ) {
            # show sound only if it is not referenced by other html
            if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
					$escapedmessageid, "&amp;convfrom=$convfrom");
            }
         } else {
            # show misc attachment only if it is not referenced by other html
            if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $attcharset, $readcharset,
					$escapedmessageid, "&amp;convfrom=$convfrom", 1);
            }
         }

      }
   }
   $html =~ s/\@\@\@BODY\@\@\@/$temphtml/;

   if ($has_nontext_att>1) {
      $temphtml = qq|<a onclick="return confirm('$lang_text{'delete_nontextatt'} ?');" |.
                  qq|href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=deleteattachment&amp;|.
                  qq|message_id=$escapedmessageid&amp;nodeid=NONTEXT&amp;$urlparm&amp;headers=$headers&amp;attmode=$attmode&amp;convfrom=$convfrom">$lang_text{'delete_nontextatt'}</a>|.
                  qq|&nbsp;\n|;
   } else {
      $temphtml='';
   }
   $html =~ s/\@\@\@DELNONTEXTATT\@\@\@/$temphtml/;

   if ($is_htmlmsg) {
      $temphtml=qq|<a href="$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=simple&amp;convfrom=$convfrom&amp;showhtmlastext=|;
      if ($showhtmlastext) {
         $temphtml.=qq|0">+html+</a>|;
      } else {
         $temphtml.=qq|1">-html-</a>|;
      }
      $html =~ s!\@\@\@SHOWHTMLASTEXTLABEL\@\@\@!$temphtml!;
   } else {
      $html =~ s/\@\@\@SHOWHTMLASTEXTLABEL\@\@\@/&nbsp;/;
   }

   # if this is unread message, confirm to transmit read receipt if requested
   if ($message{status} !~ /R/i && $notificationto ne '') {
      if ($prefs{'sendreceipt'} eq 'ask') {
         $html.=qq|<script language="JavaScript">\n<!--\n|.
                qq|replyreceiptconfirm('$send_url_with_id&amp;action=replyreceipt', 0);\n|.
                qq|//-->\n</script>\n|;
      } elsif ($prefs{'sendreceipt'} eq 'yes') {
         $html.=qq|<script language="JavaScript">\n<!--\n|.
                qq|replyreceiptconfirm('$send_url_with_id&amp;action=replyreceipt', 1);\n|.
                qq|//-->\n</script>\n|;
      }
   }

   # play sound if number of new msg increases in INBOX
   if ( $now_inbox_newmessages>$orig_inbox_newmessages ) {
      if (-f "$config{'ow_htmldir'}/sounds/$prefs{'newmailsound'}" ) {
         $html.=qq|<embed src="$config{'ow_htmlurl'}/sounds/$prefs{'newmailsound'}" autostart="true" hidden="true">\n|;
      }
   }

   $temphtml='';
   # show quotahit del warning
   if ($quotahit_deltype ne '') {
      my $msg=qq|<font size="-1" color="#cc0000">$lang_err{$quotahit_deltype}</font>|;
      $msg=~s/\@\@\@QUOTALIMIT\@\@\@/$config{'quota_limit'}$lang_sizes{'kb'}/;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$readcharset', '$lang_text{"quotahit"}', '$msg', '$lang_text{"close"}', '_quotahit_del', 400, 100, 60);\n|.
                 qq|//-->\n</script>\n|;
   }
   # show quotahit alert
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      my $msg=qq|<font size="-1" color="#cc0000">$lang_err{'quotahit_alert'}</font>|;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$readcharset', '$lang_text{"quotahit"}', '$msg', '$lang_text{"close"}', '_quotahit_alert', 400, 100, 60);\n|.
                 qq|//-->\n</script>\n|;
   # show spool overlimit alert
   } elsif ($config{'spool_limit'}>0 && $inboxsize_k>$config{'spool_limit'}) {
      my $msg=qq|<font size="-1" color="#cc0000">$lang_err{'spool_overlimit'}</font>|;
      $msg=~s/\@\@\@SPOOLLIMIT\@\@\@/$config{'spool_limit'}$lang_sizes{'kb'}/;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$readcharset', '$lang_text{"quotahit"}', '$msg', '$lang_text{"close"}', '_spool_overlimit', 400, 100, 60);\n|.
                 qq|//-->\n</script>\n|;
   }
   # popup stat of incoming msgs
   if ($prefs{'newmailwindowtime'}>0) {
      my ($totalfiltered, %filtered)=read_filterfolderdb(1);
      if ($totalfiltered>0) {
         my $msg;
         my $line=0;
         foreach my $f (get_defaultfolders(), 'DELETE') {
            if ($filtered{$f}>0) {
               $msg .= qq|$lang_folders{$f} &nbsp; $filtered{$f}<br>|;
               $line++;
            }
         }
         foreach my $f (sort keys %filtered) {
            next if (is_defaultfolder($f));
            $msg .= f2u($f).qq| &nbsp; $filtered{$f}<br>|;
            $line++;
         }
         $msg = qq|<font size="-1">$msg</font>|;
         $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
         $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                    qq|showmsg('$readcharset', '$lang_text{"inmessages"}', '$msg', '$lang_text{"close"}', '_incoming', 160, |.($line*16+70).qq|, $prefs{'newmailwindowtime'});\n|.
                    qq|//-->\n</script>\n|;
      }
   }
   $html.=readtemplate('showmsg.js').$temphtml if ($temphtml);

   my $footermode=2;
   if ($printfriendly eq "yes") {
      $html.=qq|<script language="JavaScript">\n<!--\n|.
             qq|setTimeout("window.print()", 1*1000);\n|.
             qq|//-->\n</script>\n|;
      $footermode=0;
   }

   @tmp=();
   if ($readcharset ne $prefs{'charset'}) {
      @tmp=($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'});
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=('en_US', $readcharset, 'en_US.UTF-8');
   }

   # show unread inbox messages count in titlebar
   my $unread_messages_info;
   if ($now_inbox_newmessages>0) {
      $unread_messages_info = "$lang_folders{INBOX}: $now_inbox_newmessages $lang_text{'messages'} $lang_text{'unread'}";
   }
   httpprint([], [htmlheader($unread_messages_info), $html, htmlfooter($footermode)]);

   if ($#tmp>=1) {
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=@tmp;
   }

   # fork a child to do the status update and folderdb update
   # thus the result of readmessage can be returned as soon as possible
   if ($message{status} !~ /R/i) {	# msg file doesn't has R flag
      # below handler not necessary, as we call zombie_cleaner at end of each request
      #local $SIG{CHLD}=\&ow::tool::zombie_cleaner;

      local $|=1; 			# flush all output
      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         writelog("debug - update msg status process forked - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});

         my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
         ow::filelock::lock($folderfile, LOCK_EX) or openwebmail_exit(1);

         # since status in folderdb may have flags not found in msg header
         # we must read the status from folderdb and then update it back
         my @attr=get_message_attributes($messageid, $folderdb);
         update_message_status($messageid, $attr[$_STATUS]."R", $folderdb, $folderfile) if ($#attr>0);

         ow::filelock::lock($folderfile, LOCK_UN);

         writelog("debug - update msg status process terminated - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});
         openwebmail_exit(0);
      }
   } elsif (param('db_chkstatus')) { # check and set msg status R flag
      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
      my (%FDB, @attr);
      ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} db ".f2u($folderdb));
      @attr=string2msgattr($FDB{$messageid});
      if ($attr[$_STATUS] !~ /R/i) {
         $attr[$_STATUS].="R";
         $FDB{$messageid}=msgattr2string(@attr);
      }
      ow::dbm::close(\%FDB, $folderdb);
   }
   return;
}


sub html_att2table {
   my ($r_attachments, $attnumber, $attcharset, $readcharset, $escapedmessageid, $showhtmlastext)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $temphtml;

   if (${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable/i) {
      $temphtml = decode_qp(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^base64/i) {
      $temphtml = decode_base64(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^x-uuencode/i) {
      $temphtml = ow::mime::uudecode(${${$r_attachment}{r_content}});
   } else {
      $temphtml = ${${$r_attachment}{r_content}};
   }

   if ($showhtmlastext) {	# html -> text -> html
      $temphtml = ow::htmltext::html2text($temphtml);
      $temphtml = ow::htmltext::text2html($temphtml);
      # change color for quoted lines
      $temphtml =~ s!^(&gt;.*<br>)$!<font color=#009900>$1</font>!img;
      $temphtml =~ s/<a href=/<a class=msgbody href=/ig;
   } else {				# html rendering
      $temphtml = ow::htmlrender::html4nobase($temphtml);
      $temphtml = ow::htmlrender::html4noframe($temphtml);
      $temphtml = ow::htmlrender::html4link($temphtml);
      $temphtml = ow::htmlrender::html4disablejs($temphtml) if ($prefs{'disablejs'});
      $temphtml = ow::htmlrender::html4disableembcode($temphtml) if ($prefs{'disableembcode'});
      $temphtml = ow::htmlrender::html4disableemblink($temphtml, $prefs{'disableemblink'}, "$config{'ow_htmlurl'}/images/backgrounds/Transparent.gif") if ($prefs{'disableemblink'} ne 'none');
      $temphtml = ow::htmlrender::html4attachments($temphtml, $r_attachments, "$config{'ow_cgiurl'}/openwebmail-viewatt.pl", "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
      $temphtml = ow::htmlrender::html4mailto($temphtml, "$config{'ow_cgiurl'}/openwebmail-send.pl",
                  "sessionid=$thissession&amp;folder=$escapedfolder&amp;page=$page&amp;".
                  "sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;".
                  "action=composemessage&amp;message_id=$escapedmessageid&amp;compose_caller=read");
   }
   $temphtml = ow::htmlrender::html2table($temphtml);
   ($temphtml)=iconv($attcharset, $readcharset, $temphtml);

   return($temphtml);
}

sub enriched_att2table {
   my ($r_attachments, $attnumber, $attcharset, $readcharset, $showhtmlastext)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $temphtml;

   if (${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable/i) {
      $temphtml = decode_qp(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^base64/i) {
      $temphtml = decode_base64(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^x-uuencode/i) {
      $temphtml = ow::mime::uudecode(${${$r_attachment}{r_content}});
   } else {
      $temphtml = ${${$r_attachment}{r_content}};
   }
   $temphtml = ow::enriched::enriched2html($temphtml);
   if ($showhtmlastext) {	# html -> text -> html
      $temphtml = ow::htmltext::html2text($temphtml);
      $temphtml = ow::htmltext::text2html($temphtml);
      # change color for quoted lines
      $temphtml =~ s!^(&gt;.*<br>)$!<font color=#009900>$1</font>!img;
      $temphtml =~ s/<a href=/<a class=msgbody href=/ig;
   }
   $temphtml = ow::htmlrender::html2table($temphtml);
   ($temphtml)=iconv($attcharset, $readcharset, $temphtml);

   return($temphtml);
}

sub text_att2table {
   my ($r_attachments, $attnumber, $attcharset, $readcharset)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $temptext;

   if (${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable/i) {
      $temptext = decode_qp(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^base64/i) {
      $temptext = decode_base64(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^x-uuencode/i) {
      $temptext = ow::mime::uudecode(${${$r_attachment}{r_content}});
   } else {
      $temptext = ${${$r_attachment}{r_content}};
   }

   # remove odds space or blank lines
   $temptext =~ s/(\r?\n){2,}/\n\n/g;
   $temptext =~ s/^\s+//;
   $temptext =~ s/\n\s*$/\n/;
   if ($prefs{'usesmileicon'}) {
      $temptext =~ s/(^|\D)(>?)([:;8])[-^]?([\(\)\>\<\|PpDdOoX\\\/])([\s\<])/$1 SMILY_$smilies{"$2$3$4"}\.png $5/g;
      $temptext = ow::htmltext::text2html($temptext);
      $temptext =~ s/SMILY_(.+?\.png)/<img border="0" width="12" height="12" src="$config{'ow_htmlurl'}\/images\/smilies\/$1">/g;
   } else {
      $temptext = ow::htmltext::text2html($temptext);
   }
   $temptext =~ s/<a href=/<a class=msgbody href=/ig;
   ($temptext)=iconv($attcharset, $readcharset, $temptext);

   return($temptext. "<BR>");
}

sub message_att2table {
   my ($r_attachments, $attnumber, $attcharset, $readcharset, $headercolor)=@_;
   $headercolor='#dddddd' if ($headercolor eq '');

   my $r_attachment=${$r_attachments}[$attnumber];
   my $temptext;

   if (${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable/i) {
      $temptext = decode_qp(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^base64/i) {
      $temptext = decode_base64(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^x-uuencode/i) {
      $temptext = ow::mime::uudecode(${${$r_attachment}{r_content}});
   } else {
      $temptext = ${${$r_attachment}{r_content}};
   }

   my ($header, $body)=split(/\n\r*\n/, $temptext, 2);
   my %msg;
   $msg{'content-type'}='N/A';	# assume msg is simple text
   ow::mailparse::parse_header(\$header, \%msg);
   $attcharset=$1 if ($msg{'content-type'}=~/charset="?([^\s"';]*)"?\s?/i);

   $header=simpleheader($header);
   $header=ow::htmltext::text2html($header);

   if ($msg{'content-type'} =~ /^text/i) {
      if ($msg{'content-transfer-encoding'} =~ /^quoted-printable/i) {
          $body = decode_qp($body);
      } elsif ($msg{'content-transfer-encoding'} =~ /^base64/i) {
          $body = decode_base64($body);
      } elsif ($msg{'content-transfer-encoding'} =~ /^x-uuencode/i) {
          $body = ow::mime::uudecode($body);
      }
   }
   if ($msg{'content-type'} =~ m#^text/html#i) { # convert into html table
      $body = ow::htmlrender::html4nobase($body);
      $body = ow::htmlrender::html4disablejs($body) if ($prefs{'disablejs'});
      $body = ow::htmlrender::html4disableembcode($body) if ($prefs{'disableembcode'});
      $body = ow::htmlrender::html4disableemblink($body, $prefs{'disableemblink'}, "$config{'ow_htmlurl'}/images/backgrounds/Transparent.gif") if ($prefs{'disableemblink'} ne 'none');
      $body = ow::htmlrender::html2table($body);
   } else {
      $body = ow::htmltext::text2html($body);
      $body =~ s/<a href=/<a class=msgbody href=/ig;
   }
   ($header, $body)=iconv($attcharset, $readcharset, $header, $body);

   # header lang_text replacement should be done after iconv
   $header=~s!Date: !<B>$lang_text{'date'}:</B> !i;
   $header=~s!From: !<B>$lang_text{'from'}:</B> !i;
   $header=~s!Reply-To: !<B>$lang_text{'replyto'}:</B> !i;
   $header=~s!To: !<B>$lang_text{'to'}:</B> !i;
   $header=~s!Cc: !<B>$lang_text{'cc'}:</B> !i;
   $header=~s!Subject: !<B>$lang_text{'subject'}:</B> !i;

   # be aware the message header are keep untouched here
   # in order to make it easy for further parsing
   my $temphtml=qq|<table width="100%" border=0 cellpadding=2 cellspacing=0>\n|.
                qq|<tr bgcolor=$headercolor><td class="msgbody">\n|.
                qq|$header\n|.
                qq|</td></tr>\n|.
                qq|\n\n|.
                qq|<tr><td class="msgbody">\n|.
                qq|$body\n|.
                qq|</td></tr></table>|;
   return($temphtml);
}

sub image_att2table {
   my ($r_attachments, $attnumber, $attcharset, $readcharset, $escapedmessageid, $extraparm)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $filename=${$r_attachment}{filename};
   my $description=${$r_attachment}{'content-description'};
   ($filename, $description)=iconv($attcharset, $readcharset, $filename, $description);

   my $attlen=lenstr(${$r_attachment}{'content-length'},1);
   my $nodeid=${$r_attachment}{nodeid};
   my $disposition=substr(${$r_attachment}{'content-disposition'},0,1);
   my $escapedfilename = ow::tool::escapeURL($filename);
   my $jsfilename=$filename; $jsfilename=~ s/'/\\'/g;	# escape ' with \'

   my $temphtml .= qq|<table border="0" align="center" cellpadding="2">|.
                   qq|<tr><td bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: |.ow::htmltext::str2html($filename).qq| &nbsp;($attlen)&nbsp;&nbsp;|;
   $temphtml .= qq|<a onclick="return confirm('$lang_text{delete} $jsfilename?');" |.
                qq|href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=deleteattachment&amp;|.
                qq|message_id=$escapedmessageid&amp;nodeid=$nodeid&amp;$urlparm$extraparm">$lang_text{'delete'}</a>|.
                qq|&nbsp;\n|;
   if ($config{'enable_webdisk'} && !$config{'webdisk_readonly'}) {
      $temphtml .= qq|<a href=#here title="$lang_text{'saveatt_towd'}" onClick="window.open('$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=sel_saveattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm&amp;attname=$escapedfilename&amp;attnamecharset=$readcharset|.
                   qq|', '_blank','width=500,height=330,scrollbars=yes,resizable=yes,location=no');">$lang_text{'webdisk'}</a>|.
                   qq|&nbsp;\n|;
   }
   $temphtml .= qq|<font color=$style{"attachment_dark"} class="smalltext">$nodeid $disposition</font>|.
                qq|</td></tr>|.
                qq|<tr><td bgcolor=$style{"attachment_light"} align="center">|.
                qq|<a href="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm" title="$lang_text{'download'}">|.
                qq|<img border="0" |;
   $temphtml .= qq|alt="$description" | if ($description ne "");
   $temphtml .= qq|SRC="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm">|.
                qq|</a>|.
                qq|</td></tr></table>|;
   return($temphtml);
}

sub misc_att2table {
   my ($r_attachments, $attnumber, $attcharset, $readcharset, $escapedmessageid, $extraparm, $checktnef)=@_;
   my $r_attachment=${$r_attachments}[$attnumber];
   my $filename=${$r_attachment}{filename};
   my $contenttype=${$r_attachment}{'content-type'}; $contenttype =~ s/^(.+?);.*/$1/g;
   my $description=${$r_attachment}{'content-description'};

   if ($checktnef && $contenttype=~/^application\/ms\-tnef/i) {
      my ($arcname, @filelist)=tnef_att2namelist($filename, ${$r_attachment}{'content-transfer-encoding'}, ${$r_attachment}{'r_content'});
      if ($arcname ne '') {
         $filename=$arcname;
         $contenttype=ow::tool::ext2contenttype($filename);
         $description='encapsulated as ms-tnef';
         $description=ow::htmltext::str2html(join(', ', @filelist)).' '.$description if ($#filelist>0);
      } else {
         $description='unrecognized ms-tnef ?';
      }
      if (${$r_attachment}{'content-description'} ne '') {
         $description.= ", ${$r_attachment}{'content-description'}";
      }
   }
   ($filename, $description)=iconv($attcharset, $readcharset, $filename, $description);

   my $escapedfilename = ow::tool::escapeURL($filename);
   my $jsfilename=$filename; $jsfilename=~ s/'/\\'/g;	# escaep ' with \'
   my $attlen=lenstr(${$r_attachment}{'content-length'},1);
   my $nodeid=${$r_attachment}{nodeid};
   my $disposition=substr(${$r_attachment}{'content-disposition'},0,1);
   my $attlink="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm";

   my $temphtml .= qq|<table border="0" width="40%" align="center" cellpadding="2">|.
                   qq|<tr><td nowrap colspan="2" bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: |.ow::htmltext::str2html($filename). qq|&nbsp;($attlen)&nbsp;&nbsp;\n|;
   $temphtml .= qq|<a onclick="return confirm('$lang_text{delete} $jsfilename?');" |.
                qq|href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=deleteattachment&amp;|.
                qq|message_id=$escapedmessageid&amp;nodeid=$nodeid&amp;$urlparm$extraparm">$lang_text{'delete'}</a>|.
                qq|&nbsp;\n|;
   if ($filename=~/\.(?:doc|dot)$/ ) {
      $temphtml .= qq|<a href="$attlink&amp;wordpreview=1" target="_blank">$lang_wdbutton{'preview'}</a>|.
                   qq|\n|;
   }
   if ($config{'enable_webdisk'} && !$config{'webdisk_readonly'}) {
      $temphtml .= qq|<a href=#here title="$lang_text{'saveatt_towd'}" onClick="window.open('$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=sel_saveattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm&amp;attname=$escapedfilename&amp;attnamecharset=$readcharset|.
                   qq|', '_blank','width=500,height=330,scrollbars=yes,resizable=yes,location=no');">$lang_text{'webdisk'}</a>|.
                   qq|&nbsp;\n|;
   }
   $temphtml .= qq|<font color=$style{"attachment_dark"} class="smalltext">$nodeid $disposition|.
                qq|</td></tr>|.
                qq|<tr><td nowrap bgcolor= $style{"attachment_light"} align="center">|.
                qq|$lang_text{'type'}: |.ow::htmltext::str2html($contenttype).qq|<br>|.
                qq|$lang_text{'encoding'}: |.ow::htmltext::str2html(${$r_attachment}{'content-transfer-encoding'});
   if ($description ne "") {
      $temphtml .= qq|<br>$lang_text{'description'}: |.ow::htmltext::str2html($description);
   }
   my $blank="";
   if ($contenttype=~/^text/ || $filename=~/\.(?:jpg|jpeg|gif|png|bmp)$/i) {
      $blank="target=_blank";
   }
   $temphtml .= qq|</td><td nowrap width="10%" bgcolor= $style{"attachment_light"} align="center">|.
                qq|<a href="$attlink" $blank>$lang_text{'download'}</a>|.
                qq|</td></tr></table>|;
   return($temphtml);
}

sub tnef_att2namelist {
   my ($attfilename, $attencoding, $r_content)=@_;
   my $tnefbin=ow::tool::findbin('tnef'); return '' if ($tnefbin eq '');
   my @filelist;
   if ($attencoding =~ /^quoted-printable/i) {
      my $tnefdata = decode_qp(${$r_content});
      @filelist=ow::tnef::get_tnef_filelist($tnefbin, \$tnefdata);
   } elsif ($attencoding =~ /^base64/i) {
      my $tnefdata = decode_base64(${$r_content});
      @filelist=ow::tnef::get_tnef_filelist($tnefbin, \$tnefdata);
   } else {
      @filelist=ow::tnef::get_tnef_filelist($tnefbin, $r_content);
   }
   if ($#filelist==0) {
      return($filelist[0], @filelist);
   } elsif ($#filelist>0) {
      my $arcbasename = $attfilename; $arcbasename=~s/\.[\w\d]{0,4}$//;
      if (ow::tool::findbin('zip') ne '') {
         return($arcbasename.'.zip', @filelist);
      } elsif (ow::tool::findbin('tar') ne '') {
         if (ow::tool::findbin('gzip') ne '') {
            return($arcbasename.'.tgz', @filelist);
         } else {
            return($arcbasename.'.tar', @filelist);
         }
      }
   }
   return '';
}
########## END READMESSAGE #######################################

########## REBUILDMESSAGE ########################################
sub rebuildmessage {
   my $partialid = $_[0];
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");

   my ($errorcode, $rebuildmsgid, @partialmsgids)=
	rebuild_message_with_partialid($folderfile, $folderdb, $partialid);

   ow::filelock::lock($folderfile, LOCK_UN);

   if ($errorcode==0) {
      # move partial msgs to trash folder
      my ($trashfile, $trashdb)=get_folderpath_folderdb($user, "mail-trash");
      if ($folderfile ne $trashfile) {
         ow::filelock::lock($trashfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $trashfile");
         my $moved=(operate_message_with_ids("move", \@partialmsgids, $folderfile, $folderdb, $trashfile, $trashdb))[0];
         folder_zapmessages($folderfile, $folderdb) if ($moved>0);
         ow::filelock::lock($trashfile, LOCK_UN);
      }

      readmessage($rebuildmsgid);
      writelog("rebuild message - rebuild $rebuildmsgid in $folder");
      writehistory("rebuild message - rebuild $rebuildmsgid from $folder");
   } else {
      my ($html, $temphtml);
      $html = applystyle(readtemplate("rebuildfailed.template"));

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
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$errormsg/;

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl").
                  ow::tool::hiddens(action=>'readmessage',
                                    page=>$page,
                                    sort=>$sort,
                                    keyword=>$keyword,
                                    searchtype=>$searchtype,
                                    folder=>$escapedfolder,
                                    headers=>param('headers') ||$prefs{'headers'} || 'simple',
                                    attmode=>param('attmode') || 'simple',
                                    sessionid=>$thissession,
                                    message_id=>param('message_id')||'').
                  submit("$lang_text{'continue'}").
                  end_form();
      $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

      httpprint([], [htmlheader(), $html, htmlfooter(2)]);
   }
}
########## END REBUILDMESSGAE ####################################

########## DEL_ATTACHMENT_FROM_MESSAGE ###########################
sub del_attachment_from_message {
   my ($user, $folder, $messageid, $nodeid)=@_;
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my @attr=get_message_attributes($messageid, $folderdb);

   my ($block, $msgsize, $err, $errmsg, %message);
   ($msgsize, $errmsg)=lockget_message_block($messageid, $folderfile, $folderdb, \$block);
   return ($msgsize, $errmsg) if ($msgsize<=0);
   ($message{header}, $message{body}, $message{attachment})
		=ow::mailparse::parse_rfc822block(\$block, "0", "all");
   return 0 if (!defined @{$message{attachment}});

   my @datas;
   my $boundary = "----=OPENWEBMAIL_ATT_" . rand();
   my $contenttype_line=0;
   foreach (split(/\n/, $message{header})) {
      if (/^Content\-Type:/i) {
         $contenttype_line=1;
         $datas[0].= qq|Content-Type: multipart/mixed;\n|.
                     qq|\tboundary="$boundary"\n|;
      } else {
         next if (/^\s/ && $contenttype_line);
         $contenttype_line=0;
         $datas[0].= "$_\n";
      }
   }
   $attr[$_HEADERCHKSUM]=ow::tool::calc_checksum(\$datas[0]);
   $attr[$_HEADERSIZE]=length($datas[0]);

   push(@datas, "\n");
   push(@datas, $message{body});

   my @att=@{$message{attachment}};
   my $has_namedatt=0;
   my $delatt=0;
   foreach my $i (0 .. $#att) {
      if ($nodeid eq 'NONTEXT') {
         if (${$att[$i]}{'content-type'}!~/^text/i) { $delatt++; next }
      } else {
         if (${$att[$i]}{nodeid} eq $nodeid) { $delatt++; next }
      }

      push(@datas, "\n--$boundary\n");
      push(@datas, ${$att[$i]}{header});
      push(@datas, "\n");
      push(@datas, ${${$att[$i]}{r_content}});

      $has_namedatt++ if (${$att[$i]}{filename}!~/^Unknown\./);
   }
   push(@datas, "\n--$boundary--\n\n");
   return 0 if ($delatt==0);

   $block=join('', @datas);
   $attr[$_SIZE]=length($block);
   $attr[$_STATUS]=~s/T// if (!$has_namedatt);

   ow::filelock::lock($folderfile, LOCK_EX) or return(-2, "$folderfile write lock error");
   ($err, $errmsg)=append_message_to_folder($messageid, \@attr, \$block, $folderfile, $folderdb);
   if ($err==0) {
      my $zapped=folder_zapmessages($folderfile, $folderdb);
      if ($zapped<0) {
         my $m="mailfilter - $folderfile zap error $zapped"; writelog($m); writehistory($m);
      }
   }
   ow::filelock::lock($folderfile, LOCK_UN);

   return ($err, $errmsg) if ($err<0);
   return 0;
}
########## END DEL_ATTACHMENT_FROM_MESSAGE #######################
