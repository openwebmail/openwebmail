#!/usr/bin/suidperl -T
#
# openwebmail-webdisk.pl - web disk program
#
# 2002/12/30 tung@turtle.ee.ncku.edu.tw
#
# To prevent shell escape, all external commands are executed through exec
# with parameters in an array, this makes perl call execvp directly instead
# of invoking the /bin/sh
#
# Path names from CGI are treated as virtual paths under the user homedir.
# All pathname will be prefixed with $homedir when passing to external command
# for security
#
# To disable the use of symbolic link, please refer to openwebmail.conf.help
# for options webdisk_lssymlink and webdisk_allow_symlinkouthome
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
use IPC::Open3;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

require "ow-shared.pl";
require "filelock.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);
use vars qw($webdiskusage);

openwebmail_init();
verifysession();

# openwebmail_init() will set umask to 0077 to protect mail folder data.
# set umask back to 0022 here dir & files are created as world readable
umask(0022); 

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_wdbutton %lang_text %lang_err);	# defined in lang/xy
use vars qw($messageid $escapedmessageid);

########################## MAIN ##############################
$messageid = param("message_id");
$escapedmessageid = escapeURL($messageid);

my $action = param("action");

my $currentdir;
if (defined(param('currentdir')) && param('currentdir') ne "") {
   $currentdir = param('currentdir'); 
} else {
   $currentdir = cookie("$user-currentdir"),
}

my $gotodir = param('gotodir'); 
my @selitems = (param('selitems')); 
my $destname = param('destname')||''; 
my $filesort = param('filesort')|| 'name';
my $page = param('page') || 1;

$webdiskusage=0;
if ($config{'webdisk_quota'}>0) {
   my ($stdout, $stderr, $exit, $sig)=execute('/usr/bin/du', '-sk', $homedir);
   $webdiskusage=$1 if ($stdout=~/(\d+)/);
}

# all path in param are treated as virtual path under $homedir.
$currentdir = absolute_vpath("/", $currentdir);
$gotodir = absolute_vpath($currentdir, $gotodir);

my $msg=verify_vpath($homedir, $currentdir);
openwebmailerror($msg) if ($msg);
($currentdir =~ /^(.+)$/) && ($currentdir = $1);  # untaint ...

