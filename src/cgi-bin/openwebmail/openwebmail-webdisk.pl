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
#
# Based on work from
# 2002/12/30 tung.AT.turtle.ee.ncku.edu.tw
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
#

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

die("SCRIPT_DIR cannot be set") if ($SCRIPT_DIR eq '');
push (@INC, $SCRIPT_DIR);

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH}='/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

use HTML::Template 2.9;
use vars qw($htmltemplatefilters);     # defined in ow-shared.pl

use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

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
use vars qw(%prefs);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_wdbutton %lang_text %lang_err);	# defined in lang/xy

# local globals
use vars qw($folder $messageid);
use vars qw($escapedmessageid $escapedfolder);
use vars qw($webdiskrootdir);

# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

if (!$config{'enable_webdisk'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webdisk'} $lang_err{'access_denied'}");
}

# userenv_init() will set umask to 0077 to protect mail folder data.
# set umask back to 0022 here dir & files are created as world readable
umask(0022);

$folder = ow::tool::unescapeURL(param('folder')) || 'INBOX';
$messageid = param('message_id')||'';

$escapedfolder = ow::tool::escapeURL($folder);
$escapedmessageid = ow::tool::escapeURL($messageid);

$webdiskrootdir = ow::tool::untaint($homedir.absolute_vpath("/", $config{'webdisk_rootpath'}));
$webdiskrootdir =~ s!/+$!!; # remove tail /
if (! -d $webdiskrootdir) {
   mkdir($webdiskrootdir, 0755) or
      openwebmailerror(__FILE__, __LINE__, "$lang_text{'couldnt_create'} $webdiskrootdir ($!)");
}

my $action = param('action') || '';
my $currentdir;
if (defined param('currentdir') && param('currentdir') ne "") {
   $currentdir = ow::tool::unescapeURL(param('currentdir'));
} else {
   $currentdir = cookie("ow-currentdir-$domain-$user"),
}
my $gotodir  = ow::tool::unescapeURL(param('gotodir')) || '';
my @selitems = (param('selitems')); 
foreach (@selitems) { $_=ow::tool::unescapeURL($_) }
my $destname = ow::tool::unescapeURL(param('destname')) || '';
my $filesort = param('filesort') || 'name';
my $page     = param('page') || 1;

# all path in param are treated as virtual path under $webdiskrootdir.
$currentdir = absolute_vpath("/", $currentdir);
$gotodir = absolute_vpath($currentdir, $gotodir);

my $msg = verify_vpath($webdiskrootdir, $currentdir);
openwebmailerror(__FILE__, __LINE__, "$lang_err{'access_denied'} (".f2u($currentdir).": $msg)") if ($msg);
$currentdir=ow::tool::untaint($currentdir);

writelog("debug - request webdisk begin, action=$action, currentdir=$currentdir - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "mkdir" || defined param('mkdirbutton') ) {
   if ($config{'webdisk_readonly'}) {
      $msg=$lang_err{'webdisk_readonly'};
   } elsif (is_quota_available(0)) {
      $msg = createdir($currentdir, $destname) if ($destname);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "newfile" || defined param('newfilebutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = createfile($currentdir, $destname) if ($destname);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "copy" || defined param('copybutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = copymovesymlink_dirfiles("copy", $currentdir, $destname, @selitems) if ($#selitems >= 0);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "move" || defined param('movebutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = copymovesymlink_dirfiles("move", $currentdir, $destname, @selitems) if ($#selitems >= 0);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ( $config{'webdisk_allow_symlinkcreate'} &&
         ($action eq "symlink" || defined param('symlinkbutton')) ){
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = copymovesymlink_dirfiles("symlink", $currentdir, $destname, @selitems) if ($#selitems >= 0);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "delete" || defined param('deletebutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } else {
      $msg = deletedirfiles($currentdir, @selitems) if  ($#selitems >= 0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ( $config{'webdisk_allow_chmod'} &&
	 ($action eq "chmod" || defined param('chmodbutton')) ) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } else {
      $msg = chmoddirfiles(param('permission'), $currentdir, @selitems) if  ($#selitems >= 0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "editfile" || defined param('editbutton')) {
   if ($config{'webdisk_readonly'}) {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'webdisk_readonly'});
   } elsif (is_quota_available(0)) {
      if ($#selitems == 0) {
         editfile($currentdir, $selitems[0]);
      } else {
         autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'onefileonly'});
      }
   } else {
      autoclosewindow($lang_text{'quotahit'}, $lang_err{'quotahit_alert'});
   }

} elsif ($action eq "savefile" || defined param('savebutton')) {
   if ($config{'webdisk_readonly'}) {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'webdisk_readonly'});
   } elsif (is_quota_available(0)) {
      savefile($currentdir, $destname, param('filecontent')) if ($destname ne '');
   } else {
      autoclosewindow($lang_text{'quotahit'}, $lang_err{'quotahit_alert'});
   }

} elsif ( $config{'webdisk_allow_gzip'} &&
         ($action eq "gzip" || defined param('gzipbutton')) ) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = compressfiles("gzip", $currentdir, '', @selitems) if ($#selitems >= 0);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ( $config{'webdisk_allow_zip'} &&
         ($action eq "mkzip" || defined param('mkzipbutton')) ) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = compressfiles("mkzip", $currentdir, $destname, @selitems) if ($#selitems >= 0);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ( $config{'webdisk_allow_tar'} &&
	 ($action eq "mktgz" || defined param('mktgzbutton')) ) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = compressfiles("mktgz", $currentdir, $destname, @selitems) if ($#selitems >= 0);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "decompress" || defined param('decompressbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      if ($#selitems == 0) {
         $msg = decompressfile($currentdir, $selitems[0]);
      } else {
         $msg = "$lang_wdbutton{'decompress'} - $lang_err{'onefileonly'}";
      }
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ( $config{'webdisk_allow_listarchive'} &&
	 ($action eq "listarchive" || defined param('listarchivebutton')) ) {
   if ($#selitems == 0) {
      $msg = listarchive($currentdir, $selitems[0]);
   } else {
      $msg = "$lang_wdbutton{'listarchive'} - $lang_err{'onefileonly'}";
   }

} elsif ($action eq "wordpreview" || defined param('wordpreviewbutton')) {
   if ($#selitems == 0) {
      $msg = wordpreview($currentdir, $selitems[0]);
   } else {
      $msg = "MS Word $lang_wdbutton{'preview'} - $lang_err{'onefileonly'}";
   }

} elsif ($action eq "mkpdf" || defined param('mkpdfbutton') ) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      if ($#selitems == 0) {
         $msg = makepdfps('mkpdf', $currentdir, $selitems[0]);
      } else {
         $msg = "$lang_wdbutton{'mkpdf'} - $lang_err{'onefileonly'}";
      }
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mkps" || defined param('mkpsbutton') ) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      if ($#selitems == 0) {
         $msg = makepdfps('mkps', $currentdir, $selitems[0]);
      } else {
         $msg = "$lang_wdbutton{'mkps'} - $lang_err{'onefileonly'}";
      }
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mkthumbnail" || defined param('mkthumbnailbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg = makethumbnail($currentdir, @selitems) if ($#selitems >= 0);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "preview") {
   my $vpath = absolute_vpath($currentdir, $selitems[0]);
   my $filecontent = param('filecontent')||'';
   if ($#selitems == 0) {
      if ($filecontent) {
         $msg = previewfile($currentdir, $selitems[0], $filecontent);
      } elsif (-d "$webdiskrootdir/$vpath" ) {
         showdir($currentdir, $vpath, $filesort, $page, $msg); 
         $msg = '';
      } else {
         $msg = previewfile($currentdir, $selitems[0], '');
      }
   } else {
      $msg = $lang_err{'no_file_todownload'};
   }
   openwebmailerror(__FILE__, __LINE__, $msg) if ($msg ne '');

} elsif ($action eq "download" || defined param('downloadbutton')) {
   if ($#selitems > 0) {
      $msg = downloadfiles($currentdir, @selitems);
   } elsif ($#selitems == 0) {
      my $vpath = absolute_vpath($currentdir, $selitems[0]);
      if (-d "$webdiskrootdir/$vpath" ) {
         $msg = downloadfiles($currentdir, @selitems);
      } else {
         $msg = downloadfile($currentdir, $selitems[0]);
      }
   } else {
      $msg = "$lang_err{'no_file_todownload'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg) if (defined($msg) && $msg ne '');

} elsif ($action eq "upload" || defined param('uploadbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg = "$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      my $upload = param('upload');	# name and handle of the upload file
      $msg = uploadfile($currentdir, $upload) if ($upload);
   } else {
      $msg = "$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "sel_addattachment") { 	# used in composemsg to add attachment
   dirfilesel($action, $currentdir, $gotodir, $filesort, $page);

} elsif ($action eq "sel_saveattfile" ||	# used in composemsg to save attfile
         $action eq "sel_saveattachment") {	# used in readmsg to save attachment
   if ($config{'webdisk_readonly'}) {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'webdisk_readonly'});
   } elsif (is_quota_available(0)) {
      dirfilesel($action, $currentdir, $gotodir, $filesort, $page);
   } else {
      autoclosewindow($lang_text{'quotahit'}, $lang_err{'quotahit_alert'});
   }

} elsif ($action eq "userrefresh")  {
   if ($config{'quota_module'} ne 'none') {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "showdir" || $action eq "" || defined param('chdirbutton'))  {
   # put chdir in last or user will be matched by ($action eq "") when clicking button
   if ($destname ne '') {	# chdir
      $destname = absolute_vpath($currentdir, $destname);
      showdir($currentdir, $destname, $filesort, $page, $msg);
   } else {		# showdir, refresh
      showdir($currentdir, $gotodir, $filesort, $page, $msg);
   }

} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request webdisk end, action=$action, currentdir=$currentdir - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();

# BEGIN SUBROUTINES

sub createdir {
   my ($currentdir, $destname) = @_;
   $destname = u2f($destname);

   my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr = f2u($vpath);
   my $err      = verify_vpath($webdiskrootdir, $vpath);
   return ("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   if (-e "$webdiskrootdir/$vpath") {
      return("$lang_text{'dir'} $vpathstr $lang_err{'already_exists'}\n") if (-d _);
      return("$lang_text{'file'} $vpathstr $lang_err{'already_exists'}\n");
   } else {
      if (mkdir("$webdiskrootdir/$vpath", 0755)) {
         writelog("webdisk mkdir - $vpath");
         writehistory("webdisk mkdir - $vpath");
         return("$lang_wdbutton{'mkdir'} $vpathstr\n");
      } else {
         return("$lang_err{'couldnt_create'} $vpathstr ($!)\n");
      }
   }
}

sub createfile {
   my ($currentdir, $destname) = @_;
   $destname = u2f($destname);

   my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr = f2u($vpath);
   my $err      = verify_vpath($webdiskrootdir, $vpath);
   return ("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   if ( -e "$webdiskrootdir/$vpath") {
      return("$lang_text{'dir'} $vpathstr $lang_err{'already_exists'}\n") if (-d _);
      return("$lang_text{'file'} $vpathstr $lang_err{'already_exists'}\n");
   } else {
      if (sysopen(F, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT)) {
         print F ''; 
         close(F);
         writelog("webdisk createfile - $vpath");
         writehistory("webdisk createfile - $vpath");
         return("$lang_wdbutton{'newfile'} $vpathstr\n");
      } else {
         return("$lang_err{'couldnt_create'} $vpathstr ($!)\n");
      }
   }
}

sub deletedirfiles {
   my ($currentdir, @selitems) = @_;
   my ($msg, $err);

   my @filelist;
   foreach (@selitems) {
      my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $_));
      my $vpathstr = f2u($vpath);
      $err=verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} ($vpathstr: $err)\n";
         next;
      }
      if (!-l "$webdiskrootdir/$vpath" && !-e "$webdiskrootdir/$vpath") {
         $msg .= "$vpathstr $lang_err{'doesnt_exist'}\n";
         next;
      }
      if (-f _ && $vpath=~/\.(?:jpe?g|gif|png|bmp|tif)$/i) {
         my $thumbnail = path2thumbnail("$webdiskrootdir/$vpath");
         push(@filelist, $thumbnail) if (-f $thumbnail);
      }
      push(@filelist, "$webdiskrootdir/$vpath");
   }
   return($msg) if ($#filelist < 0);

   my @cmd;
   my $rmbin = ow::tool::findbin('rm');
   return("$lang_text{'program'} rm $lang_err{'doesnt_exist'}\n") if ($rmbin eq '');
   @cmd = ($rmbin, '-Rfv');

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $msg2 = webdisk_execute($lang_wdbutton{'delete'}, @cmd, @filelist);
   if ($msg2 =~ /rm:/) {
      $cmd[1] =~ s/v//;
      $msg2 = webdisk_execute($lang_wdbutton{'delete'}, @cmd, @filelist);
   }
   $msg .= $msg2;
   if ($quotalimit > 0 && $quotausage > $quotalimit) {	# get uptodate quotausage
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   return($msg);
}

sub chmoddirfiles {
   my ($perm, $currentdir, @selitems) = @_;
   my ($msg, $err);

   $perm =~ s/\s//g;
   if ($perm =~ /[^0-7]/) {	# has invalid char for chmod?
      return("$lang_wdbutton{'chmod'} $lang_err{'has_illegal_chars'}\n");
   } elsif ($perm !~ /^0/) {	# should leading with 0
      $perm = '0' . $perm;
   }
   if (!$config{'webdisk_allow_chmod'}) {
      return("chmod disabled\n");
   }

   my @filelist;
   foreach (@selitems) {
      my $vpath    = ow::tool::untaint(absolute_vpath($currentdir, $_));
      my $vpathstr = f2u($vpath);
      $err = verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} ($vpathstr: $err)\n";
         next;
      }
      if (!-l "$webdiskrootdir/$vpath" && !-e "$webdiskrootdir/$vpath") {
         $msg.="$vpathstr $lang_err{'doesnt_exist'}\n";
         next;
      }
      if (-f _ && $vpath =~ /\.(?:jpe?g|gif|png|bmp|tif)$/i) {
         my $thumbnail = path2thumbnail("$webdiskrootdir/$vpath");
         push(@filelist, $thumbnail) if (-f $thumbnail);
      }
      push(@filelist, "$webdiskrootdir/$vpath");
   }
   return($msg) if ($#filelist < 0);

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $notchanged = $#filelist + 1 - chmod(oct(ow::tool::untaint($perm)), @filelist);
   if ($notchanged != 0) {
      return("$notchanged item(s) not changed ($!)");
   }
   return($msg);
}

