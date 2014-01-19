#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009-2014, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;
use warnings FATAL => 'all';

use vars qw($SCRIPT_DIR);

if (-f '/etc/openwebmail_path.conf') {
   my $pathconf = '/etc/openwebmail_path.conf';
   open(F, $pathconf) or die "Cannot open $pathconf: $!";
   my $pathinfo = <F>;
   close(F) or die "Cannot close $pathconf: $!";
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die 'SCRIPT_DIR cannot be set' if $SCRIPT_DIR eq '';
push (@INC, $SCRIPT_DIR);
push (@INC, "$SCRIPT_DIR/lib");

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH} = '/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use CGI 3.31 qw(-private_tempfiles :cgi charset);
use CGI::Carp qw(fatalsToBrowser carpout);
use HTML::Template 2.9;

# load OWM libraries
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
use vars qw(%prefs $icons);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw($htmltemplatefilters $po);             # defined in ow-shared.pl
use vars qw($_OFFSET $_STATUS %is_internal_dbkey); # defined in maildb.pl

# local globals
use vars qw($folder $messageid $sort $msgdatetype $page $longpage $searchtype $keyword);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the webmail module is not enabled.')) unless $config{enable_webmail};

# webmail globals
$folder          = param('folder') || 'INBOX';
$page            = param('page') || 1;
$longpage        = param('longpage') || 0;
$sort            = param('sort') || $prefs{sort} || 'date_rev';
$searchtype      = param('searchtype') || '';
$keyword         = param('keyword') || '';
$msgdatetype     = param('msgdatetype') || $prefs{msgdatetype};
$messageid       = param('message_id') || '';

my $action = param('action') || '';

writelog("debug_request :: request folder begin, action=$action") if $config{debug_request};

