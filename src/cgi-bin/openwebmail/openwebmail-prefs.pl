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

require "etc/openwebmail.conf";
require "openwebmail-shared.pl";
require "filelock.pl";
require "pop3mail.pl";

local $thissession;
local $user;
local ($uid, $gid, $homedir);
local %prefs;
local %style;
local $lang;
local $firstmessage;
local $sort;
local $hitquota;
local $folderdir;
local $folder;
local $printfolder;
local $escapedfolder;
local $messageid;
local $escapedmessageid;
local $firsttimeuser;


$thissession = param("sessionid") || '';
$user = $thissession || '';
$user =~ s/\-session\-0.*$//; # Grab userid from sessionid
($user =~ /^(.+)$/) && ($user = $1);  # untaint $user...

$uid=$>; $gid = getgrnam('mail');

# setuid is required if mails is located in user's dir
if (($homedirspools eq 'yes') || ($homedirfolders eq 'yes')) { 
   if ( $> != 0 ) {
      my $suidperl=$^X;
      $suidperl=~s/perl/suidperl/;
      openwebmailerror("<b>$0 must setuid to root!</b><br>".
                       "<br>1. check if script is owned by root with mode 4755".
                       "<br>2. use '#!$suidperl' instead of '#!$^X' in script");
   }  
   if ($user) {
      my $ugid;
      ($uid, $ugid, $homedir) = (getpwnam($user))[2,3,7] or
         openwebmailerror("User $user doesn't exist!");
   }
}
set_euid_egid_umask($uid, $gid, 0077);

# egid must be mail since this is a mail program...
if ( $) != $gid) { 
   openwebmailerror("Set effective gid to mail($gid) failed!");
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

$hitquota=0;
$folder = param("folder") || 'INBOX';
$printfolder = $lang_folders{$folder} || $folder;
$escapedfolder = CGI::escape($folder);

$messageid=param("message_id") || '';
$escapedmessageid=CGI::escape($messageid);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{"sort"} || 'date';

$firsttimeuser = param("firsttimeuser") || ''; # Don't allow cancel if 'yes'

########################## MAIN ##############################
if (defined(param("action"))) {      # an action has been chosen
   my $action = param("action");
   if ($action =~ /^(\w+)$/) {
      $action = $1;
      if ($action eq "saveprefs") {
         saveprefs();
      } elsif ($action eq "editfolders") {
         editfolders();
      } elsif ($action eq "addfolder") {
         addfolder();
      } elsif ($action eq "deletefolder") {
         deletefolder();
      } elsif ($action eq "renamefolder") {
         renamefolder();
      } elsif ($action eq "downloadfolder") {
         downloadfolder();
      } elsif ($action eq "addressbook") {
         addressbook();
      } elsif ($action eq "editaddresses") {
         editaddresses();
      } elsif ($action eq "addaddress") {
         modaddress("add");
      } elsif ($action eq "deleteaddress") {
         modaddress("delete");
      } elsif ($action eq "clearaddress") {
         clearaddress();
      } elsif ($action eq "importabook") {
         importabook();
      } elsif ($action eq "exportabook") {
         exportabook();
      } elsif ($action eq "editpop3" && $enable_pop3 eq 'yes') {
         editpop3();
      } elsif ($action eq "addpop3" && $enable_pop3 eq 'yes') {
         modpop3("add");
      } elsif ($action eq "deletepop3" && $enable_pop3 eq 'yes') {
         modpop3("delete");
      } elsif ($action eq "editfilter") {
         editfilter();
      } elsif ($action eq "addfilter") {
         modfilter("add");
      } elsif ($action eq "deletefilter") {
         modfilter("delete");
      } else {
         openwebmailerror("Action $lang_err{'has_illegal_chars'}");
      }
   } else {
      openwebmailerror("Action $lang_err{'has_illegal_chars'}");
   }
} else {            # no action has been taken, display prefs page
   editprefs();
}
###################### END MAIN ##############################

####################EDITPREFS ###########################
sub editprefs {
   verifysession();

   my $html = '';
   my $temphtml;

   open (PREFSTEMPLATE, "$openwebmaildir/templates/$lang/prefs.template") or
      openwebmailerror("$lang_err{'couldnt_open'} prefs.template");
   while (<PREFSTEMPLATE>) {
      $html .= $_;
   }
   close (PREFSTEMPLATE);

   $html = applystyle($html);

   my @styles;
   printheader();

### Get a list of valid style files
   opendir (STYLESDIR, "$openwebmaildir/styles") or
      openwebmailerror("$lang_err{'couldnt_open'} $openwebmaildir/styles directory for reading!");
   while (defined(my $currentstyle = readdir(STYLESDIR))) {
      unless ($currentstyle =~ /\./) {
         push (@styles, $currentstyle);
      }
   }
   @styles = sort(@styles);
   closedir(STYLESDIR) or
      openwebmailerror("$lang_err{'couldnt_close'} $openwebmaildir/styles!");
   $temphtml = start_form(-action=>$prefsurl);
   $temphtml .= hidden(-name=>'action',
                       -default=>'saveprefs',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'firstmessage',
                       -default=>$firstmessage,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');

   $html =~ s/\@\@\@STARTPREFSFORM\@\@\@/$temphtml/;

   if (param("realname")) {
      $prefs{"realname"} = param("realname");
   }
   if ($prefs{"realname"}) {
      $temphtml = " $lang_text{'for'} " . uc($prefs{"realname"});
   } else {
      $temphtml = '';
   }

   $html =~ s/\@\@\@REALNAME\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'language',
                          -"values"=>\@availablelanguages,
                          -default=>$prefs{"language"} || $defaultlanguage,
                          -labels=>\%languagenames,
                          -override=>'1');

   $html =~ s/\@\@\@LANGUAGEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'realname',
                         -default=>$prefs{"realname"} || $lang_text{'yourname'},
                         -size=>'40',
                         -override=>'1');

   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'fromname',
                         -default=>$prefs{"fromname"} || $user,
                         -size=>'15',
                         -override=>'1');

   $html =~ s/\@\@\@USERNAME\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'domainname',
                          -"values"=>\@domainnames,
                          -default=>$prefs{"domainname"} || $domainnames[0],
                          -override=>'1');

   $html =~ s/\@\@\@DOMAINFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'replyto',
                         -default=>$prefs{"replyto"} || '',
                         -size=>'40',
                         -override=>'1');

   $html =~ s/\@\@\@REPLYTOFIELD\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'style',
                          -"values"=>\@styles,
                          -default=>$prefs{"style"} || 'Default',
                          -override=>'1');

   $html =~ s/\@\@\@STYLEMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'sort',
                          -"values"=>['date','date_rev','sender','sender_rev',
                                      'size','size_rev','subject','subject_rev',
                                      'status'],
                          -default=>$prefs{"sort"} || 'date',
                          -labels=>\%lang_sortlabels,
                          -override=>'1');

   $html =~ s/\@\@\@SORTMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'headersperpage',
                          -"values"=>['10','20','30','40','50','100','500','1000'],
                          -default=>$prefs{"headersperpage"} || $headersperpage,
                          -override=>'1');

   $html =~ s/\@\@\@HEADERSPERPAGE\@\@\@/$temphtml/;

   $filter_repeatlimit=$prefs{'filter_repeatlimit'} if ( defined($prefs{'filter_repeatlimit'}) );
   $temphtml = popup_menu(-name=>'filter_repeatlimit',
                          -"values"=>['0','5','10','20','30','40','50','100'],
                          -default=>$filter_repeatlimit,
                          -override=>'1');

   $html =~ s/\@\@\@FILTERREPEATLIMIT\@\@\@/$temphtml/;

   my %headerlabels = ('simple'=>$lang_text{'simplehead'},
                       'all'=>$lang_text{'allhead'}
                      );
   $temphtml = popup_menu(-name=>'headers',
                          -"values"=>['simple','all'],
                          -default=>$prefs{"headers"} || 'simple',
                          -labels=>\%headerlabels,
                          -override=>'1');

   $html =~ s/\@\@\@HEADERSMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'defaultdestination',
                          -"values"=>['saved-messages','mail-trash', 'DELETE'],
                          -default=>$prefs{"defaultdestination"} || 'mail-trash',
                          -labels=>\%lang_folders,
                          -override=>'1');

   $html =~ s/\@\@\@DEFAULTDESTINATIONMENU\@\@\@/$temphtml/;

   $filter_fakedsmtp=($filter_fakedsmtp eq 'yes'||$filter_fakedsmtp==1)?1:0;
   $filter_fakedsmtp=$prefs{'filter_fakedsmtp'} if ( defined($prefs{'filter_fakedsmtp'}) );
   $temphtml = checkbox(-name=>'filter_fakedsmtp',
                        -value=>'1',
                        -checked=>$filter_fakedsmtp,
                        -label=>'');
   $html =~ s/\@\@\@FILTERFAKEDSMTP\@\@\@/$temphtml/g;

   $temphtml = checkbox(-name=>'newmailsound',
                  -value=>'1',
                  -checked=>$prefs{"newmailsound"},
                  -label=>'');

   $html =~ s/\@\@\@NEWMAILSOUND\@\@\@/$temphtml/g;

   if ($enable_pop3 eq 'yes') {
      $temphtml = checkbox(-name=>'autopop3',
                           -value=>'1',
                           -checked=>$prefs{"autopop3"},
                           -label=>'');
      $html =~ s/\@\@\@AUTOPOP3CHECKBOX\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@AUTOPOP3START\@\@\@//g;
      $html =~ s/\@\@\@AUTOPOP3END\@\@\@//g;
   } else {
      $html =~ s/\@\@\@AUTOPOP3CHECKBOX\@\@\@/not available/g;
      $html =~ s/\@\@\@AUTOPOP3START\@\@\@/<!--/g;
      $html =~ s/\@\@\@AUTOPOP3END\@\@\@/-->/g;
   }

   $temphtml = checkbox(-name=>'autoemptytrash',
                  -value=>'1',
                  -checked=>$prefs{"autoemptytrash"},
                  -label=>'');

   $html =~ s/\@\@\@AUTOEMPTYTRASHCHECKBOX\@\@\@/$temphtml/g;

   unless (defined($prefs{"signature"})) {
      $prefs{"signature"} = $defaultsignature;
   }
   $temphtml = textarea(-name=>'signature',
                        -default=>$prefs{"signature"},
                        -rows=>'5',
                        -columns=>'72',
                        -wrap=>'hard',
                        -override=>'1');

   $html =~ s/\@\@\@SIGAREA\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'save'}") . end_form();

   unless ( $firsttimeuser eq 'yes' ) {
      $temphtml .= startform(-action=>"$scripturl");
      $temphtml .= hidden(-name=>'action',
                          -default=>'displayheaders',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1') .
                   '</td><td>' .
                   submit("$lang_text{'cancel'}") . end_form();
   }

   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/;

   print $html;

   printfooter();
}
#################### END EDITPREFS ###########################

