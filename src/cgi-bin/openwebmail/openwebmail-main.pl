#!/usr/bin/suidperl -T
#
# openwebmail-main.pl - message list browing program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1 }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1 }
}
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

foreach (qw(PATH ENV BASH_ENV CDPATH IFS TERM)) { $ENV{$_}='' }	# secure ENV
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/dbm.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/htmltext.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/cut.pl";
require "shares/getmsgids.pl";
require "shares/pop3mail.pl";
require "shares/pop3book.pl";
require "shares/calbook.pl";
require "shares/mailfilter.pl";

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
use vars qw($_STATUS);				# defined in maildb.pl
use vars qw(%is_defaultfolder @defaultfolders);	# defined in ow-shared.pl

# local globals
use vars qw($folder);
use vars qw($sort $page);
use vars qw($searchtype $keyword);
use vars qw($escapedfolder $escapedkeyword);

########## MAIN ##################################################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop
$SIG{CHLD}='IGNORE';		# prevent zombie

userenv_init();

my $action = param('action')||'';
if (!$config{'enable_webmail'} && $action ne "logout") {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = param('folder') || 'INBOX';
$page = param('page') || 1;
$sort = param('sort') || $prefs{'sort'} || 'date';
$searchtype = param('searchtype') || 'subject';
$keyword = param('keyword') || ''; $keyword=~s/^\s*//; $keyword=~s/\s*$//;

$escapedfolder = ow::tool::escapeURL($folder);
$escapedkeyword = ow::tool::escapeURL($keyword);

if ($action eq "movemessage" ||
    defined(param('movebutton')) ||
    defined(param('copybutton')) ) {
   my @messageids = param('message_ids');
   movemessage(\@messageids) if ($#messageids>=0);
   if (param('messageaftermove')) {
      my $headers = param('headers') || $prefs{'headers'} || 'simple';
      my $attmode = param('attmode') || 'simple';
      my $escapedmessageid=ow::tool::escapeURL(param('message_id')||'');
      $escapedmessageid=ow::tool::escapeURL($messageids[0]) if (defined(param('copybutton'))); # copy button pressed, msg not moved
      print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-read.pl?sessionid=$thissession&folder=$escapedfolder&page=$page&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&message_id=$escapedmessageid&action=readmessage&headers=$headers&attmode=$attmode");
   } else {
      listmessages();
   }
} elsif ($action eq "listmessages_afterlogin") {
   cleantrash($prefs{'trashreserveddays'});
   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   if ( ($config{'forced_moveoldmsgfrominbox'}||$prefs{'moveoldmsgfrominbox'}) &&
        (!$quotalimit||$quotausage<$quotalimit) ) {
      moveoldmsg2saved();
   }
   update_pop3check();
   _retrauthpop3() if ($config{'auth_module'} eq 'auth_pop3.pl');
   _retrpop3s($prefs{'autopop3wait'}) if ($config{'enable_pop3'} && $prefs{'autopop3'});
   listmessages();
} elsif ($action eq "userrefresh") {
   if ($config{'auth_module'} eq 'auth_pop3.pl' && $folder eq "INBOX" ) {
      _retrauthpop3();
   }
   if ($config{'quota_module'} ne 'none') {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   listmessages();
   if (update_pop3check()) {
      _retrpop3s(0) if ($config{'enable_pop3'} && $prefs{'autopop3'});
   }
} elsif ($action eq "listmessages") {
   my $update=0; $update=1 if (update_pop3check());
   if ($update) {	# get mail from auth pop3 server
      _retrauthpop3() if ($config{'auth_module'} eq 'auth_pop3.pl');
   }
   listmessages();
   if ($update) {	# get mail from misc pop3 servers
      _retrpop3s(0) if ($config{'enable_pop3'} && $prefs{'autopop3'});
   }
} elsif ($action eq "markasread") {
   markasread();
   listmessages();
} elsif ($action eq "markasunread") {
   markasunread();
   listmessages();
} elsif ($action eq "retrpop3s" && $config{'enable_pop3'}) {
   retrpop3s();
   listmessages();
} elsif ($action eq "retrpop3" && $config{'enable_pop3'}) {
   retrpop3();
   listmessages();
} elsif ($action eq "emptytrash") {
   emptytrash();
   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   listmessages();
} elsif ($action eq "logout") {
   cleantrash($prefs{'trashreserveddays'});
   if ( ($config{'forced_moveoldmsgfrominbox'}||
         $prefs{'moveoldmsgfrominbox'}) &&
        (!$quotalimit||$quotausage<$quotalimit) ) {
      moveoldmsg2saved();
   }
   logout();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

openwebmail_requestend();
########## END MAIN ##############################################

########## LISTMESSGAES ##########################################
sub listmessages {
   my $orig_inbox_newmessages=0;
   my $now_inbox_newmessages=0;
   my $now_inbox_allmessages=0;
   my $inboxsize_k=0;
   my $trash_allmessages=0;
   my %FDB;

   my $spooldb=(get_folderpath_folderdb($user, 'INBOX'))[1];
   if (ow::dbm::exist($spooldb)) {
      ow::dbm::open(\%FDB, $spooldb, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} db $spooldb");
      $orig_inbox_newmessages=$FDB{'NEWMESSAGES'};	# new msg in INBOX
      ow::dbm::close(\%FDB, $spooldb);
   }

   my ($filtered, $r_filtered)=filtermessage2($user, 'INBOX', \%prefs);

   my (@validfolders, $folderusage);
   getfolders(\@validfolders, \$folderusage);

   my $quotahit_deltype='';
   if ($quotalimit>0 && $quotausage>$quotalimit &&
       ($config{'delmail_ifquotahit'}||$config{'delfile_ifquotahit'}) ) {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      if ($quotausage>$quotalimit) {
         if ($config{'delmail_ifquotahit'} && $folderusage > $quotausage*0.5) {
            $quotahit_deltype='quotahit_delmail';
            cutfoldermails(($quotausage-$quotalimit*0.9)*1024, $user, @validfolders);
         } elsif ($config{'delfile_ifquotahit'}) {
            $quotahit_deltype='quotahit_delfile';
            my $webdiskrootdir=$homedir.absolute_vpath("/", $config{'webdisk_rootpath'});
            cutdirfiles(($quotausage-$quotalimit*0.9)*1024, $webdiskrootdir);
         }
         $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      }
   }

   # reset global $folder to INBOX if it is not a valid folder
   my $is_validfolder=0;
   foreach (@validfolders) {
      if ($_ eq $folder) { $is_validfolder=1; last; }
   }
   $folder='INBOX' if (!$is_validfolder);

   my ($totalsize, $newmessages, $r_messageids, $r_messagedepths)=getinfomessageids($user, $folder, $sort, $searchtype, $keyword);

   my $totalmessage=$#{$r_messageids}+1;
   $totalmessage=0 if ($totalmessage<0);
   my $totalpage = int($totalmessage/($prefs{'msgsperpage'}||10)+0.999999);
   $totalpage=1 if ($totalpage==0);

   $page = 1 if ($page < 1);
   $page = $totalpage if ($page > $totalpage);

   my $firstmessage = (($page-1)*$prefs{'msgsperpage'}) + 1;
   my $lastmessage = $firstmessage + $prefs{'msgsperpage'} - 1;
   $lastmessage = $totalmessage if ($lastmessage > $totalmessage);

   my $main_url = "$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder";
   my $main_url_with_keyword = "$main_url&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype";

   my ($html, $temphtml);
   $html = applystyle(readtemplate("viewfolder.template"));

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   ### we don't keep keyword, firstpage between folders,
   ### thus the keyword, firstpage will be cleared when user change folder
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
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
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} db $folderdb");
         $allmessages=$FDB{'ALLMESSAGES'};
         $allmessages-=$FDB{'INTERNALMESSAGES'} if ($prefs{'hideinternal'});
         $newmessages=$FDB{'NEWMESSAGES'};
         if ($foldername eq 'INBOX') {
            $now_inbox_allmessages=$allmessages;
            $now_inbox_newmessages=$newmessages;
            $inboxsize_k=(-s $folderfile)/1024;
         } elsif ($foldername eq 'mail-trash')  {
            $trash_allmessages=$allmessages;
         }
         ow::dbm::close(\%FDB, $folderdb);
      }

      my $option_str=qq|<OPTION value="$foldername"|;
      $option_str.=qq| selected| if ($foldername eq $folder);
      if ($newmessages>0) {
         $option_str.=qq| class="hilighttext">|;
      } else {
         $option_str.=qq|>|;
      }
      if (defined $lang_folders{$foldername}) {
         $option_str.=$lang_folders{$foldername};
      } else {
         $option_str.=$foldername;
      }
      $option_str.=" ($newmessages/$allmessages)" if ( $newmessages ne "" && $allmessages ne "");

      $select_str.="$option_str\n";
   }
   $select_str.="</SELECT>\n";

   $temphtml.=$select_str;
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
      $temphtml .= iconlink("compose.gif", $lang_text{'composenew'}, qq|accesskey="C" href="$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page&amp;compose_caller=main"|);
      $temphtml .= qq|&nbsp;\n|;
   }

   $temphtml .= iconlink("folder.gif", $lang_text{'folders'}, qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-folder.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page"|).
                iconlink("addrbook.gif", $lang_text{'addressbook'}, qq|accesskey="A" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page"|);
   if ($config{'enable_userfilter'}) {
      $temphtml .= iconlink("filtersetup.gif", $lang_text{'filterbook'}, qq|accesskey="I" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page"|);
   }

   $temphtml .= qq|&nbsp;\n|;

   if ($config{'enable_pop3'} && $folder eq "INBOX") {
      $temphtml .= iconlink("pop3.gif", $lang_text{'retr_pop3s'}, qq|accesskey="G" href="$main_url_with_keyword&amp;action=retrpop3s"|);
   }
   $temphtml .= iconlink("advsearch.gif", $lang_text{'advsearch'}, qq|accesskey="V" href="$config{'ow_cgiurl'}/openwebmail-advsearch.pl?action=advsearch&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;page=$page"|);
   $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'}, qq|accesskey="R" href="$main_url&amp;action=userrefresh&amp;page=$page&amp;userfresh=1"|);

   $temphtml .= qq|&nbsp;\n|;

   if ($config{'enable_calendar'}) {
      $temphtml .= iconlink("calendar.gif", $lang_text{'calendar'}, qq|accesskey="K" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=$prefs{'calendar_defaultview'}&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
   }
   if ($config{'enable_webdisk'}) {
      $temphtml .= iconlink("webdisk.gif", $lang_text{'webdisk'}, qq|accesskey="E" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
   }
   if ( $config{'enable_sshterm'}) {
      if ( -r "$config{'ow_htmldir'}/applet/mindterm2/mindterm.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm2/ssh2.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      } elsif ( -r "$config{'ow_htmldir'}/applet/mindterm/mindtermfull.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm/ssh.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      }
   }
   if ( $config{'enable_preference'}) {
      $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;sort=$sort&amp;page=$page&amp;prefs_caller=main"|);
   }
   $temphtml .= iconlink("logout.gif", "$lang_text{'logout'} $prefs{'email'}", qq|accesskey="X" href="$main_url&amp;action=logout"|);

   $html =~ s/\@\@\@LEFTMENUBARLINKS\@\@\@/$temphtml/;

   if ($folder eq 'mail-trash') {
      $temphtml = iconlink("trash.gif", $lang_text{'emptytrash'}, qq|accesskey="Z" href="$main_url_with_keyword&amp;action=emptytrash&amp;page=$page" onclick="return confirm('$lang_text{emptytrash} ($trash_allmessages $lang_text{messages}) ?');"|);
   } else {
      my $trashfolder='mail-trash';
      $trashfolder='DELETE' if ($quotalimit>0 && $quotausage>$quotalimit);
      $temphtml = iconlink("totrash.gif", $lang_text{'totrash'}, qq|accesskey="Z" href="JavaScript:document.pageform.destination.value='$trashfolder'; document.pageform.movebutton.click();"|);
   }
   $temphtml .= qq|&nbsp;\n|;

   $html =~ s/\@\@\@RIGHTMENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                          -name=> 'pageform').
               ow::tool::hiddens(action=>'listmessages',
                                 sessionid=>$thissession,
                                 sort=>$sort,
                                 folder=>$folder);
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


   my $sort_url="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;page=$page&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;sort";
   my $linetemplate=$prefs{'fieldorder'};
   $linetemplate=~s/date/\@\@\@DATE\@\@\@/;
   $linetemplate=~s/from/\@\@\@FROM\@\@\@/;
   $linetemplate=~s/size/\@\@\@SIZE\@\@\@/;
   $linetemplate=~s/subject/\@\@\@SUBJECT\@\@\@/;
   $linetemplate='@@@STATUS@@@ '.$linetemplate.' @@@CHECKBOX@@@';

   my $headershtml='';
   my $linehtml=$linetemplate;

   $temphtml = iconlink("unread.gif", $lang_sortlabels{'status'}, qq|href="$sort_url=status"|);
   $temphtml = qq|<td width="6%" bgcolor=$style{'columnheader'} align="center">$temphtml</td>\n|;
   $linehtml =~ s/\@\@\@STATUS\@\@\@/$temphtml/;

   if ($sort eq "date") {
      $temphtml = qq|<a href="$sort_url=date_rev">$lang_text{'date'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($sort eq "date_rev") {
      $temphtml = qq|<a href="$sort_url=date">$lang_text{'date'}</a> |.iconlink("down.gif", "v", "");;
   } else {
      $temphtml = qq|<a href="$sort_url=date">$lang_text{'date'}</a>|;
   }
   $temphtml = qq|<td width="22%" bgcolor=$style{'columnheader'}><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@DATE\@\@\@/$temphtml/;

   if ( $folder=~ m#sent-mail#i ||
        $folder=~ m#saved-drafts#i ||
        $folder=~ m#\Q$lang_folders{'sent-mail'}\E#i ||
        $folder=~ m#\Q$lang_folders{'saved-drafts'}\E#i ) {
      if ($sort eq "recipient") {
         $temphtml = qq|<a href="$sort_url=recipient_rev">$lang_text{'recipient'}</a> |.iconlink("up.gif", "^", "");
      } elsif ($sort eq "recipient_rev") {
         $temphtml = qq|<a href="$sort_url=recipient">$lang_text{'recipient'}</a> |.iconlink("down.gif", "v", "");
      } else {
         $temphtml = qq|<a href="$sort_url=recipient">$lang_text{'recipient'}</a>|;
      }
   } else {
      if ($sort eq "sender") {
         $temphtml = qq|<a href="$sort_url=sender_rev">$lang_text{'sender'}</a> |.iconlink("up.gif", "^", "");
      } elsif ($sort eq "sender_rev") {
         $temphtml = qq|<a href="$sort_url=sender">$lang_text{'sender'}</a> |.iconlink("down.gif", "v", "");
      } else {
         $temphtml = qq|<a href="$sort_url=sender">$lang_text{'sender'}</a>|;
      }
   }
   $temphtml = qq|<td width="25%" bgcolor=$style{'columnheader'}><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@FROM\@\@\@/$temphtml/;

   if ($sort eq "subject") {
      $temphtml = qq|<a href="$sort_url=subject_rev">$lang_text{'subject'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($sort eq "subject_rev") {
      $temphtml = qq|<a href="$sort_url=subject">$lang_text{'subject'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$sort_url=subject">$lang_text{'subject'}</a>|;
   }
   $temphtml = qq|<td bgcolor=$style{'columnheader'}><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/;

   if ($sort eq "size") {
      $temphtml = qq|<a href="$sort_url=size_rev">$lang_text{'size'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($sort eq "size_rev") {
      $temphtml = qq|<a href="$sort_url=size">$lang_text{'size'}</a> |.iconlink("down.gif", "v", "");
   } else {
      if ($folder eq "mail-trash") {
         $temphtml = qq|<a href="$sort_url=size_rev">$lang_text{'size'}</a>|;
      } else {
         $temphtml = qq|<a href="$sort_url=size">$lang_text{'size'}</a>|;
      }
   }
   $temphtml = qq|<td width="5%" bgcolor=$style{'columnheader'} align="right"><B>$temphtml</B></td>\n|;
   $linehtml =~ s/\@\@\@SIZE\@\@\@/$temphtml/;

   $temphtml = qq|<td width="3%" bgcolor=$style{'columnheader'} align ="center">|.
               checkbox(-name=>'allbox',
                        -value=>'1',
                        -onClick=>"CheckAll();",
                        -label=>'',
                        -override=>'1').
               qq|</td>\n|;
   $linehtml =~ s/\@\@\@CHECKBOX\@\@\@/$temphtml/;

   $headershtml .= qq|<tr>$linehtml</tr>\n|;

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my ($messageid, $messagedepth, $escapedmessageid);
   my ($offset, $from, $to, $dateserial, $subject, $content_type, $status, $messagesize, $references, $charset);
   my ($bgcolor, $boldon, $boldoff);

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} db $folderdb");

   $temphtml = '';
   foreach my $messnum ($firstmessage  .. $lastmessage) {
      $messageid=${$r_messageids}[$messnum-1];
      $messagedepth=${$r_messagedepths}[$messnum-1];
      next if (! defined($FDB{$messageid}) );

      $escapedmessageid = ow::tool::escapeURL($messageid);
      ($offset, $from, $to, $dateserial, $subject,
	$content_type, $status, $messagesize, $references, $charset)=split(/@@@/, $FDB{$messageid});
      if ($charset eq '' && $prefs{'charset'} eq 'utf-8') {
         $charset=$ow::lang::languagecharsets{ow::lang::guess_language()};
      }

      # convert from mesage charset to current user charset
      if (is_convertable($charset, $prefs{'charset'})) {
         ($from, $to, $subject)=iconv($charset, $prefs{'charset'}, $from, $to, $subject);
      }

      $linehtml=$linetemplate;
      $bgcolor = ($style{"tablerow_dark"},$style{"tablerow_light"})[$messnum%2];

      # STATUS, choose status icons based on Status: line and type of encoding
      $temphtml = "<B>$messnum</B> \n";
      $status =~ s/\s//g;	# remove blanks
      if ( $status =~ /r/i ) {
         ($boldon, $boldoff) = ('', '');
         my $icon="read.gif"; $icon="read.a.gif" if ($status =~ m/a/i);
         $temphtml .= iconlink("$icon", "$lang_text{'markasunread'} ", qq|href="$main_url_with_keyword&amp;action=markasunread&amp;message_id=$escapedmessageid&amp;status=$status&amp;page=$page"|);
      } else {
         ($boldon, $boldoff) = ('<B>', '</B>');
         my $icon="unread.gif"; $icon="unread.a.gif" if ($status =~ m/a/i);
         $temphtml .= iconlink("$icon", "$lang_text{'markasread'} ", qq|href="$main_url_with_keyword&amp;action=markasread&amp;message_id=$escapedmessageid&amp;status=$status&amp;page=$page"|);
      }
      # T flag is only supported by openwebmail internally
      # see routine update_folderindex in maildb.pl for detail
      $temphtml .= iconlink("attach.gif", "", "")    if ($status =~ /T/i);
      $temphtml .= iconlink("important.gif", "", "") if ($status =~ /I/i);
      $temphtml = qq|<td bgcolor=$bgcolor nowrap>$temphtml&nbsp;</td>\n|;
      $linehtml =~ s/\@\@\@STATUS\@\@\@/$temphtml/;

      # DATE, convert dateserial(GMT) to localtime
      $temphtml=ow::datetime::dateserial2str($dateserial,
                                 $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                 $prefs{'dateformat'}, $prefs{'hourformat'});
      $temphtml = qq|<td bgcolor=$bgcolor>$boldon$temphtml$boldoff</td>\n|;
      $linehtml =~ s/\@\@\@DATE\@\@\@/$temphtml/;

      # FROM, we aren't interested in the sender of SENT/DRAFT folder,
      # but the recipient, so display $to instead of $from
      if ( $folder=~ m#sent-mail#i ||
           $folder=~ m#saved-drafts#i ||
           $folder=~ m#\Q$lang_folders{'sent-mail'}\E#i ||
           $folder=~ m#\Q$lang_folders{'saved-drafts'}\E#i ) {
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
         my $escapedto=ow::tool::escapeURL($to);

         $from='';
         if ($prefs{'useminisearchicon'}) {
            $from .= iconlink("search.s.gif", "$lang_text{'search'} $to_address", 
                               qq|href="$main_url&amp;action=listmessages&amp;sort=$sort&amp;searchtype=to&amp;keyword=|.
                               ow::tool::escapeURL(join('|',@addrlist)).qq|"| ).
                               qq|&nbsp;|;
         }
         if ($limited) {
            $from .= $to_name;
         } else {
            $from .= qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedto&amp;compose_caller=main" title="$to_address ">$to_name </a>|;
         }
      } else {
         my ($from_name, $from_address)=ow::tool::email2nameaddr($from);
         $from_address=~s/"//g;
         my $escapedfrom=ow::tool::escapeURL($from);

         $from='';
         if ($prefs{'useminisearchicon'}) {
            $from .= iconlink("search.s.gif", "$lang_text{'search'} $from_address", 
                              qq|href="$main_url&amp;action=listmessages&amp;sort=$sort&amp;searchtype=from&amp;keyword=|.
                              ow::tool::escapeURL($from_address).qq|"| ).
                              qq|&nbsp;|;
         }
         if ($limited) {
            $from .= qq|$from_name |;
         } else {
            $from .= qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedfrom&amp;compose_caller=main" title="$from_address ">$from_name </a>|;
         }
      }
      $temphtml=qq|<td bgcolor=$bgcolor>$boldon$from$boldoff</td>\n|;
      $linehtml =~ s/\@\@\@FROM\@\@\@/$temphtml/;

      # SUBJECT, cut subject to less than 64
      $subject=substr($subject, 0, 64)."..." if (length($subject)>67);
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
                  qq|sessionid=$thissession&amp;|.
                  qq|folder=$escapedfolder&amp;page=$page&amp;sort=$sort&amp;|.
                  qq|keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;|.
                  qq|message_id=$escapedmessageid&amp;action=readmessage&amp;|.
                  qq|headers=$prefs{'headers'}&amp;attmode=simple|;
      $temphtml.= qq|&amp;db_chkstatus=1| if ($status!~/r/i);
      $temphtml.= qq|" $accesskeystr title="Charset: $charset ">\n|.
                  $subject.
                  qq| </a>\n|;

      my ($subject_begin, $subject_end, $fill) = ('', '', '');
      for (my $i=1; $i<$messagedepth; $i++) {
         $fill .= "&nbsp; &nbsp; ";
      }
      if ( $messagedepth>0 && $sort eq "subject" ) {
         $fill .=qq|&nbsp; |.iconlink("follow.up.gif", "", "").qq|&nbsp;|;
      } elsif ( $messagedepth>0 && $sort eq "subject_rev") {
         $fill .=qq|&nbsp; |.iconlink("follow.down.gif", "", "").qq|&nbsp;|;
      }
      if ($messagedepth) {
         $subject_begin = qq|<table cellpadding="0" cellspacing="0"><tr><td nowrap>$fill</td><td>|;
         $subject_end = qq|</td></tr></table>|;
      }
      if ($prefs{'useminisearchicon'}) {
         my $subject2 = $subject; $subject2 =~ s/Res?:\s*//ig; $subject2=~s/\[.*?\]//g;
         my $searchstr = iconlink("search.s.gif", "$lang_text{'search'} $subject2 ", 
                                  qq|href="$main_url&amp;action=listmessages&amp;sort=$sort&amp;searchtype=subject&amp;keyword=|.
                                  ow::tool::escapeURL($subject2).qq|"| ).
                                  qq|&nbsp;|;
         $temphtml = qq|<td bgcolor=$bgcolor>|.
                     qq|<table cellspacing="0" cellpadding="0"><tr>\n|.
                     qq|<td>$searchstr</td>|.
                     qq|<td>$subject_begin$boldon$temphtml$boldoff$subject_end</td>\n|.
                     qq|</tr></table></td>\n|;
      } else {
         $temphtml = qq|<td bgcolor=$bgcolor>$subject_begin$boldon$temphtml$boldoff$subject_end</td>\n|;
      }
      $linehtml =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/;

      # SIZE, round message size and change to an appropriate unit for display
      $temphtml = lenstr($messagesize,0);
      $temphtml = qq|<td align="right" bgcolor=$bgcolor>$boldon$temphtml$boldoff</td>\n|;
      $linehtml =~ s/\@\@\@SIZE\@\@\@/$temphtml/;

      # CHECKBOX
      if ( $totalmessage==1 ) {	# make this msg selected if it is the only one
         $temphtml = checkbox(-name=>'message_ids',
                               -value=>$messageid,
                               -checked=>1,
                               -override=>'1',
                               -label=>'');
      } else {
         $temphtml = checkbox(-name=>'message_ids',
                               -value=>$messageid,
                               -override=>'1',
                               -label=>'');
      }
      $temphtml = qq|<td align="center" bgcolor=$bgcolor>$temphtml</td>\n|;
      $linehtml =~ s/\@\@\@CHECKBOX\@\@\@/$temphtml/;

      $headershtml .= qq|<tr>$linehtml</tr>\n\n|;
   }
   ow::dbm::close(\%FDB, $folderdb);
   $html =~ s/\@\@\@HEADERS\@\@\@/$headershtml/;

   my $gif;
   $temphtml=qq|<table cellpadding="0" cellspacing="0" border="0"><tr><td>|;
   if ($page > 1) {
      $gif="left.gif"; $gif="right.gif" if ($ow::lang::RTL{$prefs{'language'}});
      $temphtml .= iconlink($gif, "&lt;", qq|accesskey="U" href="$main_url_with_keyword&amp;action=listmessages&amp;page=|.($page-1).qq|"|);
   } else {
      $gif="left-grey.gif"; $gif="right-grey.gif" if ($ow::lang::RTL{$prefs{'language'}});
      $temphtml .= iconlink($gif, "-", "");
   }
   $temphtml.=qq|</td><td>$page/$totalpage</td><td>|;
   if ($page < $totalpage) {
      $gif="right.gif"; $gif="left.gif" if ($ow::lang::RTL{$prefs{'language'}});
      $temphtml .= iconlink($gif, "&gt;", qq|accesskey="D" href="$main_url_with_keyword&amp;action=listmessages&amp;page=|.($page+1) .qq|"|);
   } else {
      $gif="right-grey.gif"; $gif="left-grey.gif" if ($ow::lang::RTL{$prefs{'language'}});
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
                            -default=>'subject',
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
             qq|</td></tr></table>|;

   my @movefolders;
   foreach my $checkfolder (@validfolders) {
      push (@movefolders, $checkfolder) if ($checkfolder ne $folder);
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
      $defaultdestination= 'INBOX';
   } elsif ($folder eq 'sent-mail' || $folder eq 'saved-drafts') {
      $defaultdestination='mail-trash';
   } else {
      $defaultdestination= $prefs{'defaultdestination'} || 'mail-trash';
      $defaultdestination='mail-trash' if ( $folder eq $defaultdestination);
   }
   $htmlmove = qq|<table cellspacing="0" cellpadding="0"><tr><td>|.
               popup_menu(-name=>'destination',
                          -values=>\@movefolders,
                          -default=>$defaultdestination,
                          -labels=>\%lang_folders,
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

   # show 'you have new messages' at status line
   if ($folder ne 'INBOX' ) {
      my $msg;
      if ($now_inbox_newmessages>0) {
         $msg="$now_inbox_newmessages $lang_text{'messages'} $lang_text{'unread'}";
      } elsif ($now_inbox_allmessages>0) {
         $msg="$now_inbox_allmessages $lang_text{'messages'}";
      } else {
         $msg=$lang_text{'nomessages'};
      }
      $html.=qq|<script language="JavaScript">\n<!--\n|.
             qq|window.defaultStatus = "$lang_folders{'INBOX'} : $msg";\n|.
             qq|//-->\n</script>\n|;
   }

   # play sound if
   # a. new msg increases in INBOX
   if ( $now_inbox_newmessages>$orig_inbox_newmessages ) {
      if (-f "$config{'ow_htmldir'}/sounds/$prefs{'newmailsound'}" ) {
         $html.=qq|<embed src="$config{'ow_htmlurl'}/sounds/$prefs{'newmailsound'}" autostart="true" hidden="true">\n|;
      }
   }

   $temphtml='';
   # show quotahit del warning
   if ($quotahit_deltype) {
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
   if (defined(param('sentsubject')) && $prefs{'mailsentwindowtime'}>0) {
      my $msg=qq|<font size="-1">$lang_text{'msgsent'}</font>|;
      my $sentsubject=param('sentsubject')||'N/A';
      $msg=~s!\@\@\@SUBJECT\@\@\@!$sentsubject!;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      $temphtml.=qq|<script language="JavaScript">\n<!--\n|.
                 qq|showmsg('$prefs{"charset"}', '$lang_text{'send'}', '$msg', '$lang_text{"close"}', '_msgsent', 300, 100, $prefs{'mailsentwindowtime'});\n|.
                 qq|//-->\n</script>\n|;
   }
   # popup stat of incoming msgs
   if ( $prefs{'newmailwindowtime'}>0 &&
        ($filtered>0||$now_inbox_newmessages>$orig_inbox_newmessages) ) {
      my $msg;
      my $line=0;
      if ($now_inbox_newmessages>$orig_inbox_newmessages) {
         $msg .= qq|$lang_folders{'INBOX'} &nbsp; |.($now_inbox_newmessages-$orig_inbox_newmessages).qq|<br>|;
         $line++;
      }
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
                 qq|showmsg('$prefs{"charset"}', '$lang_text{"inmessages"}', '$msg', '$lang_text{"close"}', '_incoming', 200, |.($line*16+70).qq|, $prefs{'newmailwindowtime'});\n|.
                 qq|//-->\n</script>\n|;
   }
   $html.=readtemplate('showmsg.js').$temphtml if ($temphtml);

   # since some browsers always treat refresh directive as realtive url.
   # we use relative path for refresh
   my $refreshinterval=$prefs{'refreshinterval'}*60;
   my $relative_url="$config{'ow_cgiurl'}/openwebmail-main.pl";
   $relative_url=~s!/.*/!!g;

   httpprint([-Refresh=>"$refreshinterval;URL=$relative_url?sessionid=$thissession&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=INBOX&action=listmessages&page=1&session_noupdate=1"],
             [htmlheader(), htmlplugin($config{'header_pluginfile'}),
              $html,
              htmlplugin($config{'footer_pluginfile'}), htmlfooter(2)] );
}

# reminder for events within 7 days
sub eventreminder_html {
   my ($reminderdays)=@_;

   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'});
   my ($year, $month, $day, $hour, $min)=(ow::datetime::seconds2array($localtime))[5,4,3,2,1];
   $year+=1900; $month++;
   my $hourmin=sprintf("%02d%02d", $hour, $min);

   my $calbookfile=dotpath('calendar.book');
   my (%items, %indexes);
   if ( readcalbook($calbookfile, \%items, \%indexes, 0)<0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $calbookfile");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

   my ($easter_month, $easter_day) = ow::datetime::gregorian_easter($year); # compute once
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
      push(@indexlist, @{$indexes{$date}}) if (defined($indexes{$date}));
      push(@indexlist, @{$indexes{'*'}})   if (defined($indexes{'*'}));
      @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

      my $dayhtml="";
      for my $index (@indexlist) {
         next if ($used{$index});
         if ($date=~/$items{$index}{'idate'}/  ||
             $date2=~/$items{$index}{'idate'}/ ||
             ow::datetime::easter_match($year,$month,$day,
                                        $easter_month,$easter_day,
                                        $items{$index}{'idate'}) ) {
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
               $s=$items{$index}{'string'};
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
   if ($attr[$_STATUS] !~ /R/i) {
      ow::filelock::lock($folderfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderfile!");
      update_message_status($messageid, $attr[$_STATUS]."R", $folderdb, $folderfile);
      ow::filelock::lock("$folderfile", LOCK_UN);
   }
}
########## END MARKASREAD ########################################

########## MARKASUNREAD ##########################################
sub markasunread {
   my $messageid = param('message_id');
   return if ($messageid eq "");

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my @attr=get_message_attributes($messageid, $folderdb);
   if ($attr[$_STATUS] =~ /[RV]/i) {
      # clear flag R(read), V(verified by mailfilter)
      my $newstatus=$attr[$_STATUS];
      $newstatus=~s/[RV]//ig;

      ow::filelock::lock($folderfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderfile!");
      update_message_status($messageid, $newstatus, $folderdb, $folderfile);
      ow::filelock::lock("$folderfile", LOCK_UN);
   }
}
########## END MARKASUNREAD ######################################

########## MOVEMESSAGE ###########################################
sub movemessage {
   my $r_messageids=$_[0];

   my $destination = ow::tool::untaint(safefoldername(param('destination')));
#   if ($destination eq $folder || $destination eq 'INBOX')
   if ($destination eq $folder) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'shouldnt_move_here'}")
   }

   my $op;
   if ( defined(param('copybutton')) ) {	# copy button pressed
      return if ($destination eq 'DELETE');	# copy to DELETE is meaningless, so return
      $op='copy';
   } else {					# move button pressed
      $op=($destination eq 'DELETE')?'delete':'move';
   }
   if ($quotalimit>0 && $quotausage>$quotalimit && $op ne "delete") {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'quotahit_alert'}");
   }

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   if (! -f "$folderfile" ) {
      openwebmailerror(__FILE__, __LINE__, "$folderfile $lang_err{'doesnt_exist'}");
   }
   my ($dstfile, $dstdb)=get_folderpath_folderdb($user, $destination);
   if ($destination ne 'DELETE' && ! -f "$dstfile" ) {
      open (F,">>$dstfile") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $lang_err{'destination_folder'} $dstfile! ($!)");
      close(F);
   }

   ow::filelock::lock("$folderfile", LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderfile!");
   if ($destination ne 'DELETE') {
      ow::filelock::lock($dstfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $dstfile!");
   }

   my $counted=0;
   if ($op eq "delete") {
      $counted=operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb);
   } else {
      $counted=operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb,
							$dstfile, $dstdb);
   }
   $counted=folder_zapmessages($folderfile, $folderdb);

   ow::filelock::lock($dstfile, LOCK_UN);
   ow::filelock::lock($folderfile, LOCK_UN);

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
           $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2];
        }
      }
      writelog($msg);
      writehistory($msg);
   } elsif ($counted==-1) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'inv_msg_op'}");
   } elsif ($counted==-2) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderfile");
   } elsif ($counted==-3) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $dstfile!");
   }
   return;
}
########## END MOVEMESSAGE #######################################

########## EMPTYTRASH ############################################
sub emptytrash {
   my ($trashfile, $trashdb)=get_folderpath_folderdb($user, 'mail-trash');

   ow::filelock::lock($trashfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $trashfile!");
   my $ret=emptyfolder($trashfile, $trashdb);
   ow::filelock::lock($trashfile, LOCK_UN);

   if ($ret==-1) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $trashfile!");
   } elsif ($ret==-2) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} db $trashdb");
   }
   writelog("empty trash");
   writehistory("empty trash");
}
########## END EMPTYTRASH ########################################

########## RETRIVEPOP3/RETRPOP3S #################################
sub retrpop3 {
   my $pop3host = param('pop3host') || '';
   my $pop3port = param('pop3port') || '110';
   my $pop3user = param('pop3user') || '';
   my $pop3book = dotpath('pop3.book');
   return if (!$pop3host || !$pop3user || !-f $pop3book);

   foreach ( @{$config{'disallowed_pop3servers'}} ) {
      if ($pop3host eq $_) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'disallowed_pop3'} $pop3host");
      }
   }

   my %accounts;
   if (readpop3book($pop3book, \%accounts) <0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $pop3book!");
   }

   # don't care enable flag since this is triggered by user clicking
   my ($pop3passwd, $pop3del)
	=(split(/\@\@\@/, $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}))[3,4];

   my $response=_retrpop3($pop3host,$pop3port, $pop3user,$pop3passwd, $pop3del);
   if ($response == -1 || $response==-2) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} uidldb");
   } elsif ($response == -3) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} spoolfile");
   } elsif ($response == -11 || $response == -12) {
      openwebmailerror(__FILE__, __LINE__, "$pop3user\@$pop3host:$pop3port $lang_err{'couldnt_open'}");
   } elsif ($response == -13) {
      openwebmailerror(__FILE__, __LINE__, "$pop3user\@$pop3host:$pop3port $lang_err{'user_not_exist'}");
   } elsif ($response == -14) {
      openwebmailerror(__FILE__, __LINE__, "$pop3user\@$pop3host:$pop3port $lang_err{'pwd_incorrect'}");
   } elsif ($response == -15 || $response == -16 || $response == -17) {
      openwebmailerror(__FILE__, __LINE__, "$pop3user\@$pop3host:$pop3port $lang_err{'network_server_error'}");
   }
   return;
}

sub retrpop3s {
   return if (! -f dotpath('pop3.book'));
   if (update_pop3check()) {
      _retrauthpop3() if ($config{'auth_module'} eq 'auth_pop3.pl');
   }
   _retrpop3s(10);	# wait background fetching for no more 10 second
}

sub _retrpop3 {
   my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del)=@_;
   my ($spoolfile, $folderdb)=get_folderpath_folderdb($user, 'INBOX');

   # since pop3 fetch may be slow, the spoolfile lock is done inside routine.
   # the spoolfile is locked when each one complete msg is retrieved
   my ($ret, $errmsg)=retrpop3mail($pop3host, $pop3port,
				$pop3user, $pop3passwd, $pop3del,
				dotpath("uidl.$pop3user\@$pop3host"), $spoolfile);
   if ($ret<0) {
      writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
      writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:pop3port");
   }
   return($ret);
}

