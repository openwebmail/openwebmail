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
umask(0002); # make sure the openwebmail group can write

require "etc/openwebmail.conf";
require "pop3mail.pl";

my $thissession = param("sessionid") || '';
my $user = $thissession || '';
$user =~ s/\-session\-0.*$//; # Grab userid from sessionid
($user =~ /^(.+)$/) && ($user = $1);  # untaint $user...

my ($login, $pass, $uid, $gid, $homedir);
if ($user) {
   if (($homedirspools eq 'yes') || ($homedirfolders eq 'yes')) {
      ($login, $pass, $uid, $gid, $homedir) = (getpwnam($user))[0,1,2,3,7] or
         openwebmailerror("User $user doesn't exist!");
      $gid = getgrnam('mail');
   }
}

my %prefs = %{&readprefs};
my %style = %{&readstyle};

my $lang = $prefs{'language'} || $defaultlanguage;
($lang =~ /^(..)$/) && ($lang = $1);
require "etc/lang/$lang";
$lang_charset ||= 'iso-8859-1';

my $firstmessage;
if (param("firstmessage")) {
   $firstmessage = param("firstmessage");
} else {
   $firstmessage = 1;
}

my $sort;
if (param("sort")) {
   $sort = param("sort");
} else {
   $sort = 'date';
}

my $folderdir;
if ( $homedirfolders eq 'yes') {
   $folderdir = "$homedir/$homedirfolderdirname";
} else {
   $folderdir = "$userprefsdir/$user";
}

my $folder;
if (param("folder")) {
   $folder = param("folder");
} else {
   $folder = "INBOX";
}
my $printfolder = $lang_folders{$folder} || $folder;
my $escapedfolder = CGI::escape($folder);

my $messageid;
if (param("message_id")) {
   $messageid=param("message_id");
}
my $escapedmessageid=CGI::escape($messageid);

my $firsttimeuser = param("firsttimeuser") || ''; # Don't allow cancel if 'yes'

$sessiontimeout = $sessiontimeout/60/24; # convert to format expected by -M