$action eq 'refreshfolders' ? refreshfolders() :
$action eq 'addfolder'      ? addfolder()      :
$action eq 'editfolders'    ? editfolders()    :
$action eq 'markreadfolder' ? markreadfolder() :
$action eq 'chkindexfolder' ? reindexfolder(0) :
$action eq 'reindexfolder'  ? reindexfolder(1) :
$action eq 'renamefolder'   ? renamefolder()   :
$action eq 'deletefolder'   ? deletefolder()   :
$action eq 'downloadfolder' ? downloadfolder() :
openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request folder end, action=$action") if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub editfolders {
   my @validfolders = ();
   my $inboxusage   = 0;
   my $folderusage  = 0;
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   my @defaultfolders = get_defaultfolders();

   my @userfolders = $config{enable_userfolders} ? (grep { !is_defaultfolder($_) } @validfolders) : ();

   # get up to date quota usage
   my $enable_quota       = $config{quota_module} eq 'none' ? 0 : 1;
   my $quotashowusage     = 0;
   my $quotaoverthreshold = 0;
   my $quotabytesusage    = 0;
   my $quotapercentusage  = 0;

   if ($enable_quota && $quotalimit > 0) {
      $quotausage         = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
      $quotaoverthreshold = ($quotausage / $quotalimit) > ($config{quota_threshold} / 100);
      $quotashowusage     = ($quotaoverthreshold || $config{quota_threshold} == 0) ? 1 : 0;
      $quotabytesusage    = lenstr($quotausage * 1024, 1) if $quotashowusage;
      $quotapercentusage  = int($quotausage * 1000 / $quotalimit) / 10 if $quotaoverthreshold;
   }

   # prepare the foldersloop
   my $foldersloop       = [];
   my $total_newmessages = 0;
   my $total_allmessages = 0;
   my $total_foldersize  = 0;
   my $lastcategoryname  = '';

   foreach my $currentfolder (@userfolders, @defaultfolders) {
      my $is_defaultfolder     = is_defaultfolder($currentfolder) ? 1 : 0;

      my $is_categorizedfolder = $prefs{categorizedfolders}
                                 && !$is_defaultfolder
                                 && $currentfolder =~ m/^(.+?)[\Q$prefs{categorizedfolders_fs}\E](.+)$/ ? 1 : 0;
      my $categoryname         = $is_categorizedfolder ? $1 : '';
      my $categoryfoldername   = $is_categorizedfolder ? $2 : '';
      my $categorychanged      = $categoryname ne $lastcategoryname ? 1 : 0;

      $lastcategoryname = $categoryname;

      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $currentfolder);

      my $foldersize = (-s $folderfile);
      $foldersize = 0 unless defined $foldersize && $foldersize;

      my $newmessages = 0;
      my $allmessages = 0;

      my %FDB = ();

      if (ow::dbm::existdb($folderdb)) {
         ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
            openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb));

         $allmessages = defined $FDB{ALLMESSAGES} ? $FDB{ALLMESSAGES} : 0;
         $newmessages = defined $FDB{NEWMESSAGES} ? $FDB{NEWMESSAGES} : 0;

         ow::dbm::closedb(\%FDB, $folderdb) or
            openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($folderdb));
      }

      $total_foldersize  += $foldersize;
      $total_newmessages += $newmessages;
      $total_allmessages += $allmessages;

      push(@{$foldersloop}, {
                               # standard params
                               sessionid                   => $thissession,
                               folder                      => $folder,
                               sort                        => $sort,
                               msgdatetype                 => $msgdatetype,
                               page                        => $page,
                               longpage                    => $longpage,
                               searchtype                  => $searchtype,
                               keyword                     => $keyword,
                               url_cgi                     => $config{ow_cgiurl},
                               url_html                    => $config{ow_htmlurl},
                               use_texticon                => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                               charset                     => $prefs{charset},
                               iconset                     => $prefs{iconset},
                               (map { $_, $icons->{$_} } keys %{$icons}),

                               odd                         => (scalar @{$foldersloop} + 1) % 2 == 0 ? 0 : 1,
                               count                       => scalar @{$foldersloop} + 1,
                               is_defaultfolder            => $is_defaultfolder,
                               is_categorizedfolder        => $is_categorizedfolder,
                               categorychanged             => $categorychanged,
                               categoryname                => $categoryname,
                               categoryfoldername          => f2u($categoryfoldername),
                               "foldername_$currentfolder" => 1,
                               foldername                  => f2u($currentfolder),
                               foldersize                  => lenstr($foldersize, 1),
                               newmessages                 => $newmessages,
                               allmessages                 => $allmessages,
                               accesskey                   => (scalar @{$foldersloop} + 1) % 10,
                            }
          );
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("editfolders.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      sessionid                  => $thissession,
                      folder                     => $folder,
                      sort                       => $sort,
                      msgdatetype                => $msgdatetype,
                      page                       => $page,
                      longpage                   => $longpage,
                      searchtype                 => $searchtype,
                      keyword                    => $keyword,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      charset                    => $prefs{charset},
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # editfolders.tmpl
                      enable_quota               => $enable_quota,
                      quotashowusage             => $quotashowusage,
                      quotaoverthreshold         => $quotaoverthreshold,
                      quotabytesusage            => $quotabytesusage,
                      quotapercentusage          => $quotapercentusage,
                      quotalimit                 => $quotalimit,
                      quotaoverlimit             => ($quotalimit > 0 && $quotausage > $quotalimit) ? 1 : 0,
                      is_callerfolderdefault     => is_defaultfolder($folder) ? 1 : 0,
                      "callerfoldername_$folder" => 1,
                      callerfoldername           => f2u($folder),
                      enable_userfolders         => $config{enable_userfolders},
                      foldername_maxlen          => $config{foldername_maxlen},
                      foldername_maxlenstring    => sprintf(ngettext('%d character', '%d characters', $config{foldername_maxlen}), $config{foldername_maxlen}),
                      foldersloop                => $foldersloop,
                      total_newmessages          => $total_newmessages,
                      total_allmessages          => $total_allmessages,
                      total_foldersize           => lenstr($total_foldersize, 1),

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );


   httpprint([], [$template->output]);
}

sub refreshfolders {
   my @validfolders = ();
   my $inboxusage   = 0;
   my $folderusage  = 0;
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   my $errorcount = 0;
   foreach my $currentfolder (@validfolders) {
      my ($folderfile,$folderdb) = get_folderpath_folderdb($user, $currentfolder);

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile));

      if (update_folderindex($folderfile, $folderdb) < 0) {
         $errorcount++;
         writelog("db error - Cannot update db $folderdb");
         writehistory("db error - Cannot update db $folderdb");
      }

      ow::filelock::lock($folderfile, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($folderfile));
   }

   writelog("folder - refresh, $errorcount errors");
   writehistory("folder - refresh, $errorcount errors");

   $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2] if $config{quota_module} ne 'none';

   return editfolders();
}