sub _retrauthpop3 {
   return 0 if (!$config{'getmail_from_pop3_authserver'});

   my $authpop3book=dotpath('authpop3.book');
   my %accounts;
   if ( -f "$authpop3book") {
      if (readpop3book($authpop3book, \%accounts)>0) {
         my $login=$user;  $login.="\@$domain" if ($config{'auth_withdomain'});
         my ($pop3passwd, $pop3del)
		=(split(/\@\@\@/, $accounts{"$config{'pop3_authserver'}:$config{'pop3_authport'}\@\@\@$login"}))[3,4];
         # don't case enable flag since noreason to stop fetch from auth server
         return _retrpop3($config{'pop3_authserver'}, $config{'pop3_authport'}, $login, $pop3passwd, $pop3del);
      } else {
         writelog("pop3 error - couldn't open $authpop3book");
         writehistory("pop3 error - couldn't open $authpop3book");
      }
   }
   return 0;
}

use vars qw($_retrpop3s_fetch_complete);
sub _retrpop3s {
   my $timeout=$_[0];
   my ($spoolfile, $folderdb)=get_folderpath_folderdb($user, 'INBOX');
   my $pop3book=dotpath('pop3.book');
   my %accounts;

   return 0 if ( ! -f "$pop3book" );
   if (readpop3book("$pop3book", \%accounts)<0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $pop3book!");
   }

   # fork a child to do fetch pop3 mails and return immediately
   if (%accounts>0) {
      local $|=1; # flush all output
      local $_retrpop3s_fetch_complete=0;	# localize for reentry safe
      local $SIG{CHLD} = sub { wait; $_retrpop3s_fetch_complete=1; };	# handle zombie

      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);

         foreach (values %accounts) {
            my ($pop3host,$pop3port, $pop3user,$pop3passwd, $pop3del, $enable)=split(/\@\@\@/,$_);
            next if (!$enable);

            my $disallowed=0;
            foreach ( @{$config{'disallowed_pop3servers'}} ) {
               if ($pop3host eq $_) {
                  $disallowed=1; last;
               }
            }
            next if ($disallowed);

            my ($ret, $errmsg) = retrpop3mail($pop3host,$pop3port,
					$pop3user,$pop3passwd, $pop3del,
					dotpath("uidl.$pop3user\@$pop3host"),
					$spoolfile);
            if ($ret<0) {
               writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
               writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
            }
         }
         openwebmail_exit(0);
      }

      for (my $i=0; $i<$timeout; $i++) {	# wait fetch to complete for $timeout seconds
         sleep 1;
         last if ($_retrpop3s_fetch_complete);
      }
   }

   return 0;
}

