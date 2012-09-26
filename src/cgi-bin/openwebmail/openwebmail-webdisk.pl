#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009, The OpenWebMail Project
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
#

# To prevent shell escape, all external commands are executed through exec
# with parameters in an array, this makes perl call execvp directly instead
# of invoking the /bin/sh
#
# Path names from CGI are treated as virtual paths under $webdiskrootdir
# ($homedir/$config{webdisk_rootpath}), and all pathnames will be prefixed
# with $webdiskrootdir before passing to external command for security
#
# To disable the use of symbolic link, please refer to openwebmail.conf.help
# for options webdisk_lssymlink and webdisk_allow_symlinkout

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

# define the hook used to track file uploads
CGI::upload_hook(\&track_upload);

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/execute.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/htmltext.pl";
require "modules/wget.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/cut.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config);
use vars qw($thissession);
use vars qw($domain $user $homedir);
use vars qw($quotausage $quotalimit);
use vars qw(%prefs $icons);
use vars qw($htmltemplatefilters $po);     # defined in ow-shared.pl

# local globals
use vars qw($folder $messageid $sort $msgdatetype $page $longpage $searchtype $keyword);
use vars qw($webdiskrootdir $wdpage $wdsearchtype $wdkeyword);

# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the webdisk module is not enabled.')) if !$config{enable_webdisk};

# userenv_init() will set umask to 0077 to protect mail folder data.
# set umask back to 0022 here so that directories and files are created world-readable
umask(0022);

# webmail globals
$folder          = param('folder') || 'INBOX';
$page            = param('page') || 1;
$longpage        = param('longpage') || 0;
$sort            = param('sort') || $prefs{sort} || 'date_rev';
$searchtype      = param('searchtype') || '';
$keyword         = param('keyword') || '';
$msgdatetype     = param('msgdatetype') || $prefs{msgdatetype};
$messageid       = param('message_id') || '';

# webdisk globals
$wdpage          = param('wdpage') || 1;
$wdsearchtype    = param('wdsearchtype') || '';
$wdkeyword       = param('wdkeyword') || '';

