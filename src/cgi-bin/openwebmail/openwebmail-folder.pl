#!/usr/bin/perl -T
#############################################################################
# Open WebMail - Provides a web interface to user mailboxes                 #
#                                                                           #
# Copyright (C) 2001-2002                                                   #
# Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric, Thomas Chung   #
# Copyright (C) 2000                                                        #
# Ernie Miller  (original GPL project: Neomail)                             #
#                                                                           #
# This program is distributed under GNU General Public License              #
#############################################################################

use vars qw($SCRIPT_DIR);
if ( $ENV{'SCRIPT_FILENAME'} =~ m!^(.*?)/[\w\d\-]+\.pl! || $0 =~ m!^(.*?)/[\w\d\-]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\n\$SCRIPT_DIR not set in CGI script!\n"; exit 0; }
push (@INC, $SCRIPT_DIR, ".");

$ENV{PATH} = ""; # no PATH should be needed
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

require "openwebmail-shared.pl";
require "filelock.pl";
require "mime.pl";
require "maildb.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();
verifysession();

use vars qw($firstmessage);
use vars qw($sort);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';

# extern vars
use vars qw($lang_charset %lang_folders %lang_text %lang_err);	# defined in lang/xy

########################## MAIN ##############################

my $action = param("action");
if ($action eq "editfolders") {
   editfolders();
} elsif ($action eq "chkindexfolder") {
   reindexfolder(0);
} elsif ($action eq "reindexfolder") {
   reindexfolder(1);
} elsif ($action eq "addfolder") {
   addfolder();
} elsif ($action eq "deletefolder") {
   deletefolder();
} elsif ($action eq "renamefolder") {
   renamefolder();
} elsif ($action eq "downloadfolder") {
   downloadfolder();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}
###################### END MAIN ##############################

#################### EDITFOLDERS ###########################
my ($total_newmessages, $total_allmessages, $total_foldersize);

sub editfolders {
   my (@defaultfolders, @userfolders);

   $total_newmessages=0;
   $total_allmessages=0;
   $total_foldersize=0;

   push(@defaultfolders, 'INBOX', 
                         'saved-messages', 
                         'sent-mail', 
                         'saved-drafts', 
                         'mail-trash');

   foreach (@validfolders) {
      if ($_ ne 'INBOX' &&
          $_ ne 'saved-messages' &&
          $_ ne 'sent-mail' &&
          $_ ne 'saved-drafts' &&
          $_ ne 'mail-trash') {
         push (@userfolders, $_);
      }
   }

   my $html = '';
   my $temphtml;

   open (EDITFOLDERSTEMPLATE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/editfolders.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/editfolders.template!");
   while (<EDITFOLDERSTEMPLATE>) {
      $html .= $_;
   }
   close (EDITFOLDERSTEMPLATE);

   $html = applystyle($html);

   $html =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/g;

   printheader();

   $temphtml = qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$escapedfolder" title="$lang_text{'backto'} $printfolder"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/backtofolder.gif" border="0" ALT="$lang_text{'backto'} $printfolder"></a>|;

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-folder.pl") .
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
                         -size=> $config{'foldername_maxlen'},
                         -maxlength=>$config{'foldername_maxlen'},
                         -override=>'1');

   $html =~ s/\@\@\@FOLDERNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"$lang_text{'add'}",
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   my $bgcolor = $style{"tablerow_dark"};
   my $currfolder;
   my $i=0;
   $temphtml='';
   foreach $currfolder (@userfolders) {
      $temphtml .= _folderline($currfolder, $i, $bgcolor);
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
      $i++;
   }
   $html =~ s/\@\@\@FOLDERS\@\@\@/$temphtml/;

   $bgcolor = $style{"tablerow_dark"};
   $temphtml='';
   foreach $currfolder (@defaultfolders) {
      $temphtml .= _folderline($currfolder, $i, $bgcolor);
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
      $i++;
   }
   $html =~ s/\@\@\@DEFAULTFOLDERS\@\@\@/$temphtml/;

   my $usagestr;
   if ($config{'folderquota'}) {
      if ($folderusage>=90) {
         $usagestr="<B><font color='#cc0000'>$folderusage %</font></B>";
      } else {
         $usagestr="<B>$folderusage %</B>";
      }
   } else {
      $usagestr="&nbsp;";
   }

   if ($total_foldersize > 1048575){
      $total_foldersize = int($total_foldersize/1048576*10+0.5)/10 . "MB";
   } elsif ($total_foldersize > 1023) {
      $total_foldersize =  int(($total_foldersize/1024)+0.5) . "KB";
   }
   $temphtml = qq|<tr>|.
               qq|<td align="center" bgcolor=$bgcolor><B>$lang_text{'total'}</B></td>|.
               qq|<td align="center" bgcolor=$bgcolor><B>$total_newmessages</B></td>|.
               qq|<td align="center" bgcolor=$bgcolor><B>$total_allmessages</B></td>|.
               qq|<td align="center" bgcolor=$bgcolor><B>$total_foldersize</B></td>|.
               qq|<td bgcolor=$bgcolor align="center">$usagestr</td>|.
               qq|</tr>|;
   $html =~ s/\@\@\@TOTAL\@\@\@/$temphtml/;

   print $html;

   printfooter(1);
}

# this is inline function used by sub editfolders(), it changes
# $total_newmessages, $total_allmessages and $total_size in editfolders()
sub _folderline {
   my ($currfolder, $i, $bgcolor)=@_;
   my $temphtml='';
   my (%HDB, $newmessages, $allmessages, $foldersize);
   my ($folderfile,$headerdb)=get_folderfile_headerdb($user, $currfolder);

   if ( -f "$headerdb$config{'dbm_ext'}" ) {
      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
   } else {
      $allmessages='&nbsp;';
      $newmessages='&nbsp;';
   }

   # we count size for both folder file and related dbm
   $foldersize = (-s "$folderfile") + (-s "$headerdb$config{'dbm_ext'}");

   $total_foldersize+=$foldersize;
   # round foldersize and change to an appropriate unit for display
   if ($foldersize > 1048575){
      $foldersize = int($foldersize/1048576*10+0.5)/10 . "MB";
   } elsif ($foldersize > 1023) {
      $foldersize =  int(($foldersize/1024)+0.5) . "KB";
   }

   my $escapedcurrfolder = escapeURL($currfolder);
   my $url = "$config{'ow_cgiurl'}/openwebmail-folder.pl?sessionid=$thissession&amp;folder=$escapedcurrfolder&amp;action=downloadfolder";
   my $folderstr=$currfolder;
   $folderstr=$lang_folders{$currfolder} if defined($lang_folders{$currfolder});

   $temphtml .= qq|<tr>|.
                qq|<td align="center" bgcolor=$bgcolor>|.
                qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$escapedcurrfolder">|.
                qq|$folderstr</a>&nbsp;\n|.
                qq|<a href="$url" title="$lang_text{'download'} $folderstr"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/download.gif" align="absmiddle" border="0" ALT="$lang_text{'download'} $folderstr">|.
                qq|</a></td>\n|.
                qq|<td align="center" bgcolor=$bgcolor>$newmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>$allmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>$foldersize</td>\n|;

   $temphtml .= qq|<td bgcolor=$bgcolor align="center">\n|;

   $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-folder.pl",
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
   $temphtml .= "\n";

   my $jsfolderstr=$currfolder; $jsfolderstr=~ s/'/\\'/g;	# escaep ' with \'
   $temphtml .= submit(-name=>"$lang_text{'chkindex'}",
                       -class=>"medtext",
                       -onClick=>"return OpConfirm('folderform$i', 'chkindexfolder', $lang_text{'folderchkindexconf'}+' ( $jsfolderstr )')");
   $temphtml .= submit(-name=>"$lang_text{'reindex'}", 
                       -class=>"medtext",
                       -onClick=>"return OpConfirm('folderform$i', 'reindexfolder', $lang_text{'folderreindexconf'}+' ( $jsfolderstr )')");
   if ($currfolder ne "INBOX") {
      $temphtml .= submit(-name=>"$lang_text{'rename'}", 
                          -class=>"medtext",
                          -onClick=>"return OpConfirm('folderform$i', 'renamefolder', $lang_text{'folderrenprop'}+' ( $jsfolderstr )')");
      $temphtml .= submit(-name=>"$lang_text{'delete'}",
                          -class=>"medtext",
                          -onClick=>"return OpConfirm('folderform$i', 'deletefolder', $lang_text{'folderdelconf'}+' ( $jsfolderstr )')");
   }

   $temphtml .= "</td></tr>";
   $temphtml .= end_form()."\n";

   return($temphtml);
}
################### END EDITFOLDERS ########################

################### REINDEXFOLDER ##############################
sub reindexfolder {
   my $recreate=$_[0];
   my $foldertoindex = param('foldername') || '';
   $foldertoindex =~ s/\.\.+//g;
   $foldertoindex =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($foldertoindex =~ /^(.+)$/) && ($foldertoindex = $1);
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertoindex);

   if ($recreate) {
      my $filename="$headerdb$config{'dbm_ext'}";
      ($filename =~ /^(.+)$/) && ($filename = $1);  # untaint
      unlink($filename);
   }

   if ( -f "$headerdb$config{'dbm_ext'}" ) {
      my %HDB;
      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
      $HDB{'METAINFO'}={'RENEW'};
      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
   }
   update_headerdb($headerdb, $folderfile);

   getfolders(\@validfolders, \$folderusage);
   editfolders();

#   print "Location: $config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
}
################### END REINDEXFOLDER ##########################

