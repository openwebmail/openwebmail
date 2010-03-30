#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009-2010, The OpenWebMail Project
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
use warnings;

use vars qw($SCRIPT_DIR);

if (-f "/etc/openwebmail_path.conf") {
   my $pathconf = "/etc/openwebmail_path.conf";
   open(F, $pathconf) or die("Cannot open $pathconf: $!");
   my $pathinfo = <F>;
   close(F) or die("Cannot close $pathconf: $!");
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die("SCRIPT_DIR cannot be set") if $SCRIPT_DIR eq '';
push (@INC, $SCRIPT_DIR);

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH} = '/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :cgi charset);
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
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw($htmltemplatefilters);                 # defined in ow-shared.pl
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy
use vars qw($_OFFSET $_STATUS %is_internal_dbkey);	# defined in maildb.pl

# local globals
use vars qw($folder $sort $page);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(__FILE__, __LINE__, "$lang_text{webmail} $lang_err{access_denied}") if !$config{enable_webmail};

$folder = param('folder') || 'INBOX';
$page   = param('page') || 1;
$sort   = param('sort') || $prefs{sort} || 'date_rev';

my $action = param('action') || '';

writelog("debug - request folder begin, action=$action - " .__FILE__.":". __LINE__) if $config{debug_request};

$action eq "editfolders"                                 ? editfolders()    :
$action eq "refreshfolders"                              ? refreshfolders() :
$action eq "markreadfolder"                              ? markreadfolder() :
$action eq "chkindexfolder"                              ? reindexfolder(0) :
$action eq "reindexfolder"                               ? reindexfolder(1) :
$action eq "downloadfolder"                              ? downloadfolder() :
$action eq "deletefolder"                                ? deletefolder()   :
$action eq "addfolder"    && $config{enable_userfolders} ? addfolder()      :
$action eq "renamefolder" && $config{enable_userfolders} ? renamefolder()   :
openwebmailerror(__FILE__, __LINE__, "Action $lang_err{has_illegal_chars}");

