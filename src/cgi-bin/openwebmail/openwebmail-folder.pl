#!/usr/bin/suidperl -T
#
# openwebmail-folder.pl - mail folder management program
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
require "modules/mime.pl";
require "modules/mailparse.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy
use vars qw($_OFFSET $_STATUS %is_internal_dbkey);	# defined in maildb.pl

# local globals
use vars qw($folder);
use vars qw($sort $page);
use vars qw($escapedfolder);

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = ow::tool::unescapeURL(param('folder')) || 'INBOX';
$page = param('page') || 1;
$sort = param('sort') || $prefs{'sort'} || 'date_rev';

$escapedfolder=ow::tool::escapeURL($folder);

my $action = param('action')||'';
writelog("debug - request folder begin, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
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
} elsif ($action eq "addfolder" && $config{'enable_userfolders'}) {
   addfolder();
} elsif ($action eq "deletefolder") {
   deletefolder();
} elsif ($action eq "renamefolder" && $config{'enable_userfolders'}) {
   renamefolder();
} elsif ($action eq "downloadfolder") {
   downloadfolder();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request folder end, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## EDITFOLDERS ###########################################
sub editfolders {
   my (@userfolders, @validfolders, $inboxusage, $folderusage);

   getfolders(\@validfolders, \$inboxusage, \$folderusage);
   foreach (@validfolders) {
      push (@userfolders, $_) if (!is_defaultfolder($_));
   }

   my $total_newmessages=0;
   my $total_allmessages=0;
   my $total_foldersize=0;

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editfolders.template"));

   $html =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/g;

   my $folderstr=$lang_folders{$folder}||f2u($folder);
   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $folderstr", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder"|). qq|&nbsp; \n|;
   $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'}, qq|accesskey="R" href="$config{'ow_cgiurl'}/openwebmail-folder.pl?action=refreshfolders&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;page=$page"|). qq| \n|;

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $bgcolor;
   my $currfolder;
   my $form_i=0;
   if ($config{'enable_userfolders'}) {
      templateblock_enable($html, 'USERFOLDERS');

      $bgcolor = $style{"tablerow_dark"};
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-folder.pl").
                  ow::tool::hiddens(action=>'addfolder',
                                    sessionid=>$thissession,
                                    sort=>$sort,
                                    page=>$page,
                                    folder=>$escapedfolder);
      $html =~ s/\@\@\@STARTFOLDERFORM\@\@\@/$temphtml/;

      $temphtml = textfield(-name=>'foldername',
                            -default=>'',
                            -size=> 24,
                            -maxlength=>$config{'foldername_maxlen'},
                            -override=>'1');
#                         -accesskey=>'I',
      $html =~ s/\@\@\@FOLDERNAMEFIELD\@\@\@/$temphtml/;

      $temphtml = submit(-name=>$lang_text{'add'},
                         -accesskey=>'A',
                         -class=>"medtext");
      $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

      $temphtml = end_form();
      $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

      $temphtml='';
      my ($thisfolderprefix, $lastfolderprefix);
      my $categorizedfolders_fs = $prefs{'categorizedfolders_fs'}||'-';
      foreach $currfolder (@userfolders) {
         if ($prefs{'categorizedfolders'} &&
             !is_defaultfolder($currfolder) &&
             !is_lang_defaultfolder($currfolder)) {
            my $folderstr=$lang_folders{$currfolder}||f2u($currfolder);
            if ($folderstr=~/^(.+?)\Q$categorizedfolders_fs\E/) {
               $thisfolderprefix=$1;
               if ($thisfolderprefix ne $lastfolderprefix) {
                  $temphtml .= qq|<tr>|.
                               qq|<td bgcolor=$style{"columnheader"} colspan="5">&nbsp; &nbsp;<b>|.
                               ow::htmltext::str2html($thisfolderprefix).qq|</td>|.
                               qq|</tr>|;
               }
            }
         }

         $temphtml .= _folderline($currfolder, $form_i, $bgcolor,
                                  \$total_newmessages, \$total_allmessages, \$total_foldersize);
         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"};
         } else {
            $bgcolor = $style{"tablerow_dark"};
         }
         $form_i++;

         $lastfolderprefix=$thisfolderprefix;
      }
      $html =~ s/\@\@\@FOLDERS\@\@\@/$temphtml/;

   } else {
      templateblock_disable($html, 'USERFOLDERS');
   }

   $bgcolor = $style{"tablerow_dark"};
   $temphtml='';
   foreach $currfolder (get_defaultfolders()) {
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
               qq|<td bgcolor=$bgcolor>&nbsp;<B>$lang_text{'total'}</B></td>|.
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
   my (%FDB, $newmessages, $allmessages, $foldersize);
   my ($folderfile,$folderdb)=get_folderpath_folderdb($user, $currfolder);

   if (ow::dbm::exist("$folderdb")) {
      ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db ".f2u($folderdb));
      if (defined $FDB{'ALLMESSAGES'}) {
         $allmessages=$FDB{'ALLMESSAGES'};
         ${$r_total_allmessages}+=$allmessages;
      } else {
         $allmessages='&nbsp;';
      }
      if (defined $FDB{'NEWMESSAGES'}) {
         $newmessages=$FDB{'NEWMESSAGES'};
         ${$r_total_newmessages}+=$newmessages;
      } else {
         $newmessages='&nbsp;';
      }
      ow::dbm::close(\%FDB, $folderdb);
   } else {
      $allmessages='&nbsp;';
      $newmessages='&nbsp;';
   }

   # we count size for both folder file and related dbm
   $foldersize = (-s "$folderfile");

   ${$r_total_foldersize}+=$foldersize;
   $foldersize=lenstr($foldersize,0);

   my $escapedcurrfolder = ow::tool::escapeURL($currfolder);
   my $currfolderstr=$lang_folders{$currfolder}||f2u($currfolder);
   my $url = "$config{'ow_cgiurl'}/openwebmail-folder.pl?sessionid=$thissession&amp;folder=$escapedcurrfolder&amp;action=downloadfolder";

   my $accesskeystr=$i%10+1;
   if ($accesskeystr == 10) {
      $accesskeystr=qq|accesskey="0"|;
   } elsif ($accesskeystr < 10) {
      $accesskeystr=qq|accesskey="$accesskeystr"|;
   }

   my ($gifstr, $folderbasename)=('', $currfolderstr);
   if ($prefs{'categorizedfolders'} &&
       !is_defaultfolder($currfolder) &&
       !is_lang_defaultfolder($currfolder)) {
      my $categorizedfolders_fs = $prefs{'categorizedfolders_fs'}||'-';
      if ($currfolderstr=~/^.+?\Q$categorizedfolders_fs\E(.+)$/) {
         $gifstr=qq| &nbsp; - &nbsp; |;
         $folderbasename=$1;
      }
   }
   $temphtml .= qq|<tr>|.
                qq|<td bgcolor=$bgcolor> &nbsp; &nbsp; $gifstr|.
                qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedcurrfolder">|.
                ow::htmltext::str2html($folderbasename).qq| </a>&nbsp;\n|.
                iconlink("download.gif", "$lang_text{'download'} $currfolderstr ", qq|$accesskeystr href="$url"|).
                qq|</td>\n|.
                qq|<td align="center" bgcolor=$bgcolor>$newmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>&nbsp;$allmessages</td>|.
                qq|<td align="center" bgcolor=$bgcolor>&nbsp;$foldersize</td>\n|;

   $temphtml .= qq|<td bgcolor=$bgcolor align="center">\n|;

   $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-folder.pl",
                           -name=>"folderform$i").
                ow::tool::hiddens(action=>'chkindexfolder',
                                  sessionid=>$thissession,
                                  sort=>$sort,
                                  page=>$page,
                                  folder=>$escapedfolder,
                                  foldername=>$escapedcurrfolder,
                                  foldernamestr=>$currfolderstr,
                                  foldernewname=>'')."\n";

   my $jsfolderstr=$currfolderstr; $jsfolderstr=~ s/'/\\'/g;	# escaep ' with \'
   $temphtml .= submit(-name=>$lang_text{'markread'},
                       -class=>"medtext",
                       -onClick=>"return OpConfirm('folderform$i', 'markreadfolder', $lang_text{'foldermarkreadconf'}+' ( $jsfolderstr )')");
   $temphtml .= submit(-name=>$lang_text{'chkindex'},
                       -class=>"medtext",
                       -onClick=>"return OpConfirm('folderform$i', 'chkindexfolder', $lang_text{'folderchkindexconf'}+' ( $jsfolderstr )')");
   $temphtml .= submit(-name=>$lang_text{'reindex'},
                       -class=>"medtext",
                       -onClick=>"return OpConfirm('folderform$i', 'reindexfolder', $lang_text{'folderreindexconf'}+' ( $jsfolderstr )')");
   if ($currfolder ne "INBOX") {
      $temphtml .= submit(-name=>$lang_text{'rename'},
                          -class=>"medtext",
                          -onClick=>"return OpConfirm('folderform$i', 'renamefolder', $lang_text{'folderrenprop'}+' ( $jsfolderstr )')");
   }
   $temphtml .= submit(-name=>$lang_text{'delete'},
                       -class=>"medtext",
                       -onClick=>"return OpConfirm('folderform$i', 'deletefolder', $lang_text{'folderdelconf'}+' ( $jsfolderstr )')");

   $temphtml .= "</td></tr>".end_form()."\n";

   return($temphtml);
}
########## END EDITFOLDERS #######################################