sub markreadfolder {
   my $foldertomark = ow::tool::untaint(safefoldername(param('foldername'))) || '';

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertomark);

   my $ioerr = 0;

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile) . " ($!)");

   if (update_folderindex($folderfile, $folderdb) < 0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      openwebmailerror(gettext('Cannot update db:') . ' ' . f2u($folderdb));
   }

   my %FDB    = ();
   my %offset = ();
   my %status = ();

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb));

   foreach my $messageid (keys %FDB) {
      next if ($is_internal_dbkey{$messageid});
      my @attr = string2msgattr($FDB{$messageid});
      if ($attr[$_STATUS] !~ m/R/i) {
         $offset{$messageid} = $attr[$_OFFSET];
         $status{$messageid} = $attr[$_STATUS];
      }
   }

   ow::dbm::closedb(\%FDB, $folderdb) or
      openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($folderdb));

   my @unreadmsgids = sort { $offset{$a} <=> $offset{$b} } keys %offset;

   while (!$ioerr && $#unreadmsgids >= 0) {

      my $tmpdir  = ow::tool::mktmpdir('markread.tmp');
      my $tmpfile = ow::tool::untaint("$tmpdir/folder");
      my $tmpdb   = ow::tool::untaint("$tmpdir/db");

      $ioerr++ if $tmpdir eq '';

      my @markids = ();

      sysopen(F, $tmpfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $tmpfile ($!)");

      close(F) or
         openwebmailerror(gettext('Cannot close file:') . " $tmpfile ($!)");

      ow::filelock::lock($tmpfile, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . " $tmpfile ($!)");

      if (update_folderindex($tmpfile, $tmpdb) < 0) {
         ow::dbm::unlinkdb($tmpdb) or
            openwebmailerror(gettext('Cannot delete db:') . " $tmpdb ($!)");

         ow::filelock::lock($tmpfile, LOCK_UN) or
            openwebmailerror(gettext('Cannot unlock file:') . " $tmpfile ($!)");

         unlink($tmpfile) or
            openwebmailerror(gettext('Cannot delete file:') . " $tmpfile ($!)");

         rmdir($tmpdir) or
            openwebmailerror(gettext('Cannot delete directory:') . " $tmpdir ($!)");

         openwebmailerror(gettext('Cannot update db:') . " $tmpdb");
      }

      while (!$ioerr && $#unreadmsgids >= 0) {
         my $messageid = shift(@unreadmsgids);

         my $copied = operate_message_with_ids('copy', [$messageid], $folderfile, $folderdb, $tmpfile, $tmpdb);

         if ($copied > 0) {
            if (update_message_status($messageid, $status{$messageid} . 'R', $tmpdb, $tmpfile) == 0) {
               push(@markids, $messageid);
            } else {
               $ioerr++;
            }
         } elsif ($copied < 0) {
            $ioerr++;
         }

         my $tmpsize = (stat($tmpfile))[7];
         if (
              (!$ioerr && ($tmpsize > 10 * 1024 * 1024 || $#markids >= 999)) # tmpfolder size > 10MB or marked == 1000
              || ($ioerr && $tmpsize > 0)                                    # any io error
              || $#unreadmsgids < 0                                          # no more unread messages
            ) {
            # copy read msg back from tmp folder
            if ($#markids >= 0) {
               $ioerr++ if operate_message_with_ids('delete', \@markids, $folderfile, $folderdb) < 0;
               $ioerr++ if folder_zapmessages($folderfile, $folderdb) < 0;
               $ioerr++ if operate_message_with_ids('move', \@markids, $tmpfile, $tmpdb, $folderfile, $folderdb) < 0;
            }

            last; # renew tmp folder and @markids
         }
      }

      if (ow::dbm::existdb($tmpdb)) {
         ow::dbm::unlinkdb($tmpdb) or
            openwebmailerror(gettext('Cannot delete db:') . " $tmpdb ($!)");
      }

      if (-f $tmpfile) {
         ow::filelock::lock($tmpfile, LOCK_UN) or
            openwebmailerror(gettext('Cannot unlock file:') . " $tmpfile ($!)");

         unlink($tmpfile) or
            openwebmailerror(gettext('Cannot delete file:') . " $tmpfile ($!)");
      }

      rmdir($tmpdir) or
         openwebmailerror(gettext('Cannot delete directory:') . " $tmpdir ($!)");
   }

   ow::filelock::lock($folderfile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . " $folderfile ($!)");

   writelog("markread folder - $foldertomark");
   writehistory("markread folder - $foldertomark");

   return editfolders();
}

sub reindexfolder {
   my $reindex = shift; # boolean

   my $foldertoindex = ow::tool::untaint(safefoldername(param('foldername'))) || '';
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertoindex);

   ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile));

   if ($reindex) {
      # remove the old index db
      ow::dbm::unlinkdb($folderdb) or
         openwebmailerror(gettext('Cannot delete file:') . ' ' . f2u($folderdb));
   }

   if (ow::dbm::existdb($folderdb)) {
      my %FDB = ();

      if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH)) {
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
         openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb));
      }

      @FDB{'METAINFO', 'LSTMTIME'} = ('RENEW', -1);

      ow::dbm::closedb(\%FDB, $folderdb) or
         openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($folderdb));
   }

   if (update_folderindex($folderfile, $folderdb) < 0) {
      ow::filelock::lock($folderfile, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($folderfile));

      openwebmailerror(gettext('Cannot update db:') . ' ' . f2u($folderdb));
   }

   if ($reindex) {
      folder_zapmessages($folderfile, $folderdb);

      writelog("reindex folder - $foldertoindex");
      writehistory("reindex folder - $foldertoindex");
   } else {
      writelog("chkindex folder - $foldertoindex");
      writehistory("chkindex folder - $foldertoindex");
   }

   ow::filelock::lock($folderfile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($folderfile));

   return editfolders();
}