#################### EDITFOLDERS ###########################
sub editfolders {
   verifysession();
   my (@defaultfolders, @userfolders);
   my ($total_newmessages, $total_allmessages, $total_foldersize)=(0,0,0);

   push(@defaultfolders, 'INBOX', 
                         'saved-messages', 
                         'sent-mail', 
                         'saved-drafts', 
                         'mail-trash');

   opendir (FOLDERDIR, "$folderdir") or
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir!");
   while (defined(my $filename = readdir(FOLDERDIR))) {
### skip files started with ., which are openwebmail internal files (dbm, search caches)
      if ( $filename=~/^\./ ) {	
         next;
      }
      if  ( $filename !~ /^\./ &&		# not . .. or .xxx
            $filename ne 'saved-messages' &&
            $filename ne 'sent-mail' &&
            $filename ne 'saved-drafts' &&
            $filename ne 'mail-trash' ) {
         push (@userfolders, $filename);
      }
   }
   closedir (FOLDERDIR) or
      openwebmailerror("$lang_err{'couldnt_close'} $folderdir!");

   my $html = '';
   my $temphtml;

   open (EDITFOLDERSTEMPLATE, "$openwebmaildir/templates/$lang/editfolders.template") or
      openwebmailerror("$lang_err{'couldnt_open'} editfolders.template!");
   while (<EDITFOLDERSTEMPLATE>) {
      $html .= $_;
   }
   close (EDITFOLDERSTEMPLATE);

   $html = applystyle($html);

   printheader();

   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$escapedfolder\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>$prefsurl) .
               hidden(-name=>'action',
                      -value=>'addfolder',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -value=>$thissession,
                      -override=>'1') .
               hidden(-name=>'sort',
                      -default=>$sort,
                      -override=>'1') .
               hidden(-name=>'firstmessage',
                      -default=>$firstmessage,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');

   $html =~ s/\@\@\@STARTFOLDERFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'foldername',
                         -default=>'',
                         -size=>'16',
                         -maxlength=>'16',
                         -override=>'1');

   $html =~ s/\@\@\@FOLDERNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'add'}");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   my $bgcolor = $style{"tablerow_dark"};
   my $currfolder;
   my $i=0;

   $temphtml = '';
   foreach $currfolder (sort (@userfolders)) {
      my (%HDB, $newmessages, $allmessages, $foldersize);
      my ($folderfile,$headerdb)=get_folderfile_headerdb($user, $currfolder);

      filelock("$headerdb.$dbm_ext", LOCK_SH);
      dbmopen (%HDB, $headerdb, undef);
      if ( defined($HDB{'ALLMESSAGES'}) ) {
         $allmessages=$HDB{'ALLMESSAGES'};
         $total_allmessages+=$allmessages;
      } else {
         $allmessages='&nbsp;';
      }
      if ( defined($HDB{'NEWMESSAGES'}) ) {
         $newmessages=$HDB{'NEWMESSAGES'};
         $total_newmessages+=$newmessages;
      } else {
         $newmessages='&nbsp;';
      }
      dbmclose(%HDB);
      filelock("$headerdb.$dbm_ext", LOCK_UN);

      $foldersize = (-s "$folderfile");
      $total_foldersize+=$foldersize;
      # round foldersize and change to an appropriate unit for display
      if ($foldersize > 1048575){
         $foldersize = int(($foldersize/1048576)+0.5) . "MB";
      } elsif ($foldersize > 1023) {
         $foldersize =  int(($foldersize/1024)+0.5) . "KB";
      }

      my $escapedcurrfolder = CGI::escape($currfolder);
      my $url = "$prefsurl?sessionid=$thissession&amp;folder=$escapedcurrfolder&amp;action=downloadfolder";
      $temphtml .= "<tr><td align=\"center\" bgcolor=$bgcolor><a href=\"$url\">$currfolder</a></td>".
                   "<td align=\"center\" bgcolor=$bgcolor>$newmessages</td>".
                   "<td align=\"center\" bgcolor=$bgcolor>$allmessages</td>".
                   "<td align=\"center\" bgcolor=$bgcolor>$foldersize</td>";

      $temphtml .= start_form(-action=>$prefsurl,
                              -name=>"folderform$i");
      $temphtml .= hidden(-name=>'action',
                          -value=>'deletefolder',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'foldername',
                          -value=>$currfolder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'foldernewname',
                          -value=>$currfolder,
                          -override=>'1');

      $temphtml .= "<td bgcolor=$bgcolor align=\"center\">";

      $temphtml .= submit(-name=>"$lang_text{'rename'}", 
                          -onClick=>"return OpConfirm('folderform$i', 'renamefolder', $lang_text{'folderrenprop'}+' ( $currfolder )')");
      $temphtml .= submit(-name=>"$lang_text{'delete'}",
                          -onClick=>"return OpConfirm('folderform$i', 'deletefolder', $lang_text{'folderdelconf'}+' ( $currfolder )')");

      $temphtml .= '</td></tr>';
      $temphtml .= end_form();
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }

      $i++;
   }
   $html =~ s/\@\@\@FOLDERS\@\@\@/$temphtml/;

   $temphtml='';
   foreach $currfolder (@defaultfolders) {
      my (%HDB, $newmessages, $allmessages, $foldersize);
      my ($folderfile,$headerdb)=get_folderfile_headerdb($user, $currfolder);

      filelock("$headerdb.$dbm_ext", LOCK_SH);
      dbmopen (%HDB, $headerdb, undef);
      if ( defined($HDB{'ALLMESSAGES'}) ) {
         $allmessages=$HDB{'ALLMESSAGES'};
         $total_allmessages+=$allmessages;
      } else {
         $allmessages='&nbsp;';
      }
      if ( defined($HDB{'NEWMESSAGES'}) ) {
         $newmessages=$HDB{'NEWMESSAGES'};
         $total_newmessages+=$newmessages;
      } else {
         $newmessages='&nbsp;';
      }
      dbmclose(%HDB);
      filelock("$headerdb.$dbm_ext", LOCK_UN);

      $foldersize = (-s "$folderfile");
      $total_foldersize+=$foldersize;
      # round foldersize and change to an appropriate unit for display
      if ($foldersize > 1048575){
         $foldersize = int(($foldersize/1048576)+0.5) . "MB";
      } elsif ($foldersize > 1023) {
         $foldersize =  int(($foldersize/1024)+0.5) . "KB";
      }

      my $escapedcurrfolder = CGI::escape($currfolder);
      my $url = "$prefsurl?sessionid=$thissession&amp;folder=$escapedcurrfolder&amp;action=downloadfolder";
      my $folderstr=$currfolder;
      $folderstr=$lang_folders{$currfolder} if defined($lang_folders{$currfolder});
      $temphtml .= "<tr>".
                   "<td align=\"center\" bgcolor=$bgcolor><a href=\"$url\">$folderstr</a></td>".
                   "<td align=\"center\" bgcolor=$bgcolor>$newmessages</td>".
                   "<td align=\"center\" bgcolor=$bgcolor>$allmessages</td>".
                   "<td align=\"center\" bgcolor=$bgcolor>$foldersize</td>".
                   "<td bgcolor=$bgcolor align=\"center\">-----</td>";
                   "</tr>";
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   $html =~ s/\@\@\@DEFAULTFOLDERS\@\@\@/$temphtml/;

   if ($total_foldersize > 1048575){
      $total_foldersize = int(($total_foldersize/1048576)+0.5) . "MB";
   } elsif ($total_foldersize > 1023) {
      $total_foldersize =  int(($total_foldersize/1024)+0.5) . "KB";
   }
   $temphtml = "<tr>".
               "<td align=\"center\" bgcolor=$bgcolor><B>$lang_text{'total'}</B></td>".
               "<td align=\"center\" bgcolor=$bgcolor><B>$total_newmessages</B></td>".
               "<td align=\"center\" bgcolor=$bgcolor><B>$total_allmessages</B></td>".
               "<td align=\"center\" bgcolor=$bgcolor><B>$total_foldersize</B></td>".
               "<td bgcolor=$bgcolor align=\"center\">&nbsp</td>";
               "</tr>";
   $html =~ s/\@\@\@TOTAL\@\@\@/$temphtml/;

   print $html;

   printfooter();
}
################### END EDITFOLDERS ########################