########## REFRESHFOLDERS ########################################
sub refreshfolders {
   my $errcount=0;

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   foreach my $currfolder (@validfolders) {
      my ($folderfile,$folderdb)=get_folderpath_folderdb($user, $currfolder);

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");
      if (update_folderindex($folderfile, $folderdb)<0) {
         $errcount++;
         writelog("db error - Couldn't update db $folderdb");
         writehistory("db error - Couldn't update db $folderdb");
      }
      ow::filelock::lock($folderfile, LOCK_UN);
   }

   writelog("folder - refresh, $errcount errors");
   writehistory("folder - refresh, $errcount errors");

   if ($config{'quota_module'} ne 'none') {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   editfolders();
}
########## END REFRESHFOLDERS ####################################

########## MARKREADFOLDER ########################################
sub markreadfolder {
   my $foldertomark = ow::tool::untaint(safefoldername(ow::tool::unescapeURL(param('foldername')))) || '';
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $foldertomark);

   my $ioerr=0;

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile)."!");

   if (update_folderindex($folderfile, $folderdb)<0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} db ".f2u($folderdb));
   }

   my (%FDB, %offset, %status);
   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db ".f2u($folderdb));
   foreach my $messageid (keys %FDB) {
      next if ($is_internal_dbkey{$messageid});
      my @attr=string2msgattr($FDB{$messageid});
      if ($attr[$_STATUS] !~ /R/i) {
         $offset{$messageid}=$attr[$_OFFSET];
         $status{$messageid}=$attr[$_STATUS];
      }
   }
   ow::dbm::close(\%FDB, $folderdb);
   my @unreadmsgids=(sort { $offset{$a}<=>$offset{$b} } keys %offset);

   my $tmpdir=ow::tool::mktmpdir("markread.tmp"); $ioerr++ if ($tmpdir eq '');
   my $tmpfile=ow::tool::untaint("$tmpdir/folder");
   my $tmpdb=ow::tool::untaint("$tmpdir/db");

   while (!$ioerr && $#unreadmsgids>=0) {
      my @markids=();

      sysopen(F, $tmpfile, O_WRONLY|O_TRUNC|O_CREAT); close(F);
      ow::filelock::lock($tmpfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $tmpfile");

      if (update_folderindex($tmpfile, $tmpdb)<0) {
         ow::filelock::lock($tmpfile, LOCK_UN);
         ow::dbm::unlink($tmpdb);
         unlink($tmpfile);
         rmdir($tmpdir);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} db $tmpdb");
      }

      while (!$ioerr && $#unreadmsgids>=0) {
         my $messageid=shift(@unreadmsgids);

         my $copied=(operate_message_with_ids("copy", [$messageid], $folderfile, $folderdb, $tmpfile, $tmpdb))[0];
         if ($copied>0) {
            if (update_message_status($messageid, $status{$messageid}."R", $tmpdb, $tmpfile)==0) {
               push(@markids, $messageid);
            } else {
               $ioerr++;
            }
         } elsif ($copied<0) {
            $ioerr++;
         }

         my $tmpsize=(stat($tmpfile))[7];
         if ( (!$ioerr && ($tmpsize>10*1024*1024||$#markids>=999)) ||	# tmpfolder size>10MB or marked==1000
              ($ioerr && $tmpsize>0) ||			# any io error
              $#unreadmsgids<0 ) { 			# no more unread msg
            # copy read msg back from tmp folder
            if ($#markids>=0) {
               $ioerr++ if ((operate_message_with_ids("delete", \@markids, $folderfile, $folderdb))[0]<0);
               $ioerr++ if (folder_zapmessages($folderfile, $folderdb)<0);
               $ioerr++ if ((operate_message_with_ids("move", \@markids, $tmpfile, $tmpdb, $folderfile, $folderdb))[0]<0);
            }
            last;	# renew tmp folder and @markids
         }
      }

      ow::dbm::unlink($tmpdb);
      ow::filelock::lock("$tmpfile", LOCK_UN);
      unlink($tmpfile);
      rmdir($tmpdir);
   }

   ow::filelock::lock($folderfile, LOCK_UN);

   writelog("markread folder - $foldertomark");
   writehistory("markread folder - $foldertomark");

   editfolders();
}
########## END MARKREADFOLDER ####################################

########## REINDEXFOLDER #########################################
sub reindexfolder {
   my $recreate=$_[0];
   my $foldertoindex = ow::tool::untaint(safefoldername(ow::tool::unescapeURL(param('foldername')))) || '';
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $foldertoindex);

   ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} ".f2u($folderfile));

   if ($recreate) {
      ow::dbm::unlink($folderdb);
   }
   if (ow::dbm::exist($folderdb) ) {
      my %FDB;
      if (!ow::dbm::open(\%FDB, $folderdb, LOCK_SH)) {
         ow::filelock::lock($folderfile, LOCK_UN);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db ".f2u($folderdb));
      }
      @FDB{'METAINFO', 'LSTMTIME'}=('RENEW', -1);
      ow::dbm::close(\%FDB, $folderdb);
   }
   if (update_folderindex($folderfile, $folderdb)<0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} db ".f2u($folderdb));
   }

   if ($recreate) {
      folder_zapmessages($folderfile, $folderdb);

      writelog("reindex folder - $foldertoindex");
      writehistory("reindex folder - $foldertoindex");
   } else {
      writelog("chkindex folder - $foldertoindex");
      writehistory("chkindex folder - $foldertoindex");
   }

   ow::filelock::lock($folderfile, LOCK_UN);

   editfolders();
}
########## END REINDEXFOLDER #####################################