writelog("debug - request folder end, action=$action - " .__FILE__.":". __LINE__) if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub editfolders {
   my (@defaultfolders, @validfolders, $inboxusage, $folderusage);
   my @userfolders           = ();
   my $enable_userfolders    = $config{enable_userfolders};
   my $url_cgi               = $config{ow_cgiurl};
   my $url_html              = $config{ow_htmlurl};
   my $foldername_maxlen     = $config{foldername_maxlen};
   my $usingquota            = ($config{quota_module} ne 'none') ? 1 : 0;
   my $categorizedfolders    = $prefs{categorizedfolders};
   my $categorizedfolders_fs = $prefs{categorizedfolders_fs} || '-';
   my $total_newmessages     = 0;
   my $total_allmessages     = 0;
   my $total_foldersize      = 0;
   my $currfolder            = '';
   my $percent               = 0;
   my $foldersloop           = [];
   my $thiscategory          = '';
   my $lastcategory          = '';

   getfolders(\@validfolders, \$inboxusage, \$folderusage);
   @defaultfolders = get_defaultfolders();

   if ($enable_userfolders) {
      foreach (@validfolders) {
         push (@userfolders, $_) if (!is_defaultfolder($_) && !is_lang_defaultfolder($_));
      }
   }

   if ($quotalimit > 0) {
      $percent = $usingquota ? int($quotausage * 1000 / $quotalimit) / 10 : 0;
   }

   foreach $currfolder (@userfolders, @defaultfolders) {
      my $folder_n          = scalar @{$foldersloop};
      my $userfolder        = $folder_n <= scalar(@userfolders);
      my $categorizedfolder = 0;
      my $categorytitle     = '';
      my $folderstr         = $lang_folders{$currfolder} || f2u($currfolder);
      my $folderbasename    = $folderstr;
      my $newmessages       = 0;
      my $allmessages       = 0;
      my $foldersize        = 0;

      if ($userfolder) {
         if ($categorizedfolders && ($folderstr =~ m/^(.+?)\Q$categorizedfolders_fs\E(.+)$/)) {
            $categorizedfolder = 1;
            $thiscategory      = $1;
            $categorytitle     = ($thiscategory ne $lastcategory) ? $thiscategory : '';
            $lastcategory      = $thiscategory;
            $folderbasename    = $2;
         }
      }

      get_folderdata($currfolder, \$newmessages, \$allmessages, \$foldersize);
      $total_newmessages += $newmessages if $newmessages ne '';
      $total_allmessages += $allmessages if $allmessages ne '';
      $total_foldersize  += $foldersize;
      push(@{$foldersloop}, {
                               url_cgi           => $url_cgi,
                               url_html          => $url_html,
                               sessionid         => $thissession,
                               iconset           => $prefs{iconset},
                               sort              => $sort,
                               page              => $page,
                               odd               => ($folder_n + 1) % 2 > 0 ? 1 : 0,
                               folder_n          => $folder_n,
                               categorytitle     => $categorytitle,
                               categorizedfolder => $categorizedfolder,
                               currfolder        => $currfolder,
                               folderbasename    => $folderbasename,
                               accesskey         => ($folder_n + 1) % 10,
                               inbox             => $currfolder eq 'INBOX' ? 1 : 0,
                               newmessages       => $newmessages,
                               allmessages       => $allmessages,
                               foldersize        => lenstr($foldersize)
                            }
          );
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("editfolders.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # standard params
                      use_texticon       => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                      url_html           => $config{ow_htmlurl},
                      url_cgi            => $config{ow_cgiurl},
                      iconset            => $prefs{iconset},
                      sessionid          => $thissession,
                      folder             => $folder,
                      sort               => $sort,
                      page               => $page,

                      # editfolders.tmpl
                      callerfoldername   => $lang_folders{$folder} || f2u($folder),
                      enable_userfolders => $enable_userfolders,
                      foldername_maxlen  => $foldername_maxlen,
                      foldersloop        => $foldersloop,
                      total_newmessages  => $total_newmessages,
                      total_allmessages  => $total_allmessages,
                      total_foldersize   => lenstr($total_foldersize),
                      quotausage         => $usingquota ? lenstr($quotausage * 1024, 1) : 0,
                      overquota          => $percent > 90 ? 1 : 0,
                      quotalimit         => $quotalimit > 0 ? lenstr($quotalimit * 1024, 1) : 0,
                      percent            => $percent,

                      # footer.tmpl
                      footer_template    => get_footer($config{footer_template_file}),
                   );


   httpprint([], [$template->output]);
}

sub get_folderdata {
   my ($currfolder, $r_newmessages, $r_allmessages, $r_foldersize) = @_;

   my %FDB;
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $currfolder);

   if (ow::dbm::exist("$folderdb")) {
      ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db " . f2u($folderdb));
      ${$r_allmessages} = defined $FDB{ALLMESSAGES} ? $FDB{ALLMESSAGES} : '';
      ${$r_newmessages} = defined $FDB{NEWMESSAGES} ? $FDB{NEWMESSAGES} : '';
      ow::dbm::close(\%FDB, $folderdb);
   } else {
      ${$r_allmessages} = '';
      ${$r_newmessages} = '';
   }

   ${$r_foldersize} = (-s $folderfile);
}

sub is_lang_defaultfolder {
   foreach (keys %lang_folders) { # defaultfolder localized name check
      return 1 if ($_[0] eq $lang_folders{$_} && is_defaultfolder($_));
   }
   return 0;
}

