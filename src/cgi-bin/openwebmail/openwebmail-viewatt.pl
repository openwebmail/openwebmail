#!/usr/bin/suidperl -T
#
# openwebmail-viewatt.pl - attachment reading program
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
require "mime.pl";
require "iconv.pl";
require "maildb.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();
verifysession();

use vars qw($sort $page);
use vars qw($searchtype $keyword $escapedkeyword);

$page = param("page") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';
$keyword = param("keyword") || '';
$escapedkeyword = escapeURL($keyword);
$searchtype = param("searchtype") || 'subject';

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy
use vars qw($_SUBJECT $_CHARSET);	# defined in maildb.pl

########################## MAIN ##############################

my $action = param("action");
if ($action eq "viewattachment") {
   viewattachment();
} elsif ($action eq "saveattachment" && $config{'enable_webdisk'}) {
   saveattachment();
} elsif ($action eq "viewattfile") {
   viewattfile();
} elsif ($action eq "saveattfile" && $config{'enable_webdisk'}) {
   saveattfile();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

###################### END MAIN ##############################

################ VIEWATTACHMENT/SAVEATTACHMENT ##################
sub viewattachment {	# view attachments inside a message
   my $messageid = param("message_id");
   my $nodeid = param("attachment_nodeid");

   my ($attfilename, $length, $r_attheader, $r_attbody)=getattachment($folder, $messageid, $nodeid);
   print "${$r_attheader}\n${$r_attbody}";
}

sub saveattachment {	# save attachments inside a message to webdisk
   my $messageid = param("message_id");
   my $nodeid = param("attachment_nodeid");
   my $webdisksel=param('webdisksel');

   my ($attfilename, $length, $r_attheader, $r_attbody)=getattachment($folder, $messageid, $nodeid);
   savefile2webdisk($attfilename, $length, $r_attbody, $webdisksel);
}

sub getattachment {
   my ($folder, $messageid, $nodeid)=@_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();

   filelock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      openwebmailerror("$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
   }
   open($folderhandle, "$folderfile");
   my $r_block= get_message_block($messageid, $headerdb, $folderhandle);
   close($folderhandle);
   filelock($folderfile, LOCK_UN);

   if ( !defined(${$r_block}) ) {
      openwebmailerror("What the heck? Message ".str2html($messageid)." seems to be gone!");
   }

   my @attr=get_message_attributes($messageid, $headerdb);
   my $convfrom=param('convfrom');
   if ($convfrom eq "") {
      if ( is_convertable($attr[$_CHARSET], $prefs{'charset'}) ) {
         $convfrom=lc($attr[$_CHARSET]);
      } else {
         $convfrom='none.prefscharset';
      }
   }

   if ( $nodeid eq 'all' ) {
      # return whole msg as an message/rfc822 object
      my $subject = $attr[$_SUBJECT];
      if (is_convertable($convfrom, $prefs{'charset'}) ) {
         ($subject)=iconv($convfrom, $prefs{'charset'}, $subject);
      }
      $subject =~ s/\s+/_/g;

      my $length = length(${$r_block});
      # disposition:attachment default to save
      my $attheader=qq|Content-Length: $length\n|.
                    qq|Content-Transfer-Coding: binary\n|.
                    qq|Connection: close\n|.
                    qq|Content-Type: message/rfc822; name="$subject.msg"\n|;

      # ugly hack since ie5.5 is broken with disposition: attchment
      if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
         $attheader.=qq|Content-Disposition: attachment; filename="$subject.msg"\n|;
      }
      return("$subject.msg", $length, \$attheader, $r_block);

   } else {
      # return a specific attachment
      my ($header, $body, $r_attachments)=parse_rfc822block($r_block, "0", $nodeid);
      undef(${$r_block});
      undef($r_block);

      my $r_attachment;
      for (my $i=0; $i<=$#{$r_attachments}; $i++) {
         if ( ${${$r_attachments}[$i]}{nodeid} eq $nodeid ) {
            $r_attachment=${$r_attachments}[$i];
         }
      }
      if (defined($r_attachment)) {
         my $charset=${$r_attachment}{filenamecharset}||
                     ${$r_attachment}{charset}||
                     $convfrom||
                     $attr[$_CHARSET];
         if (is_convertable($charset, $prefs{'charset'})) {
            (${$r_attachment}{filename})=iconv($charset, $prefs{'charset'},
                                                ${$r_attachment}{filename});
         }

         my $content;
         if (${$r_attachment}{encoding} =~ /^base64$/i) {
            $content = decode_base64(${${$r_attachment}{r_content}});
         } elsif (${$r_attachment}{encoding} =~ /^quoted-printable$/i) {
            $content = decode_qp(${${$r_attachment}{r_content}});
         } elsif (${$r_attachment}{encoding} =~ /^x-uuencode$/i) {
            $content = uudecode(${${$r_attachment}{r_content}});
         } else { ## Guessing it's 7-bit, at least sending SOMETHING back! :)
            $content = ${${$r_attachment}{r_content}};
         }
         if (${$r_attachment}{contenttype} =~ m#^text/html#i ) {
            my $escapedmessageid = escapeURL($messageid);
            $content = html4nobase($content);
#            $content = html4link($content);
            $content = html4disablejs($content) if ($prefs{'disablejs'}==1);
            $content = html4disableembcgi($content) if ($prefs{'disableembcgi'}==1);
            $content = html4attachments($content, $r_attachments, "$config{'ow_cgiurl'}/openwebmail-viewatt.pl", "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
#            $content = html4mailto($content, "$config{'ow_cgiurl'}/openwebmail-send.pl", "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;page=$page&amp;sessionid=$thissession&amp;composetype=sendto");
         }

         my $length = length($content);
         my $contenttype = ${$r_attachment}{contenttype};
         my $filename = ${$r_attachment}{filename};
         $filename=~s/\s$//;

         # remove char disallowed in some fs
         if ($prefs{'charset'} eq 'big5' || $prefs{'charset'} eq 'gb2312') {
            $filename = zh_dospath2fname($filename, '_');	# dos path
         } else {
            $filename =~ s|\\|_|;			# dos path
         }
         $filename =~ s|^.*/||;	# unix path
         $filename =~ s|^.*:||;	# mac path and dos drive
         $filename=safedlname($filename);

         # we send message with contenttype text/plain for easy view
         if ($contenttype =~ /^message\//i) {
            $contenttype = "text/plain";
         }

         # we change the filename of an attachment
         # from *.exe, *.com *.bat, *.pif, *.lnk, *.scr to *.file
         # if its contenttype is not application/octet-stream
         # to avoid this attachment is referenced by html and executed directly ie
         if ( $filename =~ /\.(exe|com|bat|pif|lnk|scr)$/i &&
              $contenttype !~ /application\/octet\-stream/i &&
              $contenttype !~ /application\/x\-msdownload/i ) {
            $filename="$filename.file";
         }

         # change contenttype of image to make it directly displayed by browser
         if ( $contenttype =~ /application\/octet\-stream/i &&
              $filename =~ /\.(jpg|jpeg|gif|png|bmp)$/i ) {
            $contenttype="image/".lc($1);
         }

         # disposition:attachment default to save
         my $attheader=qq|Content-Length: $length\n|.
                       qq|Content-Transfer-Coding: binary\n|.
                       qq|Connection: close\n|.
                       qq|Content-Type: $contenttype; name="$filename"\n|;
         # ugly hack since ie5.5 is broken with disposition: attchment
         if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
            if ($contenttype =~ /^text/i) {
               $attheader.=qq|Content-Disposition: inline; filename="$filename"\n|;
            } else {
               $attheader.=qq|Content-Disposition: attachment; filename="$filename"\n|;
            }
         }

         # use undef to free memory before attachment transfer
         undef %{$r_attachment};
         undef $r_attachment;
         undef @{$r_attachments};
         undef $r_attachments;
         return($filename, $length, \$attheader, \$content);
      } else {
         openwebmailerror("What the heck? Message ".str2html($messageid)." $nodeid seems to be gone!");
      }
   }
   # never reach
}
################### END VIEWATTACHMENT ##################

