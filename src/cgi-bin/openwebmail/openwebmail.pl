#!/usr/bin/perl -T
#############################################################################
# Open WebMail - Provides a web interface to user maildir spools            #
# Copyright (C) 2001 Nai-Jung Kuo, Chao-Chiu Wang, Chung-Kie Tung           #
# Copyright (C) 2000 Ernie Miller  (original GPL project: Neomail)          #
#                                                                           #
# This program is free software; you can redistribute it and/or             #
# modify it under the terms of the GNU General Public License               #
# as published by the Free Software Foundation; either version 2            #
# of the License, or (at your option) any later version.                    #
#                                                                           #
# This program is distributed in the hope that it will be useful,           #
# but WITHOUT ANY WARRANTY; without even the implied warranty of            #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             #
# GNU General Public License for more details.                              #
#                                                                           #
# You should have received a copy of the GNU General Public License         #
# along with this program; if not, write to the Free Software Foundation,   #
# Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.           #
#############################################################################

use strict;
no strict 'vars';
push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
use Fcntl qw(:DEFAULT :flock);
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);

CGI::nph();   # Treat script as a non-parsed-header script

$ENV{PATH} = ""; # no PATH should be needed
umask(0007); # make sure the openwebmail group can write

if ($> != 0) {
   my $suidperl=$^X;
   $suidperl=~s/perl/suidperl/;
   print "Content-type: text/html\n\n",
         "<br><b>$0 is not setuid to root!</b><br>",
         "<br>1. check if script is owned by root with mode 4755",
         "<br>2. use '#!$suidperl' instead of '#!$^X' in script";
   exit;
}  

require "etc/openwebmail.conf";
require "openwebmail-shared.pl";
require "mime.pl";
require "maildb.pl";
require "pop3mail.pl";
require "mailfilter.pl";


if ( ($logfile ne 'no') && (! -f $logfile)  ) {
   open (LOGFILE,">>$logfile") or openwebmailerror("$lang_err{'couldnt_open'} $logfile!");
   close(LOGFILE);
   chmod(0660, $logfile);
   chown(0, getgrnam('mail'), $logfile);
}

local $thissession;
local $user;
local $userip;
local $useremail;
local $setcookie;
local ($uid, $gid, $homedir);
local %prefs;
local %style;
local $lang;
local $numberofheaders;
local $firstmessage;
local $sort;
local $keyword;
local $escapedkeyword;
local $searchcontent=0;
local $hitquota;
local $folderdir;
local $folder;
local @validfolders;
local $printfolder;
local $escapedfolder;
local $total_size;
local $savedattsize;
local $decodedhtml;


$thissession = param("sessionid") || '';
$user = $thissession || '';
$user =~ s/\-session\-0.*$//; # Grab userid from sessionid
($user =~ /^(.+)$/) && ($user = $1);  # untaint $user...

if (defined $ENV{'HTTP_X_FORWARDED_FOR'} &&
   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^10\./ &&
   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^172\.[1-2][6-9]\./ &&
   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^192\.168\./ &&
   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^127\.0\./ ) {
   $userip=(split(/,/,$ENV{HTTP_X_FORWARDED_FOR}))[0];
} else {
   $userip=$ENV{REMOTE_ADDR};
}

$uid=0; $gid=getgrnam('mail');
if ($user) {
   if (($homedirspools eq 'yes') || ($homedirfolders eq 'yes')) {
      my $ugid;
      ($uid, $ugid, $homedir) = (getpwnam($user))[2,3,7] or
         openwebmailerror("User $user doesn't exist!");
   }

   # if no user specified, euid remains root and we redo set_euid at sub login
   set_euid_egid_umask($uid, $gid, 0077);	
}

if ( $homedirfolders eq 'yes') {
   $folderdir = "$homedir/$homedirfolderdirname";
} else {
   $folderdir = "$openwebmaildir/users/$user";
}

$sessiontimeout = $sessiontimeout/60/24; # convert to format expected by -M


%prefs = %{&readprefs};
%style = %{&readstyle};

$lang = $prefs{'language'} || $defaultlanguage;
($lang =~ /^(..)$/) && ($lang = $1);
require "etc/lang/$lang";
$lang_charset ||= 'iso-8859-1';

$hitquota = 0;
if ($user) {
   if ($prefs{"fromname"}) {
      # Create from: address for when "fromname" is defined
      $useremail = $prefs{"fromname"} . "@" . $prefs{domainname}; 
   } else {
      # Create from: address for when "fromname" is not defined
      $useremail = $thissession;
      $useremail =~ s/\-session\-0.*$/\@$prefs{domainname}/; # create from: address
   } 

   @validfolders = @{&getfolders()};
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
}
$printfolder = $lang_folders{$folder} || $folder || '';
$escapedfolder = CGI::escape($folder);

$numberofheaders = $prefs{'numberofmessages'} || $numberofheaders;

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{"sort"} || 'date';

$keyword = param("keyword") || '';
$escapedkeyword=CGI::escape($keyword);
$searchcontent = param("searchcontent") || 0;

# store the total size of current folder
$total_size = 0;

# last html read within a message,
# used to check if an attachment is linked by this html
$decodedhtml="";

########################## MAIN ##############################
if (param()) {      # an action has been chosen
   my $action = param("action");
   if ($action =~ /^(\w+)$/) {
      $action = $1;
      if ($action eq "login") {
         login();
      } elsif ($action eq "displayheaders") {
         displayheaders();
      } elsif ($action eq "readmessage") {
         readmessage();
      } elsif ($action eq "emptytrash") {
         emptytrash();
      } elsif ($action eq "viewattachment") {
         viewattachment();
      } elsif ($action eq "composemessage") {
         composemessage();
      } elsif ($action eq "sendmessage") {
         sendmessage();
      } elsif ($action eq "movemessage") {
         movemessage();
      } elsif ($action eq "downloadfolder") {
         downloadfolder();
      } elsif ($action eq "retrpop3s") {
      	 retrpop3s();
      } elsif ($action eq "retrpop3") {
     	 retrpop3();
      } elsif ($action eq "logout") {
         logout();
      } else {
         openwebmailerror("Action $lang_err{'has_illegal_chars'}");
      }
   } else {
      openwebmailerror("Action $lang_err{'has_illegal_chars'}");
   }
} else {            # no action has been taken, display login page
   printheader(),
   my $html='';
   my $temphtml;
   open (LOGIN, "$openwebmaildir/templates/$lang/login.template") or
      openwebmailerror("$lang_err{'couldnt_open'} login.template!");
   while (<LOGIN>) {
      $html .= $_;
   }
   close (LOGIN);

   $html = applystyle($html);

   $temphtml = startform(-action=>$scripturl,
                         -name=>'login');
   $temphtml .= hidden("action","login");
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;
   $temphtml = textfield(-name=>'userid',
                         -default=>'',
                         -size=>'10',
                         -override=>'1');
   $html =~ s/\@\@\@USERIDFIELD\@\@\@/$temphtml/;
   $temphtml = password_field(-name=>'password',
                              -default=>'',
                              -size=>'10',
                              -override=>'1');
   $html =~ s/\@\@\@PASSWORDFIELD\@\@\@/$temphtml/;
   $temphtml = submit("$lang_text{'login'}");
   $html =~ s/\@\@\@LOGINBUTTON\@\@\@/$temphtml/;
   $temphtml = reset("$lang_text{'clear'}");
   $html =~ s/\@\@\@CLEARBUTTON\@\@\@/$temphtml/;
   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;
   print $html;
}

###################### END MAIN ##############################

####################### LOGIN ########################
sub login {
   my $userid = param("userid") || '';
   my $password = param("password") || '';
   $userid =~ /^(.*)$/; # accept any characters for userid/pass auth info
   $userid = $1;
   $password =~ /^(.*)$/;
   $password = $1;

# Checklogin() is modularized so that it's easily replaceable with other
# auth methods.
   if ($userid eq 'root') {
      writelog("ATTEMPTED ROOT LOGIN");
      openwebmailerror ("$lang_err{'norootlogin'}");
   }

   if ( checklogin($passwdfile, $userid, $password) ) {
      my $ugid;

      $thissession = $userid . "-session-" . rand(); # name the sessionid
      $user = $userid;

      writelog("login - $thissession");
      cleanupoldsessions(); # Deletes sessionids that have expired

      $uid=0; $gid=getgrnam('mail');
      if (($homedirspools eq 'yes') || ($homedirfolders eq 'yes')) {
         ($uid, $ugid, $homedir) = (getpwnam($user))[2,3,7] or
            openwebmailerror("User $user doesn't exist!");
      }
      set_euid_egid_umask($uid, $gid, 0077);

      if ( $homedirfolders eq 'yes') {
         $folderdir = "$homedir/$homedirfolderdirname";
      } else {
         $folderdir = "$openwebmaildir/users/$user";
      }

      # create session file
      $setcookie = crypt(rand(),'NM');
      open (SESSION, "> $openwebmaildir/sessions/$thissession") or # create sessionid
         openwebmailerror("$lang_err{'couldnt_open'} $thissession!");
      print SESSION $setcookie;
      close (SESSION);

      # create folderdir if it doesn't exist
      if (! -d "$folderdir" ) {
         mkdir ("$folderdir", oct(700)) or
            openwebmailerror("$lang_err{'cant_create_dir'} $folderdir");
      }

      if ( -f "$folderdir/.openwebmailrc" ) {
         %prefs = %{&readprefs};
         %style = %{&readstyle};

         $lang = $prefs{'language'} || $defaultlanguage;
         ($lang =~ /^(..)$/) && ($lang = $1);
         require "etc/lang/$lang";
         $lang_charset ||= 'iso-8859-1'; 

         if ($prefs{"fromname"}) {
            $useremail = $prefs{"fromname"} . "@" . $prefs{domainname}; 
         } else {
            $useremail = $thissession;
            $useremail =~ s/\-session\-0.*$/\@$prefs{domainname}/; # create from: address
         } 

         @validfolders = @{&getfolders()};
         $folder = "INBOX";

         $numberofheaders = $prefs{'numberofmessages'} || $numberofheaders;

         $sort = $prefs{"sort"} || 'date';

         displayheaders();
      } else {
         firsttimeuser();
      }
   } else { # Password is INCORRECT
      my $html = '';
      writelog("invalid login attempt for username=$userid");
      printheader();
      open (INCORRECT, "$openwebmaildir/templates/$lang/passwordincorrect.template") or
         openwebmailerror("$lang_err{'couldnt_open'} passwordincorrect.template!");
      while (<INCORRECT>) {
         $html .= $_;
      }
      close (INCORRECT);

      $html = applystyle($html);
      
      print $html;
      printfooter();
      exit 0;
   }
}
#################### END LOGIN #####################