sub refreshfolders {
   my $errcount = 0;

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   foreach my $currfolder (@validfolders) {
      my ($folderfile,$folderdb) = get_folderpath_folderdb($user, $currfolder);

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");

      if (update_folderindex($folderfile, $folderdb) < 0) {
         $errcount++;
         writelog("db error - Couldn't update db $folderdb");
         writehistory("db error - Couldn't update db $folderdb");
      }

      ow::filelock::lock($folderfile, LOCK_UN);
   }

   writelog("folder - refresh, $errcount errors");
   writehistory("folder - refresh, $errcount errors");

   if ($config{quota_module} ne 'none') {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   editfolders();
}

sub markreadfolder {
   my $foldertomark = ow::tool::untaint(safefoldername(param('foldername'))) || '';
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertomark);

   my $ioerr = 0;

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");

   if (update_folderindex($folderfile, $folderdb) < 0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_updatedb} db " . f2u($folderdb));
   }

   my (%FDB, %offset, %status);

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db " . f2u($folderdb));

   foreach my $messageid (keys %FDB) {
      next if ($is_internal_dbkey{$messageid});
      my @attr = string2msgattr($FDB{$messageid});
      if ($attr[$_STATUS] !~ m/R/i) {
         $offset{$messageid} = $attr[$_OFFSET];
         $status{$messageid} = $attr[$_STATUS];
      }
   }

   ow::dbm::close(\%FDB, $folderdb);

   my @unreadmsgids = sort { $offset{$a} <=> $offset{$b} } keys %offset;

   my $tmpdir  = ow::tool::mktmpdir('markread.tmp');
   my $tmpfile = ow::tool::untaint("$tmpdir/folder");
   my $tmpdb   = ow::tool::untaint("$tmpdir/db");

   $ioerr++ if $tmpdir eq '';

   while (!$ioerr && $#unreadmsgids >= 0) {
      my @markids = ();

      sysopen(F, $tmpfile, O_WRONLY|O_TRUNC|O_CREAT); close(F);
      ow::filelock::lock($tmpfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} $tmpfile");

      if (update_folderindex($tmpfile, $tmpdb) < 0) {
         ow::filelock::lock($tmpfile, LOCK_UN);
         ow::dbm::unlink($tmpdb);
         unlink($tmpfile);
         rmdir($tmpdir);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_updatedb} db $tmpdb");
      }

      while (!$ioerr && $#unreadmsgids >= 0) {
         my $messageid = shift(@unreadmsgids);

         my $copied = (operate_message_with_ids("copy", [$messageid], $folderfile, $folderdb, $tmpfile, $tmpdb))[0];
         if ($copied > 0) {
            if (update_message_status($messageid, $status{$messageid}."R", $tmpdb, $tmpfile) == 0) {
               push(@markids, $messageid);
            } else {
               $ioerr++;
            }
         } elsif ($copied < 0) {
            $ioerr++;
         }

         my $tmpsize = (stat($tmpfile))[7];
         if (
              ( !$ioerr && ($tmpsize > 10 * 1024 * 1024 || $#markids >= 999) ) # tmpfolder size > 10MB or marked == 1000
              || ($ioerr && $tmpsize > 0)                                      # any io error
              || $#unreadmsgids < 0                                            # no more unread msg
            ) {
            # copy read msg back from tmp folder
            if ($#markids >= 0) {
               $ioerr++ if ((operate_message_with_ids('delete', \@markids, $folderfile, $folderdb))[0] < 0);
               $ioerr++ if (folder_zapmessages($folderfile, $folderdb) < 0);
               $ioerr++ if ((operate_message_with_ids('move', \@markids, $tmpfile, $tmpdb, $folderfile, $folderdb))[0] < 0);
            }

            last; # renew tmp folder and @markids
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

sub reindexfolder {
   my $recreate = shift;
   my $foldertoindex = ow::tool::untaint(safefoldername(param('foldername'))) || '';
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertoindex);

   ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} " . f2u($folderfile));

   if ($recreate) {
      ow::dbm::unlink($folderdb);
   }
   if (ow::dbm::exist($folderdb)) {
      my %FDB;
      if (!ow::dbm::open(\%FDB, $folderdb, LOCK_SH)) {
         ow::filelock::lock($folderfile, LOCK_UN);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db " . f2u($folderdb));
      }
      @FDB{'METAINFO', 'LSTMTIME'} = ('RENEW', -1);
      ow::dbm::close(\%FDB, $folderdb);
   }
   if (update_folderindex($folderfile, $folderdb) < 0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_updatedb} db " . f2u($folderdb));
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

sub addfolder {
   if ($quotalimit > 0 && ($quotausage > $quotalimit)) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate quotausage
      if ($quotausage > $quotalimit) {
         openwebmailerror(__FILE__, __LINE__, $lang_err{quotahit_alert});
      }
   }

   my $foldertoadd = ow::tool::untaint(param('foldername')) || ''; # from js field
   $foldertoadd = u2f($foldertoadd);
   is_safefoldername($foldertoadd) or
      openwebmailerror(__FILE__, __LINE__, "$foldertoadd $lang_err{has_illegal_chars}");
   $foldertoadd = safefoldername($foldertoadd);
   return editfolders() if $foldertoadd eq '';

   if (length($foldertoadd) > $config{foldername_maxlen}) {
      my $msg = $lang_err{foldername_long};
      $msg =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{foldername_maxlen}/;
      openwebmailerror(__FILE__, __LINE__, $msg);
   }

   if (
        is_defaultfolder($foldertoadd)
        || is_lang_defaultfolder($foldertoadd)
        || $foldertoadd eq $user
      ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{cant_create_folder} (" . f2u($foldertoadd) . ')');
   }

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertoadd);
   if (-f $folderfile) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{folder_with_name} " . f2u($foldertoadd) . " $lang_err{already_exists}");
   }

   sysopen(FOLDERTOADD, $folderfile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{cant_create_folder} " . f2u($foldertoadd) . "! ($!)");
   close(FOLDERTOADD) or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} " . f2u($foldertoadd) . "! ($!)");

   # create empty index dbm with mode 0600
   my %FDB;
   ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderdb));
   ow::dbm::close(\%FDB, $folderdb);

   writelog("create folder - $foldertoadd");
   writehistory("create folder - $foldertoadd");

   reindexfolder();
}

