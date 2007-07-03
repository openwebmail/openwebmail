#!/usr/bin/suidperl -T
#
# openwebmail-webdisk.pl - web disk program
#
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
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_wdbutton %lang_text %lang_err);	# defined in lang/xy

# local globals
use vars qw($folder $messageid);
use vars qw($escapedmessageid $escapedfolder);
use vars qw($webdiskrootdir);

########## MAIN ##################################################
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

$webdiskrootdir=ow::tool::untaint($homedir.absolute_vpath("/", $config{'webdisk_rootpath'}));
$webdiskrootdir=~s!/+$!!; # remove tail /
if (! -d $webdiskrootdir) {
   mkdir($webdiskrootdir, 0755) or
      openwebmailerror(__FILE__, __LINE__, "$lang_text{'couldnt_create'} $webdiskrootdir ($!)");
}

my $action = param('action')||'';
my $currentdir;
if (defined param('currentdir') && param('currentdir') ne "") {
   $currentdir = ow::tool::unescapeURL(param('currentdir'));
} else {
   $currentdir = cookie("ow-currentdir-$domain-$user"),
}
my $gotodir = ow::tool::unescapeURL(param('gotodir'))||'';
my @selitems = (param('selitems')); foreach (@selitems) { $_=ow::tool::unescapeURL($_) }
my $destname = ow::tool::unescapeURL(param('destname'))||'';
my $filesort = param('filesort')|| 'name';
my $page = param('page') || 1;

# all path in param are treated as virtual path under $webdiskrootdir.
$currentdir = absolute_vpath("/", $currentdir);
$gotodir = absolute_vpath($currentdir, $gotodir);

my $msg=verify_vpath($webdiskrootdir, $currentdir);
openwebmailerror(__FILE__, __LINE__, "$lang_err{'access_denied'} (".f2u($currentdir).": $msg)") if ($msg);
$currentdir=ow::tool::untaint($currentdir);