sub copymovesymlink_dirfiles {
   my ($op, $currentdir, $destname, @selitems) = @_;
   $destname = u2f($destname);

   my ($msg, $err);
   my $vpath2    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpath2str = f2u($vpath2);
   $err = verify_vpath($webdiskrootdir, $vpath2);
   return ("$lang_err{'access_denied'} ($vpath2str: $err)\n") if ($err);

   if ($#selitems > 0) {
      if (!-e "$webdiskrootdir/$vpath2") {
         return("$vpath2str $lang_err{'doesnt_exist'}\n");
      } elsif (!-d _) {
         return("$vpath2str $lang_err{'isnt_a_dir'}\n");
      }
   }

   my @filelist;
   foreach (@selitems) {
      my $vpath1    = ow::tool::untaint(absolute_vpath($currentdir, $_));
      my $vpath1str = f2u($vpath1);
      $err = verify_vpath($webdiskrootdir, $vpath1);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} ($vpath1str: $err)\n";
         next;
      }
      if (! -e "$webdiskrootdir/$vpath1") {
         $msg .= "$vpath1str $lang_err{'doesnt_exist'}\n";
         next;
      }
      next if ($vpath1 eq $vpath2);

      my $p = "$webdiskrootdir/$vpath1";
      $p =~ s!/+!/!g;	# eliminate duplicated /
      push(@filelist, $p);
   }
   return($msg) if ($#filelist < 0);

   my @cmd;
   if ($op eq "copy") {
      my $cpbin = ow::tool::findbin('cp');
      return("$lang_text{'program'} cp $lang_err{'doesnt_exist'}\n") if ($cpbin eq '');
      @cmd = ($cpbin, '-pRfv');
   } elsif ($op eq "move") {
      my $mvbin = ow::tool::findbin('mv');
      return("$lang_text{'program'} mv $lang_err{'doesnt_exist'}\n") if ($mvbin eq '');
      @cmd = ($mvbin, '-fv');
   } elsif ($op eq "symlink") {
      my $lnbin = ow::tool::findbin('ln');
      return("$lang_text{'program'} ln $lang_err{'doesnt_exist'}\n") if ($lnbin eq '');
      @cmd = ($lnbin, '-sv');
   } else {
      return($msg);
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $msg2 = webdisk_execute($lang_wdbutton{$op}, @cmd, @filelist, "$webdiskrootdir/$vpath2");
   if ($msg2 =~ /cp:/ || $msg2 =~ /mv:/ || $msg2 =~ /ln:/) {	# -vcmds not supported on solaris
      $cmd[1] =~ s/v//;
      $msg2 = webdisk_execute($lang_wdbutton{$op}, @cmd, @filelist, "$webdiskrootdir/$vpath2");
   }
   $msg .= $msg2;
   return($msg);
}

sub editfile {
   my ($currentdir, $selitem) = @_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);
   my $content;

   if (-d "$webdiskrootdir/$vpath") {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'edit_notfordir'});
   } elsif (-f "$webdiskrootdir/$vpath") {
      my $err = verify_vpath($webdiskrootdir, $vpath);
      autoclosewindow($lang_wdbutton{'edit'}, "$lang_err{'access_denied'} ($vpathstr: $err)") if ($err);

      ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_SH|LOCK_NB) or
         autoclosewindow($lang_text{'edit'}, "$lang_err{'couldnt_readlock'} $vpathstr!");
      if (sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY)) {
         local $/; 
         undef $/;
         $content = <F>; 
         close(F);
      } else {
         ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN);
         autoclosewindow($lang_wdbutton{'edit'}, "$lang_err{'couldnt_read'} $vpathstr");
      }
      ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN);

      writelog("webdisk editfile - $vpath");
      writehistory("webdisk editfile - $vpath");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_editfile.tmpl"),
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
                      sessionid           => $thissession,
                      url_cgi             => $config{ow_cgiurl},

                      # webdisk_editfile.tmpl
                      currentdir          => $currentdir,
                      vpathstr            => $vpathstr,
                      is_html             => ($vpath =~ /\.html?$/) ? 1 : 0,
                      rows                => $prefs{'webdisk_fileeditrows'},
                      columns             => $prefs{'webdisk_fileeditcolumns'},
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
   my $err = verify_vpath($webdiskrootdir, $vpath);
   autoclosewindow($lang_text{'savefile'}, "$lang_err{'access_denied'} ($vpathstr: $err)", 60) if ($err);

   $content =~ s|</ESCAPE_TEXTAREA>|</textarea>|gi;
   $content =~ s/\r\n/\n/g;
   $content =~ s/\r/\n/g;

   if (!sysopen(F, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT) ) {
      autoclosewindow($lang_text{'savefile'}, "$lang_text{'savefile'} $lang_text{'failed'} ($vpathstr: $!)", 60);
   }
   ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_EX) or
      autoclosewindow($lang_text{'savefile'}, "$lang_err{'couldnt_writelock'} $vpathstr!", 60);
   print F $content;
   close(F);
   ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN);

   writelog("webdisk savefile - $vpath");
   writehistory("webdisk savefile - $vpath");

   my $jscode = qq|if (window.opener.document.dirform!=null) {window.opener.document.dirform.submit();}|;	# refresh parent if it is dirform
   autoclosewindow($lang_text{'savefile'}, "$lang_text{'savefile'} $lang_text{'succeeded'} ($vpathstr)", 5, $jscode);
}

