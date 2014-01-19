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

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "modules/tnef.pl";
require "modules/htmltext.pl";
require "modules/htmlrender.pl";
require "modules/execute.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/lockget.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs);
use vars qw($quotausage $quotalimit);
use vars qw($htmltemplatefilters $po); # defined in ow-shared.pl

# extern vars
use vars qw($_SUBJECT $_CHARSET); # defined in maildb.pl

# local global
use vars qw($folder $messageid $sort $msgdatetype $page $longpage $searchtype $keyword);



# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the webmail module is not enabled.')) if !$config{enable_webmail};

# webmail globals
$folder          = param('folder') || 'INBOX';
$page            = param('page') || 1;
$longpage        = param('longpage') || 0;
$sort            = param('sort') || $prefs{sort} || 'date_rev';
$searchtype      = param('searchtype') || 'subject';
$keyword         = param('keyword') || '';
$msgdatetype     = param('msgdatetype') || $prefs{msgdatetype};
$messageid       = param('message_id') || '';

my $action = param('action') || '';

writelog("debug_request :: request viewatt begin, action=$action") if $config{debug_request};

$action eq 'viewattachment'                            ? viewattachment() :
$action eq 'viewattfile'                               ? viewattfile()    :
$action eq 'saveattfile'    && $config{enable_webdisk} ? saveattfile()    :
$action eq 'saveattachment' && $config{enable_webdisk} ? saveattachment() :
openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request viewatt end, action=$action") if $config{debug_request};

openwebmail_requestend();



# BEGIN SUBROUTINES

sub viewattachment {
   # view attachments inside a message
   my $nodeid      = param('attachment_nodeid');
   my $wordpreview = param('wordpreview') || 0;

   my ($attfilename, $length, $r_attheader, $r_attbody) = getattachment($folder, $messageid, $nodeid, $wordpreview);

   if (${$r_attheader} =~ m#Content-Type: text/#i && $length > 512 && is_http_compression_enabled()) {
      my $zattbody = Compress::Zlib::memGzip($r_attbody);
      undef ${$r_attbody};
      undef $r_attbody;
      my $zlen = length $zattbody;
      my $zattheader = qq|Content-Encoding: gzip\n|.
                       qq|Vary: Accept-Encoding\n|.
                       ${$r_attheader};
      $zattheader =~ s#Content\-Length: .*?\n#Content-Length: $zlen\n#ims;
      print $zattheader, "\n", $zattbody;
   } else {
      print ${$r_attheader}, "\n", ${$r_attbody};
   }

   return;
}

sub saveattachment {
   # save attachments inside a message to webdisk
   my $nodeid     = param('attachment_nodeid');
   my $webdisksel = param('webdisksel')||'';

   my ($attfilename, $length, $r_attheader, $r_attbody) = getattachment($folder, $messageid, $nodeid);
   savefile2webdisk($attfilename, $length, $r_attbody, $webdisksel);
}

