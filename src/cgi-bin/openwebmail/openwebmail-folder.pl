#!/usr/bin/suidperl -T
#
# openwebmail-folder.pl - mail folder management program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1; }
}
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "ow-shared.pl";
require "filelock.pl";
require "mime.pl";
require "maildb.pl";
require "htmltext.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

# extern vars
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy
use vars qw($_OFFSET $_STATUS);				# defined in maildb.pl

# local globals
use vars qw($sort $page);

########################## MAIN ##############################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop

userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$page = param("page") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';

my $action = param("action");
if ($action eq "editfolders") {
   editfolders();
} elsif ($action eq "refreshfolders") {
   refreshfolders();
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
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

openwebmail_requestend();
###################### END MAIN ##############################

#################### EDITFOLDERS ###########################
sub editfolders {
   my (@defaultfolders, @userfolders);
   my $total_newmessages=0;
   my $total_allmessages=0;
   my $total_foldersize=0;

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

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editfolders.template"));

   $html =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/g;

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder"|). qq|&nbsp; \n|;
   $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'}, qq|accesskey="R" href="$config{'ow_cgiurl'}/openwebmail-folder.pl?action=refreshfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;page=$page"|). qq| \n|;

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
               hidden(-name=>'page',
                      -default=>$page,
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
#                         -accesskey=>'I',
   $html =~ s/\@\@\@FOLDERNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"$lang_text{'add'}",
                      -accesskey=>'A',
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   my $bgcolor = $style{"tablerow_dark"};
   my $currfolder;
   my $form_i=0;
   $temphtml='';
   foreach $currfolder (@userfolders) {
      $temphtml .= _folderline($currfolder, $form_i, $bgcolor,
                               \$total_newmessages, \$total_allmessages, \$total_foldersize);
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
      $form_i++;
   }
   $html =~ s/\@\@\@FOLDERS\@\@\@/$temphtml/;

   $bgcolor = $style{"tablerow_dark"};
   $temphtml='';
   foreach $currfolder (@defaultfolders) {
      $temphtml .= _folderline($currfolder, $form_i, $bgcolor,
                               \$total_newmessages, \$total_allmessages, \$total_foldersize);
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
      $form_i++;
   }
   $html =~ s/\@\@\@DEFAULTFOLDERS\@\@\@/$temphtml/;

   my $usagestr;
   if ($config{'quota_module'} ne "none") {
      my $percent=0;
      $usagestr="$lang_text{'quotausage'}: ".lenstr($quotausage*1024,1);
      if ($quotalimit>0) {
         $percent=int($quotausage*1000/$quotalimit)/10;
         $usagestr.=" ($percent%) &nbsp;";
         $usagestr.="$lang_text{'quotalimit'}: ".lenstr($quotalimit*1024,1);
      }
      if ($percent>=90) {
         $usagestr="<B><font color='#cc0000'>$usagestr</font></B>";
      } else {
         $usagestr="<B>$usagestr</B>";
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

   httpprint([], [htmlheader(), $html, htmlfooter(1)]);
}

# this is inline function used by sub editfolders(), it changes
# $total_newmessages, $total_allmessages and $total_size in editfolders()
sub _folderline {
   my ($currfolder, $i, $bgcolor,
       $r_total_newmessages, $r_total_allmessages, $r_total_foldersize)=@_;
   my $temphtml='';
   my (%HDB, $newmessages, $allmessages, $foldersize);
   my ($folderfile,$headerdb)=get_folderfile_headerdb($user, $currfolder);

   if ( -f "$headerdb$config{'dbm_ext'}" && !-z "$headerdb$config{'dbm_ext'}" ) {
      open_dbm(\%HDB, $headerdb, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $headerdb$config{'dbm_ext'}");
      if ( defined($HDB{'ALLMESSAGES'}) ) {
         $allmessages=$HDB{'ALLMESSAGES'};
         ${$r_total_allmessages}+=$allmessages;
      } else {
         $allmessages='&nbsp;';
      }
      if ( defined($HDB{'NEWMESSAGES'}) ) {
         $newmessages=$HDB{'NEWMESSAGES'};
         ${$r_total_newmessages}+=$newmessages;
      } else {
         $newmessages='&nbsp;';
      }
      close_dbm(\%HDB, $headerdb);
   } else {
      $allmessages='&nbsp;';
      $newmessages='&nbsp;';
   }

   # we count size for both folder file and related dbm
   $foldersize = (-s "$folderfile") + (-s "$headerdb$config{'dbm_ext'}");

   ${$r_total_foldersize}+=$foldersize;
   $foldersize=lenstr($foldersize,0);

   my $escapedcurrfolder = escapeURL($currfolder);
   my $url = "$config{'ow_cgiurl'}/openwebmail-folder.pl?sessionid=$thissession&amp;folder=$escapedcurrfolder&amp;action=downloadfolder";
   my $folderstr=$lang_folders{$currfolder}||$currfolder;

   my $accesskeystr=$i%10+1;
   if ($accesskeystr == 10) {
      $accesskeystr=qq|accesskey="0"|;
   } elsif ($accesskeystr < 10) {
      $accesskeystr=qq|accesskey="$accesskeystr"|;
   }

   $temphtml .= qq|<tr>|.
                qq|<td align="center" bgcolor=$bgcolor>|.
                qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedcurrfolder">|.
                str2html($folderstr).qq| </a>&nbsp;\n|.
                iconlink("download.gif", "$lang_text{'download'} $folderstr ", qq|$accesskeystr href="$url"|).
                qq|</td>\n|.
                qq|<td align="center" bgcolor=$bgcolor>$newmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>&nbsp;$allmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>&nbsp;$foldersize</td>\n|;

   $temphtml .= qq|<td bgcolor=$bgcolor align="center">\n|;

   $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-folder.pl",
                           -name=>"folderform$i");
   $temphtml .= hidden(-name=>'action',
                       -value=>'chkindexfolder',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -value=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'sort',
                       -default=>$sort,
                       -override=>'1');
   $temphtml .= hidden(-name=>'page',
                       -default=>$page,
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

################### REFRESHFOLDERS ##############################
sub refreshfolders {
   my $errcount=0;

   foreach my $currfolder (@validfolders) {
      my ($folderfile,$headerdb)=get_folderfile_headerdb($user, $currfolder);

      filelock($folderfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderfile!");
      if (update_headerdb($headerdb, $folderfile)<0) {
         $errcount++;
         writelog("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
         writehistory("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      }
      filelock($folderfile, LOCK_UN);
   }

   writelog("folder - refresh, $errcount errors");
   writehistory("folder - refresh, $errcount errors");

   # get uptodate quota/folder usage info
   getfolders(\@validfolders, \$folderusage);
   if ($config{'quota_module'} ne 'none') {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   editfolders();
}
################### END REFRESHFOLDERS ##########################

################### MARKREADFOLDER ##############################
sub markreadfolder {
   my $foldertomark = safefoldername(param('foldername')) || '';
   ($foldertomark =~ /^(.+)$/) && ($foldertomark = $1);
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertomark);

   filelock($folderfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderfile!");

   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
   }

   my (%HDB, %offset, %status);
   open_dbm(\%HDB, $headerdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $headerdb$config{'dbm_ext'}");
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
   close_dbm(\%HDB, $headerdb);

   my @markids;
   my $tmpfile="/tmp/markread_tmp_$$";
   my $tmpdb="/tmp/.markread_tmp_$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);
   ($tmpdb =~ /^(.+)$/) && ($tmpdb = $1);

   open(F, ">$tmpfile"); close(F);
   filelock("$tmpfile", LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $tmpfile");

   if (update_headerdb($tmpdb, $tmpfile)<0) {
      filelock($tmpfile, LOCK_UN);
      unlink("$tmpdb$config{'dbm_ext'}", "$tmpdb.dir", "$tmpdb.pag", $tmpfile);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} $tmpdb$config{'dbm_ext'}");
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
   unlink("$tmpdb$config{'dbm_ext'}", "$tmpdb.dir", "$tmpdb.pag", $tmpfile);

   writelog("markread folder - $foldertomark");
   writehistory("markread folder - $foldertomark");

   getfolders(\@validfolders, \$folderusage);
   editfolders();
}
################### END MARKREADFOLDER ##########################

################### REINDEXFOLDER ##############################
sub reindexfolder {
   my $recreate=$_[0];
   my $foldertoindex = safefoldername(param('foldername')) || '';
   ($foldertoindex =~ /^(.+)$/) && ($foldertoindex = $1);
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertoindex);

   if ($recreate) {
      my $filename=untaint("$headerdb$config{'dbm_ext'}");
      unlink($filename);
   }

   if ( -f "$headerdb$config{'dbm_ext'}" ) {
      my %HDB;
      open_dbm(\%HDB, $headerdb, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $headerdb$config{'dbm_ext'}");

      $HDB{'METAINFO'}={'RENEW'};
      close_dbm(\%HDB, $headerdb);
   }
   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
   }

   if ($recreate) {
      writelog("reindex folder - $foldertoindex");
      writehistory("reindex folder - $foldertoindex");
   } else {
      writelog("chkindex folder - $foldertoindex");
      writehistory("chkindex folder - $foldertoindex");
   }

#   print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&page=$page");
   getfolders(\@validfolders, \$folderusage);
   editfolders();
}
################### END REINDEXFOLDER ##########################

################### ADDFOLDER ##############################
sub addfolder {
   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2];	# get uptodate quotausage
      if ($quotausage>$quotalimit) {
         openwebmailerror(__FILE__, __LINE__, $lang_err{'quotahit_alert'});
      }
   }

   my $foldertoadd = safefoldername(param('foldername')) || '';
   ($foldertoadd =~ /^(.+)$/) && ($foldertoadd = $1);

   if (length($foldertoadd) > $config{'foldername_maxlen'}) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'foldername_long'}");
   }
   if ( is_defaultfolder($foldertoadd) ||
        $foldertoadd eq "$user" || $foldertoadd eq "" ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_folder'}");
   }

   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertoadd);
   if ( -f $folderfile ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'folder_with_name'} $foldertoadd $lang_err{'already_exists'}");
   }

   open (FOLDERTOADD, ">$folderfile") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_folder'} $foldertoadd! ($!)");
   close (FOLDERTOADD) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $foldertoadd! ($!)");

   # create empty index dbm with mode 0600
   my %HDB;
   open_dbm(\%HDB, $headerdb, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $headerdb$config{'dbm_ext'}");
   close_dbm(\%HDB, $headerdb);

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
      return 1;
   } else {
      return 0;
   }
}
################### END ADDFOLDER ##########################

################### DELETEFOLDER ##############################
sub deletefolder {
   my $foldertodel = safefoldername(param('foldername')) || '';
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

   # get uptodate quota/folder usage info
   getfolders(\@validfolders, \$folderusage);
   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   editfolders();
}
################### END DELETEFOLDER ##########################

################### RENAMEFOLDER ##############################
sub renamefolder {
   my $oldname = safefoldername(param('foldername')) || '';
   ($oldname =~ /^(.+)$/) && ($oldname = $1);
   if ($oldname eq 'INBOX') {
      editfolders();
      return;
   }

   my $newname = safefoldername(param('foldernewname'));
   ($newname =~ /^(.+)$/) && ($newname = $1);

   if (length($newname) > $config{'foldername_maxlen'}) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'foldername_long'}");
   }
   if ( is_defaultfolder($newname) ||
        $newname eq "$user" || $newname eq "" ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_folder'}");
   }
   if ( -f "$folderdir/$newname" ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'folder_with_name'} $newname $lang_err{'already_exists'}");
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

      writelog("rename folder - $oldname to $newname");
      writehistory("rename folder - $oldname to $newname");
   }

#   print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfolders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&page=$page");
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
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderfile");

   # disposition:attachment default to save
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$filename"\n|;
   if ( $ENV{'HTTP_USER_AGENT'}=~/MSIE 5.5/ ) {	# ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$filename"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$filename"\n|;
   }
   print qq|\n|;

   $cmd=untaint($cmd);
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