sub compressfiles {	# pack files with gzip, zip or tgz (tar -zcvf)
   my ($ztype, $currentdir, $destname, @selitems)=@_;
   $destname = u2f($destname);

   my ($vpath2, $vpath2str, $msg, $err);
   if ($ztype eq "mkzip" || $ztype eq "mktgz" ) {
      $vpath2    = ow::tool::untaint(absolute_vpath($currentdir, $destname));
      $vpath2str = f2u($vpath2);
      $err = verify_vpath($webdiskrootdir, $vpath2);
      return ("$lang_err{'access_denied'} ($vpath2str: $err)\n") if ($err);
      if (-e "$webdiskrootdir/$vpath2") {
         return("$lang_text{'dir'} $vpath2str $lang_err{'already_exists'}\n") if (-d _);
         return("$lang_text{'file'} $vpath2str $lang_err{'already_exists'}\n");
      }
   }

   my %selitem;
   foreach (@selitems) {
      my $vpath    = absolute_vpath($currentdir, $_);
      my $vpathstr = f2u($vpath);
      $err = verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} ($vpathstr: $err)\n";
         next;
      }

      # use relative path to currentdir since we will chdir to webdiskrootdir/currentdir before compress
      my $p = fullpath2vpath("$webdiskrootdir/$vpath", "$webdiskrootdir/$currentdir");
      # use absolute path if relative to webdiskrootdir/currentdir is not possible
      $p = "$webdiskrootdir/$vpath" if ($p eq "");
      $p = ow::tool::untaint($p);

      if (-d "$webdiskrootdir/$vpath" ) {
         $selitem{".$p/"} = 1;
      } elsif ( -e _ ) {
         $selitem{".$p"} = 1;
      }
   }
   my @filelist = keys(%selitem);
   return($msg) if ($#filelist < 0);

   my @cmd;
   if ($ztype eq "gzip") {
      if (!$config{'webdisk_allow_gzip'}) {
         return "gzip disabled";
      }
      my $gzipbin = ow::tool::findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      @cmd = ($gzipbin, '-rq');
   } elsif ($ztype eq "mkzip") {
      if (!$config{'webdisk_allow_zip'}) {
         return "zip disabled";
      }
      my $zipbin = ow::tool::findbin('zip');
      return("$lang_text{'program'} zip $lang_err{'doesnt_exist'}\n") if ($zipbin eq '');
      @cmd = ($zipbin, '-ryq', "$webdiskrootdir/$vpath2");
   } elsif ($ztype eq "mktgz") {
      if (!$config{'webdisk_allow_tar'}) {
         return "tar disabled";
      }
      my $gzipbin = ow::tool::findbin('gzip');
      my $tarbin  = ow::tool::findbin('tar');
      if (!$config{'webdisk_allow_gzip'}) {
         $gzipbin = '';
      }
      if ($gzipbin ne '') {
         $ENV{'PATH'}=$gzipbin; $ENV{'PATH'}=~s|/gzip||; # for tar
         @cmd = ($tarbin, '-zcpf', "$webdiskrootdir/$vpath2");
      } else {
         @cmd = ($tarbin, '-cpf', "$webdiskrootdir/$vpath2");
      }
   } else {
      return("unknown ztype($ztype)?");
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $opstr;
   if ($ztype eq "mkzip") {
      $opstr = $lang_wdbutton{'mkzip'};
   } elsif ($ztype eq "mktgz") {
      $opstr = $lang_wdbutton{'mktgz'};
   } else {
      $opstr = $lang_wdbutton{'gzip'};
   }
   return(webdisk_execute($opstr, @cmd, @filelist));
}

sub decompressfile {	# unpack tar.gz, tgz, tar.bz2, tbz, gz, zip, rar, arj, ace, lzh, tnef/tnf
   my ($currentdir, $selitem)=@_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   if (!-f "$webdiskrootdir/$vpath" || !-r _) {
      return("$lang_err{'couldnt_read'} $vpathstr");
   }
   my $err = verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   my @cmd;
   if ($vpath =~ /\.(tar\.g?z||tgz)$/i && $config{'webdisk_allow_untar'} 
        && $config{'webdisk_allow_ungzip'}) {
      my $gzipbin = ow::tool::findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      my $tarbin = ow::tool::findbin('tar');
      $ENV{'PATH'} = $gzipbin;
      $ENV{'PATH'} =~ s|/gzip||; # for tar
      @cmd = ($tarbin, '-zxpf');

   } elsif ($vpath =~ /\.(tar\.bz2?||tbz)$/i && $config{'webdisk_allow_untar'} && $config{'webdisk_allow_unbzip2'}) {
      my $bzip2bin = ow::tool::findbin('bzip2');
      return("$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if ($bzip2bin eq '');
      my $tarbin = ow::tool::findbin('tar');
      $ENV{'PATH'} = $bzip2bin; $ENV{'PATH'}=~s|/bzip2||;	# for tar
      @cmd = ($tarbin, '-yxpf');

   } elsif ($vpath =~ /\.tar?$/i && $config{'webdisk_allow_untar'}) {
      my $tarbin = ow::tool::findbin('tar');
      @cmd = ($tarbin, '-xpf');

   } elsif ($vpath =~ /\.g?z$/i && $config{'webdisk_allow_ungzip'}) {
      my $gzipbin = ow::tool::findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      @cmd = ($gzipbin, '-dq');

   } elsif ($vpath =~ /\.bz2?$/i && $config{'webdisk_allow_unbzip2'}) {
      my $bzip2bin = ow::tool::findbin('bzip2');
      return("$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if ($bzip2bin eq '');
      @cmd = ($bzip2bin, '-dq');

   } elsif ($vpath =~ /\.zip$/i && $config{'webdisk_allow_unzip'}) {
      my $unzipbin = ow::tool::findbin('unzip');
      return("$lang_text{'program'} unzip $lang_err{'doesnt_exist'}\n") if ($unzipbin eq '');
      @cmd = ($unzipbin, '-oq');

   } elsif ($vpath =~ /\.rar$/i && $config{'webdisk_allow_unrar'}) {
      my $unrarbin = ow::tool::findbin('unrar');
      return("$lang_text{'program'} unrar $lang_err{'doesnt_exist'}\n") if ($unrarbin eq '');
      @cmd = ($unrarbin, 'x', '-r', '-y', '-o+');

   } elsif ($vpath =~ /\.arj$/i && $config{'webdisk_allow_unarj'}) {
      my $unarjbin = ow::tool::findbin('unarj');
      return("$lang_text{'program'} unarj $lang_err{'doesnt_exist'}\n") if ($unarjbin eq '');
      @cmd = ($unarjbin, 'x');

   } elsif ($vpath =~ /\.ace$/i && $config{'webdisk_allow_unace'}) {
      my $unacebin = ow::tool::findbin('unace');
      return("$lang_text{'program'} unace $lang_err{'doesnt_exist'}\n") if ($unacebin eq '');
      @cmd = ($unacebin, 'x', '-y');

   } elsif ($vpath =~ /\.lzh$/i && $config{'webdisk_allow_unlzh'}) {
      my $lhabin = ow::tool::findbin('lha');
      return("$lang_text{'program'} lha $lang_err{'doesnt_exist'}\n") if ($lhabin eq '');
      @cmd = ($lhabin, '-xfq');

   } elsif ($vpath =~ /\.tne?f$/i && $config{'webdisk_allow_untnef'}) {
      my $tnefbin = ow::tool::findbin('tnef');
      return("$lang_text{'program'} tnef $lang_err{'doesnt_exist'}\n") if ($tnefbin eq '');
      @cmd = ($tnefbin, '--overwrite', '-v', '-f');

   } else {
      return("$lang_err{'decomp_notsupported'} ($vpathstr)\n");
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $opstr;
   if ($vpath =~ /\.(?:zip|rar|arj|ace|lhz|t[bg]z|tar\.g?z|tar\.bz2?|tne?f)$/i) {
      $opstr = $lang_wdbutton{'extract'};
   } else {
      $opstr = $lang_wdbutton{'decompress'};
   }
   return(webdisk_execute($opstr, @cmd, "$webdiskrootdir/$vpath"));
}

sub listarchive {
   my ($currentdir, $selitem) = @_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   if (!$config{'webdisk_allow_listarchive'}) {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_err{'access_denied'}");
      return;
   }

   if (!-f "$webdiskrootdir/$vpath") {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'file'} $vpathstr $lang_err{'doesnt_exist'}");
      return;
   }
   my $err = verify_vpath($webdiskrootdir, $vpath);
   if ($err) {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_err{'access_denied'} ($vpathstr: $err)");
      return;
   }

   my @cmd;
   if ($vpath =~ /\.(tar\.g?z|tgz)$/i) {
      my $gzipbin = ow::tool::findbin('gzip');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      my $tarbin = ow::tool::findbin('tar');
      $ENV{'PATH'} = $gzipbin; 
      $ENV{'PATH'} =~ s|/gzip||; # for tar
      @cmd = ($tarbin, '-ztvf');

   } elsif ($vpath =~ /\.(tar\.bz2?|tbz)$/i) {
      my $bzip2bin = ow::tool::findbin('bzip2');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if ($bzip2bin eq '');
      my $tarbin = ow::tool::findbin('tar');
      $ENV{'PATH'} = $bzip2bin; 
      $ENV{'PATH'} =~ s|/bzip2||;	# for tar
      @cmd = ($tarbin, '-ytvf');

   } elsif ($vpath =~ /\.zip$/i) {
      my $unzipbin = ow::tool::findbin('unzip');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unzip $lang_err{'doesnt_exist'}\n") if ($unzipbin eq '');
      @cmd = ($unzipbin, '-lq');

   } elsif ($vpath =~ /\.rar$/i) {
      my $unrarbin = ow::tool::findbin('unrar');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unrar $lang_err{'doesnt_exist'}\n") if ($unrarbin eq '');
      @cmd = ($unrarbin, 'l');

   } elsif ($vpath =~ /\.arj$/i) {
      my $unarjbin = ow::tool::findbin('unarj');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unarj $lang_err{'doesnt_exist'}\n") if ($unarjbin eq '');
      @cmd = ($unarjbin, 'l');

   } elsif ($vpath =~ /\.ace$/i) {
      my $unacebin = ow::tool::findbin('unace');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unace $lang_err{'doesnt_exist'}\n") if ($unacebin eq '');
      @cmd = ($unacebin, 'l', '-y');

   } elsif ($vpath =~ /\.lzh$/i) {
      my $lhabin = ow::tool::findbin('lha');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} lha $lang_err{'doesnt_exist'}\n") if ($lhabin eq '');
      @cmd = ($lhabin, '-l');

   } elsif ($vpath =~ /\.tne?f$/i) {
      my $tnefbin = ow::tool::findbin('tnef');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} tnef $lang_err{'doesnt_exist'}\n") if ($tnefbin eq '');
      @cmd = ($tnefbin, '-t');

   } else {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_err{'decomp_notsupported'} ($vpathstr)\n");
   }

   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute(@cmd, "$webdiskrootdir/$vpath");
   # try to conv realpath in stdout/stderr back to vpath
   $stdout =~ s!(?:$webdiskrootdir//|\s$webdiskrootdir/)! /!g; 
   $stdout =~ s!/+!/!g;
   $stderr =~ s!(?:$webdiskrootdir//|\s$webdiskrootdir/)! /!g; 
   $stderr =~ s!/+!/!g;
   ($stdout, $stderr) = iconv($prefs{'fscharset'}, $prefs{'charset'}, $stdout, $stderr);

   if ($exit || $sig) {
      my $err = "$lang_text{'program'} $cmd[0]  $lang_text{'failed'} (exit status $exit";
      $err .= ", terminated by signal $sig" if ($sig);
      $err .= ")\n$stdout$stderr";
      autoclosewindow($lang_wdbutton{'listarchive'}, $err);
   } else {
      writelog("webdisk listarchive - $vpath");
      writehistory("webdisk listarchive - $vpath");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_listarchive.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
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

sub wordpreview {		# msword text preview
   my ($currentdir, $selitem) = @_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   if (!-f "$webdiskrootdir/$vpath") {
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_text{'file'} $vpathstr $lang_err{'doesnt_exist'}");
      return;
   }
   my $err = verify_vpath($webdiskrootdir, $vpath);
   if ($err) {
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_err{'access_denied'} ($vpathstr: $err)");
      return;
   }

   my @cmd;
   if ($vpath =~ /\.(?:doc|dot)$/i) {
      my $antiwordbin = ow::tool::findbin('antiword');
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_text{'program'} antiword $lang_err{'doesnt_exist'}\n") if ($antiwordbin eq '');
      @cmd = ($antiwordbin, '-m', 'UTF-8.txt');
   } else {
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_err{'filefmt_notsupported'} ($vpathstr)\n");
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute(@cmd, "$webdiskrootdir/$vpath");

   if ($exit || $sig) {
      # try to conv realpath in stdout/stderr back to vpath
      $stderr =~ s!(?:$webdiskrootdir//|\s$webdiskrootdir/)! /!g; 
      $stderr =~ s!/+!/!g;
      $stderr =~ s/^\s+.*$//mg;	# remove the antiword syntax description
      $stderr = f2u($stderr);

      my $err = "$lang_text{'program'} antiword $lang_text{'failed'} (exit status $exit";
      $err .= ", terminated by signal $sig" if ($sig);
      $err .= ")\n$stderr";
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", $err);
   } else {
      ($stdout) = iconv('utf-8', $prefs{'charset'}, $stdout);
      writelog("webdisk wordpreview - $vpath");
      writehistory("webdisk wordpreview - $vpath");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_wordpreview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
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

sub makepdfps {		# ps2pdf or pdf2ps
   my ($mktype, $currentdir, $selitem)=@_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);

   if ( !-f "$webdiskrootdir/$vpath" || !-r _) {
      return("$lang_err{'couldnt_read'} $vpathstr");
   }
   my $err = verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   my $gsbin=ow::tool::findbin('gs');
   return("$lang_text{'program'} gs $lang_err{'doesnt_exist'}\n") if ($gsbin eq '');

   my @cmd;
   my $outputfile="$webdiskrootdir/$vpath";

   if ($mktype eq 'mkpdf' && $outputfile=~s/^(.*)\.e?ps$/$1\.pdf/i) {
      @cmd=($gsbin, '-q', '-dNOPAUSE', '-dBATCH', '-dSAFER',
		'-dCompatibilityLevel=1.3', '-dPDFSETTINGS=/printer',
		'-sDEVICE=pdfwrite', "-sOutputFile=$outputfile",
		'-c', '.setpdfwrite', '-f');	# -c must immediately before -f

   } elsif ($mktype eq 'mkps' && $outputfile=~s/^(.*)\.pdf$/$1\.ps/i) {
      @cmd=($gsbin, '-q', '-dNOPAUSE', '-dBATCH', '-dSAFER',
		'-sDEVICE=pswrite', "-sOutputFile=$outputfile",
		'-c', 'save', 'pop', '-f');	# -c must immediately before -f

   } else {
      return("$lang_err{'filefmt_notsupported'} ($vpathstr)\n");
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   return(webdisk_execute($lang_wdbutton{$mktype}, @cmd, "$webdiskrootdir/$vpath"));
}

sub makethumbnail {
   my ($currentdir, @selitems)=@_;
   my $msg;

   my $convertbin = ow::tool::findbin('convert');
   return("$lang_text{'program'} convert $lang_err{'doesnt_exist'}\n") if ($convertbin eq '');
   my @cmd = ($convertbin, '+profile', '*', '-interlace', 'NONE', '-geometry', '64x64');

   foreach (@selitems) {
      my $vpath    = absolute_vpath($currentdir, $_);
      my $vpathstr = f2u($vpath);
      my $err = verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} ($vpathstr: $err)\n";
         next;
      }
      next if ( $vpath!~/\.(jpe?g|gif|png|bmp|tif)$/i ||
                !-f "$webdiskrootdir/$vpath" ||
                -s _ < 2048);				# use image itself is as thumbnail if size<2k

      my $thumbnail = ow::tool::untaint(path2thumbnail($vpath));
      my @p = split(/\//, $thumbnail); pop(@p);
      my $thumbnaildir = join('/', @p);
      if (!-d "$webdiskrootdir/$thumbnaildir") {
         if (!mkdir (ow::tool::untaint("$webdiskrootdir/$thumbnaildir"), 0755)) {
            $msg .= "$!\n";
            next;
         }
      }

      my ($img_atime,$img_mtime) = (stat("$webdiskrootdir/$vpath"))[8,9];
      if (-f "$webdiskrootdir/$thumbnail") {
         my ($thumbnail_atime,$thumbnail_mtime) = (stat("$webdiskrootdir/$thumbnail"))[8,9];
         next if ($thumbnail_mtime == $img_mtime);
      }
      $msg .= webdisk_execute("$lang_wdbutton{'mkthumbnail'} $thumbnail", @cmd, "$webdiskrootdir/$vpath", "$webdiskrootdir/$thumbnail");
      if (-f "$webdiskrootdir/$thumbnail.0") {
         my @f;
         foreach (1..20) {
            push(@f, "$webdiskrootdir/$thumbnail.$_");
         }
         unlink @f;
         rename("$webdiskrootdir/$thumbnail.0", "$webdiskrootdir/$thumbnail");
      }
      if (-f "$webdiskrootdir/$thumbnail") {
         utime(ow::tool::untaint($img_atime), ow::tool::untaint($img_mtime), "$webdiskrootdir/$thumbnail");
      }
   }
   return($msg);
}

sub path2thumbnail {
   my @p = split(/\//, $_[0]);
   my $tfile = pop(@p); 
   $tfile =~ s/\.[^\.]*$/\.jpg/i;
   push(@p, '.thumbnail');
   return(join('/',@p) . "/$tfile");
}

sub downloadfiles {	# through zip or tgz
   my ($currentdir, @selitems) = @_;
   my $msg;

   my %selitem;
   foreach (@selitems) {
      my $vpath    = absolute_vpath($currentdir, $_);
      my $vpathstr = f2u($vpath);
      my $err = verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} ($vpathstr: $err)\n";
         next;
      }
      # use relative path to currentdir since we will chdir to webdiskrootdir/currentdir before DL
      my $p = fullpath2vpath("$webdiskrootdir/$vpath", "$webdiskrootdir/$currentdir");
      # use absolute path if relative to webdiskrootdir/currentdir is not possible
      $p = "$webdiskrootdir/$vpath" if ($p eq "");
      $p = ow::tool::untaint($p);

      if (-d "$webdiskrootdir/$vpath" ) {
         $selitem{".$p/"} = 1;
      } elsif (-e _ ) {
         $selitem{".$p"} = 1;
      }
   }
   my @filelist = keys(%selitem);
   return($msg) if ($#filelist < 0);

   my $dlname;
   if ($#filelist == 0) {
      $dlname = safedlname($filelist[0]);
   } else {
      my $localtime = ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
      my @t = ow::datetime::seconds2array($localtime);
      $dlname = sprintf("%4d%02d%02d-%02d%02d", $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1]);
   }

   my @cmd;
   my $zipbin = ow::tool::findbin('zip');
   if ($zipbin ne '') {
      @cmd = ($zipbin, '-ryq', '-');
      $dlname .= ".zip";
   } else {
      my $gzipbin = ow::tool::findbin('gzip');
      my $tarbin = ow::tool::findbin('tar');
      if ($gzipbin ne '') {
         $ENV{'PATH'} = $gzipbin; 
         $ENV{'PATH'} =~ s|/gzip||; # for tar
         @cmd = ($tarbin, '-zcpf', '-');
         $dlname .= ".tgz";
      } else {
         @cmd = ($tarbin, '-cpf', '-');
         $dlname .= ".tar";
      }
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $contenttype = ow::tool::ext2contenttype($dlname);

   local $| = 1;
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;
   if ($ENV{'HTTP_USER_AGENT'} =~ /MSIE 5.5/) {	# ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$dlname"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$dlname"\n|;
   }
   print qq|\n|;

   writelog("webdisk download - ".join(' ', @filelist));
   writehistory("webdisk download - ".join(' ', @filelist));

   # set enviro's for cmd
   $ENV{'USER'} = $ENV{'LOGNAME'} = $user;
   $ENV{'HOME'} = $homedir;
   $< = $>;		# drop ruid by setting ruid = euid
   exec(@cmd, @filelist) or print qq|Error in executing |.join(' ', @cmd, @filelist);
}

sub downloadfile {
   my ($currentdir, $selitem) = @_;

   my $vpath = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);
   my $err = verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY) or
      return("$lang_err{'couldnt_read'} $vpathstr\n");

   my $dlname = safedlname($vpath);
   my $contenttype = ow::tool::ext2contenttype($vpath);
   my $length = (-s "$webdiskrootdir/$vpath");

   # disposition:inline default to open
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;
   if ($contenttype =~ /^text/ || $dlname =~ /\.(jpe?g|gif|png|bmp)$/i) {
      print qq|Content-Disposition: inline; filename="$dlname"\n|;
   } else {
      if ($ENV{'HTTP_USER_AGENT'} =~ /MSIE 5.5/ ) { # ie5.5 is broken with content-disposition: attachment
         print qq|Content-Disposition: filename="$dlname"\n|;
      } else {
         print qq|Content-Disposition: attachment; filename="$dlname"\n|;
      }
   }

   if ($contenttype =~ /^text/ && $length > 512 
         && is_http_compression_enabled()) {
      my $content;
      local $/; 
      undef $/; 
      $content=<F>; # no separator, read whole file at once
      close(F);
      $content = Compress::Zlib::memGzip($content);
      $length = length($content);
      print qq|Content-Encoding: gzip\n|,
            qq|Vary: Accept-Encoding\n|,
            qq|Content-Length: $length\n\n|, $content;
   } else {
      print qq|Content-Length: $length\n\n|;
      my $buff;
      while (read(F, $buff, 32768)) {
         print $buff;
      }
      close(F);
   }

   # we only log download other than thumbnail imgs
   my @p = split(/\//, $vpath);
   if (!defined $p[$#p-1] || $p[$#p-1] ne '.thumbnail') {
      writelog("webdisk download - $vpath");
      writehistory("webdisk download - $vpath ");
   }
   return;
}

########## PREVIEWFILE ###########################################
# relative links in html content will be converted so they can be
# redirect back to openwebmail-webdisk.pl with correct parmteters
sub previewfile {
   my ($currentdir, $selitem, $filecontent)=@_;
   my $vpath    = absolute_vpath($currentdir, $selitem);
   my $vpathstr = f2u($vpath);
   my $err = verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   if ($filecontent eq "") {
      sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY) or return("$lang_err{'couldnt_read'} $vpath\n");
      local $/; undef $/; $filecontent=<F>; # no separator, read whole file at once
      close(F);
   }

   # remove path from filename
   my $dlname = safedlname($vpath);
   my $contenttype = ow::tool::ext2contenttype($vpath);
   if ($vpath =~ /\.(?:html?|js)$/i) {
      # use the dir where this html is as new currentdir
      my @p = path2array($vpath); pop @p;
      my $newdir = '/' . join('/', @p);
      my $escapednewdir = ow::tool::escapeURL($newdir);
      my $preview_url = qq|$config{'ow_cgiurl'}/openwebmail-webdisk.pl?sessionid=$thissession|.
                        qq|&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid|.
                        qq|&amp;currentdir=$escapednewdir&amp;action=preview&amp;selitems=|;
      $filecontent =~ s/\r\n/\n/g;
      $filecontent = linkconv($filecontent, $preview_url);
   }

   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|,
         qq|Content-Disposition: inline; filename="$dlname"\n|;

   my $length = length($filecontent);	# calc length since linkconv may change data length
   if ($contenttype =~ /^text/ && $length>512
        && is_http_compression_enabled()) {
      $filecontent = Compress::Zlib::memGzip($filecontent);
      $length = length($filecontent);
      print qq|Content-Encoding: gzip\n|,
            qq|Vary: Accept-Encoding\n|,
            qq|Content-Length: $length\n\n|;
   } else {
      print qq|Content-Length: $length\n\n|;
   }
   print $filecontent;
   return;
}

sub linkconv {
   my ($html, $preview_url) = @_;
   $html =~ s/( url| href| src| stylesrc| background)(="?)([^\<\>\s]+?)("?[>\s+])/_linkconv($1.$2, $3, $4, $preview_url)/igems;
   $html =~ s/(window.open\()([^\<\>\s]+?)(\))/_linkconv2($1, $2, $3, $preview_url)/igems;
   return($html);
}

sub _linkconv {
   my ($prefix, $link, $postfix, $preview_url) = @_;
   if ($link =~ m!^(?:mailto:|javascript:|#)!i) {
      return($prefix.$link.$postfix);
   }
   if ($link !~ m!^http://!i && $link!~m!^/!) {
       $link = $preview_url.$link;
   }
   return($prefix.$link.$postfix);
}
sub _linkconv2 {
   my ($prefix, $link, $postfix, $preview_url)=@_;
   if ($link =~ m!^'?(?:http://|/)!i) {
      return($prefix.$link.$postfix);
   }
   $link = qq|'$preview_url'.$link|;
   return($prefix.$link.$postfix);
}
########## END PREVIEWFILE #######################################

########## UPLOADFILE ############################################
sub uploadfile {
   no strict 'refs';	# for $upload, which is fname and fhandle of the upload
   my ($currentdir, $upload) = @_;

   my $size = (-s $upload);
   if (!is_quota_available($size/1024)) {
      return("$lang_err{'quotahit_alert'}\n");
   }
   if ($config{'webdisk_uploadlimit'} &&
       $size/1024>$config{'webdisk_uploadlimit'} ) {
      return ("$lang_err{'upload_overlimit'} $config{'webdisk_uploadlimit'} $lang_sizes{'kb'}\n");
   }

   my ($fname, $wgethandle);
   if ($upload =~ m!^(https?|ftp)://!) {
      my $wgetbin = ow::tool::findbin('wget');
      return("$lang_text{'program'} wget $lang_err{'doesnt_exist'}\n") if ($wgetbin eq '');

      my ($ret, $errmsg, $contenttype);
      ($ret, $errmsg, $contenttype, $wgethandle)=ow::wget::get_handle($wgetbin, $upload);
      return("$lang_wdbutton{'upload'} $upload $lang_text{'failed'}\n($errmsg)") if ($ret<0);

      my $ext = ow::tool::contenttype2ext($contenttype);
      $fname = $upload;				# url
      $fname = ow::tool::unescapeURL($fname);	# unescape str in url
      $fname =~ s/\?.*$//;			# clean cgi parm in url
      $fname =~ s!/$!!; $fname =~ s|^.*/||;	# clear path in url
      $fname .= ".$ext" if ($fname!~/\.$ext$/ && $ext ne 'bin');

   } else {
      if ($size == 0) {
         return("$lang_wdbutton{'upload'} $lang_text{'failed'} (filesize is zero)\n");
      }
      $fname = $upload;
      # Convert :: back to the ' like it should be.
      $fname =~ s/::/'/g;
      # Trim the path info from the filename
      if ($prefs{'charset'} eq 'big5' || $prefs{'charset'} eq 'gb2312') {
         $fname = ow::tool::zh_dospath2fname($fname);	# dos path
      } else {
         $fname =~ s|^.*\\||;	# dos path
      }
      $fname =~ s|^.*/||;	# unix path
      $fname =~ s|^.*:||;	# mac path and dos drive
      $fname = u2f($fname);	# prefscharset to fscharset
   }

   my $vpath = ow::tool::untaint(absolute_vpath($currentdir, $fname));
   my $vpathstr = f2u($vpath);
   my $err = verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   ow::tool::rotatefilename("$webdiskrootdir/$vpath") if ( -f "$webdiskrootdir/$vpath");
   sysopen(UPLOAD, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT) or
      return("$lang_wdbutton{'upload'} $vpathstr $lang_text{'failed'} ($!)\n");
   my $buff;
   if (defined $wgethandle) {
      while (read($wgethandle, $buff, 32768)) {
         print UPLOAD $buff;
      }
      close($wgethandle);
   } else {
      while (read($upload, $buff, 32768)) {
         print UPLOAD $buff;
      }
      close($upload);
   }
   close(UPLOAD);

   writelog("webdisk upload - $vpath");
   writehistory("webdisk upload - $vpath");
   return("$lang_wdbutton{'upload'} $vpathstr $lang_text{'succeeded'}\n");
}

sub sortfiles {
   my ($filesort, $r_ftype, $r_fsize, $r_fdate, $r_fperm) = @_;
   my @sortedlist;
   if ($filesort eq "name_rev") {
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $b cmp $a} keys(%{$r_ftype})
   } elsif ($filesort eq "size") {
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $r_fsize->{$a} <=> $r_fsize->{$b}} keys(%{$r_ftype})
   } elsif ($filesort eq "size_rev") {
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $r_fsize->{$b} <=> $r_fsize->{$a}} keys(%{$r_ftype})
   } elsif ($filesort eq "time") {
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $r_fdate->{$a} <=> $r_fdate->{$b}} keys(%{$r_ftype})
   } elsif ($filesort eq "time_rev") {
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $r_fdate->{$b} <=> $r_fdate->{$a}} keys(%{$r_ftype})
   } elsif ($filesort eq "perm") {
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $r_fperm->{$a} cmp $r_fperm->{$b}} keys(%{$r_ftype})
   } elsif ($filesort eq "perm_rev") {
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $r_fperm->{$b} cmp $r_fperm->{$a}} keys(%{$r_ftype})
   } else { # filesort = name
      @sortedlist = sort {$r_ftype->{$a} cmp $r_ftype->{$b} || $r_ftype->{$a} cmp $r_ftype->{$b} || $a cmp $b} keys(%{$r_ftype})
   }
   return @sortedlist;
}

sub mkpathloop {
   my ($currentdir, $page, $filesort, $caller_showdir) = @_;
   my $showthumbnail =  param('showthumbnail') || 0;
   my $showhidden    =  param('showhidden')    || 0;
   my $singlepage    =  param('singlepage')    || 0;
   my @pathloop;
   my $p = '';
   foreach ('', grep(!/^$/, split(/\//, $currentdir))) {
      $p .= "$_/";
      my $tmp = {
                            # standard params
                            url_cgi             => $config{ow_cgiurl},
                            folder              => $folder,
                            sessionid           => $thissession,
                            message_id          => $messageid,

                            # pathloop
                            dir                 => $p,
                            dirstr              => f2u("$_/"),
                            page                => $page,
                            currentdir          => $currentdir,
                            filesort            => $filesort,
                            showhidden          => $showhidden,
                            singlepage          => $singlepage,
             };
      if ($caller_showdir)
      {
         $tmp->{'showthumbnail'} = $showthumbnail;
      } else {
         $tmp->{'action'}     = $action;
         if ($action eq 'sel_saveattfile') {
            $tmp->{$action}                = 1;
            $tmp->{'attname'}              = param('attname') || '';
            $tmp->{'attfile'}              = param('attfile')  || '';
         } elsif ($action eq 'sel_saveattachment') {
            $tmp->{$action}                = 1;
            $tmp->{'attname'}              = param('attname') || '';
            $tmp->{'attachment_nodeid'}    = param('attachment_nodeid');
            $tmp->{'convfrom'}             = param('convfrom') || '';
         }
      }
      push (@pathloop, $tmp);
   }
   return @pathloop;
}

sub mkheadersloop {
   my ($currentdir, $page, $filesort, $keyword, $caller_showdir) = @_;
   my $showthumbnail =  param('showthumbnail') || 0;
   my $showhidden    =  param('showhidden')    || 0;
   my $singlepage    =  param('singlepage')    || 0;
   my $searchtype    =  param('searchtype')    || '';
   my @headersloop;
   my @headers = qw{name size time};
   push(@headers, 'perm') if ($caller_showdir);
   foreach (@headers) {
      my $revsort = $filesort eq $_ . "_rev" ? 1 : 0;
      my $tmp = {
                      # standard params
                      url_cgi             => $config{ow_cgiurl},
                      url_html            => $config{ow_htmlurl},
                      folder              => $folder,
                      iconset             => $prefs{iconset},
                      sessionid           => $thissession,
                      message_id          => $messageid,
                      # headersloop
                      $_."header"         => 1,
                      revsort             => $revsort,
                      fwdsort             => $filesort eq $_ ? 1 : 0,
                      newfilesort         => $revsort ? $_ : ($_ . "_rev"),
                      currentdir          => $currentdir,
                      page                => $page,
                      singlepage          => $singlepage,
         };
      if ($caller_showdir) {
         $tmp->{'showthumbnail'} = $showthumbnail;
         $tmp->{'keyword'}       = $keyword;
         $tmp->{'searchtype'}    = $searchtype;
         $tmp->{'showthumbnail'} = $showthumbnail;
      }
      push (@headersloop, $tmp);
   }
   return @headersloop;
}

sub mkpagelinksloop {
   my ($currentdir, $page, $filesort, $totalpage, $caller_showdir) = @_;
   my $showthumbnail =  param('showthumbnail') || 0;
   my $showhidden    =  param('showhidden')    || 0;
   my $singlepage    =  param('singlepage')    || 0;
   my @pagelinksloop;
   if (!$singlepage) {
      my $p_first = $page - 4;
      $p_first = 1 if ($p_first < 1);
      my $p_last = $p_first + 9;
      if ($p_last > $totalpage) {
         $p_last = $totalpage;
         while ($p_last - $p_first < 9 && $p_first > 1) {
            $p_first--;
         }
      }
      for my $i ($p_first..$p_last) {
         my $tmp = {
                      # standard params
                      url_cgi             => $config{ow_cgiurl},
                      sessionid           => $thissession,
                      message_id          => $messageid,
                      folder              => $folder,

                      # pagelinksloop 
                      currentdir          => $currentdir,
                      showhidden          => $showhidden,
                      pagenr              => $i,
                      thispage            => $i == $page,
            };
      if ($caller_showdir) {
         $tmp->{'showthumbnail'} = $showthumbnail,
         $tmp->{'filesort'}      = $filesort,
      } else {
         $tmp->{'action'}     = $action;
         if ($action eq 'sel_saveattfile') {
            $tmp->{$action}                = 1;
            $tmp->{'attname'}              = param('attname') || '';
            $tmp->{'attfile'}              = param('attfile')  || '';
         } elsif ($action eq 'sel_saveattachment') {
            $tmp->{$action}                = 1;
            $tmp->{'attname'}              = param('attname') || '';
            $tmp->{'attachment_nodeid'}    = param('attachment_nodeid');
            $tmp->{'convfrom'}             = param('convfrom') || '';
         }
      }
      push (@pagelinksloop, $tmp);
      }
   }
   return @pagelinksloop;
}

sub dirfilesel {
   my ($action, $olddir, $newdir, $filesort, $page) = @_;
   my $showhidden        = param('showhidden') || 0;
   my $singlepage        = param('singlepage') || 0;

   # for sel_saveattfile, used in compose to save attfile
   my $attfile           = param('attfile')  || '';
   my $attachment_nodeid = param('attachment_nodeid');
   my $convfrom          = param('convfrom') || '';

   # attname is from compose or readmessage, its charset may be different than prefs{charset}
   my $attnamecharset    = param('attnamecharset') || $prefs{'charset'};
   my $attname           = param('attname') || ''; 
   $attname              = (iconv($attnamecharset, $prefs{'charset'}, $attname))[0];

   if ($action eq "sel_saveattfile" && $attfile eq "") {
      autoclosewindow($lang_text{'savefile'}, $lang_err{'param_fmterr'});
   } elsif ($action eq "sel_saveattachment" && $attachment_nodeid eq "") {
      autoclosewindow($lang_text{'savefile'}, $lang_err{'param_fmterr'});
   }

   my ($currentdir, $msg);
   foreach my $dir ($newdir, $olddir, "/") {
      my $err = verify_vpath($webdiskrootdir, $dir);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} (" . f2u($dir) . ": $err)<br>\n"; 
         next;
      }
      if (!opendir(D, "$webdiskrootdir/$dir")) {
         $msg .= "$lang_err{'couldnt_read'} " . f2u($dir) . " ($!)<br>\n"; 
         next;
      }
      $currentdir = $dir; 
      last;
   }
   openwebmailerror(__FILE__, __LINE__, $msg) if ($currentdir eq '');

   my (%fsize, %fdate, %ftype, %flink);
   while(my $filename = readdir(D)) {
      next if ($filename eq "." 
             || $filename eq "..");
      next if ((!$config{'webdisk_lshidden'} || !$showhidden) 
                  && $filename =~ /^\./ );
      if (!$config{'webdisk_lsmailfolder'}) {
          next if (is_under_dotdir_or_folderdir("$webdiskrootdir/$currentdir/$filename"));
      }
      if (-l "$webdiskrootdir/$currentdir/$filename") {	# symbolic link, aka:shortcut
         next if (!$config{'webdisk_lssymlink'});
         my $realpath = readlink("$webdiskrootdir/$currentdir/$filename");
         $realpath    = "$webdiskrootdir/$currentdir/$realpath" if ($realpath !~ m!^/!);
         my $vpath    = fullpath2vpath($realpath, $webdiskrootdir);
         if ($vpath ne '') {
            $flink{$filename} = " -> $vpath";
         } else {
            next if (!$config{'webdisk_allow_symlinkout'});
            if ($config{'webdisk_symlinkout_display'} eq 'path') {
               $flink{$filename} = " -> sys::$realpath";
            } elsif ($config{'webdisk_symlinkout_display'} eq '@') {
               $flink{$filename} = '@';
            } else {
               $flink{$filename} = '';
            }
         }
      }

      my ($st_dev,   $st_ino,   $st_mode,  $st_nlink,
          $st_uid,   $st_gid,   $st_rdev,  $st_size,
          $st_atime, $st_mtime, $st_ctime, $st_blksize,
          $st_blocks) = stat("$webdiskrootdir/$currentdir/$filename");

      if (($st_mode & 0170000) == 0040000) {
         $ftype{$filename} = "d";
      } elsif (($st_mode & 0170000) == 0100000) {
         $ftype{$filename} = "f";
      } else {	# unix specific filetype: fifo, socket, block dev, char dev..
         next;  # skip because dirfilesel is used for upload/download
      }
      $fsize{$filename} = $st_size;
      $fdate{$filename} = $st_mtime;
   }
   closedir(D);

   my %dummy = ();
   my @sortedlist = sortfiles($filesort, \%ftype, \%fsize, \%fdate, \%dummy);

   my $totalpage = int(($#sortedlist + 1) / 10 + 0.999999); # use 10 instead of $prefs{'webdisk_dirnumitems'} for shorter page
   $totalpage = 1 if ($totalpage == 0);
   if ($currentdir ne $olddir) {
      $page = 1;	# reset page number if change to new dir
   } else {
      $page = 1 if ($page < 1);
      $page = $totalpage if ($page > $totalpage);
   }
    
   my @pathloop = mkpathloop($currentdir, $page, $filesort, 0);

   my @headersloop = mkheadersloop($currentdir, $page, $filesort, '', 0);

   my $filesloop = [];

   if ($#sortedlist >= 0) {
      my $os = $^O || 'generic';
      my ($i_first, $i_last) = (0, $#sortedlist);
      if (!$singlepage) {
         $i_first  = ($page - 1) * 10; # use 10 instead of $prefs{'webdisk_dirnumitems'} for shorter page
         $i_last   = $i_first + 9;
         $i_last   = $#sortedlist if ($i_last > $#sortedlist);
      }
      foreach my $i ($i_first .. $i_last) {
         my $filename = $sortedlist[$i];
         my $vpath = absolute_vpath($currentdir, $filename);
         my $vpathstr = f2u($vpath);
         my $is_txt = ($ftype{$filename} eq 'd') ? 0 
                      : (-T "$webdiskrootdir/$currentdir/$filename" || $filename =~ /\.(txt|html?)$/i);
         my $ficon = ($prefs{'iconset'} =~ /^Text\./) ? '' 
                      : findicon($filename, $ftype{$filename}, $is_txt, $os);
         my $datestr = '';
         if (defined $fdate{$filename}) {
            $datestr = ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial($fdate{$filename}),
                                      $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                      $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'});
         }

         push (@{$filesloop}, {
                      # standard params
                      url_html            => $config{ow_htmlurl},
                      url_cgi             => $config{ow_cgiurl},
                      folder              => $folder,
                      sessionid           => $thissession,
                      message_id          => $messageid,

                      # filesloop
                      $action             => 1,
                      action              => $action,
                      uselightbar         => $prefs{'uselightbar'},
                      attfile             => $attfile,
                      attname             => $attname,
                      attachment_nodeid   => $attachment_nodeid,
                      convfrom            => $convfrom,
                      odd                 => $i % 2,
                      page                => $page,
                      currentdir          => $currentdir,
                      filesort            => $filesort,
                      showhidden          => $showhidden,
                      singlepage          => $singlepage,
                      isdir               => $ftype{$filename} eq "d",
                      filename            => $filename,
                      vpath               => $vpath,
                      vpathstr            => $vpathstr,
                      accesskeynr         => ($i + 1) % 10,
                      ficon               => $ficon,
                      filenamestr         => f2u($filename),
                      flinkstr            => defined($flink{$filename}) ? f2u($flink{$filename}) : '',
                      datestr             => $datestr,
                      fsizestr            => lenstr($fsize{$filename},1),
                      fsize               => $fsize{$filename},
            });
      }
   }

   my @pagelinksloop = mkpagelinksloop($currentdir, $page, $filesort, $totalpage, 0);

   my $defaultname = "";

   if ($action eq "sel_saveattfile" 
       || $action eq "sel_saveattachment") {
      $defaultname = f2u(absolute_vpath($currentdir, u2f($attname)));
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_dirfilesel.tmpl"),
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
                      sessionid           => $thissession,
                      message_id          => $messageid,
                      url_html            => $config{ow_htmlurl},
                      url_cgi             => $config{ow_cgiurl},
                      folder              => $folder,
                      use_texticon        => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                      iconset             => $prefs{iconset},

                      # webdisk_dirfilesel.tmpl
                      $action             => 1,
                      action              => $action,
                      currentdir          => $currentdir,
                      parentdir           => absolute_vpath($currentdir, ".."),
                      gotodir             => $gotodir,
                      isroot              => $currentdir eq '/',
                      page                => $page,
                      attfile             => $attfile,
                      attname             => $attname,
                      attachment_nodeid   => $attachment_nodeid,
                      convfrom            => $convfrom,
                      filesort            => $filesort,
                      enablehidden        => $config{'webdisk_lshidden'},
                      showhidden          => $showhidden,
                      singlepage          => $singlepage,
                      pathloop            => \@pathloop,
                      headersloop         => \@headersloop,
                      filesloop           => $filesloop,
                      pagelinksloop       => \@pagelinksloop,
                      prevpage            => ($page > 1) ? $page - 1 : '',
                      nextpage            => ($page < $totalpage) ? $page + 1 : '',
                      is_right_to_left    => $ow::lang::RTL{$prefs{'locale'}},
                      defaultname         => $defaultname,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   my $cookie = cookie( -name  => "ow-currentdir-$domain-$user",
                        -value => $currentdir,
                        -path  => '/');

   httpprint([-cookie   => $cookie], 
             [$template->output]);
   return;
}

sub showdir {
   my ($olddir, $newdir, $filesort, $page, $msg) = @_;
   my $searchtype    =  param('searchtype')    || '';
   my $showthumbnail =  param('showthumbnail') || 0;
   my $showhidden    =  param('showhidden')    || 0;
   my $singlepage    =  param('singlepage')    || 0;
   my $keyword       =  param('keyword')       || ''; 
   $keyword          =~ s/[`;\|]//g;

   my ($quotadellimit, $quotausagestr, $peroverquota) = ('', '', '');
   if (  $quotalimit > 0 
      && $quotausage > $quotalimit 
      && ($config{'delmail_ifquotahit'}
         || $config{'delfile_ifquotahit'})) {

      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      if ($quotausage > $quotalimit) {
         my (@validfolders, $inboxusage, $folderusage);
         getfolders(\@validfolders, \$inboxusage, \$folderusage);
         if (  $config{'delfile_ifquotahit'} 
            && $folderusage < $quotausage * 0.5) {

            $quotadellimit = $config{'quota_limit'};
            my $webdiskrootdir = $homedir.absolute_vpath("/", $config{'webdisk_rootpath'});
            cutdirfiles(($quotausage - $quotalimit * 0.9) * 1024, $webdiskrootdir);

            $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
         }
      }
   }

   if ($config{'quota_module'} ne "none") {
      my $overthreshold = ($quotalimit > 0 && $quotausage / $quotalimit > $config{'quota_threshold'} / 100);
      if ($config{'quota_threshold'} == 0 
         || $overthreshold) {
         $quotausagestr = lenstr($quotausage * 1024, 1);
      }
      if ($overthreshold) {
         $peroverquota = int($quotausage * 1000 / $quotalimit) / 10;
      }
   } 

   my ($currentdir, @list);
   if ($keyword ne '') {	# olddir = newdir if keyword is supplied for searching
      my $err = filelist_of_search($searchtype, $keyword, $olddir, dotpath('webdisk.cache'), \@list);
      if ($err) {
         $keyword = ""; 
         $msg .= $err;
      } else {
         $currentdir = $olddir;
      }
   }
   if ($keyword eq '') {
      foreach my $dir ($newdir, $olddir, "/") {
         my $err = verify_vpath($webdiskrootdir, $dir);
         if ($err) {
            $msg .= "$lang_err{'access_denied'} (".f2u($dir).": $err)\n"; 
            next;
         }
         if (!opendir(D, "$webdiskrootdir/$dir")) {
            $msg .= "$lang_err{'couldnt_read'} ".f2u($dir)." ($!)\n"; 
            next;
         }
         @list = readdir(D);
         closedir(D);
         $currentdir = $dir;
         last;
      }
      openwebmailerror(__FILE__, __LINE__, $msg) if ($currentdir eq '');
   }

   my (%fsize, %fdate, %fowner, %fmode, %fperm, %ftype, %flink);
   my ($dcount, $fcount, $sizecount) = (0, 0, 0);
   foreach my $filename (@list) {
      next if ( $filename eq "." 
             || $filename eq "..");
      my $vpath = absolute_vpath($currentdir, $filename);
      if (!$config{'webdisk_lsmailfolder'}) {
          next if (is_under_dotdir_or_folderdir("$webdiskrootdir/$vpath"));
      }
      my $fname = $vpath; 
      $fname =~ s|.*/||;
      next if ((!$config{'webdisk_lshidden'} || !$showhidden) 
                && $fname =~ /^\./ );
      if (-l "$webdiskrootdir/$vpath") {	# symbolic link, aka:shortcut
         next if (!$config{'webdisk_lssymlink'});
         my $realpath = readlink("$webdiskrootdir/$vpath");
         $realpath    = "$webdiskrootdir/$vpath/../$realpath" if ($realpath !~ m!^/!);
         my $vpath2   = fullpath2vpath($realpath, $webdiskrootdir);
         if (defined $vpath2 && $vpath2 ne '') {
            $flink{$filename} = " -> $vpath2";
         } else {
            next if (!$config{'webdisk_allow_symlinkout'});
            if ($config{'webdisk_symlinkout_display'} eq 'path') {
               $flink{$filename} = " -> sys::$realpath";
            } elsif ($config{'webdisk_symlinkout_display'} eq '@') {
               $flink{$filename} = '@';
            } else {
               $flink{$filename} = '';
            }
         }
      }
      my ($st_dev,   $st_ino,   $st_mode,  $st_nlink,
          $st_uid,   $st_gid,   $st_rdev,  $st_size,
          $st_atime, $st_mtime, $st_ctime, $st_blksize,
          $st_blocks) = stat("$webdiskrootdir/$vpath");

      if (($st_mode & 0170000) == 0040000) {
         $ftype{$filename} = "d"; 
         $dcount++;
      } elsif (($st_mode & 0170000) == 0100000) {
         $ftype{$filename} = "f"; 
         $fcount++; 
         $sizecount += $st_size;
      } else {	# unix specific filetype: fifo, socket, block dev, char dev..
         next if (!$config{'webdisk_lsunixspec'});
         $ftype{$fname} = "u";
      }
      my $r = (-r _) ? 'r' : '-';
      my $w = (-w _) ? 'w' : '-';
      my $x = (-x _) ? 'x' : '-';
      $fperm{$filename}  = "$r$w$x";
      $fsize{$filename}  = $st_size;
      $fdate{$filename}  = $st_mtime;
      $fowner{$filename} = (getpwuid($st_uid)?getpwuid($st_uid):$st_uid) . ':' . (getgrgid($st_gid)?getgrgid($st_gid):$st_gid);
      $fmode{$filename}  = sprintf("%04o", $st_mode & 07777);
   }
   close(D);

   my @sortedlist = sortfiles($filesort, \%ftype, \%fsize, \%fdate, \%fperm);

   my $totalpage = int(($#sortedlist + 1) / ($prefs{'webdisk_dirnumitems'} || 10) + 0.999999);
   $totalpage = 1 if ($totalpage == 0);
   if ($currentdir ne $olddir) {
      $page = 1;	# reset page number if change to new dir
   } else {
      $page = 1 if ($page < 1);
      $page = $totalpage if ($page > $totalpage);
   }

   my @pathloop = mkpathloop($currentdir, $page, $filesort, 1);
   
   my @headersloop = mkheadersloop($currentdir, $page, $filesort, $keyword, 1);

   my $canwrite = (!$config{'webdisk_readonly'} &&
                    (!$quotalimit || $quotausage < $quotalimit));
   my $filesloop = [];
   if ($#sortedlist >= 0) {
      my $os = $^O || 'generic';
      my ($i_first, $i_last) = (0, $#sortedlist);
      if (!$singlepage) {
         $i_first  = ($page - 1) * $prefs{'webdisk_dirnumitems'};
         $i_last   = $i_first + $prefs{'webdisk_dirnumitems'} - 1;
         $i_last   = $#sortedlist if ($i_last > $#sortedlist);
      }
      foreach my $i ($i_first .. $i_last) {
         my $filename = $sortedlist[$i];
         my $is_txt = ($ftype{$filename} eq 'd') ? 0 
                      : (-T "$webdiskrootdir/$currentdir/$filename" || $filename =~ /\.(txt|html?)$/i);
         my $ficon = ($prefs{'iconset'} =~ /^Text\./) ? '' 
                      : findicon($filename, $ftype{$filename}, $is_txt, $os);
         my ($dname, $fname, $dnamestr) = ('', '', '');
         my ($mkpspdf, $mkps, $preview, $editfile, $listarchive, 
             $wordpreview, $candeflate, $thumbnail, $archive) = 
            ('', '', '', '', '', '', '', '', ''); 
         if ($ftype{$filename} ne 'd') {
            if ($filename =~ m|^(.*/)([^/]*)$|) {
               ($dname, $fname) = ($1, $2);
               $dnamestr = f2u($dname);
            } else {
               ($dname, $fname) = ('', $filename);
            }
            $preview = 1 if ($is_txt && $filename =~ m/\.html?$/i);
            if ($filename =~ m/\.(?:zip|rar|arj|ace|lzh|t[bg]z|tar\.g?z|tar\.bz2?|tne?f)$/i) {
               $archive = 1;
               $listarchive = $config{'webdisk_allow_listarchive'};
            } elsif ($filename =~ /\.(?:doc|dot)$/i) {
               $wordpreview = 1;
            } elsif ($showthumbnail && $filename =~ /\.(?:jpe?g|gif|png|bmp|tif)$/i) {
               if ($fsize{$filename} < 2048) {
                  $thumbnail = $filename;	# show image itself if size <2k
               } else {
                  $thumbnail = path2thumbnail($filename);
                  $thumbnail = '' unless (-f "$webdiskrootdir/$currentdir/$thumbnail");
               }
            }
            if ($canwrite) {
               if ($filename =~ m/\.pdf$/i) {
                  $mkpspdf = 'mkps';
                  $mkps = 1;
               } elsif ($filename =~ m/\.e?ps$/i) {
                  $mkpspdf = 'mkpdf';
               } elsif ($is_txt) {
                  $editfile = 1;
               } elsif ($archive && 
                        (  $filename =~ /\.(?:t[bg]z|tar\.g?z)$/i && $config{'webdisk_allow_untar'} && $config{'webdisk_allow_ungzip'}
                        || $filename =~ /\.(?:tar\.bz2?)$/i && $config{'webdisk_allow_untar'} && $config{'webdisk_allow_unbzip2'} 
                        || $filename =~ /\.zip$/i && $config{'webdisk_allow_unzip'} 
                        || $filename =~ /\.rar$/i && $config{'webdisk_allow_unrar'} 
                        || $filename =~ /\.arj$/i && $config{'webdisk_allow_unarj'} 
                        || $filename =~ /\.ace$/i && $config{'webdisk_allow_unace'} 
                        || $filename =~ /\.tar$/i && $config{'webdisk_allow_untar'} 
                        || $filename =~ /\.lzh$/i && $config{'webdisk_allow_unlzh'}
                        )
                       || $filename =~ /\.(?:bz2?)$/i && $config{'webdisk_allow_unbzip2'}
                       || $filename =~ /\.(?:g?z?)$/i && $config{'webdisk_allow_ungzip'}
                       ) {
                  $candeflate = 1;
               } 
            }

         }
         my $datestr = '';
         if (defined $fdate{$filename}) {
            $datestr = ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial($fdate{$filename}),
                                      $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                      $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'});
         }
         $fperm{$filename}  =~ /^(.)(.)(.)$/;
         my $permstr = "$1 $2 $3";
         push (@{$filesloop}, {
                      # standard params
                      url_html            => $config{ow_htmlurl},
                      url_cgi             => $config{ow_cgiurl},
                      folder              => $folder,
                      sessionid           => $thissession,
                      message_id          => $messageid,

                      # filesloop
                      uselightbar         => $prefs{'uselightbar'},
                      odd                 => $i % 2,
                      page                => $page,
                      currentdir          => $currentdir,
                      filesort            => $filesort,
                      showthumbnail       => $showthumbnail,
                      showhidden          => $showhidden,
                      singlepage          => $singlepage,
                      filenumber          => $i,
                      isdir               => $ftype{$filename} eq "d",
                      filename            => $filename,
                      fname               => $fname,
                      fnamestr            => f2u($fname),
                      dname               => $dname,
                      dnamestr            => $dnamestr,
                      ownerstr            => $fowner{$filename},
                      accesskeynr         => ($i + 1) % 10,
                      ficon               => $ficon,
                      filenamestr         => f2u($filename),
                      flinkstr            => defined($flink{$filename}) ? f2u($flink{$filename}) : '',
                      blank               => ($is_txt || $filename =~ /\.(?:jpe?g|gif|png|bmp)$/i) ? 1 : 0,
                      withconfirm         => $prefs{'webdisk_confirmcompress'} ? 1 : 0,
                      mkpspdf             => $mkpspdf,
                      mkps                => $mkps,
                      preview             => $preview,
                      editfile            => $editfile,
                      listarchive         => $listarchive,
                      wordpreview         => $wordpreview,
                      candeflate          => $candeflate,
                      thumbnail           => $thumbnail,
                      archive             => $archive,
                      fmode               => $fmode{$filename},
                      fperm               => $permstr,
                      datestr             => $datestr,
                      fsizestr            => lenstr($fsize{$filename},1),
                      fsize               => $fsize{$filename},
            });
      }
   }
   # release mem if possible
   undef(%fsize); 
   undef(%fdate); 
   undef(%fperm); 
   undef(%ftype); 
   undef(%flink);	

   my @pagelinksloop = mkpagelinksloop($currentdir, $page, $filesort, $totalpage, 1);

   if ($quotalimit > 0 && $quotausage >= $quotalimit) {
      $msg .= "$lang_err{'quotahit_alert'}\n";
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("webdisk_showdir.tmpl"),
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
                      use_texticon        => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                      url_html            => $config{ow_htmlurl},
                      url_cgi             => $config{ow_cgiurl},
                      iconset             => $prefs{iconset},
                      sessionid           => $thissession,
                      message_id          => $messageid,
                      folder              => $folder,
                      folderstr           => $lang_folders{$folder} || f2u($folder),

                      # webdisk_showdir.tmpl
                      currentdir          => $currentdir,
                      isroot              => $currentdir eq '/',
                      parentdir           => absolute_vpath($currentdir, ".."),
                      filesort            => $filesort,
                      gotodir             => $gotodir,
                      page                => $page,
                      prevpage            => ($page > 1) ? $page - 1 : '',
                      nextpage            => ($page < $totalpage) ? $page + 1 : '',
                      is_right_to_left    => $ow::lang::RTL{$prefs{'locale'}},
                      quotausage          => $quotausagestr,
                      peroverquota        => $peroverquota,
                      allowthumbnails     => $config{'webdisk_allow_thumbnail'},
                      showthumbnail       => $showthumbnail,
                      enablehidden        => $config{'webdisk_lshidden'},
                      showhidden          => $showhidden,
                      keyword             => $keyword,
                      singlepage          => $singlepage,
                      enable_webmail      => $config{'enable_webmail'},
                      enable_addressbook  => $config{enable_addressbook},
                      enable_calendar     => $config{enable_calendar},
                      calendardefaultview => $prefs{calendar_defaultview},
                      enable_preference   => $config{enable_preference},
                      enable_sshterm      => $config{enable_sshterm},
                      use_ssh1            => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar" ? 1 : 0,
                      use_ssh2            => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar" ? 1 : 0,
                      pathloop            => \@pathloop,
                      headersloop         => \@headersloop,
                      filesloop           => $filesloop,
                      dcount              => $dcount,
                      fcount              => $fcount,
                      totsize             => lenstr($sizecount, 1),
                      pagelinksloop       => \@pagelinksloop,
                      canwrite            => $canwrite,
                      notreadonly         => !$config{'webdisk_readonly'},
                      underquota          => (!$quotalimit || $quotausage < $quotalimit),
                      cansymlink          => ($config{'webdisk_allow_symlinkcreate'} && $config{'webdisk_lssymlink'}),
                      canchmod            => $config{'webdisk_allow_chmod'},
                      cangzip             => $config{'webdisk_allow_gzip'},
                      canzip              => $config{'webdisk_allow_zip'},
                      cantargz            => ($config{'webdisk_allow_tar'} && $config{'webdisk_allow_gzip'}),
                      cantar              => $config{'webdisk_allow_tar'},
                      canthumb            => $config{'webdisk_allow_thumbnail'},
                      popup_quotadellimit => $quotadellimit,
                      charset             => $prefs{'charset'},
                      msg                 => $msg,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   my $cookie = cookie( -name  => "ow-currentdir-$domain-$user",
                        -value => $currentdir,
                        -path  => '/');
   httpprint([-cookie   => $cookie,
              -Refresh  => ($prefs{refreshinterval} * 60) . 
                           ";URL=openwebmail-webdisk.pl?action=showdir&session_noupdate=1&" .
                           join ("&", (
                                 "currentdir="    . ow::tool::escapeURL($currentdir),
                                 "sessionid="     . ow::tool::escapeURL($thissession),
                                 "folder="        . ow::tool::escapeURL($folder),
                                 "message_id="    . ow::tool::escapeURL($messageid),
                                 "gotodir="       . ow::tool::escapeURL($currentdir),
                                 "keyword="       . ow::tool::escapeURL($keyword),
                                 "showthumbnail=" . $showthumbnail,
                                 "showhidden="    . $showhidden,
                                 "singlepage="    . $singlepage,
                                 "filesort="      . $filesort,
                                 "page="          . $page,
                                 "searchtype="    . $searchtype))
             ], [$template->output]);

   return;
}

sub filelist_of_search {
   my ($searchtype, $keyword, $vpath, $cachefile, $r_list)=@_;
   my $keyword_fs   = (iconv($prefs{'charset'}, $prefs{'fscharset'}, $keyword))[0];
   my $keyword_utf8 = (iconv($prefs{'charset'}, 'utf-8', $keyword))[0];

   my $metainfo = join("@@@", $searchtype, $keyword_fs, $vpath);
   my $cache_metainfo;
   my $vpathstr = f2u($vpath);

   $cachefile = ow::tool::untaint($cachefile);
   ow::filelock::lock($cachefile, LOCK_EX) or
      return("$lang_err{'couldnt_writelock'} $cachefile\n");

   if (-e $cachefile) {
      sysopen(CACHE, $cachefile, O_RDONLY) or return("$lang_err{'couldnt_read'} $cachefile!");
      $cache_metainfo = <CACHE>;
      chomp($cache_metainfo);
      close(CACHE);
   }
   if ($cache_metainfo ne $metainfo) {
      my (@cmd, $stdout, $stderr, $exit, $sig);

      chdir("$webdiskrootdir/$vpath") or
         return("$lang_err{'couldnt_chdirto'} $vpathstr\n");

      my $findbin = ow::tool::findbin('find');
      return("$lang_text{'program'} find $lang_err{'doesnt_exist'}\n") if ($findbin eq '');

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
         if ($searchtype eq "filename") {	# search keyword in file name
            push(@{$r_list}, $fname) if ($fname=~/$keyword_fs/i);

         } else {				# search keyword in file content
            next if (!-f "$webdiskrootdir/$vpath/$fname");
            my $ext = $fname; 
            $ext =~ s!.*/!!; 
            $ext =~ m!.*\.(.*)!; 
            $ext = $1;
            my $contenttype = ow::tool::ext2contenttype($fname);
            if ($contenttype =~ /msword/) {
               my $antiwordbin = ow::tool::findbin('antiword');
               next if ($antiwordbin eq '');
               my ($stdout, $stderr, $exit, $sig) = ow::execute::execute($antiwordbin, '-m', 'UTF-8.txt', "$webdiskrootdir/$vpath/$fname");
               next if ($exit||$sig);
               ($stdout) = iconv('utf-8', $prefs{'charset'}, $stdout);
               push(@{$r_list}, $fname) if ($stdout =~ /$keyword_utf8/i);

            } elsif ($contenttype =~ /text/|| $ext eq '') {
               # only read leading 4MB
               my $buff; 
               sysopen(F, "$webdiskrootdir/$vpath/$fname", O_RDONLY); 
               read(F, $buff, 4*1024*1024); 
               close(F);
               push(@{$r_list}, $fname) if ($buff=~/$keyword_fs/i);
            }
         }
      }

      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT);
      print CACHE join("\n", $metainfo, @{$r_list});
      close(CACHE);

   } else {
      my @result;
      sysopen(CACHE, $cachefile, O_RDONLY);
      $_ = <CACHE>;
      while (<CACHE>) {
         chomp;
         push (@{$r_list}, $_);
      }
      close(CACHE);
   }

   ow::filelock::lock($cachefile, LOCK_UN);

   return;
}

# a wrapper for execute() to handle the dirty work
sub webdisk_execute {
   my ($opstr, @cmd) = @_;
   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute(@cmd);

   # try to conv realpath in stdout/stderr back to vpath
   foreach ($stdout, $stderr) {
      s!(?:$webdiskrootdir/+|^$webdiskrootdir/*| $webdiskrootdir/*)! /!g;
      s!^\s*!!mg;  
      s!/+!/!g;
   }
   ($stdout, $stderr) = iconv($prefs{'fscharset'}, $prefs{'charset'}, $stdout, $stderr);

   my $opresult;
   if ($exit || $sig) {
      $opresult = $lang_text{'failed'};
   } else {
      $opresult = $lang_text{'succeeded'};
      writelog("webdisk execute - ".join(' ', @cmd));
      writehistory("webdisk execute - ".join(' ', @cmd));
   }
   if ($sig) {
      return "$opstr $opresult (exit status $exit, terminated by signal $sig)\n$stdout$stderr";
   } else {
      return "$opstr $opresult (exit status $exit)\n$stdout$stderr";
   }
}

sub findicon {
   my ($fname, $ftype, $is_txt, $os) = @_;

   return ("dir.gif") if ($ftype eq "d");
   return ("sys.gif") if ($ftype eq "u");

   $_ = lc($fname);

   return("cert.gif") if ( /\.(ce?rt|cer|ssl)$/ );
   return("help.gif") if ( /\.(hlp|man|cat|info)$/ );
   return("pdf.gif")  if ( /\.(fdf|pdf)$/ );
   return("html.gif") if ( /\.(shtml|html?|xml|sgml|wmls?)$/ );
   return("txt.gif")  if ( /\.te?xt$/ );

   if ($is_txt) {
      return("css.gif")  if ( /\.(css|jsp?|aspx?|php[34]?|xslt?|vb[se]|ws[cf]|wrl|vrml)$/ );
      return("ini.gif")  if ( /\.(ini|inf|conf|cf|config)$/ || /^\..*rc$/ );
      return("mail.gif") if ( /\.(msg|elm)$/ );
      return("ps.gif")   if ( /\.(ps|eps)$/ );
      return("txt.gif");
   } else {
      return("audio.gif")  if ( /\.(mid[is]?|mod|au|cda|aif[fc]?|voc|wav|snd)$/ );
      return("chm.gif")    if ( /\.chm$/ );
      return("doc.gif")    if ( /\.(do[ct]|rtf|wri)$/ );
      return("exe.gif")    if ( /\.(exe|com|dll)$/ );
      return("font.gif")   if ( /\.fon$/ );
      return("graph.gif")  if ( /\.(jpe?g|gif|png|bmp|p[nbgp]m|pc[xt]|pi[cx]|psp|dcx|kdc|tiff?|ico|x[bp]m|img)$/);
      return("mdb.gif")    if ( /\.(md[bentz]|ma[fmq])$/ );
      return("mp3.gif")    if ( /\.(m3u|mp[32]|mpga)$/ );
      return("ppt.gif")    if ( /\.(pp[at]|pot)$/ );
      return("rm.gif")     if ( /\.(r[fampv]|ram)$/ );
      return("stream.gif") if ( /\.(wmv|wvx|as[fx])$/ );
      return("ttf.gif")    if ( /\.tt[cf]$/ );
      return("video.gif")  if ( /\.(avi|mov|dat|mpe?g)$/ );
      return("xls.gif")    if ( /\.xl[abcdmst]$/ );
      return("zip.gif")    if ( /\.(zip|tar|t?g?z|tbz|bz2?|rar|lzh|arj|ace|bhx|hqx|jar|tne?f)$/ );

      return("file".lc($1).".gif") if ( $os =~ /(bsd|linux|solaris)/i );
      return("file.gif");
   }
}

sub is_quota_available {
   my $writesize = $_[0];
   if ($quotalimit > 0 && $quotausage + $writesize > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
      return 0 if ($quotausage + $writesize > $quotalimit);
   }
   return 1;
}