################### ADDFOLDER ##############################
sub addfolder {
   verifysession();

   my $foldertoadd = param('foldername') || '';
   $foldertoadd =~ s/\.\.+//g;
   $foldertoadd =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($foldertoadd =~ /^(.+)$/) && ($foldertoadd = $1);

   if (length($foldertoadd) > 16) {
      openwebmailerror("$lang_err{'foldername_long'}");
   }
   if ( is_defaultfolder($foldertoadd) ||
        $foldertoadd eq "$user" || $foldertoadd eq "" ) {
      openwebmailerror("$lang_err{'cant_create_folder'}");
   }

   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertoadd);
   if ( -f $folderfile ) {
      openwebmailerror ("$lang_err{'folder_with_name'} $foldertoadd $lang_err{'already_exists'}");
   }

   open (FOLDERTOADD, ">$folderfile") or
      openwebmailerror("$lang_err{'cant_create_folder'} $foldertoadd!");
   close (FOLDERTOADD) or openwebmailerror("$lang_err{'couldnt_close'} $foldertoadd!");

#   print "Location: $prefsurl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
   editfolders();
}

sub is_defaultfolder {
   my $foldername=$_[0];
   if ($foldername eq 'INBOX' ||
       $foldername eq 'saved-messages' || 
       $foldername eq 'sent-mail' ||
       $foldername eq 'saved-drafts' ||
       $foldername eq 'mail-trash' ||
       $foldername eq 'DELETE' ||
       $foldername eq $lang_folders{'saved-messages'} ||
       $foldername eq $lang_folders{'sent-mail'} ||
       $foldername eq $lang_folders{'saved-drafts'} ||
       $foldername eq $lang_folders{'mail-trash'} ) {
      return(1);
   } else {
      return(0);
   }
}
################### END ADDFOLDER ##########################

################### DELETEFOLDER ##############################
sub deletefolder {
   verifysession();

   my $foldertodel = param('foldername') || '';
   $foldertodel =~ s/\.\.+//g;
   $foldertodel =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($foldertodel =~ /^(.+)$/) && ($foldertodel = $1);

   # if is default folder, return to editfolder immediately
   if (is_defaultfolder($foldertodel)) {
      editfolders();
   }

   if ( -f "$folderdir/$foldertodel" ) {
      unlink ("$folderdir/$foldertodel",
              "$folderdir/.$foldertodel.$dbm_ext",
              "$folderdir/.$foldertodel.db",
	      "$folderdir/.$foldertodel.dir",
              "$folderdir/.$foldertodel.pag",
              "$folderdir/.$foldertodel.cache",
              "$folderdir/$foldertodel.lock",
              "$folderdir/$foldertodel.lock.lock");              
   }

#   print "Location: $prefsurl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
   editfolders();
}
################### END DELETEFOLDER ##########################

################### RENAMEFOLDER ##############################
sub renamefolder {
   verifysession();

   my $oldname = param('foldername') || '';
   $oldname =~ s/\.\.+//g;
   $oldname =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($oldname =~ /^(.+)$/) && ($oldname = $1);

   if (is_defaultfolder($oldname)) {
      editfolders();
   }

   my $newname = param('foldernewname');
   $newname =~ s/\.\.+//g;
   $newname =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($newname =~ /^(.+)$/) && ($newname = $1);

   if (length($newname) > 16) {
      openwebmailerror("$lang_err{'foldername_long'}");
   }
   if ( is_defaultfolder($newname) ||
        $newname eq "$user" || $newname eq "" ) {
      openwebmailerror("$lang_err{'cant_create_folder'}");
   }
   if ( -f "$folderdir/$newname" ) {
      openwebmailerror ("$lang_err{'folder_with_name'} $newname $lang_err{'already_exists'}");
   }

   if ( -f "$folderdir/$oldname" ) {
      rename("$folderdir/$oldname",          "$folderdir/$newname");
      rename("$folderdir/.$oldname.$dbm_ext","$folderdir/.$newname.$dbm_ext");
      rename("$folderdir/.$oldname.db",      "$folderdir/.$newname.db");
      rename("$folderdir/.$oldname.dir",     "$folderdir/.$newname.dir");
      rename("$folderdir/.$oldname.pag",     "$folderdir/.$newname.pag");
      rename("$folderdir/.$oldname.cache",   "$folderdir/.$newname.cache");
      unlink("$folderdir/$oldname.lock", "$folderdir/$oldname.lock.lock");
   }

#   print "Location: $prefsurl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
   editfolders();
}
################### END RENAMEFOLDER ##########################

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

   # disposition:attachment default to save
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