################ VIEWATTFILE/SAVEATTFILE ##################
sub viewattfile {	# view attachments uploaded to $config{'ow_sessionsdir'}
   my $attfile=param("attfile");
   $attfile =~ s/\///g;  # just in case someone gets tricky ...

   my ($attfilename, $length, $r_attheader, $r_attbody)=getattfile($attfile);
   print "${$r_attheader}\n${$r_attbody}";
}

sub saveattfile {	# save attachments uploaded to $config{'pw_sessiondir'} to webdisk
   my $attfile=param("attfile");
   my $webdisksel=param('webdisksel');

   my ($attfilename, $length, $r_attheader, $r_attbody)=getattfile($attfile);
   savefile2webdisk($attfilename, $length, $r_attbody, $webdisksel);
}

sub getattfile {
   my $attfile=$_[0];
   # only allow to view attfiles belongs the $thissession
   if ($attfile!~/^$thissession/  || !-f "$config{'ow_sessionsdir'}/$attfile") {
      openwebmailerror("What the heck? Attfile $config{'ow_sessionsdir'}/$attfile seems to be gone!");
   }

   my ($attsize, $attheader, $attheaderlen, $attcontent);
   my ($attcontenttype, $attencoding, $attdisposition,
       $attid, $attlocation, $attfilename);

   $attsize=(-s("$config{'ow_sessionsdir'}/$attfile"));

   open(ATTFILE, "$config{'ow_sessionsdir'}/$attfile") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}/$attfile!");
   read(ATTFILE, $attheader, 512);
   $attheaderlen=index($attheader,  "\n\n", 0);
   $attheader=substr($attheader, 0, $attheaderlen);
   seek(ATTFILE, $attheaderlen+2, 0);
   read(ATTFILE, $attcontent, $attsize-$attheaderlen-2);
   close(ATTFILE);

   my $lastline='NONE';
   foreach (split(/\n/, $attheader)) {
      if (/^\s/) {
         s/^\s+//; # fields in attheader us ';' as delimiter, no space is ok
         if ($lastline eq 'TYPE') { $attcontenttype .= $_ }
      } elsif (/^content-type:\s+(.+)$/ig) {
         $attcontenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $attencoding = $1;
         $lastline = 'NONE';
      } elsif (/^content-disposition:\s+(.+)$/ig) {
         $attdisposition = $1;
         $lastline = 'NONE';
      } elsif (/^content-id:\s+(.+)$/ig) {
         $attid = $1;
         $attid =~ s/^\<(.+)\>$/$1/;
         $lastline = 'NONE';
      } elsif (/^content-location:\s+(.+)$/ig) {
         $attlocation = $1;
         $lastline = 'NONE';
      } else {
         $lastline = 'NONE';
      }
   }

   $attfilename = $attcontenttype;
   $attcontenttype =~ s/^(.+);.*/$1/g;
   unless ($attfilename =~ s/^.+name[:=]"?([^"]+)"?.*$/$1/ig) {
      $attfilename = $attdisposition || '';
      unless ($attfilename =~ s/^.+filename="?([^"]+)"?.*$/$1/ig) {
         $attfilename = "Unknown.".contenttype2ext($attcontenttype);
      }
   }
   $attdisposition =~ s/^(.+);.*/$1/g;

   # remove char disallowed in some fs
   if ($prefs{'charset'} eq 'big5' || $prefs{'charset'} eq 'gb2312') {
      $attfilename = zh_dospath2fname($attfilename, '_');	# dos path
   } else {
      $attfilename =~ s|\\|_|;			# dos path
   }
   $attfilename =~ s|^.*/||;	# unix path
   $attfilename =~ s|^.*:||;	# mac path and dos drive
   $attfilename=safedlname($attfilename);

   if ($attencoding =~ /^base64$/i) {
      $attcontent = decode_base64($attcontent);
   } elsif ($attencoding =~ /^quoted-printable$/i) {
      $attcontent = decode_qp($attcontent);
   } elsif ($attencoding =~ /^x-uuencode$/i) {
      $attcontent = uudecode($attcontent);
   }

   my $length = length($attcontent);
   # rebuild attheader for download
   # disposition:inline default to open
   $attheader= qq|Content-Length: $length\n|.
               qq|Content-Transfer-Coding: binary\n|.
               qq|Connection: close\n|.
               qq|Content-Type: $attcontenttype; name="$attfilename"\n|.
               qq|Content-Disposition: inline; filename="$attfilename"\n|;

   return($attfilename, $length, \$attheader, \$attcontent);
}
################### END VIEWATTATTFILE ##################