sub getattachment {
   my ($folder, $messageid, $nodeid, $wordpreview) = @_;

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   my $folderhandle = do { no warnings 'once'; local *FH };

   my $block   = '';
   my $msgsize = lockget_message_block($messageid, $folderfile, $folderdb, \$block);
   openwebmailerror(gettext('Message ID can no longer be found:') . " ($messageid)") if $msgsize <= 0;

   my @attr = get_message_attributes($messageid, $folderdb);

   my $convfrom = param('convfrom') || '';
   if ($convfrom eq '') {
      $convfrom = is_convertible($attr[$_CHARSET], $prefs{charset})
                  ? lc($attr[$_CHARSET])
                  : "none\.$prefs{charset}";
   }

   if ($nodeid eq 'all') {
      # return whole message as an message/rfc822 object
      my ($subject) = iconv($convfrom, $prefs{charset}, $attr[$_SUBJECT]);
      $subject =~ s/\s+/_/g;

      my $length    = length($block);
      my $attheader = qq|Content-Length: $length\n|.
                      qq|Connection: close\n|.
                      qq|Content-Type: message/rfc822; name="$subject.msg"\n|;

      # disposition:attachment default to save
      if ($ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/) {
         # ie5.5 is broken with content-disposition: attachment
         $attheader .= qq|Content-Disposition: filename="$subject.msg"\n|;
      } else {
         $attheader .= qq|Content-Disposition: attachment; filename="$subject.msg"\n|;
      }

      # allow caching for messages in folders other than saved-drafts
      if ($folder ne 'saved-drafts') {
         $attheader .= qq|Expires: | . CGI::expires('+900s') . qq|\n|.
                       qq|Cache-Control: private,max-age=900\n|;
      }

      return("$subject.msg", $length, \$attheader, \$block);
   } else {
      # return a specific attachment
      my ($header, $body, $r_attachments) = ow::mailparse::parse_rfc822block(\$block, 0, $nodeid);
      undef($block);

      my $r_attachment = {};
      for (my $i = 0; $i <= $#{$r_attachments}; $i++) {
         if ($r_attachments->[$i]{nodeid} eq $nodeid) {
            $r_attachment = $r_attachments->[$i];
         }
      }

      if (defined $r_attachment) {
         my $charset     = $r_attachment->{filenamecharset} || $r_attachment->{charset} || $convfrom || $attr[$_CHARSET];
         my $contenttype = $r_attachment->{'content-type'};
         my $filename    = $r_attachment->{filename};
         $filename =~ s/\s$//;

         my $content = ow::mime::decode_content(${$r_attachment->{r_content}}, $r_attachment->{'content-transfer-encoding'});

         if ($contenttype =~ m#^application/ms\-tnef#) {
            # try to convert tnef -> zip/tgz/tar
            my $tnefbin = ow::tool::findbin('tnef');
            if ($tnefbin ne '') {
               my ($arcname, $r_arcdata) = ow::tnef::get_tnef_archive($tnefbin, $filename, \$content);
               if ($arcname ne '') { # tnef extraction and conversion successed
                  $filename    = $arcname;
                  $contenttype = ow::tool::ext2contenttype($filename);
                  $content     = ${$r_arcdata};
               }
            }
         }

         if ($contenttype =~ m#^text/html#i ) {
            # try to rendering html
            my $escapedfolder    = ow::tool::escapeURL($folder);
            my $escapedmessageid = ow::tool::escapeURL($messageid);
            $content = ow::htmlrender::html4nobase($content);
            $content = ow::htmlrender::html4disablejs($content) if $prefs{disablejs};
            $content = ow::htmlrender::html4disableembcode($content) if $prefs{disableembcode};
            $content = ow::htmlrender::html4disableemblink($content, $prefs{disableemblink}, "$config{ow_htmlurl}/images/backgrounds/Transparent.gif");
            $content = ow::htmlrender::html4attachments($content, $r_attachments, "$config{ow_cgiurl}/openwebmail-viewatt.pl", "action=viewattachment&amp;sessionid=$thissession&amp;message_id=$escapedmessageid&amp;folder=$escapedfolder");
         }

         $filename = (iconv($charset, $prefs{charset}, $filename))[0];

         # remove char disallowed in some filesystems
         if ($prefs{charset} eq 'big5' || $prefs{charset} eq 'gb2312') {
            $filename = ow::tool::zh_dospath2fname($filename, '_'); # dos path
         } else {
            $filename =~ s|\\|_|; # dos path
         }

         $filename =~ s|^.*/||;	# unix path
         $filename =~ s|^.*:||;	# mac path and dos drive
         $filename = safedlname($filename);

         # adjust att fname and contenttype
         if (
               $filename =~ m/\.(?:exe|com|bat|pif|lnk|scr)$/i
               && $contenttype !~ m/application\/octet\-stream/i
               && $contenttype !~ m/application\/x\-msdownload/i
            ) {
            # change attname from *.exe, *.com *.bat, *.pif, *.lnk, *.scr to *.file
            # if its contenttype is not application/octet-stream,
            # so this attachment will not be referenced by html and executed directly by Internet Explorer
            $filename = "$filename.file";
         } elsif ($filename =~ /\.(?:doc|dot)$/i && $wordpreview && msword2html(\$content)) {
            # in wordpreview mode?
            $contenttype = 'text/html';
         } elsif ($contenttype =~ m/^message\//i) {
            # set message contenttype to text/plain for easy view
            $contenttype = 'text/plain';
         } elsif ($contenttype =~ m/application\/octet\-stream/i) {
            # guess a better contenttype so attachment can be better displayed by browser
            $contenttype = ow::tool::ext2contenttype($filename);
         }

         my $length    = length($content);
         my $attheader = qq|Content-Length: $length\n|.
                         qq|Connection: close\n|.
                         qq|Content-Type: $contenttype; name="$filename"\n|;

         if ($contenttype =~ m/^text/i) {
            $attheader .= qq|Content-Disposition: inline; filename="$filename"\n|;
         } else {
            # disposition:attachment default to save
            if ($ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/) {
               # ie5.5 is broken with content-disposition: attachment
               $attheader .= qq|Content-Disposition: filename="$filename"\n|;
            } else {
               $attheader .= qq|Content-Disposition: attachment; filename="$filename"\n|;
            }
         }

         # allow cache for msg attachment in folder other than saved-drafts
         if ($folder ne 'saved-drafts') {
            $attheader .= qq|Expires: | . CGI::expires('+900s') . qq|\n|.
                          qq|Cache-Control: private,max-age=900\n|;
         }

         # use undef to free memory before attachment transfer
         undef %{$r_attachment};
         undef $r_attachment;
         undef @{$r_attachments};
         undef $r_attachments;

         return($filename, $length, \$attheader, \$content);
      } else {
         openwebmailerror(gettext('Message node can no longer be found:') . " ($messageid $nodeid)");
      }
   }
}

