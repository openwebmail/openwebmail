#!/usr/bin/suidperl -T
#
# openwebmail-read.pl - message reading program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1 }
if ($SCRIPT_DIR eq '' && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1 }
}
if ($SCRIPT_DIR eq '') { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

foreach (qw(PATH ENV BASH_ENV CDPATH IFS TERM)) { $ENV{$_}='' }	# secure ENV
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
require "modules/mailparse.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/cut.pl";
require "shares/getmsgids.pl";
require "shares/getmessage.pl";
require "shares/mailfilter.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_wdbutton %lang_text %lang_err);	# defined in lang/xy
use vars qw(%charset_convlist);			# defined in iconv.pl
use vars qw($_STATUS);				# defined in maildb.pl
use vars qw(%is_defaultfolder @defaultfolders);	# defined in ow-shared.pl

# local globals
use vars qw($folder);
use vars qw($sort $page $longpage);
use vars qw($searchtype $keyword);
use vars qw($escapedfolder $escapedkeyword);

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
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop
$SIG{CHLD}='IGNORE';		# prevent zombie

userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = param('folder') || 'INBOX';
$page = param('page') || 1;
$longpage = param('longpage') || 0;
$sort = param('sort') || $prefs{'sort'} || 'date';
$searchtype = param('searchtype') || 'subject';
$keyword = param('keyword') || '';

$escapedfolder = ow::tool::escapeURL($folder);
$escapedkeyword = ow::tool::escapeURL($keyword);

my $action = param('action')||'';
if ($action eq "readmessage") {
   readmessage(param('message_id')||'');
} elsif ($action eq "rebuildmessage") {
   rebuildmessage(param('partialid')||'');
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

openwebmail_requestend();
########## END MAIN ##############################################

########## READMESSAGE ###########################################
sub readmessage {
   my $messageid = $_[0];

   # filter junkmail at inbox beofre display any message in inbox
   my ($filtered, $r_filtered);
   ($filtered, $r_filtered)=filtermessage2($user, 'INBOX', \%prefs) if ($folder eq 'INBOX');

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
   my ($totalsize, $newmessages, $r_messageids)=getinfomessageids($user, $folder, $sort, $searchtype, $keyword);
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
      print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&page=$page&sessionid=$thissession&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder");
      return;
   }

   my %message = %{&getmessage($user, $folder, $messageid)};

   $page=int($message_num/($prefs{'msgsperpage'}||10)+0.999999)||$page;

   my $headers = param('headers') || $prefs{'headers'} || 'simple';
   my $attmode = param('attmode') || 'simple';
   my $printfriendly = param('printfriendly') ||'';

   my $showhtmlastext=$prefs{'showhtmlastext'};
   $showhtmlastext=param('showhtmlastext') if (param('showhtmlastext') ne "");

   my $convfrom=param('convfrom')||lc($message{'charset'});
   if ($convfrom eq '' && $prefs{'charset'} eq 'utf-8') {
      $convfrom=$ow::lang::languagecharsets{ow::lang::guess_language()};
   }
   $convfrom="none.$prefs{'charset'}" if ($convfrom!~/^none\./ && !is_convertable($convfrom, $prefs{'charset'}));
   my $readcharset=$prefs{'charset'};	# charset choosed by user to read current message
   $readcharset=$1 if ($convfrom=~/^none\.(.+)$/);	# read msg with no conversion

   my $urlparm="sessionid=$thissession&amp;folder=$escapedfolder&amp;".
               "page=$page&amp;longpage=$longpage&amp;".
               "sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype";
   my $main_url = "$config{'ow_cgiurl'}/openwebmail-main.pl?$urlparm";
   my $read_url = "$config{'ow_cgiurl'}/openwebmail-read.pl?$urlparm";
   my $send_url = "$config{'ow_cgiurl'}/openwebmail-send.pl?$urlparm";
   my $read_url_with_id = "$read_url&amp;message_id=$escapedmessageid";
   my $send_url_with_id = "$send_url&amp;message_id=$escapedmessageid".
                          "&amp;showhtmlastext=$showhtmlastext&amp;compose_caller=read";

   my ($html, $temphtml, @tmp);
   my $templatefile="readmessage.template";
   $templatefile="printmessage.template" if ($printfriendly eq 'yes');

   # temporarily switch lang/charset if user want original charset
   if ($readcharset ne $prefs{'charset'}) {
      @tmp=($prefs{'language'}, $prefs{'charset'});
      ($prefs{'language'}, $prefs{'charset'})=('en', $readcharset);
      loadlang($prefs{'language'});
   }
   $html=applystyle(readtemplate($templatefile));
   if ($#tmp>=1) {
      ($prefs{'language'}, $prefs{'charset'})=@tmp;
   }

   if ( $lang_folders{$folder} ) {
      $html =~ s/\@\@\@FOLDER\@\@\@/$lang_folders{$folder}/;
   } else {
      $html =~ s/\@\@\@FOLDER\@\@\@/$folder/;
   }

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

   if (is_convertable($convfrom, $readcharset) ) {
      ($from,$replyto,$to,$cc,$bcc,$subject,$body)
	=iconv($convfrom, $readcharset, $from,$replyto,$to,$cc,$bcc,$subject,$body);
   }

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

   $html =~ s/\@\@\@MESSAGETOTAL\@\@\@/$message_total/;

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder), qq|accesskey="B" href="$main_url&amp;action=listmessages"|);

   $temphtml .= "&nbsp;\n";

   # quota or spool over the limit
   my $inboxsize_k=(-s (get_folderpath_folderdb($user, 'INBOX'))[0])/1024;
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
      }
      $temphtml .= "&nbsp;\n";
   }

   $temphtml .= iconlink("print.gif", $lang_text{'printfriendly'}, qq|href=#here onClick="javascript:window.open('$read_url_with_id&amp;action=readmessage&amp;headers=$headers&amp;attmode=simple&amp;convfrom=$convfrom&amp;printfriendly=yes','_print', 'width=720,height=360,resizable=yes,menubar=yes,scrollbars=yes')"|);
   $temphtml .= "&nbsp;\n";

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
      $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;sort=$sort&amp;page=$page&amp;prefs_caller=read"|);
   }
   $temphtml .= iconlink("logout.gif","$lang_text{'logout'} $prefs{'email'}", qq|accesskey="Q" href="$main_url&amp;action=logout"|) . qq| \n|;

   $html =~ s/\@\@\@LEFTMENUBARLINKS\@\@\@/$temphtml/;

   $temphtml='';
   if ($folder ne 'mail-trash') {
      my $trashfolder='mail-trash';
      $trashfolder='DELETE' if ($quotalimit>0 && $quotausage>=$quotalimit);
      my $url=qq|accesskey="Z" href="$main_url&amp;action=movemessage&amp;message_ids=$escapedmessageid&amp;message_id=$escapedmessageaftermove&amp;destination=$trashfolder&amp;headers=$headers&amp;attmode=$attmode|;
      $url .= qq|&amp;messageaftermove=1| if ($messageaftermove && $prefs{'viewnextaftermsgmovecopy'});
      $url .= qq|" |;
      $url .= qq|onClick="return confirm($lang_text{'msgmoveconf'})"| if ($prefs{'confirmmsgmovecopy'});
      $temphtml = iconlink("totrash.gif", $lang_text{'totrash'}, $url);
   }
   $temphtml .= "&nbsp;\n";

   $html =~ s/\@\@\@RIGHTMENUBARLINKS\@\@\@/$temphtml/;

   my $gif;
   $temphtml='';
   if ($messageid_prev ne '') {
      $gif="left.s.gif"; $gif="right.s.gif" if ($ow::lang::RTL{$prefs{'language'}});
      $temphtml .= iconlink($gif, "&lt;", qq|accesskey="U" href="$read_url&amp;message_id=|.ow::tool::escapeURL($messageid_prev).qq|&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode"|);
   } else {
      $gif="left-grey.s.gif"; $gif="right-grey.s.gif" if ($ow::lang::RTL{$prefs{'language'}});
      $temphtml .= iconlink($gif, "-", "");
   }
   $temphtml.=qq|$message_num|;
   if ($messageid_next ne '') {
      my $gif="right.s.gif"; $gif="left.s.gif" if ($ow::lang::RTL{$prefs{'language'}});
      $temphtml .= iconlink($gif, "&gt;", qq|accesskey="D" href="$read_url&amp;message_id=|.ow::tool::escapeURL($messageid_next).qq|&amp;action=readmessage&amp;headers=$headers&amp;attmode=$attmode"|);
   } else {
      my $gif="right-grey.s.gif"; $gif="left-grey.s.gif" if ($ow::lang::RTL{$prefs{'language'}});
      $temphtml .= iconlink($gif, "-", "");
   }
   $html =~ s/\@\@\@MESSAGECONTROL\@\@\@/$temphtml/g;

   $temphtml = iconlink("gotop.gif", "^", qq|href="#"|);
   $html =~ s/\@\@\@TOPCONTROL\@\@\@/$temphtml/;


   my ($htmlconv, $htmlstat, $htmlmove);

   # charset conversion menu
   if(defined($charset_convlist{$prefs{'charset'}}) ) {
      my (@cflist, %cflabels, %allsets, $cf);
      foreach (values %ow::lang::languagecharsets, keys %charset_convlist) {
         $allsets{$_}=1 if (!defined($allsets{$_}));
      }

      $cf="none.".lc($message{'charset'}); # readmsg with orig charset and no conversion
      push(@cflist, $cf); $cflabels{$cf}=(lc($message{'charset'})||$lang_text{'none'})." *";
      delete $allsets{$cf};

      $cf="none.$prefs{'charset'}";	# readmsg with prefs charset and no conversion
      if (!defined($cflabels{$cf})) {
         push(@cflist, $cf); $cflabels{$cf}=$prefs{'charset'};
         delete $allsets{$prefs{'charset'}};
      }

      $cf=lc($message{'charset'});	# readmsg with prefs charset and conversion
      if ($cf ne "" && $cf ne $prefs{'charset'} && is_convertable($cf, $prefs{'charset'})) {
         push(@cflist, $cf); $cflabels{$cf}="$cf > $prefs{'charset'}";
         delete $allsets{$cf};
      }
      foreach $cf (@{$charset_convlist{$prefs{'charset'}}}) {
         if (!defined($cflabels{$cf})) {
            push(@cflist, $cf); $cflabels{$cf}="$cf > $prefs{'charset'}";
            delete $allsets{$cf};
         }
      }

      foreach (sort keys %allsets) {	# readmsg with other charset and no conversion
         $cf="none.$_";
         next if (defined($cflabels{$cf}));
         push(@cflist, $cf); $cflabels{$cf}=$_;
      }

      $htmlconv = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl").
                  ow::tool::hiddens(action=>'readmessage',
                                    page=>$page,
                                    sort=>$sort,
                                    keyword=>$keyword,
                                    searchtype=>$searchtype,
                                    folder=>$folder,
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

   # reply with stationary selection
   if ( $folder ne 'saved-drafts' && $folder ne 'sent-mail' &&
        $config{'enable_stationery'} ) {
      my (@stationery,%escstat);
      push(@stationery, $lang_text{'statreply'});

      my $statbookfile=dotpath('stationery.book');
      if ( -f $statbookfile ) {
         open (STATBOOK, $statbookfile) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $statbookfile! ($!)");
         while (<STATBOOK>) {
            my ($name, $content) = split(/\@\@\@/, $_, 2);
            chomp($name); chomp($content);
            push(@stationery,ow::tool::escapeURL($name));
            $escstat{ow::tool::escapeURL($name)} = $name;
         }
         close (STATBOOK) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $statbookfile! ($!)");
      }

      $htmlstat = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-send.pl",
                            -name=>'ReplyWith').
                  ow::tool::hiddens(sessionid=>$thissession,
                                    message_id=>$messageid,
                                    folder=>$folder,
                                    sort=>$sort,
                                    page=>$page,
                                    convfrom=>$convfrom,
                                    action=>'composemessage',
                                    composetype=>'reply',
                                    compose_caller=>'read').
                  qq|<table cellspacing=0 cellpadding=0 border=0><tr vlign=center>$htmlstat<td>|.
                  popup_menu(-name=>'statname',
                             -values=>\@stationery,
                             -labels=>\%escstat,
                             -onChange=>'JavaScript:document.ReplyWith.submit();',
                             -override=>'1').
                  qq|</td><td>|.
                  iconlink("editst.s.gif", $lang_text{'editstat'}, qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editstat&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;sort=$sort&amp;page=$page"|).
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
                                 folder=>$folder,
                                 headers=>$headers,
                                 message_ids=>$messageid,
                                 message_id=>$messageaftermove);
   if ($messageaftermove && $prefs{'viewnextaftermsgmovecopy'}) {
      $htmlmove .= ow::tool::hiddens(messageaftermove=>'1');
   }

   my @movefolders;
   foreach my $checkfolder (@validfolders) {
   #  if ( ($checkfolder ne 'INBOX') && ($checkfolder ne $folder) )
      if ($checkfolder ne $folder) {
         push (@movefolders, $checkfolder);
      }
   }
   # option to del message directly from folder
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      @movefolders=('DELETE');
   } else {
      push(@movefolders, 'DELETE');
   }
   my $defaultdestination;
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      $defaultdestination='DELETE';
   } elsif ($folder eq 'mail-trash') {
      $defaultdestination='saved-messages';
   } elsif ($folder eq 'sent-mail' || $folder eq 'saved-drafts') {
      $defaultdestination='mail-trash';
   } else {
      my $smartdestination;
      if ($prefs{'smartdestination'}) {
         my $subject=$message{'subject'}; $subject=~s/\s//g;
         foreach (@movefolders) {
            next if ($_ eq "DELETE");
            if ($subject=~/\Q$_\E/i || $message{'from'}=~/\Q$_\E/i) {
               $smartdestination=$_; last;
            }
         }
      }
      $defaultdestination=$smartdestination || $prefs{'defaultdestination'} || 'mail-trash';
      $defaultdestination='mail-trash' if ( $folder eq $defaultdestination);
   }

   $htmlmove = qq|<table cellspacing=0 cellpadding=0 border=0><tr>$htmlmove<td nowrap>|.
               popup_menu(-name=>'destination',
                          -values=>\@movefolders,
                          -default=>$defaultdestination,
                          -labels=>\%lang_folders,
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
      $temphtml = ow::mime::decode_mimewords($message{header});
      if (is_convertable($convfrom, $readcharset) ) {
         ($temphtml)=iconv($convfrom, $readcharset, $temphtml);
      }
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
      $temphtml .= qq|<B>$lang_text{'from'}:</B> <a href="http://www.google.com/search?q=$eaddr" title="google $lang_text{'search'}..." target="_blank">$from</a>&nbsp; \n|;
      if ($printfriendly ne "yes") {
         $temphtml .= qq|&nbsp;|. iconlink("import.s.gif",   "$lang_text{'importadd'} $eaddr",  qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addaddress&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;realname=|.ow::tool::escapeURL($ename).qq|&amp;email=|.ow::tool::escapeURL($eaddr).qq|&amp;usernote=_reserved_" onclick="return confirm('$lang_text{importadd} $eaddr ?');"|) . qq|\n|;
         $temphtml .= qq|&nbsp;|. iconlink("blockemail.gif", "$lang_text{'blockemail'} $eaddr", qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;priority=20&amp;ruletype=from&amp;include=include&amp;text=$eaddr&amp;destination=mail-trash&amp;enable=1" onclick="return confirm('$lang_text{blockemail} $eaddr ?');"|) . qq|\n|;
         if ($message{smtprelay} !~ /^\s*$/) {
            $temphtml .= qq|&nbsp; |.iconlink("blockrelay.gif", "$lang_text{'blockrelay'} $message{smtprelay}", qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;priority=20&amp;ruletype=smtprelay&amp;include=include&amp;text=$message{smtprelay}&amp;destination=mail-trash&amp;enable=1" onclick="return confirm('$lang_text{blockrelay} $message{smtprelay} ?');"|) . qq|\n|;
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

   my $onlyone_att=0;
   $onlyone_att=1 if ($#{$message{attachment}}==0);

   foreach my $attnumber (0 .. $#{$message{attachment}}) {
      next unless (defined(%{$message{attachment}[$attnumber]}));

      my $charset=$convfrom;
      if ($convfrom eq lc($message{'charset'})) {	# get convfrom from attheader is it was from msgheader
         $charset=lc(${$message{attachment}[$attnumber]}{filenamecharset})||
                  lc(${$message{attachment}[$attnumber]}{charset})||
                  $convfrom;
      }
      if (is_convertable($charset, $readcharset)) {
         (${$message{attachment}[$attnumber]}{filename})
		=iconv($charset, $readcharset, ${$message{attachment}[$attnumber]}{filename});
      }

      if ( $attmode eq 'all' ) {
         if ( ${$message{attachment}[$attnumber]}{filename}=~/\.(?:jpg|jpeg|gif|png|bmp)$/i
            && !$prefs{'showimgaslink'} ) {
            $temphtml .= image_att2table($message{attachment}, $attnumber, $escapedmessageid, "&amp;convfrom=$convfrom");
         } else {
            $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid, "&amp;convfrom=$convfrom");
         }

      } else {	# attmode==simple
         # handle case to skip to next text/html attachment
         if ( defined(%{$message{attachment}[$attnumber+1]}) &&
              (${$message{attachment}[$attnumber+1]}{boundary} eq
		  ${$message{attachment}[$attnumber]}{boundary}) ) {

            # skip to next text/(html|enriched) attachment in the same alternative group
            if ( (${$message{attachment}[$attnumber]}{subtype} =~ /alternative/i) &&
                 (${$message{attachment}[$attnumber+1]}{subtype} =~ /alternative/i) &&
                 (${$message{attachment}[$attnumber+1]}{'content-type'} =~ /^text/i) &&
                 (${$message{attachment}[$attnumber+1]}{filename}=~ /^Unknown\./ ) ) {
               next;
            }
            # skip to next attachment if this=unknow.(txt|enriched) and next=unknow.(html|enriched)
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
                  $content=html_att2table($message{attachment}, $attnumber, $escapedmessageid, $showhtmlastext);
                  $is_htmlmsg=1;
               } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^text\/enriched/i ) {
                  $content=enriched_att2table($message{attachment}, $attnumber, $showhtmlastext);
                  $is_htmlmsg=1;
               } else {
                  $content=text_att2table($message{attachment}, $attnumber);
               }
               my $charset=$convfrom;
               if ($convfrom eq lc($message{'charset'})) {	# get convfrom from attheader is it was from msgheader
                  $charset=lc(${$message{attachment}[$attnumber]}{charset})||
                           lc(${$message{attachment}[$attnumber]}{filenamecharset})||
                           $convfrom;
               }
               if (is_convertable($charset, $readcharset)) {
                  ($content)=iconv($charset, $readcharset, $content);
               }
               $temphtml .= $content;
            } else {
               # show misc attachment only if it is not referenced by other html
               if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid, "&amp;convfrom=$convfrom");
               }
            }
         } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^message\/external\-body/i ) {
            # attachment external reference, not an real message
            $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
         } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^message\/partial/i ) {
            # fragmented message
            $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
         } elsif ( ${$message{attachment}[$attnumber]}{'content-type'}=~ /^message/i ) {
            # always show message/... attachment
            $temphtml .= message_att2table($message{attachment}, $attnumber, $style{"window_dark"});
         } elsif ( ${$message{attachment}[$attnumber]}{filename}=~ /\.(?:jpg|jpeg|gif|png|bmp)$/i ) {
            # show image only if it is not referenced by other html
            if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
               if (!$prefs{'showimgaslink'}) {
                  $temphtml .= image_att2table($message{attachment}, $attnumber, $escapedmessageid, "&amp;convfrom=$convfrom");
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid, "&amp;convfrom=$convfrom");
               }
            }
         } elsif ( ${$message{attachment}[$attnumber]}{filename}=~ /\.(?:midi?|wav|mp3|ra|au|snd)$/i ) {
            # show sound only if it is not referenced by other html
            if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid, "&amp;convfrom=$convfrom");
            }
         } else {
            # show misc attachment only if it is not referenced by other html
            if ( ${$message{attachment}[$attnumber]}{referencecount}==0 ) {
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid, "&amp;convfrom=$convfrom");
            }
         }

      }
   }
   $html =~ s/\@\@\@BODY\@\@\@/$temphtml/;

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
   if ($message{status} !~ /r/i && $notificationto ne '') {
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
   if ($prefs{'newmailwindowtime'}>0 && $filtered > 0) {
      my $msg;
      my $line=0;
      foreach my $f (@defaultfolders, 'DELETE') {
         if (defined(${$r_filtered}{$f})) {
            $msg .= qq|$lang_folders{$f} &nbsp; ${$r_filtered}{$f}<br>|;
            $line++;
         }
      }
      foreach my $f (sort keys %{$r_filtered}) {
         next if ($is_defaultfolder{$f} || $f eq '_ALL');
         $msg .= qq|$f &nbsp; ${$r_filtered}{$f}<br>|;
         $line++;
      }
      $msg = qq|<font size="-1">$msg</font>|;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$readcharset', '$lang_text{"inmessages"}', '$msg', '$lang_text{"close"}', '_incoming', 160, |.($line*16+70).qq|, $prefs{'newmailwindowtime'});\n|.
                 qq|//-->\n</script>\n|;
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
      @tmp=($prefs{'language'}, $prefs{'charset'});
      ($prefs{'language'}, $prefs{'charset'})=('en', $readcharset);
   }
   httpprint([], [htmlheader(), $html, htmlfooter($footermode)]);
   if ($#tmp>=1) {
      ($prefs{'language'}, $prefs{'charset'})=@tmp;
   }

   # fork a child to do the status update and folderdb update
   # thus the result of readmessage can be returned as soon as possible
   if ($message{status} !~ /r/i) {	# msg file doesn't has R flag
      local $|=1; 			# flush all output
      local $SIG{CHLD} = 'IGNORE';	# handle zombie
      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);

         my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
         ow::filelock::lock($folderfile, LOCK_EX|LOCK_NB) or openwebmail_exit(1);

         # since status in folderdb may have flags not found in msg header
         # we must read the status from folderdb and then update it back
         my $status=(get_message_attributes($messageid, $folderdb))[$_STATUS];
         update_message_status($messageid, $status."R", $folderdb, $folderfile);

         ow::filelock::lock($folderfile, LOCK_UN);
         openwebmail_exit(0);
      }
   } elsif (param('db_chkstatus')) { # check and set msg status R flag
      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
      my (%FDB, @attr);
      ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} db $folderdb");
      @attr=string2msgattr($FDB{$messageid});
      if ($attr[$_STATUS] !~ /r/i) {
         $attr[$_STATUS].="R";
         $FDB{$messageid}=msgattr2string(@attr);
      }
      ow::dbm::close(\%FDB, $folderdb);
   }
   return;
}


