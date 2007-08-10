#!/usr/bin/suidperl -T
#
# openwebmail-main.pl - message list browsing program
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

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/htmltext.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "modules/spamcheck.pl";
require "modules/viruscheck.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/lockget.pl";
require "shares/cut.pl";
require "shares/getmsgids.pl";
require "shares/fetchmail.pl";
require "shares/pop3book.pl";
require "shares/calbook.pl";
require "shares/filterbook.pl";
require "shares/mailfilter.pl";

# optional module
ow::tool::has_module('IO/Socket/SSL.pm');
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($default_logindomain);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err %lang_sortlabels
            %lang_calendar %lang_wday);		# defined in lang/xy
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES);	# defined in maildb.pl

# local globals
use vars qw($folder);
use vars qw($sort $msgdatetype $page $longpage);
use vars qw($searchtype $keyword);
use vars qw($escapedfolder $escapedkeyword);

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

my $action = param('action')||'';
if (!$config{'enable_webmail'} && $action ne "logout") {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = ow::tool::unescapeURL(param('folder'))||'INBOX';
$sort = param('sort') || $prefs{'sort'} || 'date_rev';
$msgdatetype = param('msgdatetype') || $prefs{'msgdatetype'};
$page = param('page') || 1;
$longpage = param('longpage') || 0;

$searchtype = param('searchtype') || 'subject';
$keyword = param('keyword') || ''; $keyword=~s/^\s*//; $keyword=~s/\s*$//;

$escapedfolder = ow::tool::escapeURL($folder);
$escapedkeyword = ow::tool::escapeURL($keyword);

writelog("debug - request main begin, action=$action, folder=$folder - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "movemessage" ||
    defined param('movebutton') ||
    defined param('copybutton') ) {
   my @messageids = param('message_ids');
   my $destination=ow::tool::unescapeURL(param('destination'));
   $destination=ow::tool::untaint(safefoldername($destination));

   if ($destination eq 'FORWARD' && $#messageids>=0) {	# forwarding msgs
      sysopen(FORWARDIDS, "$config{'ow_sessionsdir'}/$thissession-forwardids", O_WRONLY|O_TRUNC|O_CREAT);
      print FORWARDIDS join("\n", @messageids);
      close(FORWARDIDS);
      my $send_url = qq|$config{'ow_cgiurl'}/openwebmail-send.pl?|.
                     qq|sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
                     qq|page=$page&amp;longpage=$longpage&amp;|.
                     qq|sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;|.
                     qq|compose_caller=main&amp;action=composemessage|;
      if (defined param('movebutton')) {
         print redirect(-location=>"$send_url&amp;composetype=forwardids_delete");
      } else {
         print redirect(-location=>"$send_url&amp;composetype=forwardids");
      }
   } else {						# move/copy/del msgs
      movemessage(\@messageids, $destination) if ($#messageids>=0);
      if (param('messageaftermove')) {
         my $headers = param('headers') || $prefs{'headers'} || 'simple';
         my $attmode = param('attmode') || 'simple';
         my $escapedmessageid=ow::tool::escapeURL(param('message_id')||'');
         $escapedmessageid=ow::tool::escapeURL($messageids[0]) if (defined param('copybutton')); # copy button pressed, msg not moved
         print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-read.pl?sessionid=$thissession&folder=$escapedfolder&page=$page&longpage=$longpage&sort=$sort&msgdatetype=$msgdatetype&keyword=$escapedkeyword&searchtype=$searchtype&message_id=$escapedmessageid&action=readmessage&headers=$headers&attmode=$attmode");
      } else {
         listmessages();
      }
   }
} elsif ($action eq "listmessages_afterlogin") {
   clean_trash_spamvirus();
   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   if ( ($config{'forced_moveoldmsgfrominbox'}||$prefs{'moveoldmsgfrominbox'}) &&
        (!$quotalimit||$quotausage<$quotalimit) ) {
      moveoldmsg2saved();
   }
   update_pop3check();
   authpop3_fetch() if ($config{'auth_module'} eq 'auth_pop3.pl' ||
                        $config{'auth_module'} eq 'auth_ldap_vpopmail.pl');
   pop3_fetches($prefs{'autopop3wait'}) if ($config{'enable_pop3'} && $prefs{'autopop3'});
   listmessages();
} elsif ($action eq "userrefresh") {
   if ($folder eq 'INBOX') {
      authpop3_fetch() if ($config{'auth_module'} eq 'auth_pop3.pl' ||
                           $config{'auth_module'} eq 'auth_ldap_vpopmail.pl');
   }
   if ($config{'quota_module'} ne 'none') {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   listmessages();
   if (update_pop3check()) {
      pop3_fetches(0) if ($config{'enable_pop3'} && $prefs{'autopop3'});
   }
} elsif ($action eq "listmessages") {
   my $update=0; $update=1 if (update_pop3check());
   if ($update) {	# get mail from auth pop3 server
      authpop3_fetch() if ($config{'auth_module'} eq 'auth_pop3.pl' ||
                           $config{'auth_module'} eq 'auth_ldap_vpopmail.pl');
   }
   listmessages();
   if ($update) {	# get mail from misc pop3 servers
      pop3_fetches(0) if ($config{'enable_pop3'} && $prefs{'autopop3'});
   }
} elsif ($action eq "markasread") {
   markasread();
   listmessages();
} elsif ($action eq "markasunread") {
   markasunread();
   listmessages();
} elsif ($action eq "pop3fetches" && $config{'enable_pop3'}) {
   www_pop3_fetches();
   listmessages();
} elsif ($action eq "pop3fetch" && $config{'enable_pop3'}) {
   www_pop3_fetch();
   listmessages();
} elsif ($action eq "emptyfolder") {
   www_emptyfolder($folder);
   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   listmessages();
} elsif ($action eq "logout") {
   clean_trash_spamvirus();
   if ( ($config{'forced_moveoldmsgfrominbox'}||
         $prefs{'moveoldmsgfrominbox'}) &&
        (!$quotalimit||$quotausage<$quotalimit) ) {
      moveoldmsg2saved();
   }
   logout();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request main end, action=$action, folder=$folder - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## LISTMESSGAES ##########################################
sub listmessages {
   my $orig_inbox_newmessages=0;
   my $now_inbox_newmessages=0;
   my $now_inbox_allmessages=0;
   my $inboxsize_k=0;
   my $folder_allmessages=0;
   my %FDB;

   my $spooldb=(get_folderpath_folderdb($user, 'INBOX'))[1];
   if (ow::dbm::exist($spooldb)) {
      ow::dbm::open(\%FDB, $spooldb, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db $spooldb");
      $orig_inbox_newmessages=$FDB{'NEWMESSAGES'};	# new msg in INBOX
      ow::dbm::close(\%FDB, $spooldb);
   }

   # filtermessage in background
   filtermessage($user, 'INBOX', \%prefs);

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

   # reset global $folder to INBOX if it is not a valid folder
   my $is_validfolder=0;
   foreach (@validfolders) {
      if ($_ eq $folder) { $is_validfolder=1; last; }
   }
   $folder='INBOX' if (!$is_validfolder);

   my ($totalsize, $newmessages, $r_messageids, $r_messagedepths)=
      getinfomessageids($user, $folder, $sort, $msgdatetype, $searchtype, $keyword);
   my $msgsperpage=$prefs{'msgsperpage'}||10; $msgsperpage=1000 if ($longpage);
   my $totalmessage=$#{$r_messageids}+1; $totalmessage=0 if ($totalmessage<0);
   my $totalpage=int($totalmessage/$msgsperpage+0.999999); $totalpage=1 if ($totalpage==0);

   $page = 1 if ($page < 1); $page = $totalpage if ($page>$totalpage);

   my $firstmessage = ($page-1)*$msgsperpage + 1;
   my $lastmessage = $firstmessage + $msgsperpage - 1;
   $lastmessage = $totalmessage if ($lastmessage>$totalmessage);

   my $main_url = "$config{'ow_cgiurl'}/openwebmail-main.pl";
   my $urlparmstr="sessionid=$thissession&amp;folder=$escapedfolder&amp;".
                  "page=$page&amp;longpage=$longpage&amp;".
                  "sort=$sort&amp;msgdatetype=$msgdatetype&amp;";
   my $urlparmstr_keyword=$urlparmstr."keyword=$escapedkeyword&amp;searchtype=$searchtype";

   my ($html, $temphtml);
   $html = applystyle(readtemplate("viewfolder.template"));

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
         if ($foldername eq 'INBOX') {
            $now_inbox_allmessages=$allmessages;
            $now_inbox_newmessages=$newmessages;
            $inboxsize_k=(-s $folderfile)/1024;
         } elsif ($foldername eq $folder) {
            $folder_allmessages=$allmessages;
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
         $option_str.=ow::htmltext::str2html(f2u($foldername));
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

   $temphtml = '';
   if ($totalmessage>0) {
      $temphtml .= "$newmessages $lang_text{'unread'} / " if ($newmessages);
      $temphtml .= "$totalmessage $lang_text{'messages'} / ". lenstr($totalsize, 1);
   } else {
      $temphtml = $lang_text{'nomessages'};
   }
   $html =~ s/\@\@\@NUMBEROFMESSAGES\@\@\@/$temphtml/;

   # quota or spool over the limit
   my $limited=(($quotalimit>0 && $quotausage>$quotalimit) ||			   # quota
                ($config{'spool_limit'}>0 && $inboxsize_k>$config{'spool_limit'})); # spool

   $temphtml = '';
   if (!$limited) {
      $temphtml .= iconlink("compose.gif", $lang_text{'composenew'}, qq|accesskey="C" href="$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page&amp;compose_caller=main"|);
      $temphtml .= qq|&nbsp;\n|;
   }

   $temphtml .= iconlink("folder.gif", $lang_text{'folders'}, qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-folder.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page"|);

   if ($config{'enable_userfilter'}) {
      $temphtml .= iconlink("filtersetup.gif", $lang_text{'filterbook'}, qq|accesskey="I" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page"|);
   }
   if ($config{'enable_saprefs'} && !$config{'enable_preference'}) {
      $temphtml .= iconlink("saprefs.gif", $lang_text{'sa_prefs'}, qq|href="$config{'ow_cgiurl'}/openwebmail-saprefs.pl?action=edittest&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page"|);
   }

   $temphtml .= qq|&nbsp;\n|;

   if ($config{'enable_pop3'} && $folder eq "INBOX") {
      $temphtml .= iconlink("pop3.gif", $lang_text{'retr_pop3s'}, qq|accesskey="G" href="$main_url?$urlparmstr_keyword&amp;action=pop3fetches"|);
   }
   if ($config{'enable_advsearch'}) {
      $temphtml .= iconlink("advsearch.gif", $lang_text{'advsearch'}, qq|accesskey="V" href="$config{'ow_cgiurl'}/openwebmail-advsearch.pl?$urlparmstr&amp;action=advsearch"|);
   }
   $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'}, qq|accesskey="R" href="$main_url?$urlparmstr&amp;action=userrefresh&amp;userfresh=1"|);

   $temphtml .= qq|&nbsp;\n|;

   if ($config{'enable_addressbook'}) {
      $temphtml .= iconlink("addrbook.gif", $lang_text{'addressbook'}, qq|accesskey="A" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?$urlparmstr_keyword&amp;action=addrlistview"|);
   }
   if ($config{'enable_calendar'}) {
      $temphtml .= iconlink("calendar.gif", $lang_text{'calendar'}, qq|accesskey="K" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?$urlparmstr&amp;action=$prefs{'calendar_defaultview'}"|);
   }
   if ($config{'enable_webdisk'}) {
      $temphtml .= iconlink("webdisk.gif", $lang_text{'webdisk'}, qq|accesskey="E" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?$urlparmstr&amp;action=showdir"|);
   }
   if ( $config{'enable_sshterm'}) {
      if ( -r "$config{'ow_htmldir'}/applet/mindterm2/mindterm.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm2/ssh2.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      } elsif ( -r "$config{'ow_htmldir'}/applet/mindterm/mindtermfull.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm/ssh.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      }
   }
   if ( $config{'enable_preference'}) {
      $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?$urlparmstr&amp;action=editprefs&amp;prefs_caller=main"|);
   }
   $temphtml .= iconlink("logout.gif", "$lang_text{'logout'} $prefs{'email'}", qq|accesskey="X" href="$main_url?$urlparmstr&amp;action=logout"|);

   $html =~ s/\@\@\@LEFTMENUBARLINKS\@\@\@/$temphtml/;

   $temphtml='';
   if ($config{'enable_learnspam'}) {
      if ($folder eq 'spam-mail') {
         $temphtml = iconlink("learnham.gif", $lang_text{'learnham'}, qq|accesskey="Z" href="JavaScript:document.pageform.destination.value='LEARNHAM'; document.pageform.movebutton.click();"|);
      } elsif ($folder ne 'saved-drafts' && $folder ne 'sent-mail' &&
               $folder ne 'spam-mail' && $folder ne 'virus-mail') {
         $temphtml = iconlink("learnspam.gif", $lang_text{'learnspam'}, qq|accesskey="Z" href="JavaScript:document.pageform.destination.value='LEARNSPAM'; document.pageform.movebutton.click();"|);
      }
   }
   if ($folder eq 'saved-drafts' || $folder eq 'mail-trash' ||
       $folder eq 'spam-mail' || $folder eq 'virus-mail') {
      $temphtml .= iconlink("emptyfolder.gif", $lang_text{'emptyfolder'}, qq|accesskey="Z" href="$main_url?$urlparmstr&amp;action=emptyfolder" onclick="return confirm('$lang_text{emptyfolder} ($lang_folders{$folder}, $folder_allmessages $lang_text{messages}) ?');"|);
   } else {
      my $trashfolder='mail-trash';
      $trashfolder='DELETE' if ($quotalimit>0 && $quotausage>$quotalimit);
      $temphtml .= iconlink("totrash.gif", $lang_text{'totrash'}, qq|accesskey="Z" href="JavaScript:document.pageform.destination.value='$trashfolder'; document.pageform.movebutton.click();"|);
   }
   $temphtml .= qq|&nbsp;\n|;

   $html =~ s/\@\@\@RIGHTMENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                          -name=> 'pageform').
               ow::tool::hiddens(action=>'listmessages',
                                 sessionid=>$thissession,
                                 sort=>$sort,
                                 msgdatetype=>$msgdatetype,
                                 folder=>$escapedfolder);
   $html =~ s/\@\@\@STARTPAGEFORM\@\@\@/$temphtml/;

   $temphtml="";
   if ($config{'enable_calendar'} && $prefs{'calendar_reminderdays'}>0) {
      $temphtml=eventreminder_html($prefs{'calendar_reminderdays'});
   }
   if ($temphtml ne "") {
      $html =~ s/\@\@\@EVENTREMINDER\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@EVENTREMINDER\@\@\@/&nbsp;/;
   }

   $temphtml=htmlplugin($config{'webmail_middle_pluginfile'}, $config{'webmail_middle_pluginfile_charset'}, $prefs{'charset'});
   if ($temphtml ne "") {
      $html =~ s/\@\@\@MIDDLEPLUGIN\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@MIDDLEPLUGIN\@\@\@/<br>/;
   }

   my $sort_url="$main_url?sessionid=$thissession&amp;folder=$escapedfolder&amp;".
                "action=listmessages&amp;page=$page&amp;longpage=$longpage&amp;".
                "keyword=$escapedkeyword&amp;searchtype=$searchtype";
   my $linetemplate=$prefs{'fieldorder'};
   $linetemplate=~s/date/\@\@\@DATE\@\@\@/;
   $linetemplate=~s/from/\@\@\@FROM\@\@\@/;
   $linetemplate=~s/size/\@\@\@SIZE\@\@\@/;
   $linetemplate=~s/subject/\@\@\@SUBJECT\@\@\@/;
   $linetemplate='@@@STATUS@@@ '.$linetemplate.' @@@CHECKBOX@@@';

   my $headershtml='';
   my $linehtml=$linetemplate;

   $temphtml = iconlink("unread.gif", $lang_sortlabels{'status'}, qq|href="$sort_url&amp;sort=status"|);
   $temphtml = qq|<td width="6%" bgcolor=$style{'columnheader'} align="center">$temphtml</td>\n|;
   $linehtml =~ s/\@\@\@STATUS\@\@\@/$temphtml/;

   if ($msgdatetype eq 'recvdate') {
      if ($sort eq "date") {
         $temphtml = qq|<a href="$sort_url&amp;sort=date&amp;msgdatetype=sentdate">$lang_text{'recvdate'}</a> |.
                     iconlink("up.gif", "^", qq|href="$sort_url&amp;sort=date_rev&amp;msgdatetype=recvdate"|);
      } elsif ($sort eq "date_rev") {
         $temphtml = qq|<a href="$sort_url&amp;sort=date_rev&amp;msgdatetype=sentdate">$lang_text{'recvdate'}</a> |.
                     iconlink("down.gif", "v", qq|href="$sort_url&amp;sort=date&amp;msgdatetype=recvdate"|);
      } else {
         $temphtml = qq|<a href="$sort_url&amp;sort=date_rev">$lang_text{'recvdate'}</a>|;
      }
   } else {
      if ($sort eq "date") {
         $temphtml = qq|<a href="$sort_url&amp;sort=date&amp;msgdatetype=recvdate">$lang_text{'sentdate'}</a> |.
                     iconlink("up.gif", "^", qq|href="$sort_url&amp;sort=date_rev&amp;msgdatetype=sentdate"|);
      } elsif ($sort eq "date_rev") {
         $temphtml = qq|<a href="$sort_url&amp;sort=date_rev&amp;msgdatetype=recvdate">$lang_text{'sentdate'}</a> |.
                     iconlink("down.gif", "v", qq|href="$sort_url&amp;sort=date&amp;msgdatetype=sentdate"|);
      } else {
         $temphtml = qq|<a href="$sort_url&amp;sort=date_rev">$lang_text{'sentdate'}</a>|;
      }
   }
   $temphtml = qq|<td width="22%" bgcolor=$style{'columnheader'}><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@DATE\@\@\@/$temphtml/;

   if ( $folder=~ m#sent-mail#i ||
        $folder=~ m#saved-drafts#i ||
        $folder=~ m#\Q$lang_folders{'sent-mail'}\E#i ||
        $folder=~ m#\Q$lang_folders{'saved-drafts'}\E#i ) {
      if ($sort eq "recipient" || $sort eq "sender") {
         $temphtml = qq|<a href="$sort_url&amp;sort=recipient_rev">$lang_text{'recipient'}</a> |.
                     iconlink("up.gif", "^", qq|href="$sort_url&amp;sort=recipient_rev"|);
      } elsif ($sort eq "recipient_rev" || $sort eq "sender_rev") {
         $temphtml = qq|<a href="$sort_url&amp;sort=recipient">$lang_text{'recipient'}</a> |.
                     iconlink("down.gif", "v", qq|href="$sort_url&amp;sort=recipient"|);
      } else {
         $temphtml = qq|<a href="$sort_url&amp;sort=recipient">$lang_text{'recipient'}</a>|;
      }
   } else {
      if ($sort eq "sender" || $sort eq "recipient") {
         $temphtml = qq|<a href="$sort_url&amp;sort=sender_rev">$lang_text{'sender'}</a> |.
                     iconlink("up.gif", "^", qq|href="$sort_url&amp;sort=sender_rev"|);
      } elsif ($sort eq "sender_rev" || $sort eq "recepient_rev") {
         $temphtml = qq|<a href="$sort_url&amp;sort=sender">$lang_text{'sender'}</a> |.
                     iconlink("down.gif", "v", qq|href="$sort_url&amp;sort=sender"|);
      } else {
         $temphtml = qq|<a href="$sort_url&amp;sort=sender">$lang_text{'sender'}</a>|;
      }
   }
   $temphtml = qq|<td width="25%" bgcolor=$style{'columnheader'}><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@FROM\@\@\@/$temphtml/;

   if ($sort eq "subject") {
      $temphtml = qq|<a href="$sort_url&amp;sort=subject_rev">$lang_text{'subject'}</a> |.
                  iconlink("up.gif", "^", qq|href="$sort_url&amp;sort=subject_rev"|);
   } elsif ($sort eq "subject_rev") {
      $temphtml = qq|<a href="$sort_url&amp;sort=subject">$lang_text{'subject'}</a> |.
                  iconlink("down.gif", "v", qq|href="$sort_url&amp;sort=subject"|);
   } else {
      $temphtml = qq|<a href="$sort_url&amp;sort=subject_rev">$lang_text{'subject'}</a>|;
   }
   $temphtml = qq|<td bgcolor=$style{'columnheader'}><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/;

   if ($sort eq "size") {
      $temphtml = qq|<a href="$sort_url&amp;sort=size_rev">$lang_text{'size'}</a> |.
                  iconlink("up.gif", "^", qq|href="$sort_url&amp;sort=size_rev"|);
   } elsif ($sort eq "size_rev") {
      $temphtml = qq|<a href="$sort_url&amp;sort=size">$lang_text{'size'}</a> |.
                  iconlink("down.gif", "v", qq|href="$sort_url&amp;sort=size"|);
   } else {
      if ($folder eq "mail-trash" || $folder eq "spam-mail" || $folder eq "virus-mail") {
         $temphtml = qq|<a href="$sort_url&amp;sort=size_rev">$lang_text{'size'}</a>|;
      } else {
         $temphtml = qq|<a href="$sort_url&amp;sort=size">$lang_text{'size'}</a>|;
      }
   }
   $temphtml = qq|<td width="5%" bgcolor=$style{'columnheader'} align="right" nowrap><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@SIZE\@\@\@/$temphtml/;

   $temphtml = qq|<td width="3%" bgcolor=$style{'columnheader'} align ="center">|.
               checkbox(-name=>'allbox',
                        -value=>'1',
                        -onClick=>"CheckAll($prefs{'uselightbar'});",
                        -label=>'',
                        -override=>'1').
               qq|</td>\n|;
   $linehtml =~ s/\@\@\@CHECKBOX\@\@\@/$temphtml/;

   $headershtml .= qq|<tr>$linehtml</tr>\n|;

   my $r_abookemailhash=get_abookemailhash();
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my ($messageid, $messagedepth, $escapedmessageid);
   my ($tr_bgcolorstr, $td_bgcolorstr, $checkbox_onclickstr, $boldon, $boldoff);

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db ".f2u($folderdb));

   $temphtml = '';
   foreach my $messnum ($firstmessage  .. $lastmessage) {
      $messageid=${$r_messageids}[$messnum-1];
      $messagedepth=${$r_messagedepths}[$messnum-1];
      next if (!defined $FDB{$messageid});

      $escapedmessageid = ow::tool::escapeURL($messageid);

      my @attr=string2msgattr($FDB{$messageid});
      my $charset=$attr[$_CHARSET];
      if ($charset eq '' && $prefs{'charset'} eq 'utf-8') {
         # assume msg is from sender using same language as the recipient's browser
         my $browserlocale = ow::lang::guess_browser_locale($config{available_locales});
         $charset=(ow::lang::localeinfo($browserlocale))[6];
      }
      # convert from message charset to current user charset
      my ($from, $to, $subject)=iconv('utf-8' , $prefs{'charset'}, $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]);

      $linehtml=$linetemplate;
      if ($prefs{'uselightbar'}) {
         $tr_bgcolorstr=qq|bgcolor=$style{tablerow_light} |;
         $tr_bgcolorstr=qq|bgcolor=$style{tablerow_dark} | if ($totalmessage==1); # make this msg selected if it is the only one
         $tr_bgcolorstr.=qq|onMouseOver='this.style.backgroundColor=$style{tablerow_hicolor};' |.
                         qq|onMouseOut='this.style.backgroundColor = document.getElementById("$messnum").checked? $style{tablerow_dark}:$style{tablerow_light};' |.
                         qq|onClick='if (!document.layers) {var cb=document.getElementById("$messnum"); cb.checked=!cb.checked}' |.
                         qq|id="tr_$messnum" |;
         $td_bgcolorstr='';
         $checkbox_onclickstr='if (!document.layers) {this.checked=!this.checked}';	# disable checkbox change since it is already done once by tr onclick event
      } else {
         $tr_bgcolorstr='';
         $td_bgcolorstr=qq|bgcolor=|.($style{"tablerow_dark"},$style{"tablerow_light"})[$messnum%2];
         $checkbox_onclickstr='';
      }

      $temphtml = "<B>$messnum</B> \n";

      # STATUS, choose status icons based on Status: line and type of encoding
      my $status=$attr[$_STATUS]; $status =~ s/\s//g;	# remove blanks
      if ( $status =~ /R/i ) {
         ($boldon, $boldoff) = ('', '');
         my $icon="read.gif"; $icon="read.a.gif" if ($status=~/A/i);
         $temphtml .= iconlink("$icon", "$lang_text{'markasunread'} ", qq|href="$main_url?$urlparmstr_keyword&amp;action=markasunread&amp;message_id=$escapedmessageid&amp;status=$status"|);
      } else {
         ($boldon, $boldoff) = ('<B>', '</B>');
         my $icon="unread.gif"; $icon="unread.a.gif" if ($status=~/A/i);
         $temphtml .= iconlink("$icon", "$lang_text{'markasread'} ", qq|href="$main_url?$urlparmstr_keyword&amp;action=markasread&amp;message_id=$escapedmessageid&amp;status=$status"|);
      }
      # T flag is only supported by openwebmail internally
      # see routine update_folderindex in maildb.pl for detail
      $temphtml .= iconlink("attach.gif", "", "")    if ($status =~ /T/i);
      $temphtml .= iconlink("important.gif", "", "") if ($status =~ /I/i);
      $temphtml = qq|<td $td_bgcolorstr nowrap>$temphtml&nbsp;</td>\n|;
      $linehtml =~ s/\@\@\@STATUS\@\@\@/$temphtml/;

      # DATE, convert dateserial(GMT) to localtime
      my $serial=($msgdatetype eq 'recvdate')?$attr[$_RECVDATE]:$attr[$_DATE];
      my %t=( sign => '+');
      $t{sec}=ow::datetime::dateserial2gmtime($attr[$_RECVDATE])-ow::datetime::dateserial2gmtime($attr[$_DATE]);
      if ($t{sec}<0) {
         $t{sign}='-'; $t{sec}*=-1;
      }
      $t{min}=int($t{sec}/60); $t{sec}=$t{sec}%60;
      $t{hour}=int($t{min}/60); $t{min}=$t{min}%60;
      $temphtml = qq|<td $td_bgcolorstr>$boldon|.
                  qq|<a title="|.sprintf("%s %dh %dm %ds ", $t{sign}, $t{hour}, $t{min}, $t{sec}).qq|">|.
                  ow::datetime::dateserial2str($serial,
						$prefs{'timeoffset'}, $prefs{'daylightsaving'},
						$prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'}).
                  qq|</a>$boldoff</td>\n|;
      $linehtml =~ s/\@\@\@DATE\@\@\@/$temphtml/;

      # FROM, find name, email of from and to field first
      my @recvlist = ow::tool::str2list($to,0);
      my (@namelist, @addrlist);
      foreach my $recv (@recvlist) {
         my ($n, $a)=ow::tool::email2nameaddr($recv);
         # if $n or $a has ", $recv may be an incomplete addr
         push(@namelist, $n) if ($n!~/"/);
         push(@addrlist, $a) if ($a!~/"/);;
      }
      my ($to_name, $to_address)=(join(",", @namelist), join(",", @addrlist));
      $to_name=substr($to_name, 0, 29)."..." if (length($to_name)>32);
      $to_address=substr($to_address, 0, 61)."..." if (length($to_address)>64);
      my ($from_name, $from_address)=ow::tool::email2nameaddr($from);
      $from_address=~s/"//g;

      # we aren't interested in the sender of SENT/DRAFT folder,
      # but the recipient, so display $to instead of $from
      my ($from2, $from2_name, $from2_address, $from2_searchtype, $from2_keyword);
      if ( $folder=~ m#sent-mail#i ||
           $folder=~ m#saved-drafts#i ||
           $folder=~ m#\Q$lang_folders{'sent-mail'}\E#i ||
           $folder=~ m#\Q$lang_folders{'saved-drafts'}\E#i ) {
         ($from2, $from2_name, $from2_address)=($to, $to_name, $to_address);
         ($from2_searchtype, $from2_keyword)=('to', join('|',@addrlist));
      } else {
         ($from2, $from2_name, $from2_address)=($from, $from_name, $from_address);
         ($from2_searchtype, $from2_keyword)=('from', $from_address);
      }

      # XSS safety - turns & and < > into html entities. No other chars are changed,
      # so in normal cases this won't mess up anything
      $to_name = ow::htmltext::str2html($to_name);
      $to_address = ow::htmltext::str2html($to_address);
      $from2_name = ow::htmltext::str2html($from2_name);
      $from2_address = ow::htmltext::str2html($from2_address);

      my ($linkstr, $searchstr, $friendstr);
      if (!$limited) {
         $linkstr=qq|href="$config{'ow_cgiurl'}/openwebmail-send.pl?$urlparmstr_keyword&amp;|.
                  qq|action=composemessage&amp;composetype=sendto&amp;|.
                  qq|to=|.ow::tool::escapeURL($from2).qq|&amp;compose_caller=main"|;
      }
      if ($prefs{'useminisearchicon'}) {
         $searchstr=iconlink("search.s.gif", "$lang_text{'search'} $from2_address",
                            qq|href="$main_url?sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
                            qq|action=listmessages&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;|.
                            qq|searchtype=$from2_searchtype&amp;keyword=|.ow::tool::escapeURL($from2_keyword).qq|"| );
      }
      if ($config{'enable_addressbook'} &&
          defined ${$r_abookemailhash}{lc($from2_address)}) {	# case insensitive lookup
         $friendstr=iconlink("friend.gif", "$lang_text{'search'} $lang_text{'addressbook'}", qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;abookkeyword=$from2_address&amp;abooksearchtype=email&amp;abookfolder=ALL&amp;sessionid=$thissession&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page"|);
      }

      my $from2str=qq|<a $linkstr title="|.ow::htmltext::str2html($from_address).qq| -&gt; |.ow::htmltext::str2html($to_address).qq|">$from2_name</a>|;
      if ($searchstr ne '' || $friendstr ne '') {
         $temphtml = qq|<td $td_bgcolorstr>|.
                     qq|<table cellspacing="0" cellpadding="0"><tr>\n|.
                     qq|<td nowrap>$searchstr$friendstr&nbsp;</td>|.
                     qq|<td>$boldon$from2str$boldoff</td>|.
                     qq|</tr></table></td>\n|;
      } else {
         $temphtml=qq|<td $td_bgcolorstr>$boldon$from2str$boldoff</td>\n|;
      }
      $linehtml =~ s/\@\@\@FROM\@\@\@/$temphtml/;

      # SUBJECT, cut subject to less than 64
      $subject=substr($subject, 0, 64)."..." if (length($subject)>67);
      my $subject2 = $subject; # for searching later
      $subject = ow::htmltext::str2html($subject);
      $subject = "N/A" if ($subject !~ /[^\s]/); # Make sure there's SOMETHING clickable
      my $accesskeystr=($messnum-$firstmessage)%10+1;	# 1..10
      if ($accesskeystr == 10) {
         $accesskeystr=qq|accesskey="0"|;
      } elsif ($accesskeystr < 10) {
         $accesskeystr=qq|accesskey="$accesskeystr"|;
      }

      # param order is purposely same as prev/next links in readmessage,
      # so the resulted webpage could be cached with same url in both cases
      $temphtml = qq|<a href="$config{'ow_cgiurl'}/openwebmail-read.pl?|.
                  qq|sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
                  qq|page=$page&amp;longpage=$longpage&amp;|.
                  qq|sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;|.
                  qq|message_id=$escapedmessageid&amp;action=readmessage&amp;|.
                  qq|headers=$prefs{'headers'}&amp;attmode=simple|;
      $temphtml.= qq|&amp;db_chkstatus=1| if ($status!~/R/i);
      $temphtml.= qq|" $accesskeystr title="$lang_text{'charset'}: $charset ">\n|.
                  $subject.
                  qq| </a>\n|;

      my ($subject_begin, $subject_end, $fill) = ('', '', '');
      for (my $i=1; $i<$messagedepth; $i++) {
         $fill .= "&nbsp; &nbsp; ";
      }
      if ( $messagedepth>0 && $sort eq "subject" ) {
         $fill .=qq|&nbsp; |.iconlink("follow.down.gif", "", "").qq|&nbsp;|;
      } elsif ( $messagedepth>0 && $sort eq "subject_rev") {
         $fill .=qq|&nbsp; |.iconlink("follow.up.gif", "", "").qq|&nbsp;|;
      }
      if ($messagedepth) {
         $subject_begin = qq|<table cellpadding="0" cellspacing="0"><tr><td nowrap>$fill</td><td>|;
         $subject_end = qq|</td></tr></table>|;
      }
      if ($prefs{'useminisearchicon'}) {
         $subject2 =~ s/Res?:\s*//ig; $subject2=~s/\[.*?\]//g;
         my $searchstr = iconlink("search.s.gif", "$lang_text{'search'} $subject",
                                  qq|href="$main_url?sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
                                  qq|action=listmessages&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;|.
                                  qq|searchtype=subject&amp;keyword=|.ow::tool::escapeURL($subject2).qq|"| ).
                                  qq|&nbsp;|;
         $temphtml = qq|<td $td_bgcolorstr>|.
                     qq|<table cellspacing="0" cellpadding="0"><tr>\n|.
                     qq|<td>$searchstr</td>|.
                     qq|<td>$subject_begin$boldon$temphtml$boldoff$subject_end</td>\n|.
                     qq|</tr></table></td>\n|;
      } else {
         $temphtml = qq|<td $td_bgcolorstr>$subject_begin$boldon$temphtml$boldoff$subject_end</td>\n|;
      }
      $linehtml =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/;

      # SIZE, round message size and change to an appropriate unit for display
      $temphtml = lenstr($attr[$_SIZE],0);
      $temphtml = qq|<td align="right" $td_bgcolorstr>$boldon$temphtml$boldoff</td>\n|;
      $linehtml =~ s/\@\@\@SIZE\@\@\@/$temphtml/;

      # CHECKBOX
      if ( $totalmessage==1 ) {	# make this msg selected if it is the only one
         $temphtml = checkbox(-name=>'message_ids',
                               -value=>$messageid,
                               -checked=>1,
                               -override=>'1',
                               -label=>'',
                               -onclick=> $checkbox_onclickstr,
                               -id=>$messnum);
      } else {
         $temphtml = checkbox(-name=>'message_ids',
                               -value=>$messageid,
                               -override=>'1',
                               -label=>'',
                               -onclick=> $checkbox_onclickstr,
                               -id=>$messnum);
      }
      $temphtml = qq|<td align="center" $td_bgcolorstr>$temphtml</td>\n|;
      $linehtml =~ s/\@\@\@CHECKBOX\@\@\@/$temphtml/;

      $headershtml .= qq|<tr $tr_bgcolorstr>$linehtml</tr>\n\n|;
   }
   ow::dbm::close(\%FDB, $folderdb);
   undef(@{$r_messageids}); undef($r_messageids);

   my $page_url="$main_url?sessionid=$thissession&amp;folder=$escapedfolder&amp;".
                "action=listmessages&amp;longpage=$longpage&amp;".
                "sort=$sort&amp;msgdatetype=$msgdatetype&amp;".
                "keyword=$escapedkeyword&amp;searchtype=$searchtype";
   my $gif;
   $temphtml=qq|<table cellpadding="0" cellspacing="0" border="0"><tr><td>|;
   if ($page > 1) {
      $gif="left.gif"; $gif="right.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "&lt;", qq|accesskey="U" href="$page_url&amp;page=|.($page-1).qq|"|);
   } else {
      $gif="left-grey.gif"; $gif="right-grey.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "-", "");
   }
   $temphtml.=qq|</td><td>$page/$totalpage</td><td>|;
   if ($page < $totalpage) {
      $gif="right.gif"; $gif="left.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "&gt;", qq|accesskey="D" href="$page_url&amp;page=|.($page+1) .qq|"|);
   } else {
      $gif="right-grey.gif"; $gif="left-grey.gif" if ($ow::lang::RTL{$prefs{'locale'}});
      $temphtml .= iconlink($gif, "-", "");
   }
   $temphtml.=qq|</td></tr></table>|;
   $html =~ s/\@\@\@PAGECONTROL\@\@\@/$temphtml/g;

   if ($lastmessage-$firstmessage>10) {
      $temphtml = iconlink("gotop.gif", "^", qq|href="#"|);
      $html =~ s/\@\@\@TOPCONTROL\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@TOPCONTROL\@\@\@//;
   }


   my ($htmlsearch, $htmlpage, $htmlmove);

   my %searchtypelabels;
   foreach (qw(from to subject date attfilename header textcontent all)) {
      $searchtypelabels{$_}=$lang_text{$_};
   }
   $htmlsearch = qq|<table cellspacing="0" cellpadding="0"><tr><td>|.
                 popup_menu(-name=>'searchtype',
                            -default=>$searchtype,
                            -values=>['from', 'to', 'subject', 'date', 'attfilename', 'header', 'textcontent' ,'all'],
                            -labels=>\%searchtypelabels).
                 qq|</td><td>|.
                 textfield(-name=>'keyword',
                           -default=>$keyword,
                           -size=>'12',
                           -accesskey=>'S',	# search folder
                           -override=>'1').
                 qq|</td><td>|.
                 submit(-name =>'searchbutton',
                        -value=>$lang_text{'search'}).
                 qq|</td></tr></table>|;

   my @pagevalues;
   for (my $p=1; $p<=$totalpage; $p++) {
      my $pdiff=abs($p-$page);
      if ($pdiff<10 || $p==1 || $p==$totalpage ||
          ($pdiff<100 && $p%10==0) || ($pdiff<1000 && $p%100==0) || $p%1000==0) {
         push(@pagevalues, $p);
      }
   }
   $htmlpage=qq|<table cellpadding="0" cellspacing="0"><tr>|.
             qq|<td>$lang_text{'page'}</td><td>|.
             popup_menu(-name=>'page',
                        -values=>\@pagevalues,
                        -default=>$page,
                        -onChange=>"JavaScript:document.pageform.submit();",
                        -override=>'1').
             qq|</td>|.ow::tool::hiddens(longpage=>$longpage).qq|<td>|;

   my $longpage_url="$main_url?sessionid=$thissession&amp;folder=$escapedfolder&amp;".
                    "action=listmessages&amp;page=$page&amp;".
                    "sort=$sort&amp;msgdatetype=$msgdatetype&amp;".
                    "keyword=$escapedkeyword&amp;searchtype=$searchtype";
   if ($longpage) {
      my $str=$lang_text{'msgsperpage'}; $str=~s/\@\@\@MSGCOUNT\@\@\@/$prefs{'msgsperpage'}/;
      $htmlpage.=qq|<a href="$longpage_url&amp;longpage=0" title="$str">&nbsp;-&nbsp;</a>|;
   } else {
      my $str=$lang_text{'msgsperpage'}; $str=~s/\@\@\@MSGCOUNT\@\@\@/1000/;
      $htmlpage.=qq|<a href="$longpage_url&amp;longpage=1" title="$str">&nbsp;+&nbsp;</a>|;
   }
   $htmlpage.=qq|</td></tr></table>|;

   my (@movefolders, %movelabels); %movelabels=%lang_folders;
   # option to del message directly from folder
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      @movefolders=('DELETE');
   } else {
      foreach my $f (@validfolders) {
         my ($value, $label)=(ow::tool::escapeURL($f), $f);
         $label=(defined $lang_folders{$f})?$lang_folders{$f}:f2u($f);
         push(@movefolders, $value); $movelabels{$value}=$label if ($value ne $label);
      }
      push(@movefolders, 'LEARNSPAM', 'LEARNHAM') if ($config{'enable_learnspam'});
      push(@movefolders, 'FORWARD', 'DELETE');
   }
   my $defaultdestination;
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      $defaultdestination='DELETE';
   } elsif ($folder eq 'mail-trash' || $folder eq 'spam-mail' || $folder eq 'virus-mail') {
      $defaultdestination= 'INBOX';
   } elsif ($folder eq 'sent-mail' || $folder eq 'saved-drafts') {
      $defaultdestination='mail-trash';
   } else {
      $defaultdestination= $prefs{'defaultdestination'} || 'mail-trash';
      $defaultdestination='mail-trash' if ( $folder eq $defaultdestination);
   }
   $htmlmove = qq|<table cellspacing="0" cellpadding="0"><tr><td>|.
               popup_menu(-name=>'destination',
                          -default=>ow::tool::escapeURL($defaultdestination),
                          -values=>\@movefolders,
                          -labels=>\%movelabels,
                          -accesskey=>'T',	# target folder
                          -override=>'1').
               qq|</td><td>|.
               submit(-name =>'movebutton',
                      -value=>$lang_text{'move'},
                      -onClick=>"return OpConfirm($lang_text{'msgmoveconf'}, $prefs{'confirmmsgmovecopy'})");
   if (!$limited) {
      $htmlmove .= qq|</td><td>|.
                   submit(-name =>'copybutton',
                          -value=>$lang_text{'copy'},
                          -onClick=>"return OpConfirm($lang_text{'msgcopyconf'}, $prefs{'confirmmsgmovecopy'})");
   }
   $htmlmove .= qq|</td></tr></table>|;

   if ($prefs{'ctrlposition_folderview'} eq 'top') {
      templateblock_enable($html, 'CONTROLBAR1');
      templateblock_disable($html, 'CONTROLBAR2');
      $html =~ s/\@\@\@SEARCH1\@\@\@/$htmlsearch/;
      $html =~ s/\@\@\@PAGEMENU1\@\@\@/$htmlpage/;
      $html =~ s/\@\@\@MOVECONTROLS1\@\@\@/$htmlmove/;
   } else {
      templateblock_disable($html, 'CONTROLBAR1');
      templateblock_enable($html, 'CONTROLBAR2');
      $html =~ s/\@\@\@SEARCH2\@\@\@/$htmlsearch/;
      $html =~ s/\@\@\@PAGEMENU2\@\@\@/$htmlpage/;
      $html =~ s/\@\@\@MOVECONTROLS2\@\@\@/$htmlmove/;
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
                 qq|showmsg('$prefs{"charset"}', '$lang_text{"quotahit"}', '$msg', '$lang_text{"close"}', '_quotahit_del', 400, 100, 60);\n|.
                 qq|//-->\n</script>\n|;
   }
   # show quotahit alert
   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      my $msg=qq|<font size="-1" color="#cc0000">$lang_err{'quotahit_alert'}</font>|;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$prefs{"charset"}', '$lang_text{"quotahit"}', '$msg', '$lang_text{"close"}', '_quotahit_alert', 400, 100, 60);\n|.
                 qq|//-->\n</script>\n|;
   # show spool overlimit alert
   } elsif ($config{'spool_limit'}>0 && $inboxsize_k>$config{'spool_limit'}) {
      my $msg=qq|<font size="-1" color="#cc0000">$lang_err{'spool_overlimit'}</font>|;
      $msg=~s/\@\@\@SPOOLLIMIT\@\@\@/$config{'spool_limit'}$lang_sizes{'kb'}/;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$prefs{"charset"}', '$lang_text{"quotahit"}', '$msg', '$lang_text{"close"}', '_spool_overlimit', 400, 100, 60);\n|.
                 qq|//-->\n</script>\n|;
   }
   # show msgsent confirmation
   if (defined param('sentsubject') && $prefs{'mailsentwindowtime'}>0) {
      my $msg=qq|<font size="-1">$lang_text{'msgsent'}</font>|;
      my $sentsubject=param('sentsubject')||'N/A';
      $msg=~s!\@\@\@SUBJECT\@\@\@!$sentsubject!;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$prefs{"charset"}', '$lang_text{"send"}', '$msg', '$lang_text{"close"}', '_msgsent', 300, 100, $prefs{"mailsentwindowtime"});\n|.
                 qq|//-->\n</script>\n|;
   }
   # popup stat of incoming msgs
   if ( $prefs{'newmailwindowtime'}>0) {
      my ($totalfiltered, %filtered)=read_filterfolderdb(1);
      if ($totalfiltered>0 ||
          $now_inbox_newmessages>$orig_inbox_newmessages) {
         my $msg;
         my $line=0;
         if ($now_inbox_newmessages>$orig_inbox_newmessages) {
            $msg .= qq|$lang_folders{'INBOX'} &nbsp; |.($now_inbox_newmessages-$orig_inbox_newmessages).qq|<br>|;
            $line++;
         }
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
                    qq|showmsg('$prefs{"charset"}', '$lang_text{"inmessages"}', '$msg', '$lang_text{"close"}', '_incoming', 200, |.($line*16+70).qq|, $prefs{'newmailwindowtime'});\n|.
                    qq|//-->\n</script>\n|;
      }
   }
   $html.=readtemplate('showmsg.js').$temphtml if ($temphtml);

   # since $headershtml may be large, we put it into $html as late as possible
   $html =~ s/\@\@\@HEADERS\@\@\@/$headershtml/; undef($headershtml);

   # since some browsers always treat refresh directive as realtive url.
   # we use relative path for refresh
   my $refreshinterval=$prefs{'refreshinterval'}*60;
   my $relative_url="$config{'ow_cgiurl'}/openwebmail-main.pl";
   $relative_url=~s!/.*/!!g;

   # show unread inbox messages count in titlebar
   my $unread_messages_info;
   if ($now_inbox_newmessages>0) {
      $unread_messages_info = "$lang_folders{INBOX}: $now_inbox_newmessages $lang_text{'messages'} $lang_text{'unread'}";
   }

   httpprint([-Refresh=>"$refreshinterval;URL=$relative_url?sessionid=$thissession&sort=$sort&msgdatetype=$msgdatetype&keyword=$escapedkeyword&searchtype=$searchtype&folder=INBOX&action=listmessages&page=1&session_noupdate=1"],
             [htmlheader($unread_messages_info),
              htmlplugin($config{'header_pluginfile'}, $config{'header_pluginfile_charset'}, $prefs{'charset'}),
              $html,
              htmlplugin($config{'footer_pluginfile'}, $config{'footer_pluginfile_charset'}, $prefs{'charset'}),
              htmlfooter(2)] );
}


# reminder for events within 7 days
sub eventreminder_html {
   my ($reminderdays)=@_;

   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($year, $month, $day, $hour, $min)=(ow::datetime::seconds2array($localtime))[5,4,3,2,1];
   $year+=1900; $month++;
   my $hourmin=sprintf("%02d%02d", $hour, $min);

   my $calbookfile=dotpath('calendar.book');
   my (%items, %indexes);
   if ( readcalbook($calbookfile, \%items, \%indexes, 0)<0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

   my $event_count=0;
   my %used;	# tag used index so an item won't be show more than once in case it is a regexp
   my $temphtml="";
   for my $x (0..$reminderdays-1) {
      my $wdaynum;
      ($wdaynum, $year, $month, $day)=(ow::datetime::seconds2array($localtime+$x*86400))[6,5,4,3];
      $year+=1900; $month++;
      my $dow=$ow::datetime::wday_en[$wdaynum];
      my $date=sprintf("%04d%02d%02d", $year,$month,$day);
      my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

      my @indexlist=();
      push(@indexlist, @{$indexes{$date}}) if (defined $indexes{$date});
      push(@indexlist, @{$indexes{'*'}})   if (defined $indexes{'*'});
      @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

      my $dayhtml="";
      for my $index (@indexlist) {
         next if ($used{$index});
         next if (!$items{$index}{'eventreminder'});

         if ($date=~/$items{$index}{'idate'}/  ||
             $date2=~/$items{$index}{'idate'}/ ||
             ow::datetime::easter_match($year,$month,$day,$items{$index}{'idate'}) ) {
            if ($items{$index}{'starthourmin'}>=$hourmin ||
                $items{$index}{'starthourmin'}==0 ||
                $x>0) {
               $event_count++;
               $used{$index}=1;
               last if ($event_count>5);
               my ($t, $s);

               if ($items{$index}{'starthourmin'}=~/(\d+)(\d\d)/) {
                  if ($prefs{'hourformat'}==12) {
                     my ($h, $ampm)=ow::datetime::hour24to12($1);
                     $t="$h:$2$ampm";
                  } else {
                     $t="$1:$2";
                  }
                  if ($items{$index}{'endhourmin'}=~/(\d+)(\d\d)/) {
                     if ($prefs{'hourformat'}==12) {
                        my ($h, $ampm)=ow::datetime::hour24to12($1);
                        $t.="-$h:$2$ampm";
                     } else {
                        $t.="-$1:$2";
                     }
                  }
               } else {
                  $t='#';
               }

               ($s)=iconv($items{$index}{'charset'}, $prefs{'charset'}, $items{$index}{'string'});
               $s=substr($s,0,20).".." if (length($s)>=21);
               $s.='*' if ($index>=1E6);
               $dayhtml.=qq|&nbsp; | if $dayhtml ne "";
               $dayhtml.=qq|<font class="smallcolortext">$t </font><font class="smallblacktext">$s</font>|;
            }
         }
      }
      if ($dayhtml ne "") {
         my $title=$prefs{'dateformat'}||"mm/dd/yyyy";
         my ($m, $d)=(sprintf("%02d",$month), sprintf("%02d",$day));
         $title=~s/yyyy/$year/; $title=~s/mm/$m/; $title=~s/dd/$d/;
         if ($lang_text{'calfmt_yearmonthdaywday'} =~ /^\s*\@\@\@WEEKDAY\@\@\@/) {
            $title="$lang_wday{$wdaynum} $title";
         } else {
            $title="$title $lang_wday{$wdaynum}";
         }
         $temphtml.=qq| &nbsp; | if ($temphtml ne"");
         $temphtml.=qq|<font class="smallblacktext">[+$x] </font>| if ($x>0);
         $temphtml.=qq|<a href="$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
                    qq|action=calday&amp;year=$year&amp;month=$month&amp;day=$day" title="$title">$dayhtml</a>\n|;
      }
   }
   $temphtml .= " &nbsp; ..." if ($event_count>5);

   $temphtml=qq|&nbsp;$temphtml|;
   return($temphtml);
}
########## END LISTMESSAGES ######################################

########## MARKASREAD ############################################
sub markasread {
   my $messageid = param('message_id');
   return if ($messageid eq "");

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my @attr=get_message_attributes($messageid, $folderdb);
   return if ($#attr<0);	# msg not found in db

   if ($attr[$_STATUS] !~ /R/i) {
      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");
      update_message_status($messageid, $attr[$_STATUS]."R", $folderdb, $folderfile);
      ow::filelock::lock($folderfile, LOCK_UN);
   }
}
########## END MARKASREAD ########################################

########## MARKASUNREAD ##########################################
sub markasunread {
   my $messageid = param('message_id');
   return if ($messageid eq "");

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my @attr=get_message_attributes($messageid, $folderdb);
   return if ($#attr<0);	# msg not found in db

   if ($attr[$_STATUS] =~ /[RV]/i) {
      # clear flag R(read), V(verified by mailfilter)
      my $newstatus=$attr[$_STATUS];
      $newstatus=~s/[RV]//ig;

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");
      update_message_status($messageid, $newstatus, $folderdb, $folderfile);
      ow::filelock::lock($folderfile, LOCK_UN);
   }
}
########## END MARKASUNREAD ######################################

########## MOVEMESSAGE ###########################################
sub movemessage {
   my ($r_messageids, $destination)=@_;
   if ($destination eq $folder) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'shouldnt_move_here'}");
   }

   my $op='move';
   if ($destination eq 'DELETE') {	# copy to DELETE is meaningless, so return
      return if (defined param('copybutton'));		# copy to delete =>nothing to do
      $op='delete';
   } else {
      $op='copy' if (defined param('copybutton'));	# copy button pressed
   }
   if ($quotalimit>0 && $quotausage>$quotalimit && $op ne "delete") {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'quotahit_alert'}");
   }

   my ($learntype, $learnfolder)=('none', $folder);
   if ($destination eq 'LEARNSPAM') {
      $learntype='learnspam';
      $destination=$folder;	# default no move by set dst=src
      if ($folder ne 'spam-mail' && $folder ne 'virus-mail') {
         $learnfolder=$destination=$config{'learnspam_destination'};	# we will move spam if it was not in spam/virus
      }
   } elsif ($destination eq 'LEARNHAM') {
      $learntype='learnham';
      $destination=$folder;	# default no move by set dst=src
      if ($folder eq 'mail-trash' || $folder eq 'spam-mail' || $folder eq 'virus-mail') {
         $learnfolder=$destination=$config{'learnham_destination'};	# we will move ham if it was in trash/spam/virus
      }
   }

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my ($dstfile, $dstdb)=get_folderpath_folderdb($user, $destination);

   if (!-f $folderfile) {
      openwebmailerror(__FILE__, __LINE__, f2u($folderfile)." $lang_err{'doesnt_exist'}");
   }

   my ($counted, $errmsg)=(0, '');
   if ($folder ne $destination) {
      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");

      if ($destination eq 'DELETE') {
         ($counted, $errmsg)=operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb);
      } else {
         if (!-f "$dstfile" ) {
            if (!sysopen(F, $dstfile, O_WRONLY|O_APPEND|O_CREAT)) {
               my $err=$!;
               ow::filelock::lock($folderfile, LOCK_UN);
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $lang_err{'destination_folder'} ".f2u($dstfile)."! ($err)");
            }
            close(F);
         }
         if (!ow::filelock::lock($dstfile, LOCK_EX)) {
            ow::filelock::lock($folderfile, LOCK_UN);
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($dstfile)."!");
         }
         ($counted, $errmsg)=operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb, $dstfile, $dstdb);
      }
      folder_zapmessages($folderfile, $folderdb) if ($counted>0);

      ow::filelock::lock($dstfile, LOCK_UN);
      ow::filelock::lock($folderfile, LOCK_UN);
   }

   # fork a child to do learn the msg in background
   # thus the resulted msglist can be returned as soon as possible
   if ($learntype ne 'none') {
      # below handler is not necessary, as we call zombie_cleaner at end of each request
      #local $SIG{CHLD}=\&ow::tool::zombie_cleaner;

      local $|=1; 			# flush all output

      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         writelog("debug - $learntype process forked - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});

         ow::suid::drop_ruid_rgid(); # set ruid=euid to avoid fork in spamcheck.pl
         my ($totallearned, $totalexamed)=(0,0);
         my ($learnfile, $learndb)=get_folderpath_folderdb($user, $learnfolder);
         my $learnhandle=FileHandle->new();
         foreach my $messageid (@{$r_messageids}) {
            my ($msgsize, $errmsg, $block, $learned, $examed);
            ($msgsize, $errmsg)=lockget_message_block($messageid, $learnfile, $learndb, \$block);
            next if ($msgsize<=0);

            if ($learntype eq 'learnspam') {
               ($learned, $examed)=ow::spamcheck::learnspam($config{'learnspam_pipe'}, \$block);
            } else {
               ($learned, $examed)=ow::spamcheck::learnham($config{'learnham_pipe'}, \$block);
            }
            if ($learned==-99999) {
               my $m="$learntype - error ($examed) at $messageid";
               writelog($m); writehistory($m);
               last;
            } else {
               $totallearned+=$learned;
               $totalexamed+=$examed;
            }
         }
         my $m="$learntype - $totallearned learned, $totalexamed examined";
         writelog($m); writehistory($m);

         writelog("debug - $learntype process terminated - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});
         openwebmail_exit(0);
      }
   }

   if ($counted>0){
      my $msg;
      if ( $op eq 'move') {
         $msg="move message - move $counted msgs from $folder to $destination - ids=".join(", ", @{$r_messageids});
      } elsif ($op eq 'copy' ) {
         $msg="copy message - copy $counted msgs from $folder to $destination - ids=".join(", ", @{$r_messageids});
      } else {
         $msg="delete message - delete $counted msgs from $folder - ids=".join(", ", @{$r_messageids});
        # recalc used quota for del if user quotahit
        if ($quotalimit>0 && $quotausage>$quotalimit) {
           $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
        }
      }
      writelog($msg);
      writehistory($msg);
   } elsif ($counted<0) {
      openwebmailerror(__FILE__, __LINE__, $errmsg);
   }
   return;
}
########## END MOVEMESSAGE #######################################

########## EMPTYFOLDER ############################################
sub www_emptyfolder {
   my $folder=$_[0];
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");
   my $ret=empty_folder($folderfile, $folderdb);
   ow::filelock::lock($folderfile, LOCK_UN);

   if ($ret==-1) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} ".f2u($folderfile)."!");
   } elsif ($ret==-2) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} db ".f2u($folderdb));
   }
   writelog("emptyfolder - $folder");
   writehistory("emptyfolder - $folder");
}
########## END EMPTYFOLDER ########################################

########## RETRIVEPOP3/RETRPOP3S #################################
sub www_pop3_fetch {
   my $pop3host = param('pop3host') || '';
   my $pop3port = param('pop3port') || '110';
   my $pop3user = param('pop3user') || '';
   my $pop3book = dotpath('pop3.book');
   return if ($pop3host eq '' || $pop3user eq '' || !-f $pop3book);

   foreach ( @{$config{'pop3_disallowed_servers'}} ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'disallowed_pop3'} $pop3host") if ($pop3host eq $_);
   }
   my %accounts;
   if (readpop3book($pop3book, \%accounts) <0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $pop3book!");
   }
   # don't care enable flag since this is triggered by user clicking
   my ($pop3ssl, $pop3passwd, $pop3del)
	=(split(/\@\@\@/, $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}))[2,4,5];

   my ($ret, $errmsg)=pop3_fetch($pop3host,$pop3port,$pop3ssl, $pop3user,$pop3passwd,$pop3del);
   if ($ret<0) {
      openwebmailerror(__FILE__, __LINE__, "$errmsg at $pop3user\@$pop3host:$pop3port");
   }
}

sub pop3_fetch {
   my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del)=@_;

   my ($ret, $errmsg)=fetchmail($pop3host, $pop3port, $pop3ssl,
                                $pop3user, $pop3passwd, $pop3del);
   if ($ret<0) {
      writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
      writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
   }
   return($ret, $errmsg);
}

sub authpop3_fetch {
   return 0 if (!$config{'authpop3_getmail'});

   my $authpop3book=dotpath('authpop3.book');
   my %accounts;
   if ( -f "$authpop3book") {
      if (readpop3book($authpop3book, \%accounts)>0) {
         my $login=$user;  $login.="\@$domain" if ($config{'auth_withdomain'});
         my ($pop3ssl, $pop3passwd, $pop3del)
		=(split(/\@\@\@/, $accounts{"$config{'authpop3_server'}:$config{'authpop3_port'}\@\@\@$login"}))[2,4,5];
         # don't case enable flag since noreason to stop fetch from auth server
         return pop3_fetch($config{'authpop3_server'},$config{'authpop3_port'},$pop3ssl, $login,$pop3passwd,$pop3del);
      } else {
         writelog("pop3 error - couldn't open $authpop3book");
         writehistory("pop3 error - couldn't open $authpop3book");
      }
   }
   return 0;
}

sub www_pop3_fetches {
   return if (! -f dotpath('pop3.book'));
   if (update_pop3check()) {
      authpop3_fetch() if ($config{'auth_module'} eq 'auth_pop3.pl' ||
                           $config{'auth_module'} eq 'auth_ldap_vpopmail.pl');
   }
   pop3_fetches(10);	# wait background fetching for no more 10 second
}

use vars qw($pop3_fetches_complete);
sub pop3_fetches {
   my $timeout=$_[0];
   my $pop3book=dotpath('pop3.book');
   my %accounts;

   return 0 if ( ! -f "$pop3book" );
   if (readpop3book("$pop3book", \%accounts)<0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $pop3book!");
   }

   # fork a child to do fetch pop3 mails and return immediately
   if (%accounts>0) {
      local $|=1; # flush all output
      local $pop3_fetches_complete=0;	# localize for reentry safe
      local $SIG{CHLD} = sub { wait; $pop3_fetches_complete=1; };	# signaled when pop3 fetch completes

      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         writelog("debug - fetch pop3s process forked - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});

         ow::suid::drop_ruid_rgid(); # set ruid=euid can avoid fork in spamcheck.pl
         foreach (values %accounts) {
            my ($pop3host,$pop3port,$pop3ssl, $pop3user,$pop3passwd, $pop3del, $enable)=split(/\@\@\@/,$_);
            next if (!$enable);

            my $disallowed=0;
            foreach ( @{$config{'pop3_disallowed_servers'}} ) {
               if ($pop3host eq $_) {
                  $disallowed=1; last;
               }
            }
            next if ($disallowed);
            my ($ret, $errmsg) = fetchmail($pop3host, $pop3port, $pop3ssl,
                                           $pop3user, $pop3passwd, $pop3del);
            if ($ret<0) {
               writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
               writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
            }
         }

         writelog("debug - fetch pop3s process terminated - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});
         openwebmail_exit(0);
      }

      for (my $i=0; $i<$timeout; $i++) {	# wait fetch to complete for $timeout seconds
         sleep 1;
         last if ($pop3_fetches_complete);
      }
   }

   return 0;
}

sub update_pop3check {
   my $now=time();
   my $pop3checkfile=dotpath('pop3.check');

   my $ftime=(stat($pop3checkfile))[9];

   if (!$ftime) {	# create if not exist
      sysopen(F, $pop3checkfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $pop3checkfile! ($!)");
      print F "pop3check timestamp file";
      close(F);
   }
   if ( $now-$ftime > $config{'fetchpop3interval'}*60 ) {
      utime($now-1, $now-1, ow::tool::untaint($pop3checkfile));	# -1 is trick for nfs
      return 1;
   } else {
      return 0;
   }
}
########## END RETRIVEPOP3/RETRPOP3S #############################

########## MOVEOLDMSG2SAVED ######################################
sub moveoldmsg2saved {
   my ($srcfile, $srcdb)=get_folderpath_folderdb($user, 'INBOX');
   my ($dstfile, $dstdb)=get_folderpath_folderdb($user, 'saved-messages');

   ow::filelock::lock($srcfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($srcfile)."!");
   ow::filelock::lock($dstfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($dstfile)."!");

   my $counted=move_oldmsg_from_folder($srcfile, $srcdb, $dstfile, $dstdb);

   ow::filelock::lock($dstfile, LOCK_UN);
   ow::filelock::lock($srcfile, LOCK_UN);

   if ($counted>0){
      my $msg="move message - move $counted old msgs from INBOX to saved-messages";
      writelog($msg);
      writehistory($msg);
   }
}
########## END MOVEOLDMSG2SAVED ##################################

########## CLEANTRASH ############################################
sub clean_trash_spamvirus {
   my $now=time();
   my $trashcheckfile=dotpath('trash.check');
   my $ftime=(stat($trashcheckfile))[9];
   if (!$ftime) {	# create if not exist
      sysopen(TRASHCHECK, $trashcheckfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} ".f2u($trashcheckfile)."! ($!)");
      print TRASHCHECK "trashcheck timestamp file";
      close(TRASHCHECK);
   }

   my %reserveddays=('mail-trash' => $prefs{'trashreserveddays'},
                     'spam-mail'  => $prefs{'spamvirusreserveddays'},
                     'virus-mail' => $prefs{'spamvirusreserveddays'} );
   my (@f, $msg);
   push(@f, 'virus-mail') if ($config{'has_virusfolder_by_default'});
   push(@f, 'spam-mail') if ($config{'has_spamfolder_by_default'});
   push(@f, 'mail-trash');
   foreach my $folder (@f) {
      next if ($reserveddays{$folder}<0 || $reserveddays{$folder}>=999999);

      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");
      if ($reserveddays{$folder}==0) {	# empty folder
         my $ret=empty_folder($folderfile, $folderdb);
         if ($ret == 0) {
            $msg.=', ' if ($msg ne '');
            $msg.="all msg deleted from $folder";
         }
      } elsif ( $now-$ftime > 43200 ) {	# do clean only if last clean has passed for more than 0.5 day (43200 sec)
         my $deleted=delete_message_by_age($reserveddays{$folder}, $folderdb, $folderfile);
         if ($deleted > 0) {
            $msg.=', ' if ($msg ne '');
            $msg.="$deleted msg deleted from $folder";
         }
      }
      ow::filelock::lock($folderfile, LOCK_UN);
   }
   if ($msg ne '') {
      writelog("clean trash - $msg");
      writehistory("clean trash - $msg");
   }

   if ( $now-$ftime > 43200 ) {	# mor than half day, update timestamp of checkfile
      utime($now-1, $now-1, ow::tool::untaint($trashcheckfile));	# -1 is trick for nfs
   }
   return;
}
########## END CLEANTRASH ########################################

########## LOGOUT ################################################
sub logout {
   unlink "$config{'ow_sessionsdir'}/$thissession";
   autologin_rm();	# disable next autologin for specific ip/browser/user
   writelog("logout - $thissession");
   writehistory("logout - $thissession");

   my ($html, $temphtml);
   $html = applystyle(readtemplate("logout.template"));

   my $start_url=$config{'start_url'};

   if (cookie("ow-ssl")) {	# backto SSL
      $start_url="https://$ENV{'HTTP_HOST'}$start_url" if ($start_url!~s!^https?://!https://!i);
   }
   $temphtml = start_form(-action=>"$start_url");
   $temphtml .= ow::tool::hiddens(logindomain=>$default_logindomain) if ($default_logindomain);
   $temphtml .= submit("$lang_text{'loginagain'}").
                "&nbsp; &nbsp;".
                button(-name=>'exit',
                       -value=>$lang_text{'exit'},
                       -onclick=>'javascript:top.window.close();',
                       -override=>'1').
                end_form();
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/;

   # clear session cookie at logout
   my $cookie= cookie(-name  => "ow-sessionkey-$domain-$user",
                      -value => '',
                      -path  => '/',
                      -expires => '+1s');
   httpprint([-cookie => $cookie], [htmlheader(), $html, htmlfooter(2)]);
}
########## END LOGOUT ############################################