########## ADDFOLDER #############################################
sub addfolder {
   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];	# get uptodate quotausage
      if ($quotausage>$quotalimit) {
         openwebmailerror(__FILE__, __LINE__, $lang_err{'quotahit_alert'});
      }
   }

   my $foldertoadd = ow::tool::untaint(ow::tool::unescapeURL(param('foldername'))) || ''; # from js field
   $foldertoadd = u2f($foldertoadd);
   is_safefoldername($foldertoadd) or
      openwebmailerror(__FILE__, __LINE__, "$foldertoadd $lang_err{'has_illegal_chars'}");
   $foldertoadd = safefoldername($foldertoadd);
   return editfolders() if ($foldertoadd eq '');

   if (length($foldertoadd) > $config{'foldername_maxlen'}) {
      my $msg=$lang_err{'foldername_long'};
      $msg =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/;
      openwebmailerror(__FILE__, __LINE__, $msg);
   }
   if ( is_defaultfolder($foldertoadd) || is_lang_defaultfolder($foldertoadd) ||
        $foldertoadd eq "$user") {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_folder'} (".f2u($foldertoadd).")");
   }

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $foldertoadd);
   if ( -f $folderfile ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'folder_with_name'} ".f2u($foldertoadd)." $lang_err{'already_exists'}");
   }

   sysopen(FOLDERTOADD, $folderfile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_folder'} ".f2u($foldertoadd)."! ($!)");
   close(FOLDERTOADD) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($foldertoadd)."! ($!)");

   # create empty index dbm with mode 0600
   my %FDB;
   ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderdb));
   ow::dbm::close(\%FDB, $folderdb);

   writelog("create folder - $foldertoadd");
   writehistory("create folder - $foldertoadd");

   editfolders();
}