sub deletefolder {
   my $foldertodel = ow::tool::untaint(safefoldername(param('foldername'))) || '';

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertodel);
   if (-f $folderfile) {
      unlink ($folderfile,
              "$folderfile.lock",
              "$folderfile.lock.lock",
              "$folderdb.cache");
      ow::dbm::unlink($folderdb);

      writelog("delete folder - $foldertodel");
      writehistory("delete folder - $foldertodel");
   }

   if ($quotalimit > 0 && $quotausage > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   editfolders();
}

sub renamefolder {
   my $oldname = ow::tool::untaint(safefoldername(param('foldername'))) || '';
   if ($oldname eq 'INBOX') {
      return editfolders();
   }

   my $newnamestr = ow::tool::untaint(param('foldernewname')) || ''; # from js field
   my $newname = u2f($newnamestr);
   is_safefoldername($newname) or
      openwebmailerror(__FILE__, __LINE__, "$newname $lang_err{has_illegal_chars}");
   $newname = safefoldername($newname);
   return editfolders() if $newname eq '';

   if (length($newname) > $config{foldername_maxlen}) {
      my $msg = $lang_err{foldername_long};
      $msg =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{foldername_maxlen}/;
      openwebmailerror(__FILE__, __LINE__, $msg);
   }

   if (
        is_defaultfolder($newname)
        || is_lang_defaultfolder($newname)
        || $newname eq $user
      ) {
      openwebmailerror(__FILE__, __LINE__, $lang_err{cant_create_folder});
   }

   my ($oldfolderfile, $olddb) = get_folderpath_folderdb($user, $oldname);
   my ($newfolderfile, $newdb) = get_folderpath_folderdb($user, $newname);

   if (-f $newfolderfile) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{folder_with_name} $newnamestr $lang_err{already_exists}");
   }

   if (-f $oldfolderfile) {
      unlink("$oldfolderfile.lock", "$oldfolderfile.lock.lock");
      rename($oldfolderfile, $newfolderfile);
      rename("$olddb.cache", "$newdb.cache");
      ow::dbm::rename($olddb, $newdb);

      writelog("rename folder - $oldname to $newname");
      writehistory("rename folder - $oldname to $newname");
   }

   editfolders();
}

sub downloadfolder {
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile));

   my ($cmd, $contenttype, $filename) = ('','','');
   if (($cmd = ow::tool::findbin("zip")) ne '') {
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
      sysopen(T, $folderfile, O_RDONLY);
   }

   $filename =~ s/\s+/_/g;

   # disposition:attachment default to save
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$filename"\n|;
   if ($ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/) {
      # ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$filename"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$filename"\n|;
   }
   print qq|\n|;

   my $buff;
   while (read(T, $buff, 32768)) {
     print $buff;
   }

   close(T);

   ow::filelock::lock($folderfile, LOCK_UN);

   writelog("download folder - $folder");
   writehistory("download folder - $folder");

   return;
}