##################### SAVEFILE2WEBDISK ###################
sub savefile2webdisk {
   my ($filename, $length, $r_content, $webdisksel)=@_;

   if ($config{'webdisk_quota'}>0) {
      my $webdiskusage=0;
      my ($stdout, $stderr, $exit, $sig)=execute('/usr/bin/du', '-sk', $homedir);
      $webdiskusage=$1 if ($stdout=~/(\d+)/);
      if ($length/1024+$webdiskusage > $config{'webdisk_quota'}) {
         autoclosewindow($lang_text{'quota_hit'}, $lang_err{'webdisk_hitquota'});
      }
   }

   my $vpath=absolute_vpath('/', $webdisksel);
   my $err=verify_vpath($homedir, $vpath);
   openwebmailerror($err) if ($err);

   if (-d "$homedir/$vpath") {			# use choose a dirname, save att with its original name
      $vpath=absolute_vpath($vpath, $filename);
      $err=verify_vpath($homedir, $vpath);
      openwebmailerror($err) if ($err);
   }
   ($vpath =~ /^(.+)$/) && ($vpath = $1);  # untaint ...

   if (!open(F, ">$homedir/$vpath") ) {
      autoclosewindow($lang_text{'savefile'}, "$lang_text{'savefile'} $lang_text{'failed'} ($vpath: $!)");
   }
   filelock("$homedir/$vpath", LOCK_EX|LOCK_NB) or
      autoclosewindow($lang_text{'savefile'}, "$lang_err{'couldnt_lock'} $homedir/$vpath!");
   print F ${$r_content};
   close(F);
   chmod(0644, "$homedir/$vpath");
   filelock("$homedir/$vpath", LOCK_UN);

   writelog("saveatt - $vpath");
   writehistory("saveatt - $vpath");

   autoclosewindow($lang_text{'savefile'}, "$lang_text{'savefile'} $lang_text{'succeeded'} ($vpath)");
}
################### END SAVEFILE2WEBDISK #################