sub is_lang_defaultfolder {
   foreach (keys %lang_folders) {	# defaultfolder locallized name check
      return 1 if ($_[0] eq $lang_folders{$_} && is_defaultfolder($_));
   }
   return 0;
}
########## END ADDFOLDER #########################################

########## DELETEFOLDER ##########################################
sub deletefolder {
   my $foldertodel = safefoldername(ow::tool::unescapeURL(param('foldername'))) || '';

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $foldertodel);
   if ( -f $folderfile) {
      unlink ($folderfile,
              "$folderfile.lock",
              "$folderfile.lock.lock",
              "$folderdb.cache");
      ow::dbm::unlink($folderdb);

      writelog("delete folder - $foldertodel");
      writehistory("delete folder - $foldertodel");
   }

   if ($quotalimit>0 && $quotausage>$quotalimit) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   editfolders();
}
########## END DELETEFOLDER ######################################

########## RENAMEFOLDER ##########################################
sub renamefolder {
   my $oldname = ow::tool::untaint(safefoldername(ow::tool::unescapeURL(param('foldername')))) || '';
   if ($oldname eq 'INBOX') {
      return editfolders();
   }

   my $newnamestr = ow::tool::untaint(param('foldernewname'))||'';	# from js field
   my $newname = u2f($newnamestr);
   is_safefoldername($newname) or
      openwebmailerror(__FILE__, __LINE__, "$newname $lang_err{'has_illegal_chars'}");
   $newname = safefoldername($newname);
   return editfolders() if ($newname eq '');

   if (length($newname) > $config{'foldername_maxlen'}) {
      my $msg=$lang_err{'foldername_long'};
      $msg =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/;
      openwebmailerror(__FILE__, __LINE__, $msg);
   }
   if ( is_defaultfolder($newname) || is_lang_defaultfolder($newname) ||
        $newname eq "$user") {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_folder'}");
   }

   my ($oldfolderfile, $olddb)=get_folderpath_folderdb($user, $oldname);
   my ($newfolderfile, $newdb)=get_folderpath_folderdb($user, $newname);

   if ( -f $newfolderfile ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'folder_with_name'} $newnamestr $lang_err{'already_exists'}");
   }

   if ( -f $oldfolderfile ) {
      unlink("$oldfolderfile.lock", "$oldfolderfile.lock.lock");
      rename($oldfolderfile, $newfolderfile);
      rename("$olddb.cache", "$newdb.cache");
      ow::dbm::rename($olddb, $newdb);

      writelog("rename folder - $oldname to $newname");
      writehistory("rename folder - $oldname to $newname");
   }

   editfolders();
}
########## END RENAMEFOLDER ######################################