##################### IMPORTABOOK ############################
sub importabook {
   verifysession();

   my ($name, $email);
   my %addresses;
   my $abookupload = param("abook") || '';
   my $abooktowrite='';
   my $mua = param("mua") || '';
   if ($abookupload) {
      no strict 'refs';
      my $abookcontents = '';
      while (<$abookupload>) {
         $abookcontents .= $_;
      }
      close($abookupload);
#      if ($mua eq 'outlookexp5') {
#         unless ($abookcontents =~ /^Name,E-mail Address/) {
#            openwebmailerror("$lang_err{'abook_invalid'} <a href=\"$prefsurl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid\">$lang_err{'back'}</a> $lang_err{'tryagain'}");
#         }
#      }
      unless ( -f "$folderdir/.address.book" ) {
         open (ABOOK, ">>$folderdir/.address.book"); # Create if nonexistent
         close(ABOOK);
      }
      filelock("$folderdir/.address.book", LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} .address.book!");
      open (ABOOK,"+<$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
      while (<ABOOK>) {
         ($name, $email) = split(/:/, $_);
         chomp($email);
         $addresses{"$name"} = $email;
      }
      my @fields;
      my $quotecount;
      my $tempstr;
      my @processed;

      foreach (split(/\r*\n/, $abookcontents)) {
 #        next if ( ($mua eq 'outlookexp5') && (/^Name,E-mail Address/) );
         next if ( $_ !~ (/\@/) );
         $quotecount = 0;
         @fields = split(/,/);
         @processed = ();
         $tempstr = '';
         foreach my $str (@fields) {
            if ( ($str =~ /"/) && ($quotecount == 1) ) {
               $tempstr .= ',' . $str;
               $tempstr =~ s/"//g;
               push (@processed, $tempstr);
               $tempstr = '';
               $quotecount = 0;
            } elsif ($str =~ /"/) {
               $tempstr .= $str;
               $quotecount = 1;
            } elsif ($quotecount == 1) {
               $tempstr .= ',' . $str;
            } else {
               push (@processed, $str);
            }
         }
         if ( ($mua eq 'outlookexp5') && ($processed[0]) && ($processed[1]) ) {
            $processed[0] =~ s/^\s*//;
            $processed[0] =~ s/\s*$//;
            $processed[0] =~ s/://;
            $processed[0] =~ s/</&lt;/g;
            $processed[0] =~ s/>/&gt;/g;
            $processed[1] =~ s/</&lt;/g;
            $processed[1] =~ s/>/&gt;/g;
            $addresses{"$processed[0]"} = $processed[1];
         } elsif ( ($mua eq 'nsmail') && ($processed[0]) && ($processed[6]) ) {
            $processed[0] =~ s/^\s*//;
            $processed[0] =~ s/\s*$//;
            $processed[0] =~ s/://;
            $processed[0] =~ s/</&lt;/g;
            $processed[0] =~ s/>/&gt;/g;
            $processed[6] =~ s/</&lt;/g;
            $processed[6] =~ s/>/&gt;/g;
            $addresses{"$processed[0]"} = $processed[6];
         }
      }

      seek (ABOOK, 0, 0) or
         openwebmailerror("$lang_err{'couldnt_seek'} .address.book!");

      while ( ($name, $email) = each %addresses ) {
         $abooktowrite .= "$name:$email\n";
      }

      if (length($abooktowrite) > ($maxabooksize * 1024)) {
         openwebmailerror("$lang_err{'abook_toobig'}
                       <a href=\"$prefsurl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid\">$lang_err{'back'}</a>
                       $lang_err{'tryagain'}");
      }
      print ABOOK $abooktowrite;
      truncate(ABOOK, tell(ABOOK));

      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");
      filelock("$folderdir/.address.book", LOCK_UN);

#      print "Location: $prefsurl?action=editaddresses&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&message_id=$escapedmessageid\n\n";
      editaddresses();

   } else {

      my $abooksize = ( -s "$folderdir/.address.book" ) || 0;
      my $freespace = int($maxabooksize - ($abooksize/1024) + .5);

      my $html = '';
      my $temphtml;

      open (IMPORTTEMPLATE, "$openwebmaildir/templates/$lang/importabook.template") or
         openwebmailerror("$lang_err{'couldnt_open'} importabook.template");
      while (<IMPORTTEMPLATE>) {
         $html .= $_;
      }
      close (IMPORTTEMPLATE);

      $html = applystyle($html);

      printheader();

      $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace/g;

      $temphtml = start_multipart_form();
      $temphtml .= hidden(-name=>'action',
                          -value=>'importabook',
                          -override=>'1') .
                   hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1') .
                   hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1') .
                   hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1') .
                   hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
                   hidden(-name=>'message_id',
                          -default=>$messageid,
                          -override=>'1');
      $html =~ s/\@\@\@STARTIMPORTFORM\@\@\@/$temphtml/;

      $temphtml = radio_group(-name=>'mua',
                              -"values"=>['outlookexp5','nsmail'],
                              -default=>'outlookexp5',
                              -labels=>\%lang_mualabels);
      $html =~ s/\@\@\@MUARADIOGROUP\@\@\@/$temphtml/;

      $temphtml = filefield(-name=>'abook',
                            -default=>'',
                            -size=>'30',
                            -override=>'1');
      $html =~ s/\@\@\@IMPORTFILEFIELD\@\@\@/$temphtml/;

      $temphtml = submit("$lang_text{'import'}");
      $html =~ s/\@\@\@IMPORTBUTTON\@\@\@/$temphtml/;

      $temphtml = end_form();
      $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

      $temphtml = start_form(-action=>$prefsurl) .
                  hidden(-name=>'action',
                         -value=>'editaddresses',
                         -override=>'1') .
                  hidden(-name=>'sessionid',
                         -value=>$thissession,
                         -override=>'1') .
                  hidden(-name=>'sort',
                         -default=>$sort,
                         -override=>'1') .
                  hidden(-name=>'folder',
                         -default=>$folder,
                         -override=>'1') .
                  hidden(-name=>'firstmessage',
                         -default=>$firstmessage,
                         -override=>'1');
                  hidden(-name=>'message_id',
                         -default=>$messageid,
                         -override=>'1') .
      $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;


      $temphtml = submit("$lang_text{'cancel'}");
      $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

      print $html;

      printfooter();
   }
}
#################### END IMPORTABOOK #########################

##################### EXPORTABOOK ############################
sub exportabook {
   verifysession();

   filelock("$folderdir/.address.book", LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} .address.book!");
   open (ABOOK,"$folderdir/.address.book") or
      openwebmailerror("$lang_err{'couldnt_open'} .address.book!");

   # disposition:attachment default to save
   print qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: text/plain; name="adbook.csv"\n|,
         qq|Content-Disposition: attachment; filename="adbook.csv"\n|,
         qq|\n|;

   print qq|Name,E-mail Address,Note\n|;

   while (<ABOOK>) {
      print join(",", split(/:/,$_,3));
   }

   close(ABOOK);
   filelock("$folderdir/.address.book", LOCK_UN);
   return;
}
#################### END EXPORTABOOK #########################

#################### EDITADDRESSES ###########################
sub editaddresses {
   verifysession();

   my %addresses=();
   my %notes=();
   my %globaladdresses=();
   my %globalnotes=();
   my ($name, $email, $note);

   my $html = '';
   my $temphtml;

   open (EDITABOOKTEMPLATE, "$openwebmaildir/templates/$lang/editaddresses.template") or
      openwebmailerror("$lang_err{'couldnt_open'} editaddresses.template");
   while (<EDITABOOKTEMPLATE>) {
      $html .= $_;
   }
   close (EDITABOOKTEMPLATE);

   $html = applystyle($html);

   if ( -f "$folderdir/.address.book" ) {
      open (ABOOK,"$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
      while (<ABOOK>) {
         ($name, $email, $note) = split(/:/, $_, 3);
         chomp($email); chomp($note);
         $addresses{"$name"} = $email;
         $notes{"$name"}=$note;
      }
      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");
   }
   my $abooksize = ( -s "$folderdir/.address.book" ) || 0;
   my $freespace = int($maxabooksize - ($abooksize/1024) + .5);

   if ( $global_addressbook ne "" && -f "$global_addressbook" ) {
      if (open (ABOOK,"$global_addressbook") ) {
         while (<ABOOK>) {
            ($name, $email, $note) = split(/:/, $_, 3);
            chomp($email);
            $globaladdresses{"$name"} = $email;
            $globalnotes{"$name"} = $note;
         }
         close (ABOOK);
      }
   }

   printheader();

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace/g;

   if ( param("message_id") ) {
      $temphtml = "<a href=\"$scripturl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   } else {
      $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   }
   $temphtml .= "<a href=\"$prefsurl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$imagedir_url/import.gif\" border=\"0\" ALT=\"$lang_text{'importadd'}\"></a>&nbsp;";
   $temphtml .= "<a href=\"$prefsurl?action=exportabook&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$imagedir_url/export.gif\" border=\"0\" ALT=\"$lang_text{'exportadd'}\"></a>&nbsp;";
   $temphtml .= "<a href=\"$prefsurl?action=clearaddress&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\" onclick=\"return confirm('$lang_text{'clearadd'}?')\"><IMG SRC=\"$imagedir_url/clearaddress.gif\" border=\"0\" ALT=\"$lang_text{'clearadd'}\"></a>";

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = startform(-action=>$prefsurl,
                         -name=>'newaddress') .
               hidden(-name=>'action',
                      -value=>'addaddress',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -value=>$thissession,
                      -override=>'1') .
               hidden(-name=>'sort',
                      -default=>$sort,
                      -override=>'1') .
               hidden(-name=>'firstmessage',
                      -default=>$firstmessage,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');

   $html =~ s/\@\@\@STARTADDRESSFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'realname',
                         -default=>'',
                         -size=>'20',
                         -override=>'1');

   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'email',
                         -default=>'',
                         -size=>'30',
                         -override=>'1');
   $temphtml .= "<a href=\"Javascript:GoAddressWindow('email')\">&nbsp;<IMG SRC=\"$imagedir_url/group.gif\" border=\"0\" ALT=\"$lang_text{'group'}\"></a>";

   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'note',
                         -default=>'',
                         -size=>'20',
                         -override=>'1');
   $html =~ s/\@\@\@NOTEFIELD\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'addmod'}");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};

   foreach my $key (sort { uc($a) cmp uc($b) } (keys %addresses)) {
      my ($namestr, $emailstr, $notestr)=($key, $addresses{$key}, $notes{$key});
      $namestr=substr($namestr, 0, 25)."..." if (length($namestr)>30);
      $emailstr=substr($emailstr, 0, 35)."..." if (length($emailstr)>40);
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor width="150"><a href="Javascript:Update('$key','$addresses{$key}','$notes{$key}')">$namestr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="250"><a href="$scripturl?action=composemessage&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$addresses{$key}">$emailstr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="150">$notestr</td>|;

      $temphtml .= start_form(-action=>$prefsurl);
      $temphtml .= hidden(-name=>'action',
                          -value=>'deleteaddress',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>$messageid,
                          -override=>'1');
      $temphtml .= hidden(-name=>'realname',
                          -value=>$key,
                          -override=>'1');
      $temphtml .= "<td bgcolor=$bgcolor align=\"center\" width=\"80\">";
      $temphtml .= submit("$lang_text{'delete'}");
      $temphtml .= '</td></tr>';
      $temphtml .= end_form();
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   my @sortkeys=sort { uc($a) cmp uc($b) } (keys %globaladdresses);
   if ($#sortkeys >= 0) {
      $temphtml .= "<tr><td colspan=\"4\">&nbsp;</td></tr>\n";
      $temphtml .= "<tr><td colspan=\"4\" bgcolor=$style{columnheader}><B>$lang_text{globaladdressbook}</B> ($lang_text{readonly})</td></tr>\n";
   }
   foreach my $key (@sortkeys) {
      my ($namestr, $emailstr, $notestr)=($key, $globaladdresses{$key}, $globalnotes{$key});
      $namestr=substr($namestr, 0, 25)."..." if (length($namestr)>30);
      $emailstr=substr($emailstr, 0, 35)."..." if (length($emailstr)>40);
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor width="150"><a href="Javascript:Update('$key','$globaladdresses{$key}','$globalnotes{$key}')">$namestr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="250"><a href="$scripturl?action=composemessage&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$addresses{$key}">$emailstr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="150">$notestr</td>|;

      $temphtml .= "<td bgcolor=$bgcolor align=\"center\" width=\"80\">";
      $temphtml .= "-----";
      $temphtml .= '</td></tr>';

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/;

   $html =~ s/\@\@\@SESSIONID\@\@\@/$thissession/g;

   print $html;

   printfooter();
}
################### END EDITADDRESSES ########################

################### MODADDRESS ##############################
sub modaddress {
   verifysession();

   my $mode = shift;
   my ($realname, $address, $ussrnote);
   $realname = param("realname") || '';
   $address = param("email") || '';
   $usernote = param("note") || '';
   $realname =~ s/://;
   $realname =~ s/^\s*//; # strip beginning and trailing spaces from hash key
   $realname =~ s/\s*$//;
   $address =~ s/[#&=\?]//g;
   $usernote =~ s/^\s*//; # strip beginning and trailing spaces
   $usernote =~ s/\s*$//;

   if (($realname && $address) || (($mode eq 'delete') && $realname) ) {
      my %addresses;
      my %notes;
      my ($name,$email,$note);
      if ( -f "$folderdir/.address.book" ) {
         my $abooksize = ( -s "$folderdir/.address.book" );
         if ( (($abooksize + length($realname) + length($address) + 2) >= ($maxabooksize * 1024) ) && ($mode ne "delete") ) {
            openwebmailerror("$lang_err{'abook_toobig'} <a href=\"$prefsurl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid\">$lang_err{'back'}</a>
                          $lang_err{'tryagain'}");
         }
         filelock("$folderdir/.address.book", LOCK_EX|LOCK_NB) or
            openwebmailerror("$lang_err{'couldnt_lock'} .address.book!");
         open (ABOOK,"+<$folderdir/.address.book") or
            openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
         while (<ABOOK>) {
            ($name, $email, $note) = split(/:/, $_, 3);
            chomp($email); chomp($note);
            $addresses{"$name"} = $email;
            $notes{"$name"} = $note;
         }
         if ($mode eq 'delete') {
            delete $addresses{"$realname"};
         } else {
            $addresses{"$realname"} = $address;
            if ($usernote ne '') { # overwrite old note only if new one is not null
               $notes{"$realname"} = $usernote;
            }
         }
         seek (ABOOK, 0, 0) or
            openwebmailerror("$lang_err{'couldnt_seek'} .address.book!");

         foreach my $key (sort { uc($a) cmp uc($b) } (keys %addresses)) {
            print ABOOK "$key:$addresses{$key}:$notes{$key}\n";
         }
         truncate(ABOOK, tell(ABOOK));
         close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");
         filelock("$folderdir/.address.book", LOCK_UN);
      } else {
         open (ABOOK, ">$folderdir/.address.book" ) or
            openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
         print ABOOK "$realname:$address:$usernote\n";
         close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");
      }
   }

#   print "Location: $prefsurl?action=editaddresses&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&amp;message_id=$escapedmessageid\n\n";
   editaddresses();
}
################## END MODADDRESS ###########################

################## CLEARADDRESS ###########################
sub clearaddress {
   verifysession();

   if ( -f "$folderdir/.address.book" ) {
      open (ABOOK, ">$folderdir/.address.book") or
         openwebmailerror ("$lang_err{'couldnt_open'} $folderdir/.address.book!");
      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.address.book!");
   }

#   print "Location: $prefsurl?action=editaddresses&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&amp;message_id=$escapedmessageid\n\n";
   editaddresses();
}
################## END MODADDRESS ###########################

#################### EDITPOP3 ###########################
sub editpop3 {
   verifysession();

   my %account;
   my ($name, $pass, $host, $del);

   my $html = '';
   my $temphtml;

   open (EDITPOP3BOOKTEMPLATE, "$openwebmaildir/templates/$lang/editpop3.template") or
      openwebmailerror("$lang_err{'couldnt_open'} editpop3.template");
   while (<EDITPOP3BOOKTEMPLATE>) {
      $html .= $_;
   }
   close (EDITPOP3BOOKTEMPLATE);

   $html = applystyle($html);

   if ( -f "$folderdir/.pop3.book" ) {
      open (POP3BOOK,"$folderdir/.pop3.book") or
         openwebmailerror("$lang_err{'couldnt_open'} .pop3.book!");
      while (<POP3BOOK>) {
      	 chomp($_);
         ($host, $name, $pass, $del) = split(/:/, $_);
         $account{"$host:$name"} = "$host:$name:$pass:$del";
      }
      close (POP3BOOK) or openwebmailerror("$lang_err{'couldnt_close'} .pop3.book!");
   }
   my $abooksize = ( -s "$folderdir/.pop3.book" ) || 0;
   my $freespace = int($maxabooksize - ($abooksize/1024) + .5);

   printheader();

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace/g;

   if ( param("message_id") ) {
      $temphtml = "<a href=\"$scripturl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   } else {
      $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   }
   $temphtml .= "<a href=\"$scripturl?action=retrpop3s&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$imagedir_url/pop3.gif\" border=\"0\" ALT=\"$lang_text{'retr_pop3s'}\"></a>";

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = startform(-action=>$prefsurl,
                         -name=>'newpop3') .
               hidden(-name=>'action',
                      -value=>'addpop3',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -value=>$thissession,
                      -override=>'1') .
               hidden(-name=>'sort',
                      -default=>$sort,
                      -override=>'1') .
               hidden(-name=>'firstmessage',
                      -default=>$firstmessage,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');

   $html =~ s/\@\@\@STARTADDRESSFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'host',
                         -default=>'',
                         -size=>'32',
                         -override=>'1');

   $html =~ s/\@\@\@HOSTFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'name',
                         -default=>'',
                         -size=>'16',
                         -override=>'1');

   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'pass',
                         -default=>'',
                         -size=>'12',
                         -override=>'1');

   $html =~ s/\@\@\@PASSFIELD\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'del',
                  -value=>'1',
                  -label=>'');

   $html =~ s/\@\@\@DELFIELD\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'addmod'}");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   #foreach my $key (sort { uc($a) cmp uc($b) } (keys %account)) 
   foreach (sort values %account) {
      ($host, $name, $pass, $del) = split(/:/, $_);
      $temphtml .= "<tr>
                    <td bgcolor=$bgcolor><a href=\"$scripturl?action=retrpop3&name=$name&host=$host&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&\">$host</a></td>
      		    <td align=\"center\" bgcolor=$bgcolor><a href=\"Javascript:Update('$name','$pass','$host','$del')\">$name</a></td>
                    <td align=\"center\" bgcolor=$bgcolor>\*\*\*\*\*\*</td>
                    <td align=\"center\" bgcolor=$bgcolor>";
      if ( $del == 1) {
      	 $temphtml .= $lang_text{'delete'};
      }
      else {
      	 $temphtml .= $lang_text{'reserve'};
      }
      $temphtml .= "</td>";

      $temphtml .= start_form(-action=>$prefsurl);
      $temphtml .= hidden(-name=>'action',
                          -value=>'deletepop3',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>$messageid,
                          -override=>'1');
      $temphtml .= hidden(-name=>'name',
                          -value=>$name,
                          -override=>'1');
      $temphtml .= hidden(-name=>'host',
                          -value=>$host,
                          -override=>'1');
      $temphtml .= "<td bgcolor=$bgcolor align=\"center\" width=\"100\">";
      $temphtml .= submit("$lang_text{'delete'}");
      $temphtml .= '</td></tr>';
      $temphtml .= end_form();
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/;
   print $html;

   printfooter();
}
################### END EDITPOP3 ########################

################### MODPOP3 ##############################
sub modpop3 {
   verifysession();

   my $mode = shift;
   my ($host, $name, $pass, $del, $lastid);
   $host = param("host") || '';
   $name = param("name") || '';
   $pass = param("pass") || '';
   $del = param("del") || 0;
   $lastid = "none";
   
   # strip beginning and trailing spaces from hash key
   $host =~ s/://;
   $host =~ s/^\s*//; 
   $host =~ s/\s*$//;
   $host =~ s/[#&=\?]//g;
   
   $name =~ s/://;
   $name =~ s/^\s*//; 
   $name =~ s/\s*$//;
   $name =~ s/[#&=\?]//g;
   
   $pass =~ s/://;
   $pass =~ s/^\s*//; 
   $pass =~ s/\s*$//;

   if (($host && $name && $pass) || (($mode eq 'delete') && $host && $name) ) {
      my %account;
      
      if ( -f "$folderdir/.pop3.book" ) {
         my $pop3booksize = ( -s "$folderdir/.pop3.book" );
         if ( (($pop3booksize + length($host) + length($name)+ length($pass)+ 3) >= ($maxabooksize * 1024) ) && ($mode ne "delete") ) {
            openwebmailerror("$lang_err{'abook_toobig'} <a href=\"$prefsurl?action=editpop3&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid\">$lang_err{'back'}</a>
                          $lang_err{'tryagain'}");
         }
         filelock("$folderdir/.pop3.book", LOCK_EX|LOCK_NB) or
            openwebmailerror("$lang_err{'couldnt_lock'} .pop3.book!");
         open (POP3BOOK,"+<$folderdir/.pop3.book") or
            openwebmailerror("$lang_err{'couldnt_open'} .pop3.book!");
         while (<POP3BOOK>) {
         	my ($ehost,$ename,$epass,$edel,$elastid);
         	chomp($_);
            ($ehost, $ename, $epass, $edel, $elastid) = split(/:/, $_);
            $account{"$ehost:$ename"}="$ehost:$ename:$epass:$edel:$elastid";
         }
         if ($mode eq 'delete') {
            delete $account{"$host:$name"};
         } else {
            $account{"$host:$name"}="$host:$name:$pass:$del:$lastid";
         }
         seek (POP3BOOK, 0, 0) or
            openwebmailerror("$lang_err{'couldnt_seek'} .pop3.book!");
         	
         foreach (values %account) {
            print POP3BOOK "$_\n";
         }
         truncate(POP3BOOK, tell(POP3BOOK));
         close (POP3BOOK) or openwebmailerror("$lang_err{'couldnt_close'} .pop3.book!");
         filelock("$folderdir/.pop3.book", LOCK_UN);
      } else {
         open (POP3BOOK, ">$folderdir/.pop3.book" ) or
            openwebmailerror("$lang_err{'couldnt_open'} .pop3.book!");
         print POP3BOOK "$host:$name:$pass:$del:$lastid\n";
         close (POP3BOOK) or openwebmailerror("$lang_err{'couldnt_close'} .pop3.book!");
      }
   }

#   print "Location: $prefsurl?action=editpop3&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&amp;message_id=$escapedmessageid\n\n";
   editpop3();
}
################## END MODPOP3 ###########################

#################### EDITFILTER ###########################
sub editfilter {
   verifysession();

   #### variables ####
   my $html = '';
   my $temphtml;
   my @validfolders;
   my @filterrules=();
   my @globalfilterrules=();

   #### UI: header ####
   printheader();

   #### UI: between header/footer ####
   open (EDITFILTERTEMPLATE, "$openwebmaildir/templates/$lang/editfilter.template") or
       openwebmailerror("$lang_err{'couldnt_open'} editfilter.template");
   while (<EDITFILTERTEMPLATE>) {
       $html .= $_;
   }
   close (EDITFILTERTEMPLATE);

   ## user-prefer-UI-style ##
   $html = applystyle($html);
   
   ## replace @@@FREESPACE@@@ ##
   my $abooksize = ( -s "$folderdir/.filter.book" ) || 0;
   my $freespace = int($maxabooksize - ($abooksize/1024) + .5);
   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace/g;
   
   ## replace @@@MENUBARLINKS@@@ ##
   if ( param("message_id") ) {
      $temphtml = "<a href=\"$scripturl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";
   } else {
      $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder\"><IMG SRC=\"$imagedir_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";
   }
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   ## replace @@@STARTFILTERFORM@@@ ##
   $temphtml = startform(-action=>$prefsurl,
                         -name=>'newfilter') .
                     hidden(-name=>'action',
                            -value=>'addfilter',
                            -override=>'1') .
                     hidden(-name=>'sessionid',
                            -value=>$thissession,
                            -override=>'1') .
                     hidden(-name=>'sort',
                            -default=>$sort,
                            -override=>'1') .
                     hidden(-name=>'firstmessage',
                            -default=>$firstmessage,
                            -override=>'1') .
                     hidden(-name=>'folder',
                            -default=>$folder,
                            -override=>'1');
                     hidden(-name=>'message_id',
                            -default=>$messageid,
                            -override=>'1');
   $html =~ s/\@\@\@STARTFILTERFORM\@\@\@/$temphtml/;

   ## replace @@@ENDFILTERFORM@@@ ##
   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFILTERFORM\@\@\@/$temphtml/;

   ## replace @@@PRIORITYMENU@@@ ##
   $temphtml = popup_menu(-name=>'priority',
                          -values=>['01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20'],
                          -default=>'10');
   $html =~ s/\@\@\@PRIORITYMENU\@\@\@/$temphtml/;

   ## replace @@@RULEMENU@@@ ##
   %labels = ('from'=>$lang_text{'from'},
                        'to'=>$lang_text{'to'},
                        'subject'=>$lang_text{'subject'},
                        'smtprelay'=>$lang_text{'smtprelay'},
                        'header'=>$lang_text{'header'},
                        'body'=>$lang_text{'body'},
                        'attfilename'=>$lang_text{'attfilename'});
   $temphtml = popup_menu(-name=>'rules',
                          -values=>['from', 'to', 'subject', 'smtprelay', 'header', 'body' ,'attfilename'],
                          -labels=>\%labels);
   $html =~ s/\@\@\@RULEMENU\@\@\@/$temphtml/;

   ## replace @@@INCLUDEMENU@@@ ##
   my %labels = ('include'=>$lang_text{'include'},
                        'exclude'=>$lang_text{'exclude'});
   $temphtml = popup_menu(-name=>'include',
                          -values=>['include', 'exclude'],
                          -labels=>\%labels);
   $html =~ s/\@\@\@INCLUDEMENU\@\@\@/$temphtml/;

   ## replace @@@TEXTFIELD@@@ ##
   $temphtml = textfield(-name=>'text',
                         -default=>'',
                         -size=>'26',
                         -override=>'1');
   $html =~ s/\@\@\@TEXTFIELD\@\@\@/$temphtml/;

   ## replace @@@OPMENU@@@ ##
   my %labels = ('move'=>$lang_text{'move'},
                 'copy'=>$lang_text{'copy'});
   $temphtml = popup_menu(-name=>'op',
                          -values=>['move', 'copy'],
                          -labels=>\%labels);
   $html =~ s/\@\@\@OPMENU\@\@\@/$temphtml/;

   ## replace @@@FOLDERMENU@@@ ##
   @validfolders = @{&getfolders()};
   push(@validfolders, 'DELETE');
   foreach (@validfolders) {
      if ( defined($lang_folders{$_}) ) {
          $labels{$_} = $lang_folders{$_};
      } else { 
         $labels{$_} = $_; 
      }
   }
   $temphtml = popup_menu(-name=>'destination',
                          -values=>[@validfolders],
                          -default=>'mail-trash',
                          -labels=>\%labels);
   $html =~ s/\@\@\@FOLDERMENU\@\@\@/$temphtml/;
   
   ## replace @@@ENABLECHECKBOX@@@ ##
   $temphtml = checkbox(-name=>'enable',
                        -value=>'1',
                        -checked=>"checked",
                        -label=>'');

   $html =~ s/\@\@\@ENABLECHECKBOX\@\@\@/$temphtml/;
   
   ## replace @@@ADDBUTTON@@@ ##
   $temphtml = submit("$lang_text{'addmod'}");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   ## replace @@@FILTERRULES@@@ ##
   if ( -f "$folderdir/.filter.book" ) {
      open (FILTER,"$folderdir/.filter.book") or
         openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
      while (<FILTER>) {
         chomp($_);
         push (@filterrules, $_);
      }
      close (FILTER) or openwebmailerror("$lang_err{'couldnt_close'} .filter.book!");
   }
   if ( $global_filterbook ne "" && -f "$global_filterbook" ) {
      if ( open (FILTER, "$global_filterbook") ) { 
         while (<FILTER>) {
            chomp($_);
            push (@globalfilterrules, $_);
         }
         close (FILTER);
      }
   }

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach my $line (@filterrules) {
      my ($priority, $rules, $include, $text, $op, $destination, $enable) = split(/\@\@\@/, $line);
      if ( $enable eq '') {	# compatible with old format
         ($priority, $rules, $include, $text, $destination, $enable) = split(/\@\@\@/, $line);
         $op='move';
      }
            
      $temphtml .= "<tr>\n".
                   "<td bgcolor=$bgcolor align=center>$priority</td>\n".
                   "<td bgcolor=$bgcolor align=center>$lang_text{$rules}</td>\n".
                   "<td bgcolor=$bgcolor align=center>$lang_text{$include}</td>\n".
                   "<td bgcolor=$bgcolor align=center><a href=\"Javascript:Update('$priority','$rules','$include','$text','$op','$destination','$enable')\">$text</a></td>\n";
      if ($destination eq 'INBOX') {
         $temphtml .= "<td bgcolor=$bgcolor align=center>-----</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{$op}</td>\n";
      }
      if (defined($lang_folders{$destination})) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_folders{$destination}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$destination</td>\n";
      }
      if ($enable == 1) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'enable'}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'disable'}</td>\n";
      }
      $temphtml .= start_form(-action=>$prefsurl);
      $temphtml .= "<td bgcolor=$bgcolor align=center>";
      $temphtml .= hidden(-name=>'action',
                          -value=>'deletefilter',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>$messageid,
                          -override=>'1');
      $temphtml .= hidden(-name=>'rules',
                          -value=>$rules,
                          -override=>'1');
      $temphtml .= hidden(-name=>'include',
                          -value=>$include,
                          -override=>'1');
      $temphtml .= hidden(-name=>'text',
                          -value=>$text,
                          -override=>'1');
      $temphtml .= hidden(-name=>'destination',
                          -value=>$destination,
                          -override=>'1');
      $temphtml .= submit("$lang_text{'delete'}");
      $temphtml .= "</td>";
      $temphtml .= "</tr>";
      $temphtml .= end_form();
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   if ($#globalfilterrules >= 0) {
      $temphtml .= "<tr><td colspan=\"8\">&nbsp;</td></tr>\n";
      $temphtml .= "<tr><td colspan=\"8\" bgcolor=$style{columnheader}><B>$lang_text{globalfilterrule}</B> ($lang_text{readonly})</td></tr>\n";
   }
   foreach $line (@globalfilterrules) {
      my ($priority, $rules, $include, $text, $op, $destination, $enable) = split(/\@\@\@/, $line);
      if ( $enable eq '') {	# compatible with old format
         ($priority, $rules, $include, $text, $destination, $enable) = split(/\@\@\@/, $line);
         $op='move';
      }
            
      $temphtml .= "<tr>\n".
                   "<td bgcolor=$bgcolor align=center>$priority</td>\n".
                   "<td bgcolor=$bgcolor align=center>$lang_text{$rules}</td>\n".
                   "<td bgcolor=$bgcolor align=center>$lang_text{$include}</td>\n".
                   "<td bgcolor=$bgcolor align=center><a href=\"Javascript:Update('$priority','$rules','$include','$text','$op','$destination','$enable')\">$text</a></td>\n".
                   "<td bgcolor=$bgcolor align=center>$lang_text{$op}</td>\n";
      if (defined($lang_folders{$destination})) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_folders{$destination}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$destination</td>\n";
      }
      if ($enable == 1) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'enable'}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'disable'}</td>\n";
      }
      $temphtml .= "<td bgcolor=$bgcolor align=center>";
      $temphtml .= "-----";
      $temphtml .= "</td>";
      $temphtml .= "</tr>";
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   $html =~ s/\@\@\@FILTERRULES\@\@\@/$temphtml/;

   print $html;
   
   #### UI: footer ####
   printfooter();
}
################### END EDITFILTER ########################