# once we print the header, we don't want to do it again if there's an error
my $headerprinted = 0;
my $validsession = 0;

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
      } elsif ($action eq "addressbook") {
         addressbook();
      } elsif ($action eq "editaddresses") {
         editaddresses();
      } elsif ($action eq "addaddress") {
         modaddress("add");
      } elsif ($action eq "deleteaddress") {
         modaddress("delete");
      } elsif ($action eq "importabook") {
         importabook();
      } elsif ($action eq "editpop3") {
         editpop3();
      } elsif ($action eq "addpop3") {
         modpop3("add");
      } elsif ($action eq "deletepop3") {
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
   opendir (STYLESDIR, $stylesdir) or
      openwebmailerror("$lang_err{'couldnt_open'} $stylesdir directory for reading!");
   while (defined(my $currentstyle = readdir(STYLESDIR))) {
      unless ($currentstyle =~ /\./) {
         push (@styles, $currentstyle);
      }
   }
   @styles = sort(@styles);
   closedir(STYLESDIR) or
      openwebmailerror("$lang_err{'couldnt_close'} $stylesdir!");
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

   $temphtml = popup_menu(-name=>'numberofmessages',
                          -"values"=>['10','20','30','40','50','100','500','1000'],
                          -default=>$prefs{"numberofmessages"} || $numberofheaders,
                          -override=>'1');

   $html =~ s/\@\@\@NUMBEROFMESSAGES\@\@\@/$temphtml/;

   my %headerlabels = ('simple'=>$lang_text{'simplehead'},
                       'all'=>$lang_text{'allhead'}
                      );
   $temphtml = popup_menu(-name=>'headers',
                          -"values"=>['simple','all'],
                          -default=>$prefs{"headers"} || 'simple',
                          -labels=>\%headerlabels,
                          -override=>'1');

   $html =~ s/\@\@\@HEADERSMENU\@\@\@/$temphtml/;

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
###################### END MAIN ##############################

#################### EDITFOLDERS ###########################
sub editfolders {
   verifysession();
   my @folders;
   opendir (FOLDERDIR, "$folderdir") or
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir!");
   while (defined(my $filename = readdir(FOLDERDIR))) {
### skip files started with ., which are openwebmail internal files (dbm, search caches)
      if ( $filename=~/^\./ ) {	
         next;
      }

      if ($homedirfolders eq 'yes') {
         unless ( ($filename eq 'saved-messages') ||
                  ($filename eq 'sent-mail') ||
                  ($filename eq 'mail-trash') ||
                  ($filename eq '.') ||
                  ($filename eq '..')
                ) {
            push (@folders, $filename);
         }
      } else {
         if ($filename =~ /^(.+)\.folder$/) {
            push (@folders, $1);
         }
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

   $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$escapedfolder\"><IMG SRC=\"$image_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";

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

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   my $currfolder;
   foreach $currfolder (sort (@folders)) {
      $temphtml .= "<tr><td align=\"center\" bgcolor=$bgcolor>$currfolder</td>";

      $temphtml .= start_form(-action=>$prefsurl,
                              -onSubmit=>"return confirm($lang_text{'folderconf'})");
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
      $temphtml .= "<td bgcolor=$bgcolor align=\"center\">";
      $temphtml .= submit("$lang_text{'delete'}");
      $temphtml .= '</td></tr>';
      $temphtml .= end_form();
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   $html =~ s/\@\@\@FOLDERS\@\@\@/$temphtml/;
   print $html;

   printfooter();
}
################### END EDITFOLDERS ########################

################### ADDFOLDER ##############################
sub addfolder {
   my $foldertoadd = param('foldername') || '';
   $foldertoadd =~ s/[\s|\.|\/|\\|\`|;|<|>]//g;
   unless ($homedirfolders eq 'yes') {
      $foldertoadd = uc($foldertoadd);
   }
   if (length($foldertoadd) > 16) {
      openwebmailerror("$lang_err{'foldername_long'}");
   }
   ($foldertoadd =~ /^(.+)$/) && ($foldertoadd = $1);
   unless ($homedirfolders eq 'yes') {
      $foldertoadd .= '.folder';
   }

   if ($foldertoadd eq "$user") {
      openwebmailerror("$lang_err{'cant_create_folder'}");
   }
   if ( -f "$folderdir/$foldertoadd" ) {
      openwebmailerror ("$lang_err{'folder_with_name'} $foldertoadd $lang_err{'already_exists'}");
   }

   if ( ($homedirfolders eq 'yes') && ($> == 0) ) {
      $) = $gid;
      $> = $uid;
      umask(0077); # make sure only owner can read/write
   }
   open (FOLDERTOADD, ">$folderdir/$foldertoadd") or
      openwebmailerror("$lang_err{'cant_create_folder'}");
   close (FOLDERTOADD) or openwebmailerror("$lang_err{'couldnt_close'} $foldertoadd!");
   print "Location: $prefsurl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
}
################### END ADDFOLDER ##########################

################### DELETEFOLDER ##############################
sub deletefolder {
   my $foldertodel = param('foldername') || '';
   $foldertodel =~ s/\.\.+//g;
   $foldertodel =~ s/[\/|\\|\`|;|<|>]//g;
   ($foldertodel =~ /^(.+)$/) && ($foldertodel = $1);
   unless ($homedirfolders eq 'yes') {
      $foldertodel .= '.folder';
   }
   if ( -f "$folderdir/$foldertodel" ) {
      unlink ("$folderdir/$foldertodel",
              "$folderdir/.$foldertodel.db",
	      "$folderdir/.$foldertodel.dir",
              "$folderdir/.$foldertodel.pag",
              "$folderdir/.$foldertodel.cache");              
   }
   print "Location: $prefsurl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
}
################### END DELETEFOLDER ##########################

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
      open (ABOOK,"+<$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
      unless (flock(ABOOK, LOCK_EX|LOCK_NB)) {
         openwebmailerror("$lang_err{'couldnt_lock'} .address.book!");
      }
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

      print "Location: $prefsurl?action=editaddresses&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&message_id=$escapedmessageid\n\n";

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

#################### EDITADDRESSES ###########################
sub editaddresses {
   verifysession();
   my %addresses;
   my ($name, $email);

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
         ($name, $email) = split(/:/, $_);
         chomp($email);
         $addresses{"$name"} = $email;
      }
      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");
   }
   my $abooksize = ( -s "$folderdir/.address.book" ) || 0;
   my $freespace = int($maxabooksize - ($abooksize/1024) + .5);

   printheader();

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace/g;

   if ( param("message_id") ) {
      $temphtml = "<a href=\"$scripturl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$image_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   } else {
      $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder\"><IMG SRC=\"$image_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   }
   $temphtml .= "<a href=\"$prefsurl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$image_url/import.gif\" border=\"0\" ALT=\"$lang_text{'importadd'}\"></a>";

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
                         -size=>'25',
                         -override=>'1');

   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'email',
                         -default=>'',
                         -size=>'35',
                         -override=>'1');

   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'addmod'}");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach my $key (sort { uc($a) cmp uc($b) } (keys %addresses)) {
      $temphtml .= "<tr><td bgcolor=$bgcolor width=\"200\">
                    <a href=\"Javascript:Update('$key','$addresses{$key}')\">
                    $key</a></td><td bgcolor=$bgcolor width=\"200\">
                    <a href=\"$scripturl?action=composemessage&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$addresses{$key}\">$addresses{$key}</a></td>";

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
################### END EDITADDRESSES ########################

################### MODADDRESS ##############################
sub modaddress {
   verifysession();
   my $mode = shift;
   my ($realname, $address);
   $realname = param("realname") || '';
   $address = param("email") || '';
   $realname =~ s/://;
   $realname =~ s/^\s*//; # strip beginning and trailing spaces from hash key
   $realname =~ s/\s*$//;
   $address =~ s/[#&=\?]//g;

   if (($realname && $address) || (($mode eq 'delete') && $realname) ) {
      my %addresses;
      my ($name,$email);
      if ( -f "$folderdir/.address.book" ) {
         my $abooksize = ( -s "$folderdir/.address.book" );
         if ( (($abooksize + length($realname) + length($address) + 2) >= ($maxabooksize * 1024) ) && ($mode ne "delete") ) {
            openwebmailerror("$lang_err{'abook_toobig'} <a href=\"$prefsurl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid\">$lang_err{'back'}</a>
                          $lang_err{'tryagain'}");
         }
         open (ABOOK,"+<$folderdir/.address.book") or
            openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
         unless (flock(ABOOK, LOCK_EX|LOCK_NB)) {
            openwebmailerror("$lang_err{'couldnt_lock'} .address.book!");
         }
         while (<ABOOK>) {
            ($name, $email) = split(/:/, $_);
            chomp($email);
            $addresses{"$name"} = $email;
         }
         if ($mode eq 'delete') {
            delete $addresses{"$realname"};
         } else {
            $addresses{"$realname"} = $address;
         }
         seek (ABOOK, 0, 0) or
            openwebmailerror("$lang_err{'couldnt_seek'} .address.book!");
         while ( ($name, $email) = each %addresses ) {
            print ABOOK "$name:$email\n";
         }
         truncate(ABOOK, tell(ABOOK));
         close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");
      } else {
         open (ABOOK, ">$folderdir/.address.book" ) or
            openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
         print ABOOK "$realname:$address\n";
         close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");
         chmod (0600, "$folderdir/.address.book");
         chown ($uid, $gid, "$folderdir/.address.book");
      }
   }

   print "Location: $prefsurl?action=editaddresses&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&amp;message_id=$escapedmessageid\n\n";
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
      $temphtml = "<a href=\"$scripturl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$image_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   } else {
      $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder\"><IMG SRC=\"$image_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a> &nbsp; &nbsp; ";
   }
   $temphtml .= "<a href=\"$scripturl?action=retrpop3s&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$image_url/pop3.gif\" border=\"0\" ALT=\"$lang_text{'retr_pop3s'}\"></a>";

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
      #<td bgcolor=$bgcolor width=\"200\"><a href=\"$scripturl?action=retrpop3&name=$name&host=$host&del=0&mbox=$name\@$host&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&\">$host</a></td>
      $temphtml .= "<tr>
                    <td bgcolor=$bgcolor width=\"200\"><a href=\"$scripturl?action=retrpop3&name=$name&host=$host&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&\">$host</a></td>
      		    <td align=\"center\" bgcolor=$bgcolor width=\"200\"><a href=\"Javascript:Update('$name','$pass','$host','$del')\">$name</a></td>
                    <td align=\"center\" bgcolor=$bgcolor width=\"200\">\*\*\*\*\*\*</td>
                    <td align=\"center\" bgcolor=$bgcolor width=\"200\">";
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
         open (POP3BOOK,"+<$folderdir/.pop3.book") or
            openwebmailerror("$lang_err{'couldnt_open'} .pop3.book!");
         unless (flock(POP3BOOK, LOCK_EX|LOCK_NB)) {
            openwebmailerror("$lang_err{'couldnt_lock'} .pop3.book!");
         }
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
      } else {
         open (POP3BOOK, ">$folderdir/.pop3.book" ) or
            openwebmailerror("$lang_err{'couldnt_open'} .pop3.book!");
         print POP3BOOK "$host:$name:$pass:$del:$lastid\n";
         close (POP3BOOK) or openwebmailerror("$lang_err{'couldnt_close'} .pop3.book!");
         chmod (0600, "$folderdir/.pop3.book");
         chown ($uid, $gid, "$folderdir/.pop3.book");
      }
   }

   print "Location: $prefsurl?action=editpop3&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&amp;message_id=$escapedmessageid\n\n";
}
################## END MODPOP3 ###########################

#################### EDITFILTER ###########################
sub editfilter {
   verifysession();

   #### variables ####
   my $html = '';
   my $temphtml;
   my @validfolders;
   my @filterrules;

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
      $temphtml = "<a href=\"$scripturl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid\"><IMG SRC=\"$image_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";
   } else {
      $temphtml = "<a href=\"$scripturl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder\"><IMG SRC=\"$image_url/backtofolder.gif\" border=\"0\" ALT=\"$lang_text{'backto'} $printfolder\"></a>";
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
                        'header'=>$lang_text{'header'},
                        'body'=>$lang_text{'body'},
                        'attfilename'=>$lang_text{'attfilename'});
   $temphtml = popup_menu(-name=>'rules',
                          -values=>['from', 'to', 'subject', 'header', 'body' ,'attfilename'],
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

   ## replace @@@FOLDERMENU@@@ ##
   @validfolders = @{&getfolders()};
   foreach (@validfolders) {
      if ( defined($lang_folders{$_}) ) {
          $labels{$_} = $lang_folders{$_};
      } else { 
         $labels{$_} = $_; 
      }
   }
   $temphtml = popup_menu(-name=>'destination',
                          -values=>[@validfolders],
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
   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach (@filterrules) {
      my ($priority, $rules, $include, $text, $destination, $enable) = split(/\@\@\@/, $_);
            
      $temphtml .= "<tr>
               <td bgcolor=$bgcolor align=center>$priority</td>
               <td bgcolor=$bgcolor align=center>$lang_text{$rules}</td>
               <td bgcolor=$bgcolor align=center>$lang_text{$include}</td>
               <td bgcolor=$bgcolor align=center><a href=\"Javascript:Update('$priority','$rules','$include','$text','$destination','$enable')\">$text</a></td>";
      if (defined($lang_folders{$destination})) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_folders{$destination}</td>";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$destination</td>";
      }
      if ($enable == 1) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'enable'}</td>";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'disable'}</td>";
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
   my ($priority, $rules, $include, $text, $destination, $enable);
   $priority = param("priority") || '';
   $rules = param("rules") || '';
   $include = param("include") || '';
   $text = param("text") || '';
   $text =~ s/^[\s\@]+//;
   $text =~ s/[\@\s]+$//;
   $text =~ s/\@\@\@//g;
   $destination = param("destination") || '';
   $enable = param("enable") || 0;
   
   ## add mode -> can't have null $rules, null $text, null $destination ##
   ## delete mode -> can't have null $filter ##
   if(($rules && $include && $text && $destination && $priority) || (($mode eq 'delete') && ($rules && $include && $text && $destination))) {
      my %filterrules;
      if ( -f "$folderdir/.filter.book" ) {
         open (FILTER,"+<$folderdir/.filter.book") or
               openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
         unless (flock(FILTER, LOCK_EX|LOCK_NB)) {
            openwebmailerror("$lang_err{'couldnt_lock'} .filter.book!");
         }
         while(<FILTER>) {
            my ($epriority,$erules,$einclude,$etext,$edestination,$eenable);
            chomp($_);
            ($epriority,$erules,$einclude,$etext,$edestination,$eenable) = split(/\@\@\@/, $_);
            $filterrules{"$erules\@\@\@$einclude\@\@\@$etext\@\@\@$edestination"}="$epriority\@\@\@$erules\@\@\@$einclude\@\@\@$etext\@\@\@$edestination\@\@\@$eenable";
         }
         if ($mode eq 'delete') {
            delete $filterrules{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"};
         } else {
            $filterrules{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$priority\@\@\@$rules\@\@\@$include\@\@\@$text\@\@\@$destination\@\@\@$enable";
         }
         seek (FILTER, 0, 0) or
            openwebmailerror("$lang_err{'couldnt_seek'} .filter.book!");
   
         foreach (sort values %filterrules) {
            print FILTER "$_\n";
         }
         truncate(FILTER, tell(FILTER));
         close (FILTER) or openwebmailerror("$lang_err{'couldnt_close'} .filter.book!");         
      } else {
         open (FILTER, ">$folderdir/.filter.book" ) or
                  openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
         print FILTER "$priority\@\@\@$rules\@\@\@$include\@\@\@$text\@\@\@$destination\@\@\@$enable\n";
         close (FILTER) or openwebmailerror("$lang_err{'couldnt_close'} .filter.book!");
         chmod (0600, "$folderdir/.filter.book");
         chown ($uid, $gid, "$folderdir/.filter.book");
      }
      
      ## remove .filter.check ##
      unlink("$folderdir/.filter.check");
   }
   print "Location: $prefsurl?action=editfilter&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&amp;message_id=$escapedmessageid\n\n";
}
################## END MODFILTER ###########################


###################### READPREFS #########################
sub readprefs {
   my ($key,$value);
   my %prefshash;
   if ( -f "$userprefsdir$user/config" ) {
      open (CONFIG,"$userprefsdir$user/config") or
         openwebmailerror("$lang_err{'couldnt_open'} config!");
      while (<CONFIG>) {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         if ($key eq 'style') {
            $value =~ s/\.//g;  ## In case someone gets a bright idea...
         }
         $prefshash{"$key"} = $value;
      }
      close (CONFIG) or openwebmailerror("$lang_err{'couldnt_close'} config!");
   }
   if ( -f "$userprefsdir$user/signature" ) {
      $prefshash{"signature"} = '';
      open (SIGNATURE, "$userprefsdir$user/signature") or
         openwebmailerror("$lang_err{'couldnt_open'} signature!");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close (SIGNATURE) or openwebmailerror("$lang_err{'couldnt_close'} signature!");
   }
   return \%prefshash;
}
##################### END READPREFS ######################

###################### READSTYLE #########################
sub readstyle {
   my ($key,$value);
   my $stylefile = $prefs{"style"} || 'Default';
   my %stylehash;
   unless ( -f "$stylesdir$stylefile") {
      $stylefile = 'Default';
   }
   open (STYLE,"$stylesdir$stylefile") or
      openwebmailerror("$lang_err{'couldnt_open'} $stylefile!");
   while (<STYLE>) {
      if (/###STARTSTYLESHEET###/) {
         $stylehash{"css"} = '';
         while (<STYLE>) {
            $stylehash{"css"} .= $_;
         }
      } else {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         $stylehash{"$key"} = $value;
      }
   }
   close (STYLE) or openwebmailerror("$lang_err{'couldnt_close'} $stylefile!");
   return \%stylehash;
}
##################### END READSTYLE ######################

###################### SAVEPREFS #########################
sub saveprefs {
   verifysession();
   unless ( -d "$userprefsdir$user" ) {
      mkdir ("$userprefsdir$user", oct(700)) or
         openwebmailerror("$lang_err{'cant_create_dir'}");
   }
   open (CONFIG,">$userprefsdir$user/config") or
      openwebmailerror("$lang_err{'couldnt_open'} config!");
   foreach my $key (qw(realname domainname replyto sort headers style
                       numberofmessages language fromname)) {
      my $value = param("$key") || '';
      $value =~ s/[\n|=|\/|\||\\|\`]//; # Strip out any sort of nastiness.
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
      } else {
         print CONFIG "$key=$value\n";
      }
   }
   close (CONFIG) or openwebmailerror("$lang_err{'couldnt_close'} config!");
   open (SIGNATURE,">$userprefsdir$user/signature") or
      openwebmailerror("$lang_err{'couldnt_open'} signature!");
   my $value = param("signature") || '';
   if (length($value) > 500) {  # truncate signature to 500 chars
      $value = substr($value, 0, 500);
   }
   print SIGNATURE $value;
   close (SIGNATURE) or openwebmailerror("$lang_err{'couldnt_close'} signature!");
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
   my %addresses;
   my ($name, $email);
   my $field=param("field");
   my $preexisting = param("preexisting") || '';
   $preexisting =~ s/(\s+)?,(\s+)?/,/g;
   print startform(-action=>"javascript:Update('" . $field . "')",
                   -name=>'addressbook'
                  );
   print '<table border="0" align="center" width="90%" cellpadding="0" cellspacing="0">';

   print '<tr><td colspan="2" bgcolor=',$style{"titlebar"},' align="left">',
   '<font color=',$style{"titlebar_text"},' face=',$style{"fontface"},' size="3"><b>',uc($lang_text{$field}),": $lang_text{'abook'}</b></font>",
   '</td></tr>';

   if ( -f "$folderdir/.address.book" ) {
      open (ABOOK,"$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} .address.book!");
      while (<ABOOK>) {
         ($name, $email) = split(/:/, $_);
         chomp($email);
         $addresses{"$name"} = $email;
      }
      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} .address.book!");

      my $bgcolor = $style{"tablerow_dark"};
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
   print '</td></tr><tr><td align="center" colspan="2" bgcolor=',$style{"tablerow_dark"},'>';
   print '<input type="hidden" name="remainingstr" value="', $preexisting, '">';
   print '<input type="submit" name="mailto.x" value="OK"> &nbsp;&nbsp;';
   print '<input type="button" value="Cancel" onClick="window.close();">';
   print '</td></tr></table>';
   print '<script language="JavaScript">
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
         if (whichfield == "to")
            window.opener.document.composeform.to.value = e2;
         else if (whichfield == "cc")
            window.opener.document.composeform.cc.value = e2;
         else
            window.opener.document.composeform.bcc.value = e2;
         window.close();
      }
      //-->
      </script>';
   print end_form();
   print end_html();
}
################## END ADDRESSBOOK #####################

############## VERIFYSESSION ########################
sub verifysession {
   if ($validsession == 1) {
      return 1;
   }
   if ( -M "$openwebmaildir/$thissession" > $sessiontimeout || !(-e "$openwebmaildir/$thissession")) {
      my $html = '';
      printheader();
      open (TIMEOUT, "$openwebmaildir/templates/$lang/sessiontimeout.template") or
         openwebmailerror("$lang_err{'couldnt_open'} sessiontimeout.template!");
      while (<TIMEOUT>) {
         $html .= $_;
      }
      close (TIMEOUT);

      $html = applystyle($html);

      print $html;

      printfooter();
      writelog("timed-out session access attempt - $thissession");
      exit 0;
   }
   if ( -e "$openwebmaildir/$thissession" ) {
      open (SESSION, "$openwebmaildir/$thissession");
      my $cookie = <SESSION>;
      close (SESSION);
      chomp $cookie;
      unless ( cookie("sessionid") eq $cookie) {
         writelog("attempt to hijack session $thissession!");
         openwebmailerror("$lang_err{'inv_sessid'}");
      }
   }

   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^([\w\.\-]+)$/) && ($thissession = $1));
   open (SESSION, '>' . "$openwebmaildir/$thissession" ) or
      openwebmailerror("$lang_err{'couldnt_open'} $thissession!");
   print SESSION cookie("sessionid");
   close (SESSION);
   $validsession = 1;
   return 1;
}
############# END VERIFYSESSION #####################

##################### WRITELOG ############################
sub writelog {
   unless ( ($logfile eq 'no') || ( -l "$logfile" ) ) {
      open (LOGFILE,">>$logfile") or openwebmailerror("$lang_err{'couldnt_open'} $logfile!");
      my $timestamp = localtime();
      my $logaction = shift;
      my $loggeduser = $user || 'UNKNOWNUSER';
      print LOGFILE "$timestamp - [$$] ($ENV{REMOTE_ADDR}) $loggeduser - $logaction\n";
      close (LOGFILE);
   }
}
#################### END WRITELOG #########################

##################### OPENWEBMAILERROR ##########################
sub openwebmailerror {
   unless ($headerprinted) {
      $headerprinted = 1;
      my $background = $style{"background"};
      $background =~ s/"//g;
      if ( $CGI::VERSION>=2.57) {
         print header(-pragma=>'no-cache',
                      -charset=>$lang_charset);
      } else {
         print header(-pragma=>'no-cache');
      }
      print start_html(-"title"=>"Open WebMail version $version",
                       -BGCOLOR=>$background,
                       -BACKGROUND=>$bg_url);
      print '<style type="text/css">';
      print $style{"css"};
      print '</style>';
      print "<FONT FACE=",$style{"fontface"},">\n";
   }
   print '<BR><BR><BR><BR><BR><BR>';
   print '<table border="0" align="center" width="40%" cellpadding="1" cellspacing="1">';

   print '<tr><td bgcolor=',$style{"titlebar"},' align="left">',
   '<font color=',$style{"titlebar_text"},' face=',$style{"fontface"},' size="3"><b>OPENWEBMAIL ERROR</b></font>',
   '</td></tr><tr><td align="center" bgcolor=',$style{"window_light"},'><BR>';
   print shift;
   print '<BR><BR></td></tr></table>';
   print '<p align="center"><font size="1"><BR>
          <a href="http://turtle.ee.ncku.edu.tw/openwebmail/">
          Open WebMail</a> version ', $version,'<BR>
          </FONT></FONT></P></BODY></HTML>';
   exit 0;
}
################### END OPENWEBMAILERROR #######################

##################### PRINTHEADER #########################
sub printheader {
   unless ($headerprinted) {
      my $html = '';
      $headerprinted = 1;
      open (HEADER, "$openwebmaildir/templates/$lang/header.template") or
         openwebmailerror("$lang_err{'couldnt_open'} header.template!");
      while (<HEADER>) {
         $html .= $_;
      }
      close (HEADER);

      $html = applystyle($html);

      $html =~ s/\@\@\@BG_URL\@\@\@/$bg_url/g;

      $html =~ s/\@\@\@CHARSET\@\@\@/$lang_charset/g;

      if ( $CGI::VERSION>=2.57) {
         print header(-pragma=>'no-cache',
                      -charset=>$lang_charset);
      } else {
         print header(-pragma=>'no-cache');
      }
      print $html;
   }
}
################### END PRINTHEADER #######################

################### PRINTFOOTER ###########################
sub printfooter {
   my $html = '';
   open (FOOTER, "$openwebmaildir/templates/$lang/footer.template") or
      openwebmailerror("$lang_err{'couldnt_open'} footer.template!");
   while (<FOOTER>) {
      $html .= $_;
   }
   close (FOOTER);

   $html = applystyle($html);

   $html =~ s/\@\@\@VERSION\@\@\@/$version/g;
   print $html;
}
################# END PRINTFOOTER #########################

################# APPLYSTYLE ##############################
sub applystyle {
   my $template = shift;
   $template =~ s/\@\@\@LOGO_URL\@\@\@/$logo_url/g;
   $template =~ s/\@\@\@BACKGROUND\@\@\@/$style{"background"}/g;
   $template =~ s/\@\@\@TITLEBAR\@\@\@/$style{"titlebar"}/g;
   $template =~ s/\@\@\@TITLEBAR_TEXT\@\@\@/$style{"titlebar_text"}/g;
   $template =~ s/\@\@\@MENUBAR\@\@\@/$style{"menubar"}/g;
   $template =~ s/\@\@\@WINDOW_DARK\@\@\@/$style{"window_dark"}/g;
   $template =~ s/\@\@\@WINDOW_LIGHT\@\@\@/$style{"window_light"}/g;
   $template =~ s/\@\@\@ATTACHMENT_DARK\@\@\@/$style{"attachment_dark"}/g;
   $template =~ s/\@\@\@ATTACHMENT_LIGHT\@\@\@/$style{"attachment_light"}/g;
   $template =~ s/\@\@\@COLUMNHEADER\@\@\@/$style{"columnheader"}/g;
   $template =~ s/\@\@\@TABLEROW_LIGHT\@\@\@/$style{"tablerow_light"}/g;
   $template =~ s/\@\@\@TABLEROW_DARK\@\@\@/$style{"tablerow_dark"}/g;
   $template =~ s/\@\@\@FONTFACE\@\@\@/$style{"fontface"}/g;
   $template =~ s/\@\@\@SCRIPTURL\@\@\@/$scripturl/g;
   $template =~ s/\@\@\@PREFSURL\@\@\@/$prefsurl/g;
   $template =~ s/\@\@\@CSS\@\@\@/$style{"css"}/g;
   $template =~ s/\@\@\@VERSION\@\@\@/$version/g;

   return $template;
}
################ END APPLYSTYLE ###########################

################## GETFOLDERS ####################
sub getfolders {
   my (@folders, @userfolders);
   my @delfiles=();
   my $filename;

   if ( $homedirfolders eq 'yes' ) {
      @folders = ('saved-messages', 'sent-mail', 'mail-trash');
   } else {
      @folders = ('SAVED', 'TRASH', 'SENT');
   }

   opendir (FOLDERDIR, "$folderdir") or 
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir!");

   while (defined($filename = readdir(FOLDERDIR))) {

      ### files started with . are not folders
      ### they are openwebmail internal files (., .., dbm, search caches)
      if ( $filename=~/^\./ ) {
         if ( $filename=~/^\.(.*)\.$dbm_ext$/ ||
              ($filename=~/^\.(.*)\.cache$/ && $filename ne ".search.cache") ) {
            if ( ($1 ne $user) && (! -f "$folderdir/$1") ){
               # dbm or cache whose folder doesn't exist
               ($filename =~ /^(.+)$/) && ($filename = $1); # bypass taint check
               push (@delfiles, "$folderdir/$filename");	
            }
         }
         next;
      }

      ### find all user folders
      if ( $homedirfolders eq 'yes' ) {
         unless ( ($filename eq 'saved-messages') ||
                  ($filename eq 'sent-mail') ||
                  ($filename eq 'mail-trash') ||
                  ($filename eq '.') || ($filename eq '..')
                ) {
            push (@userfolders, $filename);
         }
      } else {
         if ($filename =~ /^(.+)\.folder$/) {
            push (@userfolders, $1);
         }
      }
   }

   closedir (FOLDERDIR) or
      openwebmailerror("$lang_err{'couldnt_close'} $folderdir!");

   push (@folders, sort(@userfolders));

   if ($#delfiles >= 0) {
      unlink(@delfiles);
   }

   return \@folders;
}
################ END GETFOLDERS ##################

