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

use vars qw($firstmessage);
use vars qw($sort);
use vars qw($searchtype $keyword $escapedkeyword);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';
$keyword = param("keyword") || '';
$escapedkeyword = escapeURL($keyword);
$searchtype = param("searchtype") || 'subject';

# extern vars
use vars qw(%lang_err);			# defined in lang/xy
use vars qw($_SUBJECT $_CHARSET);	# defined in maildb.pl

########################## MAIN ##############################

my $action = param("action");
if ($action eq "viewattachment") {
   viewattachment();
} elsif ($action eq "viewattfile") {
   viewattfile();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

###################### END MAIN ##############################

################ VIEWATTACHMENT ##################
sub viewattachment {	# view attachments inside a message
   my $messageid = param("message_id");
   my $nodeid = param("attachment_nodeid");
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
      printheader();
      $messageid = str2html($messageid);
      print "What the heck? Message $messageid seems to be gone!";
      printfooter(1);
      return;
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
      print qq|Content-Length: $length\n|,
            qq|Content-Transfer-Coding: binary\n|,
            qq|Connection: close\n|,
            qq|Content-Type: message/rfc822; name="$subject.msg"\n|;

      # ugly hack since ie5.5 is broken with disposition: attchment
      if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
         print qq|Content-Disposition: attachment; filename="$subject.msg"\n|;
      }
      print qq|\n|, ${$r_block};

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
#            $content = html4mailto($content, "$config{'ow_cgiurl'}/openwebmail-send.pl", "action=composemessage&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;sessionid=$thissession&amp;composetype=sendto");
         }

         my $length = length($content);
         my $contenttype = ${$r_attachment}{contenttype};
         my $filename = ${$r_attachment}{filename}; 
         $filename=~s/\s$//;

         # remove char disallowed in some fs
         if ($prefs{'charset'} eq 'big5') {
            $filename =~ s|([^\xA1-\xF9])\\|$1_|;	# dos path
         } elsif ($prefs{'charset'} eq 'gb2312') {
            $filename =~ s|([^\x81-\xFE])\\|$1_|;	# dos path
         } else {
            $filename =~ s|\\|_|;			# dos path
         }
         $filename =~ s|^.*/||;	# unix path
         $filename =~ s|^.*:||;	# mac path and dos drive

         # IE6 will crash if filename longer than 45, tricky!
         if (length($filename)>45) {
            $filename=~/^(.*)(\.[^\.]*)$/;
            $filename=substr($1, 0, 45-length($2)).$2;
         }
         $filename=~s/_*\._*/\./g;
         $filename=~s/__+/_/g;

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
         print qq|Content-Length: $length\n|,
               qq|Content-Transfer-Coding: binary\n|,
               qq|Connection: close\n|,
               qq|Content-Type: $contenttype; name="$filename"\n|;

         # ugly hack since ie5.5 is broken with disposition: attchment
         if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
            if ($contenttype =~ /^text/i) {
               print qq|Content-Disposition: inline; filename="$filename"\n|;
            } else {
               print qq|Content-Disposition: attachment; filename="$filename"\n|;
            }
         }

         # use undef to free memory before attachment transfer
         undef %{$r_attachment};
         undef $r_attachment;
         undef @{$r_attachments};
         undef $r_attachments;
         print qq|\n|, $content;
      } else {
         printheader();
         $messageid = str2html($messageid);
         print "What the heck? Message $messageid attachmment $nodeid seems to be gone!";
         printfooter(1);
      }
      return;

   }
}
################### END VIEWATTACHMENT ##################

################ VIEWATTFILE ##################
sub viewattfile {	# view attachments uploaded to $config{'ow_sessionsdir'}
   my $attfile=param("attfile");
   $attfile =~ s/\///g;  # just in case someone gets tricky ...
   # only allow to view attfiles belongs the $thissession
   if ($attfile!~/^$thissession/  || !-f "$config{'ow_sessionsdir'}/$attfile") {
      printheader();
      print "What the heck? Attfile $config{'ow_sessionsdir'}/$attfile seems to be gone!";
      printfooter(1);
      return;
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
   if ($prefs{'charset'} eq 'big5') {
      $attfilename =~ s|([^\xA1-\xF9])\\|$1_|;	# dos path
   } elsif ($prefs{'charset'} eq 'gb2312') {
      $attfilename =~ s|([^\x81-\xFE])\\|$1_|;	# dos path
   } else {
      $attfilename =~ s|\\|_|;			# dos path
   }
   $attfilename =~ s|^.*/||;	# unix path
   $attfilename =~ s|^.*:||;	# mac path and dos drive

   # IE6 will crash if filename longer than 45, tricky!
   if (length($attfilename)>45) {
      $attfilename=~/^(.*)(\.[^\.]*)$/;
      $attfilename=substr($1, 0, 45-length($2)).$2;
   }
   $attfilename=~s/_*\._*/\./g;
   $attfilename=~s/__+/_/g;

   if ($attencoding =~ /^base64$/i) {
      $attcontent = decode_base64($attcontent);
   } elsif ($attencoding =~ /^quoted-printable$/i) {
      $attcontent = decode_qp($attcontent);
   } elsif ($attencoding =~ /^x-uuencode$/i) {
      $attcontent = uudecode($attcontent);
   }

   my $length = length($attcontent);
   # disposition:inline default to open
   print qq|Content-Length: $length\n|,
         qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: $attcontenttype; name="$attfilename"\n|,
         qq|Content-Disposition: inline; filename="$attfilename"\n|,
         qq|\n|, $attcontent;

   return;
}
################### END VIEWATTATTFILE ##################