sub html_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid, $showhtmlastext)=@_;

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
                  "sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;".
                  "action=composemessage&amp;message_id=$escapedmessageid&amp;compose_caller=read");
   }
   $temphtml = ow::htmlrender::html2table($temphtml);
   return($temphtml);
}

sub enriched_att2table {
   my ($r_attachments, $attnumber, $showhtmlastext)=@_;

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
   return($temphtml);
}

sub text_att2table {
   my ($r_attachments, $attnumber)=@_;

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
   return($temptext. "<BR>");
}

sub message_att2table {
   my ($r_attachments, $attnumber, $headercolor)=@_;
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

   $header=simpleheader($header);
   $header=ow::htmltext::text2html($header);
   $header=~s!Date: !<B>$lang_text{'date'}:</B> !i;
   $header=~s!From: !<B>$lang_text{'from'}:</B> !i;
   $header=~s!Reply-To: !<B>$lang_text{'replyto'}:</B> !i;
   $header=~s!To: !<B>$lang_text{'to'}:</B> !i;
   $header=~s!Cc: !<B>$lang_text{'cc'}:</B> !i;
   $header=~s!Subject: !<B>$lang_text{'subject'}:</B> !i;

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
   my ($r_attachments, $attnumber, $escapedmessageid, $extraparm)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $escapedfilename = ow::tool::escapeURL(${$r_attachment}{filename});
   my $attlen=lenstr(${$r_attachment}{'content-length'},1);
   my $nodeid=${$r_attachment}{nodeid};
   my $disposition=substr(${$r_attachment}{'content-disposition'},0,1);

   my $temphtml .= qq|<table border="0" align="center" cellpadding="2">|.
                   qq|<tr><td bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: ${$r_attachment}{filename} &nbsp;($attlen)&nbsp;&nbsp;|;
   if ($config{'enable_webdisk'} && !$config{'webdisk_readonly'}) {
      $temphtml .= qq|<a href=#here title="$lang_text{'saveatt_towd'}" onClick="window.open('$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=sel_saveattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm&amp;attname=|.
                   ow::tool::escapeURL(${$r_attachment}{filename}).qq|', '_blank','width=500,height=330,scrollbars=yes,resizable=yes,location=no');">$lang_text{'webdisk'}</a>|.
                   qq|&nbsp;\n|;
   }
   $temphtml .=    qq|<font color=$style{"attachment_dark"} class="smalltext">$nodeid $disposition</font>|.
                   qq|</td></tr>|.
                   qq|<tr><td bgcolor=$style{"attachment_light"} align="center">|.
                   qq|<a href="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm" title="$lang_text{'download'}">|.
                   qq|<img border="0" |;
   if (${$r_attachment}{'content-description'} ne "") {
      $temphtml .= qq|alt="${$r_attachment}{'content-description'}" |;
   }
   $temphtml .=    qq|SRC="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm">|.
                   qq|</a>|.
                   qq|</td></tr></table>|;
   return($temphtml);
}