################### MODFILTER ##############################
sub modfilter {
   verifysession();
    
   ## get parameters ##
   my $mode = shift;
   my ($priority, $rules, $include, $text, $op, $destination, $enable);
   $priority = param("priority") || '';
   $rules = param("rules") || '';
   $include = param("include") || '';
   $text = param("text") || '';
   $text =~ s/^[\s\@]+//;
   $text =~ s/[\@\s]+$//;
   $text =~ s/\@\@\@//g;
   $op = param("op") || 'move';
   $destination = param("destination") || '';
   $destination =~ s/\.\.+//g;
   $destination =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   $enable = param("enable") || 0;
   
   ## add mode -> can't have null $rules, null $text, null $destination ##
   ## delete mode -> can't have null $filter ##
   if( ($rules && $include && $text && $destination && $priority) || 
       (($mode eq 'delete') && ($rules && $include && $text && $destination)) ) {
      my %filterrules;
      if ( -f "$folderdir/.filter.book" ) {
         filelock("$folderdir/.filter.book", LOCK_EX|LOCK_NB) or
            openwebmailerror("$lang_err{'couldnt_lock'} .filter.book!");
         open (FILTER,"+<$folderdir/.filter.book") or
            openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
         while(<FILTER>) {
            my ($epriority,$erules,$einclude,$etext,$eop,$edestination,$eenable);
            my $line=$_; chomp($line);
            ($epriority,$erules,$einclude,$etext,$eop,$edestination,$eenable) = split(/\@\@\@/, $line);
            if ($eenable eq '') {	# compatible with old format
               ($epriority,$erules,$einclude,$etext,$edestination,$eenable) = split(/\@\@\@/, $line);
               $eop='move';
            }
            $filterrules{"$erules\@\@\@$einclude\@\@\@$etext\@\@\@$edestination"}="$epriority\@\@\@$erules\@\@\@$einclude\@\@\@$etext\@\@\@$eop\@\@\@$edestination\@\@\@$eenable";
         }
         if ($mode eq 'delete') {
            delete $filterrules{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"};
         } else {
            $filterrules{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$priority\@\@\@$rules\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable";
         }
         seek (FILTER, 0, 0) or
            openwebmailerror("$lang_err{'couldnt_seek'} .filter.book!");
   
         foreach (sort values %filterrules) {
            print FILTER "$_\n";
         }
         truncate(FILTER, tell(FILTER));
         close (FILTER) or openwebmailerror("$lang_err{'couldnt_close'} .filter.book!");         
         filelock("$folderdir/.filter.book", LOCK_UN);
      } else {
         open (FILTER, ">$folderdir/.filter.book" ) or
                  openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
         print FILTER "$priority\@\@\@$rules\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable\n";
         close (FILTER) or openwebmailerror("$lang_err{'couldnt_close'} .filter.book!");
      }
      
      ## remove .filter.check ##
      unlink("$folderdir/.filter.check");
   }
#   print "Location: $prefsurl?action=editfilter&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&amp;message_id=$escapedmessageid\n\n";
    editfilter();
}
################## END MODFILTER ###########################

###################### SAVEPREFS #########################
sub saveprefs {
   verifysession();

   if (! -d "$folderdir" ) {
      mkdir ("$folderdir", oct(700)) or
         openwebmailerror("$lang_err{'cant_create_dir'} $folderdir");
   }
   open (CONFIG,">$folderdir/.openwebmailrc") or
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.openwebmailrc!");
   foreach my $key (qw(language realname fromname domainname replyto 
                       style sort headers headersperpage defaultdestination
                       filter_repeatlimit filter_fakedsmtp 
                       newmailsound autopop3 autoemptytrash)) {
      my $value = param("$key") || '';

      $value =~ s/\.\.+//g;
      $value =~ s/[=\n\/\`\|\<\>;]//g; # remove dangerous char
      if ($key eq 'language') {
         my $validlanguage=0;
         my $currlanguage;
         foreach $currlanguage (@availablelanguages) {
            if ($value eq $currlanguage) {
               print CONFIG "$key=$value\n";
               last;
            }
         }
      } elsif ($key eq 'fromname') {
         $value =~ s/\s+//g; # Spaces will just screw people up.
         print CONFIG "$key=$value\n";
      } elsif ($key eq 'filter_repeatlimit') {
         # if repeatlimit changed, redo filtering maybe needed
         if ( $value != $prefs{'filter_repeatlimit'} ) { 
            unlink("$folderdir/.filter.check");
         }
         print CONFIG "$key=$value\n";
      } elsif ( $key eq 'filter_fakedsmtp' ||
                $key eq 'newmailsound' ||
                $key eq 'autopop3' ||
                $key eq 'autoemptytrash') {
         $value=0 if ($value eq '');
         print CONFIG "$key=$value\n";
      } else {
         print CONFIG "$key=$value\n";
      }
   }
   close (CONFIG) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.openwebmailrc!");

   open (SIGNATURE,">$folderdir/.signature") or
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.signature!");
   my $value = param("signature") || '';
   if (length($value) > 500) {  # truncate signature to 500 chars
      $value = substr($value, 0, 500);
   }
   print SIGNATURE $value;
   close (SIGNATURE) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.signature!");
   printheader();

   my $html = '';
   my $temphtml;

   open (PREFSSAVEDTEMPLATE, "$openwebmaildir/templates/$lang/prefssaved.template") or
      openwebmailerror("$lang_err{'couldnt_open'} prefssaved.template!");
   while (<PREFSSAVEDTEMPLATE>) {
      $html .= $_;
   }
   close (PREFSSAVEDTEMPLATE);

   $html = applystyle($html);

   $temphtml = startform(-action=>"$scripturl") .
               hidden(-name=>'action',
                      -default=>'displayheaders',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'sort',
                      -default=>$sort,
                      -override=>'1') .
               hidden(-name=>'firstmessage',
                      -default=>$firstmessage,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1') .
               submit("$lang_text{'continue'}") .
               end_form();
   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;
   print $html;

   printfooter();
}
##################### END SAVEPREFS ######################

#################### ADDRESSBOOK #######################
sub addressbook {
   verifysession();

   if ( $CGI::VERSION>=2.57) {
      print header(-pragma=>'no-cache',
                   -charset=>$lang_charset);
   } else {
      print header(-pragma=>'no-cache');
   }
   print start_html(-"title"=>"$lang_text{'abooktitle'}",
                    -BGCOLOR=>'#FFFFFF',
                    -BACKGROUND=>$bg_url);
   my %addresses=();
   my %globaladdresses=();
   my ($name, $email);
   my $form=param("form");
   my $field=param("field");
   my $preexisting = param("preexisting") || '';
   $preexisting =~ s/(\s+)?,(\s+)?/,/g;
   print startform(-action=>"javascript:Update('" . $field . "')",
                   -name=>'addressbook'
                  );
   print '<table border="0" align="center" width="90%" cellpadding="0" cellspacing="0">';

   if (defined($lang_text{$field})) {
      print '<tr><td colspan="2" bgcolor=',$style{"titlebar"},' align="left">',
      '<font color=',$style{"titlebar_text"},' face=',$style{"fontface"},' size="3"><b>',uc($lang_text{$field}),": $lang_text{'abook'}</b></font>",
      '</td></tr>';
   } else {
      print '<tr><td colspan="2" bgcolor=',$style{"titlebar"},' align="left">',
      '<font color=',$style{"titlebar_text"},' face=',$style{"fontface"},' size="3"><b>',uc($field),": $lang_text{'abook'}</b></font>",
      '</td></tr>';
   }
   my $bgcolor = $style{"tablerow_dark"};
   if ( -f "$folderdir/.address.book" ) {
      open (ABOOK,"$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
      while (<ABOOK>) {
         ($name, $email) = (split(/:/, $_, 3))[0,1];
         chomp($email);
         $addresses{"$name"} = $email;
      }
      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");

      foreach my $key (sort(keys %addresses)) {
         print "<tr><td bgcolor=$bgcolor width=\"20\"><input type=\"checkbox\" name=\"to\" value=\"",
         $addresses{"$key"}, '"';
         if ($preexisting =~ s/\Q$addresses{"$key"}\E,?//g) {
            print " checked";
         }
         print "></td><td width=\"100%\" bgcolor=$bgcolor>$key</td></tr>\n";
         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"};
         } else {
            $bgcolor = $style{"tablerow_dark"};
         }
      }
   }

   if ( $global_addressbook ne "" && -f "$global_addressbook" ) {
      if (open (ABOOK,"$global_addressbook")) {
         while (<ABOOK>) {
            ($name, $email) = (split(/:/, $_, 3))[0,1];
            chomp($email);
            $globaladdresses{"$name"} = $email;
         }
         close (ABOOK);
      }
      foreach my $key (sort(keys %globaladdresses)) {
         print "<tr><td bgcolor=$bgcolor width=\"20\"><input type=\"checkbox\" name=\"to\" value=\"",
         $globaladdresses{"$key"}, '"';
         if ($preexisting =~ s/\Q$globaladdresses{"$key"}\E,?//g) {
            print " checked";
         }
         print "></td><td width=\"100%\" bgcolor=$bgcolor>$key</td></tr>\n";
         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"};
         } else {
            $bgcolor = $style{"tablerow_dark"};
         }
      }
   }

   print '</td></tr><tr><td align="center" colspan="2" bgcolor=',$style{"tablerow_dark"},'>';
   print '<input type="hidden" name="remainingstr" value="', $preexisting, '">';
   print '<input type="submit" name="mailto.x" value="OK"> &nbsp;&nbsp;';
   print '<input type="button" value="Cancel" onClick="window.close();">';
   print '</td></tr></table>';
   print qq|<script language="JavaScript">
      <!--
      function Update(whichfield)
      {
         var e2 = document.addressbook.remainingstr.value;
         for (var i = 0; i < document.addressbook.elements.length; i++)
         {
            var e = document.addressbook.elements[i];
            if (e.name == "to" && e.checked)
            {
               if (e2)
                  e2 += ",";
               e2 += e.value;
            }
         }
         window.opener.document.$form.$field.value = e2;
         window.close();
      }
      //-->
      </script>|;
   print end_form();
   print end_html();
}
################## END ADDRESSBOOK #####################