sub viewattfile {
   # view attachments uploaded to $config{ow_sessionsdir}
   my $wordpreview = param('wordpreview') || 0;
   my $attfile     = param('attfile') || '';
   $attfile =~ s/\///g; # just in case someone gets tricky ...

   my ($attfilename, $length, $r_attheader, $r_attbody) = getattfile($attfile, $wordpreview);

   if (${$r_attheader} =~ m!Content-Type: text/!i && $length > 512 && is_http_compression_enabled()) {
      my $zattbody = Compress::Zlib::memGzip($r_attbody);
      undef ${$r_attbody};
      undef $r_attbody;
      my $zlen = length $zattbody;
      my $zattheader = qq|Content-Encoding: gzip\n| .
                       qq|Vary: Accept-Encoding\n| .
                       ${$r_attheader};
      $zattheader =~ s!Content\-Length: .*?\n!Content-Length: $zlen\n!ims;
      print $zattheader, "\n", $zattbody;
   } else {
      print ${$r_attheader}, "\n", ${$r_attbody};
   }

   return undef;
}

sub saveattfile {
   # save attachments uploaded to $config{ow_sessiondir} to webdisk
   my $attfile    = param('attfile') || '';
   my $webdisksel = param('webdisksel') || '';

   my ($attfilename, $length, $r_attheader, $r_attbody) = getattfile($attfile);
   savefile2webdisk($attfilename, $length, $r_attbody, $webdisksel);
}

