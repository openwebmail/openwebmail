#!/usr/bin/suidperl -T
#
# openwebmail-main.pl - message list browing program
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
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

require "ow-shared.pl";
require "filelock.pl";
require "mime.pl";
require "iconv.pl";
require "maildb.pl";
require "pop3mail.pl";
require "mailfilter.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();
verifysession();

use vars qw($firstmessage);
use vars qw($sort);
use vars qw($searchtype $keyword $escapedkeyword);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';
$searchtype = param("searchtype") || 'subject';
$keyword = param("keyword") || '';
$escapedkeyword = escapeURL($keyword);

# extern vars
use vars qw(%lang_folders %lang_text %lang_err %lang_sortlabels
            %lang_calendar %lang_wday @wdaystr); # defined in lang/xy
use vars qw($pop3_authserver);	# defined in auth_pop3.pl
use vars qw($_STATUS);		# defined in maildb.pl

########################## MAIN ##############################

my $action = param("action");
if ($action eq "displayheaders_afterlogin") {
   cleantrash($prefs{'trashreserveddays'});
   if ( ($config{'forced_moveoldmsgfrominbox'}||$prefs{'moveoldmsgfrominbox'}) &&
        $folderusage<100) {
      moveoldmsg2saved();
   }
   update_pop3check();
   if (defined($pop3_authserver) && $config{'getmail_from_pop3_authserver'}) {
      my $login=$user; $login .= "\@$domain" if ($config{'auth_withdomain'});
      _retrpop3($pop3_authserver, $login, "$folderdir/.authpop3.book");
   }
   displayheaders();
   if ($config{'enable_pop3'} && $prefs{'autopop3'}) {
      _retrpop3s(0, "$folderdir/.pop3.book");
   }
} elsif ($action eq "userrefresh") {
   if (defined($pop3_authserver) && $config{'getmail_from_pop3_authserver'}
      && $folder eq "INBOX" ) {
      my $login=$user; $login .= "\@$domain" if ($config{'auth_withdomain'});
      _retrpop3($pop3_authserver, $login, "$folderdir/.authpop3.book");
   }
   displayheaders();
   if (update_pop3check()) {
      if ($config{'enable_pop3'} && $prefs{'autopop3'}==1 ) {
         _retrpop3s(0, "$folderdir/.pop3.book");
      }
   }

} elsif ($action eq "displayheaders") {
   my $update=0; $update=1 if (update_pop3check());
   if ($update) {
      if (defined($pop3_authserver) && $config{'getmail_from_pop3_authserver'}) {
         my $login=$user; $login .= "\@$domain" if ($config{'auth_withdomain'});
         _retrpop3($pop3_authserver, $login, "$folderdir/.authpop3.book");
      }
   }
   displayheaders();
   if ($update) {
      if ($config{'enable_pop3'} && $prefs{'autopop3'}==1 ) {
         _retrpop3s(0, "$folderdir/.pop3.book");
      }
   }
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
   # call getfolders to recalc used quota
   getfolders(\@validfolders, \$folderusage);
   displayheaders();
} elsif ($action eq "logout") {
   cleantrash($prefs{'trashreserveddays'});
   if ( ($config{'forced_moveoldmsgfrominbox'}||$prefs{'moveoldmsgfrominbox'}) &&
        $folderusage<100) {
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

   if (-f "$folderdir/.$user$config{'dbm_ext'}" && !-z "$folderdir/.$user$config{'dbm_ext'}" ) {
      filelock("$folderdir/.$user$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
      dbmopen (%HDB, "$folderdir/.$user$config{'dbmopen_ext'}", undef);	# dbm for INBOX
      $orig_inbox_newmessages=$HDB{'NEWMESSAGES'};	# new msg in INBOX
      dbmclose(%HDB);
      filelock("$folderdir/.$user$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   }

   my ($filtered, $r_filtered)=filtermessage();

   my $do_cutfolders=0;
   if ($folderusage>=100 && $config{'cutfolders_ifoverquota'}) {
      cutfolders(@validfolders);
      $do_cutfolders=1;
      getfolders(\@validfolders, \$folderusage);
   }

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
   my $refreshinterval=$prefs{'refreshinterval'}*60;
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
      $totalsize = int($totalsize/1048576*10+0.5)/10 . " MB";
   } elsif ($totalsize > 1023) {
      $totalsize =  int($totalsize/1024+0.5) . " KB";
   } else {
      $totalsize = $totalsize . " B";
   }

   my $html = readtemplate("viewfolder.template");
   my $temphtml;

   $html = applystyle($html);

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   ### we don't keep keyword, firstpage between folders,
   ### thus the keyword, firstpage will be cleared when user change folder
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
      if ( -f "$headerdb$config{'dbm_ext'}" && !-z "$headerdb$config{'dbm_ext'}" ) {
         my ($newmessages, $allmessages);

         filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
         dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

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

   if ($config{'folderquota'}) {
      if ($folderusage>=100) {
         $temphtml = " [ $lang_text{'quota_hit'} ]";
      } elsif ($folderusage>=$config{'folderusage_threshold'}) {
         $temphtml = " [ $lang_text{'usage'} $folderusage% ]";
      } else {
         $temphtml="&nbsp;";
      }
   } else {
      $temphtml="&nbsp;";
   }

   $html =~ s/\@\@\@QUOTAINFO\@\@\@/$temphtml/g;

   if ($numheaders>0) {
      $temphtml = ($firstmessage) . " - " . ($lastmessage) . " $lang_text{'of'} " .
                  $numheaders . " $lang_text{'messages'} ";
      if ($newmessages) {
         $temphtml .= "($newmessages $lang_text{'unread'})";
      }
      $temphtml .= " / $totalsize";
   } else {
      $temphtml = $lang_text{'nomessages'};
   }

   $html =~ s/\@\@\@NUMBEROFMESSAGES\@\@\@/$temphtml/g;

   $temphtml = iconlink("compose.gif", $lang_text{'composenew'}, qq|href="$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage"|). qq| \n|;
   if ($config{'folderquota'}) {
      $temphtml .= iconlink("folder.gif", "$lang_text{'folders'} ($lang_text{'usage'} $folderusage%)", qq|href="$config{'ow_cgiurl'}/openwebmail-folder.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage"|). qq| \n|;
   } else {
      $temphtml .= iconlink("folder.gif", $lang_text{'folders'}, qq|href="$config{'ow_cgiurl'}/openwebmail-folder.pl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage"|). qq| \n|;
   }
   $temphtml .= iconlink("addrbook.gif", $lang_text{'addressbook'}, qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage"|). qq| \n|.
                iconlink("filtersetup.gif", $lang_text{'filterbook'}, qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage"|). qq| \n|;
   $temphtml .= qq|&nbsp; \n|;
   if ($config{'enable_pop3'} && $folder eq "INBOX") {
      $temphtml .= iconlink("pop3.gif", $lang_text{'retr_pop3s'}, qq|href="$main_url_with_keyword&amp;action=retrpop3s"|). qq| \n|;
   }
   $temphtml .= iconlink("advsearch.gif", $lang_text{'advsearch'}, qq|href="$config{'ow_cgiurl'}/openwebmail-advsearch.pl?action=advsearch&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage"|). qq| \n|;
   $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'}, qq|href="$main_url&amp;action=userrefresh&amp;firstmessage=$firstmessage&amp;userfresh=1"|). qq| \n|;
   if ($folder eq 'mail-trash') {
      $temphtml .= iconlink("trash.gif", $lang_text{'emptytrash'}, qq|href="$main_url_with_keyword&amp;action=emptytrash&amp;firstmessage=$firstmessage" onclick="return confirm('$lang_text{emptytrash} ($trash_allmessages $lang_text{messages}) ?');"|). qq| \n|;
   } else {
      $temphtml .= iconlink("totrash.gif", $lang_text{'totrash'}, qq|href="JavaScript:document.moveform.destination.value='mail-trash'; document.moveform.submit();" onclick="return OpConfirm($lang_text{'msgmoveconf'}, $prefs{'confirmmsgmovecopy'});"|). qq| \n|;
   }
   $temphtml .= qq|&nbsp; \n|;
   if ($config{'enable_calendar'}) {
      $temphtml .= iconlink("calendar.gif", $lang_text{'calendar'}, qq|href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=calmonth&amp;sessionid=$thissession&amp;folder=$escapedfolder"|). qq| \n|;
   }
   $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage"|). qq| \n|;
   $temphtml .= iconlink("logout.gif", "$lang_text{'logout'} $prefs{'email'}", qq|href="$main_url&amp;action=logout"|). qq| \n|;

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
      $temphtml1 = iconlink("first.gif", "&lt;&lt;", qq|href="$main_url_with_keyword&amp;action=displayheaders&amp;firstmessage=1"|). qq|\n|;
   } else {
      $temphtml1 = iconlink("first-grey.gif", "&lt;&lt;", ""). qq|\n|;
   }

   if (($firstmessage - $prefs{'headersperpage'}) >= 1) {
      $temphtml1 .= iconlink("left.gif", "&lt;", qq|href="$main_url_with_keyword&amp;action=displayheaders&amp;firstmessage=|.($firstmessage-$prefs{'headersperpage'}).qq|"|) .qq|\n|;
   } else {
      $temphtml1 .= iconlink("left-grey.gif", "&lt;", ""). qq|\n|;
   }

   $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml1/g;

   if (($firstmessage + $prefs{'headersperpage'}) <= $numheaders) {
      $temphtml2 = iconlink("right.gif", "&gt;", qq|href="$main_url_with_keyword&amp;action=displayheaders&amp;firstmessage=|.($firstmessage+$prefs{'headersperpage'}) .qq|"|). qq|\n|;
   } else {
      $temphtml2 = iconlink("right-grey.gif", "&gt;", ""). qq|\n|;
   }

   if (($firstmessage + $prefs{'headersperpage'}) <= $numheaders ) {
      $temphtml2 .= iconlink("last.gif", "&gt;&gt;", qq|href="$main_url_with_keyword&amp;action=displayheaders&amp;custompage=$page_total"|). qq|\n|;
   } else {
      $temphtml2 .= iconlink("last-grey.gif", "&gt;&gt;", ""). qq|\n|;
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
   if ($folderusage>=100 ) {
      $defaultdestination='DELETE';
   } elsif ($folder eq 'mail-trash') {
      $defaultdestination= 'INBOX';
   } elsif ($folder eq 'sent-mail' || $folder eq 'saved-drafts') {
      $defaultdestination='mail-trash';
   } else {
      $defaultdestination= $prefs{'defaultdestination'} || 'mail-trash';
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


   my $sort_url="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;sort";

   $temphtml = iconlink("unread.gif", $lang_sortlabels{'status'}, qq|href="$sort_url=status"|). qq| \n|;
   $html =~ s/\@\@\@STATUS\@\@\@/$temphtml/g;

   if ($sort eq "date") {
      $temphtml = qq|<a href="$sort_url=date_rev">$lang_text{'date'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($sort eq "date_rev") {
      $temphtml = qq|<a href="$sort_url=date">$lang_text{'date'}</a> |.iconlink("down.gif", "v", "");;
   } else {
      $temphtml = qq|<a href="$sort_url=date">$lang_text{'date'}</a>|;
   }
   $html =~ s/\@\@\@DATE\@\@\@/$temphtml/g;

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
   $html =~ s/\@\@\@SENDER\@\@\@/$temphtml/g;

   if ($sort eq "subject") {
      $temphtml = qq|<a href="$sort_url=subject_rev">$lang_text{'subject'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($sort eq "subject_rev") {
      $temphtml = qq|<a href="$sort_url=subject">$lang_text{'subject'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$sort_url=subject">$lang_text{'subject'}</a>|;
   }
   $html =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/g;

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
   $html =~ s/\@\@\@SIZE\@\@\@/$temphtml/g;

   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my ($messageid, $messagedepth, $escapedmessageid);
   my ($offset, $from, $to, $dateserial, $subject, $content_type, $status, $messagesize, $references, $charset);
   my ($bgcolor, $message_status);
   my ($boldon, $boldoff); # Used to control whether text is bold for new mails

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

   $temphtml = '';
   foreach my $messnum (($firstmessage - 1) .. ($lastmessage - 1)) {

      $messageid=${$r_messageids}[$messnum];
      $messagedepth=${$r_messagedepths}[$messnum];
      next if (! defined($HDB{$messageid}) );

      $escapedmessageid = escapeURL($messageid);
      ($offset, $from, $to, $dateserial, $subject,
	$content_type, $status, $messagesize, $references, $charset)=split(/@@@/, $HDB{$messageid});

      # convert from mesage charset to current user charset
      if (is_convertable($charset, $prefs{'charset'})) {
         ($from, $to, $subject)=iconv($charset, $prefs{'charset'}, $from, $to, $subject);
      }

      # We aren't interested in the sender of SENT/DRAFT folder,
      # but the recipient, so display $to instead of $from
      if ( $folder=~ m#sent-mail#i ||
           $folder=~ m#saved-drafts#i ||
           $folder=~ m#\Q$lang_folders{'sent-mail'}\E#i ||
           $folder=~ m#\Q$lang_folders{'saved-drafts'}\E#i ) {
         my @recvlist = str2list($to,0);
         my (@namelist, @addrlist);
         foreach my $recv (@recvlist) {
            my ($n, $a)=email2nameaddr($recv);
            push(@namelist, $n);
            push(@addrlist, $a);
         }
         my ($to_name, $to_address)=(join(",", @namelist), join(",", @addrlist));
         $to_name=substr($to_name, 0, 29)."..." if (length($to_name)>32);
         my $escapedto=escapeURL($to);
         $from = qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedto" title="$to_address">$to_name </a>|;
      } else {
         my ($from_name, $from_address)=email2nameaddr($from);
         my $escapedfrom=escapeURL($from);
         $from = qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedfrom" title="$from_address">$from_name </a>|;
      }

      $subject=substr($subject, 0, 64)."..." if (length($subject)>67);
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
         $fill .=qq|&nbsp; |.iconlink("follow.up.gif", "", "").qq|&nbsp;|;
      } elsif ( $messagedepth>0 && $sort eq "subject_rev") {
         $fill .=qq|&nbsp; |.iconlink("follow.down.gif", "", "").qq|&nbsp;|;
      }

      if ($messagedepth) {
         $subject_begin = '<table cellpadding="0" cellspacing="0"><tr><td nowrap>' . $fill . "</td><td>";
         $subject_end = "</td></tr></table>";
      }

      if ( $messnum % 2 ) {
         $bgcolor = $style{"tablerow_dark"};
      } else {
         $bgcolor = $style{"tablerow_light"};
      }

      $message_status = "<B>".($messnum+1)."</B> \n";
      # Choose status icons based on Status: line and type of encoding
      $status =~ s/\s//g;	# remove blanks
      if ( $status =~ /r/i ) {
         my $icon="read.gif";
         $icon="read.a.gif" if ($status =~ m/a/i);
         $message_status .= iconlink("$icon", "$lang_text{'markasunread'} ", qq|href="$main_url_with_keyword&amp;action=markasunread&amp;message_id=$escapedmessageid&amp;status=$status&amp;firstmessage=$firstmessage"|);
         $boldon = '';
         $boldoff = '';
      } else {
         my $icon="unread.gif";
         $icon="unread.a.gif" if ($status =~ m/a/i);
         $message_status .= iconlink("$icon", "$lang_text{'markasread'} ", qq|href="$main_url_with_keyword&amp;action=markasread&amp;message_id=$escapedmessageid&amp;status=$status&amp;firstmessage=$firstmessage"|);
         $boldon = "<B>";
         $boldoff = "</B>";
      }

#      if ( ($content_type ne '') &&
#           ($content_type ne 'N/A') &&
#           ($content_type !~ /^text/i) )
      # T flag is only supported by openwebmail internally
      # see routine update_headerdb in maildb.pl for detail
      $message_status .= iconlink("attach.gif", "", "")    if ($status =~ /T/i);
      $message_status .= iconlink("important.gif", "", "") if ($status =~ /I/i);

      # Round message size and change to an appropriate unit for display
      $messagesize=lenstr($messagesize,0);

      # convert dateserial(GMT) to localtime
      my $datestr=dateserial2str(add_dateserial_timeoffset($dateserial, $prefs{'timeoffset'}), $prefs{'dateformat'});
      $temphtml .= qq|<tr>|.
         qq|<td valign="middle" width="6%" nowrap bgcolor=$bgcolor>$message_status&nbsp;</td>\n|.
         qq|<td valign="middle" width="18%" bgcolor=$bgcolor>$boldon<font size=-1>$datestr</font>$boldoff</td>\n|.
         qq|<td valign="middle" width="25%" bgcolor=$bgcolor>$boldon$from$boldoff</td>\n|.
         qq|<td valign="middle" bgcolor=$bgcolor>|.
         $subject_begin .
         qq|$boldon<a href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;|.
         qq|firstmessage=$firstmessage&amp;sessionid=$thissession&amp;|.
         qq|status=$status&amp;folder=$escapedfolder&amp;sort=$sort&amp;|.
         qq|keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;|.
         qq|headers=|.($prefs{'headers'} || 'simple').qq|&amp;|.
         qq|message_id=$escapedmessageid">\n$subject \n</a>$boldoff|.
         $subject_end .
         qq|</td>\n|.
         qq|<td valign="middle" align="right" width="5%" bgcolor=$bgcolor>$boldon$messagesize$boldoff</td>\n|.
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
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

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

   $temphtml="";
   if ($config{'enable_calendar'} && $prefs{'calendar_reminderdays'}>0) {
      $temphtml=eventreminder_html($prefs{'calendar_reminderdays'}, "$folderdir/.calendar.book");
   }
   if ($temphtml ne "") {
      $html =~ s/\@\@\@EVENTREMINDER\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@EVENTREMINDER\@\@\@/<br>/g;
   }

   print $html;

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

      print qq|<script language="JavaScript">\n<!--\n|.
            qq|window.defaultStatus = "$lang_folders{'INBOX'} : $msg";\n|.
            qq|//-->\n</script>\n|;
   }

   # play sound if
   # a. INBOX has new msg and in refresh mode
   # b. user is viewing other folder and new msg increases in INBOX
   if ( (defined(param("refresh")) && $now_inbox_newmessages>0) ||
        ($folder ne 'INBOX' && $now_inbox_newmessages>$orig_inbox_newmessages) ) {
      if (-f "$config{'ow_htmldir'}/sounds/$prefs{'newmailsound'}" ) {
         print qq|<embed src="$config{'ow_htmlurl'}/sounds/$prefs{'newmailsound'}" autostart=true hidden=true>|;
      }
   }

   my $load_showmsgjs=0;

   # show cut folder warning
   if ($do_cutfolders) {
      if (!$load_showmsgjs) {
         print qq|<script language="JavaScript" src="$config{'ow_htmlurl'}/javascript/showmsg.js"></script>\n|;
         $load_showmsgjs=1;
      }
      my $msg=qq|<font size="-1" color="#cc0000">$lang_err{'folder_cutdone'}</font>|;
      $msg=~s/\@\@\@FOLDERQUOTA\@\@\@/$config{'folderquota'}KB/;
      print qq|<script language="JavaScript">\n<!--\n|.
            qq|showmsg('$prefs{"charset"}', '$lang_text{"quota_hit"}', '$msg', '$lang_text{"close"}', '_cutfolder', 400, 100, 60);\n|.
            qq|//-->\n</script>\n|;
   }

   # popup stat of incoming msgs
   if ($prefs{'newmailwindowtime'} >0 &&
       ($filtered > 0 || ($now_inbox_newmessages>$orig_inbox_newmessages))) {
      if (!$load_showmsgjs) {
         print qq|<script language="JavaScript" src="$config{'ow_htmlurl'}/javascript/showmsg.js"></script>\n|;
         $load_showmsgjs=1;
      }
      my $msg;
      my $line=0;
      if ($now_inbox_newmessages>$orig_inbox_newmessages) {
         $msg .= qq|$lang_folders{'INBOX'} &nbsp; |.($now_inbox_newmessages-$orig_inbox_newmessages).qq|<br>|;
         $line++;
      }
      foreach my $f (qw(saved-messages sent-mail saved-drafts mail-trash DELETE)) {
         if (defined(${$r_filtered}{$f})) {
            $msg .= qq|$lang_folders{$f} &nbsp; ${$r_filtered}{$f}<br>|;
            $line++;
         }
      }
      foreach my $f (sort keys %{$r_filtered}) {
         next if ($f eq '_ALL' ||
                  $f eq 'INBOX' ||
                  $f eq 'saved-messages' ||
                  $f eq 'sent-mail' ||
                  $f eq 'saved-drafts' ||
                  $f eq 'mail-trash' ||
                  $f eq 'DELETE');
         $msg .= qq|$f &nbsp; ${$r_filtered}{$f}<br>|;
         $line++;
      }
      $msg = qq|<font size=-1>$msg</font>|;
      $msg =~ s!\\!\\\\!g; $msg =~ s!'!\\'!g;	# escape ' for javascript
      print qq|<script language="JavaScript">\n<!--\n|.
            qq|showmsg('$prefs{"charset"}', '$lang_text{"inmessages"}', '$msg', '$lang_text{"close"}', '_incoming', 160, |.($line*16+70).qq|, $prefs{'newmailwindowtime'});\n|.
            qq|//-->\n</script>\n|;
   }

   printfooter(2);
}

# reminder for events within 7 days
sub eventreminder_html {
   my ($reminderdays, $calbook)=@_;
   my $starttime=time()+timeoffset2seconds($prefs{'timeoffset'});
   my ($year, $month, $day, $hour, $min)=(gmtime($starttime))[5,4,3,2,1];
   $year+=1900; $month++;
   my $hourmin=sprintf("%02d%02d", $hour, $min);

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if ($prefs{'calendar_reminderforglobal'} && -f $config{'global_calendarbook'}) {
      if ( readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6)<0 ) {
         openwebmailerror("$lang_err{'couldnt_open'} $config{'global_calendarbook'}");
      }
   }

   my $event_count=0;
   my %used;	# tag used index so an item won't be show more than once in case it is a regexp
   my $temphtml="";
   for my $x (0..$reminderdays-1) {
      my $wdaynum;
      ($wdaynum, $year, $month, $day)=(gmtime($starttime+$x*86400))[6,5,4,3];
      $year+=1900; $month++;
      my $dow=$wdaystr[$wdaynum];
      my $date=sprintf("%04d%02d%02d", $year,$month,$day);
      my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

      my @indexlist=();
      push(@indexlist, @{$indexes{$date}}) if (defined($indexes{$date}));
      push(@indexlist, @{$indexes{'*'}})   if (defined($indexes{'*'}));
      @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

      my $dayhtml="";
      for my $index (@indexlist) {
         next if ($used{$index});
         if ($date=~/$items{$index}{'idate'}/ || $date2=~/$items{$index}{'idate'}/) {
            if ($items{$index}{'starthourmin'}>=$hourmin ||
                $items{$index}{'starthourmin'}==0 ||
                $x>0) {
               $event_count++;
               $used{$index}=1;
               last if ($event_count>5);
               my ($t, $s);

               if ($items{$index}{'starthourmin'}=~/(\d+)(\d\d)/) {
                  $t="$1:$2";
                  if ($items{$index}{'endhourmin'}=~/(\d+)(\d\d)/) {
                     $t.= "-$1:$2";
                  }
               } else {
                  $t='#';
               }
               $s=$items{$index}{'string'};
               $s=substr($s,0,20).".." if (length($s)>=21);
               $s.='*' if ($index>=1E6);
               $dayhtml.=qq|&nbsp; | if $dayhtml ne "";
               $dayhtml.=qq|<font size=-2 color=#c00000>$t </font><font size=-2 color=#000000>$s</font>|;
            }
         }
      }
      if ($dayhtml ne "") {
         my $title=dateserial2str(sprintf("%04d%02d%02d",$year,$month,$day),$prefs{'dateformat'});
         if ($lang_text{'calfmt_yearmonthdaywday'} =~ /^\s*\@\@\@WEEKDAY\@\@\@/) {
            $title="$lang_wday{$wdaynum} $title";
         } else {
            $title="$title $lang_wday{$wdaynum}";
         }
         $temphtml.=qq| &nbsp; | if ($temphtml ne"");
         $temphtml.=qq|<font size=-2>[+$x] </font>| if ($x>0);
         $temphtml.=qq|<a href="$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
                    qq|action=calday&year=$year&month=$month&day=$day" title="$title">$dayhtml</a>\n|;
      }
   }
   $temphtml .= " &nbsp; ..." if ($event_count>5);

   if ($temphtml ne "") {
      $temphtml=qq|<table width=95% border=0 cellspacing=1 cellpadding=0 align=center><tr><td align=right>|.
                qq|&nbsp;$temphtml|.
                qq|</td><tr></table>|;
   }
   return($temphtml);
}
############### END DISPLAYHEADERS ##################

################# MARKASREAD ####################
sub markasread {
   my $messageid = param("message_id");
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);

   my @attr=get_message_attributes($messageid, $headerdb);

   if ($attr[$_STATUS] !~ /R/i) {
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

   if ($attr[$_STATUS] =~ /[RV]/i) {
      # clear flag R(read), V(verified by mailfilter)
      my $newstatus=$attr[$_STATUS];
      $newstatus=~s/[RV]//ig;

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
         my $headers = param("headers") || $prefs{'headers'} || 'simple';
         my $attmode = param("attmode") || 'simple';
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

   $destination =~ s!\.\.+/!!g;
   $destination =~ s!^\s*/!!g;
   $destination =~ s/[\s\`\|\<\>;]//g;		# remove dangerous char
   ($destination =~ /^(.+)$/) && ($destination = $1);	# untaint ...

   my $op;
   if ( defined(param($lang_text{copy})) ) {	# copy button pressed
      if ($destination eq 'DELETE') {
         if (param("messageaftermove")) {
            my $headers = param("headers") || $prefs{'headers'} || 'simple';
            my $attmode = param("attmode") || 'simple';
            my $messageid = param("message_id");
            my $escapedmessageid=escapeURL($messageid);
            print "Location: $config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&firstmessage=$firstmessage&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&message_id=$escapedmessageid&headers=$headers&attmode=$attmode\n\n";
         } else {
            displayheaders();
         }
         return;	# copy to DELETE is meaningless, so return
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
      my $headers = param("headers") || $prefs{'headers'} || 'simple';
      my $attmode = param("attmode") || 'simple';
      my $messageid = param("message_id");
      my $escapedmessageid=escapeURL($messageid);
      my $escapeddestination=escapeURL($destination);
      print "Location: $config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&firstmessage=$firstmessage&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&message_id=$escapedmessageid&headers=$headers&attmode=$attmode&destination=$escapeddestination\n\n";
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
   if (update_headerdb($trashdb, $trashfile)<0) {
      openwebmailerror("$lang_err{'couldnt_updatedb'} $trashdb$config{'dbm_ext'}");
   }
   writelog("empty trash");
   writehistory("empty trash");
}
#################### END EMPTYTRASH #######################

################## RETRIVEPOP3/RETRPOP3S ###########################
use vars qw(%pop3error);
%pop3error=( -1=>"pop3book read error",
             -2=>"connect error",
             -3=>"server not ready",
             -4=>"'user' error",
             -5=>"'pass' error",
             -6=>"'stat' error",
             -7=>"'retr' error",
             -8=>"spoolfile write error",
             -9=>"pop3book write error"
           );

sub retrpop3 {
   my $pop3host = param("pop3host") || '';
   my $pop3user = param("pop3user") || '';

   if ( ! -f "$folderdir/.pop3.book" ) {
      displayheaders();
      return;
   }

   foreach ( @{$config{'disallowed_pop3servers'}} ) {
      if ($pop3host eq $_) {
         openwebmailerror("$lang_err{'disallowed_pop3'} $pop3host");
      }
   }

   _retrpop3($pop3host, $pop3user, "$folderdir/.pop3.book");

   $folder="INBOX";
   print "Location: $config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&sessionid=$thissession&sort=$sort&firstmessage=$firstmessage&folder=$escapedfolder\n\n";
   return;
}

sub _retrpop3 {
   my ($pop3host, $pop3user, $pop3book)=@_;
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
   my (%accounts, $response);

   if (readpop3book("$pop3book", \%accounts) <0) {
      openwebmailerror("$lang_err{'couldnt_open'} $pop3book!");
   }

   # since pop3 fetch may be slow, the spoolfile lock is done inside routine.
   # the spoolfile is locked when each one complete msg is retrieved
   $response = retrpop3mail($pop3host, $pop3user, "$pop3book", $spoolfile);

   if ($response< 0) {
      writelog("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
      writehistory("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
      if ($response == -1 || $response==-9) {
   	  openwebmailerror("$lang_err{'couldnt_open'} $pop3book!");
      } elsif ($response == -8) {
   	  openwebmailerror("$lang_err{'couldnt_open'} $spoolfile");
      } elsif ($response == -2 || $response == -3) {
   	  openwebmailerror("$pop3user\@$pop3host $lang_err{'couldnt_open'}");
      } elsif ($response == -4) {
    	  openwebmailerror("$pop3user\@$pop3host $lang_err{'user_not_exist'}");
      } elsif ($response == -5) {
      	  openwebmailerror("$pop3user\@$pop3host $lang_err{'pwd_incorrect'}");
      } elsif ($response == -6 || $response == -7) {
   	  openwebmailerror("$pop3user\@$pop3host $lang_err{'network_server_error'}");
      }
   }
}

sub retrpop3s {
   if ( ! -f "$folderdir/.pop3.book" ) {
      displayheaders();
      return;
   }

   if (update_pop3check()) {
      if (defined($pop3_authserver) && $config{'getmail_from_pop3_authserver'}) {
         my $login=$user; $login .= "\@$domain" if ($config{'auth_withdomain'});
         _retrpop3($pop3_authserver, $login, "$folderdir/.authpop3.book");
      }
   }
   _retrpop3s(10, "$folderdir/.pop3.book");

   displayheaders();
}

use vars qw($_retrpop3s_fetch_complete);
sub _retrpop3s {
   my ($timeout, $pop3book)=@_;
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
   my (%accounts, $response);

   return if ( ! -f "$pop3book" );

   if (readpop3book("$pop3book", \%accounts) <0) {
      openwebmailerror("$lang_err{'couldnt_open'} $pop3book!");
   }

   local $_retrpop3s_fetch_complete=0;	# localsize this var for reentry safe
   # fork a child to do fetch pop3 mails and return immediately
   if (%accounts >0) {
      $|=1; 				# flush all output
      $SIG{CHLD} = sub { wait; $_retrpop3s_fetch_complete=1; };	# handle zombie

      if ( fork() == 0 ) {		# child
         close(STDOUT);
         close(STDIN);

         foreach (values %accounts) {
            my ($pop3host, $pop3user, $enable);
            my ($response, $dummy);
            my $disallowed=0;

            ($pop3host, $pop3user, $dummy, $dummy, $dummy, $enable) = split(/\@\@\@/,$_);
            next if (!$enable);

            foreach ( @{$config{'disallowed_pop3servers'}} ) {
               if ($pop3host eq $_) {
                  $disallowed=1; last;
               }
            }
            next if ($disallowed);

            $response = retrpop3mail($pop3host, $pop3user,
         				"$pop3book",  $spoolfile);
            if ( $response<0) {
               writelog("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
               writehistory("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
            }
         }
         exit;
      }

      for (my $i=0; $i<$timeout; $i++) {	# wait fetch to complete for $timeout seconds
         sleep 1;
         last if ($_retrpop3s_fetch_complete);
      }
   }

   return;
}

sub update_pop3check {
   if ( (-M "$folderdir/.pop3.check") > $config{'fetchpop3interval'}/60/24
     || !(-e "$folderdir/.pop3.check")) {
      my $timestamp = localtime();
      open (POP3CHECK, "> $folderdir/.pop3.check") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.pop3.check!");
      print POP3CHECK $timestamp;
      close (POP3CHECK);
      return 1;
   } else {
      return 0;
   }
}
################## END RETRIVEPOP3/RETRPOP3S ###########################

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

   if ($days==0) {
      emptytrash(); return;
   } elsif ($days<0||$days>=999999) {
      return;
   }

   # do clean only if last clean has passed for more than 0.5 day
   my $m=(-M "$folderdir/.trash.check");
   return if ( $m && $m<0.5 );

   my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'mail-trash');
   filelock($trashfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $trashfile!");
   my $deleted=delete_message_by_age($days, $trashdb, $trashfile);
   if ($deleted >0) {
      writelog("cleantrash - delete $deleted msgs from mail-trash");
      writehistory("cleantrash - delete $deleted msgs from mail-trash");
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

   unlink "$config{'ow_sessionsdir'}/$thissession";
   writelog("logout - $thissession");
   writehistory("logout - $thissession");

   printheader();

   my $html=readtemplate("logout.template");
   $html = applystyle($html);

   my $start_url=$config{'start_url'};
   if (cookie("openwebmail-ssl")) {
      $start_url="https://$ENV{'HTTP_HOST'}$start_url" if ($start_url!~m!^https?://!i);
   }
   my $temphtml = startform(-action=>"$start_url") .
                  submit("$lang_text{'loginagain'}").
                  "&nbsp; &nbsp;".
                  button(-name=>"exit",
                         -value=>$lang_text{'exit'},
                         -onclick=>'javascript:top.window.close();',
                         -override=>'1').
                  end_form();
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/;

   print $html;

   printfooter(2);
}
################## END LOGOUT ######################