sub addfolder {
   return editfolders() unless $config{enable_userfolders};

   if ($quotalimit > 0 && ($quotausage > $quotalimit)) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get current quotausage
      openwebmailerror(gettext('Quota limit exceeded. Please delete some messages or webdisk files to free disk space.'))
        if $quotausage > $quotalimit;
   }

   my $foldertoadd = ow::tool::untaint(param('foldername')) || ''; # from js field
   $foldertoadd = u2f($foldertoadd);

   openwebmailerror(gettext('Illegal characters in folder name:') . " $foldertoadd")
     unless is_safefoldername($foldertoadd);

   $foldertoadd = safefoldername($foldertoadd);
   return editfolders() if $foldertoadd eq '';

   openwebmailerror(sprintf(ngettext('Folder name exceeds the %d character limit:', 'Folder name exceeds the %d character limit:', $config{foldername_maxlen}), $config{foldername_maxlen}) . " $foldertoadd")
     if length $foldertoadd > $config{foldername_maxlen};

   openwebmailerror(gettext('The folder name is reserved by the system and cannot be used:') . ' ' . f2u($foldertoadd))
     if is_defaultfolder($foldertoadd) || $foldertoadd eq $user;

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertoadd);

   openwebmailerror(gettext('Folder already exists:') . ' ' . f2u($foldertoadd))
     if -f $folderfile;

   sysopen(FOLDERTOADD, $folderfile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($foldertoadd) . " ($!)");

   close(FOLDERTOADD) or
      openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($foldertoadd) . " ($!)");

   # create empty index dbm with mode 0600
   my %FDB = ();

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or
      openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb));

   ow::dbm::closedb(\%FDB, $folderdb) or
      openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($folderdb));

   writelog("create folder - $foldertoadd");
   writehistory("create folder - $foldertoadd");

   return reindexfolder();
}

sub deletefolder {
   my $foldertodel = ow::tool::untaint(safefoldername(param('foldername'))) || '';

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertodel);
   if (-f $folderfile) {
      unlink ($folderfile, "$folderfile.lock", "$folderfile.lock.lock", "$folderdb.cache") or
         openwebmailerror(gettext('Cannot delete file:') . "$folderfile, $folderfile.lock, $folderfile.lock.lock, $folderdb.cache. ($!)");

      if (-f $folderdb) {
         ow::dbm::unlinkdb($folderdb) or
            openwebmailerror(gettext('Cannot delete db:') . ' ' . f2u($folderdb));
      }

      writelog("delete folder - $foldertodel");
      writehistory("delete folder - $foldertodel");
   }

   if ($quotalimit > 0 && $quotausage > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }

   return editfolders();
}