################### ADDFOLDER ##############################
sub addfolder {
   my $foldertoadd = param('foldername') || '';
   $foldertoadd =~ s/\.\.+//g;
   $foldertoadd =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($foldertoadd =~ /^(.+)$/) && ($foldertoadd = $1);

   if (length($foldertoadd) > $config{'foldername_maxlen'}) {
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

   # create empty index dbm with mode 0600
   my %HDB;
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);
   dbmclose(%HDB);

   writelog("create folder - $foldertoadd");
   writehistory("create folder - $foldertoadd");

   getfolders(\@validfolders, \$folderusage);
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
   my $foldertodel = param('foldername') || '';
   $foldertodel =~ s/\.\.+//g;
   $foldertodel =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($foldertodel =~ /^(.+)$/) && ($foldertodel = $1);

   # if is INBOX, return to editfolder immediately
   if ($foldertodel eq 'INBOX') {
      editfolders();
      return;
   }

   if ( -f "$folderdir/$foldertodel" ) {
      unlink ("$folderdir/$foldertodel",
              "$folderdir/.$foldertodel$config{'dbm_ext'}",
              "$folderdir/.$foldertodel.db",
	      "$folderdir/.$foldertodel.dir",
              "$folderdir/.$foldertodel.pag",
              "$folderdir/.$foldertodel.cache",
              "$folderdir/$foldertodel.lock",
              "$folderdir/$foldertodel.lock.lock");              

      writelog("delete folder - $foldertodel");
      writehistory("delete folder - $foldertodel");
   }

   getfolders(\@validfolders, \$folderusage);
   editfolders();
}
################### END DELETEFOLDER ##########################