#################### LOGOUT ########################
sub logout {
   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^(.+?\-\d?\.\d+)$/) && ($thissession = $1));
   $thissession =~ s/\///g;  # just in case someone gets tricky ...
   unlink "$openwebmaildir/sessions/$thissession";

   writelog("logout - $thissession");

   print "Location: $scripturl\n\n";
}
################## END LOGOUT ######################

################ DISPLAYHEADERS #####################
sub displayheaders {
   verifysession() unless $setcookie;

   my ($orig_inbox_newmessages, $now_inbox_newmessages);
   my %HDB;
   filelock("$folderdir/.$user.$dbm_ext", LOCK_SH);
   dbmopen (%HDB, "$folderdir/.$user", undef);		# dbm for INBOX
   $orig_inbox_newmessages=$HDB{'NEWMESSAGES'};		# new msg in INBOX
   dbmclose(%HDB);
   filelock("$folderdir/.$user.$dbm_ext", LOCK_UN);

   filtermessage();

   my ($bgcolor, $status, $message_size);
   my $newmessages = 0;
   my $escapedmessageid; # Used when creating link from subject line
   my @headers = @{&getheaders()};
   my $numheaders = $#headers + 1 || 1;
   my $page_total = $numheaders/$numberofheaders || 1;
   $page_total = int($page_total) + 1 if ($page_total != int($page_total));

   if (defined(param("custompage"))) {
      my $pagenumber = param("custompage");
      $pagenumber = 1 if ($pagenumber < 1);
      $pagenumber = $page_total if ($pagenumber > $page_total);
      $firstmessage = (($pagenumber-1)*$numberofheaders) + 1;
   }

### Perform verification of $firstmessage, make sure it's within bounds
   if ($firstmessage > ($#headers + 1)) {
      $firstmessage = $#headers - ($numberofheaders - 1);
   }
   if ($firstmessage < 1) {
      $firstmessage = 1;
   }
   my $lastmessage = $firstmessage + $numberofheaders - 1;
   if ($lastmessage > ($#headers + 1)) {
       $lastmessage = ($#headers + 1);
   }

   foreach my $messnum (0 .. $#headers) {
      unless (${$headers[$messnum]}{status} =~ /r/i) {
         $newmessages++;
      }
   }

   my $base_url = "$scripturl?sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder";
   my $base_url_nokeyword = "$scripturl?sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder";

   my $refresh=param("refresh")+1;
   printheader(-Refresh=>"900;URL='$scripturl?sessionid=$thissession&sort=$sort&keyword=$escapedkeyword&searchcontent=$searchcontent&folder=INBOX&action=displayheaders&firstmessage=1&refresh=$refresh'");

   my $page_nb;
   if ($#headers > 0) {
      $page_nb = ($firstmessage) * (($#headers + 1) / $numberofheaders) / ($#headers + 1);
      ($page_nb = int($page_nb) + 1) if ($page_nb != int($page_nb));
   } else {
      $page_nb = 1;
   }

   if ($total_size > 1048575){
      $total_size = int(($total_size/1048576)+0.5) . " MB";
   } elsif ($total_size > 1023) {
      $total_size =  int(($total_size/1024)+0.5) . " KB";
   } else {
      $total_size = $total_size . " B";
   }

   my $html = '';
   my $temphtml;
   open (VIEWFOLDER, "$openwebmaildir/templates/$lang/viewfolder.template") or
      openwebmailerror("$lang_err{'couldnt_open'} viewfolder.template!");
   while (<VIEWFOLDER>) {
      $html .= $_;
   }
   close (VIEWFOLDER);

   $html = applystyle($html);

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

### we don't keep keyword between folders,
### thus the keyword will be cleared when user change folder
   $temphtml = startform(-action=>$scripturl,
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
      my ($headerdb, $newmessages, $allmessages);

      if (defined $lang_folders{$foldername}) {
         $folderlabels{$foldername}=$lang_folders{$foldername};
      } else {
         $folderlabels{$foldername}=$foldername;
      }

      if ($foldername eq 'INBOX') {
         $headerdb="$folderdir/.$user";
      } else {
         $headerdb="$folderdir/.$foldername";
      }
      filelock("$headerdb.$dbm_ext", LOCK_SH);
      dbmopen (%HDB, $headerdb, undef);
      if ($foldername eq 'INBOX') {	# don't count msg of 'DON'T DELETE THIS MAIL'
         $allmessages=$HDB{'ALLMESSAGES'}-$HDB{'INTERNALMESSAGES'};
         $newmessages=$HDB{'NEWMESSAGES'};
         $now_inbox_newmessages=$newmessages;
      } else {
         $allmessages=$HDB{'ALLMESSAGES'};
         $newmessages=$HDB{'NEWMESSAGES'};
      }
      dbmclose(%HDB);
      filelock("$headerdb.$dbm_ext", LOCK_UN);

      if ( $newmessages ne "" && $allmessages ne "" ) {
         $folderlabels{$foldername}.= " ($newmessages/$allmessages)";
      }
   }
   $temphtml = popup_menu(-name=>'folder',
                          -"values"=>\@validfolders,
                          -default=>$folder,
                          -labels=>\%folderlabels,
                          -onChange=>'JavaScript:document.FolderForm.submit();',
                          -override=>'1');
   $html =~ s/\@\@\@FOLDERPOPUP\@\@\@/$temphtml/;

   if (defined($headers[0])) {
      $temphtml = ($firstmessage) . " - " . ($lastmessage) . " $lang_text{'of'} " .
                  ($#headers + 1) . " $lang_text{'messages'} ";
      if ($newmessages) {
         $temphtml .= "($newmessages $lang_text{'unread'})";
      }
      $temphtml .= " - $total_size";
   } else {
      $temphtml = $lang_text{'nomessages'};
   }

   if ($hitquota) {
      $temphtml .= " [ $lang_text{'quota_hit'} ]";
   }

   $html =~ s/\@\@\@NUMBEROFMESSAGES\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$base_url&amp;action=composemessage&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/compose.gif\" border=\"0\" ALT=\"$lang_text{'composenew'}\"></a> ";
   $temphtml .= "<a href=\"$base_url_nokeyword&amp;action=displayheaders&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/refresh.gif\" border=\"0\" ALT=\"$lang_text{'refresh'}\"></a> ";
   $temphtml .= "<a href=\"$prefsurl?sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/prefs.gif\" border=\"0\" ALT=\"$lang_text{'userprefs'}\"></a> ";
   $temphtml .= "<a href=\"$prefsurl?action=editfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/folder.gif\" border=\"0\" ALT=\"$lang_text{'folders'}\"></a> ";
   $temphtml .= "<a href=\"$prefsurl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/addresses.gif\" border=\"0\" ALT=\"$lang_text{'addressbook'}\"></a> ";
   $temphtml .= "<a href=\"$prefsurl?action=editfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/filtersetup.gif\" border=\"0\" ALT=\"$lang_text{'filterbook'}\"></a> &nbsp; &nbsp; ";
   $temphtml .= "<a href=\"$prefsurl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/pop3setup.gif\" border=\"0\" ALT=\"$lang_text{'pop3book'}\"></a> ";
   $temphtml .= "<a href=\"$scripturl?action=retrpop3s&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$imagedir_url/pop3.gif\" border=\"0\" ALT=\"$lang_text{'retr_pop3s'}\"></a> &nbsp; &nbsp; ";

   $temphtml .= "<a href=\"$base_url&amp;action=emptytrash&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/trash.gif\" border=\"0\" ALT=\"$lang_text{'emptytrash'}\"></a> ";
   $temphtml .= "<a href=\"$base_url&amp;action=logout&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/logout.gif\" border=\"0\" ALT=\"$lang_text{'logout'} $useremail\"></a>";

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>$scripturl);
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
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');

   $html =~ s/\@\@\@STARTPAGEFORM\@\@\@/$temphtml/g;
   
   my ($temphtml1, $temphtml2);

   if ($firstmessage != 1) {
      $temphtml1 = "<a href=\"$base_url&amp;action=displayheaders&amp;firstmessage=1\">";
      $temphtml1 .= "<img src=\"$imagedir_url/first.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;&lt;\"></a>";
   } else {
      $temphtml1 = "<img src=\"$imagedir_url/first-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   if (($firstmessage - $numberofheaders) >= 1) {
      $temphtml1 .= "<a href=\"$base_url&amp;action=displayheaders&amp;firstmessage=" . ($firstmessage - $numberofheaders) . "\">";
      $temphtml1 .= "<img src=\"$imagedir_url/left.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;\"></a>";
   } else {
      $temphtml1 .= "<img src=\"$imagedir_url/left-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml1/g;

   if (($firstmessage + $numberofheaders) <= ($#headers + 1)) {
      $temphtml2 = "<a href=\"$base_url&amp;action=displayheaders&amp;firstmessage=" . ($firstmessage + $numberofheaders) . "\">";
      $temphtml2 .= "<img src=\"$imagedir_url/right.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;\"></a>";
   } else {
      $temphtml2 = "<img src=\"$imagedir_url/right-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   if (($firstmessage + $numberofheaders) <= ($#headers +1) ) {
      $temphtml2 .= "<a href=\"$base_url&amp;action=displayheaders&amp;custompage=" . "$page_total\">";
      $temphtml2 .= "<img src=\"$imagedir_url/last.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;&gt;\"></a>";
   } else {
      $temphtml2 .= "<img src=\"$imagedir_url/last-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
   }

   $html =~ s/\@\@\@RIGHTPAGECONTROL\@\@\@/$temphtml2/g;

   $temphtml = $temphtml1."&nbsp;&nbsp;"."[$lang_text{'page'} " .
                textfield(-name=>'custompage',
                          -default=>$page_nb,
                          -size=>'2',
                          -override=>'1') .
                " $lang_text{'of'} " . $page_total . ']'."&nbsp;&nbsp;".$temphtml2;

   $html =~ s/\@\@\@PAGECONTROL\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>$scripturl,
                          -name=>'moveform');
   my @movefolders;
   foreach my $checkfolder (@validfolders) {
#      unless ( ($checkfolder eq 'INBOX') || ($checkfolder eq $folder) )
      unless ( $checkfolder eq $folder ) {
         push (@movefolders, $checkfolder);
      }
   }
   # option to del message directly from folder
   push(@movefolders, 'DELETE');   

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
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');
   $html =~ s/\@\@\@STARTMOVEFORM\@\@\@/$temphtml/g;
   
   if ($folder eq 'mail-trash') {
      $temphtml = popup_menu(-name=>'destination',
                             -"values"=>\@movefolders,
                             -default=>'DELETE',
                             -labels=>\%lang_folders,
                             -override=>'1');
   } else {
      $temphtml = popup_menu(-name=>'destination',
                             -"values"=>\@movefolders,
                             -default=>'mail-trash',
                             -labels=>\%lang_folders,
                             -override=>'1');
   }

   $temphtml .= submit(-name=>"$lang_text{'move'}",
                       -onClick=>"return OpConfirm($lang_text{'moveconfirm'})");
   $temphtml .= submit(-name=>"$lang_text{'copy'}",
                       -onClick=>"return OpConfirm($lang_text{'copyconfirm'})");

   $html =~ s/\@\@\@MOVECONTROLS\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;firstmessage=".
               ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;sort=";
   $temphtml .= "status\"><IMG SRC=\"$imagedir_url/new.gif\" border=\"0\" alt=\"$lang_sortlabels{'status'}\"></a>";

   $html =~ s/\@\@\@STATUS\@\@\@/$temphtml/g;
   
   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;firstmessage=".
               ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;sort=";
   if ($sort eq "date") {
      $temphtml .= "date_rev\">$lang_text{'date'} <IMG SRC=\"$imagedir_url/up.gif\" border=\"0\" alt=\"^\"></a>";
   } elsif ($sort eq "date_rev") {
      $temphtml .= "date\">$lang_text{'date'} <IMG SRC=\"$imagedir_url/down.gif\" border=\"0\" alt=\"v\"></a>";
   } else {
      $temphtml .= "date\">$lang_text{'date'}</a>";
   }

   $html =~ s/\@\@\@DATE\@\@\@/$temphtml/g;
   
   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;firstmessage=".
                ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;sort=";

   if ( ($folder eq 'sent-mail') || ($folder eq 'saved-drafts') ) {
      if ($sort eq "sender") {
         $temphtml .= "sender_rev\">$lang_text{'recipient'} <IMG SRC=\"$imagedir_url/down.gif\" border=\"0\" alt=\"v\"></a></B></td>";
      } elsif ($sort eq "sender_rev") {
         $temphtml .= "sender\">$lang_text{'recipient'} <IMG SRC=\"$imagedir_url/up.gif\" border=\"0\" alt=\"^\"></a></B></td>";
      } else {
         $temphtml .= "sender\">$lang_text{'recipient'}</a>";
      }
   } else {
      if ($sort eq "sender") {
         $temphtml .= "sender_rev\">$lang_text{'sender'} <IMG SRC=\"$imagedir_url/down.gif\" border=\"0\" alt=\"v\"></a>";
      } elsif ($sort eq "sender_rev") {
         $temphtml .= "sender\">$lang_text{'sender'} <IMG SRC=\"$imagedir_url/up.gif\" border=\"0\" alt=\"^\"></a>";
      } else {
         $temphtml .= "sender\">$lang_text{'sender'}</a>";
      }
   }

   $html =~ s/\@\@\@SENDER\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;firstmessage=".
                ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;sort=";

   if ($sort eq "subject") {
      $temphtml .= "subject_rev\">$lang_text{'subject'} <IMG SRC=\"$imagedir_url/down.gif\" border=\"0\" alt=\"v\"></a>";
   } elsif ($sort eq "subject_rev") {
      $temphtml .= "subject\">$lang_text{'subject'} <IMG SRC=\"$imagedir_url/up.gif\" border=\"0\" alt=\"^\"></a>";
   } else {
      $temphtml .= "subject\">$lang_text{'subject'}</a>";
   }

   $html =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/g;

   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;firstmessage=".
                ($firstmessage)."&amp;sessionid=$thissession&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;sort=";

   if ($sort eq "size") {
      $temphtml .= "size_rev\">$lang_text{'size'} <IMG SRC=\"$imagedir_url/up.gif\" border=\"0\" alt=\"^\"></a>";
   } elsif ($sort eq "size_rev") {
      $temphtml .= "size\">$lang_text{'size'} <IMG SRC=\"$imagedir_url/down.gif\" border=\"0\" alt=\"v\"></a>";
   } else {
      $temphtml .= "size\">$lang_text{'size'}</a>";
   }

   $html =~ s/\@\@\@SIZE\@\@\@/$temphtml/g;

   $temphtml = '';
   my ($boldon, $boldoff); # Used to control whether text is bold for new mails
   foreach my $messnum (($firstmessage - 1) .. ($lastmessage - 1)) {
### Stop when we're out of messages!
      last if !(defined($headers[$messnum]));

      (${$headers[$messnum]}{from} =~ s/^"?(.+?)"?\s*<(.*)>$/<a href="$scripturl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$2">$1<\/a>/) ||
      (${$headers[$messnum]}{from} =~ s/<?(.*@.*)>?\s+\((.+?)\)/<a href="$scripturl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$1">$2<\/a>/) ||
      (${$headers[$messnum]}{from} =~ s/<(.+)>/<a href="$scripturl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$1">$1<\/a>/) ||
      (${$headers[$messnum]}{from} =~ s/(.+)/<a href="$scripturl\?action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$1">$1<\/a>/);

      ${$headers[$messnum]}{subject} = str2html(${$headers[$messnum]}{subject});

### Make sure there's SOMETHING clickable for subject line
      unless (${$headers[$messnum]}{subject} =~ /[^\s]/) {
         ${$headers[$messnum]}{subject} = "N/A";
      }

      $escapedmessageid = CGI::escape(${$headers[$messnum]}{message_id});

      if ( $messnum % 2 ) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }

      $message_size = ${$headers[$messnum]}{messagesize};
### Round message size and change to an appropriate unit for display
      if ($message_size > 1048575){
         $message_size = int(($message_size/1048576)+0.5) . "MB";
      } elsif ($message_size > 1023) {
         $message_size =  int(($message_size/1024)+0.5) . "KB";
      }

      $status = "<B>".($messnum+1)."</B> ";
### Choose status icons based on Status: line and type of encoding
      if ( ${$headers[$messnum]}{status} =~ /r/i ) {
         $boldon = '';
         $boldoff = '';
      } else {
         $status .= "<img src=\"$imagedir_url/new.gif\" align=\"absmiddle\">";
         $boldon = "<B>";
         $boldoff = "</B>";
      }

      if ( (${$headers[$messnum]}{content_type} ne 'N/A') && !(${$headers[$messnum]}{content_type} =~ /^text/i) ) {
         $status .= "<img src=\"$imagedir_url/attach.gif\" align=\"absmiddle\">";
      }

      $temphtml .= "<tr><td valign=\"middle\" width=\"50\" bgcolor=$bgcolor>$status&nbsp;</td>".
         "<td valign=\"middle\" width=\"150\" bgcolor=$bgcolor>$boldon<font size=-1>".
         ${$headers[$messnum]}{date}."</font>$boldoff</td>".
         "<td valign=\"middle\" width=\"150\" bgcolor=$bgcolor>$boldon".
         ${$headers[$messnum]}{from}."$boldoff</td>".
         "<td valign=\"middle\" width=\"350\" bgcolor=$bgcolor>".
         "<a href=\"$scripturl?action=readmessage&amp;firstmessage=".
         ($firstmessage)."&amp;sessionid=$thissession&amp;status=".
         ${$headers[$messnum]}{status}."&amp;folder=$escapedfolder&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;headers=".
         ($prefs{"headers"} || 'simple'). "&amp;message_id=".
         $escapedmessageid ."\">$boldon".
         ${$headers[$messnum]}{subject}."</a>$boldoff</td>".
         "<td valign=\"middle\" width=\"40\" bgcolor=$bgcolor>$boldon".
         $message_size . "$boldoff</td>".
         "<td align=\"center\" valign=\"middle\" width=\"50\" bgcolor=$bgcolor>".
         checkbox(-name=>'message_ids',
                  -value=>${$headers[$messnum]}{message_id},
                  -label=>'').
         '</td></tr>';
   }
   $html =~ s/\@\@\@HEADERS\@\@\@/$temphtml/;


   $temphtml = start_form(-action=>$scripturl);
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

   $temphtml = "<b>$lang_text{search}&nbsp;&nbsp;</b>";
   $temphtml .= textfield(-name=>'keyword',
                          -default=>$keyword,
                          -size=>'25',
                          -override=>'1');
   $temphtml .= "&nbsp;";
   $temphtml .= checkbox(-name=>'searchcontent',
                  -value=>'1',
                  -label=>$lang_text{content});


   $html =~ s/\@\@\@SEARCH\@\@\@/$temphtml/g;

   print $html;

   # play sound if 
   # a. INBOX has new msg and in refresh mode
   # b. user is viewing other folder and new msg increases in INBOX
   if ( (defined(param("refresh")) && $now_inbox_newmessages>0) ||
        ($folder ne 'INBOX' && $now_inbox_newmessages>$orig_inbox_newmessages) ) {
      if ($sound_url ne "" ) {
         # only enable sound on Windows platform
         if ( $ENV{'HTTP_USER_AGENT'} =~ /Win/ ) {
            print "<embed src=\"$sound_url\" autostart=true hidden=true>";
         }
      }
   }

   printfooter();
}
############### END DISPLAYHEADERS ##################

################# READMESSAGE ####################

sub readmessage {
   verifysession();
   printheader();
   my $messageid = param("message_id");
   my $escapedmessageid = CGI::escape($messageid);
   my %message = %{&getmessage($messageid)};
   my $headers = param("headers") || 'simple';
   my $attmode = param("attmode") || 'simple';

   if (%message) {
      my $html = '';
      my ($temphtml, $temphtml1, $temphtml2);
      open (READMESSAGE, "$openwebmaildir/templates/$lang/readmessage.template") or
         openwebmailerror("$lang_err{'couldnt_open'} readmessage.template!");
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

### these will hold web-ified headers
      my ($from, $replyto, $to, $cc, $subject, $body);
      $from = str2html($message{from} || '');
      $replyto = str2html($message{replyto} || '');
      $to = str2html($message{to} || '');
      $cc = str2html($message{cc} || '');
      $subject = str2html($message{subject} || '');

      $body = $message{"body"} || '';

      if ($message{contenttype} =~ /^text/i) {
         if ($message{encoding} =~ /^quoted-printable/i) {
            $body= decode_qp($body);
         } elsif ($message{encoding} =~ /^base64/i) {
            $body= decode_base64($body);
         }
      }
      if ($message{contenttype} =~ m#^text/html#i) { # convert into html table
         $body = html4nobase($body); 
         $body = html4mailto($body, $scripturl, "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
         $body = html2table($body); 
      } else { 					     # body must be html or text
      # remove odds space or blank lines
         $body =~ s/(\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;	
         $body =~ s/\n\s*$/\n/;
         $body = text2html($body);
      }

      my $base_url = "$scripturl?sessionid=$thissession&amp;firstmessage=" . ($firstmessage) .
                     "&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid";
      my $base_url_noid = "$scripturl?sessionid=$thissession&amp;firstmessage=" . ($firstmessage) .
                          "&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder";

##### Set up the message to go to after move.
      my $messageaftermove;
      if (defined($message{"next"})) {
         $messageaftermove = $message{"next"};
      } elsif (defined($message{"prev"})) {
         $messageaftermove = $message{"prev"};
      }

      $html =~ s/\@\@\@MESSAGETOTAL\@\@\@/$message{"total"}/g;

      $temphtml = "<a href=\"$base_url&amp;action=displayheaders\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
      $html =~ s/\@\@\@BACKTOLINK\@\@\@/$temphtml/g;

      if ($folder eq 'saved-drafts') {
         $temphtml .= "<a href=\"$base_url&amp;action=composemessage&amp;composetype=editdraft\"><IMG SRC=\"$imagedir_url/compose.gif\" border=\"0\" ALT=\"$lang_text{'editdraft'}\"></a> &nbsp; &nbsp; ";
      } elsif ($folder eq 'sent-mail') {
         $temphtml .= "<a href=\"$base_url&amp;action=composemessage&amp;composetype=editdraft\"><IMG SRC=\"$imagedir_url/compose.gif\" border=\"0\" ALT=\"$lang_text{'editdraft'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=reply\"><IMG SRC=\"$imagedir_url/reply.gif\" border=\"0\" ALT=\"$lang_text{'reply'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=replyall\"><IMG SRC=\"$imagedir_url/replyall.gif\" border=\"0\" ALT=\"$lang_text{'replyall'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=forward\"><IMG SRC=\"$imagedir_url/forward.gif\" border=\"0\" ALT=\"$lang_text{'forward'}\"></a> &nbsp; &nbsp; ";
      } else {
         $temphtml .= "<a href=\"$base_url&amp;action=composemessage&amp;composetype=reply\"><IMG SRC=\"$imagedir_url/reply.gif\" border=\"0\" ALT=\"$lang_text{'reply'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=replyall\"><IMG SRC=\"$imagedir_url/replyall.gif\" border=\"0\" ALT=\"$lang_text{'replyall'}\"></a> " .
         "<a href=\"$base_url&amp;action=composemessage&amp;composetype=forward\"><IMG SRC=\"$imagedir_url/forward.gif\" border=\"0\" ALT=\"$lang_text{'forward'}\"></a> &nbsp; &nbsp; ";
      }
      $temphtml .= "<a href=\"$base_url&amp;action=logout\"><IMG SRC=\"$imagedir_url/logout.gif\" border=\"0\" ALT=\"$lang_text{'logout'} $useremail\"></a>";
   
      $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

      if (defined($message{"prev"})) {
         $temphtml1 = "<a href=\"$base_url_noid&amp;action=readmessage&amp;message_id=$message{'prev'}&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$imagedir_url/left.gif\" align=\"absmiddle\" border=\"0\" alt=\"&lt;&lt;\"></a>";
      } else {
         $temphtml1 = "<img src=\"$imagedir_url/left-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
      }
      $html =~ s/\@\@\@LEFTMESSAGECONTROL\@\@\@/$temphtml1/g;

      if (defined($message{"next"})) {
         $temphtml2 = "<a href=\"$base_url_noid&amp;action=readmessage&amp;message_id=$message{'next'}&amp;headers=$headers&amp;attmode=$attmode\"><img src=\"$imagedir_url/right.gif\" align=\"absmiddle\" border=\"0\" alt=\"&gt;&gt;\"></a>";
      } else {
         $temphtml2 = "<img src=\"$imagedir_url/right-grey.gif\" align=\"absmiddle\" border=\"0\" alt=\"\">";
      }
      $html =~ s/\@\@\@RIGHTMESSAGECONTROL\@\@\@/$temphtml2/g;

      $temphtml = $temphtml1 . "  " . $message{"number"} . "  " . $temphtml2;
      $html =~ s/\@\@\@MESSAGECONTROL\@\@\@/$temphtml/g;

      $temphtml = start_form(-action=>$scripturl,
                             -name=>'moveform');
      my @movefolders;
      foreach my $checkfolder (@validfolders) {
#         unless ( ($checkfolder eq 'INBOX') || ($checkfolder eq $folder) ) 
         unless ($checkfolder eq $folder) {
            push (@movefolders, $checkfolder);
         }
      }
      # add option to delete message from folder directly
      push(@movefolders, 'DELETE');

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
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_ids',
                          -default=>$messageid,
                          -override=>'1');
      if ($messageaftermove) {
         $temphtml .= hidden(-name=>'messageaftermove',
                             -default=>'1',
                             -override=>'1');
         $temphtml .= hidden(-name=>'message_id',
                             -default=>$messageaftermove,
                             -override=>'1');
      }
      $html =~ s/\@\@\@STARTMOVEFORM\@\@\@/$temphtml/g;
   
      if ($folder eq 'mail-trash') {
         $temphtml = popup_menu(-name=>'destination',
                                -"values"=>\@movefolders,
                                -labels=>\%lang_folders,
                                -default=>'DELETE',
                                -override=>'1');
      } else {
         $temphtml = popup_menu(-name=>'destination',
                                -"values"=>\@movefolders,
                                -labels=>\%lang_folders,
                                -default=>'mail-trash',
                                -override=>'1');
      }
      $temphtml .= submit(-name=>"$lang_text{'move'}",
                       -onClick=>"return confirm($lang_text{'moveconfirm'})");
      $temphtml .= submit(-name=>"$lang_text{'copy'}",
                       -onClick=>"return confirm($lang_text{'copyconfirm'})");

      $html =~ s/\@\@\@MOVECONTROLS\@\@\@/$temphtml/g;

      if ($headers eq "all") {
         $message{"header"} = decode_mimewords($message{"header"});
         $message{"header"} = text2html($message{"header"});
         $message{"header"} =~ s/\n([-\w]+?:)/\n<B>$1<\/B>/g;
         $temphtml = $message{"header"};
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
         $realname=CGI::escape($realname);
         $escapedemail=CGI::escape($email);
         $temphtml .= "&nbsp;<a href=\"$prefsurl?action=addaddress&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;realname=$realname&amp;email=$escapedemail\">".
                      "<IMG SRC=\"$imagedir_url/imports.gif\" border=\"0\" ALT=\"$lang_text{'importadd'} $email\">".
                      "</a>";

         if ($message{smtprelay} !~ /^\s*$/) {
            $temphtml .= "&nbsp;<a href=\"$prefsurl?action=addfilter&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;priority=20&amp;rules=smtprelay&amp;include=include&amp;text=$message{smtprelay}&amp;destination=mail-trash&amp;enable=1\">".
                      "<IMG SRC=\"$imagedir_url/blockrelay.gif\" border=\"0\" ALT=\"$lang_text{'blockrelay'} $message{smtprelay}\">".
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
							/\.(jpg|jpeg|gif|png)$/i) {
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
                  if ( ${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\.msg/ ) {
                     my ($header, $body)=
			split(/\n\r*\n/, ${${$message{attachment}[$attnumber]}{r_content}}, 2);
                     $header=simpleheader($header);
                     #set bgcolor for message/rfc822 header
                     $header=~s/#dddddd/$style{"window_dark"}/ig;	
                     ${${$message{attachment}[$attnumber]}{r_content}}=$header."\n\n".$body;
                  }
                  $temphtml .= html_att2table($message{attachment}, $attnumber, $escapedmessageid);
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
               }
            } elsif ( ${$message{attachment}[$attnumber]}{contenttype}=~ /^text/i ) {
               if ( ${$message{attachment}[$attnumber]}{filename}=~ /^Unknown\./ ) {
                  $temphtml .= text_att2table($message{attachment}, $attnumber);
               } else {
                  $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
               }
            } elsif ( ${$message{attachment}[$attnumber]}{filename}=~ /\.(jpg|jpeg|gif|png)$/i) {
               # show image only if it is not linked
               if ( ($decodedhtml !~ /\Q${$message{attachment}[$attnumber]}{id}\E/) &&
                    ($decodedhtml !~ /\Q${$message{attachment}[$attnumber]}{location}\E/) ) {
                  # ugly match for strange CID link
                  my $filename=CGI::escape(${$message{attachment}[$attnumber]}{filename});
                  if ($filename ne '' && $decodedhtml!~ m#CID:\{[\d\w\-]+\}/$filename#) {
                     $temphtml .= image_att2table($message{attachment}, $attnumber, $escapedmessageid);
                  }
               }
            } else {
               $temphtml .= misc_att2table($message{attachment}, $attnumber, $escapedmessageid);
            }

         }
      }

      # enable download the whole message block in attmode==all
      if ( $attmode eq 'all' ) {
         $temphtml .= qq|<table width="100%" border="0" align="center" cellpadding="2"><tr><td align=right>|.
                      qq|<a href="$scripturl/Unknown.msg?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=all">$lang_text{'download'}</a>|.
                      qq|</td></tr></table>|;
      }

      $html =~ s/\@\@\@BODY\@\@\@/$temphtml/g;
      print $html;

   } else {
      $messageid = str2html($messageid);
      print "What the heck? Message $messageid seems to be gone!";
   }
   printfooter();

### fork a child to do the status update and headerdb update
   unless ($message{status} =~ /r/i) {
      $|=1; 				# flush all output
      $SIG{CHLD} = sub { wait };	# handle zombie
      if ( fork() == 0 ) {		# child
         close(STDOUT);
         close(STDIN);
         updatestatus($messageid,"R");
         exit;
      }
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

   $decodedhtml = $temphtml;	# store decoded html in global, used by others 

   $temphtml = html4nobase($temphtml);
   $temphtml = html4attachments($temphtml, $r_attachments, $scripturl, "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
   $temphtml = html4mailto($temphtml, $scripturl, "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
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

sub image_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $escapedfilename = CGI::escape(${$r_attachment}{filename});
   my $attlen=lenstr(${$r_attachment}{contentlength});
   my $nodeid=${$r_attachment}{nodeid};
   my $disposition=${$r_attachment}{disposition};
   $disposition=~s/^(.).*$/$1/;

   my $temphtml .= qq|<table border="0" align="center" cellpadding="2">|.
                   qq|<tr><td valign="middle" bgcolor=$style{"attachment_dark"} align="center">|.
                   qq|$lang_text{'attachment'} $attnumber: ${$r_attachment}{filename} &nbsp;($attlen)&nbsp;&nbsp;<font color=$style{"attachment_dark"}  size=-2>$nodeid $disposition</font>|.
                   qq|</td></tr><td valign="middle" bgcolor=$style{"attachment_light"} align="center">|.
                   qq|<IMG BORDER="0" SRC="$scripturl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid">|.
                   qq|</td></tr></table>|;
   return($temphtml);
}

sub misc_att2table {
   my ($r_attachments, $attnumber, $escapedmessageid)=@_;

   my $r_attachment=${$r_attachments}[$attnumber];
   my $escapedfilename = CGI::escape(${$r_attachment}{filename});
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
                   qq|<a href="$scripturl/$escapedfilename?action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder&amp;attachment_nodeid=$nodeid">$lang_text{'download'}</a>|.
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

############### COMPOSEMESSAGE ###################
# 6 composetype: continue(used after adding attachment), 
#                reply, replyall, forward, editdraft or none(newmail)
sub composemessage {
   no strict 'refs';
   verifysession();
   my $html = '';
   my $temphtml;
   my @attlist;
   open (COMPOSEMESSAGE, "$openwebmaildir/templates/$lang/composemessage.template") or
      openwebmailerror("$lang_err{'couldnt_open'} composemessage.template!");
   while (<COMPOSEMESSAGE>) {
      $html .= $_;
   }
   close (COMPOSEMESSAGE);

   $html = applystyle($html);
   
   if (defined(param($lang_text{'add'}))) {
      @attlist = @{&getattlist()};
      my $attachment = param("attachment");
      my $attname = $attachment;
      my $attcontents = '';

      if ($attachment) {
         if ( ($attlimit) && ( ( $savedattsize + (-s $attachment) ) > ($attlimit * 1048576) ) ) {
            openwebmailerror ("$lang_err{'att_overlimit'} $attlimit MB!");
         }
         my $content_type;
### Convert :: back to the ' like it should be.
         $attname =~ s/::/'/g;
### Trim the path info from the filename
         $attname =~ s/^.*\\//;
         $attname =~ s/^.*\///;
         $attname =~ s/^.*://;

         if (defined(uploadInfo($attachment))) {
            $content_type = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
         } else {
            $content_type = 'application/octet-stream';
         }
         my $attnum = ($#attlist +1) || 0;
         open (ATTFILE, ">$openwebmaildir/sessions/$thissession-att$attnum");
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
         push (@attlist, $attname);
      }
   } elsif ( !(defined(param($lang_text{'add'}))) ) {
      deleteattachments();
   }

   my $messageid = param("message_id");
   my %message;
   my $attnumber;
   my $from = $useremail;
   if ($prefs{"realname"}) {
      my $realname = $prefs{"realname"};
      $from =~ s/^(.+)$/$realname <$1>/;
   }
   my $escapedfrom = str2html($from);
   my $to = '';
   my $cc = '';
   my $bcc = '';
   my $subject = '';
   my $body = '';
   my $composetype = param("composetype");

   if ($composetype) {
      $to = param("to") || '';
      $cc = param("cc") || '';
      $bcc = param("bcc") || '';
      $subject = param("subject") || '';
      $body = param("body") || '';

      if ($composetype eq "reply" || $composetype eq "replyall" ||
          $composetype eq "forward" || $composetype eq "editdraft" ) {

         if ($composetype eq "forward" || $composetype eq "editdraft") {
            %message = %{&getmessage($messageid, "all")};
         } else {
            %message = %{&getmessage($messageid, "")};
         }

         $body = $message{"body"} || '';
         ### Handle mail programs that send the body encoded
         if ($message{contenttype} =~ /^text/i) {
            if ($message{encoding} =~ /^quoted-printable/i) {
               $body= decode_qp($body);
            } elsif ($message{encoding} =~ /^base64/i) {
               $body= decode_base64($body);
            }
         }
         ### convert to pure text since user is going to edit it
         if ($message{contenttype} =~ /^text\/html/i) {
            $body= html2txt($body);
         }

         ### If the first attachment is text, assume it's the body of a message
         ### in multi-part format
         if (($message{contenttype} =~ /^multipart/i) &&
            (defined(${$message{attachment}[0]}{contenttype})) &&
            (${$message{attachment}[0]}{contenttype} =~ /^text\/plain/i)) {
            if (${$message{attachment}[0]}{encoding} =~ /^quoted-printable/i) {
               ${${$message{attachment}[0]}{r_content}} =
               		decode_qp(${${$message{attachment}[0]}{r_content}});
            } elsif (${$message{attachment}[$attnumber]}{encoding} =~ /^base64/i) {
               ${${$message{attachment}[$attnumber]}{r_content}} = 
			decode_base64(${${$message{attachment}[$attnumber]}{r_content}});
            }
            $body = ${${$message{attachment}[0]}{r_content}};

            # remove text and html of attachemnts that the body now represents
#           if ( defined(%{$message{attachment}[1]}) &&
#                (${$message{attachment}[1]}{boundary} eq 
#	 	 ${$message{attachment}[0]}{boundary}) ) {

#              # 1st(text) and 2nd(html) attachments in the same alternative group
#              if ( (${$message{attachment}[0]}{subtype} =~ /alternative/i) &&
#                (${$message{attachment}[1]}{subtype} =~ /alternative/i) &&
#                (${$message{attachment}[1]}{contenttype} =~ /^text/i) ) {
#
#                 # keep html version, clear body and remove text version
#                 ${$message{attachment}[1]}{filename}="Forward.html";
#                 $body=" ";
#                 shift @{$message{attachment}};
#
#              # 1st=unknow.txt and 2nd=unknow.html
#              } elsif ( (${$message{attachment}[0]}{contenttype}=~ /^text\/plain/i ) &&
#                   (${$message{attachment}[0]}{filename}=~ /^Unknown\./ ) &&
#                   (${$message{attachment}[1]}{contenttype} =~ /^text\/html/i)  &&
#                   (${$message{attachment}[1]}{filename}=~ /^Unknown\./ ) ) {
#
#                 # keep html version, clear body and remove text version
#                 ${$message{attachment}[1]}{filename}=~ s/^Unknow\./Forward\./;
#                 $body=" ";
#                 shift @{$message{attachment}};
#
#              # remove 1st(text) attachment only
#              } else {
#                 shift @{$message{attachment}};
#              }

#           } else {
               shift @{$message{attachment}};
#           }
         }

# Handle the messages generated if sendmail is set up to send MIME error reports
         if ($message{contenttype} =~ /^multipart\/report/i) {
            foreach my $attnumber (0 .. $#{$message{attachment}}) {
               if (defined(${${$message{attachment}[$attnumber]}{r_content}})) {
                  $body .= ${${$message{attachment}[$attnumber]}{r_content}};
                  shift @{$message{attachment}};
               }
            }
         }
      }

# remove odds space or blank lines
      $body =~ s/(\r?\n){2,}/\n\n/g;
      $body =~ s/^\s+//;	
      $body =~ s/\s+$//;

      if (($composetype eq "reply") || ($composetype eq "replyall")) {
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
         }

         $body =~ s/\n/\n\> /g;
         $body = "> " . $body . "\n\n";
      }

      if ($composetype eq "forward" || $composetype eq "editdraft") {
         if (defined(${$message{attachment}[0]}{header})) {
            foreach my $attnumber (0 .. $#{$message{attachment}}) {
	       ($attnumber =~ /^(.+)$/) && ($attnumber = $1);   # bypass taint check
               open (ATTFILE, ">$openwebmaildir/sessions/$thissession-att$attnumber");
               print ATTFILE ${$message{attachment}[$attnumber]}{header}, "\n\n", ${${$message{attachment}[$attnumber]}{r_content}};
               close ATTFILE;
            }
            @attlist = @{&getattlist()};
         }
         $subject = $message{"subject"} || '';

         if ($composetype eq "editdraft") {
            $to = $message{"to"} if (defined($message{"to"}));
            $cc = $message{"cc"} if (defined($message{"cc"}));
            $bcc = $message{"bcc"} if (defined($message{"bcc"}));
         } elsif ($composetype eq "forward") {
            $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);
            $body = "\n\n------------- Forwarded message follows -------------\n$body";
         }
      }

   }
   if ( (defined($prefs{"signature"})) && 
        ($composetype ne 'continue') &&
        ($composetype ne 'editdraft') ) {
      $body .= "\n\n".$prefs{"signature"};
   }
   printheader();
   
   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;firstmessage=$firstmessage\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";
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
   $temphtml .= hidden(-name=>'firstmessage',
                       -default=>$firstmessage,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');
   if (param("message_id")) {
      $temphtml .= hidden(-name=>'message_id',
                          -default=>param("message_id"),
                          -override=>'1');
   }
   $html =~ s/\@\@\@STARTCOMPOSEFORM\@\@\@/$temphtml/g;

   $html =~ s/\@\@\@ESCAPEDFROM\@\@\@/$escapedfrom/g;

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
                         -default=>$prefs{"replyto"} || '',
                         -size=>'70',
                         -override=>'1');
   $html =~ s/\@\@\@REPLYTOFIELD\@\@\@/$temphtml/g;
   
   $temphtml = '';
   foreach my $filename (@attlist) {
      $temphtml .= "$filename<BR>";
   }
   if ( $savedattsize ) {
      $temphtml .= "<em>" . int($savedattsize/1024) . "KB";
      if ( $attlimit ) {
         $temphtml .= " $lang_text{'of'} $attlimit MB";
      }
      $temphtml .= "</em><BR>";
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

   $html =~ s/\@\@\@CONFIRMREADINGFIELD\@\@\@/$temphtml/;

   $temphtml = textarea(-name=>'body',
                        -default=>$body,
                        -rows=>'20',
                        -columns=>'78',
                        -wrap=>'hard',
                        -override=>'1');
   $html =~ s/\@\@\@BODYAREA\@\@\@/$temphtml/g;

   $temphtml = submit("$lang_text{'send'}");
   $html =~ s/\@\@\@SENDBUTTON\@\@\@/$temphtml/g;

   $temphtml = submit("$lang_text{'savedraft'}");
   $html =~ s/\@\@\@SAVEDRAFTBUTTON\@\@\@/$temphtml/g;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>$scripturl);
   
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

   verifysession();

   if (defined(param($lang_text{'add'}))) {
      composemessage();
   } else {
### Add a header that will allow sent-mail/saved-drafts folder to function correctly
      my $localtime = scalar(localtime);
      my $date = localtime();
      my @datearray = split(/ +/, $date);
      $date = "$datearray[0], $datearray[2] $datearray[1] $datearray[4] $datearray[3] $timeoffset";

      my $from = $useremail;
      my $realname = $prefs{"realname"} || '';
      $from =~ s/[\||'|"|`]/ /g;  # Get rid of shell escape attempts
      $realname =~ s/[\||'|"|`]/ /g;  # Get rid of shell escape attempts
      ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
      ($from =~ /^(.+)$/) && ($from = $1);

      my $boundary = "----=OPENWEBMAIL_ATT_" . rand();
      my $to = param("to");
      my $cc = param("cc");
      my $bcc = param("bcc");
      my $subject = param("subject");
      my $confirmreading = param("confirmreading");
      my $body = param("body");
      $body =~ s/\r//g;  # strip ^M characters from message. How annoying!

      my $attachment = param("attachment");
      if ( $attachment ) {
         getattlist();
         if ( ($attlimit) && ( ( $savedattsize + (-s $attachment) ) > ($attlimit * 1048576) ) ) {
            openwebmailerror ("$lang_err{'att_overlimit'} $attlimit MB!");
         }
      }
      my $attname = $attachment;
      ### Convert :: back to the ' like it should be.
      $attname =~ s/::/'/g;
      ### Trim the path info from the filename
      $attname =~ s/^.*\\//;
      $attname =~ s/^.*\///;
      $attname =~ s/^.*://;

      my @attfilelist=();
      opendir (SESSIONSDIR, "$openwebmaildir/sessions") or
         openwebmailerror("$lang_err{'couldnt_open'} $openwebmaildir/sessions!");
      while (defined(my $currentfile = readdir(SESSIONSDIR))) {
         if ($currentfile =~ /^($thissession-att\d+)$/) {
            push (@attfilelist, "$openwebmaildir/sessions/$1");
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
         open (SENDMAIL, "|" . $sendmail . " -oem -oi -F '$realname' -f '$from' -t 1>&2") or
            openwebmailerror("$lang_err{'couldnt_open'} $sendmail!");
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

      if  ($hitquota) {
         $do_savefolder=0;
      } else {
         if (filelock($savefile, LOCK_EX|LOCK_NB)) {
            update_headerdb($savedb, $savefile);

            if ( $savefolder eq 'saved-drafts' && defined(param("message_id")) ) {
               my $alreadyexist=0;
               my $messageid=param("message_id");
               my %HDB;

               filelock("$savedb.$dbm_ext", LOCK_EX);
               dbmopen(%HDB, $savedb, 0600);
               if (defined($HDB{$messageid})) {
                  $alreadyexist=1;
               }
               dbmclose(%HDB);
               filelock("$savedb.$dbm_ext", LOCK_UN);

               if ($alreadyexist) {
                  my @a;
                  push (@a, $messageid);
                  op_message_with_ids("delete", \@a, $savefile, $savedb);
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

      print FOLDER "From $user $localtime\n" if ($do_savefolder);

      my $tempcontent="";
      $tempcontent .= "From: $realname <$from>\n";
      $tempcontent .= "To: $to\n";
      $tempcontent .= "CC: $cc\n" if ($cc);
      $tempcontent .= "Bcc: $bcc\n" if ($bcc);
      $tempcontent .= "Reply-To: ".$prefs{"replyto"}."\n" if ($prefs{"replyto"}); 
      $tempcontent .= "Subject: $subject\n";
      $tempcontent .= "X-Mailer: Open WebMail $version\n";
      $tempcontent .= "X-OriginatingIP: $userip ($user)\n";
      if ($confirmreading) {
         if ($prefs{"replyto"}) {
            $tempcontent .= "X-Confirm-Reading-To: $prefs{'replyto'}\n";
            $tempcontent .= "Disposition-Notification-To: $prefs{'replyto'}\n";
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

      my $contenttype="";
      if ($attachment || $#attfilelist>=0 ) {
         my $buff='';

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
            my $content_type;
            if (defined(uploadInfo($attachment))) {
               $content_type = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
            } else {
               $content_type = 'application/octet-stream';
            }
            $tempcontent ="";
            $tempcontent .= "--$boundary\nContent-Type: $content_type;\n";
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
      
      if ($do_savefolder) {
         my @attr;
         my @datearray = split(/\s+/, $date);
         if ($datearray[0] =~ /[A-Za-z,]/) {
            shift @datearray; # Get rid of the day of the week
         }

         $attr[$_OFFSET]=$messagestart;
         $attr[$_TO]=$to;
         $attr[$_FROM]=(split(/,/, $to))[0];	# since this is sent folder
         ### we store localtime on dbm, so day offset is not needed
         $attr[$_DATE]="$month{$datearray[1]}/$datearray[0]/$datearray[2] $datearray[3]";
         $attr[$_SUBJECT]=$subject;
         $attr[$_CONTENT_TYPE]=$contenttype;
         $attr[$_STATUS]="R";
         $attr[$_SIZE]=$messagesize;

         my %HDB;
         filelock("$savedb.$dbm_ext", LOCK_EX);
         dbmopen(%HDB, $savedb, 0600);
         $HDB{$messageid}=join('@@@', @attr);
         $HDB{'ALLMESSAGES'}++;
         $HDB{'METAINFO'}=metainfo($savefile);
         dbmclose(%HDB);
         filelock("$savedb.$dbm_ext", LOCK_UN);

         filelock($savefile, LOCK_UN);
      }

      if ($sendmail_errorstr) {
         openwebmailerror($sendmail_errorstr);
      } elsif ($savefolder_errorstr) {
         openwebmailerror($savefolder_errorstr);
      } else {	
#         if ( defined(param("message_id")) ) {
#            readmessage();
#         } else {
            displayheaders();
#         }
      }
   }
}

############## END SENDMESSAGE ###################

################ VIEWATTACHMENT ##################
sub viewattachment {
   verifysession();
   my $messageid = param("message_id");
   my $nodeid = param("attachment_nodeid");
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();

   unless(filelock($folderfile, LOCK_SH|LOCK_NB)) {
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   }
   update_headerdb($headerdb, $folderfile);
   open($folderhandle, "$folderfile");
   my $r_block= get_message_block($messageid, $headerdb, $folderhandle);
   close($folderhandle);
   filelock($folderfile, LOCK_UN);

   if ( ! defined(${$r_block}) ) {
      printheader();
      $messageid = str2html($messageid);
      print "What the heck? Message $messageid seems to be gone!";
      printfooter();
      return;
   }

   if ( $nodeid eq 'all' ) {
      # return whole msg as an message/rfc822 object
      my $length = length(${$r_block});
      print qq|Content-Length: $length\n|,
            qq|Content-Transfer-Coding: binary\n|,
            qq|Connection: close\n|,
            qq|Content-Type: message/rfc822; name="Unknown.msg"\n|,
            qq|Content-Disposition: attachment; filename="Unknown.msg"\n|,
            qq|\n|, ${$r_block};

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
            my $escapedmessageid = CGI::escape($messageid);
            $content = html4nobase($content);
            $content = html4attachments($content, $r_attachments, $scripturl, "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
            $content = html4mailto($content, $scripturl, "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
         }

         my $length = length($content);
         print qq|Content-Length: $length\n|,
               qq|Content-Transfer-Coding: binary\n|,
               qq|Connection: close\n|,
               qq|Content-Type: ${$r_attachment}{contenttype}; name="${$r_attachment}{filename}"\n|;
         unless (${$r_attachment}{contenttype} =~ /^text/i) {
            print qq|Content-Disposition: attachment; filename="${$r_attachment}{filename}"\n|;
         }
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

################## GETHEADERS #######################
sub getheaders {
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();
   my @message = ();
   my @messageids;
   my $messageid;

   unless ( filelock($folderfile, LOCK_SH|LOCK_NB) ) {
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   }

   update_headerdb($headerdb, $folderfile);

   if ( $keyword ne '' ) {
      open($folderhandle, "$folderfile");
      my %haskeyword=search_messages_for_keyword($keyword, $searchcontent, $headerdb, $folderhandle, "$folderdir/.search.cache");
      close($folderhandle);
      foreach ( get_messageids_sorted($headerdb, $sort, "$headerdb.cache") ) {
         push (@messageids, $_) if ( $haskeyword{$_} == 1 ); 
      }
   } else {
      @messageids=get_messageids_sorted($headerdb, $sort, "$headerdb.cache");
   }

   filelock($folderfile, LOCK_UN);

   $messagenumber=-1;
   $total_size=0;

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen (%HDB, $headerdb, undef);

   foreach $messageid (@messageids) {
### Get a unique memory address before creating pointer
      my %header;
            
      $header{'message_id'}=$messageid;
      ( $header{'offset'},
	$header{'from'}, $header{'to'}, $header{'date'}, $header{'subject'},
	$header{'content_type'}, $header{'status'}, 
	$header{'messagesize'} )=split(/@@@/, $HDB{$messageid});

      # don't show the imap control message in INBOX to user
      if ( ($folder eq "INBOX") && ($header{'subject'} =~ /DON'T DELETE THIS MESSAGE/) ) {
         undef(%header);
         next;
      }

      $total_size+=$header{'messagesize'};
      $messagenumber++;
      $message[$messagenumber] = \%header;
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   return \@message;
}

#################### END GETHEADERS #######################

#################### GETMESSAGE ###########################
sub getmessage {
   my ($messageid, $mode) = @_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();
   my @messageids;
   my %message = ();

   my ($currentheader, $currentbody, $r_currentattachments, $currentfrom, $currentdate,
       $currentsubject, $currentid, $currenttype, $currentto, $currentcc,
       $currentreplyto, $currentencoding, $currentstatus, $currentreceived);

   unless(filelock($folderfile, LOCK_SH|LOCK_NB)) {
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   }
   update_headerdb($headerdb, $folderfile);
   open($folderhandle, "$folderfile");

   if ( $keyword ne '' ) {
      my %haskeyword=search_messages_for_keyword($keyword, $searchcontent, $headerdb, $folderhandle, "$folderdir/.search.cache");
      foreach ( get_messageids_sorted($headerdb, $sort, "$headerdb.cache") ) {
         push (@messageids, $_) if ( $haskeyword{$_} == 1 ); 
      }
   } else {
      @messageids=get_messageids_sorted($headerdb, $sort, "$headerdb.cache");
   }

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
         elsif ($lastline eq 'RECEIVED')   { $currentreceived .= $_ }
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
      } elsif (/^Received:(.+)$/ig) {
         my $tmp=$1;
         if ($currentreceived=~ /.* by\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1);
         }
         if ($currentreceived=~ /.* from\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1);
         }
         $currentreceived=$tmp;
         $lastline = 'RECEIVED';
      } else {
         $lastline = 'NONE';
      }
   }

   # we don't count last from host as smtp relay since it is sender pc
   if ($currentreceived=~ /.*by\s([^\s]+)\s.*/) {
      unshift(@smtprelays, $1);
   }
   foreach (@smtprelays) {
      if (/[\w\d\-_]+\.[\w\d\-_]+/) {
         $message{smtprelay} = $_;
         last;
      }
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


   # Determine message's number and previous and next message IDs.
   foreach my $messagenumber (0..$#messageids) {
      if ($messageids[$messagenumber] eq $messageid) {
         $message{"prev"} = $messageids[$messagenumber-1] if ($messagenumber > 0);
         $message{"next"} = $messageids[$messagenumber+1] if ($messagenumber < $#messageids);
         $message{"number"} = $messagenumber+1;
         $message{"total"}=$#messageids+1;
         last;
      }
   }
   return \%message;
}

#################### END GETMESSAGE #######################

#################### UPDATESTATUS #########################
sub updatestatus {
   my ($messageid, $status) = @_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();

# since spool must exists here, we do lock before open
   unless (filelock($folderfile, LOCK_EX|LOCK_NB)) {
      openwebmailerror("$lang_err{'couldnt_lock'} $folderfile!");
   }
   update_headerdb($headerdb, $folderfile);
   open ($folderhandle, "+<$folderfile") or 
	openwebmailerror("$lang_err{'couldnt_open'} $folderfile!");

   my @messageids=get_messageids_sorted_by_offset($headerdb);
   my $movement;
   my @attr;
   my $i;

   filelock("$headerdb.$dbm_ext", LOCK_EX);
   dbmopen (%HDB, $headerdb, 600);

   for ($i=0; $i<=$#messageids; $i++) {
      if ($messageids[$i] eq $messageid) {
         @attr=split(/@@@/, $HDB{$messageid});

         return if ($attr[$_STATUS]=~/$status/i);

         my $messagestart=$attr[$_OFFSET];
         my $messagesize=$attr[$_SIZE];
         my $messagenewstatus;
         my ($header, $headerend, $headerlen, $newheaderlen);
         my $buff;
         
         seek ($folderhandle, $messagestart, 0) or openwebmailerror("$lang_err{'couldnt_seek'} $folderfile!");

         $header="";
         $headerlen=-1;
         while ( ($headerlen=index($header,  "\n\n")) < 0 ) {
             my $left = $messagesize-length($header);
             if ($left>1024) {
               read($folderhandle, $buff, 1024);
             } elsif ($left>0) {
               read($folderhandle, $buff, $left);
             } else {
               $headerlen=length($header);
               last;
             }
             $header .= $buff;
         }
         $header=substr($header, 0, $headerlen);
         $headerend=$messagestart+$headerlen;

         # generate receipt to sender if read-confirmation is requested
         if ( $attr[$_STATUS]!~/r/i && $status=~/r/i &&
              $header=~/^Disposition-Notification-To:\s?(.*?)$/im ) {
            my $from = $useremail;
            my $to=$1;
            my $realname = $prefs{"realname"} || '';

            my $date = localtime();
            my @datearray = split(/ +/, $date);
            if ($datearray[0] =~ /[A-Za-z,]/) {
               shift @datearray; # Get rid of the day of the week
            }
            $date="$month{$datearray[0]}/$datearray[1]/$datearray[3] $datearray[2]";

            $to =~ s/^"?(.+?)"?\s*<(.*)>$/$2/ ||
            $to =~ s/<?(.*@.*)>?\s+\((.+?)\)/$1/ ||
            $to =~ s/<(.+)>/$1/;

            $realname =~ s/[\||'|"|`]/ /g;  # Get rid of shell escape attempts
            $from =~ s/[\||'|"|`]/ /g;  # Get rid of shell escape attempts
            $to =~ s/[\||'|"|`]/ /g;  # Get rid of shell escape attempts

            ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
            ($from =~ /^(.+)$/) && ($from = $1);
            ($to =~ /^(.+)$/) && ($to = $1);
            ($date =~ /^(.+)$/) && ($date = $1);

            if ( open (SENDMAIL, "|" . $sendmail . " -oem -oi -F '$realname' -f '$from' -t 1>&2") ) {
               print SENDMAIL "From: $realname <$from>\n";
               print SENDMAIL "To: $to\n";
               if ($prefs{"replyto"}) {
                  print SENDMAIL "Reply-To: ",$prefs{"replyto"},"\n";
               }
               print SENDMAIL "Subject: $lang_text{'read'} - $attr[$_SUBJECT]\n";
               print SENDMAIL "X-Mailer: Open WebMail $version\n";
               print SENDMAIL "X-OriginatingIP: $userip ($user)\n";

               print SENDMAIL "MIME-Version: 1.0\n";
               print SENDMAIL "Content-Type: text/plain; charset=$lang_charset\n\n";

               print SENDMAIL "$lang_text{'yourmsg'}\n\n";
               print SENDMAIL "  $lang_text{'to'}: $attr[$_TO]\n";
               print SENDMAIL "  $lang_text{'subject'}: $attr[$_SUBJECT]\n";
               print SENDMAIL "  $lang_text{'delivered'}: $attr[$_DATE]\n\n";
               print SENDMAIL "$lang_text{'wasreadon1'} $date $lang_text{'wasreadon2'}\n\n";
               close(SENDMAIL);
            }
         }      

         # update status
         if ($header =~ s/^status:\s?(.*?)$/Status: $status$1/im) {
           $messagenewstatus="$status$1";
         } else {
           $header .= "\nStatus: $status";
           $messagenewstatus="$status";
         }
         $header="From $header" unless ($header =~ /^From /);

         $newheaderlen=length($header);
         $movement=$newheaderlen-$headerlen;

         my $foldersize=(stat($folderhandle))[7];
         shiftblock($folderhandle, $headerend, $foldersize-$headerend, $movement);

         seek($folderhandle, $messagestart, 0) or openwebmailerror("$lang_err{'couldnt_seek'} $folderfile!");
         print $folderhandle $header;

         seek($folderhandle, $foldersize+$movement, 0);
         truncate($folderhandle, tell($folderhandle));

### set attributes in headerdb for this status changed message
         if ($attr[$_STATUS]!~/r/i && $messagenewstatus=~/r/i) {
            $HDB{'NEWMESSAGES'}--;
         }
         $attr[$_SIZE]=$messagesize+$movement;
         $attr[$_STATUS]=$messagenewstatus;
         $HDB{$messageid}=join('@@@', @attr);

         last;
      }
   }
   $i++;

### set attributes in headerdb for messages after the above status changed message
   for (;$i<=$#messageids; $i++) {
      @attr=split(/@@@/, $HDB{$messageids[$i]});
      $attr[$_OFFSET]+=$movement;
      $HDB{$messageids[$i]}=join('@@@', @attr);
   }

   close ($folderhandle) or openwebmailerror("$lang_err{'couldnt_close'} $folderfile!");

   $HDB{'METAINFO'}=metainfo($folderfile);
   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   filelock("$folderfile", LOCK_UN);
}
################### END UPDATESTATUS ######################

#################### MOVEMESSAGE ########################
sub movemessage {
   verifysession();
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
   $destination =~ s/[\s|\.|\/|\\|\`|;|<|>]//g; # remove dangerous char
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
   if ($hitquota && $op ne "delete") {
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
      $counted=op_message_with_ids($op, \@messageids, $folderfile, $headerdb);
   } else {
      $counted=op_message_with_ids($op, \@messageids, $folderfile, $headerdb, 
							$dstfile, $dstdb);
   }

   filelock($dstfile, LOCK_UN);
   filelock($folderfile, LOCK_UN);

   if ($counted>0){
      if ( $op eq 'move' || $op eq 'copy' ) {
         writelog("$op $counted msgs from $folder to $destination - ids=".join(", ", @messageids) );
      } else {
         writelog("$op $counted msgs from $folder - ids=".join(", ", @messageids) );
      }
   } elsif ($counted==-1) {
      openwebmailerror("$lang_err{'inv_msg_op'}");
   } elsif ($counted==-2) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderfile");
   } elsif ($counted==-3) {
      openwebmailerror("$lang_err{'couldnt_open'} $dstfile!");
   }
    
   if (param("messageaftermove")) {
      readmessage();
   } else {
      displayheaders();
   }
}


#################### END MOVEMESSAGE #######################

#################### DOWNLOAD FOLDER #######################

sub downloadfolder {
   verifysession();
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my ($cmd, $contenttype, $filename);
   my $buff;

   if ( -x '/usr/local/bin/zip' ) {
      $cmd="/usr/local/bin/zip -r - $folderfile |";
      $contenttype='application/x-zip-compressed';
      $filename="$folder.zip";

   } elsif ( -x '/usr/bin/zip' ) {
      $cmd="/usr/bin/zip -r - $folderfile |";
      $contenttype='application/x-zip-compressed';
      $filename="$folder.zip";

   } elsif ( -x '/usr/bin/gzip' ) {
      $cmd="/usr/bin/gzip -c $folderfile |";
      $contenttype='application/x-gzip-compressed';
      $filename="$folder.gz";

   } elsif ( -x '/usr/local/bin/gzip' ) {
      $cmd="/usr/local/bin/gzip -c $folderfile |";
      $contenttype='application/x-gzip-compressed';
      $filename="$folder.gz";

   } else {
      $cmd="$folderfile";
      $contenttype='text/plain';
      $filename="$folder";
   }

   filelock($folderfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $folderfile");

   print qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$filename"\n|,
         qq|Content-Disposition: attachment; filename="$filename"\n|,
         qq|\n|;

   ($cmd =~ /^(.+)$/) && ($cmd = $1);		# bypass taint check
   open (T, $cmd);
   while ( read(T, $buff,32768) ) {
     print $buff;
   }
   close(T);

   filelock($folderfile, LOCK_UN);

   return;
}

################## END DOWNLOADFOLDER #####################

#################### EMPTYTRASH ########################
sub emptytrash {
   verifysession();
   my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'trash-mail');
   open (TRASH, ">$trashfile") or
      openwebmailerror ("$lang_err{'couldnt_open'} $trashfile!");
   close (TRASH) or openwebmailerror("$lang_err{'couldnt_close'} $trashfile!");
   update_headerdb($trashdb, $trashfile);

   writelog("trash emptied");
   displayheaders();
}
#################### END EMPTYTRASH #######################


##################### GETATTLIST ###############################
sub getattlist {
   my $currentfile;
   my @attlist;
   $savedattsize = 0;

   opendir (SESSIONSDIR, "$openwebmaildir/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $openwebmaildir/sessions!");

   while (defined($currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         $currentfile = $1;
         $savedattsize += ( -s "$openwebmaildir/sessions/$currentfile" );
         open (ATTFILE, "$openwebmaildir/sessions/$currentfile");
         while (defined(my $line = <ATTFILE>)) {
            if ($line =~ s/^.+name="?([^"]+)"?.*$/$1/i) {
               $line = str2html($line);
               $line =~ s/^(.*)$/<em>$1<\/em>/;
               push (@attlist, $line);
               last;
            } elsif ($line =~ /^\s+$/ ) {
               $line = $currentfile;
               $line =~ s/^.*att(\d+)$/<em>attachment.$1<\/em>/;
               push (@attlist, $line);
               last; 
            }
         }
         close (ATTFILE);
      }
   }

   closedir (SESSIONSDIR);
   return \@attlist;
}
##################### END GETATTLIST ###########################

##################### DELETEATTACHMENTS ############################
sub deleteattachments {
   my $currentfile;
   opendir (SESSIONSDIR, "$openwebmaildir/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $openwebmaildir/sessions!");
   while (defined($currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         $currentfile = $1;
         unlink ("$openwebmaildir/sessions/$currentfile");
      }
   }
   closedir (SESSIONSDIR);
}
#################### END DELETEATTACHMENTS #########################

################ CLEANUPOLDSESSIONS ##################
sub cleanupoldsessions {
   my $sessionid;
   opendir (SESSIONSDIR, "$openwebmaildir/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $openwebmaildir/sessions!");
   while (defined($sessionid = readdir(SESSIONSDIR))) {
      if ($sessionid =~ /^(\w+\-session\-0\.\d*.*)$/) {
         $sessionid = $1;
         if ( -M "$openwebmaildir/sessions/$sessionid" > $sessiontimeout ) {
            writelog("session cleanup - $sessionid");
            unlink "$openwebmaildir/sessions/$sessionid";
         }
      }
   }
   closedir (SESSIONSDIR);
}
############## END CLEANUPOLDSESSIONS ################

##################### FIRSTTIMEUSER ################################
sub firsttimeuser {
   my $html = '';
   my $temphtml;
   open (FTUSER, "$openwebmaildir/templates/$lang/firsttimeuser.template") or
      openwebmailerror("$lang_err{'couldnt_open'} firsttimeuser.template!");
   while (<FTUSER>) {
      $html .= $_;
   }
   close (FTUSER);
   
   $html = applystyle($html);

   printheader();

   $temphtml = startform(-action=>"$prefsurl");
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'firsttimeuser',
                       -default=>'yes',
                       -override=>'1');
   $temphtml .= hidden(-name=>'realname',
                       -default=>(split(/,/,(getpwnam($user))[6]))[0] || "Your Name",
                       -override=>'1');
   $temphtml .= submit("$lang_text{'continue'}");
   $temphtml .= end_form();

   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;
   
   print $html;

   printfooter();
}
################### END FIRSTTIMEUSER ##############################

################## RETRIVE POP3 ###########################
sub retrpop3 {
   verifysession();
   my ($spoolfile, $header)=get_folderfile_headerdb($user, 'INBOX');
   my ($pop3host, $pop3user);
   my (%account, $response);

   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      open (F, ">>$spoolfile");
      close(F);
   }

   $pop3host = param("host") || '';
   $pop3user = param("name") || '';

   if ( ! -f "$folderdir/.pop3.book" ) {
      print "Location:  $prefsurl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage";
   }

   %account = getpop3book("$folderdir/.pop3.book");
   if (%account == 0) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.pop3.book!");
   }

#   unless (filelock($spoolfile, LOCK_EX|LOCK_NB)) {
#      openwebmailerror("$lang_err{'couldnt_lock'} $spoolfile!");
#   }
   $response = retrpop3mail($pop3host, $pop3user, 
				"$folderdir/.pop3.book", $spoolfile);
#   filelock($spoolfile, LOCK_UN);

   if ($response>=0) {	# new mail found
      $folder="INBOX";
      print "Location: $scripturl?action=displayheaders&sessionid=$thissession&sort=$sort&firstmessage=$firstmessage&folder=$folder\n\n";
   } else {
      writelog("pop3 error $response at $pop3user\@$pop3host");
      if ($response == -1) {
   	  openwebmailerror("$lang_err{'user_not_exist'}");
      } elsif ($response == -2) {
   	  openwebmailerror("$lang_err{'couldnt_open'} pop3 folder for $host");
      } elsif ($response == -3) {
   	  openwebmailerror("$host $lang_err{'network_server_error'}");
      } elsif ($response == -4) {
      	  openwebmailerror("$host $lang_err{'password_error'}");
      }
   }
}
################## END RETRIVE POP3 ###########################

################## RETRIVE ALL POP3 ###########################
sub retrpop3s {
   verifysession();
   my ($spoolfile, $header)=get_folderfile_headerdb($user, 'INBOX');
   my (%account, $response);
   my $fetch_complete=0;
   my $i;

   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      open (F, ">>$spoolfile");
      close(F);
   }

   if ( ! -f "$folderdir/.pop3.book" ) {
      print "Location: $prefsurl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchcontent=$searchcontent&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage";
   }

   %account = getpop3book("$folderdir/.pop3.book");

   # fork a child to do fetch pop3 mails and return immediately
   if (%account >0) {
      $|=1; 				# flush all output
      $SIG{CHLD} = sub { wait; $fetch_complete=1; };	# handle zombie

      if ( fork() == 0 ) {		# child
         close(STDOUT);
         close(STDIN);

         foreach (values %account) {
            my ($pop3host, $pop3user, $mbox);
            my ($response, $dummy);

            ($pop3host, $pop3user, $dummy) = split(/:/,$_, 3);
            $response = retrpop3mail($pop3host, $pop3user, 
         				"$folderdir/.pop3.book",  $spoolfile);
            if ( $response<0) {
               writelog("pop3 error $response at $pop3user\@$pop3host");
            }
         }
         exit;
      }
   }

   for ($i=0; $i<10; $i++) {	# wait fetch to complete for 10 seconds
      sleep 1;
      if ($fetch_complete==1) {
         last;
      }
   }   

   $folder="INBOX";
   print "Location: $scripturl?action=displayheaders&sessionid=$thissession&sort=$sort&firstmessage=$firstmessage&folder=$folder\n\n";
}
################## END RETRIVE ALL POP3 ###########################

################# FILTERMESSAGE ###########################
sub filtermessage {
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');

   my $removed=mailfilter($spoolfile, $headerdb, 
			$folderdir, \@validfolders, $user, $uid, $gid);
   if ($removed > 0) {
      writelog("filter $removed msgs from $spoolfile");
   } elsif ($removed == -1 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   } elsif ($removed == -2 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
   } elsif ($removed == -3 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} $spoolfile!");
   } elsif ($removed == -4 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $spoolfile!");
   } elsif ($removed == -5 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   }
}
################# END FILTERMESSAGE #######################

################ CHECKLOGIN ###############################

sub checklogin {
  my ($passwdfile, $username, $password)=@_;
  my $success = 1; # default to success

   if ( $passwdfile && $username && $password ) {
      open (PASSWD, $passwdfile) or exit 1;
      while (defined($line = <PASSWD>)) {
         ($usr,$pswd) = (split(/:/, $line))[0,1];
         last if ($usr eq $username); # We've found the user in /etc/passwd
      }
      close (PASSWD);
      if (($usr ne $username) or (crypt($password, $pswd) ne $pswd)) {
         $success = 0; # User/Pass combo is WRONG!
      }
   } else {
      $success = 0;
   }

   return $success;
}

################ END CHECKLOGIN ###########################