writelog("debug - request webdisk begin, action=$action, currentdir=$currentdir - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "mkdir" || defined param('mkdirbutton') ) {
   if ($config{'webdisk_readonly'}) {
      $msg=$lang_err{'webdisk_readonly'};
   } elsif (is_quota_available(0)) {
      $msg=createdir($currentdir, $destname) if ($destname);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "newfile" || defined param('newfilebutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=createfile($currentdir, $destname) if ($destname);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "copy" || defined param('copybutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=copymovesymlink_dirfiles("copy", $currentdir, $destname, @selitems) if ($#selitems>=0);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "move" || defined param('movebutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=copymovesymlink_dirfiles("move", $currentdir, $destname, @selitems) if ($#selitems>=0);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ( $config{'webdisk_allow_symlinkcreate'} &&
         ($action eq "symlink" || defined param('symlinkbutton')) ){
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=copymovesymlink_dirfiles("symlink", $currentdir, $destname, @selitems) if ($#selitems>=0);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "delete" || defined param('deletebutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } else {
      $msg=deletedirfiles($currentdir, @selitems) if  ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "chmod" || defined param('chmodbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } else {
      $msg=chmoddirfiles(param('permission'), $currentdir, @selitems) if  ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "editfile" || defined param('editbutton')) {
   if ($config{'webdisk_readonly'}) {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'webdisk_readonly'});
   } elsif (is_quota_available(0)) {
      if ($#selitems==0) {
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

} elsif ($action eq "gzip" || defined param('gzipbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=compressfiles("gzip", $currentdir, '', @selitems) if ($#selitems>=0);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mkzip" || defined param('mkzipbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=compressfiles("mkzip", $currentdir, $destname, @selitems) if ($#selitems>=0);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mktgz" || defined param('mktgzbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=compressfiles("mktgz", $currentdir, $destname, @selitems) if ($#selitems>=0);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "decompress" || defined param('decompressbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      if ($#selitems==0) {
         $msg=decompressfile($currentdir, $selitems[0]);
      } else {
         $msg="$lang_wdbutton{'decompress'} - $lang_err{'onefileonly'}";
      }
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "listarchive" || defined param('listarchivebutton')) {
   if ($#selitems==0) {
      $msg=listarchive($currentdir, $selitems[0]);
   } else {
      $msg="$lang_wdbutton{'listarchive'} - $lang_err{'onefileonly'}";
   }

} elsif ($action eq "wordpreview" || defined param('wordpreviewbutton')) {
   if ($#selitems==0) {
      $msg=wordpreview($currentdir, $selitems[0]);
   } else {
      $msg="MS Word $lang_wdbutton{'preview'} - $lang_err{'onefileonly'}";
   }

} elsif ($action eq "mkpdf" || defined param('mkpdfbutton') ) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      if ($#selitems==0) {
         $msg=makepdfps('mkpdf', $currentdir, $selitems[0]);
      } else {
         $msg="$lang_wdbutton{'mkpdf'} - $lang_err{'onefileonly'}";
      }
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mkps" || defined param('mkpsbutton') ) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      if ($#selitems==0) {
         $msg=makepdfps('mkps', $currentdir, $selitems[0]);
      } else {
         $msg="$lang_wdbutton{'mkps'} - $lang_err{'onefileonly'}";
      }
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mkthumbnail" || defined param('mkthumbnailbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      $msg=makethumbnail($currentdir, @selitems) if ($#selitems>=0);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "preview") {
   my $vpath=absolute_vpath($currentdir, $selitems[0]);
   my $filecontent=param('filecontent')||'';
   if ($#selitems==0) {
      if ( $filecontent) {
         $msg=previewfile($currentdir, $selitems[0], $filecontent);
      } elsif ( -d "$webdiskrootdir/$vpath" ) {
         showdir($currentdir, $vpath, $filesort, $page, $msg); $msg='';
      } else {
         $msg=previewfile($currentdir, $selitems[0], '');
      }
   } else {
      $msg=$lang_err{'no_file_todownload'};
   }
   openwebmailerror(__FILE__, __LINE__, $msg) if ($msg ne '');

} elsif ($action eq "download" || defined param('downloadbutton')) {
   if ($#selitems>0) {
      $msg=downloadfiles($currentdir, @selitems);
   } elsif ($#selitems==0) {
      my $vpath=absolute_vpath($currentdir, $selitems[0]);
      if ( -d "$webdiskrootdir/$vpath" ) {
         $msg=downloadfiles($currentdir, @selitems);
      } else {
         $msg=downloadfile($currentdir, $selitems[0]);
      }
   } else {
      $msg="$lang_err{'no_file_todownload'}\n";
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg) if ($msg ne '');

} elsif ($action eq "upload" || defined param('uploadbutton')) {
   if ($config{'webdisk_readonly'}) {
      $msg="$lang_err{'webdisk_readonly'}\n";
   } elsif (is_quota_available(0)) {
      my $upload=param('upload');	# name and handle of the upload file
      $msg=uploadfile($currentdir, $upload) if ($upload);
   } else {
      $msg="$lang_err{'quotahit_alert'}\n";
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
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
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
########## END MAIN ##############################################

########## CREATEDIR #############################################
sub createdir {
   my ($currentdir, $destname)=@_;
   $destname=u2f($destname);

   my $vpath=ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr=f2u($vpath);
   my $err=verify_vpath($webdiskrootdir, $vpath);
   return ("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   if ( -e "$webdiskrootdir/$vpath") {
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
########## END CREATEDIR #########################################

########## NEWFILE ###############################################
sub createfile {
   my ($currentdir, $destname)=@_;
   $destname=u2f($destname);

   my $vpath=ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr=f2u($vpath);
   my $err=verify_vpath($webdiskrootdir, $vpath);
   return ("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   if ( -e "$webdiskrootdir/$vpath") {
      return("$lang_text{'dir'} $vpathstr $lang_err{'already_exists'}\n") if (-d _);
      return("$lang_text{'file'} $vpathstr $lang_err{'already_exists'}\n");
   } else {
      if (sysopen(F, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT)) {
         print F ''; close(F);
         writelog("webdisk createfile - $vpath");
         writehistory("webdisk createfile - $vpath");
         return("$lang_wdbutton{'newfile'} $vpathstr\n");
      } else {
         return("$lang_err{'couldnt_create'} $vpathstr ($!)\n");
      }
   }
}
########## END NEWFILE ###########################################

########## DELETEDIRFILES ########################################
sub deletedirfiles {
   my ($currentdir, @selitems)=@_;
   my ($msg, $err);

   my @filelist;
   foreach (@selitems) {
      my $vpath=ow::tool::untaint(absolute_vpath($currentdir, $_));
      my $vpathstr=f2u($vpath);
      $err=verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg.="$lang_err{'access_denied'} ($vpathstr: $err)\n"; next;
      }
      if (!-l "$webdiskrootdir/$vpath" && !-e "$webdiskrootdir/$vpath") {
         $msg.="$vpathstr $lang_err{'doesnt_exist'}\n"; next;
      }
      if (-f _ && $vpath=~/\.(?:jpe?g|gif|png|bmp|tif)$/i) {
         my $thumbnail=path2thumbnail("$webdiskrootdir/$vpath");
         push(@filelist, $thumbnail) if (-f $thumbnail);
      }
      push(@filelist, "$webdiskrootdir/$vpath");
   }
   return($msg) if ($#filelist<0);

   my @cmd;
   my $rmbin=ow::tool::findbin('rm');
   return("$lang_text{'program'} rm $lang_err{'doesnt_exist'}\n") if ($rmbin eq '');
   @cmd=($rmbin, '-Rfv');

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $msg2=webdisk_execute($lang_wdbutton{'delete'}, @cmd, @filelist);
   if ($msg2=~/rm:/) {
      $cmd[1]=~s/v//;
      $msg2=webdisk_execute($lang_wdbutton{'delete'}, @cmd, @filelist);
   }
   $msg.=$msg2;
   if ($quotalimit>0 && $quotausage>$quotalimit) {	# get uptodate quotausage
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   return($msg);
}
########## END DELETEDIRFILES ####################################

########## CHMODDIRFILES #########################################
sub chmoddirfiles {
   my ($perm, $currentdir, @selitems)=@_;
   my ($msg, $err);

   $perm=~s/\s//g;
   if ($perm=~/[^0-7]/) {	# has invalid char for chmod?
      return("$lang_wdbutton{'chmod'} $lang_err{'has_illegal_chars'}\n");
   } elsif ($perm!~/^0/) {	# should leading with 0
      $perm='0'.$perm;
   }

   my @filelist;
   foreach (@selitems) {
      my $vpath=ow::tool::untaint(absolute_vpath($currentdir, $_));
      my $vpathstr=f2u($vpath);
      $err=verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg.="$lang_err{'access_denied'} ($vpathstr: $err)\n"; next;
      }
      if (!-l "$webdiskrootdir/$vpath" && !-e "$webdiskrootdir/$vpath") {
         $msg.="$vpathstr $lang_err{'doesnt_exist'}\n"; next;
      }
      if (-f _ && $vpath=~/\.(?:jpe?g|gif|png|bmp|tif)$/i) {
         my $thumbnail=path2thumbnail("$webdiskrootdir/$vpath");
         push(@filelist, $thumbnail) if (-f $thumbnail);
      }
      push(@filelist, "$webdiskrootdir/$vpath");
   }
   return($msg) if ($#filelist<0);

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $notchanged=$#filelist+1 - chmod(oct(ow::tool::untaint($perm)), @filelist);
   if ($notchanged!=0) {
      return("$notchanged item(s) not chnaged ($!)");
   }
   return($msg);
}
########## END CHMODDIRFILES #####################################

########## COPYDIRFILES ##########################################
sub copymovesymlink_dirfiles {
   my ($op, $currentdir, $destname, @selitems)=@_;
   $destname=u2f($destname);

   my ($msg, $err);
   my $vpath2=ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpath2str=f2u($vpath2);
   $err=verify_vpath($webdiskrootdir, $vpath2);
   return ("$lang_err{'access_denied'} ($vpath2str: $err)\n") if ($err);

   if ($#selitems>0) {
      if (!-e "$webdiskrootdir/$vpath2") {
         return("$vpath2str $lang_err{'doesnt_exist'}\n");
      } elsif (!-d _) {
         return("$vpath2str $lang_err{'isnt_a_dir'}\n");
      }
   }

   my @filelist;
   foreach (@selitems) {
      my $vpath1=ow::tool::untaint(absolute_vpath($currentdir, $_));
      my $vpath1str=f2u($vpath1);
      $err=verify_vpath($webdiskrootdir, $vpath1);
      if ($err) {
         $msg.="$lang_err{'access_denied'} ($vpath1str: $err)\n"; next;
      }
      if (! -e "$webdiskrootdir/$vpath1") {
         $msg.="$vpath1str $lang_err{'doesnt_exist'}\n"; next;
      }
      next if ($vpath1 eq $vpath2);

      my $p="$webdiskrootdir/$vpath1"; $p=~s!/+!/!g;	# eliminate duplicated /
      push(@filelist, $p);
   }
   return($msg) if ($#filelist<0);

   my @cmd;
   if ($op eq "copy") {
      my $cpbin=ow::tool::findbin('cp');
      return("$lang_text{'program'} cp $lang_err{'doesnt_exist'}\n") if ($cpbin eq '');
      @cmd=($cpbin, '-pRfv');
   } elsif ($op eq "move") {
      my $mvbin=ow::tool::findbin('mv');
      return("$lang_text{'program'} mv $lang_err{'doesnt_exist'}\n") if ($mvbin eq '');
      @cmd=($mvbin, '-fv');
   } elsif ($op eq "symlink") {
      my $lnbin=ow::tool::findbin('ln');
      return("$lang_text{'program'} ln $lang_err{'doesnt_exist'}\n") if ($lnbin eq '');
      @cmd=($lnbin, '-sv');
   } else {
      return($msg);
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $msg2=webdisk_execute($lang_wdbutton{$op}, @cmd, @filelist, "$webdiskrootdir/$vpath2");
   if ($msg2=~/cp:/ || $msg2=~/mv:/ || $msg2=~/ln:/) {	# -vcmds not supported on solaris
      $cmd[1]=~s/v//;
      $msg2=webdisk_execute($lang_wdbutton{$op}, @cmd, @filelist, "$webdiskrootdir/$vpath2");
   }
   $msg.=$msg2;
   return($msg);
}
########## END COPYDIRFILES ######################################

########## EDITFILE ##############################################
sub editfile {
   my ($currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $vpathstr=f2u($vpath);
   my $content;

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editfile.template"));

   if ( -d "$webdiskrootdir/$vpath") {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'edit_notfordir'});
   } elsif ( -f "$webdiskrootdir/$vpath" ) {
      my $err=verify_vpath($webdiskrootdir, $vpath);
      autoclosewindow($lang_wdbutton{'edit'}, "$lang_err{'access_denied'} ($vpathstr: $err)") if ($err);

      ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_SH|LOCK_NB) or
         autoclosewindow($lang_text{'edit'}, "$lang_err{'couldnt_readlock'} $vpathstr!");
      if (sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY)) {
         local $/; undef $/;
         $content=<F>; close(F);
      } else {
         ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN);
         autoclosewindow($lang_wdbutton{'edit'}, "$lang_err{'couldnt_read'} $vpathstr");
      }
      ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN);

      $content =~ s|<\s*/\s*textarea\s*>|</ESCAPE_TEXTAREA>|gi;

      writelog("webdisk editfile - $vpath");
      writehistory("webdisk editfile - $vpath");
   }

   $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl",
                           -name=>'editfile') .
                ow::tool::hiddens(sessionid=>$thissession,
                                  action=>'savefile',
                                  currentdir=>ow::tool::escapeURL($currentdir));
   $html =~ s/\@\@\@STARTEDITFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'destname',
                         -default=>$vpathstr,
                         -size=>'66',
                         -override=>'1');
   $html =~ s/\@\@\@FILENAME\@\@\@/$temphtml/;

   if ($vpath=~/\.html?$/) {
      $temphtml = submit(-name=>'previewbutton',
                         -value=>$lang_wdbutton{'preview'},
                         -OnClick=>qq|preview(); return false;|,
                         -override=>'1');
      $html =~ s/\@\@\@PREVIEWBUTTON\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@PREVIEWBUTTON\@\@\@//;
   }

   $temphtml = submit("$lang_text{'save'}");
   $html =~ s/\@\@\@SAVEBUTTON\@\@\@/$temphtml/;

   $temphtml = button(-name=>'cancelbutton',
                      -value=>$lang_text{'cancel'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl",
                         -name=>'previewform',
                         -target=>'_preview').
              ow::tool::hiddens(sessionid=>$thissession,
                                action=>'preview',
                                currentdir=>ow::tool::escapeURL($currentdir),
                                selitems=>'',
                                filecontent=>'');
   $html =~ s/\@\@\@STARTPREVIEWFORM\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   # put this at last to avoid @@@pattern@@@ replacement happens on $content
   $temphtml = textarea(-name=>'filecontent',
                        -default=>f2u($content),
                        -rows=>$prefs{'webdisk_fileeditrows'},
                        -columns=>$prefs{'webdisk_fileeditcolumns'},
                        -wrap=>'soft',
                        -override=>'1');
   $html =~ s/\@\@\@FILECONTENT\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITFILE ##########################################

########## SAVEFILE ##############################################
sub savefile {
   my ($currentdir, $destname, $content)=@_;
   ($destname, $content)=iconv($prefs{charset}, $prefs{fscharset}, $destname, $content);

   my $vpath=ow::tool::untaint(absolute_vpath($currentdir, $destname));
   my $vpathstr=f2u($vpath);
   my $err=verify_vpath($webdiskrootdir, $vpath);
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

   my $jscode=qq|if (window.opener.document.dirform!=null) {window.opener.document.dirform.submit();}|;	# refresh parent if it is dirform
   autoclosewindow($lang_text{'savefile'}, "$lang_text{'savefile'} $lang_text{'succeeded'} ($vpathstr)", 5, $jscode);
}
########## END SAVEFILE ##########################################

########## COMPRESSFILES #########################################
sub compressfiles {	# pack files with zip or tgz (tar -zcvf)
   my ($ztype, $currentdir, $destname, @selitems)=@_;
   $destname=u2f($destname);

   my ($vpath2, $vpath2str, $msg, $err);
   if ($ztype eq "mkzip" || $ztype eq "mktgz" ) {
      $vpath2=ow::tool::untaint(absolute_vpath($currentdir, $destname));
      $vpath2str=f2u($vpath2);
      $err=verify_vpath($webdiskrootdir, $vpath2);
      return ("$lang_err{'access_denied'} ($vpath2str: $err)\n") if ($err);
      if ( -e "$webdiskrootdir/$vpath2") {
         return("$lang_text{'dir'} $vpath2str $lang_err{'already_exists'}\n") if (-d _);
         return("$lang_text{'file'} $vpath2str $lang_err{'already_exists'}\n");
      }
   }

   my %selitem;
   foreach (@selitems) {
      my $vpath=absolute_vpath($currentdir, $_);
      my $vpathstr=f2u($vpath);
      $err=verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg.="$lang_err{'access_denied'} ($vpathstr: $err)\n"; next;
      }

      # use relative path to currentdir since we will chdir to webdiskrootdir/currentdir before compress
      my $p=fullpath2vpath("$webdiskrootdir/$vpath", "$webdiskrootdir/$currentdir");
      # use absolute path if relative to webdiskrootdir/currentdir is not possible
      $p="$webdiskrootdir/$vpath" if ($p eq "");
      $p=ow::tool::untaint($p);

      if ( -d "$webdiskrootdir/$vpath" ) {
         $selitem{".$p/"}=1;
      } elsif ( -e _ ) {
         $selitem{".$p"}=1;
      }
   }
   my @filelist=keys(%selitem);
   return($msg) if ($#filelist<0);

   my @cmd;
   if ($ztype eq "gzip") {
      my $gzipbin=ow::tool::findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      @cmd=($gzipbin, '-rq');
   } elsif ($ztype eq "mkzip") {
      my $zipbin=ow::tool::findbin('zip');
      return("$lang_text{'program'} zip $lang_err{'doesnt_exist'}\n") if ($zipbin eq '');
      @cmd=($zipbin, '-ryq', "$webdiskrootdir/$vpath2");
   } elsif ($ztype eq "mktgz") {
      my $gzipbin=ow::tool::findbin('gzip');
      my $tarbin=ow::tool::findbin('tar');
      if ($gzipbin ne '') {
         $ENV{'PATH'}=$gzipbin; $ENV{'PATH'}=~s|/gzip||; # for tar
         @cmd=($tarbin, '-zcpf', "$webdiskrootdir/$vpath2");
      } else {
         @cmd=($tarbin, '-cpf', "$webdiskrootdir/$vpath2");
      }
   } else {
      return("unknown ztype($ztype)?");
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $opstr;
   if ($ztype eq "mkzip") {
      $opstr=$lang_wdbutton{'mkzip'};
   } elsif ($ztype eq "mktgz") {
      $opstr=$lang_wdbutton{'mktgz'};
   } else {
      $opstr=$lang_wdbutton{'gzip'};
   }
   return(webdisk_execute($opstr, @cmd, @filelist));
}
########## END COMPRESSFILES #####################################

########## DECOMPRESSFILE ########################################
sub decompressfile {	# unpack tar.gz, tgz, tar.bz2, tbz, gz, zip, rar, arj, ace, lzh, tnef/tnf
   my ($currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $vpathstr=f2u($vpath);

   if ( !-f "$webdiskrootdir/$vpath" || !-r _) {
      return("$lang_err{'couldnt_read'} $vpathstr");
   }
   my $err=verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   my @cmd;
   if ($vpath=~/\.(tar\.g?z||tgz)$/i && $config{'webdisk_allow_untar'}) {
      my $gzipbin=ow::tool::findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      my $tarbin=ow::tool::findbin('tar');
      $ENV{'PATH'}=$gzipbin; $ENV{'PATH'}=~s|/gzip||; # for tar
      @cmd=($tarbin, '-zxpf');

   } elsif ($vpath=~/\.(tar\.bz2?||tbz)$/i && $config{'webdisk_allow_untar'}) {
      my $bzip2bin=ow::tool::findbin('bzip2');
      return("$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if ($bzip2bin eq '');
      my $tarbin=ow::tool::findbin('tar');
      $ENV{'PATH'}=$bzip2bin; $ENV{'PATH'}=~s|/bzip2||;	# for tar
      @cmd=($tarbin, '-yxpf');

   } elsif ($vpath=~/\.g?z$/i) {
      my $gzipbin=ow::tool::findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      @cmd=($gzipbin, '-dq');

   } elsif ($vpath=~/\.bz2?$/i) {
      my $bzip2bin=ow::tool::findbin('bzip2');
      return("$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if ($bzip2bin eq '');
      @cmd=($bzip2bin, '-dq');

   } elsif ($vpath=~/\.zip$/i && $config{'webdisk_allow_unzip'}) {
      my $unzipbin=ow::tool::findbin('unzip');
      return("$lang_text{'program'} unzip $lang_err{'doesnt_exist'}\n") if ($unzipbin eq '');
      @cmd=($unzipbin, '-oq');

   } elsif ($vpath=~/\.rar$/i && $config{'webdisk_allow_unrar'}) {
      my $unrarbin=ow::tool::findbin('unrar');
      return("$lang_text{'program'} unrar $lang_err{'doesnt_exist'}\n") if ($unrarbin eq '');
      @cmd=($unrarbin, 'x', '-r', '-y', '-o+');

   } elsif ($vpath=~/\.arj$/i && $config{'webdisk_allow_unarj'}) {
      my $unarjbin=ow::tool::findbin('unarj');
      return("$lang_text{'program'} unarj $lang_err{'doesnt_exist'}\n") if ($unarjbin eq '');
      @cmd=($unarjbin, 'x');

   } elsif ($vpath=~/\.ace$/i && $config{'webdisk_allow_unace'}) {
      my $unacebin=ow::tool::findbin('unace');
      return("$lang_text{'program'} unace $lang_err{'doesnt_exist'}\n") if ($unacebin eq '');
      @cmd=($unacebin, 'x', '-y');

   } elsif ($vpath=~/\.lzh$/i && $config{'webdisk_allow_unlzh'}) {
      my $lhabin=ow::tool::findbin('lha');
      return("$lang_text{'program'} lha $lang_err{'doesnt_exist'}\n") if ($lhabin eq '');
      @cmd=($lhabin, '-xfq');

   } elsif ($vpath=~/\.tne?f$/i) {
      my $tnefbin=ow::tool::findbin('tnef');
      return("$lang_text{'program'} tnef $lang_err{'doesnt_exist'}\n") if ($tnefbin eq '');
      @cmd=($tnefbin, '--overwrite', '-v', '-f');

   } else {
      return("$lang_err{'decomp_notsupported'} ($vpathstr)\n");
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $opstr;
   if ($vpath=~/\.(?:zip|rar|arj|ace|lhz|t[bg]z|tar\.g?z|tar\.bz2?|tne?f)$/i) {
      $opstr=$lang_wdbutton{'extract'};
   } else {
      $opstr=$lang_wdbutton{'decompress'};
   }
   return(webdisk_execute($opstr, @cmd, "$webdiskrootdir/$vpath"));
}
########## END DECOMPRESSFILE ####################################

########## LISTARCHIVE ###########################################
sub listarchive {
   my ($currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $vpathstr=f2u($vpath);

   my ($html, $temphtml);
   $html = applystyle(readtemplate("listarchive.template"));

   if (! -f "$webdiskrootdir/$vpath") {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'file'} $vpathstr $lang_err{'doesnt_exist'}");
      return;
   }
   my $err=verify_vpath($webdiskrootdir, $vpath);
   if ($err) {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_err{'access_denied'} ($vpathstr: $err)");
      return;
   }

   my @cmd;
   if ($vpath=~/\.(tar\.g?z|tgz)$/i) {
      my $gzipbin=ow::tool::findbin('gzip');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if ($gzipbin eq '');
      my $tarbin=ow::tool::findbin('tar');
      $ENV{'PATH'}=$gzipbin; $ENV{'PATH'}=~s|/gzip||; # for tar
      @cmd=($tarbin, '-ztvf');

   } elsif ($vpath=~/\.(tar\.bz2?|tbz)$/i) {
      my $bzip2bin=ow::tool::findbin('bzip2');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if ($bzip2bin eq '');
      my $tarbin=ow::tool::findbin('tar');
      $ENV{'PATH'}=$bzip2bin; $ENV{'PATH'}=~s|/bzip2||;	# for tar
      @cmd=($tarbin, '-ytvf');

   } elsif ($vpath=~/\.zip$/i) {
      my $unzipbin=ow::tool::findbin('unzip');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unzip $lang_err{'doesnt_exist'}\n") if ($unzipbin eq '');
      @cmd=($unzipbin, '-lq');

   } elsif ($vpath=~/\.rar$/i) {
      my $unrarbin=ow::tool::findbin('unrar');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unrar $lang_err{'doesnt_exist'}\n") if ($unrarbin eq '');
      @cmd=($unrarbin, 'l');

   } elsif ($vpath=~/\.arj$/i) {
      my $unarjbin=ow::tool::findbin('unarj');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unarj $lang_err{'doesnt_exist'}\n") if ($unarjbin eq '');
      @cmd=($unarjbin, 'l');

   } elsif ($vpath=~/\.ace$/i) {
      my $unacebin=ow::tool::findbin('unace');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unace $lang_err{'doesnt_exist'}\n") if ($unacebin eq '');
      @cmd=($unacebin, 'l', '-y');

   } elsif ($vpath=~/\.lzh$/i) {
      my $lhabin=ow::tool::findbin('lha');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} lha $lang_err{'doesnt_exist'}\n") if ($lhabin eq '');
      @cmd=($lhabin, '-l');

   } elsif ($vpath=~/\.tne?f$/i) {
      my $tnefbin=ow::tool::findbin('tnef');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} tnef $lang_err{'doesnt_exist'}\n") if ($tnefbin eq '');
      @cmd=($tnefbin, '-t');

   } else {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_err{'decomp_notsupported'} ($vpathstr)\n");
   }

   my ($stdout, $stderr, $exit, $sig)=ow::execute::execute(@cmd, "$webdiskrootdir/$vpath");
   # try to conv realpath in stdout/stderr back to vpath
   $stdout=~s!(?:$webdiskrootdir//|\s$webdiskrootdir/)! /!g; $stdout=~s!/+!/!g;
   $stderr=~s!(?:$webdiskrootdir//|\s$webdiskrootdir/)! /!g; $stderr=~s!/+!/!g;
   ($stdout, $stderr)=iconv($prefs{'fscharset'}, $prefs{'charset'}, $stdout, $stderr);

   if ($exit||$sig) {
      my $err="$lang_text{'program'} $cmd[0]  $lang_text{'failed'} (exit status $exit";
      $err.=", terminated by signal $sig" if ($sig);
      $err.=")\n$stdout$stderr";
      autoclosewindow($lang_wdbutton{'listarchive'}, $err);
   } else {
      writelog("webdisk listarchive - $vpath");
      writehistory("webdisk listarchive - $vpath");
   }

   $temphtml .= start_form('listarchive') .
   $html =~ s/\@\@\@STARTEDITFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'selectitems',
                         -default=>$vpath,
                         -size=>'66',
                         -disabled=>'1',
                         -override=>'1');
   $html =~ s/\@\@\@FILENAME\@\@\@/$temphtml/;

   $temphtml = qq|<table width="95%" border=0 cellpadding=0 cellspacing=1 bgcolor=#999999><tr><td nowrap bgcolor=#ffffff>\n|.
               qq|<table width=100%><tr><td><pre>$stdout</pre></td></tr></table>\n|.
               qq|</td</tr></table>\n|;
   $html =~ s/\@\@\@FILECONTENT\@\@\@/$temphtml/;

   $temphtml = button(-name=>'closebutton',
                      -value=>$lang_text{'close'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CLOSEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END LISTARCHIVE #######################################

########## WORDPREVIEW ###########################################
sub wordpreview {		# msword text preview
   my ($currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $vpathstr=f2u($vpath);

   my ($html, $temphtml);
   $html = applystyle(readtemplate("wordpreview.template"));

   if (! -f "$webdiskrootdir/$vpath") {
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_text{'file'} $vpathstr $lang_err{'doesnt_exist'}");
      return;
   }
   my $err=verify_vpath($webdiskrootdir, $vpath);
   if ($err) {
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_err{'access_denied'} ($vpathstr: $err)");
      return;
   }

   my @cmd;
   if ($vpath=~/\.(?:doc|dot)$/i) {
      my $antiwordbin=ow::tool::findbin('antiword');
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_text{'program'} antiword $lang_err{'doesnt_exist'}\n") if ($antiwordbin eq '');
      @cmd=($antiwordbin, '-m', 'UTF-8.txt');
   } else {
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", "$lang_err{'filefmt_notsupported'} ($vpathstr)\n");
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my ($stdout, $stderr, $exit, $sig)=ow::execute::execute(@cmd, "$webdiskrootdir/$vpath");

   if ($exit||$sig) {
      # try to conv realpath in stdout/stderr back to vpath
      $stderr=~s!(?:$webdiskrootdir//|\s$webdiskrootdir/)! /!g; $stderr=~s!/+!/!g;
      $stderr=~s!^\s+.*$!!mg;	# remove the antiword syntax description
      $stderr=f2u($stderr);

      my $err="$lang_text{'program'} antiword $lang_text{'failed'} (exit status $exit";
      $err.=", terminated by signal $sig" if ($sig);
      $err.=")\n$stderr";
      autoclosewindow("MS Word $lang_wdbutton{'preview'}", $err);
   } else {
      ($stdout)=iconv('utf-8', $prefs{'charset'}, $stdout);
      writelog("webdisk wordpreview - $vpath");
      writehistory("webdisk wordpreview - $vpath");
   }

   $temphtml .= start_form('wordpreview') .
   $html =~ s/\@\@\@STARTEDITFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'selectitems',
                         -default=>$vpathstr,
                         -size=>'66',
                         -disabled=>'1',
                         -override=>'1');
   $html =~ s/\@\@\@FILENAME\@\@\@/$temphtml/;

   $temphtml = qq|<table width="95%" border=0 cellpadding=0 cellspacing=1 bgcolor=#999999><tr><td nowrap bgcolor=#ffffff>\n|.
               qq|<table width=100%><tr><td><pre>$stdout</pre></td></tr></table>\n|.
               qq|</td</tr></table>\n|;
   $html =~ s/\@\@\@FILECONTENT\@\@\@/$temphtml/;

   $temphtml = button(-name=>'closebutton',
                      -value=>$lang_text{'close'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CLOSEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END WORDPREVIEW #######################################

########## MAKEPDFPS #############################################
sub makepdfps {		# ps2pdf or pdf2ps
   my ($mktype, $currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $vpathstr=f2u($vpath);

   if ( !-f "$webdiskrootdir/$vpath" || !-r _) {
      return("$lang_err{'couldnt_read'} $vpathstr");
   }
   my $err=verify_vpath($webdiskrootdir, $vpath);
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
########## END MAKEPDFPS #########################################

########## MAKETHUMB #############################################
sub makethumbnail {
   my ($currentdir, @selitems)=@_;
   my $msg;

   my $convertbin=ow::tool::findbin('convert');
   return("$lang_text{'program'} convert $lang_err{'doesnt_exist'}\n") if ($convertbin eq '');
   my @cmd=($convertbin, '+profile', '*', '-interlace', 'NONE', '-geometry', '64x64');

   foreach (@selitems) {
      my $vpath=absolute_vpath($currentdir, $_);
      my $vpathstr=f2u($vpath);
      my $err=verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg.="$lang_err{'access_denied'} ($vpathstr: $err)\n"; next;
      }
      next if ( $vpath!~/\.(jpe?g|gif|png|bmp|tif)$/i ||
                !-f "$webdiskrootdir/$vpath" ||
                -s _ < 2048);				# use image itself is as thumbnail if size<2k

      my $thumbnail=ow::tool::untaint(path2thumbnail($vpath));
      my @p=split(/\//, $thumbnail); pop(@p);
      my $thumbnaildir=join('/', @p);
      if (!-d "$webdiskrootdir/$thumbnaildir") {
         if (!mkdir (ow::tool::untaint("$webdiskrootdir/$thumbnaildir"), 0755)) {
            $msg.="$!\n"; next;
         }
      }

      my ($img_atime,$img_mtime)= (stat("$webdiskrootdir/$vpath"))[8,9];
      if (-f "$webdiskrootdir/$thumbnail") {
         my ($thumbnail_atime,$thumbnail_mtime)= (stat("$webdiskrootdir/$thumbnail"))[8,9];
         next if ($thumbnail_mtime==$img_mtime);
      }
      $msg.=webdisk_execute("$lang_wdbutton{'mkthumbnail'} $thumbnail", @cmd, "$webdiskrootdir/$vpath", "$webdiskrootdir/$thumbnail");
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
   my @p=split(/\//, $_[0]);
   my $tfile=pop(@p); $tfile=~s/\.[^\.]*$/\.jpg/i;
   push(@p, '.thumbnail');
   return(join('/',@p)."/$tfile");
}
########## END MAKETHUMB #########################################

########## DOWNLOADFILES #########################################
sub downloadfiles {	# through zip or tgz
   my ($currentdir, @selitems)=@_;
   my $msg;

   my %selitem;
   foreach (@selitems) {
      my $vpath=absolute_vpath($currentdir, $_);
      my $vpathstr=f2u($vpath);
      my $err=verify_vpath($webdiskrootdir, $vpath);
      if ($err) {
         $msg.="$lang_err{'access_denied'} ($vpathstr: $err)\n"; next;
      }
      # use relative path to currentdir since we will chdir to webdiskrootdir/currentdir before DL
      my $p=fullpath2vpath("$webdiskrootdir/$vpath", "$webdiskrootdir/$currentdir");
      # use absolute path if relative to webdiskrootdir/currentdir is not possible
      $p="$webdiskrootdir/$vpath" if ($p eq "");
      $p=ow::tool::untaint($p);

      if ( -d "$webdiskrootdir/$vpath" ) {
         $selitem{".$p/"}=1;
      } elsif ( -e _ ) {
         $selitem{".$p"}=1;
      }
   }
   my @filelist=keys(%selitem);
   return($msg) if ($#filelist<0);

   my $dlname;
   if ($#filelist==0) {
      $dlname=safedlname($filelist[0]);
   } else {
      my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
      my @t=ow::datetime::seconds2array($localtime);
      $dlname=sprintf("%4d%02d%02d-%02d%02d", $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1]);
   }

   my @cmd;
   my $zipbin=ow::tool::findbin('zip');
   if ($zipbin ne '') {
      @cmd=($zipbin, '-ryq', '-');
      $dlname.=".zip";
   } else {
      my $gzipbin=ow::tool::findbin('gzip');
      my $tarbin=ow::tool::findbin('tar');
      if ($gzipbin ne '') {
         $ENV{'PATH'}=$gzipbin; $ENV{'PATH'}=~s|/gzip||; # for tar
         @cmd=($tarbin, '-zcpf', '-');
         $dlname.=".tgz";
      } else {
         @cmd=($tarbin, '-cpf', '-');
         $dlname.=".tar";
      }
   }

   chdir("$webdiskrootdir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $contenttype=ow::tool::ext2contenttype($dlname);

   local $|=1;
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;
   if ( $ENV{'HTTP_USER_AGENT'}=~/MSIE 5.5/ ) {	# ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$dlname"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$dlname"\n|;
   }
   print qq|\n|;

   writelog("webdisk download - ".join(' ', @filelist));
   writehistory("webdisk download - ".join(' ', @filelist));

   # set enviro's for cmd
   $ENV{'USER'}=$ENV{'LOGNAME'}=$user;
   $ENV{'HOME'}=$homedir;
   $<=$>;		# drop ruid by setting ruid = euid
   exec(@cmd, @filelist) or print qq|Error in executing |.join(' ', @cmd, @filelist);
}
########## END DOWNLOADFILES #####################################

########## DOWNLOADFILE ##########################################
sub downloadfile {
   my ($currentdir, $selitem)=@_;

   my $vpath=absolute_vpath($currentdir, $selitem);
   my $vpathstr=f2u($vpath);
   my $err=verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY) or
      return("$lang_err{'couldnt_read'} $vpathstr\n");

   my $dlname=safedlname($vpath);
   my $contenttype=ow::tool::ext2contenttype($vpath);
   my $length = ( -s "$webdiskrootdir/$vpath");

   # disposition:inline default to open
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;
   if ($contenttype=~/^text/ || $dlname=~/\.(jpe?g|gif|png|bmp)$/i) {
      print qq|Content-Disposition: inline; filename="$dlname"\n|;
   } else {
      if ( $ENV{'HTTP_USER_AGENT'}=~/MSIE 5.5/ ) { # ie5.5 is broken with content-disposition: attachment
         print qq|Content-Disposition: filename="$dlname"\n|;
      } else {
         print qq|Content-Disposition: attachment; filename="$dlname"\n|;
      }
   }

   if ($contenttype=~/^text/ && $length>512 &&
       is_http_compression_enabled()) {
      my $content;
      local $/; undef $/; $content=<F>; # no separator, read whole file at once
      close(F);
      $content=Compress::Zlib::memGzip($content);
      $length=length($content);
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
   my @p=split(/\//, $vpath);
   if (!defined $p[$#p-1] || $p[$#p-1] ne '.thumbnail') {
      writelog("webdisk download - $vpath");
      writehistory("webdisk download - $vpath ");
   }
   return;
}
########## END DOWNLOADFILE ######################################

########## PREVIEWFILE ###########################################
# relative links in html content will be converted so they can be
# redirect back to openwebmail-webdisk.pl with correct parmteters
sub previewfile {
   my ($currentdir, $selitem, $filecontent)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $vpathstr=f2u($vpath);
   my $err=verify_vpath($webdiskrootdir, $vpath);
   return("$lang_err{'access_denied'} ($vpathstr: $err)\n") if ($err);

   if ($filecontent eq "") {
      sysopen(F, "$webdiskrootdir/$vpath", O_RDONLY) or return("$lang_err{'couldnt_read'} $vpath\n");
      local $/; undef $/; $filecontent=<F>; # no separator, read whole file at once
      close(F);
   }

   # remove path from filename
   my $dlname=safedlname($vpath);
   my $contenttype=ow::tool::ext2contenttype($vpath);
   if ($vpath=~/\.(?:html?|js)$/i) {
      # use the dir where this html is as new currentdir
      my @p=path2array($vpath); pop @p;
      my $newdir='/'.join('/', @p);
      my $escapednewdir=ow::tool::escapeURL($newdir);
      my $preview_url=qq|$config{'ow_cgiurl'}/openwebmail-webdisk.pl?sessionid=$thissession|.
                      qq|&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid|.
                      qq|&amp;currentdir=$escapednewdir&amp;action=preview&amp;selitems=|;
      $filecontent=~s/\r\n/\n/g;
      $filecontent=linkconv($filecontent, $preview_url);
   }

   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|,
         qq|Content-Disposition: inline; filename="$dlname"\n|;

   my $length = length($filecontent);	# calc length since linkconv may change data length
   if ($contenttype=~/^text/ && $length>512 &&
       is_http_compression_enabled()) {
      $filecontent=Compress::Zlib::memGzip($filecontent);
      $length=length($filecontent);
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
   my ($html, $preview_url)=@_;
   $html=~s/( url| href| src| stylesrc| background)(="?)([^\<\>\s]+?)("?[>\s+])/_linkconv($1.$2, $3, $4, $preview_url)/igems;
   $html=~s/(window.open\()([^\<\>\s]+?)(\))/_linkconv2($1, $2, $3, $preview_url)/igems;
   return($html);
}

sub _linkconv {
   my ($prefix, $link, $postfix, $preview_url)=@_;
   if ($link=~m!^(?:mailto:|javascript:|#)!i) {
      return($prefix.$link.$postfix);
   }
   if ($link !~ m!^http://!i && $link!~m!^/!) {
       $link=$preview_url.$link;
   }
   return($prefix.$link.$postfix);
}
sub _linkconv2 {
   my ($prefix, $link, $postfix, $preview_url)=@_;
   if ($link=~m!^'?(?:http://|/)!i) {
      return($prefix.$link.$postfix);
   }
   $link=qq|'$preview_url'.$link|;
   return($prefix.$link.$postfix);
}
########## END PREVIEWFILE #######################################

########## UPLOADFILE ############################################
sub uploadfile {
   no strict 'refs';	# for $upload, which is fname and fhandle of the upload
   my ($currentdir, $upload)=@_;

   my $size=(-s $upload);
   if (!is_quota_available($size/1024)) {
      return("$lang_err{'quotahit_alert'}\n");
   }
   if ($config{'webdisk_uploadlimit'} &&
       $size/1024>$config{'webdisk_uploadlimit'} ) {
      return ("$lang_err{'upload_overlimit'} $config{'webdisk_uploadlimit'} $lang_sizes{'kb'}\n");
   }

   my ($fname, $wgethandle);
   if ($upload=~m!^(https?|ftp)://!) {
      my $wgetbin=ow::tool::findbin('wget');
      return("$lang_text{'program'} wget $lang_err{'doesnt_exist'}\n") if ($wgetbin eq '');

      my ($ret, $errmsg, $contenttype);
      ($ret, $errmsg, $contenttype, $wgethandle)=ow::wget::get_handle($wgetbin, $upload);
      return("$lang_wdbutton{'upload'} $upload $lang_text{'failed'}\n($errmsg)") if ($ret<0);

      my $ext=ow::tool::contenttype2ext($contenttype);
      $fname=$upload;				# url
      $fname=ow::tool::unescapeURL($fname);	# unescape str in url
      $fname=~s/\?.*$//;			# clean cgi parm in url
      $fname=~ s!/$!!; $fname =~ s|^.*/||;	# clear path in url
      $fname.=".$ext" if ($fname!~/\.$ext$/ && $ext ne 'bin');

   } else {
      if ($size==0) {
         return("$lang_wdbutton{'upload'} $lang_text{'failed'} (filesize is zero)\n");
      }
      $fname = $upload;
      # Convert :: back to the ' like it should be.
      $fname =~ s/::/'/g;
      # Trim the path info from the filename
      if ($prefs{'charset'} eq 'big5' || $prefs{'charset'} eq 'gb2312') {
         $fname=ow::tool::zh_dospath2fname($fname);	# dos path
      } else {
         $fname =~ s|^.*\\||;	# dos path
      }
      $fname =~ s|^.*/||;	# unix path
      $fname =~ s|^.*:||;	# mac path and dos drive
      $fname=u2f($fname);	# prefscharset to fscharset
   }

   my $vpath=ow::tool::untaint(absolute_vpath($currentdir, $fname));
   my $vpathstr=f2u($vpath);
   my $err=verify_vpath($webdiskrootdir, $vpath);
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
########## END UPLOADFILE ########################################

########## FILESELECT ############################################
sub dirfilesel {
   my ($action, $olddir, $newdir, $filesort, $page)=@_;
   my $showhidden=param('showhidden')||0;
   my $singlepage=param('singlepage')||0;

   # for sel_saveattfile, used in composemessage to save attfile
   my $attfile=param('attfile')||'';
   my $attachment_nodeid=param('attachment_nodeid');
   my $convfrom=param('convfrom')||'';

   # attname is from compose or readmessage, its charset may be different than prefs{charset}
   my $attnamecharset=param('attnamecharset')||$prefs{'charset'};
   my $attname=param('attname')||''; $attname=(iconv($attnamecharset, $prefs{'charset'}, $attname))[0];

   if ( $action eq "sel_saveattfile" && $attfile eq "") {
      autoclosewindow($lang_text{'savefile'}, $lang_err{'param_fmterr'});
   } elsif ( $action eq "sel_saveattachment" && $attachment_nodeid eq "") {
      autoclosewindow($lang_text{'savefile'}, $lang_err{'param_fmterr'});
   }

   my ($currentdir, $escapedcurrentdir, $msg);
   foreach my $dir ($newdir, $olddir, "/") {
      my $err=verify_vpath($webdiskrootdir, $dir);
      if ($err) {
         $msg .= "$lang_err{'access_denied'} (".f2u($dir).": $err)<br>\n"; next;
      }
      if (!opendir(D, "$webdiskrootdir/$dir")) {
         $msg .= "$lang_err{'couldnt_read'} ".f2u($dir)." ($!)<br>\n"; next;
      }
      $currentdir=$dir; last;
   }
   openwebmailerror(__FILE__, __LINE__, $msg) if ($currentdir eq '');
   $escapedcurrentdir=ow::tool::escapeURL($currentdir);

   my (%fsize, %fdate, %ftype, %flink);
   while( my $fname=readdir(D) ) {
      next if ( $fname eq "." || $fname eq ".." );
      next if ( (!$config{'webdisk_lshidden'} || !$showhidden) && $fname =~ /^\./ );
      if ( !$config{'webdisk_lsmailfolder'} ) {
          next if ( is_under_dotdir_or_folderdir("$webdiskrootdir/$currentdir/$fname") );
      }
      if ( -l "$webdiskrootdir/$currentdir/$fname" ) {	# symbolic link, aka:shortcut
         next if (!$config{'webdisk_lssymlink'});
         my $realpath=readlink("$webdiskrootdir/$currentdir/$fname");
         $realpath="$webdiskrootdir/$currentdir/$realpath" if ($realpath!~m!^/!);
         my $vpath=fullpath2vpath($realpath, $webdiskrootdir);
         if ($vpath ne '') {
            $flink{$fname}=" -> $vpath";
         } else {
            next if (!$config{'webdisk_allow_symlinkout'});
            if ($config{'webdisk_symlinkout_display'} eq 'path') {
               $flink{$fname}=" -> sys::$realpath";
            } elsif ($config{'webdisk_symlinkout_display'} eq '@') {
               $flink{$fname}='@';
            } else {
               $flink{$fname}='';
            }
         }
      }

      my ($st_dev,$st_ino,$st_mode,$st_nlink,$st_uid,$st_gid,$st_rdev,$st_size,
          $st_atime,$st_mtime,$st_ctime,$st_blksize,$st_blocks)= stat("$webdiskrootdir/$currentdir/$fname");
      if ( ($st_mode&0170000)==0040000 ) {
         $ftype{$fname}="d";
      } elsif ( ($st_mode&0170000)==0100000 ) {
         $ftype{$fname}="f";
      } else {	# unix specific filetype: fifo, socket, block dev, char dev..
         next;  # skip because dirfilesel is used for upload/download
      }
      $fsize{$fname}=$st_size;
      $fdate{$fname}=$st_mtime;
   }
   closedir(D);

   my @sortedlist;
   if ($filesort eq "name_rev") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $b cmp $a } keys(%ftype)
   } elsif ($filesort eq "size") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fsize{$a}<=>$fsize{$b} } keys(%ftype)
   } elsif ($filesort eq "size_rev") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fsize{$b}<=>$fsize{$a} } keys(%ftype)
   } elsif ($filesort eq "time") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fdate{$a}<=>$fdate{$b} } keys(%ftype)
   } elsif ($filesort eq "time_rev") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fdate{$b}<=>$fdate{$a} } keys(%ftype)
   } else { # filesort = name
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $ftype{$a} cmp $ftype{$b} || $a cmp $b } keys(%ftype)
   }

   my $totalpage= int(($#sortedlist+1)/10+0.999999); # use 10 instead of $prefs{'webdisk_dirnumitems'} for shorter page
   $totalpage=1 if ($totalpage==0);
   if ($currentdir ne $olddir) {
      $page=1;	# reset page number if change to new dir
   } else {
      $page=1 if ($page<1);
      $page=$totalpage if ($page>$totalpage);
   }

   my ($html, $temphtml);
   $html = applystyle(readtemplate("dirfilesel.template"));

   my $wd_url=qq|$config{ow_cgiurl}/openwebmail-webdisk.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;currentdir=$escapedcurrentdir|;
   if ($action eq "sel_saveattfile") {
      $html =~ s/\@\@\@SELTITLE\@\@\@/$lang_text{'savefile_towd'}/g;
      $wd_url.=qq|&amp;attfile=$attfile&attname=|.ow::tool::escapeURL($attname);
   } elsif ($action eq "sel_saveattachment") {
      $html =~ s/\@\@\@SELTITLE\@\@\@/$lang_text{'saveatt_towd'}/g;
      $wd_url.=qq|&amp;attachment_nodeid=$attachment_nodeid&amp;convfrom=$convfrom&amp;attname=|.ow::tool::escapeURL($attname);
   } elsif ($action eq "sel_addattachment") {
      $html =~ s/\@\@\@SELTITLE\@\@\@/$lang_text{'addatt_fromwd'}/g;
   } else {
      autoclosewindow("Unknown action: $action!");
   }
   my $wd_url_sort_page=qq|$wd_url&amp;showhidden=$showhidden&amp;singlepage=$singlepage&amp;filesort=$filesort&amp;page=$page|;

   if ($action eq "sel_addattachment") {
      $temphtml=start_form(-name=>'selform',
                           -action=>"javascript:addattachment_and_close();");
   } elsif ($action eq "sel_saveattfile") {
      $temphtml=start_form(-name=>'selform',
                           -action=>"javascript:saveattfile_and_close('$attfile');");
   } elsif ($action eq "sel_saveattachment") {
      $temphtml=start_form(-name=>'selform',
                           -action=>"javascript:saveattachment_and_close('$escapedfolder', '$escapedmessageid', '$attachment_nodeid');");
   }
   $html =~ s/\@\@\@STARTDIRFORM\@\@\@/$temphtml/g;

   my $p='/';
   $temphtml=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.ow::tool::escapeURL($p).qq|">/</a>\n|;
   foreach ( split(/\//, $currentdir) ) {
      next if ($_ eq "");
      $p.="$_/";
      $temphtml.=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.ow::tool::escapeURL($p).qq|">|.
                 ow::htmltext::str2html(f2u("$_/")).qq|</a>\n|;
   }
   $html =~ s/\@\@\@CURRENTDIR\@\@\@/$temphtml/g;

   my $newval=!$showhidden;
   if ($config{'webdisk_lshidden'}) {
      $html =~ s/\@\@\@SHOWHIDDENLABEL\@\@\@/$lang_text{'showhidden'}/g;
      $temphtml=checkbox(-name=>'showhidden',
                         -value=>'1',
                         -checked=>$showhidden,
                         -OnClick=>qq|window.location.href='$wd_url&amp;action=$action&amp;filesort=$filesort&amp;page=$page&amp;singlepage=$singlepage&amp;showhidden=$newval'; return false;|,
                         -override=>'1',
                         -label=>'');
      $html =~ s/\@\@\@SHOWHIDDENCHECKBOX\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@SHOWHIDDENLABEL\@\@\@//g;
      $html =~ s/\@\@\@SHOWHIDDENCHECKBOX\@\@\@//g;
   }
   $newval=!$singlepage;
   $temphtml=checkbox(-name=>'singlepage',
                      -value=>'1',
                      -checked=>$singlepage,
                      -OnClick=>qq|window.location.href='$wd_url&amp;action=$action&amp;filesort=$filesort&amp;page=$page&amp;showhidden=$showhidden&amp;singlepage=$newval'; return false;|,
                      -override=>'1',
                      -label=>'');
   $html =~ s/\@\@\@SINGLEPAGECHECKBOX\@\@\@/$temphtml/g;

   if ($currentdir eq "/") {
      $temphtml=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/disk.gif" align="absmiddle" border="0">|;
   } else {
      my $parentdir = absolute_vpath($currentdir, "..");
      $temphtml=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.ow::tool::escapeURL($parentdir).qq|">|.
                qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/dirup.gif" align="absmiddle" border="0">|.
                qq|</a>|;
   }
   $html =~ s/\@\@\@DIRUPLINK\@\@\@/$temphtml/g;

   my $wd_url_sort=qq|$wd_url&amp;action=$action&amp;gotodir=$escapedcurrentdir&amp;showhidden=$showhidden&amp;singlepage=$singlepage&amp;page=$page&amp;filesort|;

   if ($filesort eq "name") {
      $temphtml = qq|<a href="$wd_url_sort=name_rev">$lang_text{'filename'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($filesort eq "name_rev") {
      $temphtml = qq|<a href="$wd_url_sort=name">$lang_text{'filename'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$wd_url_sort=name">$lang_text{'filename'}</a>|;
   }
   $html =~ s/\@\@\@FILENAME\@\@\@/$temphtml/g;

   if ($filesort eq "size") {
      $temphtml = qq|<a href="$wd_url_sort=size_rev">$lang_text{'size'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($filesort eq "size_rev") {
      $temphtml = qq|<a href="$wd_url_sort=size">$lang_text{'size'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$wd_url_sort=size_rev">$lang_text{'size'}</a>|;
   }
   $html =~ s/\@\@\@FILESIZE\@\@\@/$temphtml/g;

   if ($filesort eq "time") {
      $temphtml = qq|<a href="$wd_url_sort=time_rev">$lang_text{'lastmodified'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($filesort eq "time_rev") {
      $temphtml = qq|<a href="$wd_url_sort=time">$lang_text{'lastmodified'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$wd_url_sort=time_rev">$lang_text{'lastmodified'}</a>|;
   }
   $html =~ s/\@\@\@FILEDATE\@\@\@/$temphtml/g;

   my $filelisthtml='';
   if ($#sortedlist>=0) {
      my $os=$^O||'generic';
      my ($i_first, $i_last)=(0, $#sortedlist);
      if (!$singlepage) {
         $i_first=($page-1)*10; # use 10 instead of $prefs{'webdisk_dirnumitems'} for shorter page
         $i_last=$i_first+10-1;
         $i_last=$#sortedlist if ($i_last>$#sortedlist);
      }
      foreach my $i ($i_first..$i_last) {
         my $fname=$sortedlist[$i];
         my $vpath=absolute_vpath($currentdir, $fname);
         my $vpathstr=f2u($vpath);
         my $escapedvpath=ow::tool::escapeURL($vpath);
         my $accesskeystr=$i%10+1;
         if ($accesskeystr == 10) {
            $accesskeystr=qq|accesskey="0"|;
         } elsif ($accesskeystr < 10) {
            $accesskeystr=qq|accesskey="$accesskeystr"|;
         }

         my ($imgstr, $namestr, $opstr, $onclickstr);
         $namestr=ow::htmltext::str2html(f2u($fname));
         $namestr.=ow::htmltext::str2html(f2u($flink{$fname})) if (defined $flink{$fname});
         if ($ftype{$fname} eq "d") {
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($fname, $ftype{$fname}, 0, $os).
                       qq|" align="absmiddle" border="0">|;
            }
            $namestr=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.
                     ow::tool::escapeURL("$fname").qq|" $accesskeystr>$imgstr <b>$namestr</b></a>|;
            $opstr=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.
                   ow::tool::escapeURL("$fname").qq|"><b>&lt;$lang_text{'dir'}&gt;</b></a>|;
            $onclickstr=qq|onClick="window.location.href='$wd_url_sort_page&amp;action=$action&amp;gotodir=|.
                        ow::tool::escapeURL("$fname").qq|';"|;

         } else {
            my $is_txt= (-T "$webdiskrootdir/$currentdir/$fname");
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($fname, $ftype{$fname}, $is_txt, $os).
                       qq|" align="absmiddle" border="0">|;
            }
            $namestr=qq|<a href=#here onClick="filldestname('$vpathstr', '$escapedvpath');" $accesskeystr>$imgstr $namestr</a>|;
            $onclickstr=qq|onClick="filldestname('$vpathstr', '$escapedvpath')"|;
         }

         my $right='right'; $right='left' if ($ow::lang::RTL{$prefs{'locale'}});
         $namestr=qq|<table width="100%" border=0 cellspacing=0 cellpadding=0><tr>|.
                  qq|<td>$namestr</td>\n<td align="$right" nowrap>$opstr</td></tr></table>|;

         my $sizestr=qq|<a title="|.lenstr($fsize{$fname},1).qq|">$fsize{$fname}</a>|;

         my $datestr;
         if (defined $fdate{$fname}) {
            $datestr=ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial($fdate{$fname}),
                                      $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                      $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'});
         }

         my ($tr_bgcolorstr, $td_bgcolorstr);
         if ($prefs{'uselightbar'}) {
            $tr_bgcolorstr=qq|bgcolor=$style{tablerow_light} |.
                           qq|onMouseOver='this.style.backgroundColor=$style{tablerow_hicolor};' |.
                           qq|onMouseOut='this.style.backgroundColor=$style{tablerow_light};' |.
                           qq|$onclickstr |;
           $td_bgcolorstr='';
         } else {
            $tr_bgcolorstr='';
            $td_bgcolorstr=qq|bgcolor=|.($style{"tablerow_dark"},$style{"tablerow_light"})[$i%2];
         }
         $filelisthtml.=qq|<tr $tr_bgcolorstr>\n|.
                        qq|<td $td_bgcolorstr>$namestr</td>\n|.
                        qq|<td $td_bgcolorstr align="right">$sizestr</td>\n|.
                        qq|<td $td_bgcolorstr align="center">$datestr</td>\n|.
                        qq|</tr>\n\n|;
      }
   } else {
      my $td_bgcolorstr = qq|bgcolor=|.$style{"tablerow_light"};
      $filelisthtml.=qq|<tr>\n|.
                     qq|<td $td_bgcolorstr align=center>|.
                     qq|<table><tr><td><font color=#aaaaaa>$lang_text{'noitemfound'}</font></td</tr></table>|.
                     qq|</td>\n|.
                     qq|<td $td_bgcolorstr>&nbsp;</td>\n|.
                     qq|<td $td_bgcolorstr>&nbsp;</td>\n|.
                     qq|</tr>\n\n|;
   }
   undef(%fsize); undef(%fdate); undef(%ftype); undef(%flink);	# relase mem if possible

   if (!$singlepage) {
      my $wd_url_page=qq|$wd_url&amp;action=$action&amp;gotodir=$escapedcurrentdir&amp;showhidden=$showhidden&amp;singlepage=$singlepage&amp;filesort=$filesort&amp;page|;

      if ($page>1) {
         my $gif="left.gif"; $gif="right.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "&lt;", qq|accesskey="U" href="$wd_url_page=|.($page-1).qq|"|).qq|\n|;
      } else {
         my $gif="left-grey.gif"; $gif="right-grey.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "-", "").qq|\n|;
      }
      $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml/g;

      if ($page<$totalpage) {
         my $gif="right.gif"; $gif="left.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "&gt;", qq|accesskey="D" href="$wd_url_page=|.($page+1).qq|"|).qq|\n|;
      } else {
         my $gif="right-grey.gif"; $gif="left-grey.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "-", "").qq|\n|;
      }
      $html =~ s/\@\@\@RIGHTPAGECONTROL\@\@\@/$temphtml/g;

      my $p_first=$page-4; $p_first=1 if ($p_first<1);
      my $p_last=$p_first+9;
      if ($p_last>$totalpage) {
         $p_last=$totalpage;
         while ($p_last-$p_first<9 && $p_first>1) {
            $p_first--;
         }
      }

      $temphtml='';
      for my $p ($p_first..$p_last) {
         if ($p == $page) {
            $temphtml .= qq|<b>$p</b>&nbsp;\n|;
         } else {
            $temphtml .= qq|<a href="$wd_url_page=$p">$p</a>&nbsp;\n|;
         }
      }
      $html =~ s/\@\@\@PAGELINKS\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@//g;
      $html =~ s/\@\@\@RIGHTPAGECONTROL\@\@\@//g;
      $html =~ s/\@\@\@PAGELINKS\@\@\@//g;
   }

   if ($action eq "sel_saveattfile" || $action eq "sel_saveattachment") {
      my $attname_fs=u2f($attname);
      my $vpath=absolute_vpath($currentdir, $attname_fs);
      my $vpathstr=f2u($vpath);
      $temphtml = textfield(-name=>'destname',
                            -default=>"",
                            -size=>'35',
                            -accesskey=>'N',
                            -value=>$vpathstr,	# TUNG
                            -override=>'1');
   } else {
      $temphtml = textfield(-name=>'destname',
                            -default=>"",
                            -size=>'35',
                            -accesskey=>'N',
                            -value=>'',
                            -disabled=>'1',
                            -override=>'1').
                  ow::tool::hiddens(destname2=>'');	# destname2 is used to store escaped value of destname for composeform
   }
   $html =~ s/\@\@\@DESTNAMEFIELD\@\@\@/$temphtml/g;

   $temphtml='';
   # we return false for the okbutton click event because we do all things in javascript
   # and we dn't want the current page to be reloaded
   if ($action eq "sel_addattachment") {
      $temphtml.=submit(-name=>'okbutton',
                        -onClick=>"addattachment_and_close(); return false;",
                        -value=>$lang_text{'ok'});
   } elsif ($action eq "sel_saveattfile") {
      $temphtml.=submit(-name=>'okbutton',
                        -onClick=>"saveattfile_and_close('".f2u($attfile)."'); return false;",
                        -value=>$lang_text{'ok'});
   } elsif ($action eq "sel_saveattachment") {
      $temphtml.=submit(-name=>'okbutton',
                        -onClick=>"saveattachment_and_close('$escapedfolder', '$messageid', '$attachment_nodeid'); return false;",
                        -value=>$lang_text{'ok'});
   }
   $temphtml.=submit(-name=>'cencelbutton',
                     -onClick=>'window.close();',
                     -value=>$lang_text{'cancel'});
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/g;

   $temphtml=end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-viewatt.pl",
                          -name=>'saveattfileform').
               ow::tool::hiddens(action=>'saveattfile',
                                 sessionid=>$thissession,
                                 attfile=>'',
                                 webdisksel=>'').
               end_form();
   $html =~ s/\@\@\@SAVEATTFILEFORM\@\@\@/$temphtml/;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-viewatt.pl",
                          -name=>'saveattachmentform').
               ow::tool::hiddens(action=>'saveattachment',
                                 sessionid=>$thissession,
                                 folder=>'',
                                 message_id=>'',
                                 attachment_nodeid=>'saveattfile',
                                 webdisksel=>'').
               end_form();
   $html =~ s/\@\@\@SAVEATTACHMENTFORM\@\@\@/$temphtml/;

   # since $filelisthtml may be large, we put it into $html as late as possible
   $html =~ s/\@\@\@FILELIST\@\@\@/$filelisthtml/; undef($filelisthtml);

   my $cookie = cookie( -name  => "ow-currentdir-$domain-$user",
                        -value => $currentdir,
                        -path  => '/');
   httpprint([-cookie=>[$cookie]], [htmlheader(), $html, htmlfooter(2)]);
}
########## END FILESELECT ########################################

########## SHOWDIR ###############################################
sub showdir {
   my ($olddir, $newdir, $filesort, $page, $msg)=@_;
   my $showthumbnail=param('showthumbnail')||0;
   my $showhidden=param('showhidden')||0;
   my $singlepage=param('singlepage')||0;
   my $searchtype=param('searchtype')||'';
   my $keyword=param('keyword')||''; $keyword=~s/[`;\|]//g;
   my $escapedkeyword=ow::tool::escapeURL($keyword);

   my $quotahit_deltype='';
   if ($quotalimit>0 && $quotausage>$quotalimit &&
       ($config{'delmail_ifquotahit'}||$config{'delfile_ifquotahit'}) ) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      if ($quotausage>$quotalimit) {

         my (@validfolders, $inboxusage, $folderusage);
         getfolders(\@validfolders, \$inboxusage, \$folderusage);

         if ($config{'delfile_ifquotahit'} && $folderusage < $quotausage*0.5) {
            $quotahit_deltype='quotahit_delfile';
            my $webdiskrootdir=$homedir.absolute_vpath("/", $config{'webdisk_rootpath'});
            cutdirfiles(($quotausage-$quotalimit*0.9)*1024, $webdiskrootdir);

            $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
         }
      }
   }

   my ($currentdir, $escapedcurrentdir, @list);
   if ($keyword ne '') {	# olddir = newdir if keyword is supplied for searching
      my $err=filelist_of_search($searchtype, $keyword, $olddir, dotpath('webdisk.cache'), \@list);
      if ($err) {
         $keyword=""; $msg.=$err;
      } else {
         $currentdir=$olddir;
      }
   }
   if ($keyword eq '') {
      foreach my $dir ($newdir, $olddir, "/") {
         my $err=verify_vpath($webdiskrootdir, $dir);
         if ($err) {
            $msg .= "$lang_err{'access_denied'} (".f2u($dir).": $err)\n"; next;
         }
         if (!opendir(D, "$webdiskrootdir/$dir")) {
            $msg .= "$lang_err{'couldnt_read'} ".f2u($dir)." ($!)\n"; next;
         }
         @list=readdir(D);
         closedir(D);
         $currentdir=$dir;
         last;
      }
      openwebmailerror(__FILE__, __LINE__, $msg) if ($currentdir eq '');
   }
   $escapedcurrentdir=ow::tool::escapeURL($currentdir);

   my (%fsize, %fdate, %fowner, %fmode, %fperm, %ftype, %flink);
   my ($dcount, $fcount, $sizecount)=(0,0,0);
   foreach my $p (@list) {
      next if ( $p eq "." || $p eq "..");
      my $vpath=absolute_vpath($currentdir, $p);
      if ( !$config{'webdisk_lsmailfolder'} ) {
          next if ( is_under_dotdir_or_folderdir("$webdiskrootdir/$vpath") );
      }
      my $fname=$vpath; $fname=~s|.*/||;
      next if ( (!$config{'webdisk_lshidden'}||!$showhidden) && $fname =~ /^\./ );
      if ( -l "$webdiskrootdir/$vpath" ) {	# symbolic link, aka:shortcut
         next if (!$config{'webdisk_lssymlink'});
         my $realpath=readlink("$webdiskrootdir/$vpath");
         $realpath="$webdiskrootdir/$vpath/../$realpath" if ($realpath!~m!^/!);
         my $vpath2=fullpath2vpath($realpath, $webdiskrootdir);
         if ($vpath2 ne '') {
            $flink{$p}=" -> $vpath2";
         } else {
            next if (!$config{'webdisk_allow_symlinkout'});
            if ($config{'webdisk_symlinkout_display'} eq 'path') {
               $flink{$p}=" -> sys::$realpath";
            } elsif ($config{'webdisk_symlinkout_display'} eq '@') {
               $flink{$p}='@';
            } else {
               $flink{$p}='';
            }
         }
      }

      my ($st_dev,$st_ino,$st_mode,$st_nlink,$st_uid,$st_gid,$st_rdev,$st_size,
          $st_atime,$st_mtime,$st_ctime,$st_blksize,$st_blocks)= stat("$webdiskrootdir/$vpath");
      if ( ($st_mode&0170000)==0040000 ) {
         $ftype{$p}="d"; $dcount++;
      } elsif ( ($st_mode&0170000)==0100000 ) {
         $ftype{$p}="f"; $fcount++; $sizecount+=$st_size;
      } else {	# unix specific filetype: fifo, socket, block dev, char dev..
         next if (!$config{'webdisk_lsunixspec'});
         $ftype{$fname}="u";
      }
      my $r=(-r _)?'r':'-';
      my $w=(-w _)?'w':'-';
      my $x=(-x _)?'x':'-';
      $fperm{$p}="$r$w$x";
      $fsize{$p}=$st_size;
      $fdate{$p}=$st_mtime;
      $fowner{$p}=getpwuid($st_uid).':'.getgrgid($st_gid);
      $fmode{$p}=sprintf("%04o", $st_mode&07777);
   }
   close(D);

   my @sortedlist;
   if ($filesort eq "name_rev") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $b cmp $a } keys(%ftype)
   } elsif ($filesort eq "size") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fsize{$a}<=>$fsize{$b} } keys(%ftype)
   } elsif ($filesort eq "size_rev") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fsize{$b}<=>$fsize{$a} } keys(%ftype)
   } elsif ($filesort eq "time") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fdate{$a}<=>$fdate{$b} } keys(%ftype)
   } elsif ($filesort eq "time_rev") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fdate{$b}<=>$fdate{$a} } keys(%ftype)
   } elsif ($filesort eq "perm") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fperm{$a} cmp $fperm{$b} } keys(%ftype)
   } elsif ($filesort eq "perm_rev") {
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $fperm{$b} cmp $fperm{$a} } keys(%ftype)
   } else { # filesort = name
      @sortedlist= sort { $ftype{$a} cmp $ftype{$b} || $ftype{$a} cmp $ftype{$b} || $a cmp $b } keys(%ftype)
   }

   my $totalpage= int(($#sortedlist+1)/($prefs{'webdisk_dirnumitems'}||10)+0.999999);
   $totalpage=1 if ($totalpage==0);
   if ($currentdir ne $olddir) {
      $page=1;	# reset page number if change to new dir
   } else {
      $page=1 if ($page<1);
      $page=$totalpage if ($page>$totalpage);
   }

   my ($html, $temphtml);
   $html = applystyle(readtemplate("dir.template"));

   my $wd_url=qq|$config{'ow_cgiurl'}/openwebmail-webdisk.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;currentdir=$escapedcurrentdir&amp;showthumbnail=$showthumbnail&amp;showhidden=$showhidden&amp;singlepage=$singlepage|;
   my $wd_url_sort_page=qq|$wd_url&amp;filesort=$filesort&amp;page=$page|;

   $temphtml .= iconlink("home.gif" ,"$lang_text{'backto'} $lang_text{'homedir'}", qq|accesskey="G" href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.ow::tool::escapeURL('/').qq|"|);
   $temphtml .= iconlink("refresh.gif" ,"$lang_wdbutton{'refresh'} ", qq|accesskey="R" href="$wd_url_sort_page&amp;action=userrefresh&amp;gotodir=$escapedcurrentdir"|);

   $temphtml .= "&nbsp;\n";

   if ($config{'enable_webmail'}) {
      my $folderstr=ow::htmltext::str2html($lang_folders{$folder}||f2u($folder));
      if ($messageid eq "") {
         $temphtml .= iconlink("owm.gif", "$lang_text{'backto'} $folderstr",
                               qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
      } else {
         $temphtml .= iconlink("owm.gif", "$lang_text{'backto'} $folderstr",
                               qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
      }
   }
   if ($config{'enable_addressbook'}) {
      $temphtml .= iconlink("addrbook.gif", $lang_text{'addressbook'}, qq|accesskey="A" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
   }
   if ($config{'enable_calendar'}) {
      $temphtml .= iconlink("calendar.gif", $lang_text{'calendar'}, qq|accesskey="K" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=$prefs{'calendar_defaultview'}&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   }
   if ( $config{'enable_sshterm'}) {
      if ( -r "$config{'ow_htmldir'}/applet/mindterm2/mindterm.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm2/ssh2.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      } elsif ( -r "$config{'ow_htmldir'}/applet/mindterm/mindtermfull.jar" ) {
         $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm/ssh.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
      }
   }
   if ( $config{'enable_preference'}) {
      $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;prefs_caller=webdisk"|);
   }
   $temphtml .= iconlink("logout.gif", "$lang_text{'logout'} $prefs{'email'}", qq|accesskey="X" href="$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;action=logout"|);

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   if ($config{'quota_module'} ne "none") {
      $temphtml='';
      my $overthreshold=($quotalimit>0 && $quotausage/$quotalimit>$config{'quota_threshold'}/100);
      if ($config{'quota_threshold'}==0 || $overthreshold) {
         $temphtml = "$lang_text{'quotausage'}: ".lenstr($quotausage*1024,1);
      }
      if ($overthreshold) {
         $temphtml.=" (".(int($quotausage*1000/$quotalimit)/10)."%) ";
      }
   } else {
      $temphtml="&nbsp;";
   }
   $html =~ s/\@\@\@QUOTAUSAGE\@\@\@/$temphtml/;

   $temphtml = start_multipart_form(-name=>'dirform',
				    -action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl") .
               ow::tool::hiddens(sessionid=>$thissession,
                                 folder=>$escapedfolder,
                                 message_id=>$messageid,
                                 currentdir=>ow::tool::escapeURL($currentdir),
                                 gotodir=>ow::tool::escapeURL($currentdir),
                                 filesort=>$filesort,
                                 page=>$page,
                                 permission=>'');
   $html =~ s/\@\@\@STARTDIRFORM\@\@\@/$temphtml/g;

   if ($keyword ne '') {
      $temphtml=qq|$lang_text{'search'} &nbsp;|;
   } else {
      $temphtml=qq|$lang_text{'dir'} &nbsp;|;
   }

   my $p='/';
   $temphtml.=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.ow::tool::escapeURL($p).qq|">/</a>\n|;
   foreach ( split(/\//, $currentdir) ) {
      next if ($_ eq "");
      $p.="$_/";
      $temphtml.=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.ow::tool::escapeURL($p).qq|">|.
                 ow::htmltext::str2html(f2u("$_/")).qq|</a>\n|;
   }
   $html =~ s/\@\@\@CURRENTDIR\@\@\@/$temphtml/g;

   if ($config{'webdisk_allow_thumbnail'}) {
      $html =~ s/\@\@\@SHOWTHUMBLABEL\@\@\@/$lang_text{'showthumbnail'}/g;
      $temphtml=checkbox(-name=>'showthumbnail',
                         -value=>'1',
                         -checked=>$showthumbnail,
                         -OnClick=>'document.dirform.submit();',
                         -override=>'1',
                         -label=>'');
      $html =~ s/\@\@\@SHOWTHUMBCHECKBOX\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@SHOWTHUMBLABEL\@\@\@//g;
      $html =~ s/\@\@\@SHOWTHUMBCHECKBOX\@\@\@//g;
   }

   if ($config{'webdisk_lshidden'}) {
      $html =~ s/\@\@\@SHOWHIDDENLABEL\@\@\@/$lang_text{'showhidden'}/g;
      $temphtml=checkbox(-name=>'showhidden',
                         -value=>'1',
                         -checked=>$showhidden,
                         -OnClick=>'document.dirform.submit();',
                         -override=>'1',
                         -label=>'');
      $html =~ s/\@\@\@SHOWHIDDENCHECKBOX\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@SHOWHIDDENLABEL\@\@\@//g;
      $html =~ s/\@\@\@SHOWHIDDENCHECKBOX\@\@\@//g;
   }

   $temphtml=checkbox(-name=>'singlepage',
                      -value=>'1',
                      -checked=>$singlepage,
                      -OnClick=>'document.dirform.submit();',
                      -override=>'1',
                      -label=>'');
   $html =~ s/\@\@\@SINGLEPAGECHECKBOX\@\@\@/$temphtml/g;

   if ($prefs{'iconset'}!~/^Text\./) {
      if ($currentdir eq "/") {
         $temphtml=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/disk.gif" align="absmiddle" border="0">|;
      } else {
         my $parentdir = absolute_vpath($currentdir, "..");
         $temphtml=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.ow::tool::escapeURL($parentdir).qq|">|.
                   qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/dirup.gif" align="absmiddle" border="0">|.
                   qq|</a>|;
      }
   } else {
      $temphtml='';
   }
   $html =~ s/\@\@\@DIRUPLINK\@\@\@/$temphtml/g;

   my $wd_url_sort=qq|$wd_url&amp;action=showdir&amp;gotodir=$escapedcurrentdir&amp;page=$page&amp;searchtype=$searchtype&amp;keyword=$escapedkeyword&amp;filesort|;

   if ($filesort eq "name") {
      $temphtml = qq|<a href="$wd_url_sort=name_rev">$lang_text{'filename'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($filesort eq "name_rev") {
      $temphtml = qq|<a href="$wd_url_sort=name">$lang_text{'filename'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$wd_url_sort=name">$lang_text{'filename'}</a>|;
   }
   $html =~ s/\@\@\@FILENAME\@\@\@/$temphtml/g;

   if ($filesort eq "size") {
      $temphtml = qq|<a href="$wd_url_sort=size_rev">$lang_text{'size'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($filesort eq "size_rev") {
      $temphtml = qq|<a href="$wd_url_sort=size">$lang_text{'size'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$wd_url_sort=size_rev">$lang_text{'size'}</a>|;
   }
   $html =~ s/\@\@\@FILESIZE\@\@\@/$temphtml/g;

   if ($filesort eq "time") {
      $temphtml = qq|<a href="$wd_url_sort=time_rev">$lang_text{'lastmodified'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($filesort eq "time_rev") {
      $temphtml = qq|<a href="$wd_url_sort=time">$lang_text{'lastmodified'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$wd_url_sort=time_rev">$lang_text{'lastmodified'}</a>|;
   }
   $html =~ s/\@\@\@FILEDATE\@\@\@/$temphtml/g;

   if ($filesort eq "perm") {
      $temphtml = qq|<a href="$wd_url_sort=perm_rev" title="$lang_text{'permission'}">$lang_text{'perm'}</a> |.iconlink("up.gif", "^", "");
   } elsif ($filesort eq "perm_rev") {
      $temphtml = qq|<a href="$wd_url_sort=perm" title="$lang_text{'permission'}">$lang_text{'perm'}</a> |.iconlink("down.gif", "v", "");
   } else {
      $temphtml = qq|<a href="$wd_url_sort=perm_rev" title="$lang_text{'permission'}">$lang_text{'perm'}</a>|;
   }
   $html =~ s/\@\@\@FILEPERM\@\@\@/$temphtml/g;

   $temphtml = checkbox(-name=>'allbox',
                        -value=>'1',
                        -onClick=>"CheckAll($prefs{'uselightbar'});",
                        -label=>'',
                        -override=>'1');
   $html =~ s/\@\@\@ALLBOXCHECKBOX\@\@\@/$temphtml/;

   my $filelisthtml;
   if ($#sortedlist>=0) {
      my $os=$^O||'generic';
      my ($i_first, $i_last)=(0, $#sortedlist);
      if (!$singlepage) {
         $i_first=($page-1)*$prefs{'webdisk_dirnumitems'};
         $i_last=$i_first+$prefs{'webdisk_dirnumitems'}-1;
         $i_last=$#sortedlist if ($i_last>$#sortedlist);
      }
      foreach my $i ($i_first..$i_last) {
         my $p=$sortedlist[$i];
         my $accesskeystr=$i%10+1;
         if ($accesskeystr == 10) {
            $accesskeystr=qq|accesskey="0"|;
         } elsif ($accesskeystr < 10) {
            $accesskeystr=qq|accesskey="$accesskeystr"|;
         }

         my ($imgstr, $namestr, $opstr);
         if ($ftype{$p} eq "d") {
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($p, $ftype{$p}, 0, $os).
                       qq|" align="absmiddle" border="0">|;
            }
            $namestr=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.
                     ow::tool::escapeURL($p).qq|" title="$fowner{$p}" $accesskeystr>$imgstr <b> |.
                     ow::htmltext::str2html(f2u($p));
            $namestr.=ow::htmltext::str2html(f2u($flink{$p})) if (defined $flink{$p});
            $namestr.=qq|</b></a>|;
            $opstr=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.
                   ow::tool::escapeURL($p).qq|"><b>&lt;$lang_text{'dir'}&gt;</b></a>|;

         } else {
            my $is_txt= (-T "$webdiskrootdir/$currentdir/$p" || $p=~/\.(txt|html?)$/i);
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($p, $ftype{$p}, $is_txt, $os).
                       qq|" align="absmiddle" border="0">|;
            }
            my $blank=""; $blank="target=_blank" if ($is_txt || $p=~/\.(jpe?g|gif|png|bmp)$/i);

            my ($dname, $fname);
            if ($p=~m|^(.*/)([^/]*)$|) {
               ($dname, $fname)=($1, $2);
            } else {
               ($dname, $fname)=('', $p);
            }

            my $a=qq|<a href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl/|.ow::tool::escapeURL($fname).
                  qq|?sessionid=$thissession&amp;currentdir=$escapedcurrentdir&amp;|.
                  qq|action=download&amp;selitems=|.ow::tool::escapeURL($p).
                  qq|" title="$fowner{$p}" $accesskeystr $blank>|;

            $namestr="$a$imgstr</a> ";
            if ($dname ne '') {
               $namestr.=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.
                         ow::tool::escapeURL($dname).qq|" $accesskeystr><b>|.
                         ow::htmltext::str2html(f2u($dname)).qq|</b> </a>|;
            }
            $namestr.=$a.ow::htmltext::str2html(f2u($fname));
            $namestr.=ow::htmltext::str2html(f2u($flink{$p})) if (defined $flink{$p});
            $namestr.=qq|</a>|;

            if ($p=~/\.(?:pdf|e?ps)$/i ) {
               if (!$config{'webdisk_readonly'} &&
                   (!$quotalimit||$quotausage<$quotalimit) ) {
                  my $mk='mkpdf'; $mk='mkps' if ($p=~/\.pdf$/i);
                  my $onclickstr;
                  if ($prefs{'webdisk_confirmcompress'}) {
                     my $pstr=f2u($p); $pstr=~s/'/\\'/g;	# escape for javascript
                     $onclickstr=qq|onclick="return confirm('$lang_wdbutton{$mk}? ($pstr)');"|;
                  }
                  $opstr.=qq|<a href="$wd_url_sort_page&amp;action=$mk&amp;selitems=|.
                         ow::tool::escapeURL($p).qq|" $onclickstr>[$lang_wdbutton{$mk}]</a>|;
               }
            } elsif ($is_txt) {
               if ($p=~/\.html?$/i) {
                  $opstr=qq|<a href=#here onClick="window.open('|.
                         qq|$wd_url&amp;action=preview&amp;selitems=|.ow::tool::escapeURL($p).
                         qq|','_previewfile','width=720,height=550,scrollbars=yes,resizable=yes,location=no');|.
                         qq|">[$lang_wdbutton{'preview'}]</a>|;
               }
               if (!$config{'webdisk_readonly'} &&
                   (!$quotalimit||$quotausage<$quotalimit) ) {
                  $opstr.=qq|<a href=#here onClick="window.open('|.
                          qq|$wd_url&amp;action=editfile&amp;selitems=|.ow::tool::escapeURL($p).
                          qq|','_editfile','width=720,height=550,scrollbars=yes,resizable=yes,location=no');|.
                          qq|">[$lang_wdbutton{'edit'}]</a>|;
               }
            } elsif ($p=~/\.(?:zip|rar|arj|ace|lzh|t[bg]z|tar\.g?z|tar\.bz2?|tne?f)$/i ) {
               $opstr=qq|<a href=#here onClick="window.open('|.
                      qq|$wd_url&amp;action=listarchive&amp;selitems=|.ow::tool::escapeURL($p).
                      qq|','_editfile','width=780,height=550,scrollbars=yes,resizable=yes,location=no');|.
                      qq|">[$lang_wdbutton{'listarchive'}]</a>|;
               if (!$config{'webdisk_readonly'} &&
                   (!$quotalimit||$quotausage<$quotalimit) ) {
                  my $onclickstr;
                  if ($prefs{'webdisk_confirmcompress'}) {
                     my $pstr=f2u($p); $pstr=~s/'/\\'/g;	# escape for javascript
                     $onclickstr=qq|onclick="return confirm('$lang_wdbutton{extract}? ($pstr)');"|;
                  }
                  my $allow_extract=1;
                  if ($p=~/\.(?:t[bg]z|tar\.g?z|tar\.bz2?)$/i && !$config{'webdisk_allow_untar'} ||
                      $p=~/\.zip$/i && !$config{'webdisk_allow_unzip'} ||
                      $p=~/\.rar$/i && !$config{'webdisk_allow_unrar'} ||
                      $p=~/\.arj$/i && !$config{'webdisk_allow_unarj'} ||
                      $p=~/\.ace$/i && !$config{'webdisk_allow_unace'} ||
                      $p=~/\.lzh$/i && !$config{'webdisk_allow_unlzh'} ) {
                     $allow_extract=0;
                  }
                  if ($allow_extract) {
                     $opstr.=qq| <a href="$wd_url_sort_page&amp;action=decompress&amp;selitems=|.
                          ow::tool::escapeURL($p).qq|" $onclickstr>[$lang_wdbutton{'extract'}]</a>|;
                  }
               }
            } elsif ($p=~/\.(?:g?z|bz2?)$/i ) {
               if (!$config{'webdisk_readonly'} &&
                   (!$quotalimit||$quotausage<$quotalimit) ) {
                  my $onclickstr;
                  if ($prefs{'webdisk_confirmcompress'}) {
                     my $pstr=f2u($p); $pstr=~s/'/\\'/g;	# escape for javascript
                     $onclickstr=qq|onclick="return confirm('$lang_wdbutton{decompress}? ($pstr)');"|;
                  }
                  $opstr=qq|<a href="$wd_url_sort_page&amp;action=decompress&amp;selitems=|.
                         ow::tool::escapeURL($p).qq|" $onclickstr>[$lang_wdbutton{'decompress'}]</a>|;
               }
            } elsif ($p=~/\.(?:doc|dot)$/i ) {
               $opstr=qq|<a href=#here onClick="window.open('|.
                      qq|$wd_url&amp;action=wordpreview&amp;selitems=|.ow::tool::escapeURL($p).
                      qq|','_wordpreview','width=780,height=550,scrollbars=yes,resizable=yes,location=no');|.
                      qq|">[$lang_wdbutton{'preview'}]</a>|;

            } elsif ($p=~/\.(?:jpe?g|gif|png|bmp|tif)$/i ) {
               if ($showthumbnail) {
                  my $thumbnail=path2thumbnail($p);
                  $thumbnail=$p if ($fsize{$p}<2048);	# show image itself if size <2k
                  if ( -f "$webdiskrootdir/$currentdir/$thumbnail") {
                     my $fname=$p; $fname=~s|.*/||g;
                     $opstr=qq|<a href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl/|.ow::tool::escapeURL($fname).
                            qq|?sessionid=$thissession&amp;currentdir=$escapedcurrentdir&amp;|.
                            qq|action=download&amp;selitems=|.ow::tool::escapeURL($p).qq|" $blank>|.
                            qq|<IMG SRC="$wd_url_sort_page&amp;action=download&amp;selitems=|.
                            ow::tool::escapeURL($thumbnail).qq|" align="absmiddle" border="0"></a>|;
                  }
               }
            }
         }

         my $right='right'; $right='left' if ($ow::lang::RTL{$prefs{'locale'}});
         $namestr=qq|<table width="100%" border=0 cellspacing=0 cellpadding=0><tr>|.
                  qq|<td>$namestr</td>\n<td align="$right" nowrap>$opstr</td></tr></table>|;

         my $sizestr=qq|<a title="|.lenstr($fsize{$p},1).qq|">$fsize{$p}</a>|;

         my $datestr;
         if (defined $fdate{$p}) {
            $datestr=ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial($fdate{$p}),
                                      $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                      $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'});
         }

         $fperm{$p}=~/^(.)(.)(.)$/;
         my $permstr=qq|<a title="$fmode{$p}">$1 $2 $3</a>|;

         my ($tr_bgcolorstr, $td_bgcolorstr, $checkbox_onclickstr);
         if ($prefs{'uselightbar'}) {
            $tr_bgcolorstr=qq|bgcolor=$style{tablerow_light} |.
                           qq|onMouseOver='this.style.backgroundColor=$style{tablerow_hicolor};' |.
                           qq|onMouseOut='this.style.backgroundColor = document.getElementById("$i").checked? $style{tablerow_dark}:$style{tablerow_light};' |.
                           qq|onClick='if (!document.layers) {var cb=document.getElementById("$i"); cb.checked=!cb.checked}' |.
                           qq|id='tr_$i' |;
            $td_bgcolorstr='';
            $checkbox_onclickstr='if (!document.layers) {this.checked=!this.checked}';	# disable checkbox change since it is already done once by tr onclick event
         } else {
            $tr_bgcolorstr='';
            $td_bgcolorstr=qq|bgcolor=|.($style{"tablerow_dark"},$style{"tablerow_light"})[$i%2];
            $checkbox_onclickstr='';
         }

         my $pstr=ow::htmltext::str2html(f2u($p));
         $filelisthtml.=qq|<tr $tr_bgcolorstr>\n|.
                        qq|<td $td_bgcolorstr>$namestr</td>\n|.
                        qq|<td $td_bgcolorstr align="right">$sizestr</td>\n|.
                        qq|<td $td_bgcolorstr align="center">$datestr</td>\n|.
                        qq|<td $td_bgcolorstr align="center">$permstr</td>\n|.
                        qq|<td $td_bgcolorstr align="center">|.
                        checkbox(-name=>'selitems',
                                 -value=>ow::tool::escapeURL($p),
                                 -override=>'1',
                                 -label=>'',
                                 -onclick=> $checkbox_onclickstr,
                                 -id=>$i).
                        qq|<input type="hidden" name="p_$i" id="p_$i" value="$pstr">|.
                        qq|</td>\n</tr>\n\n|;
      }
   } else {
      my $td_bgcolorstr = qq|bgcolor=|.$style{"tablerow_light"};
      $filelisthtml.=qq|<tr>\n|.
                     qq|<td $td_bgcolorstr align=center>|.
                     qq|<table><tr><td><font color=#aaaaaa>$lang_text{'noitemfound'}</font></td</tr></table>|.
                     qq|</td>\n|.
                     qq|<td $td_bgcolorstr>&nbsp;</td>\n|.
                     qq|<td $td_bgcolorstr>&nbsp;</td>\n|.
                     qq|<td $td_bgcolorstr>&nbsp;</td>\n|.
                     qq|<td $td_bgcolorstr>&nbsp;</td>\n|.
                     qq|</tr>\n\n|;
   }
   undef(%fsize); undef(%fdate); undef(%fperm); undef(%ftype); undef(%flink);	# release mem if possible

   if (!$singlepage) {
      my $wd_url_page=qq|$wd_url&amp;action=showdir&amp;gotodir=$escapedcurrentdir&amp;filesort=$filesort&amp;searchtype=$searchtype&amp;keyword=$escapedkeyword&amp;page|;
      if ($page>1) {
         my $gif="left.gif"; $gif="right.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "&lt;", qq|accesskey="U" href="$wd_url_page=|.($page-1).qq|"|).qq|\n|;
      } else {
         my $gif="left-grey.gif"; $gif="right-grey.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "-", "").qq|\n|;
      }
      $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml/g;

      if ($page<$totalpage) {
         my $gif="right.gif"; $gif="left.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "&gt;", qq|accesskey="D" href="$wd_url_page=|.($page+1).qq|"|).qq|\n|;
      } else {
         my $gif="right-grey.gif"; $gif="left-grey.gif" if ($ow::lang::RTL{$prefs{'locale'}});
         $temphtml = iconlink($gif, "-", "").qq|\n|;
      }
      $html =~ s/\@\@\@RIGHTPAGECONTROL\@\@\@/$temphtml/g;

      my $p_first=$page-4; $p_first=1 if ($p_first<1);
      my $p_last=$p_first+9;
      if ($p_last>$totalpage) {
         $p_last=$totalpage;
         while ($p_last-$p_first<9 && $p_first>1) {
            $p_first--;
         }
      }

      $temphtml='';
      for my $p ($p_first..$p_last) {
         if ($p == $page) {
            $temphtml .= qq|<b>$p</b>&nbsp;\n|;
         } else {
            $temphtml .= qq|<a href="$wd_url_page=$p">$p</a>&nbsp;\n|;
         }
      }
      $html =~ s/\@\@\@PAGELINKS\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@//g;
      $html =~ s/\@\@\@RIGHTPAGECONTROL\@\@\@//g;
      $html =~ s/\@\@\@PAGELINKS\@\@\@//g;
   }

   $temphtml = sprintf("%d %s, %d %s",
               $dcount, ($dcount>1)?$lang_text{'dirs'}:$lang_text{'dir'},
               $fcount, ($fcount>1)?$lang_text{'files'}:$lang_text{'file'});
   $temphtml.= ", $totalpage $lang_text{'page'}" if ($totalpage>9);
   $html =~ s/\@\@\@INFOCOUNT\@\@\@/$temphtml/g;

   $temphtml = lenstr($sizecount,1);
   $html =~ s/\@\@\@INFOSIZE\@\@\@/$temphtml/g;


   $temphtml = textfield(-name=>'destname',
                         -default=>"",
                         -size=>'35',
                         -accesskey=>'N',
                         -override=>'1').qq|\n|;
   $html =~ s/\@\@\@DESTNAMEFIELD\@\@\@/$temphtml/g;

   $temphtml=submit(-name=>'chdirbutton',
                     -accesskey=>'J',
                     -onClick=>"if (document.dirform.keyword.value != '') {return true;}; return destnamefilled('$lang_text{dest_of_chdir}');",
                     -value=>$lang_wdbutton{'chdir'});
   if (!$config{'webdisk_readonly'} &&
       (!$quotalimit||$quotausage<$quotalimit) ) {
      $temphtml.=submit(-name=>'mkdirbutton',
                        -accesskey=>'M',
                        -onClick=>"return destnamefilled('$lang_text{name_of_newdir}');",
                        -value=>$lang_wdbutton{'mkdir'});
      $temphtml.=submit(-name=>'newfilebutton',
                        -accesskey=>'F',
                        -onClick=>"return destnamefilled('$lang_text{name_of_newfile}');",
                        -value=>$lang_wdbutton{'newfile'});
      $temphtml.=qq|\n|;

   }
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/g;

   $temphtml='';
   if (!$config{'webdisk_readonly'}) {
      if (!$quotalimit||$quotausage<$quotalimit) {
         $temphtml.=submit(-name=>'copybutton',
                           -accesskey=>'C',
                           -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_thecopy}') && opconfirm('$lang_wdbutton{copy}', $prefs{webdisk_confirmmovecopy}));",
                           -value=>$lang_wdbutton{'copy'});
         $temphtml.=submit(-name=>'movebutton',
                           -accesskey=>'V',
                           -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_themove}') && opconfirm('$lang_wdbutton{move}', $prefs{webdisk_confirmmovecopy}));",
                           -value=>$lang_wdbutton{'move'});
         if ($config{'webdisk_allow_symlinkcreate'} &&
             $config{'webdisk_lssymlink'}) {
            $temphtml.=submit(-name=>'symlinkbutton',
                              -accesskey=>'N',
                              -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_themove}') && opconfirm('$lang_wdbutton{symlink}', $prefs{webdisk_confirmmovecopy}));",
                              -value=>$lang_wdbutton{'symlink'});
         }
      }
      $temphtml.=submit(-name=>'deletebutton',
                        -accesskey=>'Y',
                        -onClick=>"return (anyfileselected() && opconfirm('$lang_wdbutton{delete}', $prefs{webdisk_confirmdel}));",
                        -value=>$lang_wdbutton{'delete'});
      $temphtml.=submit(-name=>'chmodbutton',
                        -accesskey=>'O',
                        -onClick=>"return (anyfileselected() && chmodinput());",
                        -value=>$lang_wdbutton{'chmod'});
      $temphtml.=qq|&nbsp;\n|;
   }

   if (!$config{'webdisk_readonly'} &&
       (!$quotalimit||$quotausage<$quotalimit) ) {
      $temphtml.=submit(-name=>'gzipbutton',
                        -accesskey=>'Z',
                        -onClick=>"return(anyfileselected() && opconfirm('$lang_wdbutton{gzip}', $prefs{webdisk_confirmcompress}));",
                        -value=>$lang_wdbutton{'gzip'});
      $temphtml.=submit(-name=>'mkzipbutton',
                        -accesskey=>'Z',
                        -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_thezip}') && opconfirm('$lang_wdbutton{mkzip}', $prefs{webdisk_confirmcompress}));",
                        -value=>$lang_wdbutton{'mkzip'});
      $temphtml.=submit(-name=>'mktgzbutton',
                        -accesskey=>'Z',
                        -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_thetgz}') && opconfirm('$lang_wdbutton{mktgz}', $prefs{webdisk_confirmcompress}));",
                        -value=>$lang_wdbutton{'mktgz'});
      if ($config{'webdisk_allow_thumbnail'}) {
         $temphtml.=submit(-name=>'mkthumbnailbutton',
                           -accesskey=>'Z',
                           -onClick=>"return(anyfileselected() && opconfirm('$lang_wdbutton{mkthumbnail}', $prefs{webdisk_confirmcompress}));",
                           -value=>$lang_wdbutton{'mkthumbnail'});
      }
      $temphtml.=qq|&nbsp;\n|;
   }

   $temphtml.=submit(-name=>'downloadbutton',
                     -accesskey=>'L',
                     -onClick=>'return anyfileselected();',
                     -value=>$lang_wdbutton{'download'});
   $html =~ s/\@\@\@BUTTONS2\@\@\@/$temphtml/g;

   my %searchtypelabels = ('filename'=>$lang_text{'filename'},
                           'textcontent'=>$lang_text{'textcontent'});
   $temphtml = popup_menu(-name=>'searchtype',
                           -default=>'filename',
                           -values=>['filename', 'textcontent'],
                           -labels=>\%searchtypelabels);
   $temphtml .= textfield(-name=>'keyword',
                         -default=>$keyword,
                         -size=>'20',
                         -accesskey=>'S',
                         -onChange=>'document.dirform.searchbutton.focus();',
                         -override=>'1');
   $temphtml .= submit(-name=>'searchbutton',
                       -value=>$lang_text{'search'});
   $html =~ s/\@\@\@SEARCHFILEFIELD\@\@\@/$temphtml/g;

   if (!$config{'webdisk_readonly'} &&
       (!$quotalimit||$quotausage<$quotalimit) ) {
      templateblock_enable($html, 'UPLOAD');
      $temphtml = filefield(-name=>'upload',
                            -default=>"",
                            -size=>'25',
                            -accesskey=>'W',
                            -override=>'1');
      $temphtml .= submit(-name=>'uploadbutton',
                          -onClick=>'return uploadfilled();',
                          -value=>$lang_wdbutton{'upload'});
      $html =~ s/\@\@\@UPLOADFILEFIELD\@\@\@/$temphtml/g;
   } else {
      templateblock_disable($html, 'UPLOAD');
   }

   if ($quotalimit>0 && $quotausage>=$quotalimit) {
      $msg.="$lang_err{'quotahit_alert'}\n";
   }
   $temphtml = textarea(-name=>'msg',
                        -default=>$msg,
                        -rows=>'3',
                        -columns=>'78',
                        -wrap=>'hard',
                        -override=>'1');
   $html =~ s/\@\@\@MSGTEXTAREA\@\@\@/$temphtml/g;

   $temphtml=end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   # show quotahit del warning
   if ($quotahit_deltype ne '') {
      my $msg=qq|<font size="-1" color="#cc0000">$lang_err{$quotahit_deltype}</font>|;
      $msg=~s/\@\@\@QUOTALIMIT\@\@\@/$config{'quota_limit'}$lang_sizes{'kb'}/;
      $html.=readtemplate('showmsg.js').
             qq|<script language="JavaScript">\n<!--\n|.
             qq|showmsg('$prefs{"charset"}', '$lang_text{"quotahit"}', '$msg', '$lang_text{"close"}', '_quotahit_del', 400, 100, 60);\n|.
             qq|//-->\n</script>\n|;
   }

   # since $filelisthtml may be large, we put it into $html as late as possible
   $html =~ s/\@\@\@FILELIST\@\@\@/$filelisthtml/g; undef($filelisthtml);

   # since some browser always treat refresh directive as realtive url.
   # we use relative path for refresh
   my $refreshinterval=$prefs{'refreshinterval'}*60;
   my $relative_url="$config{'ow_cgiurl'}/openwebmail-webdisk.pl";
   $relative_url=~s!/.*/!!g;
   my $cookie = cookie( -name  => "ow-currentdir-$domain-$user",
                        -value => $currentdir,
                        -path  => '/');
   httpprint([-cookie=>[$cookie],
              -Refresh=>"$refreshinterval;URL=$relative_url?sessionid=$thissession&folder=$escapedfolder&message_id=$escapedmessageid&action=showdir&currentdir=$escapedcurrentdir&gotodir=$escapedcurrentdir&showthumbnail=$showthumbnail&showhidden=$showhidden&singlepage=$singlepage&filesort=$filesort&page=$page&searchtype=$searchtype&keyword=$escapedkeyword&session_noupdate=1"],
             [htmlheader(),
              htmlplugin($config{'header_pluginfile'}, $config{'header_pluginfile_charset'}, $prefs{'charset'}),
              $html,
              htmlplugin($config{'footer_pluginfile'}, $config{'footer_pluginfile_charset'}, $prefs{'charset'}),
              htmlfooter(2)] );
}

sub filelist_of_search {
   my ($searchtype, $keyword, $vpath, $cachefile, $r_list)=@_;
   my $keyword_fs=(iconv($prefs{'charset'}, $prefs{'fscharset'}, $keyword))[0];
   my $keyword_utf8=(iconv($prefs{'charset'}, 'utf-8', $keyword))[0];

   my $metainfo=join("@@@", $searchtype, $keyword_fs, $vpath);
   my $cache_metainfo;
   my $vpathstr=f2u($vpath);

   $cachefile=ow::tool::untaint($cachefile);
   ow::filelock::lock($cachefile, LOCK_EX) or
      return("$lang_err{'couldnt_writelock'} $cachefile\n");

   if ( -e $cachefile ) {
      sysopen(CACHE, $cachefile, O_RDONLY) or  return("$lang_err{'couldnt_read'} $cachefile!");
      $cache_metainfo=<CACHE>;
      chomp($cache_metainfo);
      close(CACHE);
   }
   if ( $cache_metainfo ne $metainfo ) {
      my (@cmd, $stdout, $stderr, $exit, $sig);

      chdir("$webdiskrootdir/$vpath") or
         return("$lang_err{'couldnt_chdirto'} $vpathstr\n");

      my $findbin=ow::tool::findbin('find');
      return("$lang_text{'program'} find $lang_err{'doesnt_exist'}\n") if ($findbin eq '');

      open(F, "-|") or
         do { open(STDERR,">/dev/null"); exec($findbin, ".", "-print"); exit 9 };
      my @f=<F>; close(F);

      foreach my $fname (@f) {
         $fname=~s|^\./||; $fname=~s/\s+$//;
         if ($searchtype eq "filename") {	# search keyword in file name
            push(@{$r_list}, $fname) if ($fname=~/$keyword_fs/i);

         } else {				# search keyword in file content
            next if (!-f "$webdiskrootdir/$vpath/$fname");
            my $ext=$fname; $ext=~s!.*/!!; $ext=~m!.*\.(.*)!; $ext=$1;
            my $contenttype=ow::tool::ext2contenttype($fname);
            if ($contenttype=~/msword/) {
               my $antiwordbin=ow::tool::findbin('antiword');
               next if ($antiwordbin eq '');
               my ($stdout, $stderr, $exit, $sig)=ow::execute::execute
  			($antiwordbin, '-m', 'UTF-8.txt', "$webdiskrootdir/$vpath/$fname");
               next if ($exit||$sig);
               ($stdout)=iconv('utf-8', $prefs{'charset'}, $stdout);
               push(@{$r_list}, $fname) if ($stdout=~/$keyword_utf8/i);

            } elsif ($contenttype=~/text/|| $ext eq '') {
               # only read leading 4MB
               my $buff; sysopen(F, "$webdiskrootdir/$vpath/$fname", O_RDONLY); read(F, $buff, 4*1024*1024); close(F);
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
      $_=<CACHE>;
      while (<CACHE>) {
         chomp;
         push (@{$r_list}, $_);
      }
      close(CACHE);
   }

   ow::filelock::lock($cachefile, LOCK_UN);

   return;
}
########## END SHOWDIR ###########################################

########## WD_EXECUTE ############################################
# a wrapper for execute() to handle the dirty work
sub webdisk_execute {
   my ($opstr, @cmd)=@_;
   my ($stdout, $stderr, $exit, $sig)=ow::execute::execute(@cmd);

   # try to conv realpath in stdout/stderr back to vpath
   foreach ($stdout, $stderr) {
      s!(?:$webdiskrootdir/+|^$webdiskrootdir/*| $webdiskrootdir/*)! /!g;
      s!^\s*!!mg; s!/+!/!g;
   }
   ($stdout, $stderr)=iconv($prefs{'fscharset'}, $prefs{'charset'}, $stdout, $stderr);

   my $opresult;
   if ($exit||$sig) {
      $opresult=$lang_text{'failed'};
   } else {
      $opresult=$lang_text{'succeeded'};
      writelog("webdisk execute - ".join(' ', @cmd));
      writehistory("webdisk execute - ".join(' ', @cmd));
   }
   if ($sig) {
      return "$opstr $opresult (exit status $exit, terminated by signal $sig)\n$stdout$stderr";
   } else {
      return "$opstr $opresult (exit status $exit)\n$stdout$stderr";
   }
}
########## END WD_EXECUTE ########################################

########## FINDICON ##############################################
sub findicon {
   my ($fname, $ftype, $is_txt, $os)=@_;

   return ("dir.gif") if ($ftype eq "d");
   return ("sys.gif") if ($ftype eq "u");

   $_=lc($fname);

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
      return("audio.gif")  if (/\.(mid[is]?|mod|au|cda|aif[fc]?|voc|wav|snd)$/ );
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
########## END FINDICON ##########################################

########## IS_QUOTA_AVAILABLE ####################################
sub is_quota_available {
   my $writesize=$_[0];
   if ($quotalimit>0 && $quotausage+$writesize>$quotalimit) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
      return 0 if ($quotausage+$writesize>$quotalimit);
   }
   return 1;
}
########## END IS_QUOTA_AVAILABLE ################################