sub misc_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid, $extraparm)=@_;
   my $r_attachment=${$r_attachments}[$attnumber];
   my $escapedfilename = ow::tool::escapeURL(${$r_attachment}{filename});
   my $attlen=lenstr(${$r_attachment}{'content-length'},1);
   my $nodeid=${$r_attachment}{nodeid};
   my $contenttype=${$r_attachment}{'content-type'}; $contenttype =~ s/^(.+?);.*/$1/g;
   my $disposition=substr(${$r_attachment}{'content-disposition'},0,1);
   my $attlink="$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm";

   my $temphtml .= qq|<table border="0" width="40%" align="center" cellpadding="2">|.
                   qq|<tr><td nowrap colspan="2" bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: ${$r_attachment}{filename}&nbsp;($attlen)&nbsp;&nbsp;\n|;
   if (${$r_attachment}{filename}=~/\.(?:doc|dot)$/ ) {
      $temphtml .= qq|<a href="$attlink&amp;wordpreview=1" target="_blank">$lang_wdbutton{'preview'}</a>|.
                   qq|&nbsp;\n|;
   }
   if ($config{'enable_webdisk'} && !$config{'webdisk_readonly'}) {
      $temphtml .= qq|<a href=#here title="$lang_text{'saveatt_towd'}" onClick="window.open('$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=sel_saveattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid$extraparm&amp;attname=|.
                   ow::tool::escapeURL(${$r_attachment}{filename}).qq|', '_blank','width=500,height=330,scrollbars=yes,resizable=yes,location=no');">$lang_text{'webdisk'}</a>|.
                   qq|&nbsp;\n|;
   }
   $temphtml .= qq|<font color=$style{"attachment_dark"} class="smalltext">$nodeid $disposition|.
                qq|</td></tr>|.
                qq|<tr><td nowrap bgcolor= $style{"attachment_light"} align="center">|.
                qq|$lang_text{'type'}: $contenttype<br>|.
                qq|$lang_text{'encoding'}: ${$r_attachment}{'content-transfer-encoding'}|;
   if (${$r_attachment}{'content-description'} ne "") {
      $temphtml .= qq|<br>$lang_text{'description'}: ${$r_attachment}{'content-description'}|;
   }
   my $blank="";
   if ($contenttype=~/^text/ ||
       ${$r_attachment}{filename}=~/\.(?:jpg|jpeg|gif|png|bmp)$/i) {
      $blank="target=_blank";
   }
   $temphtml .= qq|</td><td nowrap width="10%" bgcolor= $style{"attachment_light"} align="center">|.
                qq|<a href="$attlink" $blank>$lang_text{'download'}</a>|.
                qq|</td></tr></table>|;
   return($temphtml);
}
########## END READMESSAGE #######################################

########## REBUILDMESSAGE ########################################
sub rebuildmessage {
   my $partialid = $_[0];
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderfile!");

   my ($errorcode, $rebuildmsgid, @partialmsgids)=
	rebuild_message_with_partialid($folderfile, $folderdb, $partialid);

   ow::filelock::lock($folderfile, LOCK_UN);

   if ($errorcode==0) {
      # move partial msgs to trash folder
      my ($trashfile, $trashdb)=get_folderpath_folderdb($user, "mail-trash");
      if ($folderfile ne $trashfile) {
         ow::filelock::lock($trashfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $trashfile");
         my $moved=operate_message_with_ids("move", \@partialmsgids,
				$folderfile, $folderdb, $trashfile, $trashdb);
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
                                    folder=>$folder,
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