sub update_pop3check {
   my $now=time();
   my $pop3checkfile=dotpath('pop3.check');

   my $ftime=(stat($pop3checkfile))[9];

   if (!$ftime) {	# create if not exist
      open (F, "> $pop3checkfile") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $pop3checkfile! ($!)");
      print F "pop3check timestamp file";
      close (F);
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
   my $counted;

   ow::filelock::lock($srcfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $srcfile!");
   ow::filelock::lock($dstfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $dstfile!");

   $counted=move_oldmsg_from_folder($srcfile, $srcdb, $dstfile, $dstdb);

   ow::filelock::lock($dstfile, LOCK_UN);
   ow::filelock::lock($srcfile, LOCK_UN);

   if ($counted>0){
      my $msg="move message - move $counted old msgs from INBOX to saved-messages";
      writelog($msg);
      writehistory($msg);
   } elsif ($counted==-1) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'inv_msg_op'}");
   } elsif ($counted==-2) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $srcfile");
   } elsif ($counted==-3) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $dstfile!");
   }
}
########## END MOVEOLDMSG2SAVED ##################################

########## CLEANTRASH ############################################
sub cleantrash {
   my $days=$_[0];
   if ($days==0) {
      emptytrash(); return;
   } elsif ($days<0||$days>=999999) {
      return;
   }

   # do clean only if last clean has passed for more than 0.5 day (43200 sec)
   my $now=time();
   my $trashcheckfile=dotpath('trash.check');
   my $ftime=(stat($trashcheckfile))[9];

   if (!$ftime) {	# create if not exist
      open (TRASHCHECK, ">$trashcheckfile" ) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $trashcheckfile! ($!)");
      print TRASHCHECK "trashcheck timestamp file";
      close (TRASHCHECK);
   }
   if ( $now-$ftime > 43200 ) {	# mor than half day
      my ($trashfile, $trashdb)=get_folderpath_folderdb($user, 'mail-trash');

      ow::filelock::lock($trashfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $trashfile!");
      my $deleted=delete_message_by_age($days, $trashdb, $trashfile);
      if ($deleted >0) {
         writelog("clean trash - delete $deleted msgs from mail-trash");
         writehistory("clean trash - delete $deleted msgs from mail-trash");
      }
      ow::filelock::lock($trashfile, LOCK_UN);

      utime($now-1, $now-1, ow::tool::untaint($trashcheckfile));	# -1 is trick for nfs
   }
   return;
}
########## END CLEANTRASH ########################################

########## LOGOUT ################################################
sub logout {
   unlink "$config{'ow_sessionsdir'}/$thissession";
   writelog("logout - $thissession");
   writehistory("logout - $thissession");

   my ($html, $temphtml);
   $html = applystyle(readtemplate("logout.template"));

   my $start_url=$config{'start_url'};

   if (cookie("openwebmail-ssl")) {	# backto SSL
      $start_url="https://$ENV{'HTTP_HOST'}$start_url" if ($start_url!~s!^https?://!https://!i);
   }
   $temphtml = startform(-action=>"$start_url");
   $temphtml .= ow::tool::hiddens(logindomain=>$default_logindomain) if ($default_logindomain);
   $temphtml .= submit("$lang_text{'loginagain'}").
                "&nbsp; &nbsp;".
                button(-name=>'exit',
                       -value=>$lang_text{'exit'},
                       -onclick=>'javascript:top.window.close();',
                       -override=>'1').
                end_form();
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END LOGOUT ############################################