$wdkeyword       =~ s/[`;\|]//g;

if (param('clearsearchbutton')) {
  $wdkeyword  = '';
  $wdpage     = 1;
}

$webdiskrootdir = ow::tool::untaint($homedir . absolute_vpath('/', $config{webdisk_rootpath}));
$webdiskrootdir =~ s/\/+$//; # remove trailing slash

if (!-d $webdiskrootdir) {
   mkdir($webdiskrootdir, 0755) or
      openwebmailerror(gettext('Cannot create directory:') . " $webdiskrootdir ($!)");
}

# all path in param are treated as virtual path under $webdiskrootdir.
my $currentdir = defined param('currentdir') && param('currentdir') ne ''
                 ? param('currentdir')
                 : cookie("ow-currentdir-$domain-$user");
$currentdir    = ow::tool::untaint(absolute_vpath('/', $currentdir));

my $gotodir    = param('gotodir') || '';
$gotodir       = absolute_vpath($currentdir, $gotodir);

my @selitems   = param('selitems');
my $destname   = param('destname') || '';
my $filesort   = param('filesort') || 'name';

verify_vpath($webdiskrootdir, $currentdir);

my $action = param('action')                ? param('action')  :
             param('mkdirbutton')           ? 'mkdir'          :
             param('newfilebutton')         ? 'newfile'        :
             param('copybutton')            ? 'copy'           :
             param('movebutton')            ? 'move'           :
             param('symlinkbutton')         ? 'symlink'        :
             param('deletebutton')          ? 'delete'         :
             param('chmodbutton')           ? 'chmod'          :
             param('editbutton')            ? 'editfile'       :
             param('savebutton')            ? 'savefile'       :
             param('gzipbutton')            ? 'gzip'           :
             param('mkzipbutton')           ? 'mkzip'          :
             param('mktgzbutton')           ? 'mktgz'          :
             param('extractarchivebutton')  ? 'extractarchive' :
             param('listarchivebutton')     ? 'listarchive'    :
             param('wordpreviewbutton')     ? 'wordpreview'    :
             param('mkpdfbutton')           ? 'mkpdf'          :
             param('mkpsbutton')            ? 'mkps'           :
             param('mkthumbnailbutton')     ? 'mkthumbnail'    :
             param('downloadbutton')        ? 'download'       :
             param('uploadbutton')          ? 'upload'         : 'showdir';

writelog("debug_request :: request webdisk begin, action=$action, currentdir=$currentdir") if $config{debug_request};

openwebmailerror(gettext('The operation cannot be completed because the webdisk is read-only.'))
   if $action =~ m/^(?:mkdir|newfile|copy|move|symlink|delete|chmod|gzip|mkzip|mktgz|extractarchive|mkpdf|mkps|mkthumbnail|upload)$/ && $config{webdisk_readonly};

autoclosewindow(gettext('Edit Failed'), gettext('Editing is disabled because the webdisk is read-only'))
   if $action =~ m/^(?:editfile|savefile|send_saveatt|read_saveatt)$/ && $config{webdisk_readonly};

openwebmailerror(gettext('Quota limit exceeded. Please delete some messages or webdisk files to free disk space.'))
   if $action =~ m/^(?:mkdir|newfile|copy|move|symlink|gzip|mkzip|mktgz|extractarchive|mkpdf|mkps|mkthumbnail|upload)$/ && !is_quota_available(0);

autoclosewindow(gettext('QUOTA HIT'), gettext('Quota limit exceeded. Please delete some messages or webdisk files to free disk space.'))
   if $action =~ m/^(?:editfile|savefile|send_saveatt|read_saveatt)$/ && !is_quota_available(0);

openwebmailerror(gettext('The requested operation can only be performed on one file or directory at a time:') . " ($action)")
   if $action =~ m/^(?:viewinline|symlink|editfile|savefile|send_addatt|send_saveatt|read_saveatt|extractarchive|listarchive|wordpreview|mkpdf|mkps|preview)$/ && scalar @selitems > 1;

openwebmailerror(gettext('No file has been selected for the requested operation:') . " ($action)")
   if $action =~ m/^(?:viewinline|editfile|copy|move|symlink|delete|chmod|gzip|mkzip|mktgz|mkpdf|mkps|mkthumbnail|extractarchive|listarchive|wordpreview|mkpdf|mkps|preview|download)$/ && scalar @selitems < 1;

my $msg = '';

if ($action eq 'mkdir') {
   $msg = createdir($currentdir, $destname) if $destname;
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'newfile') {
   $msg = createfile($currentdir, $destname) if $destname;
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'copy') {
   $msg = copymovesymlink_dirfiles('copy', $currentdir, $destname, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'move') {
   $msg = copymovesymlink_dirfiles('move', $currentdir, $destname, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'symlink' &&  $config{webdisk_allow_symlinkcreate}) {
   $msg = copymovesymlink_dirfiles('symlink', $currentdir, $destname, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'delete') {
   $msg = deletedirfiles($currentdir, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'chmod' &&  $config{webdisk_allow_chmod}) {
   $msg = chmoddirfiles(param('permission'), $currentdir, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'editfile') {
   editfile($currentdir, $selitems[0]);
} elsif ($action eq 'savefile') {
   savefile($currentdir, $destname, param('filecontent')) if $destname ne '';
} elsif ($action eq 'gzip' && $config{webdisk_allow_gzip}) {
   $msg = compressfiles('gzip', $currentdir, '', @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'mkzip' && $config{webdisk_allow_zip}) {
   $msg = compressfiles('mkzip', $currentdir, $destname, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'mktgz' && $config{webdisk_allow_tar}) {
   $msg = compressfiles('mktgz', $currentdir, $destname, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'extractarchive') {
   $msg = extractarchive($currentdir, $selitems[0]);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'listarchive' && $config{webdisk_allow_listarchive}) {
   $msg = listarchive($currentdir, $selitems[0]);
} elsif ($action eq 'wordpreview') {
   $msg = wordpreview($currentdir, $selitems[0]);
} elsif ($action eq 'mkpdf') {
   $msg = makepdfps('mkpdf', $currentdir, $selitems[0]);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'mkps') {
   $msg = makepdfps('mkps', $currentdir, $selitems[0]);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'mkthumbnail') {
   $msg = makethumbnail($currentdir, @selitems);
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'viewinline') {
   $msg = viewinline($currentdir, $selitems[0]);
} elsif ($action eq 'preview') {
   my $vpath       = absolute_vpath($currentdir, $selitems[0]);
   my $filecontent = param('filecontent') || '';

   if ($filecontent) {
      previewfile($currentdir, $selitems[0], $filecontent);
   } elsif (-d "$webdiskrootdir/$vpath") {
      showdir($currentdir, $vpath, $filesort, $wdpage, $msg);
   } else {
      previewfile($currentdir, $selitems[0], '');
   }
} elsif ($action eq 'download') {
   if (scalar @selitems > 1) {
      $msg = downloadfiles($currentdir, @selitems);
   } else {
      my $vpath = absolute_vpath($currentdir, $selitems[0]);

      if (-d "$webdiskrootdir/$vpath") {
         $msg = downloadfiles($currentdir, @selitems);
      } else {
         $msg = downloadfile($currentdir, $selitems[0]);
      }
   }
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg) if defined $msg && $msg ne '';
} elsif ($action eq 'upload') {
   # name and handle of the upload file
   my $upload = param('upload');
   $msg = uploadfile($currentdir, $upload) if defined $upload && $upload;
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'send_addatt') {
   # used in message compose to add an attachment
   dirfilesel($action, $currentdir, $gotodir, $filesort, $wdpage);
} elsif ($action eq 'send_saveatt' || $action eq 'read_saveatt') {
   # send_saveatt used in message compose to save an attachment
   # read_saveatt used in message reading to save an attachment
   dirfilesel($action, $currentdir, $gotodir, $filesort, $wdpage);
} elsif ($action eq 'userrefresh')  {
   $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]
      if $config{quota_module} ne 'none';
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} elsif ($action eq 'showdir')  {
   showdir($currentdir, $gotodir, $filesort, $wdpage, $msg);
} else {
   openwebmailerror(gettext('Action has illegal characters.'));
}

writelog("debug_request :: request webdisk end, action=$action, currentdir=$currentdir") if $config{debug_request};

openwebmail_requestend();

# BEGIN SUBROUTINES


sub showdir {
   my ($olddir, $newdir, $filesort, $wdpage, $msg) = @_;

   my $showthumbnail =  param('showthumbnail') || 0;
   my $showhidden    =  param('showhidden')    || 0;
   my $singlepage    =  param('singlepage')    || 0;

   my $quotadellimit = '';
   my $quotausagestr = '';
   my $peroverquota  = '';
   if (
         $quotalimit > 0
         && $quotausage > $quotalimit
         && ($config{delmail_ifquotahit} || $config{delfile_ifquotahit})
      ) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage

      if ($quotausage > $quotalimit) {
         my (@validfolders, $inboxusage, $folderusage);
         getfolders(\@validfolders, \$inboxusage, \$folderusage);
         if ($config{delfile_ifquotahit} && $folderusage < $quotausage * 0.5) {
            $quotadellimit = $config{quota_limit};
            my $webdiskrootdir = $homedir . absolute_vpath('/', $config{webdisk_rootpath});
            cutdirfiles(($quotausage - $quotalimit * 0.9) * 1024, $webdiskrootdir);

            $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
         }
      }
   }

   if ($config{quota_module} ne 'none') {
      my $overthreshold = ($quotalimit > 0 && $quotausage / $quotalimit > $config{quota_threshold} / 100);
      $quotausagestr    = lenstr($quotausage * 1024, 1) if $config{quota_threshold} == 0 || $overthreshold;
      $peroverquota     = int($quotausage * 1000 / $quotalimit) / 10 if $overthreshold;
   }

   my $currentdir = '';
   my @list       = ();

   if ($wdkeyword eq '') {
      # user has not supplied a wdkeyword
      foreach my $dir ($newdir, $olddir, '/') {
         next unless defined $dir && $dir;

         verify_vpath($webdiskrootdir, $dir);

         opendir(D, "$webdiskrootdir/$dir") or
            openwebmailerror(gettext('Cannot open directory:') . ' ' . f2u($dir) . " ($!)");

         @list = readdir(D);

         closedir(D) or
            openwebmailerror(gettext('Cannot close directory:') . ' ' . f2u($dir) . " ($!)");

         $currentdir = $dir;
         last;
      }
   } else {
      # the user is supplying a webdisk keyword to search
      # populate the @list with the search results
      filelist_of_search($wdsearchtype, $wdkeyword, $olddir, dotpath('webdisk.cache'), \@list);

      # olddir = newdir if wdkeyword is supplied for searching
      $currentdir = $olddir;
   }

   my %fsize     = ();
   my %fdate     = ();
   my %fowner    = ();
   my %fmode     = ();
   my %fperm     = ();
   my %ftype     = ();
   my %flink     = ();
   my $dcount    = 0;
   my $fcount    = 0;
   my $sizecount = 0;

   foreach my $filename (@list) {
      next if $filename eq '.' || $filename eq '..';

      my $vpath = absolute_vpath($currentdir, $filename);

      next if !$config{webdisk_lsmailfolder} && is_under_dotdir_or_mail_folder("$webdiskrootdir/$vpath");

      my $fname = $vpath;
      $fname =~ s|.*/||;

      next if (!$config{webdisk_lshidden} || !$showhidden) && $fname =~ m/^(?:\.|:2e)/;

      if (-l "$webdiskrootdir/$vpath") {
         # symbolic link, aka:shortcut
         next unless $config{webdisk_lssymlink};

         my $realpath = readlink("$webdiskrootdir/$vpath");
         $realpath    = "$webdiskrootdir/$vpath/../$realpath" if $realpath !~ m!^/!;
         my $vpath2   = fullpath2vpath($realpath, $webdiskrootdir);

         if (defined $vpath2 && $vpath2 ne '') {
            $flink{$filename} = " -> $vpath2";
         } else {
            next unless $config{webdisk_allow_symlinkout};

            if ($config{webdisk_symlinkout_display} eq 'path') {
               $flink{$filename} = " -> " . gettext('system') . "::$realpath";
            } elsif ($config{webdisk_symlinkout_display} eq '@') {
               $flink{$filename} = '@';
            } else {
               $flink{$filename} = '';
            }
         }
      }

      my (
            $st_dev, $st_ino, $st_mode, $st_nlink, $st_uid, $st_gid, $st_rdev,
            $st_size, $st_atime, $st_mtime, $st_ctime, $st_blksize, $st_blocks
         ) = (-l "$webdiskrootdir/$vpath" && !-e readlink("$webdiskrootdir/$vpath")) ? 
              lstat("$webdiskrootdir/$vpath") : stat("$webdiskrootdir/$vpath");

      if (($st_mode & 0170000) == 0040000) {
         $ftype{$filename} = 'd';
         $dcount++;
      } elsif (($st_mode & 0170000) == 0100000) {
         $ftype{$filename} = 'f';
         $fcount++;
         $sizecount += $st_size;
      } else {
         # unix specific filetype: fifo, socket, block dev, char dev..
         next unless $config{webdisk_lsunixspec};
         $ftype{$fname} = 'u';
      }

      my $r = -r "$webdiskrootdir/$vpath" ? 'r' : '-';
      my $w = -w "$webdiskrootdir/$vpath" ? 'w' : '-';
      my $x = -x "$webdiskrootdir/$vpath" ? 'x' : '-';

      $fperm{$filename}  = "$r$w$x";
      $fsize{$filename}  = $st_size;
      $fdate{$filename}  = $st_mtime;
      $fowner{$filename} = (getpwuid($st_uid) ? getpwuid($st_uid) : $st_uid) . ':' . (getgrgid($st_gid) ? getgrgid($st_gid) : $st_gid);
      $fmode{$filename}  = sprintf("%04o", $st_mode & 07777);
   }

   my @sortedlist = sortfiles($filesort, \%ftype, \%fsize, \%fdate, \%fperm);

   my $totalpages = int(scalar @sortedlist / ($prefs{webdisk_dirnumitems} || 10) + 0.999999);
   $totalpages    = 1 if $totalpages < 1 || $singlepage;

   if ($currentdir ne $olddir) {
      # reset page number if change to new dir
      $wdpage = 1;
   } else {
      $wdpage = 1 if $wdpage < 1;
      $wdpage = $totalpages if $wdpage > $totalpages;
   }

   my @pathloop    = mkpathloop($currentdir, $wdpage, $filesort, 1);
   my @headersloop = mkheadersloop($currentdir, $wdpage, $filesort, $wdkeyword, 1);

   my $canwrite  = !$config{webdisk_readonly} && (!$quotalimit || $quotausage < $quotalimit);
   my $filesloop = [];

   if (scalar @sortedlist > 0) {
      my $os      = $^O || 'generic';
      my $i_first = 0;
      my $i_last  = $#sortedlist;

      if (!$singlepage) {
         $i_first  = ($wdpage - 1) * $prefs{webdisk_dirnumitems};
         $i_last   = $i_first + $prefs{webdisk_dirnumitems} - 1;
         $i_last   = $#sortedlist if $i_last > $#sortedlist;
      }

      foreach my $i ($i_first .. $i_last) {
         my $filename    = $sortedlist[$i];
         my $is_txt      = $ftype{$filename} eq 'd'
                           ? 0
                           : (-T "$webdiskrootdir/$currentdir/$filename" || $filename =~ m/\.(txt|html?)$/i);
         my $ficon       = $prefs{iconset} =~ m/^Text$/
                           ? ''
                           : findicon($filename, $ftype{$filename}, $is_txt, $os);
         my $dname       = '';
         my $fname       = '';
         my $dnamestr    = '';
         my $mkpspdf     = '';
         my $mkps        = '';
         my $preview     = '';
         my $editfile    = '';
         my $listarchive = '';
         my $wordpreview = '';
         my $candeflate  = '';
         my $thumbnail   = '';
         my $archive     = '';

         if ($ftype{$filename} ne 'd') {
            if ($filename =~ m|^(.*/)([^/]*)$|) {
               $fname = $2;
               $dname = $1;
               $dnamestr = f2u($dname);
            } else {
               $fname = $filename;
               $dname = '';
            }

            $preview = 1 if $is_txt && $filename =~ m/\.html?$/i;

            if ($filename =~ m/\.(?:zip|rar|arj|ace|lzh|t[bg]z|tar\.g?z|tar\.bz2?|tne?f)$/i) {
               $archive = 1;
               $listarchive = $config{webdisk_allow_listarchive};
            } elsif ($filename =~ m/\.(?:doc|dot)$/i) {
               $wordpreview = 1;
            } elsif ($showthumbnail && $filename =~ m/\.(?:jpe?g|gif|png|bmp|tif)$/i) {
               if ($fsize{$filename} < 2048) {
                  # show image itself if size < 2k
                  $thumbnail = $filename;
               } else {
                  $thumbnail = path2thumbnail($filename);
                  $thumbnail = '' unless -f "$webdiskrootdir/$currentdir/$thumbnail";
               }
            }

            if ($canwrite) {
               if ($filename =~ m/\.pdf$/i) {
                  $mkpspdf = 'mkps';
                  $mkps    = 1;
               } elsif ($filename =~ m/\.e?ps$/i) {
                  $mkpspdf = 'mkpdf';
               } elsif ($is_txt) {
                  $editfile = 1;
               } elsif (
                          $archive
                          && (
                                ($filename =~ m/\.(?:t[bg]z|tar\.g?z)$/i && $config{webdisk_allow_untar} && $config{webdisk_allow_ungzip})
                                || ($filename =~ m/\.(?:tar\.bz2?)$/i && $config{webdisk_allow_untar} && $config{webdisk_allow_unbzip2})
                                || ($filename =~ m/\.zip$/i && $config{webdisk_allow_unzip})
                                || ($filename =~ m/\.rar$/i && $config{webdisk_allow_unrar})
                                || ($filename =~ m/\.arj$/i && $config{webdisk_allow_unarj})
                                || ($filename =~ m/\.ace$/i && $config{webdisk_allow_unace})
                                || ($filename =~ m/\.tar$/i && $config{webdisk_allow_untar})
                                || ($filename =~ m/\.lzh$/i && $config{webdisk_allow_unlzh})
                             )
                          || ($filename =~ /\.(?:bz2?)$/i && $config{webdisk_allow_unbzip2})
                          || ($filename =~ /\.(?:g?z?)$/i && $config{webdisk_allow_ungzip})
                       ) {
                  $candeflate = 1;
               }
            }
         }

         my $datestr = defined $fdate{$filename}
                       ? ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial($fdate{$filename}),
                            $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone})
                       : '';

         my ($permstr) = $fperm{$filename} =~ m/^(...)$/;

         push (@{$filesloop}, {
                                 # standard params
                                 sessionid     => $thissession,
                                 folder        => $folder,
                                 message_id    => $messageid,
                                 sort          => $sort,
                                 page          => $page,
                                 longpage      => $longpage,
                                 url_cgi       => $config{ow_cgiurl},
                                 url_html      => $config{ow_htmlurl},
                                 use_texticon  => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                 iconset       => $prefs{iconset},
                                 (map { $_, $icons->{$_} } keys %{$icons}),

                                 # filesloop
                                 wdpage        => $wdpage,
                                 uselightbar   => $prefs{uselightbar},
                                 odd           => $i % 2,
                                 currentdir    => $currentdir,
                                 filesort      => $filesort,
                                 showthumbnail => $showthumbnail,
                                 showhidden    => $showhidden,
                                 singlepage    => $singlepage,
                                 filenumber    => $i,
                                 isdir         => $ftype{$filename} eq 'd',
                                 filename      => $filename,
                                 fname         => $fname,
                                 fnamestr      => f2u($fname),
                                 dname         => $dname,
                                 dnamestr      => $dnamestr,
                                 ownerstr      => (split(/:/, $fowner{$filename}))[0],
                                 groupstr      => (split(/:/, $fowner{$filename}))[1],
                                 accesskeynr   => ($i + 1) % 10,
                                 ficon         => $ficon,
                                 filenamestr   => f2u($filename),
                                 flinkstr      => defined $flink{$filename} ? f2u($flink{$filename}) : '',
                                 withconfirm   => $prefs{webdisk_confirmcompress} ? 1 : 0,
                                 mkpspdf       => $mkpspdf,
                                 mkps          => $mkps,
                                 preview       => $preview,
                                 editfile      => $editfile,
                                 listarchive   => $listarchive,
                                 wordpreview   => $wordpreview,
                                 candeflate    => $candeflate,
                                 thumbnail     => $thumbnail,
                                 archive       => $archive,
                                 fmode         => $fmode{$filename},
                                 fperm         => $permstr,
                                 datestr       => $datestr,
                                 fsizestr      => lenstr($fsize{$filename}, 1),
                                 fsize         => sprintf(ngettext('%d Byte', '%d Bytes', $fsize{$filename}), $fsize{$filename}),
                              }
              );
      }
   }

   openwebmailerror(gettext('Quota limit exceeded. Please delete some messages or webdisk files to free disk space.'))
      if $quotalimit > 0 && $quotausage >= $quotalimit;

   # release mem if possible
   undef(%fsize);
   undef(%fdate);
   undef(%fperm);
   undef(%ftype);
   undef(%flink);

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_showdir.tmpl"),
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
                      message_id                 => $messageid,
                      sort                       => $sort,
                      page                       => $page,
                      longpage                   => $longpage,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # webdisk_showdir.tmpl
                      wdpage                     => $wdpage,
                      wdkeyword                  => $wdkeyword,
                      wdsearchtype               => $wdsearchtype,
                      # caller_main                => $prefs_caller eq 'main' ? 1 : 0,
                      # caller_addrlistview        => $prefs_caller eq 'addrlistview' ? 1 : 0,
                      # caller_calendar            => $webdisk_caller eq 'cal' ? 1 : 0,
                      # calendardefaultview        => $prefs{calendar_defaultview},
                      # caller_read                => $webdisk_caller eq 'read' ? 1 : 0,
                      caller_main                => defined $messageid && $messageid ? 0 : 1,
                      caller_read                => defined $messageid && $messageid ? 1 : 0,
                      is_callerfolderdefault     => is_defaultfolder($folder) ? 1 : 0,
                      "callerfoldername_$folder" => 1,
                      callerfoldername           => f2u($folder),
                      currentdir                 => $currentdir,
                      isroot                     => $currentdir eq '/',
                      parentdir                  => absolute_vpath($currentdir, ".."),
                      filesort                   => $filesort,
                      gotodir                    => $gotodir,
                      prevpage                   => ($wdpage > 1) ? $wdpage - 1 : '',
                      nextpage                   => ($wdpage < $totalpages) ? $wdpage + 1 : '',
                      is_right_to_left           => $ow::lang::RTL{$prefs{locale}},
                      quotausage                 => $quotausagestr,
                      peroverquota               => $peroverquota,
                      allowthumbnails            => $config{webdisk_allow_thumbnail},
                      showthumbnail              => $showthumbnail,
                      enablehidden               => $config{webdisk_lshidden},
                      showhidden                 => $showhidden,
                      singlepage                 => $singlepage,
                      enable_webmail             => $config{enable_webmail},
                      enable_addressbook         => $config{enable_addressbook},
                      enable_calendar            => $config{enable_calendar},
                      calendar_defaultview       => $prefs{calendar_defaultview},
                      enable_preference          => $config{enable_preference},
                      enable_sshterm             => $config{enable_sshterm},
                      use_ssh1                   => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar" ? 1 : 0,
                      use_ssh2                   => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar" ? 1 : 0,
                      pathloop                   => \@pathloop,
                      headersloop                => \@headersloop,
                      filesloop                  => $filesloop,
                      dcount                     => sprintf(ngettext('%d Directory', '%d Directories', $dcount), $dcount),
                      fcount                     => sprintf(ngettext('%d File', '%d Files', $fcount), $fcount),
                      totalsize                  => lenstr($sizecount, 1),
                      totalpages                 => $totalpages,
                      pageselectloop             => [
                                                       map { {
                                                                option   => $_,
                                                                label    => $_,
                                                                selected => $_ eq $wdpage ? 1 : 0,
                                                           } } grep {
                                                                       $_ == 1
                                                                       || $_ == $totalpages
                                                                       || abs($_ - $wdpage) < 10
                                                                       || abs($_ - $wdpage) < 100 && $_ % 10 == 0
                                                                       || abs($_ - $wdpage) < 1000 && $_ % 100 == 0
                                                                       || $_ % 1000 == 0
                                                                    } (1..$totalpages)
                                                    ],
                      canwrite                   => $canwrite,
                      is_readonly                => $config{webdisk_readonly},
                      underquota                 => (!$quotalimit || $quotausage < $quotalimit),
                      cansymlink                 => ($config{webdisk_allow_symlinkcreate} && $config{webdisk_lssymlink}),
                      canchmod                   => $config{webdisk_allow_chmod},
                      cangzip                    => $config{webdisk_allow_gzip},
                      canzip                     => $config{webdisk_allow_zip},
                      cantargz                   => ($config{webdisk_allow_tar} && $config{webdisk_allow_gzip}),
                      cantar                     => $config{webdisk_allow_tar},
                      canthumb                   => $config{webdisk_allow_thumbnail},
                      popup_quotadellimit        => $quotadellimit,
                      charset                    => $prefs{charset},
                      msg                        => $msg,

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   my $cookie = cookie( -name  => "ow-currentdir-$domain-$user",
                        -value => $currentdir,
                        -path  => '/');
   httpprint([-cookie   => $cookie,
              -Refresh  => ($prefs{refreshinterval} * 60) .
                           ";URL=openwebmail-webdisk.pl?action=showdir&session_noupdate=1&" .
                           join ('&', (
                                         "sessionid="     . $thissession,
                                         "folder="        . ow::tool::escapeURL($folder),
                                         "message_id="    . ow::tool::escapeURL($messageid),
                                         "sort="          . $sort,
                                         "page="          . $page,
                                         "longpage="      . $longpage,
                                         "searchtype="    . $searchtype,
                                         "keyword="       . ow::tool::escapeURL($keyword),
                                         "wdpage="        . $wdpage,
                                         "wdsearchtype="  . $wdsearchtype,
                                         "wdkeyword="     . ow::tool::escapeURL($wdkeyword),
                                         "currentdir="    . ow::tool::escapeURL($currentdir),
                                         "gotodir="       . ow::tool::escapeURL($currentdir),
                                         "showthumbnail=" . $showthumbnail,
                                         "showhidden="    . $showhidden,
                                         "singlepage="    . $singlepage,
                                         "filesort="      . $filesort
                                      )
                                )
             ], [$template->output]);

   return;
}

sub sortfiles {
   my ($filesort, $r_ftype, $r_fsize, $r_fdate, $r_fperm) = @_;

   return $filesort eq 'name_rev' ? sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $b cmp $a } keys %{$r_ftype}                         :
          $filesort eq 'size'     ? sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $r_fsize->{$a} <=> $r_fsize->{$b} } keys %{$r_ftype} :
          $filesort eq 'size_rev' ? sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $r_fsize->{$b} <=> $r_fsize->{$a} } keys %{$r_ftype} :
          $filesort eq 'time'     ? sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $r_fdate->{$a} <=> $r_fdate->{$b} } keys %{$r_ftype} :
          $filesort eq 'time_rev' ? sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $r_fdate->{$b} <=> $r_fdate->{$a} } keys %{$r_ftype} :
          $filesort eq 'perm'     ? sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $r_fperm->{$a} cmp $r_fperm->{$b} } keys %{$r_ftype} :
          $filesort eq 'perm_rev' ? sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $r_fperm->{$b} cmp $r_fperm->{$a} } keys %{$r_ftype} :
          sort { $r_ftype->{$a} cmp $r_ftype->{$b} || $a cmp $b } keys %{$r_ftype}; # by name
}

sub mkpathloop {
   my ($currentdir, $wdpage, $filesort, $caller_showdir) = @_;

   my $showthumbnail =  param('showthumbnail') || 0;
   my $showhidden    =  param('showhidden')    || 0;
   my $singlepage    =  param('singlepage')    || 0;

   my @pathloop = ();
   my $p        = '';

   foreach ('', grep(!m/^$/, split(/\//, $currentdir))) {
      $p .= "$_/";
      my $tmp = {
                   # standard params
                   sessionid    => $thissession,
                   folder       => $folder,
                   message_id   => $messageid,
                   sort         => $sort,
                   page         => $page,
                   longpage     => $longpage,
                   url_cgi      => $config{ow_cgiurl},
                   url_html     => $config{ow_htmlurl},
                   use_texticon => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                   iconset      => $prefs{iconset},
                   (map { $_, $icons->{$_} } keys %{$icons}),

                   # pathloop
                   wdpage       => $wdpage,
                   dir          => $p,
                   dirstr       => f2u("$_/"),
                   currentdir   => $currentdir,
                   filesort     => $filesort,
                   showhidden   => $showhidden,
                   singlepage   => $singlepage,
                };

      if ($caller_showdir) {
         $tmp->{showthumbnail} = $showthumbnail;
      } else {
         $tmp->{action} = $action;

         if ($action eq 'send_saveatt') {
            $tmp->{$action}   = 1;
            $tmp->{attname} = param('attname')  || '';
            $tmp->{attfile} = param('attfile')  || '';
         } elsif ($action eq 'read_saveatt') {
            $tmp->{$action}           = 1;
            $tmp->{attachment_nodeid} = param('attachment_nodeid');
            $tmp->{attname}           = param('attname')  || '';
            $tmp->{convfrom}          = param('convfrom') || '';
         }
      }

      push (@pathloop, $tmp);
   }

   return @pathloop;
}

sub mkheadersloop {
   my ($currentdir, $wdpage, $filesort, $wdkeyword, $caller_showdir) = @_;

   my $showthumbnail =  param('showthumbnail') || 0;
   my $showhidden    =  param('showhidden')    || 0;
   my $singlepage    =  param('singlepage')    || 0;

   my @headers = qw(name size time);
   push(@headers, 'perm') if $caller_showdir;

   my @headersloop = ();

   foreach (@headers) {
      my $tmp = {
                   # standard params
                   sessionid     => $thissession,
                   folder        => $folder,
                   message_id    => $messageid,
                   sort          => $sort,
                   page          => $page,
                   longpage      => $longpage,
                   url_cgi       => $config{ow_cgiurl},
                   url_html      => $config{ow_htmlurl},
                   use_texticon  => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                   iconset       => $prefs{iconset},
                   (map { $_, $icons->{$_} } keys %{$icons}),

                   # headersloop
                   wdpage        => $wdpage,
                   wdkeyword     => $wdkeyword,
                   wdsearchtype  => $wdsearchtype,
                   $_ . 'header' => 1,
                   is_activesort => $filesort =~ m/^\Q$_\E/ ? 1 : 0,
                   is_reverse    => ($filesort =~ m/^\Q$_\E/ && $filesort eq ($_ . '_rev')) ? 1 : 0,
                   currentdir    => $currentdir,
                   singlepage    => $singlepage,
                };

      if ($caller_showdir) {
         $tmp->{showthumbnail} = $showthumbnail;
      } else {
         $tmp->{action} = $action;

         if ($action eq 'send_saveatt') {
            $tmp->{$action}   = 1;
            $tmp->{attname} = param('attname')  || '';
            $tmp->{attfile} = param('attfile')  || '';
         } elsif ($action eq 'read_saveatt') {
            $tmp->{$action}           = 1;
            $tmp->{attachment_nodeid} = param('attachment_nodeid');
            $tmp->{attname}           = param('attname')  || '';
            $tmp->{convfrom}          = param('convfrom') || '';
         }
      }

      push (@headersloop, $tmp);
   }

   return @headersloop;
}

sub findicon {
   my ($fname, $ftype, $is_txt, $os) = @_;

   return 'dir.gif' if $ftype eq 'd';
   return 'sys.gif' if $ftype eq 'u';

   local $_ = lc($fname);

   return 'cert.gif' if m/\.(ce?rt|cer|ssl)$/;
   return 'help.gif' if m/\.(hlp|man|cat|info)$/;
   return 'pdf.gif'  if m/\.(fdf|pdf)$/;
   return 'html.gif' if m/\.(shtml|html?|xml|sgml|wmls?)$/;
   return 'txt.gif'  if m/\.te?xt$/;

   if ($is_txt) {
      return 'css.gif'  if m/\.(css|jsp?|aspx?|php[34]?|xslt?|vb[se]|ws[cf]|wrl|vrml)$/;
      return 'ini.gif'  if m/\.(ini|inf|conf|cf|config)$/ || /^\..*rc$/;
      return 'mail.gif' if m/\.(msg|elm)$/;
      return 'ps.gif'   if m/\.(ps|eps)$/;
      return 'txt.gif';
   } else {
      return 'audio.gif'  if m/\.(mid[is]?|mod|au|cda|aif[fc]?|voc|wav|snd)$/;
      return 'chm.gif'    if m/\.chm$/;
      return 'doc.gif'    if m/\.(do[ct]|rtf|wri)$/;
      return 'exe.gif'    if m/\.(exe|com|dll)$/;
      return 'font.gif'   if m/\.fon$/;
      return 'graph.gif'  if m/\.(jpe?g|gif|png|bmp|p[nbgp]m|pc[xt]|pi[cx]|psp|dcx|kdc|tiff?|ico|x[bp]m|img)$/;
      return 'mdb.gif'    if m/\.(md[bentz]|ma[fmq])$/;
      return 'mp3.gif'    if m/\.(m3u|mp[32]|mpga)$/;
      return 'ppt.gif'    if m/\.(pp[at]|pot)$/;
      return 'rm.gif'     if m/\.(r[fampv]|ram)$/;
      return 'stream.gif' if m/\.(wmv|wvx|as[fx])$/;
      return 'ttf.gif'    if m/\.tt[cf]$/;
      return 'video.gif'  if m/\.(avi|mov|dat|mpe?g)$/;
      return 'xls.gif'    if m/\.xl[abcdmst]$/;
      return 'zip.gif'    if m/\.(zip|tar|t?g?z|tbz|bz2?|rar|lzh|arj|ace|bhx|hqx|jar|tne?f)$/;

      return 'file' . lc($1) . '.gif' if $os =~ m/(bsd|linux|solaris)/i;
      return 'file.gif';
   }
}

sub createdir {
   my ($currentdir, $destname) = @_;

   $destname = u2f($destname);

   my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr = f2u($vpath);

   verify_vpath($webdiskrootdir, $vpath);

   if (-e "$webdiskrootdir/$vpath") {
      openwebmailerror(gettext('Directory already exists:') . " $vpathstr") if -d "$webdiskrootdir/$vpath";
      openwebmailerror(gettext('File already exists:') . " $vpathstr");
   } else {
      if (mkdir("$webdiskrootdir/$vpath", 0755)) {
         writelog("webdisk mkdir - $vpath");
         writehistory("webdisk mkdir - $vpath");
         return gettext('Directory created:') . " $vpathstr\n";
      } else {
         openwebmailerror(gettext('Cannot create directory:') . " $vpathstr ($!)");
      }
   }
}

sub createfile {
   my ($currentdir, $destname) = @_;

   $destname = u2f($destname);

   my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr = f2u($vpath);
   verify_vpath($webdiskrootdir, $vpath);

   if (-e "$webdiskrootdir/$vpath") {
      openwebmailerror(gettext('Directory already exists:') . " $vpathstr") if -d "$webdiskrootdir/$vpath";
      openwebmailerror(gettext('File already exists:') . " $vpathstr");
   } else {
      sysopen(F, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");

      print F '';

      close(F) or
         openwebmailerror(gettext('Cannot close file:') . " $vpathstr ($!)");

      writelog("webdisk createfile - $vpath");
      writehistory("webdisk createfile - $vpath");
      return gettext('File created:') . " $vpathstr\n";
   }
}

sub deletedirfiles {
   my ($currentdir, @selitems) = @_;

   my @filelist = ();

   # build the list of items to delete
   foreach my $item (@selitems) {
      my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $item));
      my $vpathstr = f2u($vpath);

      verify_vpath($webdiskrootdir, $vpath);

      openwebmailerror(gettext('File does not exist:') . " $vpathstr")
         if !-l "$webdiskrootdir/$vpath" && !-e "$webdiskrootdir/$vpath";

      if (-f $item && $vpath=~/\.(?:jpe?g|gif|png|bmp|tif)$/i) {
         # also delete the thumbnail if item is an image file
         my $thumbnail = path2thumbnail("$webdiskrootdir/$vpath");
         push(@filelist, $thumbnail) if -f $thumbnail;
      }

      push(@filelist, "$webdiskrootdir/$vpath");
   }

   return gettext('No files were deleted.') if scalar @filelist < 1;

   my @cmd   = ();
   my $rmbin = ow::tool::findbin('rm') || '';

   openwebmailerror(gettext('Program does not exist:') . ' (rm)') if $rmbin eq '';

   @cmd = ($rmbin, '-Rfv');

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   my $msg = webdisk_execute(gettext('Delete'), @cmd, @filelist);

   if ($msg =~ m/rm:/) {
      # -v cmds not supported on solaris
      $cmd[1] =~ s/v//;
      $msg = webdisk_execute(gettext('Delete'), @cmd, @filelist);
   }

   # update quotausage
   $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]
      if $quotalimit > 0 && $quotausage > $quotalimit;

   return $msg;
}

sub chmoddirfiles {
   my ($perm, $currentdir, @selitems) = @_;

   $perm =~ s/\s//g;

   if ($perm =~ m/[^0-7]/) {
      openwebmailerror(gettext('Illegal value for chmod operation:') . " ($perm)");
   } elsif ($perm !~ m/^0/) {
      $perm = '0' . $perm; # should leading with 0
   } elsif ($perm !~ m/\d{4}/) {
      openwebmailerror(gettext('Illegal value for chmod operation:') . " ($perm)");
   }

   my @filelist = ();
   my @vfilelist = (); # vpaths without the webdiskrootdir

   foreach my $item (@selitems) {
      my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $item));
      my $vpathstr = f2u($vpath);

      verify_vpath($webdiskrootdir, $vpath);

      openwebmailerror(gettext('File does not exist:') . " $vpathstr")
         if !-l "$webdiskrootdir/$vpath" && !-e "$webdiskrootdir/$vpath";

      if (-f "$webdiskrootdir/$vpath" && $vpath =~ /\.(?:jpe?g|gif|png|bmp|tif)$/i) {
         # chmod the thumbnail too if this is an image file
         my $thumbnail = path2thumbnail("$webdiskrootdir/$vpath");
         push(@filelist, $thumbnail) if -f $thumbnail;
      }

      push(@filelist, "$webdiskrootdir/$vpath");
      push(@vfilelist, $vpathstr);
   }

   return gettext('No files or directories could be prepared for chmod.') if scalar @filelist < 1;

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   my $notchanged = scalar @filelist - chmod(oct(ow::tool::untaint($perm)), @filelist);

   if ($notchanged != 0) {
      return gettext('Chmod') . ' :: ' . gettext('Error') . "\n" .
             sprintf(ngettext('%d item could not be changed by chmod', '%d items could not be changed by chmod', $notchanged), $notchanged);
   }

   return gettext('Chmod') . ' :: ' . gettext('Success') . ' :: ( ' . join(' ', @vfilelist) . ' )';
}

sub copymovesymlink_dirfiles {
   # copy, move, or symbolic link the given directory or file to the destination
   my ($op, $currentdir, $destname, @selitems) = @_;

   $destname = u2f($destname);

   my $destvpath    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $destvpathstr = f2u($destvpath);

   verify_vpath($webdiskrootdir, $destvpath);

   if (scalar @selitems > 1) {
      # copying or moving more than one item. The target must be a directory.
      openwebmailerror(gettext('The target must be a directory when copying or moving multiple items. The target does not exist or is not a directory:') . " $destvpathstr")
         unless -e "$webdiskrootdir/$destvpath" && -d "$webdiskrootdir/$destvpath";
   }

   my @filelist = ();

   foreach my $item (@selitems) {
      my $srcvpath    = ow::tool::untaint(absolute_vpath($currentdir, $item));
      my $srcvpathstr = f2u($srcvpath);

      verify_vpath($webdiskrootdir, $srcvpath);

      openwebmailerror(gettext('File does not exist:') . " $srcvpathstr") unless -e "$webdiskrootdir/$srcvpath";

      return gettext('Operation cancelled. The source and target names are the same:') . "\n$srcvpath == $destvpath"
         if $srcvpath eq $destvpath;

      my $p = "$webdiskrootdir/$srcvpath";
      $p =~ s#/+#/#g; # eliminate multiple slashes

      push(@filelist, $p);
   }

   return gettext('No files were copied, moved or linked.') if scalar @filelist < 1;

   my @cmd = ();

   if ($op eq 'copy') {
      my $cpbin = ow::tool::findbin('cp') || '';
      openwebmailerror(gettext('Program does not exist:') . ' (cp)') if $cpbin eq '';

      @cmd = ($cpbin, '-pRfv');
   } elsif ($op eq 'move') {
      my $mvbin = ow::tool::findbin('mv') || '';
      openwebmailerror(gettext('Program does not exist:') . ' (mv)') if $mvbin eq '';

      @cmd = ($mvbin, '-fv');
   } elsif ($op eq 'symlink') {
      my $lnbin = ow::tool::findbin('ln') || '';
      openwebmailerror(gettext('Program does not exist:') . ' (ln)') if $lnbin eq '';

      @cmd = ($lnbin, '-sv');
   } else {
      return gettext('Illegal operation:') . " ($op)";
   }

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   my $optext = $op eq 'copy'    ? gettext('Copy') :
                $op eq 'move'    ? gettext('Move') :
                gettext('Symbolic Link');

   my $msg = webdisk_execute($optext, @cmd, @filelist, "$webdiskrootdir/$destvpath");
   if ($msg =~ m/cp:/ || $msg =~ m/mv:/ || $msg =~ m/ln:/) {
      # -v cmds not supported on solaris
      $cmd[1] =~ s/v//;
      $msg = webdisk_execute($optext, @cmd, @filelist, "$webdiskrootdir/$destvpath");
   }

   return $msg;
}

sub editfile {
   my ($currentdir, $selitem) = @_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);
   my $content  = '';

   if (-d "$webdiskrootdir/$vpath") {
      autoclosewindow(gettext('Edit Failed'), gettext('Cannot edit a directory.'));
   } elsif (-f "$webdiskrootdir/$vpath") {
      verify_vpath($webdiskrootdir, $vpath);

      ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_SH|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . " $vpathstr");

      if (sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY)) {
         local $/;
         undef $/;
         $content = <F>;
         close(F);
      } else {
         ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN);
         openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");
      }

      ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . " $vpathstr");

      writelog("webdisk editfile - $vpath");
      writehistory("webdisk editfile - $vpath");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_editfile.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );
   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # standard params
                      sessionid           => $thissession,
                      url_cgi             => $config{ow_cgiurl},

                      # webdisk_editfile.tmpl
                      currentdir          => $currentdir,
                      vpathstr            => $vpathstr,
                      is_html             => $vpath =~ m/\.html?$/ ? 1 : 0,
                      rows                => $prefs{webdisk_fileeditrows},
                      columns             => $prefs{webdisk_fileeditcolumns},
                      filecontent         => f2u($content),

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub savefile {
   my ($currentdir, $destname, $content) = @_;

   ($destname, $content) = iconv($prefs{charset}, $prefs{fscharset}, $destname, $content);

   my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr = f2u($vpath);

   verify_vpath($webdiskrootdir, $vpath);

   $content =~ s#</ESCAPE_TEXTAREA>#</textarea>#gi;
   $content =~ s/\r\n/\n/g;
   $content =~ s/\r/\n/g;

   sysopen(F, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT) or
      autoclosewindow(gettext('Save File'), gettext('Cannot open file:') . " $vpathstr ($!)", 60);

   ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_EX) or
      autoclosewindow(gettext('Save File'), gettext('Cannot lock file:') . " $vpathstr", 60);

   print F $content;

   close(F) or
      autoclosewindow(gettext('Save File'), gettext('Cannot close file:') . " $vpathstr ($!)", 60);

   ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN) or
      autoclosewindow(gettext('Save File'), gettext('Cannot unlock file:') . " $vpathstr", 60);

   writelog("webdisk savefile - $vpath");
   writehistory("webdisk savefile - $vpath");

   autoclosewindow(gettext('Saved'), gettext('The file was saved successfully:') . " $vpathstr", 5, 'refresh_dirform');
}

sub compressfiles {
   # pack files with gzip, zip or tgz (tar -zcvf)
   my ($ztype, $currentdir, $destname, @selitems) = @_;

   $destname = u2f($destname);

   my $vpath2    = '';
   my $vpath2str = '';
   my $msg       = '';
   my $err       = '';
   if ($ztype eq 'mkzip' || $ztype eq 'mktgz') {
      $vpath2    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
      $vpath2str = f2u($vpath2);

      verify_vpath($webdiskrootdir, $vpath2);

      if (-e "$webdiskrootdir/$vpath2") {
         openwebmailerror(gettext('Directory already exists:') . " $vpath2str") if -d "$webdiskrootdir/$vpath2";
         openwebmailerror(gettext('File already exists:') . " $vpath2str");
      }
   }

   my %selitem = ();

   foreach my $item (@selitems) {
      my $vpath    = absolute_vpath($currentdir, $item);
      my $vpathstr = f2u($vpath);

      verify_vpath($webdiskrootdir, $vpath);

      # use relative path to currentdir since we will chdir to webdiskrootdir/currentdir before compress
      my $p = fullpath2vpath("$webdiskrootdir/$vpath", "$webdiskrootdir/$currentdir");

      # use absolute path if relative to webdiskrootdir/currentdir is not possible
      $p = "$webdiskrootdir/$vpath" if $p eq '';
      $p = ow::tool::untaint($p);

      if (-d "$webdiskrootdir/$vpath") {
         $selitem{".$p/"} = 1;
      } elsif (-e "$webdiskrootdir/$vpath") {
         $selitem{".$p"} = 1;
      }
   }

   my @filelist = keys %selitem;

   return gettext('No files or directories could be prepared for compressing.') if scalar @filelist < 1;

   my @cmd = ();

   if ($ztype eq 'gzip') {
      my $gzipbin = ow::tool::findbin('gzip') || '';
      openwebmailerror(gettext('Program does not exist:') . ' (gzip)') if $gzipbin eq '';
      @cmd = ($gzipbin, '-rq');
   } elsif ($ztype eq 'mkzip') {
      my $zipbin = ow::tool::findbin('zip') || '';
      openwebmailerror(gettext('Program does not exist:') . ' (zip)') if $zipbin eq '';

      @cmd = ($zipbin, '-ryq', "$webdiskrootdir/$vpath2");
   } elsif ($ztype eq 'mktgz') {
      my $gzipbin = ow::tool::findbin('gzip') || '';
      my $tarbin  = ow::tool::findbin('tar') || '';

      openwebmailerror(gettext('Program does not exist:') . ' (tar)') if $tarbin eq '';

      if ($gzipbin ne '') {
         $ENV{PATH} = $gzipbin;
         $ENV{PATH} =~ s#/gzip##; # for tar
         @cmd = ($tarbin, '-zcpf', "$webdiskrootdir/$vpath2");
      } else {
         @cmd = ($tarbin, '-cpf', "$webdiskrootdir/$vpath2");
      }
   } else {
      openwebmailerror(gettext('Unknown compression type:') . " ($ztype)");
   }

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   my $opstr = $ztype eq 'mkzip' ? gettext('Create ZIP') :
               $ztype eq 'mktgz' ? gettext('Create TGZ') :
               gettext('Create GZ');

   return webdisk_execute($opstr, @cmd, @filelist);
}

sub extractarchive {
   # extract tar.gz, tgz, tar.bz2, tbz, gz, zip, rar, arj, ace, lzh, tnef/tnf archives
   my ($currentdir, $selitem) = @_;

   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   openwebmailerror(gettext('Cannot read file:') . " $vpathstr")
      if (!-f "$webdiskrootdir/$vpath" || !-r "$webdiskrootdir/$vpath");

   verify_vpath($webdiskrootdir, $vpath);

   my @cmd = ();
   if ($vpath =~ m/\.(tar\.g?z||tgz)$/i && $config{webdisk_allow_untar} && $config{webdisk_allow_ungzip}) {
      my $gzipbin = ow::tool::findbin('gzip') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (gzip)') if $gzipbin eq '';

      my $tarbin = ow::tool::findbin('tar') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (tar)') if $tarbin eq '';

      $ENV{PATH} = $gzipbin;
      $ENV{PATH} =~ s#/gzip##; # for tar

      @cmd = ($tarbin, '-zxpf');
   } elsif ($vpath =~ m/\.(tar\.bz2?||tbz)$/i && $config{webdisk_allow_untar} && $config{webdisk_allow_unbzip2}) {
      my $bzip2bin = ow::tool::findbin('bzip2') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (bzip2)') if $bzip2bin eq '';

      my $tarbin = ow::tool::findbin('tar');
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (tar)') if $tarbin eq '';

      $ENV{PATH} = $bzip2bin;
      $ENV{PATH} =~ s#/bzip2##; # for tar

      @cmd = ($tarbin, '-yxpf');
   } elsif ($vpath =~ m/\.tar?$/i && $config{webdisk_allow_untar}) {
      my $tarbin = ow::tool::findbin('tar') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (tar)') if $tarbin eq '';

      @cmd = ($tarbin, '-xpf');
   } elsif ($vpath =~ m/\.g?z$/i && $config{webdisk_allow_ungzip}) {
      my $gzipbin = ow::tool::findbin('gzip') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (gzip)') if $gzipbin eq '';

      @cmd = ($gzipbin, '-dq');
   } elsif ($vpath =~ m/\.bz2?$/i && $config{webdisk_allow_unbzip2}) {
      my $bzip2bin = ow::tool::findbin('bzip2') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (bzip2)') if $bzip2bin eq '';

      @cmd = ($bzip2bin, '-dq');
   } elsif ($vpath =~ m/\.zip$/i && $config{webdisk_allow_unzip}) {
      my $unzipbin = ow::tool::findbin('unzip') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (unzip)') if $unzipbin eq '';

      @cmd = ($unzipbin, '-oq');
   } elsif ($vpath =~ m/\.rar$/i && $config{webdisk_allow_unrar}) {
      my $unrarbin = ow::tool::findbin('unrar') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (unrar)') if $unrarbin eq '';

      @cmd = ($unrarbin, 'x', '-r', '-y', '-o+');
   } elsif ($vpath =~ m/\.arj$/i && $config{webdisk_allow_unarj}) {
      my $unarjbin = ow::tool::findbin('unarj') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (unarj)') if $unarjbin eq '';

      @cmd = ($unarjbin, 'x');
   } elsif ($vpath =~ m/\.ace$/i && $config{webdisk_allow_unace}) {
      my $unacebin = ow::tool::findbin('unace') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (unace)') if $unacebin eq '';

      @cmd = ($unacebin, 'x', '-y');
   } elsif ($vpath =~ m/\.lzh$/i && $config{webdisk_allow_unlzh}) {
      my $lhabin = ow::tool::findbin('lha') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (lha)') if $lhabin eq '';

      @cmd = ($lhabin, '-xfq');
   } elsif ($vpath =~ m/\.tne?f$/i && $config{webdisk_allow_untnef}) {
      my $tnefbin = ow::tool::findbin('tnef') || '';
      autoclosewindow(gettext('Extract Archive'), gettext('Program does not exist:') . ' (tnef)') if $tnefbin eq '';

      @cmd = ($tnefbin, '--overwrite', '-v', '-f');
   } else {
      autoclosewindow(gettext('Extract Archive'), gettext('File format is not supported:') . " ($vpathstr)");
   }

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   return webdisk_execute(gettext('Extract Archive'), @cmd, "$webdiskrootdir/$vpath");
}

sub listarchive {
   my ($currentdir, $selitem) = @_;

   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   openwebmailerror(gettext('Access denied: the operation is not allowed.'))
      unless $config{webdisk_allow_listarchive};

   autoclosewindow(gettext('List Archive'), gettext('File does not exist:') . " ($vpathstr)")
      unless -f "$webdiskrootdir/$vpath";

   verify_vpath($webdiskrootdir, $vpath);

   my @cmd = ();
   if ($vpath =~ m/\.(tar\.g?z|tgz)$/i) {
      my $gzipbin = ow::tool::findbin('gzip') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (gzip)') if $gzipbin eq '';

      my $tarbin = ow::tool::findbin('tar') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (tar)') if $tarbin eq '';

      $ENV{PATH} = $gzipbin;
      $ENV{PATH} =~ s#/gzip##; # for tar

      @cmd = ($tarbin, '-ztvf');
   } elsif ($vpath =~ m/\.(tar\.bz2?|tbz)$/i) {
      my $bzip2bin = ow::tool::findbin('bzip2') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (bzip2)') if $bzip2bin eq '';

      my $tarbin = ow::tool::findbin('tar');
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (tar)') if $tarbin eq '';

      $ENV{PATH} = $bzip2bin;
      $ENV{PATH} =~ s#/bzip2##;	# for tar

      @cmd = ($tarbin, '-ytvf');
   } elsif ($vpath =~ m/\.zip$/i) {
      my $unzipbin = ow::tool::findbin('unzip') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (unzip)') if $unzipbin eq '';

      @cmd = ($unzipbin, '-lq');
   } elsif ($vpath =~ m/\.rar$/i) {
      my $unrarbin = ow::tool::findbin('unrar') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (unrar)') if $unrarbin eq '';

      @cmd = ($unrarbin, 'l');
   } elsif ($vpath =~ m/\.arj$/i) {
      my $unarjbin = ow::tool::findbin('unarj') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (unarj)') if $unarjbin eq '';

      @cmd = ($unarjbin, 'l');
   } elsif ($vpath =~ m/\.ace$/i) {
      my $unacebin = ow::tool::findbin('unace') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (unace)') if $unacebin eq '';

      @cmd = ($unacebin, 'l', '-y');
   } elsif ($vpath =~ m/\.lzh$/i) {
      my $lhabin = ow::tool::findbin('lha') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (lha)') if $lhabin eq '';

      @cmd = ($lhabin, '-l');
   } elsif ($vpath =~ /\.tne?f$/i) {
      my $tnefbin = ow::tool::findbin('tnef') || '';
      autoclosewindow(gettext('List Archive'), gettext('Program does not exist:') . ' (tnef)') if $tnefbin eq '';

      @cmd = ($tnefbin, '-t');
   } else {
      autoclosewindow(gettext('List Archive'), gettext('File format is not supported:') . " ($vpathstr)");
   }

   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute(@cmd, "$webdiskrootdir/$vpath");

   # try to conv realpath in stdout/stderr back to vpath
   foreach ($stdout, $stderr) {
      s!(?:$webdiskrootdir/+|\s$webdiskrootdir/)! /!g if defined;
      s!/+!/!g if defined;
   }

   ($stdout, $stderr) = iconv($prefs{fscharset}, $prefs{charset}, $stdout, $stderr);

   $stdout = '' unless defined $stdout;
   $stderr = '' unless defined $stderr;

   if ($exit || $sig) {
      my $err = gettext('exit status:') . $exit;
      $err .= (', ' . gettext('terminated by signal:') . $sig) if $sig;
      autoclosewindow(gettext('List Archive'), gettext('Program failed:') . " $cmd[0] :: ($err)\n$stdout$stderr");
   } else {
      writelog("webdisk listarchive - $vpath");
      writehistory("webdisk listarchive - $vpath");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_listarchive.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );
   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # webdisk_listarchive.tmpl
                      vpath               => $vpathstr,
                      filecontent         => $stdout,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub wordpreview {
   # msword text preview
   my ($currentdir, $selitem) = @_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   if (!-f "$webdiskrootdir/$vpath") {
      autoclosewindow(gettext('Word Document Preview'), gettext('File does not exist:') . " $vpathstr");
      return;
   }

   verify_vpath($webdiskrootdir, $vpath);

   my @cmd = ();
   if ($vpath =~ m/\.(?:doc|dot)$/i) {
      my $antiwordbin = ow::tool::findbin('antiword') || '';
      autoclosewindow(gettext('Word Document Preview'), gettext('Program does not exist:') . ' (antiword)') if $antiwordbin eq '';
      @cmd = ($antiwordbin, '-m', 'UTF-8.txt');
   } else {
      autoclosewindow(gettext('Word Document Preview'), gettext('File format is not supported:') . " ($vpathstr)");
   }

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute(@cmd, "$webdiskrootdir/$vpath");

   if ($exit || $sig) {
      # try to conv realpath in stdout/stderr back to vpath
      $stderr =~ s!(?:$webdiskrootdir//|\s$webdiskrootdir/)! /!g;
      $stderr =~ s!/+!/!g;
      $stderr =~ s/^\s+.*$//mg;	# remove the antiword syntax description
      $stderr = f2u($stderr);

      my $err = gettext('exit status:') . $exit;
      $err .= (', ' . gettext('terminated by signal:') . $sig) if $sig;
      autoclosewindow(gettext('Word Document Preview'), gettext('Program failed:') . " antiword :: ($err)\n$stderr");
   } else {
      $stdout = (iconv('utf-8', $prefs{charset}, $stdout))[0];
      writelog("webdisk wordpreview - $vpath");
      writehistory("webdisk wordpreview - $vpath");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_wordpreview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );
   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # webdisk_wordpreview.tmpl
                      vpath               => $vpathstr,
                      filecontent         => $stdout,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub makepdfps {
   # requires ps2pdf to create pdf files
   # requires or pdf2ps to create postscript files
   # these are components of the Ghostscript suite (gs)
   my ($mktype, $currentdir, $selitem) = @_;

   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   openwebmailerror(gettext('File does not exist:') . " $vpathstr") unless -f "$webdiskrootdir/$vpath";
   openwebmailerror(gettext('Cannot read file:') . " $vpathstr") unless -r "$webdiskrootdir/$vpath";

   verify_vpath($webdiskrootdir, $vpath);

   my $gsbin = ow::tool::findbin('gs') || '';
   openwebmailerror(gettext('Program does not exist:') . ' (gs)') if $gsbin eq '';

   my @cmd        = ();
   my $outputfile = "$webdiskrootdir/$vpath";

   if ($mktype eq 'mkpdf' && $outputfile =~ s/^(.*)\.e?ps$/$1\.pdf/i) {
      @cmd = (
                $gsbin,
                '-q',
                '-dNOPAUSE',
                '-dBATCH',
                '-dSAFER',
		'-dCompatibilityLevel=1.3',
                '-dPDFSETTINGS=/printer',
		'-sDEVICE=pdfwrite',
                "-sOutputFile=$outputfile",
		'-c',
                '.setpdfwrite',
                '-f'
             );	# -c option must appear immediately before -f

   } elsif ($mktype eq 'mkps' && $outputfile =~ s/^(.*)\.pdf$/$1\.ps/i) {
      @cmd = (
                $gsbin,
                '-q',
                '-dNOPAUSE',
                '-dBATCH',
                '-dSAFER',
		'-sDEVICE=pswrite',
                "-sOutputFile=$outputfile",
		'-c',
                'save',
                'pop',
                '-f'
             );	# -c option must appear immediately before -f

   } else {
      openwebmailerror(gettext('File format is not supported:') . " $vpathstr");
   }

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   return webdisk_execute(($mktype eq 'mkpdf' ? gettext('Make PDF') : gettext('Make Postscript')), @cmd, "$webdiskrootdir/$vpath");
}

sub makethumbnail {
   my ($currentdir, @selitems) = @_;

   my $convertbin = ow::tool::findbin('convert') || '';
   openwebmailerror(gettext('Program does not exist:') . '(convert)') if $convertbin eq '';

   my @cmd = ($convertbin, '+profile', '*', '-interlace', 'NONE', '-geometry', '64x64');

   foreach my $item (@selitems) {
      my $vpath    = absolute_vpath($currentdir, $item);
      my $vpathstr = f2u($vpath);

      verify_vpath($webdiskrootdir, $vpath);

      # use image itself is as thumbnail if size < 2k
      next if $vpath !~ m/\.(jpe?g|gif|png|bmp|tif)$/i || !-f "$webdiskrootdir/$vpath" || -s "$webdiskrootdir/$vpath" < 2048;

      my $thumbnail = ow::tool::untaint(path2thumbnail($vpath));

      my @p = split(/\//, $thumbnail);
      my $thumbnailstr = f2u(pop(@p));

      my $thumbnaildir = join('/', @p);
      if (!-d "$webdiskrootdir/$thumbnaildir") {
         mkdir (ow::tool::untaint("$webdiskrootdir/$thumbnaildir"), 0755) or
            openwebmailerror(gettext('Cannot make directory:') . " $webdiskrootdir/$thumbnaildir ($!)");
      }

      my ($img_atime, $img_mtime) = (stat("$webdiskrootdir/$vpath"))[8,9];

      if (-f "$webdiskrootdir/$thumbnail") {
         my ($thumbnail_atime, $thumbnail_mtime) = (stat("$webdiskrootdir/$thumbnail"))[8,9];
         next if $thumbnail_mtime == $img_mtime;
      }

      $msg .= webdisk_execute(gettext('Make Thumbnail') . " :: $thumbnailstr", @cmd, "$webdiskrootdir/$vpath", "$webdiskrootdir/$thumbnail");

      if (-f "$webdiskrootdir/$thumbnail.0") {
         unlink map { "$webdiskrootdir/$thumbnail.$_" } (1..20);
         rename("$webdiskrootdir/$thumbnail.0", "$webdiskrootdir/$thumbnail");
      }

      utime(ow::tool::untaint($img_atime), ow::tool::untaint($img_mtime), "$webdiskrootdir/$thumbnail")
         if -f "$webdiskrootdir/$thumbnail";
   }

   return $msg;
}

sub path2thumbnail {
   # given a filename, construct what the path to its thumbnail would be
   my $filename = shift;

   my @p = split(/\//, $filename);

   my $tfile = pop(@p);
   $tfile =~ s/\.[^\.]*$/\.jpg/i;

   push(@p, '.thumbnail');

   return join('/', (@p,$tfile));
}

sub downloadfiles {
   # this downloads multiple files through zip or tgz
   # use the downloadfile command for single file downloads
   my ($currentdir, @selitems) = @_;

   my %selitem = ();

   foreach my $item (@selitems) {
      my $vpath    = absolute_vpath($currentdir, $item);
      my $vpathstr = f2u($vpath);

      verify_vpath($webdiskrootdir, $vpath);

      # use relative path to currentdir since we will chdir to webdiskrootdir/currentdir before DL
      my $p = fullpath2vpath("$webdiskrootdir/$vpath", "$webdiskrootdir/$currentdir");

      # use absolute path if relative to webdiskrootdir/currentdir is not possible
      $p = "$webdiskrootdir/$vpath" if $p eq '';
      $p = ow::tool::untaint($p);

      if (-d "$webdiskrootdir/$vpath") {
         $selitem{".$p/"} = 1;
      } elsif (-e "$webdiskrootdir/$vpath") {
         $selitem{".$p"} = 1;
      }
   }

   my @filelist = keys %selitem;

   return gettext('No files or directories could be prepared for download.') if scalar @filelist < 1;

   my $dlname = '';

   if (scalar @filelist == 1) {
      $dlname = safedlname($filelist[0]);
   } else {
      my $localtime = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
      my @t = ow::datetime::seconds2array($localtime);
      $dlname = sprintf("%4d%02d%02d-%02d%02d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1]);
   }

   my @cmd = ();

   my $zipbin = ow::tool::findbin('zip') || '';

   if ($zipbin ne '') {
      @cmd = ($zipbin, '-ryq', '-');
      $dlname .= '.zip';
   } else {
      my $gzipbin = ow::tool::findbin('gzip') || '';
      my $tarbin  = ow::tool::findbin('tar') || '';

      openwemailerror(gettext('Multiple downloads are disabled. Please download single files only.'))
         if $tarbin eq '';

      if ($gzipbin ne '') {
         $ENV{PATH} = $gzipbin;
         $ENV{PATH} =~ s|/gzip||; # for tar
         @cmd = ($tarbin, '-zcpf', '-');
         $dlname .= '.tgz';
      } else {
         @cmd = ($tarbin, '-cpf', '-');
         $dlname .= '.tar';
      }
   }

   chdir("$webdiskrootdir/$currentdir") or
      openwebmailerror(gettext('Cannot change to directory:') . " $currentdir ($!)");

   my $contenttype = ow::tool::ext2contenttype($dlname);

   local $| = 1;

   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;

   if ($ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/) {
      # ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$dlname"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$dlname"\n|;
   }

   print qq|\n|;

   writelog("webdisk download - " . join(' ', @filelist));
   writehistory("webdisk download - " . join(' ', @filelist));

   # set environment variables for cmd
   $ENV{USER} = $ENV{LOGNAME} = $user;
   $ENV{HOME} = $homedir;

   # drop ruid by setting ruid = euid
   $< = $>;

   exec(@cmd, @filelist) or
      print gettext('Error executing command:') . join(' ', @cmd, @filelist);
}

sub viewinline {
   # show the selected item inline in the browser
   # this is similar to previewfile except that the output to the browser is buffered here
   # and the internals of the file are not modified in any way
   # this is not the same as downloadfile where the output is -not- sent
   # inline, which prompts the user to save the file
   # here the user is only prompted in the case that their browser does not support the file inline
   my ($currentdir, $selitem) = @_;

   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   verify_vpath($webdiskrootdir, $vpath);

   sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");

   my $dlname      = safedlname($vpath);
   my $contenttype = ow::tool::ext2contenttype($vpath);
   my $length      = (-s "$webdiskrootdir/$vpath");

   # disposition:inline default to open
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|,
         qq|Content-Disposition: inline; filename="$dlname"\n|;

   if ($length > 512 && is_http_compression_enabled()) {
      my $content = '';

      local $/;
      undef $/;

      $content = <F>; # slurp

      close(F) or
         openwebmailerror(gettext('Cannot close file:') . " $vpathstr ($!)");

      $content = Compress::Zlib::memGzip($content);
      $length  = length($content);

      print qq|Content-Encoding: gzip\n|,
            qq|Vary: Accept-Encoding\n|,
            qq|Content-Length: $length\n\n|, $content;
   } else {
      print qq|Content-Length: $length\n\n|;

      my $buff = '';

      print $buff while read(F, $buff, 32768);

      close(F) or
         openwebmailerror(gettext('Cannot close file:') . " $vpathstr ($!)");
   }

   return undef;
}

sub downloadfile {
   # download a single file
   # downloading directories or multiple files is not handled by this subroutine
   # to display inline use the viewinline subroutine instead
   my ($currentdir, $selitem) = @_;

   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   verify_vpath($webdiskrootdir, $vpath);

   sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");

   my $dlname      = safedlname($vpath);
   my $contenttype = ow::tool::ext2contenttype($vpath);
   my $length      = (-s "$webdiskrootdir/$vpath");

   # do not do disposition:inline for download
   # we want the user to be prompted to save the file, not display inline
   # to display inline use the viewinline subroutine instead
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;

   if ($ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/ ) {
      # ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$dlname"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$dlname"\n|;
   }

   if ($dlname !~ m/\.(?:t?gz|zip|mp4|jpg)$/i && $length > 512 && is_http_compression_enabled()) {
      my $content = '';

      local $/;
      undef $/;

      $content = <F>; # slurp

      close(F) or
         openwebmailerror(gettext('Cannot close file:') . " $vpathstr ($!)");

      $content = Compress::Zlib::memGzip($content);
      $length  = length($content);

      print qq|Content-Encoding: gzip\n|,
            qq|Vary: Accept-Encoding\n|,
            qq|Content-Length: $length\n\n|, $content;
   } else {
      print qq|Content-Length: $length\n\n|;

      my $buff = '';

      print $buff while read(F, $buff, 32768);

      close(F) or
         openwebmailerror(gettext('Cannot close file:') . " $vpathstr ($!)");
   }

   # log downloads other than thumbnail images
   my @p = split(/\//, $vpath);
   if (!defined $p[$#p - 1] || $p[$#p - 1] ne '.thumbnail') {
      writelog("webdisk download - $vpath");
      writehistory("webdisk download - $vpath ");
   }

   return undef;
}

sub previewfile {
   # this is not the same as the downloadfile or viewinline subroutines
   # relative links in html content will be converted so they can be
   # redirect back to openwebmail-webdisk.pl with correct parmteters
   # and output to the browser is unbuffered - not ideal for big files
   my ($currentdir, $selitem, $filecontent) = @_;

   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   verify_vpath($webdiskrootdir, $vpath);

   if ($filecontent eq '') {
      sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");

      # no separator, read whole file at once
      local $/;
      undef $/;
      $filecontent = <F>;

      close(F) or
         openwebmailerror(gettext('Cannot close file:') . " $vpathstr ($!)");
   }

   # remove path from filename
   my $dlname      = safedlname($vpath);
   my $contenttype = ow::tool::ext2contenttype($vpath);

   if ($vpath =~ m/\.(?:html?|js)$/i) {
      # use the dir where this html is as new currentdir
      my @p = path2array($vpath);
      pop @p;

      my $newdir      = '/' . join('/', @p);
      my $preview_url = qq|$config{ow_cgiurl}/openwebmail-webdisk.pl?| .
                        qq|&amp;action=preview| .
                        qq|sessionid=$thissession| .
                        qq|&amp;currentdir=| . ow::tool::escapeURL($newdir) .
                        qq|&amp;selitems=|;

      $filecontent =~ s/\r\n/\n/g;
      $filecontent = linkconv($filecontent, $preview_url);
   }

   print qq|Connection: close\n| .
         qq|Content-Type: $contenttype; name="$dlname"\n| .
         qq|Content-Disposition: inline; filename="$dlname"\n|;

   # calculate length since linkconv may change data length
   my $length = length $filecontent;

   if ($contenttype =~ m/^text/ && $length > 512 && is_http_compression_enabled()) {
      $filecontent = Compress::Zlib::memGzip($filecontent);
      $length      = length $filecontent;
      print qq|Content-Encoding: gzip\n| .
            qq|Vary: Accept-Encoding\n| .
            qq|Content-Length: $length\n\n|;
   } else {
      print qq|Content-Length: $length\n\n|;
   }

   print $filecontent;

   return 1;
}

sub linkconv {
   my ($html, $preview_url) = @_;
   $html =~ s/( url| href| src| stylesrc| background)(="?)([^\<\>\s]+?)("?[>\s+])/_linkconv($1.$2, $3, $4, $preview_url)/igems;
   $html =~ s/(window.open\()([^\<\>\s]+?)(\))/_linkconv2($1, $2, $3, $preview_url)/igems;
   return $html;
}

sub _linkconv {
   my ($prefix, $link, $postfix, $preview_url) = @_;

   return ($prefix . $link . $postfix) if $link =~ m!^(?:mailto:|javascript:|\#)!i;

   $link = ($preview_url . $link) if $link !~ m!^http://!i && $link !~ m!^/!;

   return $prefix . $link . $postfix;
}

sub _linkconv2 {
   my ($prefix, $link, $postfix, $preview_url) = @_;

   return ($prefix . $link . $postfix) if $link =~ m!^'?(?:http://|/)!i;

   $link = qq|'$preview_url'.$link|;

   return $prefix . $link . $postfix;
}

sub uploadfile {
   # $upload is a string from CGI.pm
   my ($currentdir, $upload) = @_;

   my $fname      = '';
   my $wgethandle = '';

   if ($upload =~ m#^(https?|ftp)://#) {
      my $wgetbin = ow::tool::findbin('wget') || '';
      openwebmailerror(gettext('Program does not exist:') . ' (wget)') if $wgetbin eq '';

      my $ret         = '';
      my $errmsg      = '';
      my $contenttype = '';
      ($ret, $errmsg, $contenttype, $wgethandle) = ow::wget::get_handle($wgetbin, $upload);
      openwebmailerror(gettext('Upload failed.') . "\n($errmsg)") if $ret < 0;

      my $ext = ow::tool::contenttype2ext($contenttype);
      $fname  = $upload; # url
      $fname  = ow::tool::unescapeURL($fname); # unescape str in url
      $fname  =~ s/\?.*$//; # clean cgi parm in url
      $fname  =~ s/\/$//;   # clear path in url
      $fname =~ s/^.*\///;  # clear path in url
      $fname .= ".$ext" if $fname !~ m/\.$ext$/ && $ext ne 'bin';
   } else {
      $fname = $upload;

      # Convert :: back to the ' like it should be.
      $fname =~ s/::/'/g;

      # Trim the DOS path info from the filename
      if ($prefs{charset} eq 'big5' || $prefs{charset} eq 'gb2312') {
         $fname = ow::tool::zh_dospath2fname($fname);
      } else {
         $fname =~ s/^.*\\//;
      }

      $fname =~ s#^.*/##;     # unix path
      $fname =~ s#^.*:##;     # mac path and dos drive
      $fname = u2f($fname);   # prefscharset to fscharset

      $upload = CGI::upload('upload'); # get the CGI.pm upload filehandle in a strict safe way
   }

   my $size = (-s $upload);

writelog("upload size: $size");

   openwebmailerror(gettext('Upload filesize is zero bytes.')) if $size == 0;

   openwebmailerror(gettext('Quota limit exceeded. Please delete some messages or webdisk files to free disk space.'))
      unless is_quota_available($size / 1024);

   openwebmailerror(sprintf(ngettext('The upload exceeds the configured %d KB limit.', 'The upload exceeds the configured %d KB limit.', $config{webdisk_uploadlimit}), $config{webdisk_uploadlimit}))
      if $config{webdisk_uploadlimit} && $size / 1024 > $config{webdisk_uploadlimit};

   my $vpath = ow::tool::untaint(absolute_vpath($currentdir, $fname));
   my $vpathstr = f2u($vpath);

   verify_vpath($webdiskrootdir, $vpath);

   ow::tool::rotatefilename("$webdiskrootdir/$vpath") if -f "$webdiskrootdir/$vpath";

   sysopen(UPLOAD, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");

   binmode UPLOAD;

   my $buff = '';
   if ($wgethandle ne '') {
      print UPLOAD $buff while read($wgethandle, $buff, 32768);
      close($wgethandle);
   } else {
      print UPLOAD $buff while read($upload, $buff, 32768);
      close($upload);
   }

   close(UPLOAD) or
      openwebmailerror(gettext('Cannot close file:') . " $vpathstr ($!)");

   writelog("webdisk upload - $vpath");
   writehistory("webdisk upload - $vpath");

   return gettext('Upload') . ' :: ' . gettext('Success') . ' :: ' . "($vpathstr)";
}

sub dirfilesel {
   # provide a reduced interface for users to choose or save attachments to and from the webdisk
   my ($action, $olddir, $newdir, $filesort, $wdpage) = @_;

   my $showhidden        = param('showhidden') || 0;
   my $singlepage        = param('singlepage') || 0;

   # for send_saveatt, used in compose to save attfile
   my $attfile           = param('attfile')  || '';
   my $attachment_nodeid = param('attachment_nodeid');
   my $convfrom          = param('convfrom') || '';

   # attname is from compose or readmessage, its charset may be different than prefs{charset}
   my $attnamecharset    = param('attnamecharset') || $prefs{charset};
   my $attname           = param('attname') || '';
   $attname              = (iconv($attnamecharset, $prefs{charset}, $attname))[0];

   autoclosewindow(gettext('Save to Webdisk'), gettext('Parameter format error.'))
      if ($action eq 'send_saveatt' && $attfile eq '')
         || ($action eq 'read_saveatt' && $attachment_nodeid eq '');

   my $currentdir = '';
   my @list       = ();

   if ($wdkeyword eq '') {
      # user has not supplied a wdkeyword
      foreach my $dir ($newdir, $olddir, '/') {
         next unless defined $dir && $dir;

         verify_vpath($webdiskrootdir, $dir);

         opendir(D, "$webdiskrootdir/$dir") or
            openwebmailerror(gettext('Cannot open directory:') . ' ' . f2u($dir) . " ($!)");

         @list = readdir(D);

         closedir(D) or
            openwebmailerror(gettext('Cannot close directory:') . ' ' . f2u($dir) . " ($!)");

         $currentdir = $dir;
         last;
      }
   } else {
      # the user is supplying a webdisk keyword to search
      # populate the @list with the search results
      filelist_of_search($wdsearchtype, $wdkeyword, $olddir, dotpath('webdisk.cache'), \@list);

      # olddir = newdir if wdkeyword is supplied for searching
      $currentdir = $olddir;
   }

   openwebmailerror(gettext('Cannot set current directory.')) if $currentdir eq '';

   my %fsize     = ();
   my %fdate     = ();
   my %ftype     = ();
   my %flink     = ();
   my $dcount    = 0;
   my $fcount    = 0;
   my $sizecount = 0;

   foreach my $filename (@list) {
      next if $filename eq '.' || $filename eq '..';

      next if (!$config{webdisk_lshidden} || !$showhidden) && $filename =~ m/^(?:\.|:2e)/;

      next if !$config{webdisk_lsmailfolder} && is_under_dotdir_or_mail_folder("$webdiskrootdir/$currentdir/$filename");

      if (-l "$webdiskrootdir/$currentdir/$filename") {
         # symbolic link, aka:shortcut
         next if !$config{webdisk_lssymlink};

         my $realpath = readlink("$webdiskrootdir/$currentdir/$filename");
         $realpath    = "$webdiskrootdir/$currentdir/$realpath" if $realpath !~ m#^/#;
         my $vpath    = fullpath2vpath($realpath, $webdiskrootdir);

         if (defined $vpath && $vpath ne '') {
            $flink{$filename} = " -> $vpath";
         } else {
            next if !$config{webdisk_allow_symlinkout};

            $flink{$filename} = $config{webdisk_symlinkout_display} eq 'path' ? " -> " . gettext('system') . "::$realpath" :
                                $config{webdisk_symlinkout_display} eq '@'    ? '@' : '';
         }
      }

      my (
            $st_dev, $st_ino, $st_mode, $st_nlink, $st_uid, $st_gid, $st_rdev,
            $st_size, $st_atime, $st_mtime, $st_ctime, $st_blksize, $st_blocks
         ) = stat("$webdiskrootdir/$currentdir/$filename");

      if (($st_mode & 0170000) == 0040000) {
         $ftype{$filename} = 'd';
         $dcount++;
      } elsif (($st_mode & 0170000) == 0100000) {
         $ftype{$filename} = 'f';
         $fcount++;
         $sizecount += $st_size;
      } else {
         # unix specific filetype: fifo, socket, block dev, char dev..
         # skip because dirfilesel is used for upload/download
         next;
      }

      $fsize{$filename} = $st_size;

      $fdate{$filename} = $st_mtime;
   }

   my %dummy = ();
   my @sortedlist = sortfiles($filesort, \%ftype, \%fsize, \%fdate, \%dummy);

   # use 10 instead of $prefs{webdisk_dirnumitems} for shorter page
   my $totalpages = int(scalar @sortedlist / 10 + 0.999999);
   $totalpages = 1 if $totalpages < 1;

   if ($currentdir ne $olddir) {
      $wdpage = 1; # reset page number if change to new dir
   } else {
      $wdpage = 1 if $page < 1;
      $wdpage = $totalpages if $wdpage > $totalpages;
   }

   my @pathloop    = mkpathloop($currentdir, $wdpage, $filesort, 0);
   my @headersloop = mkheadersloop($currentdir, $wdpage, $filesort, '', 0);

   my $filesloop = [];

   if (scalar @sortedlist > 0) {
      my $os = $^O || 'generic';

      my ($i_first, $i_last) = (0, $#sortedlist);

      if (!$singlepage) {
         # use 10 instead of $prefs{webdisk_dirnumitems} for shorter page
         $i_first  = ($wdpage - 1) * 10;
         $i_last   = $i_first + 9;
         $i_last   = $#sortedlist if $i_last > $#sortedlist;
      }

      foreach my $i ($i_first .. $i_last) {
         my $filename = $sortedlist[$i];
         my $vpath    = absolute_vpath($currentdir, $filename);
         my $vpathstr = f2u($vpath);
         my $is_txt   = $ftype{$filename} eq 'd'
                        ? 0
                        : (-T "$webdiskrootdir/$currentdir/$filename" || $filename =~ m/\.(txt|html?)$/i);
         my $ficon    = $prefs{iconset} =~ m/^Text$/
                        ? ''
                        : findicon($filename, $ftype{$filename}, $is_txt, $os);
         my $datestr  = defined $fdate{$filename}
                        ? ow::datetime::dateserial2str(
                                                         ow::datetime::gmtime2dateserial($fdate{$filename}),
                                                         $prefs{timeoffset},
                                                         $prefs{daylightsaving},
                                                         $prefs{dateformat},
                                                         $prefs{hourformat},
                                                         $prefs{timezone}
                                                      )
                        : '';

         push(@{$filesloop}, {
                                # standard params
                                sessionid         => $thissession,
                                folder            => $folder,
                                message_id        => $messageid,
                                sort              => $sort,
                                page              => $page,
                                longpage          => $longpage,
                                url_cgi           => $config{ow_cgiurl},
                                url_html          => $config{ow_htmlurl},
                                use_texticon      => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                iconset           => $prefs{iconset},
                                (map { $_, $icons->{$_} } keys %{$icons}),

                                # filesloop
                                wdpage            => $wdpage,
                                $action           => 1,
                                action            => $action,
                                uselightbar       => $prefs{uselightbar},
                                attfile           => $attfile,
                                attname           => $attname,
                                attachment_nodeid => $attachment_nodeid,
                                convfrom          => $convfrom,
                                odd               => $i % 2,
                                currentdir        => $currentdir,
                                filesort          => $filesort,
                                showhidden        => $showhidden,
                                singlepage        => $singlepage,
                                isdir             => $ftype{$filename} eq 'd',
                                filename          => $filename,
                                vpath             => $vpath,
                                vpathstr          => $vpathstr,
                                accesskeynr       => ($i + 1) % 10,
                                ficon             => $ficon,
                                filenamestr       => f2u($filename),
                                flinkstr          => defined($flink{$filename}) ? f2u($flink{$filename}) : '',
                                datestr           => $datestr,
                                fsizestr          => lenstr($fsize{$filename},1),
                                fsize             => sprintf(ngettext('%d Byte', '%d Bytes', $fsize{$filename}), $fsize{$filename}),
                             }
             );
      }
   }

   my $defaultname = '';

   $defaultname = f2u(absolute_vpath($currentdir, u2f($attname)))
      if $action eq 'send_saveatt' || $action eq 'read_saveatt';

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_dirfilesel.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );
   $template->param(
                      # header.tmpl
                      header_template   => get_header($config{header_template_file}),

                      # standard params
                      sessionid         => $thissession,
                      folder            => $folder,
                      message_id        => $messageid,
                      sort              => $sort,
                      page              => $page,
                      longpage          => $longpage,
                      url_cgi           => $config{ow_cgiurl},
                      url_html          => $config{ow_htmlurl},
                      use_texticon      => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      iconset           => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # webdisk_dirfilesel.tmpl
                      wdpage            => $wdpage,
                      wdkeyword         => $wdkeyword,
                      wdsearchtype      => $wdsearchtype,
                      $action           => 1,
                      action            => $action,
                      currentdir        => $currentdir,
                      parentdir         => absolute_vpath($currentdir, '..'),
                      gotodir           => $gotodir,
                      isroot            => $currentdir eq '/',
                      attfile           => $attfile,
                      attname           => $attname,
                      attachment_nodeid => $attachment_nodeid,
                      convfrom          => $convfrom,
                      filesort          => $filesort,
                      enablehidden      => $config{webdisk_lshidden},
                      showhidden        => $showhidden,
                      singlepage        => $singlepage,
                      pathloop          => \@pathloop,
                      headersloop       => \@headersloop,
                      dcount            => sprintf(ngettext('%d Directory', '%d Directories', $dcount), $dcount),
                      fcount            => sprintf(ngettext('%d File', '%d Files', $fcount), $fcount),
                      totalsize         => lenstr($sizecount, 1),
                      filesloop         => $filesloop,
                      totalpages        => $totalpages,
                      pageselectloop    => [
                                              map { {
                                                       option   => $_,
                                                       label    => $_,
                                                       selected => $_ eq $wdpage ? 1 : 0,
                                                  } } grep {
                                                              $_ == 1
                                                              || $_ == $totalpages
                                                              || abs($_ - $wdpage) < 10
                                                              || abs($_ - $wdpage) < 100 && $_ % 10 == 0
                                                              || abs($_ - $wdpage) < 1000 && $_ % 100 == 0
                                                              || $_ % 1000 == 0
                                                           } (1..$totalpages)
                                           ],
                      prevpage          => $wdpage > 1 ? $wdpage - 1 : '',
                      nextpage          => $wdpage < $totalpages ? $wdpage + 1 : '',
                      is_right_to_left  => $ow::lang::RTL{$prefs{locale}},
                      defaultname       => $defaultname,

                      # footer.tmpl
                      footer_template   => get_footer($config{footer_template_file}),
                   );

   my $cookie = cookie(
                         -name  => "ow-currentdir-$domain-$user",
                         -value => $currentdir,
                         -path  => '/'
                      );

   httpprint([-cookie => $cookie], [$template->output]);
   return;
}

sub filelist_of_search {
   # given a wdsearchtype and a wdkeyword, find the files that match and populate the @{$r_list}
   my ($wdsearchtype, $wdkeyword, $vpath, $cachefile, $r_list) = @_;

   my $vpathstr       = f2u($vpath);

   # file searches use wdkeyword_fs
   my $wdkeyword_fs   = (iconv($prefs{charset}, $prefs{fscharset}, $wdkeyword))[0];

   # replace . with \. to make it more "shell-like"
   $wdkeyword_fs =~ s/\./\\./g;

   # replace * not preceeded by . with .* to make it more "shell-like"
   $wdkeyword_fs =~ s/(?<!\.)\*/\.\*/g;

   # replace ? not preceeded by ( with . to make it more "shell-like"
   $wdkeyword_fs =~ s/(?<![(])\?/\./g;

   # text searches use wdkeyword_utf8
   my $wdkeyword_utf8 = (iconv($prefs{charset}, 'utf-8', $wdkeyword))[0];

   my $metainfo       = join('@@@', $wdsearchtype, $wdkeyword_fs, $vpath);
   my $cache_metainfo = '';
   $cachefile         = ow::tool::untaint($cachefile);

   if (-e $cachefile) {
      ow::filelock::lock($cachefile, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . " $cachefile");

      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      $cache_metainfo = <CACHE>;

      chomp($cache_metainfo);

      close(CACHE);
   }

   if ($cache_metainfo ne $metainfo) {
      my @cmd    = ();
      my $stdout = '';
      my $stderr = '';
      my $exit   = 0;
      my $sig    = '';

      chdir("$webdiskrootdir/$vpath") or
         openwebmailerror(gettext('Cannot change to directory:') . " $vpathstr ($!)");

      my $findbin = ow::tool::findbin('find') || '';

      openwebmailerror(gettext('Program does not exist:') . ' (find)') if $findbin eq '';

      # TODO: this is an ugly way to fork a process and read its stdout
      # use ow::execute::execute or IPC directly
      open(F, "-|") or
         do {
               open(STDERR,">/dev/null");
               exec($findbin, ".", "-print");
               exit 9
            };
      my @f = <F>;
      close(F);

      foreach my $fname (@f) {
         $fname =~ s|^\./||;
         $fname =~ s/\s+$//;

         if ($wdsearchtype eq 'filename') {
            # search wdkeyword in file name
            if (ow::tool::is_regex($wdkeyword_fs)) {
               push(@{$r_list}, $fname) if $fname =~ m/$wdkeyword_fs/i;
            } else {
               push(@{$r_list}, $fname) if $fname =~ m/\Q$wdkeyword_fs\E/i;
            }
         } else {
            # search wdkeyword in file content
            next unless -f "$webdiskrootdir/$vpath/$fname";

            my $ext = $fname;
            $ext =~ s!.*/!!;
            $ext =~ m!.*\.(.*)!;
            $ext = $1;

            my $contenttype = ow::tool::ext2contenttype($fname);

            if ($contenttype =~ m/msword/) {
               # get the text of the word file and search it
               my $antiwordbin = ow::tool::findbin('antiword') || '';

               next if $antiwordbin eq '';

               my ($stdout, $stderr, $exit, $sig) = ow::execute::execute($antiwordbin, '-m', 'UTF-8.txt', "$webdiskrootdir/$vpath/$fname");

               next if $exit || $sig;

               $stdout = (iconv('utf-8', $prefs{charset}, $stdout))[0];

               push(@{$r_list}, $fname) if $stdout =~ m/$wdkeyword_utf8/i;
            } elsif ($contenttype =~ m/text/ || $ext eq '') {
               # only read leading 4MB
               my $buff = '';

               sysopen(F, "$webdiskrootdir/$vpath/$fname", O_RDONLY) or
                  openwebmailerror(gettext('Cannot open file:') . " $webdiskrootdir/$vpathstr/$fname ($!)");

               read(F, $buff, 4 * 1024 * 1024);

               close(F) or
                  openwebmailerror(gettext('Cannot open file:') . " $webdiskrootdir/$vpathstr/$fname ($!)");

               push(@{$r_list}, $fname) if $buff =~ m/$wdkeyword_fs/i;
            }
         }
      }

      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      print CACHE join("\n", $metainfo, @{$r_list});

      close(CACHE) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");
   } else {
      my @result = ();
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      $_ = <CACHE>;

      while (<CACHE>) {
         chomp;
         push (@{$r_list}, $_);
      }

      close(CACHE) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");
   }

   ow::filelock::lock($cachefile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . " $cachefile");

   return undef;
}

sub webdisk_execute {
   # a wrapper for execute() to handle the dirty work
   my ($opstr, @cmd) = @_;

   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute(@cmd);

   # try to conv realpath in stdout/stderr back to vpath
   foreach ($stdout, $stderr) {
      s!(?:$webdiskrootdir/+|^$webdiskrootdir/*| $webdiskrootdir/*)! /!g if defined;
      s!^\s*!!mg if defined;
      s!/+!/!g if defined;
   }

   ($stdout, $stderr) = iconv($prefs{fscharset}, $prefs{charset}, $stdout, $stderr);

   $stdout = '' unless defined $stdout;
   $stderr = '' unless defined $stderr;
   $opstr  = gettext('Operation') unless defined $opstr;

   if ($exit || $sig) {
      if ($sig) {
         openwebmailerror("$opstr :: " . gettext('ERROR') . " :: (" . gettext('exit status') . " $exit, " . gettext('terminated by signal') . " $sig)\n$stdout$stderr");
      } else {
         openwebmailerror("$opstr :: " . gettext('ERROR') . " :: (" . gettext('exit status') . " $exit)\n$stdout$stderr");
      }
   } else {
      writelog('webdisk execute - ' . join(' ', @cmd));
      writehistory('webdisk execute - ' . join(' ', @cmd));

      return "$opstr :: " . gettext('Success') . " :: (" . gettext('exit status') . " $exit)\n$stdout$stderr";
   }
}

sub is_quota_available {
   my $writesize = shift;

   if ($quotalimit > 0 && $quotausage + $writesize > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
      return 0 if ($quotausage + $writesize > $quotalimit);
   }

   return 1;
}

sub track_upload {
   # this is called by CGI.pm while a file upload is in progress
   # we write the upload bytes_read to a temp file that can be then
   # be checked by an ajax call in order to monitor the progress of
   # the upload and provide realtime feedback to the user
   my ($filename, $buffer, $bytes_read, $data) = @_;

   # TODO: finish this and the ajax progress bar on the client side
}

sub upload_progress {
   # called via ajax to check on the progress of an upload
   # progress is defined as number of bytes read versus total bytes
}