if (! $config{'enable_webdisk'}) {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

if ($action eq "mkdir" || defined(param('mkdirbutton')) ) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=createdir($currentdir, $destname) if ($destname);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "newfile" || defined(param('newfilebutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=createfile($currentdir, $destname) if ($destname);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "delete" || defined(param('deletebutton'))) {
   $msg=deletedirfiles($currentdir, @selitems) if ($#selitems>=0);
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "copy" || defined(param('copybutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=copymovedirfiles("copy", $currentdir, $destname, @selitems) if ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "move" || defined(param('movebutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=copymovedirfiles("move", $currentdir, $destname, @selitems) if ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "editfile" || defined(param('editbutton'))) {
   if ($config{'webdisk_readonly'}) {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'webdisk_readonly'});
   } elsif (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'}) {
      if ($#selitems==0) {
         editfile($currentdir, $selitems[0]);
      } else {
         autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'onefileonly'});
      }
   } else {
      autoclosewindow($lang_text{'quota_hit'}, $lang_err{'webdisk_hitquota'});
   }

} elsif ($action eq "savefile" || defined(param('savebutton'))) {
   if ($config{'webdisk_readonly'}) {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'webdisk_readonly'});
   } elsif (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'}) {
      savefile($currentdir, $destname, param('filecontent')) if ($destname);
   } else {
      autoclosewindow($lang_text{'quota_hit'}, $lang_err{'webdisk_hitquota'});
   }

} elsif ($action eq "gzip" || defined(param('gzipbutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=compressfiles("gzip", $currentdir, '', @selitems) if ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mkzip" || defined(param('mkzipbutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=compressfiles("mkzip", $currentdir, $destname, @selitems) if ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "mktgz" || defined(param('mktgzbutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=compressfiles("mktgz", $currentdir, $destname, @selitems) if ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "decompress" || defined(param('decompressbutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      if ($#selitems==0) {
         $msg=decompressfile($currentdir, $selitems[0]);
      } else {
         $msg="$lang_wdbutton{'decompress'} - $lang_err{'onefileonly'}";
      }
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "listarchive" || defined(param('listarchivebutton'))) {
   if ($#selitems==0) {
      $msg=listarchive($currentdir, $selitems[0]);
   } else {
      $msg="$lang_wdbutton{'listarchive'} - $lang_err{'onefileonly'}";
   }

} elsif ($action eq "mkthumbnail" || defined(param('mkthumbnailbutton'))) {
   if ($config{'webdisk_allow_thumbnail'} && !$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $msg=makethumbnail($currentdir, @selitems) if ($#selitems>=0);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "preview") {
   my $vpath=absolute_vpath($currentdir, $selitems[0]);
   my $filecontent=param('filecontent');
   if ($#selitems==0) {
      if ( $filecontent) {
         $msg=previewfile($currentdir, $selitems[0], $filecontent);
      } elsif ( -d "$homedir/$vpath" ) {
         showdir($currentdir, $vpath, $filesort, $page, $msg); $msg='';
      } else {
         $msg=previewfile($currentdir, $selitems[0], '');
      }
   } else {
      $msg=$lang_err{'no_file_todownload'};
   }
   openwebmailerror($msg) if ($msg);

} elsif ($action eq "download" || defined(param('downloadbutton'))) {
   if ($#selitems>0) {
      $msg=downloadfiles($currentdir, @selitems);
   } elsif ($#selitems==0) {
      my $vpath=absolute_vpath($currentdir, $selitems[0]);
      if ( -d "$homedir/$vpath" ) {
         $msg=downloadfiles($currentdir, @selitems);
      } else {
         $msg=downloadfile($currentdir, $selitems[0]);
      }
   } else {
      $msg=$lang_err{'no_file_todownload'};
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg) if ($msg);

} elsif ($action eq "upload" || defined(param('uploadbutton'))) {
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      my $upload=param('upload');	# name and handle of the upload file
      $msg=uploadfile($currentdir, $upload) if ($upload);
   }
   showdir($currentdir, $gotodir, $filesort, $page, $msg);

} elsif ($action eq "sel_addattachment") { 	# used in composemsg to add attachment
   dirfilesel($action, $currentdir, $gotodir, $filesort, $page);

} elsif ($action eq "sel_saveattfile" ||	# used in composemsg to save attfile
         $action eq "sel_saveattachment") {	# used in readmsg to save attachment
   if ($config{'webdisk_readonly'}) {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'webdisk_readonly'});
   } elsif (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'}) {
      dirfilesel($action, $currentdir, $gotodir, $filesort, $page);
   } else {
      autoclosewindow($lang_text{'quota_hit'}, $lang_err{'webdisk_hitquota'});
   }

} elsif ($action eq "showdir" || $action eq "" || defined(param('chdirbutton')))  {
# put chdir in last or user will be matched by ($action eq "") when clicking button
   if ($destname) {	# chdir
      $destname = absolute_vpath($currentdir, $destname);
      showdir($currentdir, $destname, $filesort, $page, $msg);
   } else {		# showdir, refresh
      showdir($currentdir, $gotodir, $filesort, $page, $msg);
   }

} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}
########################## END MAIN ##########################

######################## CREATEDIR ##############################
sub createdir {
   my ($currentdir, $destname)=@_;

   my $vpath=absolute_vpath($currentdir, $destname);
   ($vpath =~ /^(.+)$/) && ($vpath = $1);  # untaint ...
   my $err=verify_vpath($homedir, $vpath);
   return ("$err\n") if ($err);

   if ( -e "$homedir/$vpath") {
      return("$lang_text{'dir'} $vpath $lang_err{'already_exists'}\n") if (-d _);
      return("$lang_text{'file'} $vpath $lang_err{'already_exists'}\n");
   } else {
      if (mkdir("$homedir/$vpath", 0755)) {
         writelog("webdisk - mkdir $vpath");
         writehistory("webdisk - mkdir $vpath");
         return("$lang_wdbutton{'mkdir'} $vpath\n");
      } else {
         return("$lang_err{'couldnt_open'} $vpath ($!)\n");
      }
   }
}
######################## END CREATEDIR ##########################

########################## NEWFILE ##############################
sub createfile {
   my ($currentdir, $destname)=@_;

   my $vpath=absolute_vpath($currentdir, $destname);
   ($vpath =~ /^(.+)$/) && ($vpath = $1);  # untaint ...
   my $err=verify_vpath($homedir, $vpath);
   return ("$err\n") if ($err);

   if ( -e "$homedir/$vpath") {
      return("$lang_text{'dir'} $vpath $lang_err{'already_exists'}\n") if (-d _);
      return("$lang_text{'file'} $vpath $lang_err{'already_exists'}\n");
   } else {
      if (open(F, ">$homedir/$vpath")) {
         print F "";
         close(F);
         writelog("webdisk - createfile $vpath");
         writehistory("webdisk - createfile $vpath");
         return("$lang_wdbutton{'newfile'} $vpath\n");
      } else {
         return("$lang_err{'couldnt_open'} $vpath ($!)\n");
      }
   }
}
########################## END NEWFILE ##########################

########################## DELETEDIRFILES #######################
sub deletedirfiles {
   my ($currentdir, @selitems)=@_;
   my ($msg, $err);

   my @filelist;
   foreach (@selitems) {
      my $vpath=absolute_vpath($currentdir, $_);
      ($vpath =~ /^(.+)$/) && ($vpath = $1);  # untaint ...
      $err=verify_vpath($homedir, $vpath);
      if ($err) {
         $msg.="$err\n"; next;
      }
      if (!-e "$homedir/$vpath") {
         $msg.="$vpath $lang_text{'doesnt_exist'}\n"; next;
      }
      if (-f _ && $vpath=~/\.(jpe?g|gif|png|bmp|tif)$/i) {
         my $thumbnail=path2thumbnail("$homedir/$vpath");
         push(@filelist, $thumbnail) if (-f $thumbnail);
      }
      push(@filelist, "$homedir/$vpath");
   }
   return($msg) if ($#filelist<0);

   my @cmd;
   my $rmbin=findbin('rm');
   return("$lang_text{'program'} rm $lang_err{'doesnt_exist'}\n") if (!$rmbin);
   @cmd=($rmbin, '-Rfv');

   chdir("$homedir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   $msg.=webdisk_execute($lang_wdbutton{'delete'}, @cmd, @filelist);
   return($msg);
}
########################## END DELETEDIRFILES #######################

########################## COPYDIRFILES ##############################
sub copymovedirfiles {
   my ($op, $currentdir, $destname, @selitems)=@_;
   my ($msg, $err);

   my $vpath2=absolute_vpath($currentdir, $destname);
   ($vpath2 =~ /^(.+)$/) && ($vpath2 = $1);  # untaint ...
   $err=verify_vpath($homedir, $vpath2);
   return ("$err\n") if ($err);

   if ($#selitems>0) {
      if (!-e "$homedir/$vpath2") {
         return("$vpath2 $lang_err{'doesnt_exist'}\n");
      } elsif (!-d _) {
         return("$vpath2 $lang_err{'isnt_a_dir'}\n");
      }
   }

   my @filelist;
   foreach (@selitems) {
      my $vpath1=absolute_vpath($currentdir, $_);
      ($vpath1 =~ /^(.+)$/) && ($vpath1 = $1);  # untaint ...
      $err=verify_vpath($homedir, $vpath1);
      if ($err) {
         $msg.="$err\n"; next;
      }
      if (! -e "$homedir/$vpath1") {
         $msg.="$vpath1 $lang_text{'doesnt_exist'}\n"; next;
      }
      next if ($vpath1 eq $vpath2);
      push(@filelist, "$homedir/$vpath1");
   }
   return($msg) if ($#filelist<0);

   my @cmd;
   if ($op eq "copy") {
      my $cpbin=findbin('cp');
      return("$lang_text{'program'} cp $lang_err{'doesnt_exist'}\n") if (!$cpbin);
      @cmd=($cpbin, '-pRfv');
   } elsif ($op eq "move") {
      my $mvbin=findbin('mv');
      return("$lang_text{'program'} mv $lang_err{'doesnt_exist'}\n") if (!$mvbin);
      @cmd=($mvbin, '-fv');
   } else {
      return($msg);
   }

   chdir("$homedir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   $msg.=webdisk_execute($lang_wdbutton{$op}, @cmd, @filelist, "$homedir/$vpath2");
   return($msg);
}
######################### END COPYDIRFILES ########################

########################## EDITFILE ##############################
sub editfile {
   my ($currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $content;

   my $html = readtemplate("editfile.template");
   my $temphtml;
   $html = applystyle($html);

   if ( -d "$homedir/$vpath") {
      autoclosewindow($lang_wdbutton{'edit'}, $lang_err{'edit_notfordir'});
   } elsif ( -f "$homedir/$vpath" ) {
      my $err=verify_vpath($homedir, $vpath);
      autoclosewindow($lang_wdbutton{'edit'}, $err) if ($err);

      if (!open(F, "$homedir/$vpath")) {
         autoclosewindow($lang_wdbutton{'edit'}, "$lang_err{'couldnt_open'} $vpath");
      }
      filelock("$homedir/$vpath", LOCK_SH|LOCK_NB) or
         autoclosewindow($lang_text{'edit'}, "$lang_err{'couldnt_locksh'} $homedir/$vpath!");
      while (<F>) { $content .= $_; }
      close(F);
      filelock("$homedir/$vpath", LOCK_UN);

      $content =~ s|<\s*/\s*textarea\s*>|</ESCAPE_TEXTAREA>|gi;
   }

   $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl",
                             -name=>'editfile') .
                   hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1') .
                   hidden(-name=>'action',
                          -value=>'savefile',
                          -override=>'1') .
                   hidden(-name=>'currentdir',
                          -value=>$currentdir,
                          -override=>'1');
   $html =~ s/\@\@\@STARTEDITFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'destname',
                         -default=>$vpath,
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

   $temphtml = button(-name=>"cancelbutton",
                      -value=>$lang_text{'cancel'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl",
                         -name=>'previewform',
                         -target=>'_preview').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'action',
                      -value=>'preview',
                      -override=>'1') .
               hidden(-name=>'currentdir',
                      -value=>$currentdir,
                      -override=>'1').
               hidden(-name=>'selitems',
                      -default=>'',
                      -override=>'1').
               hidden(-name=>'filecontent',
                      -default=>'',
                      -override=>'1');
   $html =~ s/\@\@\@STARTPREVIEWFORM\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   # put this at last to avoid @@@pattern@@@ replacement happens on $content
   $temphtml = textarea(-name=>'filecontent',
                        -default=>$content,
                        -rows=>$prefs{'webdisk_fileeditrows'},
                        -columns=>$prefs{'webdisk_fileeditcolumns'},
                        -wrap=>'soft',
                        -override=>'1');
   $html =~ s/\@\@\@FILECONTENT\@\@\@/$temphtml/;

   printheader();
   print $html;
   printfooter(2);
}
######################## END EDITFILE ##############################

########################## SAVEFILE ##############################
sub savefile {
   my ($currentdir, $destname, $content)=@_;
   my $vpath=absolute_vpath($currentdir, $destname);
   ($vpath =~ /^(.+)$/) && ($vpath = $1);  # untaint ...
   my $err=verify_vpath($homedir, $vpath);
   autoclosewindow($lang_text{'savefile'}, $err, 60) if ($err);

   $content =~ s|</ESCAPE_TEXTAREA>|</textarea>|gi;
   $content =~ s/\r\n/\n/g;
   $content =~ s/\r/\n/g;

   if (!open(F, ">$homedir/$vpath") ) {
      autoclosewindow($lang_text{'savefile'}, "$lang_text{'savefile'} $lang_text{'failed'} ($vpath: $!)", 60);
   }
   filelock("$homedir/$vpath", LOCK_EX|LOCK_NB) or
      autoclosewindow($lang_text{'savefile'}, "$lang_err{'couldnt_lock'} $homedir/$vpath!", 60);
   print F "$content";
   close(F);
   filelock("$homedir/$vpath", LOCK_UN);

   writelog("webdisk - save file $vpath");
   writehistory("webdisk - save file $vpath");

   my $jscode=qq|window.opener.document.dirform.submit();|;
   autoclosewindow($lang_text{'savefile'}, "$lang_text{'savefile'} $lang_text{'succeeded'} ($vpath)", 8, $jscode);
}
########################## END SAVEFILE ##############################

########################## COMPRESSFILES ##############################
sub compressfiles {	# pack files with zip or tgz (tar -zcvf)
   my ($ztype, $currentdir, $destname, @selitems)=@_;
   my ($vpath2, $msg, $err);

   if ($ztype eq "mkzip" || $ztype eq "mktgz" ) {
      $vpath2=absolute_vpath($currentdir, $destname);
      ($vpath2 =~ /^(.+)$/) && ($vpath2 = $1);  # untaint ...
      $err=verify_vpath($homedir, $vpath2);
      return ("$err\n") if ($err);
      if ( -e "$homedir/$vpath2") {
         return("$lang_text{'dir'} $vpath2 $lang_err{'already_exists'}\n") if (-d _);
         return("$lang_text{'file'} $vpath2 $lang_err{'already_exists'}\n");
      }
   }

   my %selitem;
   foreach (@selitems) {
      my $vpath=absolute_vpath($currentdir, $_);
      $err=verify_vpath($homedir, $vpath);
      if ($err) {
         $msg.="$err\n"; next;
      }

      # use relative path to currentdir since we will chdir to homedir/currentdir before compress
      my $p=fullpath2vpath("$homedir/$vpath", "$homedir/$currentdir");
      # use absolute path if relative to homedir/currentdir is not possible
      $p="$homedir/$vpath" if (!$p);
      ($p =~ /^(.+)$/) && ($p = $1);  # untaint ...

      if ( -d "$homedir/$vpath" ) {
         $selitem{".$p/"}=1;
      } elsif ( -e _ ) {
         $selitem{".$p"}=1;
      }
   }
   my @filelist=keys(%selitem);
   return($msg) if ($#filelist<0);

   my @cmd;
   if ($ztype eq "gzip") {
      my $gzipbin=findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if (!$gzipbin);
      @cmd=($gzipbin, '-rq');
   } elsif ($ztype eq "mkzip") {
      my $zipbin=findbin('zip');
      return("$lang_text{'program'} zip $lang_err{'doesnt_exist'}\n") if (!$zipbin);
      @cmd=($zipbin, '-ryq', "$homedir/$vpath2");
   } elsif ($ztype eq "mktgz") {
      my $gzipbin=findbin('gzip');
      my $tarbin=findbin('tar');
      if ($gzipbin) {
         $ENV{'PATH'}=$gzipbin;
         $ENV{'PATH'}=~s|/gzip||; # tar finds gzip through PATH
         @cmd=($tarbin, '-zcpf', "$homedir/$vpath2");
      } else {
         @cmd=($tarbin, '-cpf', "$homedir/$vpath2");
      }
   } else {
      return("unknow ztype($ztype)?");
   }

   chdir("$homedir/$currentdir") or
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
########################## END COMPRESSFILES ##########################

########################## DECOMPRESSFILE ##############################
sub decompressfile {	# unpack zip, tar.gz, tgz, gz
   my ($currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);

   if ( !-f "$homedir/$vpath" || !-r _) {
      return("$lang_err{'couldnt_open'} $vpath");
   }
   my $err=verify_vpath($homedir, $vpath);
   return($err) if ($err);

   my @cmd;
   if ($vpath=~/\.zip$/i) {
      my $unzipbin=findbin('unzip');
      return("$lang_text{'program'} unzip $lang_err{'doesnt_exist'}\n") if (!$unzipbin);
      @cmd=($unzipbin, '-oq');

   } elsif ($vpath=~/\.(tar\.g?z||tgz)$/i) {
      my $gzipbin=findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if (!$gzipbin);
      my $tarbin=findbin('tar');
      $ENV{'PATH'}=$gzipbin; $ENV{'PATH'}=~s|/gzip||; # for tar
      @cmd=($tarbin, '-zxpf');

   } elsif ($vpath=~/\.(tar\.bz2?||tbz)$/i) {
      my $bzip2bin=findbin('bzip2');
      return("$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if (!$bzip2bin);
      my $tarbin=findbin('tar');
      $ENV{'PATH'}=$bzip2bin; $ENV{'PATH'}=~s|/bzip2||;	# for tar
      @cmd=($tarbin, '-yxpf');

   } elsif ($vpath=~/\.g?z$/i) {
      my $gzipbin=findbin('gzip');
      return("$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if (!$gzipbin);
      @cmd=($gzipbin, '-dq');

   } elsif ($vpath=~/\.bz2?$/i) {
      my $bzip2bin=findbin('bzip2');
      return("$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if (!$bzip2bin);
      @cmd=($bzip2bin, '-dq');

   } elsif ($vpath=~/\.arj$/i) {
      my $unarjbin=findbin('unarj');
      return("$lang_text{'program'} unarj $lang_err{'doesnt_exist'}\n") if (!$unarjbin);
      @cmd=($unarjbin, 'x');

   } elsif ($vpath=~/\.rar$/i) {
      my $unrarbin=findbin('unrar');
      return("$lang_text{'program'} unrar $lang_err{'doesnt_exist'}\n") if (!$unrarbin);
      @cmd=($unrarbin, 'x', '-r', '-y', '-o+');

   } elsif ($vpath=~/\.lzh$/i) {
      my $lhabin=findbin('lha');
      return("$lang_text{'program'} lha $lang_err{'doesnt_exist'}\n") if (!$lhabin);
      @cmd=($lhabin, '-xfq');

   } else {
      return("$lang_text{'decomp_notsupported'} ($vpath)\n");
   }

   chdir("$homedir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $opstr;
   if ($vpath=~/\.(zip|rar|arj|lhz|t[bg]z|tar\.g?z|tar\.bz2?)$/i) {
      $opstr=$lang_wdbutton{'extract'};
   } else {
      $opstr=$lang_wdbutton{'decompress'};
   }
   return(webdisk_execute($opstr, @cmd, "$homedir/$vpath"));
}
####################### END DECOMPRESSFILE ##########################

########################## LISTARCHIVE ##############################
sub listarchive {
   my ($currentdir, $selitem)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);

   my $html = readtemplate("listarchive.template");
   my $temphtml;
   $html = applystyle($html);

   if (! -f "$homedir/$vpath") {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'file'} $vpath $lang_err{'doesnt_exist'}");
      return;
   }
   my $err=verify_vpath($homedir, $vpath);
   if ($err) {
      autoclosewindow($lang_wdbutton{'listarchive'}, $err);
      return;
   }

   my @cmd;
   if ($vpath=~/\.zip$/i) {
      my $unzipbin=findbin('unzip');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unzip $lang_err{'doesnt_exist'}\n") if (!$unzipbin);
      @cmd=($unzipbin, '-lq');

   } elsif ($vpath=~/\.(tar\.g?z||tgz)$/i) {
      my $gzipbin=findbin('gzip');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} gzip $lang_err{'doesnt_exist'}\n") if (!$gzipbin);
      my $tarbin=findbin('tar');
      $ENV{'PATH'}=$gzipbin; $ENV{'PATH'}=~s|/gzip||; # for tar
      @cmd=($tarbin, '-ztvf');

   } elsif ($vpath=~/\.(tar\.bz2?||tbz)$/i) {
      my $bzip2bin=findbin('bzip2');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} bzip2 $lang_err{'doesnt_exist'}\n") if (!$bzip2bin);
      my $tarbin=findbin('tar');
      $ENV{'PATH'}=$bzip2bin; $ENV{'PATH'}=~s|/bzip2||;	# for tar
      @cmd=($tarbin, '-ytvf');

   } elsif ($vpath=~/\.arj$/i) {
      my $unarjbin=findbin('unarj');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unarj $lang_err{'doesnt_exist'}\n") if (!$unarjbin);
      @cmd=($unarjbin, 'l');

   } elsif ($vpath=~/\.rar$/i) {
      my $unrarbin=findbin('unrar');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} unrar $lang_err{'doesnt_exist'}\n") if (!$unrarbin);
      @cmd=($unrarbin, 'l');

   } elsif ($vpath=~/\.lzh$/i) {
      my $lhabin=findbin('lha');
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'program'} lha $lang_err{'doesnt_exist'}\n") if (!$lhabin);
      @cmd=($lhabin, '-l');

   } else {
      autoclosewindow($lang_wdbutton{'listarchive'}, "$lang_text{'decomp_notsupported'} ($vpath)\n");
   }

   my ($stdout, $stderr, $exit, $sig)=execute(@cmd, "$homedir/$vpath");
   # try to conv realpath in stdout/stderr back to vpath
   $stdout=~s!($homedir//|\s$homedir/)! /!g; $stdout=~s!/+!/!g;
   $stderr=~s!($homedir//|\s$homedir/)! /!g; $stderr=~s!/+!/!g;

   if ($exit||$sig) {
      my $err="$lang_text{'program'} $cmd[0]  $lang_text{'failed'} (exit status $exit";
      $err.=", terminated by signal $sig" if ($sig);
      $err.=")\n$stdout$stderr";
      autoclosewindow($lang_wdbutton{'listarchive'}, $err);
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

   $temphtml = button(-name=>"closebutton",
                      -value=>$lang_text{'close'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CLOSEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   printheader();
   print $html;
   printfooter(2);
}
######################## END LISTARCHIVE ##############################

########################## MAKETHUMB ################################
sub makethumbnail {
   my ($currentdir, @selitems)=@_;
   my $msg;

   my $convertbin=findbin('convert');
   return("$lang_text{'program'} convert $lang_err{'doesnt_exist'}\n") if (!$convertbin);
   my @cmd=($convertbin, '+profile', '*', '-interlace', 'NONE', '-geometry', '64x64');

   foreach (@selitems) {
      my $vpath=absolute_vpath($currentdir, $_);
      my $err=verify_vpath($homedir, $vpath);
      if ($err) {
         $msg.="$err\n"; next;
      }
      next if ( $vpath!~/\.(jpe?g|gif|png|bmp|tif)$/i || !-f "$homedir/$vpath");

      my $thumbnail=path2thumbnail($vpath);
      ($thumbnail =~ /^(.*)$/) && ($thumbnail = $1);

      my @p=split(/\//, $thumbnail); pop(@p);
      my $thumbnaildir=join('/', @p);
      if (!-d "$homedir/$thumbnaildir") {
         ($thumbnaildir =~ /^(.*)$/) && ($thumbnaildir = $1);
         if (!mkdir ("$homedir/$thumbnaildir", 0755)) {
            $msg.="$!\n"; next;
         }
      }

      my ($img_atime,$img_mtime)= (stat("$homedir/$vpath"))[8,9];
      if (-f $thumbnail) {
         my ($thumbnail_atime,$thumbnail_mtime)= (stat("$homedir/$thumbnail"))[8,9];
         next if ($thumbnail_mtime==$img_mtime);
      }
      $msg.=webdisk_execute("$lang_wdbutton{'mkthumbnail'} $thumbnail", @cmd, "$homedir/$vpath", "$homedir/$thumbnail");
      if (-f "$homedir/$thumbnail.0") {
         my @f;
         foreach (1..20) {
            push(@f, "$homedir/$thumbnail.$_");
         }
         unlink @f;
         rename("$homedir/$thumbnail.0", "$homedir/$thumbnail");
      }
      if (-f $thumbnail) {
         ($img_atime  =~ /^(.*)$/) && ($img_atime = $1);
         ($img_mtime  =~ /^(.*)$/) && ($img_mtime = $1);
         utime($img_atime, $img_mtime, "$homedir/$thumbnail") 
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
######################### END MAKETHUMB #############################

########################## DOWNLOADFILES ##############################
sub downloadfiles {	# through zip or tgz
   my ($currentdir, @selitems)=@_;
   my $msg;

   my %selitem;
   foreach (@selitems) {
      my $vpath=absolute_vpath($currentdir, $_);
      my $err=verify_vpath($homedir, $vpath);
      if ($err) {
         $msg.="$err\n"; next;
      }
      # use relative path to currentdir since we will chdir to homedir/currentdir before DL
      my $p=fullpath2vpath("$homedir/$vpath", "$homedir/$currentdir");
      # use absolute path if relative to homedir/currentdir is not possible
      $p="$homedir/$vpath" if (!$p);
      ($p =~ /^(.+)$/) && ($p = $1);  # untaint ...

      if ( -d "$homedir/$vpath" ) {
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
      my $g2l=time()+timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
      my @t=gmtime($g2l);
      $dlname=sprintf("%4d%02d%02d-%02d%02d", $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1]);
   }

   my @cmd;
   my $zipbin=findbin('zip');
   if ($zipbin) {
      @cmd=($zipbin, '-ryq', '-');
      $dlname.=".zip";
   } else {
      my $gzipbin=findbin('gzip');
      my $tarbin=findbin('tar');
      if ($gzipbin) {
         $ENV{'PATH'}=$gzipbin;
         $ENV{'PATH'}=~s|/gzip||; # tar finds gzip through PATH
         @cmd=($tarbin, '-zcpf', '-');
         $dlname.=".tgz";
      } else {
         @cmd=($tarbin, '-cpf', '-');
         $dlname.=".tar";
      }
   }

   chdir("$homedir/$currentdir") or
      return("$lang_err{'couldnt_chdirto'} $currentdir\n");

   my $contenttype=ext2contenttype($dlname);

   $|=1;
   print qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|,
         qq|Content-Disposition: attachment; filename="$dlname"\n\n|;

   writehistory("webdisk - download ".join(' ', @filelist));
   writelog("webdisk - download ".join(' ', @filelist));

   # set enviro's for cmd
   $ENV{'USER'}=$ENV{'LOGNAME'}=$user;
   $ENV{'HOME'}=$homedir;
   $<=$>;		# drop ruid by setting ruid = euid
   exec(@cmd, @filelist) || print qq|Error in executing |.join(' ', @cmd, @filelist);
}
###################### END DOWNLOADFILES #############################

########################## DOWNLOADFILE ##############################
sub downloadfile {
   my ($currentdir, $selitem)=@_;

   my $vpath=absolute_vpath($currentdir, $selitem);
   my $err=verify_vpath($homedir, $vpath);
   return($err) if ($err);

   open(F, "$homedir/$vpath") or
      return("$lang_err{'couldnt_open'} $vpath\n");

   my $dlname=safedlname($vpath);
   my $contenttype=ext2contenttype($vpath);
   my $length = ( -s "$homedir/$vpath");

   # disposition:inline default to open
   print qq|Content-Length: $length\n|,
         qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;
   if ($contenttype=~/^text/ || 
       $dlname=~/\.(jpe?g|gif|png|bmp)$/i) {
      print qq|Content-Disposition: inline; filename="$dlname"\n\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$dlname"\n\n|;
   }
   my $buff;
   while (read(F, $buff, 16384)) {
      print $buff;
   }
   close(F);

   writehistory("webdisk - download $vpath ");
   writelog("webdisk - download $vpath");
}
########################## END DOWNLOADFILE ##########################

########################## PREVIEWFILE ##############################
# relative links in html content will be converted so they can be 
# redirect back to openwebmail-webdisk.pl with correct parmteters
sub previewfile {
   my ($currentdir, $selitem, $filecontent)=@_;
   my $vpath=absolute_vpath($currentdir, $selitem);
   my $err=verify_vpath($homedir, $vpath);
   return($err) if ($err);

   if ($filecontent eq "") {
      my $buff;
      open(F, "$homedir/$vpath") or return("$lang_err{'couldnt_open'} $vpath\n");
      while (read(F, $buff, 16384)) { $filecontent.=$buff; }
      close(F);
   }

   # remove path from filename
   my $dlname=safedlname($vpath);
   my $contenttype=ext2contenttype($vpath);
   if ($vpath=~/\.(html?|js)$/i) {
      # use the dir where this html is as new currentdir
      my @p=path2array($vpath); pop @p;
      my $newdir='/'.join('/', @p);
      my $escapednewdir=escapeURL($newdir);
      my $preview_url=qq|$config{'ow_cgiurl'}/openwebmail-webdisk.pl?sessionid=$thissession|.
                      qq|&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid|.
                      qq|&amp;currentdir=$escapednewdir&amp;action=preview&amp;selitems=|;
      $filecontent=~s/\r\n/\n/g;
      $filecontent=linkconv($filecontent, $preview_url);
   }

   # calc length here since linkconv may change data length
   my $length = length($filecontent);
   print qq|Content-Length: $length\n|,
         qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|,
         qq|Content-Disposition: inline; filename="$dlname"\n\n|.
         $filecontent;
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
   if ($link=~m!^(mailto:|javascript:|#)!i) {
      return($prefix.$link.$postfix);
   } 
   if ($link !~ m!^http://!i && $link!~m!^/!) {
       $link=$preview_url.$link;	
   }
   return($prefix.$link.$postfix);
}
sub _linkconv2 {
   my ($prefix, $link, $postfix, $preview_url)=@_;
   if ($link=~m!^'?(http://|/)!i) {
      return($prefix.$link.$postfix);
   }
   $link=qq|'$preview_url'.$link|;	
   return($prefix.$link.$postfix);
}
########################## END PREVIEWFILE ##############################

########################## UPLOADFILE ##############################
sub uploadfile {
   no strict 'refs';	# for $upload, which is fname and fhandle of the upload
   my ($currentdir, $upload)=@_;
   my $size=(-s $upload);

   if ( $config{'webdisk_uploadlimit'} &&
        $size > ($config{'webdisk_uploadlimit'}*1024) ) {
      return ("$lang_err{'upload_overlimit'} $config{'webdisk_uploadlimit'} $lang_sizes{'kb'}\n");
   }
   if ( $size ==0 ) {
      return("$lang_wdbutton{'upload'} $lang_text{'failed'} (filesize is zero)\n");
   }

   my $fname = $upload;
   # Convert :: back to the ' like it should be.
   $fname =~ s/::/'/g;
   # Trim the path info from the filename

   if ($prefs{'charset'} eq 'big5' || $prefs{'charset'} eq 'gb2312') {
      $fname=zh_dospath2fname($fname);	# dos path
   } else {
      $fname =~ s|^.*\\||;		# dos path
   }
   $fname =~ s|^.*/||;	# unix path
   $fname =~ s|^.*:||;	# mac path and dos drive

   my $vpath=absolute_vpath($currentdir, $fname);
   ($vpath =~ /^(.+)$/) && ($vpath = $1);  # untaint ...
   my $err=verify_vpath($homedir, $vpath);
   return($err) if ($err);

   if (open(UPLOAD, ">$homedir/$vpath")) {
      my $buff;
      while (read($upload, $buff, 32768)) {
         print UPLOAD $buff;
      }
      close(UPLOAD);
      return("$lang_wdbutton{'upload'} $vpath $lang_text{'succeeded'}\n");
   } else {
      return("$lang_wdbutton{'upload'} $vpath $lang_text{'failed'} ($!)\n");
   }
}
######################## END UPLOADFILE ############################

########################## FILESELECT ##############################
sub dirfilesel {
   my ($action, $olddir, $newdir, $filesort, $page)=@_;
   my $showhidden=param('showhidden');
   my $singlepage=param('singlepage');

   # for sel_saveattfile, used in composemessage to save attfile
   my $attfile=param('attfile');
   my $attachment_nodeid=param('attachment_nodeid');
   my $convfrom=param('convfrom');
   my $attname=param('attname');

   if ( $action eq "sel_saveattfile" && $attfile eq "") {
      autoclosewindow($lang_text{'savefile'}, $lang_err{'param_fmterr'});
   } elsif ( $action eq "sel_saveattachment" && $attachment_nodeid eq "") {
      autoclosewindow($lang_text{'savefile'}, $lang_err{'param_fmterr'});
   }

   my ($currentdir, $escapedcurrentdir, $msg);
   foreach my $dir ($newdir, $olddir, "/") {
      my $err=verify_vpath($homedir, $dir);
      if ($err) {
         $msg .= "$err<br>\n"; next;
      }
      if (!opendir(D, "$homedir/$dir")) {
         $msg .= "$lang_err{'couldnt_open'} $dir ($!)<br>\n"; next;
      }
      $currentdir=$dir; last;
   }
   openwebmailerror($msg) if (!$currentdir);
   $escapedcurrentdir=escapeURL($currentdir);

   my (%fsize, %fdate, %ftype, %flink);
   while( my $fname=readdir(D) ) {
      next if ( $fname eq "." || $fname eq ".." );
      next if ( (!$config{'webdisk_lshidden'} || !$showhidden) && $fname =~ /^\./ );
      next if ( !$config{'webdisk_lsmailfolder'} && 
                fullpath2vpath("$currentdir/$fname", $config{'homedirfolderdirname'}) ne "");
      if ( -l "$homedir/$currentdir/$fname" ) {	# symbolic link, aka:shortcut
         next if (!$config{'webdisk_lssymlink'});
         my $realpath=readlink("$homedir/$currentdir/$fname");
         my $vpath=fullpath2vpath($realpath, $homedir);
         if ($vpath) {
            $flink{$fname}=$vpath;
         } else {
            next if (!$config{'webdisk_allow_symlinkouthome'});
            $flink{$fname}="sys::$realpath";
         }
      }

      my ($st_dev,$st_ino,$st_mode,$st_nlink,$st_uid,$st_gid,$st_rdev,$st_size,
          $st_atime,$st_mtime,$st_ctime,$st_blksize,$st_blocks)= stat("$homedir/$currentdir/$fname");
      if ( ($st_mode&0040000)==0040000 ) {
         $ftype{$fname}="d";
      } elsif ( ($st_mode&0100000)==0100000 ) {
         $ftype{$fname}="f";
      } else {	# unix specific filetype: fifo, socket, block dev, char dev..
         next if (!$config{'webdisk_lsunixspec'});
         $ftype{$fname}="u";
      }
      $fsize{$fname}=$st_size;
      $fdate{$fname}=$st_mtime;
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
   my $cookie = cookie( -name  => "$user-currentdir",
                        -value => $currentdir,
                        -path  => '/');
   printheader(-cookie=>[$cookie]);

   $html=readtemplate("dirfilesel.template");
   $html=applystyle($html);

   my $wd_url=qq|$config{ow_cgiurl}/openwebmail-webdisk.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;currentdir=$escapedcurrentdir|;
   if ($action eq "sel_saveattfile") {
      $html =~ s/\@\@\@SELTITLE\@\@\@/$lang_text{'savefile_towd'}/g;
      $wd_url.=qq|&amp;attfile=$attfile&attname=|.escapeURL($attname);
   } elsif ($action eq "sel_saveattachment") {
      $html =~ s/\@\@\@SELTITLE\@\@\@/$lang_text{'saveatt_towd'}/g;
      $wd_url.=qq|&amp;attachment_nodeid=$attachment_nodeid&amp;convfrom=$convfrom&amp;attname=|.escapeURL($attname);
   } elsif ($action eq "sel_addattachment") {
      $html =~ s/\@\@\@SELTITLE\@\@\@/$lang_text{'addatt_fromwd'}/g;
   } else {
      autoclosewindow("Unknow action: $action!");
   }
   my $wd_url_sort_page=qq|$wd_url&amp;showhidden=$showhidden&amp;singlepage=$singlepage&amp;filesort=$filesort&amp;page=$page|;

   if ($action eq "sel_addattachment") {
      $temphtml=start_form(-name=>"selform",
                          -action=>"javascript:addattachment_and_close();");
   } elsif ($action eq "sel_saveattfile") {
      $temphtml=start_form(-name=>"selform",
                          -action=>"javascript:saveattfile_and_close('$attfile');");
   } elsif ($action eq "sel_saveattachment") {
      $temphtml=start_form(-name=>"selform",
                          -action=>"javascript:saveattachment_and_close('$escapedfolder', '$escapedmessageid', '$attachment_nodeid');");
   }
   $html =~ s/\@\@\@STARTDIRFORM\@\@\@/$temphtml/g;

   my $p='/';
   $temphtml=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.escapeURL($p).qq|">/</a>\n|;
   foreach ( split(/\//, $currentdir) ) {
      next if ($_ eq "");
      $p.="$_/";
      $temphtml.=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.escapeURL($p).qq|">$_/</a>\n|;
   }
   $html =~ s/\@\@\@CURRENTDIR\@\@\@/$temphtml/g;

   my $newval=!$showhidden;
   if ($config{'webdisk_lshidden'}) {
      $html =~ s/\@\@\@SHOWHIDDENLABEL\@\@\@/$lang_text{'showhidden'}/g;
      $temphtml=checkbox(-name=>'showhidden',
                         -value=>'1',
                         -checked=>$showhidden,
                         -OnClick=>qq|window.open('$wd_url&amp;action=$action&amp;filesort=$filesort&amp;page=$page&amp;singlepage=$singlepage&amp;showhidden=$newval', '_self'); return false;|,
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
                      -OnClick=>qq|window.open('$wd_url&amp;action=$action&amp;filesort=$filesort&amp;page=$page&amp;showhidden=$showhidden&amp;singlepage=$newval', '_self'); return false;|,
                      -override=>'1',
                      -label=>'');
   $html =~ s/\@\@\@SINGLEPAGECHECKBOX\@\@\@/$temphtml/g;

   if ($currentdir eq "/") {
      $temphtml=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/disk.gif" align="absmiddle" border="0">|;
   } else {
      my $parentdir = absolute_vpath($currentdir, "..");
      $temphtml=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.escapeURL($parentdir).qq|">|.
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

   $temphtml='';
   if ($#sortedlist>=0) {
      my $bgcolor;
      my $unix=unixtype();
      my ($i_first, $i_last)=(0, $#sortedlist);
      if (!$singlepage) {
         $i_first=($page-1)*10; # use 10 instead of $prefs{'webdisk_dirnumitems'} for shorter page
         $i_last=$i_first+10-1;
         $i_last=$#sortedlist if ($i_last>$#sortedlist);
      }
      foreach my $i ($i_first..$i_last) {
         my $fname=$sortedlist[$i];
         my $vpath=absolute_vpath($currentdir, $fname);
         my $accesskeystr=$i%10+1;
         if ($accesskeystr == 10) {
            $accesskeystr=qq|accesskey="0"|;
         } elsif ($accesskeystr < 10) {
            $accesskeystr=qq|accesskey="$accesskeystr"|;
         }

         my ($imgstr, $namestr, $opstr);
         $namestr=$fname;
         $namestr.=qq| -&gt; $flink{$fname}| if (defined($flink{$fname}));
         if ($ftype{$fname} eq "d") {
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($fname, $ftype{$fname}, 0, $unix).
                       qq|" align="absmiddle" border="0">|;
            }
            $namestr=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.
                     escapeURL("$fname").qq|" $accesskeystr>$imgstr <b>$namestr</b></a>|;
            $opstr=qq|<a href="$wd_url_sort_page&amp;action=$action&amp;gotodir=|.
                   escapeURL("$fname").qq|"><b>&lt;$lang_text{'dir'}&gt;</b></a>|;

         } else {
            my $is_txt= (-T "$homedir/$currentdir/$fname");
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($fname, $ftype{$fname}, $is_txt, $unix).
                       qq|" align="absmiddle" border="0">|;
            }
            $namestr=qq|<a href=# onClick="filldestname('$vpath');" $accesskeystr>$imgstr $namestr</a>|;
         }

         my $right='right'; $right='left' if (is_RTLmode($prefs{'language'}));
         $namestr=qq|<table width="100%" border=0 cellspacing=0 cellpadding=0><tr>|.
                  qq|<td>$namestr</td>\n<td align="$right" nowrap>$opstr</td></tr></table>|;

         my $sizestr=qq|<a title="|.lenstr($fsize{$fname},1).qq|">$fsize{$fname}</a>|;

         my $datestr;
         if (defined($fdate{$fname})) {
            my @t =gmtime($fdate{$fname});
            my $dateserial=sprintf("%4d%02d%02d%02d%02d%02d", $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
            $datestr=dateserial2str(add_dateserial_timeoffset($dateserial, $prefs{'timeoffset'}), $prefs{'dateformat'});
         }

         if ( $i % 2 ) {
            $bgcolor = $style{"tablerow_light"};
         } else {
            $bgcolor = $style{"tablerow_dark"};
         }

         $temphtml.=qq|<tr>\n|.
                    qq|<td bgcolor=$bgcolor>$namestr</td>\n|.
                    qq|<td bgcolor=$bgcolor align="right">$sizestr</td>\n|.
                    qq|<td bgcolor=$bgcolor align="center">$datestr</td>\n|.
                    qq|</tr>\n\n|;
      }
   } else {
      my $bgcolor = $style{"tablerow_light"};
      $temphtml.=qq|<tr>\n|.
                 qq|<td bgcolor=$bgcolor align=center>|.
                 qq|<table><tr><td><font color=#aaaaaa>$lang_text{'noitemfound'}</font></td</tr></table>|.
                 qq|</td>\n|.
                 qq|<td bgcolor=$bgcolor>&nbsp;</td>\n|.
                 qq|<td bgcolor=$bgcolor>&nbsp;</td>\n|.
                 qq|</tr>\n\n|;
   }
   $html =~ s/\@\@\@FILELIST\@\@\@/$temphtml/g;

   if (!$singlepage) {
      my $wd_url_page=qq|$wd_url&amp;action=$action&amp;gotodir=$escapedcurrentdir&amp;showhidden=$showhidden&amp;singlepage=$singlepage&amp;filesort=$filesort&amp;page|;

      if ($page>1) {
         my $gif="left.gif"; $gif="right.gif" if (is_RTLmode($prefs{'language'}));
         $temphtml = iconlink($gif, "&lt;", qq|accesskey="U" href="$wd_url_page=|.($page-1).qq|"|).qq|\n|;
      } else {
         my $gif="left-grey.gif"; $gif="right-grey.gif" if (is_RTLmode($prefs{'language'}));
         $temphtml = iconlink($gif, "-", "").qq|\n|;
      }
      $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml/g;

      if ($page<$totalpage) {
         my $gif="right.gif"; $gif="left.gif" if (is_RTLmode($prefs{'language'}));
         $temphtml = iconlink($gif, "&gt;", qq|accesskey="D" href="$wd_url_page=|.($page+1).qq|"|).qq|\n|;
      } else {
         my $gif="right-grey.gif"; $gif="left-grey.gif" if (is_RTLmode($prefs{'language'}));
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
      $temphtml = textfield(-name=>'destname',
                            -default=>"",
                            -size=>'40',
                            -accesskey=>'N',
                            -value=>absolute_vpath($currentdir, $attname),
                            -override=>'1');
   } else {
      $temphtml = textfield(-name=>'destname',
                            -default=>"",
                            -size=>'40',
                            -accesskey=>'N',
                            -value=>'',
                            -disabled=>'1',
                            -override=>'1');
   }
   $html =~ s/\@\@\@DESTNAMEFIELD\@\@\@/$temphtml/g;

   $temphtml='';
   # we return false for the okbutton click event because we do all things in javascript
   # and we dn't want the current page to be reloaded
   if ($action eq "sel_addattachment") {
      $temphtml.=submit(-name=>"okbutton",
                        -onClick=>"addattachment_and_close(); return false;",
                        -value=>$lang_text{'ok'});
   } elsif ($action eq "sel_saveattfile") {
      $temphtml.=submit(-name=>"okbutton",
                        -onClick=>"saveattfile_and_close('$attfile'); return false;",
                        -value=>$lang_text{'ok'});
   } elsif ($action eq "sel_saveattachment") {
      $temphtml.=submit(-name=>"okbutton",
                        -onClick=>"saveattachment_and_close('$escapedfolder', '$escapedmessageid', '$attachment_nodeid'); return false;",
                        -value=>$lang_text{'ok'});
   }
   $temphtml.=submit(-name=>"cencelbutton",
                     -onClick=>'window.close();',
                     -value=>$lang_text{'cancel'});
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/g;

   $temphtml=end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   print $html;
   printfooter(2);
}
######################## END FILESELECT ##########################

########################## SHOWDIR ##############################
sub showdir {
   my ($olddir, $newdir, $filesort, $page, $msg)=@_;
   my $showthumbnail=param('showthumbnail');
   my $showhidden=param('showhidden');
   my $singlepage=param('singlepage');
   my $searchtype=param('searchtype');
   my $keyword=param('keyword'); $keyword=~s/[`;\|]//g;
   my $escapedkeyword=escapeURL($keyword);

   my ($currentdir, $escapedcurrentdir, @list);
   if ($keyword) {	# olddir = newdir if keyword is supplied for searching
      my $err=filelist_of_search($searchtype, $keyword, $olddir, "$folderdir/.webdisk.cache", \@list);
      if ($err) {
         $keyword=""; $msg.=$err;
      } else {
         $currentdir=$olddir;
      }
   }
   if (!$keyword) {
      foreach my $dir ($newdir, $olddir, "/") {
         my $err=verify_vpath($homedir, $dir);
         if ($err) {
            $msg .= "$err\n"; next;
         }
         if (!opendir(D, "$homedir/$dir")) {
            $msg .= "$lang_err{'couldnt_open'} $dir ($!)\n"; next;
         }
         @list=readdir(D);
         close(D);
         $currentdir=$dir;
         last;
      }
      openwebmailerror($msg) if (!$currentdir);
   }
   $escapedcurrentdir=escapeURL($currentdir);

   my (%fsize, %fdate, %fperm, %ftype, %flink);
   my ($dcount, $fcount, $sizecount)=(0,0,0);
   foreach my $p (@list) {
      next if ( $p eq "." || $p eq "..");
      my $vpath=absolute_vpath($currentdir, $p);
      my $fname=$vpath; $fname=~s|.*/||;
      next if ( !$config{'webdisk_lsmailfolder'} && 
                 fullpath2vpath($vpath, $config{'homedirfolderdirname'}) ne "");
      next if ( (!$config{'webdisk_lshidden'}||!$showhidden) && $fname =~ /^\./ );
      if ( -l "$homedir/$vpath" ) {	# symbolic link, aka:shortcut
         next if (!$config{'webdisk_lssymlink'});
         my $realpath=readlink("$homedir/$vpath");
         my $vpath2=fullpath2vpath($realpath, $homedir);
         if ($vpath2) {
            $flink{$p}=$vpath2;
         } else {
            next if (!$config{'webdisk_allow_symlinkouthome'});
            $flink{$p}="sys::$realpath";
         }
      }

      my ($st_dev,$st_ino,$st_mode,$st_nlink,$st_uid,$st_gid,$st_rdev,$st_size,
          $st_atime,$st_mtime,$st_ctime,$st_blksize,$st_blocks)= stat("$homedir/$vpath");
      if ( ($st_mode&0040000)==0040000 ) {
         $ftype{$p}="d"; $dcount++;
      } elsif ( ($st_mode&0100000)==0100000 ) {
         $ftype{$p}="f"; $fcount++; $sizecount+=$st_size;
      }
      my $r=(-r _)?'R':'-';
      my $w=(-w _)?'W':'-';
      my $x=(-x _)?'X':'-';
      $fperm{$p}="$r$w$x";
      $fsize{$p}=$st_size;
      $fdate{$p}=$st_mtime;
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

   my $totalpage= int(($#sortedlist+1)/$prefs{'webdisk_dirnumitems'}+0.999999);
   $totalpage=1 if ($totalpage==0);
   if ($currentdir ne $olddir) {
      $page=1;	# reset page number if change to new dir
   } else {
      $page=1 if ($page<1);
      $page=$totalpage if ($page>$totalpage);
   }

   # since some browser always treat refresh directive as realtive url.
   # we use relative path for refresh
   my $refreshinterval=$prefs{'refreshinterval'}*60;
   my $relative_url="$config{'ow_cgiurl'}/openwebmail-webdisk.pl";
   $relative_url=~s!/.*/!!g;

   my ($html, $temphtml);
   my $cookie = cookie( -name  => "$user-currentdir",
                        -value => $currentdir,
                        -path  => '/');
   printheader(-cookie=>[$cookie],
               -Refresh=>"$refreshinterval;URL=$relative_url?sessionid=$thissession&folder=escapedfolder&message_id=$escapedmessageid&action=showdir&currentdir=$escapedcurrentdir&gotodir=$escapedcurrentdir&showthumbnail=$showthumbnail&showhidden=$showhidden&singlepage=$singlepage&filesort=$filesort&page=$page&searchtype=$searchtype&keyword=$escapedkeyword&session_noupdate=1");

   $html=readtemplate("dir.template");
   $html=applystyle($html);

   my $wd_url=qq|$config{'ow_cgiurl'}/openwebmail-webdisk.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;currentdir=$escapedcurrentdir&amp;showthumbnail=$showthumbnail&amp;showhidden=$showhidden&amp;singlepage=$singlepage|;
   my $wd_url_sort_page=qq|$wd_url&amp;filesort=$filesort&amp;page=$page|;

   $temphtml .= iconlink("home.gif" ,"$lang_text{'backto'} $lang_text{'homedir'}", qq|accesskey="G" href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.escapeURL('/').qq|"|);
   $temphtml .= iconlink("refresh.gif" ,"$lang_wdbutton{'refresh'} ", qq|accesskey="R" href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=$escapedcurrentdir"|);

   $temphtml .= "&nbsp\n";

   if ($messageid eq "") {
      $temphtml .= iconlink("owm.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
   } else {
      $temphtml .= iconlink("owm.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   }
   if ($config{'enable_calendar'}) {
      $temphtml .= iconlink("calendar.gif", $lang_text{'calendar'}, qq|accesskey="K" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=calmonth&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   }
   if ( $config{'enable_sshterm'} && -r "$config{'ow_htmldir'}/applet/mindterm/mindtermfull.jar" ) {
      $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm/ssh.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
   }
   $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   $temphtml .= iconlink("logout.gif", "$lang_text{'logout'} $prefs{'email'}", qq|accesskey="X" href="$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;action=logout"|);

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   if ($config{'webdisk_quota'}>0) {
      my $percent=int($webdiskusage*1000/$config{'webdisk_quota'})/10;
      my $quotastr=qq|$lang_text{'usage'} $webdiskusage|.qq|k/$config{'webdisk_quota'}k ($percent\%)|;
      $html =~ s/\@\@\@INFOQUOTA\@\@\@/$quotastr/g;
   } else {
      $html =~ s/\@\@\@INFOQUOTA\@\@\@//g;
   }

   $temphtml = start_multipart_form(-name=>"dirform",
				    -action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl") .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1').
               hidden(-name=>'currentdir',
                      -default=>$currentdir,
                      -override=>'1').
               hidden(-name=>'gotodir',
                      -default=>$currentdir,
                      -override=>'1').
               hidden(-name=>'filesort',
                      -default=>$filesort,
                      -override=>'1').
               hidden(-name=>'page',
                      -default=>$page,
                      -override=>'1');
   $html =~ s/\@\@\@STARTDIRFORM\@\@\@/$temphtml/g;

   if ($keyword) {
      $temphtml=qq|$lang_text{'search'} &nbsp;|;
   } else {
      $temphtml=qq|$lang_text{'dir'} &nbsp;|;
   }

   my $p='/';
   $temphtml.=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.escapeURL($p).qq|">/</a>\n|;
   foreach ( split(/\//, $currentdir) ) {
      next if ($_ eq "");
      $p.="$_/";
      $temphtml.=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.escapeURL($p).qq|">$_/</a>\n|;
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
         $temphtml=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.escapeURL($parentdir).qq|">|.
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

   $temphtml='';
   if ($#sortedlist>=0) {
      my $bgcolor;
      my $unix=unixtype();
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
         $namestr=$p;
         $namestr.=qq| -&gt; $flink{$p}| if (defined($flink{$p}));
         if ($ftype{$p} eq "d") {
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($p, $ftype{$p}, 0, $unix).
                       qq|" align="absmiddle" border="0">|;
            }
            $namestr=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.
                     escapeURL($p).qq|" $accesskeystr>$imgstr <b>$namestr</b></a>|;

            $opstr=qq|<a href="$wd_url_sort_page&amp;action=showdir&amp;gotodir=|.
                   escapeURL($p).qq|"><b>&lt;$lang_text{'dir'}&gt;</b></a>|;

         } else {
            my $is_txt= (-T "$homedir/$currentdir/$p" || $p=~/\.(txt|html?)$/i);
            if ($prefs{'iconset'}!~/^Text\./) {
               $imgstr=qq|<IMG SRC="$config{'ow_htmlurl'}/images/file/|.
                       findicon($p, $ftype{$p}, $is_txt, $unix).
                       qq|" align="absmiddle" border="0">|;
            }
            my $blank="";
            $blank="target=_blank" if ($is_txt || $p=~/\.(jpe?g|gif|png|bmp)$/i);
            $namestr=qq|<a href="$wd_url_sort_page&amp;action=download&amp;selitems=|.
                     escapeURL($p).qq|" $accesskeystr $blank>$imgstr $namestr</a>|;

            if ($is_txt) {
               if ($p=~/\.html?/i) {
                  $opstr=qq|<a href=# onClick="window.open('|.
                         qq|$wd_url&amp;action=preview&amp;selitems=|.escapeURL($p).
                         qq|','_previewfile','width=720,height=550,scrollbars=yes,resizable=yes,location=no');|.
                         qq|">[$lang_wdbutton{'preview'}]</a>|;
               }
               if (!$config{'webdisk_readonly'} &&
                   (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
                  $opstr.=qq|<a href=# onClick="window.open('|.
                          qq|$wd_url&amp;action=editfile&amp;selitems=|.escapeURL($p).
                          qq|','_editfile','width=720,height=550,scrollbars=yes,resizable=yes,location=no');|.
                          qq|">[$lang_wdbutton{'edit'}]</a>|;
               }
            } elsif ($p=~/\.(zip|rar|arj|lzh|t[bg]z|tar\.g?z|tar\.bz2?)$/i ) {
               $opstr=qq|<a href=# onClick="window.open('|.
                      qq|$wd_url&amp;action=listarchive&amp;selitems=|.escapeURL($p).
                      qq|','_editfile','width=780,height=550,scrollbars=yes,resizable=yes,location=no');|.
                      qq|">[$lang_wdbutton{'listarchive'}]</a>|;
               if (!$config{'webdisk_readonly'} &&
                   (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
                  my $onclickstr;
                  if ($prefs{'webdisk_confirmcompress'}) {
                     my $pstr=$p; $pstr=~s/'/\\'/g;	# escape for javascript
                     $onclickstr=qq|onclick="return confirm('$lang_wdbutton{extract}? ($pstr)');"|;
                  }
                  $opstr.=qq| <a href="$wd_url_sort_page&amp;action=decompress&amp;selitems=|.
                          escapeURL($p).qq|" $onclickstr>[$lang_wdbutton{'extract'}]</a>|;
               }
            } elsif ($p=~/\.(g?z|bz2?)$/i ) {
               if (!$config{'webdisk_readonly'} &&
                   (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
                  my $onclickstr;
                  if ($prefs{'webdisk_confirmcompress'}) {
                     my $pstr=$p; $pstr=~s/'/\\'/g;	# escape for javascript
                     $onclickstr=qq|onclick="return confirm('$lang_wdbutton{decompress}? ($pstr)');"|;
                  }
                  $opstr=qq|<a href="$wd_url_sort_page&amp;action=decompress&amp;selitems=|.
                         escapeURL($p).qq|" $onclickstr>[$lang_wdbutton{'decompress'}]</a>|;
               }
            } elsif ($p=~/\.(jpe?g|gif|png|bmp|tif)$/i ) {
               if ($showthumbnail) {
                  my $thumbnail=path2thumbnail($p);
                  if ( -f "$homedir/$currentdir/$thumbnail") {
                     $opstr=qq|<a href="$wd_url_sort_page&amp;action=download&amp;selitems=|.
                            escapeURL($p).qq|" $blank>|.
                            qq|<IMG SRC="$wd_url_sort_page&amp;action=download&amp;selitems=|.
                            escapeURL($thumbnail).qq|" align="absmiddle" border="0"></a>|;
                  }
               }
            }
         }

         my $right='right'; $right='left' if (is_RTLmode($prefs{'language'}));
         $namestr=qq|<table width="100%" border=0 cellspacing=0 cellpadding=0><tr>|.
                  qq|<td>$namestr</td>\n<td align="$right" nowrap>$opstr</td></tr></table>|;

         my $sizestr=qq|<a title="|.lenstr($fsize{$p},1).qq|">$fsize{$p}</a>|;

         my $datestr;
         if (defined($fdate{$p})) {
            my @t =gmtime($fdate{$p});
            my $dateserial=sprintf("%4d%02d%02d%02d%02d%02d", $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
            $datestr=dateserial2str(add_dateserial_timeoffset($dateserial, $prefs{'timeoffset'}), $prefs{'dateformat'});
         }

         $fperm{$p}=~/^(.)(.)(.)$/;
         my $permstr=qq|<table cellspacing="0" cellpadding="0" border="0"><tr>|.
                     qq|<td align=center width=12>$1</td>|.
                     qq|<td align=center width=12>$2</td>|.
                     qq|<td align=center width=12>$3</td>|.
                     qq|</tr></table>|;

         if ( $i % 2 ) {
            $bgcolor = $style{"tablerow_light"};
         } else {
            $bgcolor = $style{"tablerow_dark"};
         }

         $temphtml.=qq|<tr>\n|.
                    qq|<td bgcolor=$bgcolor>$namestr</td>\n|.
                    qq|<td bgcolor=$bgcolor align="right">$sizestr</td>\n|.
                    qq|<td bgcolor=$bgcolor align="center">$datestr</td>\n|.
                    qq|<td bgcolor=$bgcolor align="center">$permstr</td>\n|.
                    qq|<td bgcolor=$bgcolor align="center">|;
         $temphtml.=checkbox(-name=>'selitems',
                             -value=>$p,
                             -override=>'1',
                             -label=>'');
         $temphtml.=qq|</td>\n</tr>\n\n|;
      }
   } else {
      my $bgcolor = $style{"tablerow_light"};
      $temphtml.=qq|<tr>\n|.
                 qq|<td bgcolor=$bgcolor align=center>|.
                 qq|<table><tr><td><font color=#aaaaaa>$lang_text{'noitemfound'}</font></td</tr></table>|.
                 qq|</td>\n|.
                 qq|<td bgcolor=$bgcolor>&nbsp;</td>\n|.
                 qq|<td bgcolor=$bgcolor>&nbsp;</td>\n|.
                 qq|<td bgcolor=$bgcolor>&nbsp;</td>\n|.
                 qq|<td bgcolor=$bgcolor>&nbsp;</td>\n|.
                 qq|</tr>\n\n|;
   }
   $html =~ s/\@\@\@FILELIST\@\@\@/$temphtml/g;

   if (!$singlepage) {
      my $wd_url_page=qq|$wd_url&amp;action=showdir&amp;gotodir=$escapedcurrentdir&amp;filesort=$filesort&amp;searchtype=$searchtype&amp;keyword=$escapedkeyword&amp;page|;
      if ($page>1) {
         my $gif="left.gif"; $gif="right.gif" if (is_RTLmode($prefs{'language'}));
         $temphtml = iconlink($gif, "&lt;", qq|accesskey="U" href="$wd_url_page=|.($page-1).qq|"|).qq|\n|;
      } else {
         my $gif="left-grey.gif"; $gif="right-grey.gif" if (is_RTLmode($prefs{'language'}));
         $temphtml = iconlink($gif, "-", "").qq|\n|;
      }
      $html =~ s/\@\@\@LEFTPAGECONTROL\@\@\@/$temphtml/g;

      if ($page<$totalpage) {
         my $gif="right.gif"; $gif="left.gif" if (is_RTLmode($prefs{'language'}));
         $temphtml = iconlink($gif, "&gt;", qq|accesskey="D" href="$wd_url_page=|.($page+1).qq|"|).qq|\n|;
      } else {
         my $gif="right-grey.gif"; $gif="left-grey.gif" if (is_RTLmode($prefs{'language'}));
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
                         -size=>'60',
                         -accesskey=>'N',
                         -override=>'1');
   $temphtml.=qq|&nbsp;\n|;
   $temphtml.=submit(-name=>"chdirbutton",
                     -accesskey=>"J",
                     -onClick=>"if (document.dirform.keyword.value != '') {return true;}; return destnamefilled('$lang_text{dest_of_chdir}');",
                     -value=>$lang_wdbutton{'chdir'}).qq|\n|;
   $html =~ s/\@\@\@DESTNAMEFIELD\@\@\@/$temphtml/g;

   $temphtml='';
   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $temphtml.=submit(-name=>"mkdirbutton",
                        -accesskey=>"M",
                        -onClick=>"return destnamefilled('$lang_text{name_of_newdir}');",
                        -value=>$lang_wdbutton{'mkdir'});
      $temphtml.=submit(-name=>"newfilebutton",
                        -accesskey=>"F",
                        -onClick=>"return destnamefilled('$lang_text{name_of_newfile}');",
                        -value=>$lang_wdbutton{'newfile'});
      $temphtml.=qq|&nbsp;\n|;
   }

   if (!$config{'webdisk_readonly'}) {
      $temphtml.=submit(-name=>"deletebutton",
                        -accesskey=>"Y",
                        -onClick=>"return (anyfileselected() && opconfirm('$lang_wdbutton{delete}', $prefs{webdisk_confirmdel}));",
                        -value=>$lang_wdbutton{'delete'});
      if (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'}) {
         $temphtml.=submit(-name=>"copybutton",
                           -accesskey=>"C",
                           -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_thecopy}') && opconfirm('$lang_wdbutton{copy}', $prefs{webdisk_confirmmovecopy}));",
                           -value=>$lang_wdbutton{'copy'});
         $temphtml.=submit(-name=>"movebutton",
                           -accesskey=>"V",
                           -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_themove}') && opconfirm('$lang_wdbutton{move}', $prefs{webdisk_confirmmovecopy}));",
                           -value=>$lang_wdbutton{'move'});
      }
      $temphtml.=qq|&nbsp;\n|;
   }

   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $temphtml.=submit(-name=>"gzipbutton",
                        -accesskey=>"Z",
                        -onClick=>"return(anyfileselected() && opconfirm('$lang_wdbutton{gzip}', $prefs{webdisk_confirmcompress}));",
                        -value=>$lang_wdbutton{'gzip'});
      $temphtml.=submit(-name=>"mkzipbutton",
                        -accesskey=>"Z",
                        -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_thezip}') && opconfirm('$lang_wdbutton{mkzip}', $prefs{webdisk_confirmcompress}));",
                        -value=>$lang_wdbutton{'mkzip'});
      $temphtml.=submit(-name=>"mktgzbutton",
                        -accesskey=>"Z",
                        -onClick=>"return(anyfileselected() && destnamefilled('$lang_text{dest_of_thetgz}') && opconfirm('$lang_wdbutton{mktgz}', $prefs{webdisk_confirmcompress}));",
                        -value=>$lang_wdbutton{'mktgz'});
      if ($config{'webdisk_allow_thumbnail'}) {
         $temphtml.=submit(-name=>"mkthumbnailbutton",
                           -accesskey=>"Z",
                           -onClick=>"return(anyfileselected() && opconfirm('$lang_wdbutton{mkthumbnail}', $prefs{webdisk_confirmcompress}));",
                           -value=>$lang_wdbutton{'mkthumbnail'});
      }
      $temphtml.=qq|&nbsp;\n|;
   }

   $temphtml.=submit(-name=>"downloadbutton",
                     -accesskey=>"L",
                     -onClick=>'return anyfileselected();',
                     -value=>$lang_wdbutton{'download'});
   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/g;

   my %searchtypelabels = ('filename'=>$lang_text{'filename'},
                           'textcontent'=>$lang_text{'textcontent'});
   $temphtml = popup_menu(-name=>'searchtype',
                           -default=>'filename',
                           -values=>['filename', 'textcontent'],
                           -labels=>\%searchtypelabels);
   $temphtml .= textfield(-name=>'keyword',
                         -default=>$keyword,
                         -size=>'25',
                         -accesskey=>'S',
                         -onChange=>'document.dirform.searchbutton.focus();',
                         -override=>'1');
   $temphtml .= submit(-name=>"searchbutton",
                       -value=>"$lang_text{'search'}");
   $html =~ s/\@\@\@SEARCHFILEFIELD\@\@\@/$temphtml/g;

   if (!$config{'webdisk_readonly'} &&
       (!$config{'webdisk_quota'} || $webdiskusage < $config{'webdisk_quota'})) {
      $temphtml = filefield(-name=>'upload',
                            -default=>"",
                            -size=>'20',
                            -accesskey=>'W',
                            -override=>'1');
      $temphtml .= submit(-name=>"uploadbutton",
                          -onClick=>'return uploadfilled();',
                          -value=>"$lang_wdbutton{'upload'}");
      $html =~ s/\@\@\@UPLOADFILEFIELD\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@UPLOADSTART\@\@\@//g;
      $html =~ s/\@\@\@UPLOADEND\@\@\@//g;
   } else {
      $html =~ s/\@\@\@UPLOADSTART\@\@\@/<!--/g;
      $html =~ s/\@\@\@UPLOADEND\@\@\@/-->/g;
   }

   if ($config{'webdisk_quota'} && $webdiskusage==$config{'webdisk_quota'}) {
      $msg.="$lang_err{'webdisk_hitquota'}\n";
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

   print $html;
   printfooter(2);
}

sub filelist_of_search {
   my ($searchtype, $keyword, $vpath, $cachefile, $r_list)=@_;
   my $metainfo=join("@@@", $searchtype, $keyword, $vpath);
   my $cache_metainfo;

   ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# untaint ...
   filelock($cachefile, LOCK_EX) or
      return("$lang_err{'couldnt_lock'} $cachefile\n");

   if ( -e $cachefile ) {
      open(CACHE, "$cachefile") ||  return("$lang_err{'couldnt_open'} $cachefile!");
      $cache_metainfo=<CACHE>;
      chomp($cache_metainfo);
      close(CACHE);
   }
   if ( $cache_metainfo ne $metainfo ) {
      my (@cmd, $stdout, $stderr, $exit, $sig);

      chdir("$homedir/$vpath") or
         return("$lang_err{'couldnt_chdirto'} $vpath\n");

      if ($searchtype eq "filename") {	# find . -name "*keyword"
         my $findbin=findbin('find');
         return("$lang_text{'program'} find $lang_err{'doesnt_exist'}\n") if (!$findbin);
         @cmd=($findbin, ".", '-iname', "*$keyword*", '-print');
         ($stdout, $stderr, $exit, $sig)=execute(@cmd);

         if ($stderr) {	# old find doesn't support -iname, use -name instead
            @cmd=($findbin, ".", '-name', "*$keyword*", '-print');
            ($stdout, $stderr, $exit, $sig)=execute(@cmd);
         }
      } else {				# grep -ilsr -- keyword .
         my $grepbin=findbin('grep');
         return("$lang_text{'program'} grep $lang_err{'doesnt_exist'}\n") if (!$grepbin);
         @cmd=($grepbin, "-ilsr", '--', $keyword, '.');
         ($stdout, $stderr, $exit, $sig)=execute(@cmd);

         if ($stderr) {	# old grep doesn't support -r, do no-recursive search instead
            if (!opendir(D, "$homedir/$vpath")) {
               return("$lang_err{'couldnt_open'} $vpath ($!)\n");
            }
            my @f=readdir(D);
            close(D);
            @cmd=($grepbin, "-ils", '--', $keyword, @f);
            ($stdout, $stderr, $exit, $sig)=execute(@cmd);
         }
      }

      if (($exit!=0 && $stderr) || $sig) {
          if ($sig) {
             return "$lang_text{'search'} $lang_text{'failed'} (exit status $exit, terminated by signal $sig)\n$stdout$stderr";
          } else {
             return "$lang_text{'search'} $lang_text{'failed'} (exit status $exit)\n$stdout$stderr";
          }
      }

      $stdout=~s|^\./||igm;
      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n", $stdout;
      close(CACHE);
      @{$r_list}=split(/\n/, $stdout);

   } else {
      my @result;
      open(CACHE, $cachefile);
      $_=<CACHE>;
      while (<CACHE>) {
         chomp;
         push (@{$r_list}, $_);
      }
      close(CACHE);
   }

   filelock($cachefile, LOCK_UN);

   return;
}
########################## END SHOWDIR ###########################

########################## WD_EXECUTE ##############################
# a wrapper for execute() to handle the dirty work
sub webdisk_execute {
   my ($opstr, @cmd)=@_;
   my ($stdout, $stderr, $exit, $sig)=execute(@cmd);

   # try to conv realpath in stdout/stderr back to vpath
   $stdout=~s!($homedir//|\s$homedir/)! /!g; $stdout=~s!/+!/!g;
   $stderr=~s!($homedir//|\s$homedir/)! /!g; $stderr=~s!/+!/!g;

   my $opresult;
   if ($exit||$sig) {
      $opresult=$lang_text{'failed'};
   } else {
      $opresult=$lang_text{'succeeded'};
      writehistory("webdisk - ".join(' ', @cmd));
      writelog("webdisk - ".join(' ', @cmd));
   }
   if ($sig) {
      return "$opstr $opresult (exit status $exit, terminated by signal $sig)\n$stdout$stderr";
   } else {
      return "$opstr $opresult (exit status $exit)\n$stdout$stderr";
   }
}
######################### END WD_EXECUTE ##########################

########################## FINDBIN ##############################
sub findbin {
   my $name=$_[0];
   foreach ('/usr/local/bin', '/usr/bin', '/bin', '/usr/X11R6/bin/', '/opt/bin') {
      return "$_/$name" if ( -x "$_/$name");
   }
   return;
}
########################## END FINDBIN ###########################

########################## FINDICON ##############################
sub findicon {
   my ($fname, $ftype, $is_txt, $unix)=@_;

   return ("dir.gif") if ($ftype eq "d");
   return ("sys.gif") if ($ftype eq "u");

   $_=lc($fname);

   return("cert.gif") if ( /\.ce?rt$/ || /\.cer$/ || /\.ssl$/ );
   return("help.gif") if ( /\.hlp$/ || /\.man$/ || /\.cat$/ || /\.info$/);
   return("pdf.gif") if ( /\.[fp]df$/ );
   return("html.gif") if ( /\.s?html?$/ || /\.xml$/ || /\.sgml$/ );
   return("txt.gif") if ( /\.text$/ || /\.txt$/ );

   if ($is_txt) {
      return("css.gif") if ( /\.css$/ || /\.jsp?$/ || /\.aspx?$/ || /\.php[34]?$/ || /\.xslt?$/ || /\.vb[se]$/ || /\.ws[cf]$/ );
      return("ini.gif") if ( /\.ini$/ || /\.inf$/ || /\.conf$/ || /\.cf$/ || /\.config$/ || /^\..*rc$/ );
      return("mail.gif") if ( /\.msg$/ || /\.elm$/ );
      return("ps.gif") if ( /\.ps$/ || /\.eps$/ );
      return("txt.gif");
   } else {
      return("audio.gif") if (/\.mid[is]?$/ || /\.mod$/ || /\.au$/ || /\.cda$/ || /\.aif$/ || /\.voc$/ );
      return("chm.gif") if ( /\.chm$/ );
      return("doc.gif") if ( /\.do[ct]$/ || /\.rtf$/ || /\.wri$/ );
      return("exe.gif") if ( /\.exe$/ || /\.com$/);
      return("font.gif") if ( /\.fon$/ );
      return("graph.gif") if ( /\.jpe?g$/ || /\.gif$/ || /\.png$/ || /\.bmp$/ || /\.pbm$/ || /\.pc[xt]$/ || /\.pi[cx]$/ || /\.psp$/ || /\.dcx$/ || /\.kdc$/ || /\.tiff?$/ || /\.ico$/ || /\.img$/);
      return("mdb.gif") if ( /\.md[bentz]$/ || /\.ma[fmq]$/ );
      return("mp3.gif") if ( /\.m3u$/ || /\.mp[32]$/ );
      return("ppt.gif") if ( /\.pp[at]$/ || /\.pot$/ );
      return("rm.gif") if ( /\.r[fampv]$/ || /\.ram$/);
      return("stream.gif") if ( /\.wmv$/ || /\.wvx$/ || /\.as[fx]$/ );
      return("ttf.gif") if ( /\.tt[cf]$/ );
      return("video.gif") if ( /\.mov$/ || /\.dat$/ || /\.mpg$/ || /\.mpeg$/ );
      return("xls.gif") if ( /\.xl[abcdmst]$/ );
      return("zip.gif") if ( /\.(zip|tar|t?g?z|tbz|bz2?|rar|lzh|arj|bhx|hqx)$/ );

      return("filebsd.gif") if ( $unix eq "bsd" );
      return("filelinux.gif") if ( $unix eq "linux" );
      return("filesolaris.gif") if ( $unix eq "solaris");
      return("file.gif");
   }
}
########################## END FINDICON ##############################

########################## UNIXTYPE ##############################
sub unixtype {
   if ( -f "/kernel" ) {
      return "bsd";
   } elsif ( -f "/boot/vmlinuz" ) {
      return "linux";
   } elsif ( -f "/kernel/genunix" ) {
      return "solaris";
   } else {
      return "generic";
   }
}
########################## END UNIXTYPE ##############################