sub getattfile {
   my ($attfile, $wordpreview) = @_;

   # only allow to view attfiles belongs the $thissession
   openwebmailerror(gettext('Attachment file can no longer be found:') . " ($config{ow_sessionsdir}/$attfile)")
      if $attfile !~ m/^\Q$thissession\E/ || !-f "$config{ow_sessionsdir}/$attfile";

   sysopen(ATTFILE, "$config{ow_sessionsdir}/$attfile", O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$attfile ($!)");

   local $/ = "\n\n";

   my $attheader = <ATTFILE>;  # read until 1st blank line

   undef $/;

   my $attcontent = <ATTFILE>; # read until file end

   close(ATTFILE);

   my %att = ();
   $att{'content-type'} = 'application/octet-stream'; # assume att is binary

   ow::mailparse::parse_header(\$attheader, \%att);

   ($att{filename}, $att{filenamecharset}) =
      ow::mailparse::get_filename_charset($att{'content-type'}, $att{'content-disposition'});

   $attcontent = ow::mime::decode_content($attcontent, $att{'content-transfer-encoding'});

   if ($wordpreview && $att{filename} =~ /\.(?:doc|dot)$/i && msword2html(\$attcontent)) {
       # in wordpreview mode?
       $attheader =~ s!$att{'content-type'}!text/html!;
       $att{'content-type'} = 'text/html';
   }

   # rebuild attheader for download, disposition:inline means default to open
   my $length = length($attcontent);
   $attheader = qq|Content-Length: $length\n|.
                qq|Connection: close\n|.
                qq|Content-Type: $att{'content-type'}; name="$att{filename}"\n|.
                qq|Content-Disposition: inline; filename="$att{filename}"\n|;

   # allow cache for attfile since its filename is based on times()
   $attheader .= qq|Expires: | . CGI::expires('+900s') . qq|\n| .
                 qq|Cache-Control: private,max-age=900\n|;

   return ($att{filename}, $length, \$attheader, \$attcontent);
}

sub savefile2webdisk {
   my ($filename, $length, $r_content, $webdisksel) = @_;

   if ($quotalimit > 0 && $quotausage + $length / 1024 > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate quotausage
      autoclosewindow(gettext('QUOTA HIT'), gettext('Quota limit exceeded. Please delete some messages or webdisk files to free disk space.'))
         if ($quotausage + $length / 1024 > $quotalimit);
   }

   # webdisksel is from webdisk.pl and it is originally in $prefs{charset}
   # so we have to convert it into fscharset before doing the vpath calculation
   $webdisksel = u2f($webdisksel);

   my $webdiskrootdir = ow::tool::untaint($homedir.absolute_vpath('/', $config{webdisk_rootpath}));
   my $vpath          = absolute_vpath('/', $webdisksel);
   my $vpathstr       = (iconv($prefs{fscharset}, $prefs{charset}, $vpath))[0];
   verify_vpath($webdiskrootdir, $vpath);

   if (-d "$webdiskrootdir/$vpath") {
      # use choose a dirname, save att with its original name
      $vpath    = absolute_vpath($vpath, $filename);
      $vpathstr = (iconv($prefs{fscharset}, $prefs{charset}, $vpath))[0];
      verify_vpath($webdiskrootdir, $vpath);
   }

   $vpath = ow::tool::untaint($vpath);

   ow::tool::rotatefilename("$webdiskrootdir/$vpath") if -f "$webdiskrootdir/$vpath";

   sysopen(F, "$webdiskrootdir/$vpath", O_WRONLY|O_TRUNC|O_CREAT) or
      autoclosewindow(gettext('System Error'), gettext('Cannot open file:') . " $vpathstr ($!)");

   ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_EX) or
      autoclosewindow(gettext('System Error'), gettext('Cannot lock file:') . " ($vpathstr)");

   print F ${$r_content};

   close(F) or
      autoclosewindow(gettext('System Error'), gettext('Cannot close file:') . " $vpathstr ($!)");

   chmod(0644, "$webdiskrootdir/$vpath");

   ow::filelock::lock("$webdiskrootdir/$vpath", LOCK_UN) or
      autoclosewindow(gettext('System Error'), gettext('Cannot unlock file:') . " ($vpathstr)");

   writelog("save attachment - $vpath");
   writehistory("save attachment - $vpath");

   autoclosewindow(gettext('Save File'), gettext('The file was saved successfully:') . " ($vpathstr)");
}

sub msword2html {
   my $r_content = shift;

   my $antiwordbin = ow::tool::findbin('antiword');
   return 0 if $antiwordbin eq '';

   my ($tmpfh, $tmpfile) = ow::tool::mktmpfile('msword2html.tmpfile');

   my $err = 0;
   print $tmpfh ${$r_content} or $err++;

   close($tmpfh);

   if ($err) {
      unlink($tmpfile);
      return 0;
   }

   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute($antiwordbin, '-m', 'UTF-8.txt', $tmpfile);

   unlink($tmpfile);

   return 0 if $exit || $sig;

   my $charset = $prefs{charset};
   if (is_convertible('utf-8', $prefs{charset})) {
      $stdout = (iconv('utf-8', $prefs{charset}, $stdout))[0];
   } else {
      $charset = 'utf-8';
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('viewatt_wordpreview.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      charset => $charset,
                      text    => $stdout,
                   );

   ${$r_content} = $template->output;

   return 1;
}