sub renamefolder {
   return editfolders() unless $config{enable_userfolders};

   my $oldname = ow::tool::untaint(safefoldername(param('foldername'))) || '';
   return editfolders() if $oldname eq 'INBOX';

   my $newnamestr = ow::tool::untaint(param('foldernewname')) || ''; # from js field
   my $newname = u2f($newnamestr);

   openwebmailerror(gettext('Illegal characters in folder name:') . " $newname")
     unless is_safefoldername($newname);

   $newname = safefoldername($newname);
   return editfolders() if $newname eq '';

   openwebmailerror(sprintf(ngettext('Folder name exceeds the %d character limit:', 'Folder name exceeds the %d character limit:', $config{foldername_maxlen}), $config{foldername_maxlen}) . " $newname")
     if length $newname > $config{foldername_maxlen};

   openwebmailerror(gettext('The folder name is reserved by the system and cannot be used:') . ' ' . f2u($newname))
     if is_defaultfolder($newname) || $newname eq $user;

   my ($oldfolderfile, $olddb) = get_folderpath_folderdb($user, $oldname);
   my ($newfolderfile, $newdb) = get_folderpath_folderdb($user, $newname);

   openwebmailerror(gettext('Folder already exists:') . ' ' . f2u($newname))
     if -f $newfolderfile;

   if (-f $oldfolderfile) {
      if (-f "$oldfolderfile.lock" || -f "$oldfolderfile.lock.lock") {
         unlink("$oldfolderfile.lock", "$oldfolderfile.lock.lock") or
            openwebmailerror(gettext('Cannot delete file:') . " $oldfolderfile.lock, $oldfolderfile.lock.lock ($!)");
      }

      rename($oldfolderfile, $newfolderfile) or
         openwebmailerror(gettext('Cannot rename file:') . " $oldfolderfile -> $newfolderfile ($!)");

      if (-f "$olddb.cache") {
         rename("$olddb.cache", "$newdb.cache") or
            openwebmailerror(gettext('Cannot rename file:') . " $olddb.cache -> $newdb.cache ($!)");
      }

      ow::dbm::renamedb($olddb, $newdb) or
         openwebmailerror(gettext('Cannot rename db:') . " $olddb -> $newdb ($!)");

      writelog("rename folder - $oldname to $newname");
      writehistory("rename folder - $oldname to $newname");
   }

   editfolders();
}

sub downloadfolder {
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile));

   my ($cmd, $contenttype, $filename) = ('','','');
   if (($cmd = ow::tool::findbin('zip')) ne '') {
      $contenttype = 'application/x-zip-compressed';
      $filename = "$folder.zip";
      open(T, "-|") or
         do {
              open(STDERR,">/dev/null");
              exec(ow::tool::untaint($cmd), "-jrq", "-", $folderfile);
              exit 9
            };
   } elsif (($cmd = ow::tool::findbin("gzip")) ne '') {
      $contenttype = 'application/x-gzip-compressed';
      $filename = "$folder.gz";
      open(T, "-|") or
         do {
              open(STDERR,">/dev/null");
              exec(ow::tool::untaint($cmd), "-c", $folderfile);
              exit 9
            };
   } else {
      $contenttype = 'text/plain';
      $filename = $folder;
      sysopen(T, $folderfile, O_RDONLY) or writelog("cannot open file $folderfile");
   }

   $filename =~ s/\s+/_/g;

   # disposition:attachment default to save
   print qq|Connection: close\n| .
         qq|Content-Type: $contenttype; name="$filename"\n| .
         (
            # ie5.5 is broken with content-disposition: attachment
            $ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/
            ? qq|Content-Disposition: filename="$filename"\n|
            : qq|Content-Disposition: attachment; filename="$filename"\n|
         ) .
         qq|\n|;

   my $buff = '';

   print $buff while read(T, $buff, 32768);

   close(T) or writelog("cannot close pipe or file");

   ow::filelock::lock($folderfile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($folderfile));

   writelog("download folder - $folder");
   writehistory("download folder - $folder");

   return 0;
}