########## DOWNLOAD FOLDER #######################################
sub downloadfolder {
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);


   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderfile));

   my ($cmd, $contenttype, $filename);
   if ( ($cmd=ow::tool::findbin("zip")) ne "" ) {
      $contenttype='application/x-zip-compressed';
      $filename="$folder.zip";
      open(T, "-|") or
         do { open(STDERR,">/dev/null"); exec(ow::tool::untaint($cmd), "-jrq", "-", $folderfile); exit 9 };

   } elsif ( ($cmd=ow::tool::findbin("gzip")) ne "" ) {
      $contenttype='application/x-gzip-compressed';
      $filename="$folder.gz";
      open(T, "-|") or
         do { open(STDERR,">/dev/null"); exec(ow::tool::untaint($cmd), "-c", $folderfile); exit 9 };

   } else {
      $contenttype='text/plain';
      $filename=$folder;
      sysopen(T, $folderfile, O_RDONLY);
   }

   $filename=~s/\s+/_/g;

   # disposition:attachment default to save
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$filename"\n|;
   if ( $ENV{'HTTP_USER_AGENT'}=~/MSIE 5.5/ ) {	# ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$filename"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$filename"\n|;
   }
   print qq|\n|;

   my $buff;
   while ( read(T, $buff,32768) ) {
     print $buff;
   }

   close(T);

   ow::filelock::lock($folderfile, LOCK_UN);

   writelog("download folder - $folder");
   writehistory("download folder - $folder");

   return;
}
########## END DOWNLOADFOLDER ####################################
