#!/usr/bin/suidperl -T
#
# openwebmail-folder.pl - mail folder management program
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
require "maildb.pl";

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

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';

# extern vars
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy
use vars qw($_OFFSET $_STATUS);				# defined in maildb.pl

########################## MAIN ##############################

my $action = param("action");
if ($action eq "editfolders") {
   editfolders();
} elsif ($action eq "markreadfolder") {
   markreadfolder();
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

   $html=readtemplate("editfolders.template");
   $html = applystyle($html);

   $html =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/g;

   printheader();

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$escapedfolder"|). qq|\n|;
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
                         -size=> 24,
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

   $total_foldersize=lenstr($total_foldersize,0);

   $temphtml = qq|<tr>|.
               qq|<td align="center" bgcolor=$bgcolor><B>$lang_text{'total'}</B></td>|.
               qq|<td align="center" bgcolor=$bgcolor><B>$total_newmessages</B></td>|.
               qq|<td align="center" bgcolor=$bgcolor><B>&nbsp;$total_allmessages</B></td>|.
               qq|<td align="center" bgcolor=$bgcolor><B>&nbsp;$total_foldersize</B></td>|.
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

   if ( -f "$headerdb$config{'dbm_ext'}" && !-z "$headerdb$config{'dbm_ext'}" ) {
      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
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
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   } else {
      $allmessages='&nbsp;';
      $newmessages='&nbsp;';
   }

   # we count size for both folder file and related dbm
   $foldersize = (-s "$folderfile") + (-s "$headerdb$config{'dbm_ext'}");

   $total_foldersize+=$foldersize;
   $foldersize=lenstr($foldersize,0);

   my $escapedcurrfolder = escapeURL($currfolder);
   my $url = "$config{'ow_cgiurl'}/openwebmail-folder.pl?sessionid=$thissession&amp;folder=$escapedcurrfolder&amp;action=downloadfolder";
   my $folderstr=$currfolder;
   $folderstr=$lang_folders{$currfolder} if defined($lang_folders{$currfolder});

   $temphtml .= qq|<tr>|.
                qq|<td align="center" bgcolor=$bgcolor>|.
                qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$escapedcurrfolder">|.
                qq|$folderstr</a>&nbsp;\n|.
                iconlink("download.gif", "$lang_text{'download'} $folderstr", qq|href="$url"|).
                qq|</td>\n|.
                qq|<td align="center" bgcolor=$bgcolor>$newmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>&nbsp;$allmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>&nbsp;$foldersize</td>\n|;

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

   my $jsfolderstr=$lang_folders{$currfolder}||$currfolder;
   $jsfolderstr=~ s/'/\\'/g;	# escaep ' with \'
   $temphtml .= submit(-name=>"$lang_text{'markread'}",
                       -class=>"medtext",
                       -onClick=>"return OpConfirm('folderform$i', 'markreadfolder', $lang_text{'foldermarkreadconf'}+' ( $jsfolderstr )')");
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

################### MARKREADFOLDER ##############################
sub markreadfolder {
   my $foldertomark = param('foldername') || '';
   $foldertomark =~ s!\.\.+/!!g;
   $foldertomark =~ s!^\s*/!!g;
   $foldertomark =~ s/[\s\`\|\<\>;]//g; # remove dangerous char
   ($foldertomark =~ /^(.+)$/) && ($foldertomark = $1);
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertomark);

   filelock($folderfile, LOCK_EX|LOCK_NB) or openwebmailerror("$lang_err{'couldnt_lock'} $folderfile!");

   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      openwebmailerror("$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
   }

   my (%HDB, %offset, %status);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
   foreach my $messageid (keys %HDB) {
      next if ( $messageid eq 'METAINFO'
             || $messageid eq 'NEWMESSAGES'
             || $messageid eq 'INTERNALMESSAGES'
             || $messageid eq 'ALLMESSAGES'
             || $messageid eq "" );
      my @attr=split( /@@@/, $HDB{$messageid} );
      if ($attr[$_STATUS] !~ /R/i) {
         $offset{$messageid}=$attr[$_OFFSET];
         $status{$messageid}=$attr[$_STATUS];
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

   my @markids;
   my $tmpfile="/tmp/markread_tmp_$$";
   my $tmpdb="/tmp/.markread_tmp_$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);
   ($tmpdb =~ /^(.+)$/) && ($tmpdb = $1);

   filelock("$tmpfile", LOCK_EX);

   if (update_headerdb($tmpdb, $tmpfile)<0) {
      filelock($tmpfile, LOCK_UN);
      openwebmailerror("$lang_err{'couldnt_updatedb'} $tmpdb$config{'dbm_ext'}");
   }

   foreach my $messageid (sort { $offset{$a}<=>$offset{$b} } keys %offset) {
      my @copyid;
      push(@copyid, $messageid);
      if (operate_message_with_ids("copy", \@copyid,
   					$folderfile, $headerdb, $tmpfile, $tmpdb) >0 ) {
         update_message_status($messageid, $status{$messageid}."R", $tmpdb, $tmpfile);
         push(@markids, $messageid);

         if ($#markids>=99) { # flush per 100 msgs
            operate_message_with_ids("delete", \@markids, $folderfile, $headerdb);
            operate_message_with_ids("move", \@markids,
   					$tmpfile, $tmpdb, $folderfile, $headerdb);
            @markids=();
         }

      }
   }
   operate_message_with_ids("delete", \@markids, $folderfile, $headerdb);
   operate_message_with_ids("move", \@markids,
   					$tmpfile, $tmpdb, $folderfile, $headerdb);

   filelock("$tmpfile", LOCK_UN);
   filelock($folderfile, LOCK_UN);
   unlink("$tmpdb$config{'dbm_ext'}", $tmpfile);

   writelog("markread folder - $foldertomark");
   writehistory("markread folder - $foldertomark");

   getfolders(\@validfolders, \$folderusage);
   editfolders();
}
################### END MARKREADFOLDER ##########################

################### REINDEXFOLDER ##############################
sub reindexfolder {
   my $recreate=$_[0];
   my $foldertoindex = param('foldername') || '';
   $foldertoindex =~ s!\.\.+/!!g;
   $foldertoindex =~ s!^\s*/!!g;
   $foldertoindex =~ s/[\s\`\|\<\>;]//g; # remove dangerous char
   ($foldertoindex =~ /^(.+)$/) && ($foldertoindex = $1);
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertoindex);

   if ($recreate) {
      my $filename="$headerdb$config{'dbm_ext'}";
      ($filename =~ /^(.+)$/) && ($filename = $1);  # untaint
      unlink($filename);
   }

   if ( -f "$headerdb$config{'dbm_ext'}" ) {
      my %HDB;
      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);
      $HDB{'METAINFO'}={'RENEW'};
      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   }
   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      openwebmailerror("$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
   }

   if ($recreate) {
      writelog("reindex folder - $foldertoindex");
      writehistory("reindex folder - $foldertoindex");
   } else {
      writelog("chkindex folder - $foldertoindex");
      writehistory("chkindex folder - $foldertoindex");
   }

#   print "Location: $config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
   getfolders(\@validfolders, \$folderusage);
   editfolders();
}
################### END REINDEXFOLDER ##########################

################### ADDFOLDER ##############################
sub addfolder {
   my $foldertoadd = param('foldername') || '';
   $foldertoadd =~ s!\.\.+/!!g;
   $foldertoadd =~ s!^\s*/!!g;
   $foldertoadd =~ s/[\s\`\|\<\>;]//g; # remove dangerous char
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
   $foldertodel =~ s!\.\.+/!!g;
   $foldertodel =~ s!^\s*/!!g;
   $foldertodel =~ s/[\s\`\|\<\>;]//g; # remove dangerous char
   ($foldertodel =~ /^(.+)$/) && ($foldertodel = $1);

   # if is INBOX, return to editfolder immediately
   if ($foldertodel eq 'INBOX') {
      editfolders();
      return;
   }

   if ( -f "$folderdir/$foldertodel" ) {
      my $headerdb="$folderdir/$foldertodel";
      ($headerdb =~ /^(.+)\/(.*)$/) && ($headerdb = "$1/.$2");
      unlink ("$folderdir/$foldertodel",
              "$folderdir/$foldertodel.lock",
              "$folderdir/$foldertodel.lock.lock",
              "$headerdb$config{'dbm_ext'}",
              "$headerdb.db",
	      "$headerdb.dir",
              "$headerdb.pag",
              "$headerdb.cache");

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
   $oldname =~ s!\.\.+/!!g;
   $oldname =~ s!^\s*/!!g;
   $oldname =~ s/[\s\`\|\<\>;]//g; # remove dangerous char
   ($oldname =~ /^(.+)$/) && ($oldname = $1);

   if ($oldname eq 'INBOX') {
      editfolders();
      return;
   }

   my $newname = param('foldernewname');
   $newname =~ s!\.\.+/!!g;
   $newname =~ s!^\s*/!!g;
   $newname =~ s/[\s\`\|\<\>;]//g; # remove dangerous char
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
      my $oldheaderdb="$folderdir/$oldname";
      my $newheaderdb="$folderdir/$newname";
      ($oldheaderdb =~ /^(.+)\/(.*)$/) && ($oldheaderdb = "$1/.$2");
      ($newheaderdb =~ /^(.+)\/(.*)$/) && ($newheaderdb = "$1/.$2");
      rename("$folderdir/$oldname",            "$folderdir/$newname");
      rename("$oldheaderdb$config{'dbm_ext'}", "$newheaderdb$config{'dbm_ext'}");
      rename("$oldheaderdb.db",                "$newheaderdb.db");
      rename("$oldheaderdb.dir",               "$newheaderdb.dir");
      rename("$oldheaderdb.pag",               "$newheaderdb.pag");
      rename("$oldheaderdb.cache",             "$newheaderdb.cache");
      unlink("$folderdir/$newname.lock",       "$folderdir/$oldname.lock.lock");

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
      $cmd="/usr/local/bin/zip -rq - $folderfile |";
      $contenttype='application/x-zip-compressed';
      $filename="$folder.zip";

   } elsif ( -x '/usr/bin/zip' ) {
      $cmd="/usr/bin/zip -rq - $folderfile |";
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