################### RENAMEFOLDER ##############################
sub renamefolder {
   my $oldname = param('foldername') || '';
   $oldname =~ s/\.\.+//g;
   $oldname =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($oldname =~ /^(.+)$/) && ($oldname = $1);

   if ($oldname eq 'INBOX') {
      editfolders();
      return;
   }

   my $newname = param('foldernewname');
   $newname =~ s/\.\.+//g;
   $newname =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char
   ($newname =~ /^(.+)$/) && ($newname = $1);

   if (length($newname) > $config{'foldername_maxlen'}) {
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
      rename("$folderdir/.$oldname$config{'dbm_ext'}", "$folderdir/.$newname$config{'dbm_ext'}");
      rename("$folderdir/.$oldname.db",      "$folderdir/.$newname.db");
      rename("$folderdir/.$oldname.dir",     "$folderdir/.$newname.dir");
      rename("$folderdir/.$oldname.pag",     "$folderdir/.$newname.pag");
      rename("$folderdir/.$oldname.cache",   "$folderdir/.$newname.cache");
      unlink("$folderdir/$oldname.lock", "$folderdir/$oldname.lock.lock");

      writelog("rename folder - rename $oldname to $newname");
      writehistory("rename folder - rename $oldname to $newname");
   }

#   print "Location: $config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
   getfolders(\@validfolders, \$folderusage);
   editfolders();
}
################### END RENAMEFOLDER ##########################

#################### DOWNLOAD FOLDER #######################
sub downloadfolder {
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

   $filename=~s/\s+/_/g;

   filelock($folderfile, LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $folderfile");

   # disposition:attachment default to save
   print qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$filename"\n|;

   # ugly hack since ie5.5 is broken with disposition: attchment
   if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
      print qq|Content-Disposition: attachment; filename="$filename"\n|;
   }
   print qq|\n|;

   ($cmd =~ /^(.+)$/) && ($cmd = $1);		# untaint ...
   open (T, $cmd);
   while ( read(T, $buff,32768) ) {
     print $buff;
   }
   close(T);

   filelock($folderfile, LOCK_UN);

   writelog("download folder - $folder");
   writehistory("download folder - $folder");

   return;
}
################## END DOWNLOADFOLDER #####################

