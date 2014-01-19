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

# TODO: refactor all of the code in this file. Lots of reuse here, and strangely organized

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
use Net::SMTP;

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
require "modules/htmlrender.pl";
require "modules/enriched.pl";
require "modules/tnef.pl";
require "modules/wget.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/getmessage.pl";
require "shares/lockget.pl";
require "shares/statbook.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config $thissession %prefs $icons);
use vars qw($loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw($htmltemplatefilters $po);                                             # defined in ow-shared.pl
use vars qw(%charset_convlist);                                                    # defined in iconv.pl
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_STATUS $_CHARSET $_REFERENCES); # defined in maildb.pl

# local globals
use vars qw($folder $sort $msgdatetype $page $longpage $keyword $searchtype);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the webmail module is not enabled.')) unless $config{enable_webmail};

$folder      = param('folder') || 'INBOX';
$sort        = param('sort') || $prefs{sort} || 'date_rev';
$msgdatetype = param('msgdatetype') || $prefs{msgdatetype};
$page        = param('page') || 1;
$longpage    = param('longpage') || 0;
$searchtype  = param('searchtype') || 'subject';
$keyword     = param('keyword') || '';

my $action   = param('action') || '';

writelog("debug_request :: request send begin, action=$action") if $config{debug_request};

$action eq 'compose'      ? compose()      :
$action eq 'replyreceipt' ? replyreceipt() :
$action eq 'sendmessage'  ?
                            !defined param('savedraftbutton')
                            && !(defined param('sendbutton') && (param('to') || param('cc') || param('bcc')))
                            ? compose() : sendmessage()
                          :
openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request send end, action=$action") if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub compose {
   my $compose_caller   = param('compose_caller') || '';

   my @tos              = param('to');
   my @ccs              = param('cc');
   my @bccs             = param('bcc');

   my $messageid        = param('message_id') || '';                         # messageid for the original message being replied/forwarded/edited
   my $mymessageid      = param('mymessageid') ||'';                         # messageid for the message we are composing

   my $forward_batchid  = param('forward_batchid');                          # batch id of forward file stored from openwebmail-main copy or move buttons

   my $from             = param('from') || '';
   my $subject          = param('subject') || '';
   my $body             = param('body') || '';
   my $replyto          = param('replyto') || '';
   my $inreplyto        = param('inreplyto') || '';
   my $references       = param('references') || '';
   my $priority         = param('priority') || 'normal';                     # normal, urgent, or non-urgent
   my $confirmreading   = param('confirmreading') || 0;
   my $backupsent       = (defined param('backupsent') && param('backupsent'))
                          ? param('backupsent') : $prefs{backupsentmsg};

   my $stationeryname   = param('stationeryname') || '';

   my $composetype      = param('composetype') || 'none';
   my $msgformat        = param('msgformat') || $prefs{msgformat} || 'text'; # text, html, both, or auto
   my $newmsgformat     = param('newmsgformat') || $msgformat;
   my $composecharset   = param('composecharset') || $prefs{charset};
   my $convfrom         = param('convfrom') || '';
   my $convto           = param('convto') || 'none';
   my $showhtmlastext   = param('showhtmlastext') || '';
   my $show_phonekbd    = param('show_phonekbd') || 0;                       # big5 phonetic keyboard

   my $addbutton        = param('addbutton') || '';                          # add attachment button clicked
   my $webdiskselection = param('webdiskselection') || '';                   # attachment file selected from webdisk
   my $urlselection     = param('urlselection') || '';                       # attachment is a url we need to retrieve
   my $deleteattfile    = param('deleteattfile') || '';                      # delete attachment link clicked
   my $attachment       = param('attachment') || '';                         # uploaded attachment filename

   my $sendbutton       = param('sendbutton') || '';
   my $savedraftbutton  = param('savedraftbutton') || '';
   my $session_noupdate = param('session_noupdate') || 0;

   my $abookfolder      = param('abookfolder') || '';
   my $abookpage        = param('abookpage') || 1;
   my $abooksort        = param('abooksort') || '';
   my $abookkeyword     = param('abookkeyword') || '';
   my $abooksearchtype  = param('abooksearchtype') || '';
   my $abookcollapse    = param('abookcollapse') || 0;

   # build unique to, cc, and bcc lists.
   my (%unique_to, %unique_cc, %unique_bcc) = ((),(),());
   my $to  = join(", ", sort { lc $a cmp lc $b } grep { defined && m/\S/ && !$unique_to{$_}++ } map { ow::tool::str2list($_) } @tos) || '';
   my $cc  = join(", ", sort { lc $a cmp lc $b } grep { defined && m/\S/ && !$unique_cc{$_}++ } map { ow::tool::str2list($_) } @ccs) || '';
   my $bcc = join(", ", sort { lc $a cmp lc $b } grep { defined && m/\S/ && !$unique_bcc{$_}++ } map { ow::tool::str2list($_) } @bccs) || '';

   # establish the user from id unless there already is one
   my $userfroms = get_userfroms();
   $from = (
             exists $userfroms->{$prefs{email}} && $userfroms->{$prefs{email}}
             ? qq|"$userfroms->{$prefs{email}}" <$prefs{email}>|
             : $prefs{email}
           ) unless $from;

   # make sure we have a messageid for the message we're composing
   $mymessageid = generate_messageid((ow::tool::email2nameaddr($from))[1]) unless $mymessageid;

   # we prefer to use the messageid in a draft message if available
   $mymessageid = $messageid if $composetype eq 'editdraft' && $messageid;

   # generate a unique id for all attachments belonging to this message, based on the messageid of this message
   my $attachments_uid = length $mymessageid > 22 ? substr($mymessageid,0,22) : $mymessageid;
   $attachments_uid =~ s#[<>@"'&;]##g;

   # get browser javascript support level (none,nn4,ie,dom)
   my $enable_htmlcompose = cookie('ow-browserjavascript') eq 'dom' ? 1 : 0;

   # force msgformat to text if html composing is not supported
   $msgformat = $newmsgformat = 'text' unless $enable_htmlcompose;

   $composecharset = $prefs{charset} unless ow::lang::is_charset_supported($composecharset) || exists $charset_convlist{$composecharset};

   if ($convfrom =~ m/^none\.(.*)$/) {
      # convfrom is a charset manually chosen by the user during last message reading
      $composecharset = $1 if ow::lang::is_charset_supported($1);
   }

   # before we convert the message for display we need to process
   # all of the attachments in order to properly support cid
   # links if there are any (adding or deleting attachments)
   if ($deleteattfile) {
      # user is trying to delete an attachment
      $deleteattfile =~ s/\///g; # safety

      # only delete attachment files that belong to this $thissession
      unlink (ow::tool::untaint("$config{ow_sessionsdir}/$deleteattfile")) if $deleteattfile =~ m/^\Q$thissession-$attachments_uid\E/;
   } elsif ($addbutton || $webdiskselection || $urlselection) {
      my($attachment_filename, $attachment_contenttype) = add_attachment($attachments_uid);
   } elsif ($composetype ne 'continue') {
      # remove previous aged attachments
      delete_attachments($attachments_uid);
   }

   # get the info about all of our attachments now that all modifications are complete
   my ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

   # ***************************************************
   # HOW IT SHOULD WORK (someday in the future):
   # build the composing message headers
   # to list
   # cc list
   # subject
   # references

   # handle the attachments
   # we need the list of attachments to properly build the
   # message body cid/loc for embedded attachments

   # build the composing message content
   # replycontent (the original message reformatted for our reply/forward)
   # composecontent (stationery and/or signature)

   # put it all together
   # replywithorigmsg atbeginning or atend
   # ***************************************************

   # format the original message body for inline display based on the compose type
   # there are 9 different compose types:
   # none           # user is composing a new mail
   # continue       # user is adding an attachment or changing a parameter during compose
   # reply          # user is replying to the sender of a message
   # replyall       # user is replying to the sender and recipients of a message
   # forward        # user is forwarding the message as inline reply content
   # forwardasorig  # user is forwarding the message as if user composed it originally
   # forwardasatt   # user is forwarding the message as an attachment to a new message
   # editdraft      # user is editing a previously saved draft message
   # sendto         # user is composing a new mail with a recipient already set

   if ($composetype eq 'none') {
      # ****************************
      # user is composing a new mail
      # ****************************
      $msgformat = 'text' if $msgformat eq 'auto';

      if (defined $prefs{autocc} && $prefs{autocc} ne '') {
         $cc .= ', ' if $cc ne '';
         $cc .= (iconv($prefs{charset}, $composecharset, $prefs{autocc}))[0];
      }

      $replyto = (iconv($prefs{charset}, $composecharset, $prefs{replyto}))[0] if defined $prefs{replyto};

      if ($prefs{signature} =~ m#[^\s]#) {
         $body .= $msgformat eq 'text'
                  ? "\n\n"     . str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat) . "\n"
                  : "<br><br>" . str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat) . "<br>";
      }

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   } elsif ($composetype eq 'continue') {
      # *******************************************************************
      # user is adding an attachment or changing a parameter during compose
      # *******************************************************************
      $msgformat    = 'text' if $msgformat eq 'auto';
      $newmsgformat = 'text' if $newmsgformat eq 'auto';

      ($body, $subject, $from, $to, $cc, $bcc, $replyto) = iconv($composecharset, $convto, $body,$subject,$from,$to,$cc,$bcc,$replyto);

      $composecharset = $convto if ow::lang::is_charset_supported($convto) || exists $charset_convlist{$convto};

      if ($msgformat eq 'text' && $newmsgformat ne 'text') {
         $body = ow::htmltext::text2html($body);
      } elsif ($msgformat ne 'text' && $newmsgformat eq 'text') {
         $body = ow::htmltext::html2text($body);
      }

      $msgformat = $newmsgformat;

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;
      }
   } elsif ($composetype eq 'reply') {
      # *******************************************
      # user is replying to the sender of a message
      # *******************************************
      # get the original message with attachments (all mode)
      my $message = getmessage($user, $folder, $messageid, 'all');

      my $bodyformat = '';
      ($body, $bodyformat) = decode_message_body($msgformat, $message);

      if ($bodyformat eq 'html') {
         store_attachments($attachments_uid, $composecharset, $convfrom, $message);
         ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

         $body = ow::htmlrender::html4nobase($body);
         $body = ow::htmlrender::html4disablejs($body) if $prefs{disablejs};
         $body = ow::htmlrender::html4disableembcode($body) if $prefs{disableembcode};
         $body = ow::htmlrender::html4disableemblink($body, $prefs{disableemblink}, "$config{ow_htmlurl}/images/backgrounds/Transparent.gif");
         $body = ow::htmlrender::html4attfiles($body, $r_attfiles, "$config{ow_cgiurl}/openwebmail-viewatt.pl", "action=viewattfile&sessionid=$thissession");
         $body = ow::htmlrender::html2block($body);

         # only keep attachments that are being referenced in the body via cid or loc
         unlink(ow::tool::untaint("$config{ow_sessionsdir}/$_->{file}")) for grep { !exists $_->{referencecount} || $_->{referencecount} < 1 } @{$r_attfiles};
         @{$r_attfiles} = grep { exists $_->{referencecount} && $_->{referencecount} } @{$r_attfiles};
      }

      if ($msgformat eq 'auto') {
         $msgformat = $bodyformat;
         $msgformat = 'both' if $msgformat eq 'html';

         $showhtmlastext = $prefs{showhtmlastext} if $showhtmlastext eq '';
         $msgformat = 'text' if $showhtmlastext;
      }

      if ($bodyformat eq 'text' && $msgformat ne 'text')  {
         $body = ow::htmltext::text2html($body);
      } elsif ($bodyformat ne 'text' && $msgformat eq 'text')  {
         $body = ow::htmltext::html2text($body);
      }

      # auto set the from to match the userfrom the message was sent to
      my $fromemail = (grep { $message->{to} =~ m/$_/i || $message->{cc} =~ m/$_/i } keys %{$userfroms})[0] || $prefs{email};

      if (exists $userfroms->{$fromemail} && $userfroms->{$fromemail} ne '') {
         $from = qq|"$userfroms->{$fromemail}" <$fromemail>|;
      } else {
         $from = $fromemail;
      }

      my $replyprefix = gettext('Re:');
      $subject = $message->{subject} || gettext('(no subject)');
      $subject = "$replyprefix $subject" unless $subject =~ m#^\Q$replyprefix\E#i;

      if (exists $message->{'reply-to'} && defined $message->{'reply-to'} && $message->{'reply-to'} =~ m#[^\s]#) {
         $to = $message->{'reply-to'} || '';
      } else {
         $to = $message->{from} || '';
      }

      ($subject, $to, $cc) = iconv('utf-8',$composecharset,$subject,$to,$cc);

      if ($msgformat eq 'text') {
         # reparagraph orig msg for better look in compose window
         $body = reparagraph($body, $prefs{editcolumns} - 8) if $prefs{reparagraphorigmsg};

         # remove odds space or blank lines from body
         $body =~ s/(?: *\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;
         $body =~ s/\s+$//;

         # add reply '>'s at the beginning of each line of the original message
         $body =~ s/\n/\n\> /g;
         $body = "> $body" if $body =~ m/[^\s]/;
      } else {
         # remove all reference to inline attachments
         # because we don't carry them from original message when replying
         $body =~ s/<[^\<\>]*?(?:background|src)\s*=[^\<\>]*?cid:[^\<\>]*?>//sig;

         # replace <p> with <br> to strip blank lines
         $body =~ s#<(?:p|p [^\<\>]*?)>#<br>#gi;
         $body =~ s#</p>##gi;

         # replace <div> with <br> to strip layer and add blank lines
         $body =~ s#<(?:div|div [^\<\>]*?)>#<br>#gi;
         $body =~ s#</div>##gi;

         $body =~ s#<br ?/?>(?:\s*<br ?/?>)+#<br><br>#gis;
         $body =~ s#^(?:\s*<br ?/?>)*##gi;
         $body =~ s#(?:<br ?/?>\s*)*$##gi;
         $body =~ s#(<br ?/?>|<div>|<div [^\<\>]*?>)#$1&gt; #gis;
         $body = "&gt; $body";
      }

      if ($prefs{replywithorigmsg} eq 'at_beginning') {
         my $replyheader = gettext('On <tmpl_var messagedate escape="none">, <tmpl_var fromnameaddr escape="none"> wrote');

         my $template = HTML::Template->new(scalarref => \$replyheader);
         $template->param(
                            messagedate  => $message->{date},
                            fromnameaddr => (ow::tool::email2nameaddr($message->{from}))[0] || gettext('Unknown'),
                         );

         my $replyheading = $template->output;
         ($replyheading) = iconv('utf-8', $composecharset, $replyheading);

         ($body) = iconv($convfrom, $composecharset, $body);

         if ($msgformat eq 'text') {
            $body = "$replyheading\n$body" if $body =~ m#[^\s]#;
         } else {
            $body = '<b>' . ow::htmltext::text2html($replyheading) . "</b><br>$body";
         }
      } elsif ($prefs{replywithorigmsg} eq 'at_end') {
         my $replyheading = gettext('From:') . $message->{from} . "\n" .
                            gettext('To:') . $message->{to} . "\n" .
                            ((exists $message->{cc} && $message->{cc} ne '') ? gettext('Cc:') . $message->{cc} . "\n" : '') .
                            gettext('Sent:') . $message->{date} . "\n" .
                            gettext('Subject:') . $message->{subject} . "\n";
         ($replyheading) = iconv('utf-8', $composecharset, $replyheading);

         ($body) = iconv($convfrom, $composecharset, $body);

         if ($msgformat eq 'text') {
            $body = gettext('---------- Original Message -----------') . "\n" .
                    $replyheading . "\n" .
                    $body . "\n" .
                    gettext('------- End of Original Message -------') . "\n";
         } else {
            $body = "<b>" . gettext('---------- Original Message -----------') . "</b><br>\n" .
                    ow::htmltext::text2html($replyheading) .
                    "<br>$body<br>" .
                    "<b>" . gettext('------- End of Original Message -------') . "</b><br>\n";
         }
      }

      if (defined $prefs{autocc} && $prefs{autocc} ne '') {
         $cc .= ', ' if $cc ne '';
         $cc .= (iconv($prefs{charset}, $composecharset, $prefs{autocc}))[0];
      }

      $replyto = (iconv($prefs{charset}, $composecharset, $prefs{replyto}))[0] if defined $prefs{replyto};
      $inreplyto = $message->{'message-id'};

      if ($message->{references} =~ m#\S#) {
         $references = "$message->{references} $message->{'message-id'}";
      } elsif ($message->{'in-reply-to'} =~ m#\S#) {
         my $string = $message->{'in-reply-to'};
         $string =~ s/^.*?(\<\S+\>).*$/$1/;
         $references = "$string $message->{'message-id'}";
      } else {
         $references = $message->{'message-id'};
      }

      my $origbody = $body;

      my $stationerycontent = '';
      if ($config{enable_stationery} && $stationeryname ne '') {
         my $stationerybookfile = dotpath('stationery.book');
         if (-f $stationerybookfile) {
            my %stationery = ();
            my ($ret, $errmsg) = read_stationerybook($stationerybookfile, \%stationery);
            $stationerycontent = (iconv($stationery{$stationeryname}{charset}, $composecharset, $stationery{$stationeryname}{content}))[0]
              if ($ret == 0);
         }
      }

      my $endofline = $msgformat eq 'text' ? "\n" : "<br>";

      if ($stationerycontent =~ m#[^\s]#) {
         $body = str2str($stationerycontent, $msgformat) . $endofline;
      } else {
         $body = $endofline . $endofline;
      }

      $body .= str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat) . $endofline
        if $prefs{signature} =~ m#[^\s]#;

      if ($prefs{replywithorigmsg} eq 'at_beginning') {
         $body = $origbody . $endofline . $body;
      } elsif ($prefs{replywithorigmsg} eq 'at_end') {
         $body = $body . $endofline . $origbody;
      }

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   } elsif ($composetype eq 'replyall') {
      # **********************************************************
      # user is replying to the sender and recipients of a message
      # **********************************************************
      # get the original message with attachments (all mode)
      my $message = getmessage($user, $folder, $messageid, 'all');

      my $bodyformat = '';
      ($body, $bodyformat) = decode_message_body($msgformat, $message);

      if ($bodyformat eq 'html') {
         store_attachments($attachments_uid, $composecharset, $convfrom, $message);
         ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

         $body = ow::htmlrender::html4nobase($body);
         $body = ow::htmlrender::html4disablejs($body) if $prefs{disablejs};
         $body = ow::htmlrender::html4disableembcode($body) if $prefs{disableembcode};
         $body = ow::htmlrender::html4disableemblink($body, $prefs{disableemblink}, "$config{ow_htmlurl}/images/backgrounds/Transparent.gif");
         $body = ow::htmlrender::html4attfiles($body, $r_attfiles, "$config{ow_cgiurl}/openwebmail-viewatt.pl", "action=viewattfile&sessionid=$thissession");
         $body = ow::htmlrender::html2block($body);

         # only keep attachments that are being referenced in the body via cid or loc
         unlink(ow::tool::untaint("$config{ow_sessionsdir}/$_->{file}")) for grep { !exists $_->{referencecount} || $_->{referencecount} < 1 } @{$r_attfiles};
         @{$r_attfiles} = grep { exists $_->{referencecount} && $_->{referencecount} } @{$r_attfiles};
      }

      if ($msgformat eq 'auto') {
         $msgformat = $bodyformat;
         $msgformat = 'both' if $msgformat eq 'html';

         $showhtmlastext = $prefs{showhtmlastext} if $showhtmlastext eq '';
         $msgformat = 'text' if $showhtmlastext;
      }

      if ($bodyformat eq 'text' && $msgformat ne 'text')  {
         $body = ow::htmltext::text2html($body);
      } elsif ($bodyformat ne 'text' && $msgformat eq 'text')  {
         $body = ow::htmltext::html2text($body);
      }

      # auto set the from to match the userfrom the message was sent to
      my $fromemail = (grep { $message->{to} =~ m/$_/i || $message->{cc} =~ m/$_/i } keys %{$userfroms})[0] || $prefs{email};

      if (exists $userfroms->{$fromemail} && $userfroms->{$fromemail} ne '') {
         $from = qq|"$userfroms->{$fromemail}" <$fromemail>|;
      } else {
         $from = $fromemail;
      }

      my $replyprefix = gettext('Re:');
      $subject = $message->{subject} || gettext('(no subject)');
      $subject = "$replyprefix $subject" unless $subject =~ m#^\Q$replyprefix\E#i;

      if (exists $message->{'reply-to'} && defined $message->{'reply-to'} && $message->{'reply-to'} =~ m#[^\s]#) {
         $to = $message->{'reply-to'} || '';
      } else {
         $to = $message->{from} || '';
      }

      # add everyone else who this message was sent to
      my @recv   = ();
      my $toaddr = (ow::tool::email2nameaddr($to))[1];
      foreach my $email (ow::tool::str2list($message->{to})) {
         my $addr = (ow::tool::email2nameaddr($email))[1];
         next if ($addr eq $fromemail || $addr eq $toaddr || $addr =~ m/^\s*$/ || $addr =~ m/undisclosed\-recipients:\s?;?/i);
         push(@recv, $email);
      }
      $to .= ', ' . join(', ', @recv) if scalar @recv > 0;

      # add everyone else who was cc'd
      @recv = ();
      foreach my $email (ow::tool::str2list($message->{cc})) {
         my $addr = (ow::tool::email2nameaddr($email))[1];
         next if ($addr eq $fromemail || $addr eq $toaddr || $addr =~ m/^\s*$/ || $addr =~ m/undisclosed\-recipients:\s?;?/i);
         push(@recv, $email);
      }
      $cc = join(', ', @recv) if scalar @recv > 0;

      ($subject, $to, $cc) = iconv('utf-8',$composecharset,$subject,$to,$cc);

      if ($msgformat eq 'text') {
         # reparagraph orig msg for better look in compose window
         $body = reparagraph($body, $prefs{editcolumns} - 8) if $prefs{reparagraphorigmsg};

         # remove odds space or blank lines from body
         $body =~ s/(?: *\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;
         $body =~ s/\s+$//;

         # add reply '>'s at the beginning of each line of the original message
         $body =~ s/\n/\n\> /g;
         $body = "> $body" if $body =~ m/[^\s]/;
      } else {
         # remove all reference to inline attachments
         # because we don't carry them from original message when replying
         $body =~ s/<[^\<\>]*?(?:background|src)\s*=[^\<\>]*?cid:[^\<\>]*?>//sig;

         # replace <p> with <br> to strip blank lines
         $body =~ s#<(?:p|p [^\<\>]*?)>#<br>#gi;
         $body =~ s#</p>##gi;

         # replace <div> with <br> to strip layer and add blank lines
         $body =~ s#<(?:div|div [^\<\>]*?)>#<br>#gi;
         $body =~ s#</div>##gi;

         $body =~ s#<br ?/?>(?:\s*<br ?/?>)+#<br><br>#gis;
         $body =~ s#^(?:\s*<br ?/?>)*##gi;
         $body =~ s#(?:<br ?/?>\s*)*$##gi;
         $body =~ s#(<br ?/?>|<div>|<div [^\<\>]*?>)#$1&gt; #gis;
         $body = "&gt; $body";
      }

      if ($prefs{replywithorigmsg} eq 'at_beginning') {
         my $replyheader = gettext('On <tmpl_var messagedate escape="none">, <tmpl_var fromnameaddr escape="none"> wrote');

         my $template = HTML::Template->new(scalarref => \$replyheader);
         $template->param(
                            messagedate  => $message->{date},
                            fromnameaddr => (ow::tool::email2nameaddr($message->{from}))[0] || gettext('Unknown'),
                         );

         my $replyheading = $template->output;
         ($replyheading) = iconv('utf-8', $composecharset, $replyheading);

         ($body) = iconv($convfrom, $composecharset, $body);

         if ($msgformat eq 'text') {
            $body = "$replyheading\n$body" if $body =~ m#[^\s]#;
         } else {
            $body = '<b>' . ow::htmltext::text2html($replyheading) . "</b><br>$body";
         }
      } elsif ($prefs{replywithorigmsg} eq 'at_end') {
         my $replyheading = gettext('From:') . $message->{from} . "\n" .
                            gettext('To:') . $message->{to} . "\n" .
                            ((exists $message->{cc} && $message->{cc} ne '') ? gettext('Cc:') . $message->{cc} . "\n" : '') .
                            gettext('Sent:') . $message->{date} . "\n" .
                            gettext('Subject:') . $message->{subject} . "\n";
         ($replyheading) = iconv('utf-8', $composecharset, $replyheading);

         ($body) = iconv($convfrom, $composecharset, $body);

         if ($msgformat eq 'text') {
            $body = gettext('---------- Original Message -----------') . "\n" .
                    $replyheading . "\n" .
                    $body . "\n" .
                    gettext('------- End of Original Message -------') . "\n";
         } else {
            $body = "<b>" . gettext('---------- Original Message -----------') . "</b><br>\n" .
                    ow::htmltext::text2html($replyheading) .
                    "<br>$body<br>" .
                    "<b>" . gettext('------- End of Original Message -------') . "</b><br>\n";
         }
      }

      if (defined $prefs{autocc} && $prefs{autocc} ne '') {
         $cc .= ', ' if $cc ne '';
         $cc .= (iconv($prefs{charset}, $composecharset, $prefs{autocc}))[0];
      }

      $replyto = (iconv($prefs{charset}, $composecharset, $prefs{replyto}))[0] if defined $prefs{replyto};
      $inreplyto = $message->{'message-id'};

      if ($message->{references} =~ m#\S#) {
         $references = "$message->{references} $message->{'message-id'}";
      } elsif ($message->{'in-reply-to'} =~ m#\S#) {
         my $string = $message->{'in-reply-to'};
         $string =~ s/^.*?(\<\S+\>).*$/$1/;
         $references = "$string $message->{'message-id'}";
      } else {
         $references = $message->{'message-id'};
      }

      my $origbody = $body;

      my $stationerycontent = '';
      if ($config{enable_stationery} && $stationeryname ne '') {
         my $stationerybookfile = dotpath('stationery.book');
         if (-f $stationerybookfile) {
            my %stationery = ();
            my ($ret, $errmsg) = read_stationerybook($stationerybookfile, \%stationery);
            $stationerycontent = (iconv($stationery{$stationeryname}{charset}, $composecharset, $stationery{$stationeryname}{content}))[0]
              if ($ret == 0);
         }
      }

      my $endofline = $msgformat eq 'text' ? "\n" : "<br>";

      if ($stationerycontent =~ m#[^\s]#) {
         $body = str2str($stationerycontent, $msgformat) . $endofline;
      } else {
         $body = $endofline . $endofline;
      }

      $body .= str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat) . $endofline
        if $prefs{signature} =~ m#[^\s]#;

      if ($prefs{replywithorigmsg} eq 'at_beginning') {
         $body = $origbody . $endofline . $body;
      } elsif ($prefs{replywithorigmsg} eq 'at_end') {
         $body = $body . $endofline . $origbody;
      }

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   } elsif ($composetype eq 'forward') {
      # ******************************************************
      # user is forwarding the message as inline reply content
      # ******************************************************
      # get the original message with attachments (all mode)
      my $message = getmessage($user, $folder, $messageid, 'all');

      my $bodyformat = '';
      ($body, $bodyformat) = decode_message_body($msgformat, $message);

      store_attachments($attachments_uid, $composecharset, $convfrom, $message);
      ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

      if ($bodyformat eq 'html') {
         $body = ow::htmlrender::html4nobase($body);
         $body = ow::htmlrender::html4disablejs($body) if $prefs{disablejs};
         $body = ow::htmlrender::html4disableembcode($body) if $prefs{disableembcode};
         $body = ow::htmlrender::html4disableemblink($body, $prefs{disableemblink}, "$config{ow_htmlurl}/images/backgrounds/Transparent.gif");
         $body = ow::htmlrender::html4attfiles($body, $r_attfiles, "$config{ow_cgiurl}/openwebmail-viewatt.pl", "action=viewattfile&sessionid=$thissession");
         $body = ow::htmlrender::html2block($body);
      }

      if ($msgformat eq 'auto') {
         $msgformat = $bodyformat;
         $msgformat = 'both' if $msgformat eq 'html';

         $showhtmlastext = $prefs{showhtmlastext} if $showhtmlastext eq '';
         $msgformat = 'text' if $showhtmlastext;
      }

      if ($bodyformat eq 'text' && $msgformat ne 'text')  {
         $body = ow::htmltext::text2html($body);
      } elsif ($bodyformat ne 'text' && $msgformat eq 'text')  {
         $body = ow::htmltext::html2text($body);
      }

      # auto set the from to match the userfrom the message was sent to
      my $fromemail = (grep { $message->{to} =~ m/$_/i || $message->{cc} =~ m/$_/i } keys %{$userfroms})[0] || $prefs{email};

      if (exists $userfroms->{$fromemail} && $userfroms->{$fromemail} ne '') {
         $from = qq|"$userfroms->{$fromemail}" <$fromemail>|;
      } else {
         $from = $fromemail;
      }

      my $forwardprefix = gettext('Fw:');
      $subject = $message->{subject} || gettext('(no subject)');
      $subject = "$forwardprefix $subject" unless $subject =~ m#^\Q$forwardprefix\E#i;

      my $forwardheading = gettext('From:') . $message->{from} . "\n" .
                           gettext('To:') . $message->{to} . "\n" .
                           ($message->{cc} ne '' ? gettext('Cc:') . $message->{cc} . "\n" : '') .
                           gettext('Sent:') . $message->{date} . "\n" .
                           gettext('Subject:') . $message->{subject} . "\n";

      $forwardheading = (iconv('utf-8', $composecharset, $forwardheading))[0];
      $subject        = (iconv('utf-8', $composecharset, $subject))[0];
      $body           = (iconv($convfrom, $composecharset, $body))[0];

      if ($msgformat eq 'text') {
         # remove odd spaces or blank lines from body
         $body =~ s/( *\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;
         $body =~ s/\s+$//;

         $body = qq|\n| .
                 gettext('---------- Forwarded Message -----------') . "\n" .
                 qq|$forwardheading\n| .
                 qq|$body\n| .
                 gettext('------- End of Forwarded Message -------') . "\n";
      } else {
         $body =~ s/<br>(\s*<br>)+/<br><br>/gis;
         $body = "<br>\n" .
                 '<b>' . gettext('---------- Forwarded Message -----------') . "</b><br>\n" .
                 ow::htmltext::text2html($forwardheading) .
                 qq|<br>$body<br>| .
                 '<b>' . gettext('------- End of Forwarded Message -------') . "</b><br>\n";
      }

      my $endofline = $msgformat eq 'text' ? "\n" : "<br>";
      $body .= $endofline . $endofline;
      if ($prefs{signature} =~ m/[^\s]/) {
         my $signature = str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat);
         if ($prefs{sigbeforeforward}) {
            $body = $endofline . $endofline . $signature . $endofline . $body . $endofline;
         } else {
            $body = $body . $signature . $endofline;
         }
      }

      $cc = (iconv($prefs{charset}, $composecharset, $prefs{autocc}))[0] if defined $prefs{autocc};
      $replyto = (iconv($prefs{charset}, $composecharset, $prefs{replyto}))[0] if defined $prefs{replyto};
      $inreplyto = $message->{'message-id'};

      my $references = $message->{'message-id'};
      if ($message->{references} =~ m/\S/) {
         $references = "$message->{references} $message->{'message-id'}";
      } elsif ($message->{'in-reply-to'} =~ m/\S/) {
         $references = $message->{'in-reply-to'};
         $references =~ s/^.*?(\<\S+\>).*$/$1/;
         $references = "$references $message->{'message-id'}";
      }

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   } elsif ($composetype eq 'forwardasorig') {
      # ****************************************************************
      # user is forwarding the message as if they originally composed it
      # the reply-to will be set to the original sender (like a bounce)
      # ****************************************************************
      # get the original message with attachments (all mode)
      my $message = getmessage($user, $folder, $messageid, 'all');

      my $bodyformat = '';
      ($body, $bodyformat) = decode_message_body($msgformat, $message);

      store_attachments($attachments_uid, $composecharset, $convfrom, $message);
      ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

      if ($bodyformat eq 'html') {
         $body = ow::htmlrender::html4nobase($body);
         $body = ow::htmlrender::html4attfiles($body, $r_attfiles, "$config{ow_cgiurl}/openwebmail-viewatt.pl", "action=viewattfile&sessionid=$thissession");
         $body = ow::htmlrender::html2block($body);
      }

      if ($msgformat eq 'auto') {
         $msgformat = $bodyformat;
         $msgformat = 'both' if $msgformat eq 'html';

         $showhtmlastext = $prefs{showhtmlastext} if $showhtmlastext eq '';
         $msgformat = 'text' if $showhtmlastext;
      }

      if ($bodyformat eq 'text' && $msgformat ne 'text')  {
         $body = ow::htmltext::text2html($body);
      } elsif ($bodyformat ne 'text' && $msgformat eq 'text')  {
         $body = ow::htmltext::html2text($body);
      }

      # auto set the from to match the userfrom the message was sent to
      my $fromemail = (grep { $message->{to} =~ m/$_/i || $message->{cc} =~ m/$_/i } keys %{$userfroms})[0] || $prefs{email};

      if (exists $userfroms->{$fromemail} && $userfroms->{$fromemail} ne '') {
         $from = qq|"$userfroms->{$fromemail}" <$fromemail>|;
      } else {
         $from = $fromemail;
      }

      $subject    = (iconv('utf-8', $composecharset, ($message->{subject} || '')))[0];
      $replyto    = (iconv('utf-8', $composecharset, $message->{from}))[0];
      $references = $message->{references};
      $priority   = $message->{priority} if defined $message->{priority} && $message->{priority} =~ m/(?:urgent|normal|non-urgent)/i;
      $cc         = (iconv($prefs{charset}, $composecharset, $prefs{autocc}))[0] if defined $prefs{autocc};
      $body       = (iconv($convfrom, $composecharset, $body))[0];

      # remove odds space or blank lines from body
      if ($msgformat eq 'text') {
         $body =~ s/( *\r?\n){2,}/\n\n/g;
         $body =~ s/^\s+//;
         $body =~ s/\s+$//;
      } else {
         $body =~ s/<br>(\s*<br>)+/<br><br>/gis;
      }

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   } elsif ($composetype eq 'forwardasatt') {
      # *****************************************************************************
      # user is forwarding a message or messages as encapsulated rfc822 attachment(s)
      # *****************************************************************************
      $msgformat = 'text' if $msgformat eq 'auto';

      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile) . " ($!)");

      if (update_folderindex($folderfile, $folderdb) < 0) {
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
         openwebmailerror(gettext('Cannot update db:') . ' ' . f2u($folderdb));
      }

      # build the list of message ids that are being forwarded
      my @forwarded_messageids = ();
      if (defined $messageid && $messageid) {
         # user is forwarding a single message from openwebmail-read
         push(@forwarded_messageids, $messageid);
      } elsif (defined $forward_batchid && $forward_batchid) {
         # user is forwarding multiple messages using openwebmail-main copy/move buttons
         sysopen(FORWARDIDS, "$config{ow_sessionsdir}/$thissession-forwardids-$forward_batchid", O_RDONLY)
              or openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$thissession-forwardids-$forward_batchid ($!)");

         while(defined(my $forward_messageid = <FORWARDIDS>)) {
            chomp($forward_messageid);
            push(@forwarded_messageids, $forward_messageid);
         }

         close(FORWARDIDS)
            or openwebmailerror(gettext('Cannot close file:') . " $config{ow_sessionsdir}/$thissession-forwardids-$forward_batchid ($!)");
      }

      my $forward_subject = gettext('(no subject)');

      # make an attachment file for each message
      foreach my $forward_messageid (@forwarded_messageids) {
         my @attr = get_message_attributes($forward_messageid, $folderdb);
         openwebmailerror(f2u($folderdb) . gettext('Message ID does not exist:') . " $forward_messageid") if $#attr < 0;

         $forward_subject = $attr[$_SUBJECT] || gettext('(no subject)');

         # auto set the from to match the userfrom the message was sent to
         my $fromemail = (grep { $attr[$_TO] =~ m/$_/i } keys %{$userfroms})[0] || $prefs{email};

         if (exists $userfroms->{$fromemail} && $userfroms->{$fromemail} ne '') {
            $from = qq|"$userfroms->{$fromemail}" <$fromemail>|;
         } else {
            $from = $fromemail;
         }

         my $attachment_serial = join('', map { int(rand(10)) }(1..9));

         my $attachment_tempfile = ow::tool::untaint("$config{ow_sessionsdir}/$thissession-$attachments_uid-att$attachment_serial");

         sysopen(ATTFILE, $attachment_tempfile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(gettext('Cannot open file:') . " $attachment_tempfile ($!)");

         my $content_filename = $attr[$_SUBJECT] || gettext('forward');
         $content_filename = length $content_filename > 64 ? mbsubstr($content_filename, 0, 64, $attr[$_CHARSET]) : $content_filename;

         print ATTFILE qq|Content-Type: message/rfc822;\n|,
                       qq|Content-Transfer-Encoding: 8bit\n|,
                       qq|Content-Disposition: attachment; filename="| . ow::mime::encode_mimewords($content_filename, ('Charset'=>$composecharset)) . qq|.msg"\n|,
                       qq|Content-Description: | . ow::mime::encode_mimewords($content_filename, ('Charset'=>$composecharset)) . qq|\n\n|;

         # copy message to be forwarded from the FOLDER to the ATTFILE
         sysopen(FOLDER, $folderfile, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $folderfile ($!)");
         seek(FOLDER, $attr[$_OFFSET], 0);

         my $attachment_dataremaining = $attr[$_SIZE];

         # do not copy 1st line if it is the 'From ' delimiter
         $_ = <FOLDER>;
         print ATTFILE $_ if !m/^From /;
         $attachment_dataremaining -= length($_);

         # copy other lines with the 'From ' delimiter escaped
         while ($attachment_dataremaining > 0) {
            $_ = <FOLDER>;
            s/^From />From /;
            print ATTFILE $_;
            $attachment_dataremaining -= length($_);
         }
         close(FOLDER) or
            openwebmailerror(gettext('Cannot close file:') . " $folderfile ($!)");

         close(ATTFILE) or
            openwebmailerror(gettext('Cannot close file:') . " $attachment_tempfile ($!)");

         ow::filelock::lock($folderfile, LOCK_UN);
      }

      ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

      my $forwardprefix = gettext('Fw:');
      $subject = $forward_subject;
      $subject = "$forwardprefix $subject" unless $subject =~ m#^\Q$forwardprefix\E#i;
      $subject = (iconv('utf-8', $composecharset, $subject))[0];

      $cc      = (iconv($prefs{charset}, $composecharset, $prefs{autocc}))[0] if defined $prefs{autocc};
      $replyto = (iconv($prefs{charset}, $composecharset, $prefs{replyto}))[0] if defined $prefs{replyto};

      my $endofline = $msgformat eq 'text' ? "\n" : "<br>";
      $body = $endofline . gettext('# Message forwarded as attachment') . "$endofline$endofline";
      $body .= str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat) . $endofline if $prefs{signature} =~ m/[^\s]/;

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   } elsif ($composetype eq 'editdraft') {
      # ************************************************
      # user is editing a previously saved draft message
      # ************************************************
      # get the original message with attachments (all mode)
      my $message = getmessage($user, $folder, $messageid, 'all');

      my $bodyformat = '';
      ($body, $bodyformat) = decode_message_body($msgformat, $message);

      store_attachments($attachments_uid, $composecharset, $convfrom, $message);
      ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

      if ($bodyformat eq 'html') {
         $body = ow::htmlrender::html4nobase($body);
         $body = ow::htmlrender::html4attfiles($body, $r_attfiles, "$config{ow_cgiurl}/openwebmail-viewatt.pl", "action=viewattfile&sessionid=$thissession");
         $body = ow::htmlrender::html2block($body);
      }

      if ($msgformat eq 'auto') {
         $msgformat = $bodyformat;
         $msgformat = 'both' if $msgformat eq 'html';

         $showhtmlastext = $prefs{showhtmlastext} if $showhtmlastext eq '';
         $msgformat = 'text' if $showhtmlastext;
      }

      if ($bodyformat eq 'text' && $msgformat ne 'text')  {
         $body = ow::htmltext::text2html($body);
      } elsif ($bodyformat ne 'text' && $msgformat eq 'text')  {
         $body = ow::htmltext::html2text($body);
      }

      # auto set the from to match the userfrom the message was sent to
      my $fromemail = (grep { $message->{from} =~ m/$_/i } keys %{$userfroms})[0] || $prefs{email};

      if (exists $userfroms->{$fromemail} && $userfroms->{$fromemail} ne '') {
         $from = qq|"$userfroms->{$fromemail}" <$fromemail>|;
      } else {
         $from = $fromemail;
      }

      $subject = $message->{subject} || gettext('(no subject)');
      $to      = $message->{to} if defined $message->{to};
      $cc      = $message->{cc} if defined $message->{cc};
      $bcc     = $message->{bcc} if defined $message->{bcc};
      $replyto = $message->{'reply-to'} if defined $message->{'reply-to'};
      ($subject, $to, $cc, $bcc, $replyto) = iconv('utf-8', $composecharset, $subject, $to, $cc, $bcc, $replyto);
      $body    = (iconv($convfrom, $composecharset, $body))[0];

      $inreplyto  = $message->{'in-reply-to'};
      $references = $message->{references};
      $priority   = $message->{priority} if defined $message->{priority} && $message->{priority} =~ m/(?:urgent|normal|non-urgent)/i;
      $replyto    = (iconv($prefs{charset}, $composecharset, $prefs{replyto}))[0] if $replyto eq '' && defined $prefs{replyto};

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   } elsif ($composetype eq 'sendto') {
      # *********************************************************
      # user is composing a new mail with a recipient already set
      # *********************************************************
      $msgformat = 'text' if $msgformat eq 'auto';

      if (defined $prefs{autocc} && $prefs{autocc} ne '') {
         $cc .= ', ' if $cc ne '';
         $cc .= (iconv($prefs{charset}, $composecharset, $prefs{autocc}))[0];
      }

      $replyto = (iconv($prefs{charset}, $composecharset, $prefs{replyto}))[0] if defined $prefs{replyto};

      if ($prefs{signature} =~ m#[^\s]#) {
         $body .= $msgformat eq 'text'
                  ? "\n\n"     . str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat) . "\n"
                  : "<br><br>" . str2str((iconv($prefs{charset}, $composecharset, $prefs{signature}))[0], $msgformat) . "<br>";
      }

      # remove tail blank line and space
      $body =~ s#\s+$#\n#s;

      if ($msgformat eq 'text') {
         # text area would eat leading \n, so we add it back here
         $body = "\n$body";
      } else {
         # insert \n for long lines to keep them short so that the width of
         # an html message composer can always fit within screen resolution
         $body =~ s#([^\n\r]{1,80})( |&nbsp;)#$1$2\n#ig;

         $body .= "\n";
      }
   }

   # prepare the dynamic template vars below this point

   # TODO: the logic here could probably improve to handle more scenarios - this is the legacy logic
   if ($composecharset ne $prefs{charset}) {
      my $composelocale = $prefs{language} . "." . ow::lang::charset_for_locale($composecharset);
      if (exists $config{available_locales}->{$composelocale}) {
         # switch to this character set in the users preferred language if it exists
         $prefs{locale} = $composelocale;
         $prefs{charset} = $composecharset;
      } else {
         # or else switch to en_US.UTF-8 and hope for the best
         $prefs{locale} = 'en_US.UTF-8';
         $prefs{charset} = $composecharset;
      }
   }

   $po = loadlang($prefs{locale});
   charset($prefs{charset}) if $CGI::VERSION >= 2.58; # setup charset of CGI module

   # charset conversion menu (convto)
   my %allsets      = ();
   my @convtolist   = ('none');
   my %convtolabels = ('none' => "$composecharset *");

   $allsets{$_} = 1 for keys %charset_convlist, map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets;

   delete $allsets{$composecharset};

   if (exists $charset_convlist{$composecharset} && defined $charset_convlist{$composecharset}) {
      foreach my $convtocharset (sort @{$charset_convlist{$composecharset}}) {
         if (is_convertible($composecharset, $convtocharset)) {
            push(@convtolist, $convtocharset);
            $convtolabels{$convtocharset} = "$composecharset > $convtocharset";

            delete $allsets{$convtocharset};
         }
      }
   }

   push(@convtolist, sort keys %allsets);

   # a list of image attachments selectable by whichever wysiwyg textarea script is used
   my $selectableimagesloop = [
                                 map { {
                                         converted_name   => (iconv($_->{namecharset}, $composecharset, $_->{name}))[0],
                                         attachment_name  => $_->{name},
                                         attachment_file  => $_->{file},
                                         sessionid        => $thissession,
                                         url_cgi          => $config{ow_cgiurl},
                                     } }
                                 grep { $_->{name} =~ m/(?:jpe?g|gif|png)$/ } @{$r_attfiles}
                              ];
   $selectableimagesloop->[$#{$selectableimagesloop}]{last} = 1 if scalar @{$selectableimagesloop} > 0;

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('send_compose.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template         => get_header($config{header_template_file}),

                      # standard params
                      sessionid               => $thissession,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,
                      url_cgi                 => $config{ow_cgiurl},
                      url_html                => $config{ow_htmlurl},
                      use_texticon            => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont           => $prefs{usefixedfont},
                      charset                 => $prefs{charset},
                      iconset                 => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder             => $abookfolder,
                      abookpage               => $abookpage,
                      abooksort               => $abooksort,
                      abookkeyword            => $abookkeyword,
                      abooksearchtype         => $abooksearchtype,
                      abookcollapse           => $abookcollapse,

                      # send_compose.tmpl
                      compose_caller          => $compose_caller,
                      is_caller_readmessage   => $compose_caller eq 'readmessage'  ? 1 : 0,
                      is_caller_addrlistview  => $compose_caller eq 'addrlistview' ? 1 : 0,
                      is_caller_listmessages  => $compose_caller eq 'listmessages' ? 1 : 0,
                      to                      => $to,
                      cc                      => $cc,
                      bcc                     => $bcc,
                      replyto                 => $replyto,
                      subject                 => $subject,
                      body                    => $body,
                      composecharset          => $composecharset,
                      mymessageid             => $mymessageid,
                      inreplyto               => $inreplyto,
                      references              => $references,
                      msgformat               => $msgformat,
                      is_msgformathtml        => $msgformat eq 'html' || $msgformat eq 'both' ? 1 : 0,
                      is_msgformattext        => $msgformat eq 'text' ? 1 : 0,
                      show_phonekbd           => $show_phonekbd,
                      show_phonekbd_button    => $composecharset eq 'big5' && $show_phonekbd == 0 ? 1 : 0,
                      messageid               => $messageid,
                      headers                 => $prefs{headers},
                      fromselectloop          => [
                                                   map {
                                                         my $option = $_->{name}
                                                                      ? (iconv($prefs{charset}, $composecharset, qq|"$_->{name}" <$_->{address}>|))[0]
                                                                      : $_->{address};

                                                         {
                                                           option   => $option,
                                                           label    => $option,
                                                           selected => $from eq $option ? 1 : 0,
                                                         }
                                                       }
                                                  sort {
                                                          $a->{name} cmp $b->{name}
                                                          || $a->{realuser} cmp $b->{realuser}
                                                          || $a->{domain} cmp $b->{domain}
                                                       }
                                                   map {
                                                          my ($name,$address)    = (($userfroms->{$_} || ''), $_);
                                                          my ($realuser,$domain) = $address =~ m/^([^@]+)@([^@]+)$/;
                                                          $realuser = $address unless defined $realuser && $realuser;
                                                          $domain   = '' unless defined $domain && $domain;
                                                          { name => $name, address => $address, realuser => $realuser, domain => $domain }
                                                       } keys %{$userfroms}
                                                 ],
                      priorityselectloop      => [
                                                   map { {
                                                           "option_$_" => 1,
                                                           selected    => $priority eq $_ ? 1 : 0,
                                                       } } qw(urgent normal non-urgent)
                                                 ],
                      convtoselectloop        => [
                                                   map { {
                                                           option   => $_,
                                                           label    => exists $convtolabels{$_} ? $convtolabels{$_} : $_,
                                                           selected => $convto eq $_ ? 1 : 0,
                                                       } } @convtolist
                                                 ],
                      enable_addressbook      => $config{enable_addressbook},
                      confirmreading          => $confirmreading,
                      attachmentsloop         => [
                                                   map { {
                                                           attachment_namecharset => $_->{namecharset},
                                                           converted_name         => (iconv($_->{namecharset}, $composecharset, $_->{name}))[0],
                                                           attachment_name        => $_->{name},
                                                           attachment_file        => $_->{file},
                                                           is_referenced          => $_->{referencecount} || 0,
                                                           attachment_size        => lenstr($_->{size}, 1),
                                                           show_wordpreview       => $_->{name} =~ m/\.(?:doc|dot)$/i ? 1 : 0,
                                                           save_to_webdisk        => $config{enable_webdisk} && !$config{webdisk_readonly} ? 1 : 0,
                                                           sessionid              => $thissession,
                                                           url_cgi                => $config{ow_cgiurl},
                                                       } } @{$r_attfiles}
                                                 ],
                      attfiles_totalsize_kb   => int($attfiles_totalsize/1024),
                      attachments_limit       => $config{attlimit},
                      attspaceavailable_kb    => $config{attlimit} - int($attfiles_totalsize/1024),
                      enable_webdisk          => $config{enable_webdisk},
                      enable_urlattach        => $config{enable_urlattach} && ow::tool::findbin('wget') ? 1 : 0,
                      enable_backupsent       => $config{enable_backupsent},
                      backupsent              => $backupsent ? 1 : 0,
                      editrows                => $prefs{editrows} || 20,
                      htmledit_height         => (($prefs{editrows} || 20) + 10) * 12,
                      editcolumns             => $prefs{editcolumns} || 78,
                      enable_savedraft        => $config{enable_savedraft},
                      enable_spellcheck       => $config{enable_spellcheck},
                      spellcheck_program      => (map { s#^.*/##; $_ } split(/\s/, $config{spellcheck}))[0],
                      dictionaryselectloop    => [
                                                   map { {
                                                           option   => $_,
                                                           label    => $_,
                                                           selected => $_ eq $prefs{dictionary} ? 1 : 0,
                                                       } } @{$config{spellcheck_dictionaries}}
                                                 ],
                      spellcheck_dictionary   => $prefs{dictionary},
                      enable_htmlcompose      => $enable_htmlcompose,
                      htmlcursorstartbottom   => $prefs{replywithorigmsg} eq 'at_beginning' ? 1 : 0,
                      is_reply                => $composetype =~ m/(?:reply|continue)/ ? 1 : 0,
                      newmsgformatselectloop  => [
                                                   map { {
                                                           "option_$_" => 1,
                                                           selected    => $_ eq $msgformat ? 1 : 0,
                                                       } } $enable_htmlcompose ? qw(text html both) : qw(text)
                                                 ],
                      sendbuttons_before      => $prefs{sendbuttonposition} =~ m#^(?:before|both)$# ? 1 : 0,
                      sendbuttons_after       => $prefs{sendbuttonposition} =~ m#^(?:after|both)$# ? 1 : 0,
                      selectableimagesloop    => $selectableimagesloop,
                      language                => (split(/_/,$prefs{language}))[0] || 'en',
                      languagedirection       => $composecharset eq $prefs{charset}
                                                 && defined $ow::lang::RTL{$prefs{locale}}
                                                 && $ow::lang::RTL{$prefs{locale}} ? 'rtl' : 'ltr',
                      popup_draftsaved        => $savedraftbutton && $session_noupdate == 0 ? 1 : 0,
                      savedraftbeforetimeout  => $savedraftbutton && $session_noupdate == 1 ? 0 : 1,
                      popup_attlimitreached   => defined param('attlimitreached') ? 1 : 0,
                      selectpopupwidth        => $prefs{abook_width}  eq 'max' ? 0 : $prefs{abook_width},
                      selectpopupheight       => $prefs{abook_height} eq 'max' ? 0 : $prefs{abook_height},
                      abook_defaultkeyword    => $prefs{abook_defaultfilter} ? $prefs{abook_defaultkeyword} : '',
                      abook_defaultsearchtype => $prefs{abook_defaultfilter} ? $prefs{abook_defaultsearchtype} : '',

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub generate_messageid {
   # create a valid and unique messageid, presumably for a new message
   # example: 20091122050846.M22324@example.com
   my $suffix = shift;
   my $fakeid = ow::datetime::gmtime2dateserial() . '.M' . int(rand() * 100000);
   return ($suffix =~ m/@(.*)$/ ? "<$fakeid\@$1>" : "<$fakeid\@$suffix>");
}

sub decode_message_body {
   # given a message, decode the body of the message
   # and determine if the body is text or html
   my ($msgformat, $message) = @_;

   my $bodyformat = 'text';

   my $body = '';

   if ($message->{'content-type'} =~ m#^multipart#i) {
      if (defined $message->{attachment}[0] && $message->{attachment}[0]{'content-type'} =~ m#^text#i) {
         # If the first attachment is text, assume it's the body of a message in multipart format
         $body = ow::mime::decode_content(${$message->{attachment}[0]{r_content}}, $message->{attachment}[0]{'content-transfer-encoding'});
         $body = ow::enriched::enriched2html($body) if $message->{attachment}[0]{'content-type'} =~ m#^text/enriched#i;
         $bodyformat = 'html' if $message->{attachment}[0]{'content-type'} =~ m#^text/(?:html|enriched)#i;

         # handle mail with both text and html versions
         # rename html to other name so if the user is in text compose mode,
         # the modified/forwarded text won't be overridden by html again
         if (
               defined $message->{attachment}[1]
               &&
               (
                 $message->{attachment}[1]{boundary} eq $message->{attachment}[0]{boundary}
                 ||
                 (
                   # support apple mail encapsulation of html part in multipart/relative sub-part
                   # which makes the boundarys not match exactly
                   $message->{attachment}[0]{boundary} =~ m#^--Apple-Mail#
                   && $message->{attachment}[1]{boundary} =~ m#^--Apple-Mail#
                 )
               )
            ) {
            # rename html attachment in the same alternative group
            if (
                 (
                   $message->{attachment}[0]{subtype}           =~ m#alternative#i
                   && $message->{attachment}[1]{subtype}        =~ m#alternative#i
                   && $message->{attachment}[1]{'content-type'} =~ m#^text#i
                   && $message->{attachment}[1]{filename}       =~ m#^Unknown\.#
                 )
                 ||
                 ( # rename next if this=unknown.txt and next=unknown.html
                   $message->{attachment}[0]{'content-type'}    =~ m#^text/(?:plain|enriched)#i
                   && $message->{attachment}[0]{filename}       =~ m#^Unknown\.#
                   && $message->{attachment}[1]{'content-type'} =~ m#^text/(?:html|enriched)#i
                   && $message->{attachment}[1]{filename}       =~ m#^Unknown\.#
                 )
               ) {
               if ($msgformat ne 'text' && $bodyformat eq 'text') {
                  $body = ow::mime::decode_content(${$message->{attachment}[1]{r_content}}, $message->{attachment}[1]{'content-transfer-encoding'});
                  $body = ow::enriched::enriched2html($body) if $message->{attachment}[1]{'content-type'} =~ m#^text/enriched#i;

                  $bodyformat = 'html';
                  shift @{$message->{attachment}}; # remove 1 attachment from the message's attachment list for html
               } else {
                  $message->{attachment}[1]{filename} =~ s#^Unknown#gettext('Original')#e;
                  $message->{attachment}[1]{header}   =~ s#^Content-Type: \s*text/(html|enriched);#qq|Content-Type: text/$1;\n   name="| . gettext('OriginalMsg') . '.htm';#ei;
               }
            }
         }
         # remove 1 attachment from the message's attachment list for text
         shift @{$message->{attachment}};
      } else {
         $body = '';
      }
   } else {
      $body = $message->{body} || '';

      # handle mail programs that send the body encoded
      if ($message->{'content-type'} =~ m#^text#i) {
         $body = ow::mime::decode_content($body, $message->{'content-transfer-encoding'});
      }

      $body = ow::enriched::enriched2html($body) if $message->{'content-type'} =~ m#^text/enriched#i;
      $bodyformat = 'html' if $message->{'content-type'} =~ m#^text/(?:html|enriched)#i;
   }

   return ($body, $bodyformat);
}

sub add_attachment {
   # user is trying to add an attachment -- we need to establish three things:
   #  - the attachment filename (with no path)
   #  - the attachment contenttype (like text/plain)
   #  - a filehandle to the uploaded or http retrieved attachment, so we can read it
   #    and base64 encode it into a temp file that will be attached to our final message
   #    openwebmail never quoted-printable encodes attachments even if they are text
   my $attachments_uid = shift || return 0;

   my $composecharset   = param('composecharset') || $prefs{charset};
   my $convfrom         = param('convfrom') || '';
   my $addbutton        = param('addbutton') || '';        # add attachment button clicked
   my $webdiskselection = param('webdiskselection') || ''; # attachment file selected from webdisk
   my $urlselection     = param('urlselection') || '';     # attachment is a url we need to retrieve
   my $attachment       = param('attachment') || '';       # uploaded attachment filename

   $composecharset = $prefs{charset} unless ow::lang::is_charset_supported($composecharset) || exists $charset_convlist{$composecharset};

   if ($convfrom =~ m/^none\.(.*)$/) {
      # convfrom is a charset manually chosen by the user during last message reading
      $composecharset = $1 if ow::lang::is_charset_supported($1);
   }

   # get the totalsize of current attachments before proceeding
   my $attfiles_totalsize = get_attachments($attachments_uid);

   my $attachment_filename    = '';
   my $attachment_contenttype = '';

   if ($config{enable_urlattach} && $urlselection =~ m#^(https?|ftp)://#) {
      # ATTACHMENT IS A URL.
      # Retrieve the file to attach using wget
      # Get filename and content-type
      # TODO: We should replace this with a perl module that does
      # the same thing, such as LWP::Simple or LWP::UserAgent
      my $wgetbin = ow::tool::findbin('wget');

      if ($wgetbin) {
         $attachment_filename = ow::tool::unescapeURL($urlselection); # unescape url

         my $returncode    = -1;
         my $error_message = '';
         ($returncode, $error_message, $attachment_contenttype, $attachment)
           = ow::wget::get_handle($wgetbin, $attachment_filename);

         if ($returncode == 0) {
            my $ext = ow::tool::contenttype2ext($attachment_contenttype);
            $attachment_filename =~ s#\?.*$##; # remove cgi query parameters in url
            $attachment_filename =~ s#/$##;    # remove trailing url slashes
            $attachment_filename =~ s#^.*/##;  # remove url path to isolate filename
            $attachment_filename .= ".$ext" if $attachment_filename !~ m/\.$ext$/ && $ext ne 'bin';
         } else {
            undef $attachment; # silent if wget err
         }
      } else {
         undef $attachment; # silent if no wget available
      }
   } elsif ($webdiskselection && $config{enable_webdisk}) {
      # ATTACHMENT IS A WEBDISK FILE
      # the webdiskselection value copied from webdisk is in fscharset and protected with escapeURL,
      # since the webdisk selection may not be in the same character set as the composing message.
      # Please see filldestname in openwebmail-webdisk.pl and templates/dirfilesel.template
      $webdiskselection = ow::tool::unescapeURL($webdiskselection);
      my $webdiskrootdir = ow::tool::untaint($homedir . absolute_vpath('/', $config{webdisk_rootpath}));
      my $vpath = absolute_vpath('/', $webdiskselection);
      my $vpathstr = (iconv($prefs{fscharset}, $composecharset, $vpath))[0];

      verify_vpath($webdiskrootdir, $vpath);

      openwebmailerror(gettext('File does not exist:') . " $vpathstr") unless -f "$webdiskrootdir/$vpath";

      # open a filehandle to the attachment file for later use during base64 encoding
      $attachment = do { no warnings 'once'; local *FH };

      sysopen($attachment, "$webdiskrootdir/$vpath", O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");

      $attachment_filename = $vpath;
      $attachment_filename =~ s#/$##;
      $attachment_filename =~ s#^.*/##;
      $attachment_filename = (iconv($prefs{fscharset}, $composecharset, $attachment_filename))[0]; # conv to composecharset
      $attachment_contenttype = ow::tool::ext2contenttype($vpath);
   } else {
      # ATTACHMENT IS AN UPLOADED FILE.
      # $attachment is a string from CGI.pm
      $attachment_filename = $attachment;

      # Convert :: back to ' like it should be.
      $attachment_filename =~ s/::/'/g;

      # Trim the DOS path info from the filename
      if ($composecharset eq 'big5' || $composecharset eq 'gb2312') {
         $attachment_filename = ow::tool::zh_dospath2fname($attachment_filename);
      } else {
         $attachment_filename =~ s#^.*\\##;
      }
      $attachment_filename =~ s#^.*/##; # trim unix path
      $attachment_filename =~ s#^.*:##; # trim mac path and dos drive

      if (defined CGI::uploadInfo($attachment)) {
         # CGI::uploadInfo($attachment) returns a hash ref of the browser info about the attachment
         $attachment_contenttype = CGI::uploadInfo($attachment)->{'Content-Type'} || 'application/octet-stream';
      } else {
         $attachment_contenttype = 'application/octet-stream';
      }

      $attachment = CGI::upload('attachment'); # get the CGI.pm filehandle in a strict safe way
   }

   # make sure we actually have an attachment
   return unless defined $attachment && $attachment;

   # read the attachment filehandle and base64 encode the attachment to disk
   # in our session directory for retrieval during message sending operations
   if ($config{attlimit} && (($attfiles_totalsize + (-s $attachment)) > ($config{attlimit} * 1024))) {
      close($attachment) or writelog("cannot close file $attachment");
      param(-name => 'attlimitreached', -value => 1);
   } else {
      # store the attachment base64 encoded on disk until we're ready to send this message
      my $attachment_serial = time();

      my $attachment_base64tempfile = ow::tool::untaint("$config{ow_sessionsdir}/$thissession-$attachments_uid-att$attachment_serial");

      sysopen(ATTFILE, $attachment_base64tempfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $attachment_base64tempfile ($!)");

      print ATTFILE qq|Content-Type: $attachment_contenttype;\n| .
                    qq|\tname="| .
                    ow::mime::encode_mimewords($attachment_filename, ('Charset' => $composecharset)) .
                    qq|"\n| .
                    qq|Content-Id: <att$attachment_serial>\n| .
                    qq|Content-Disposition: attachment; filename="| .
                    ow::mime::encode_mimewords($attachment_filename, ('Charset' => $composecharset)) .
                    qq|"\n| .
                    qq|Content-Transfer-Encoding: base64\n\n|;

      # encode it in chunks that are a multiple of 57 bytes because
      # 57 bytes of data fills one complete base64 line (76 == 57*4/3)
      # see MIME::Base64 module notes for more info
      my $readbuffer      = '';
      my $attachment_size = 0;
      while (read($attachment, $readbuffer, 400*57)) {
         $readbuffer = ow::mime::encode_base64($readbuffer);
         $attachment_size += length($readbuffer);
         print ATTFILE $readbuffer;
      }

      close(ATTFILE) or
         openwebmailerror(gettext('Cannot close file:') . " $attachment_base64tempfile ($!)");

      close($attachment) or writelog("cannot close file $attachment");
   }

   return ($attachment_filename, $attachment_contenttype);
}

sub delete_attachments {
   # delete all of the attachments containing the provided unique id
   my $attachments_uid = shift || return 0;

   opendir(SESSIONSDIR, $config{ow_sessionsdir}) or
     openwebmailerror(gettext('Cannot open directory:') . " $config{ow_sessionsdir} ($!)");

   my @sessionfiles = readdir(SESSIONSDIR);

   closedir(SESSIONSDIR) or
     openwebmailerror(gettext('Cannot close directory:') . " $config{ow_sessionsdir} ($!)");

   my @deletequeue  = ();

   foreach my $file (@sessionfiles) {
      if ($file =~ m/^(\Q$thissession-$attachments_uid-\Eatt\d+)$/) {
         push(@deletequeue, ow::tool::untaint("$config{ow_sessionsdir}/$file"))
      }
   }

   # return the number of deleted files
   unlink(@deletequeue) if scalar @deletequeue > 0;
}

sub store_attachments {
   # extract and store in the sessions directory all attachments for a given message
   # attachments are stored as attachment session files with header and content
   my $attachments_uid = shift || return 0;
   my ($composecharset, $convfrom, $message) = @_;

   if (exists $message->{attachment}[0]{header} && defined $message->{attachment}[0]{header}) {
      my $attachment_serial = time();
      $attachment_serial = ow::tool::untaint($attachment_serial);

      for (my $i = 0; $i <= $#{$message->{attachment}}; $i++) {
         $attachment_serial++;
         my $attachment_tempfile = ow::tool::untaint("$config{ow_sessionsdir}/$thissession-$attachments_uid-att$attachment_serial");

         if ($message->{attachment}[$i]{header} ne '' && defined $message->{attachment}[$i]{r_content}) {
            if ($message->{attachment}[$i]{'content-type'} =~ m#^application/ms-tnef#i) {
               my ($tnef_attachment_header, $tnef_r_content) = tnefatt2archive($message->{attachment}[$i], $convfrom, $composecharset);

               if ($tnef_attachment_header ne '') {
                  ($message->{attachment}[$i]{header}, $message->{attachment}[$i]{r_content}) = ($tnef_attachment_header, $tnef_r_content)
               }
            }

            sysopen(ATTFILE, $attachment_tempfile, O_WRONLY|O_TRUNC|O_CREAT) or
              openwebmailerror(gettext('Cannot open file:') . " $attachment_tempfile ($!)");

            print ATTFILE $message->{attachment}[$i]{header}, "\n", ${$message->{attachment}[$i]{r_content}};

            close ATTFILE or
              openwebmailerror(gettext('Cannot close file:') . " $attachment_tempfile ($!)");
         }
      }
   }
}

sub get_attachments {
   # return an array ref of all of the attachments containing the provided unique id
   # each attachment is already base64 encoded since they are written to the session
   # directory that way
   my $attachments_uid = shift || return 0;

   my @attachmentfiles = ();
   my $totalsize       = 0;

   opendir(SESSIONSDIR, $config{ow_sessionsdir}) or
     openwebmailerror(gettext('Cannot open directory:') . " $config{ow_sessionsdir} ($!)");

   my @sessionfiles = readdir(SESSIONSDIR);

   closedir(SESSIONSDIR) or
     openwebmailerror(gettext('Cannot close directory:') . " $config{ow_sessionsdir} ($!)");

   foreach my $file (sort @sessionfiles) {
      if ($file =~ m/^(\Q$thissession-$attachments_uid-\Eatt\d+)$/) {
         # parse this attachment to get its information
         my %att = ();

         if (wantarray) {
            my $attheader = '';

            push(@attachmentfiles, \%att);

            $att{file} = $1;

            local $/ = "\n\n"; # read whole file until blank line
            sysopen(ATTFILE, "$config{ow_sessionsdir}/$file", O_RDONLY) or
              openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$file ($!)");
            $attheader = <ATTFILE>;
            close(ATTFILE) or
              openwebmailerror(gettext('Cannot close file:') . " $config{ow_sessionsdir}/$file ($!)");

            $att{'content-type'} = 'application/octet-stream'; # assume attachment is binary at first
            ow::mailparse::parse_header(\$attheader, \%att);   # parse the attheader to get the actual headers

            $att{'content-id'} =~ s/^\s*<(.+)>\s*$/$1/ if exists $att{'content-id'} && defined $att{'content-id'}; # strip enclosing space or <>'s
            $att{'content-id'} = '' if !defined $att{'content-id'};

            ($att{name}, $att{namecharset}) = ow::mailparse::get_filename_charset($att{'content-type'}, $att{'content-disposition'});
            $att{name} =~ s/Unknown/attachment_$#attachmentfiles/;
         }

         $att{size} = (-s "$config{ow_sessionsdir}/$file");

         $totalsize += $att{size};
      }
   }

   return wantarray ? ($totalsize, \@attachmentfiles) : $totalsize;
}

sub str2str {
   # convert the provided string into our target format and return it
   my ($str, $format) = @_;

   my $is_html = $str =~ m#<(?:br|p|a|font|table|div)[^>]*>#is ? 1 : 0;

   return $format eq 'text'
          ? ($is_html ? ow::htmltext::html2text($str) : $str)
          : ($is_html ? $str : ow::htmltext::text2html($str));
}

sub reparagraph {
   my ($messagebody, $columnsize) = @_;

   my @lines = split(/\n/, $messagebody);

   my ($text,$left) = ('','');

   foreach my $line (@lines) {
      if ($left eq '' && length($line) < $columnsize) {
         $text .= "$line\n";
      } elsif (
                $line =~ m#^\s*$#              # newline
                || $line =~ m#^>#              # previous orig
                || $line =~ m/^#/              # comment line
                || $line =~ m/^\s*[\-=#]+\s*$/ # dash line
                || $line =~ m/^\s*[\-=#]{3,}/  # dash line
              ) {
         $text .= "$left\n" if $left ne '';
         $text .= "$line\n";
         $left = '';
      } else {
         if (
              $line =~ m#^\s*\(#
              || $line =~ m#^\s*\d\d?[\.:]#
              || $line =~ m#^\s*[A-Za-z][\.:]#
              || $line =~ m#\d\d:\d\d:\d\d#
              || $line =~ m#¡G#
            ) {
            $text .= "$left\n";
            $left = $line;
         } else {
            if ($left =~ m# $# || $line =~ m#^ # || $left eq '' || $line eq '') {
               $left .= $line;
            } else {
               $left .= " $line";
            }
         }

         while (length($left) > $columnsize) {
            my $furthersplit = 0;
            for (my $len = $columnsize - 2; $len > 2; $len -= 2) {
               if ($left =~ m#^(.{$len}.*?[\s\,\)\-])(.*)$#) {
                  if (length($1) < $columnsize) {
                     $text .= "$1\n";
                     $left = $2;
                     $furthersplit = 1;
                     last;
                  }
               } else {
                  $text .= "$left\n";
                  $left = "";
                  last;
               }
            }
            last if $furthersplit == 0;
         }
      }
   }
   $text .= "$left\n" if $left ne '';

   return($text);
}

sub tnefatt2archive {
   my ($r_attachment, $convfrom, $composecharset) = @_;

   my $tnefbin = ow::tool::findbin('tnef');
   return '' if $tnefbin eq '';

   my $content = ow::mime::decode_content(${$r_attachment->{r_content}}, $r_attachment->{'content-transfer-encoding'});

   my ($arcname, $r_arcdata, @arcfilelist) = ow::tnef::get_tnef_archive($tnefbin, $r_attachment->{filename}, \$content);
   return '' if $arcname eq '';

   my $arccontenttype = ow::tool::ext2contenttype($arcname);
   my $arcdescription = join(', ', @arcfilelist);

   # convfrom is the charset choosen by the user during message reading
   # we convert att attributes from convfrom to current composecharset
   if (is_convertible($convfrom, $composecharset)) {
      ($arcname, $arcdescription) = iconv($convfrom, $composecharset, $arcname, $arcdescription);
      $arcname = ow::mime::encode_mimewords($arcname, ('Charset'=>$composecharset));
      $arcdescription = ow::mime::encode_mimewords($arcdescription, ('Charset'=>$composecharset));
   } else {
      $arcname = ow::mime::encode_mimewords($arcname, ('Charset'=>${$r_attachment}{charset}));
      $arcdescription = ow::mime::encode_mimewords($arcdescription, ('Charset'=>${$r_attachment}{charset}));
   }

   my $attheader = qq|Content-Type: $arccontenttype;\n|.
                   qq|\tname="$arcname"\n|.
                   qq|Content-Disposition: attachment; filename="$arcname"\n|.
                   qq|Content-Transfer-Encoding: base64\n|;
   $attheader .= qq|Content-Description: $arcdescription\n| if scalar @arcfilelist > 0;

   $content = ow::mime::encode_base64(${$r_arcdata});

   return($attheader, \$content);
}

sub sendmessage {
   my $sendbutton       = param('sendbutton') || '';
   my $savedraftbutton  = param('savedraftbutton') || '';

   my $messageid        = param('message_id') || '';                         # messageid for the original message being replied/forwarded
   my $mymessageid      = param('mymessageid') ||'';                         # messageid for the message we are composing

   my $to               = param('to') || '';
   my $cc               = param('cc') || '';
   my $bcc              = param('bcc') || '';

   my $from             = param('from') || '';
   my $subject          = param('subject') || gettext('(no subject)');
   my $body             = param('body') || '';
   my $replyto          = param('replyto') || '';
   my $inreplyto        = param('inreplyto') || '';
   my $references       = param('references') || '';
   my $priority         = param('priority') || 'normal';                     # normal, urgent, or non-urgent
   my $confirmreading   = param('confirmreading') || 0;
   my $backupsent       = param('backupsent') || 0;

   my $msgformat        = param('msgformat') || $prefs{msgformat} || 'text'; # text, html, or both
   my $composecharset   = param('composecharset') || $prefs{charset};

   # establish the user from id unless there already is one
   my $userfroms = get_userfroms();
   my $realname = '';
   ($realname, $from) = $from ? ow::tool::_email2nameaddr($from) : ($userfroms->{$prefs{email}}, $prefs{email});
   $realname =~ s/['"]/ /g; # Get rid of shell escape attempts
   $from     =~ s/['"]/ /g; # Get rid of shell escape attempts

   # gmtime -> 20090727080915
   my $dateserial = ow::datetime::gmtime2dateserial();

   # 20090727080915 -> Mon, 27 Jul 2009 08:09:15 -0800 (PDT)
   my $date = ow::datetime::dateserial2datefield($dateserial, $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});

   # make sure we have a messageid for the message we're composing
   $mymessageid = generate_messageid((ow::tool::email2nameaddr($from))[1]) unless $mymessageid;

   # generate a unique id for all attachments belonging to this message, based on the messageid of this message
   my $attachments_uid = length $mymessageid > 22 ? substr($mymessageid,0,22) : $mymessageid;
   $attachments_uid =~ s#[<>@"'&;]##g;

   # add attachment if user forgot to press add
   my ($attachment_filename, $attachment_contenttype) = add_attachment($attachments_uid);
   return compose() if defined param('attlimitreached');

   # get all of the attachments for this message
   my ($attfiles_totalsize, $r_attfiles) = get_attachments($attachments_uid);

   $body =~ s/\r//g; # strip ^M characters from message.

   if ($msgformat ne 'text') {
      # replace links to attached files with their cid
      $body = ow::htmlrender::html4attfiles_link2cid($body, $r_attfiles, "$config{ow_cgiurl}/openwebmail-viewatt.pl");

      # replace url#anchor with #anchor (to remove url added by some wysiwyg html editors)
      $body =~ s#https?://$ENV{HTTP_HOST}$config{ow_cgiurl}/openwebmail-send.pl.*?action=compose.*?\##\##gs;
   }

   # convert message to prefs{sendcharset}
   if ($prefs{sendcharset} ne 'sameascomposing') {
      ($realname, $replyto, $to, $cc, $subject, $body) =
         iconv($composecharset, $prefs{sendcharset}, $realname, $replyto, $to, $cc, $subject, $body);
      $composecharset = $prefs{sendcharset};
   }

   # wrap non-text messages in complete html;
   if ($msgformat ne 'text') {
      $body = qq|<html>\n| .
              qq|<head>\n| .
              qq|<meta content="text/html; charset=$composecharset" http-equiv="Content-Type">\n| .
              qq|<meta content="$config{name} $config{version} $config{releasedate} rev $config{revision}" name="Generator">\n|.
              qq|</head>\n| .
              qq|<body>\n| .
              qq|$body\n| .
              qq|</body>\n| .
              qq|</html>\n|;
   }

   # by default, enable do_send
   my $do_send    = 1;
   my $senderrstr = '';
   my $senderr    = 0;

   # by default, enable do_save
   my $do_save    = 1;
   my $saveerrstr = '';
   my $saveerr    = 0;

   my ($savefolder, $savefile, $savedb) = ('','','');

   if ($savedraftbutton) {
      # save message to draft folder
      $savefolder = 'saved-drafts';
      $do_send = 0;

      if (!$config{enable_savedraft}) {
         $do_save = 0;
         $saveerrstr = gettext('The save draft feature is not enabled.');
         $saveerr++;
      }

      if ($do_save == 1 && $quotalimit > 0 && $quotausage >= $quotalimit) {
         $do_save = 0;
         $saveerrstr = gettext('Save draft aborted, the quota has been exceeded.');
         $saveerr++;
      }
   } else {
      # save message to sent folder and send
      $savefolder = $folder;
      $savefolder = 'sent-mail' if !$prefs{backupsentoncurrfolder} || $folder eq '' || $folder =~ m/^(?:INBOX|saved-drafts)$/;

      $do_save = 0 if !$config{enable_backupsent} || $backupsent == 0;

      if ($do_save == 1 && $quotalimit > 0 && $quotausage >= $quotalimit) {
         $do_save = 0;
         $saveerrstr = gettext('Message save aborted, the quota has been exceeded.');
         $saveerr++;
      }
   }

   # prepare to capture SMTP errors
   my $smtp = '';
   my ($smtperrfh, $smtperrfile) = ow::tool::mktmpfile('smtp.err');

   # redirect stderr to filehandle $smtperrfh
   open(SAVEERR, ">&STDERR");
   open(STDERR, ">&=" . fileno($smtperrfh));
   close($smtperrfh);
   select(STDERR);
   local $| = 1;
   select(STDOUT);

   my $messagestart  = 0;
   my $messagesize   = 0;
   my $messageheader = '';
   my $folderhandle  = do { no warnings 'once'; local *FH };

   if ($do_send) {
      my @recipients = ();

      foreach my $recv ($to, $cc, $bcc) {
         next if ($recv eq '');
         foreach (ow::tool::str2list($recv)) {
            my $addr = (ow::tool::email2nameaddr($_))[1];
            next if ($addr eq '' || $addr =~ m/\s/);
            push (@recipients, $addr);
         }
      }

      foreach my $email (@recipients) {
         # validate receiver email
         matchlist_fromtail('allowed_receiverdomain', $email) or
            openwebmailerror(gettext('You are not allowed to send messages to this email address:') . " $email");
      }

      my $timeout = 120;
      $timeout = 30 if scalar @{$config{smtpserver}} > 1; # cycle through available smtp servers faster
      $timeout += 60 if scalar @recipients > 1;

      # try to connect to one of the smtp servers available
      my $smtpserver = '';
      foreach $smtpserver (@{$config{smtpserver}}) {
         my $connectmsg = "send message - trying to connect to smtp server $smtpserver:$config{smtpport}";
         writelog($connectmsg);
         writehistory($connectmsg);

         $smtp = Net::SMTP->new(
                                 $smtpserver,
                                 Port    => $config{smtpport},
                                 Timeout => $timeout,
                                 Hello   => $config{domainnames}->[0],
                                 Debug   => 1,
                               );

         if ($smtp) {
            $connectmsg = "send message - connected to smtp server $smtpserver:$config{smtpport}";
            writelog($connectmsg);
            writehistory($connectmsg);
            last;
         } else {
            $connectmsg = "send message - error connecting to smtp server $smtpserver:$config{smtpport}";
            writelog($connectmsg);
            writehistory($connectmsg);
         }
      }

      unless ($smtp) {
         # we did not connect to any smtp servers successfully
         $senderr++;

         $senderrstr = gettext('Cannot open any of the following SMTP servers:') .
                       ' ' . join(', ', @{$config{smtpserver}}) .
                       gettext('at SMTP port:') . " $config{smtpport}";

         my $m = qq|send message error - cannot open any SMTP servers | .
                 join(', ', @{$config{smtpserver}}) .
                 qq| at port $config{smtpport}|;

         writelog($m);
         writehistory($m);
      }

      # SMTP SASL authentication (PLAIN only)
      if ($config{smtpauth} && !$senderr) {
         my $auth = $smtp->supports("AUTH");
         unless ($smtp->auth($config{smtpauth_username}, $config{smtpauth_password})) {
            $senderr++;
            $senderrstr = gettext('Network server error:') . "<br>($smtpserver - " . $smtp->message . ")";
            my $m = "send message error - SMTP server $smtpserver error - " . $smtp->message;
            writelog($m);
            writehistory($m);
         }
      }

      $smtp->mail($from) or $senderr++ if !$senderr;

      if (!$senderr) {
         my @ok = $smtp->recipient(@recipients, { SkipBad => 1 });

         if (scalar @ok < scalar @recipients) {
           $senderr++;

           my %ok_addresses        = map { $_, 1 } grep { defined } @ok;
           my %recipient_addresses = map { $_, 1 } grep { defined } @recipients;

           $senderrstr = gettext('Message send aborted due to the following bad recipient addresses:')
                         . ' ' .
                         join(', ', grep { !exists $ok_addresses{$_} } keys %recipient_addresses)
                         . '. ' .
                         gettext('A copy of the message has been saved to your drafts folder.');
         };
      }

      $smtp->data() or $senderr++ if !$senderr;

      # save message to draft if smtp error
      # if there is a quota problem, $saveerr and $saveerrstr are already set
      if ($senderr && (!$quotalimit || $quotausage < $quotalimit) && $config{enable_savedraft}) {
         $do_save    = 1;
         $savefolder = 'saved-drafts';
      }
   }

   if ($do_save) {
      ($savefile, $savedb) = get_folderpath_folderdb($user, $savefolder);

      if (! -f $savefile) {
         if (sysopen($folderhandle, $savefile, O_WRONLY|O_TRUNC|O_CREAT)) {
            close($folderhandle);
         } else {
            $saveerrstr = gettext('Cannot open file:') . " $savefile";
            $saveerr++;
            $do_save = 0;
         }
      }

      if (!$saveerr && ow::filelock::lock($savefile, LOCK_EX)) {
         if (update_folderindex($savefile, $savedb) < 0) {
            ow::filelock::lock($savefile, LOCK_UN);
            openwebmailerror(gettext('Cannot update db:') . ' ' . f2u($savedb));
         }

         my %FDB = ();

         ow::dbm::opendb(\%FDB, $savedb, LOCK_SH) or
            openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($savedb));

         my $oldmsgfound = 0;
         my $oldsubject  = '';

         if (defined $FDB{$mymessageid}) {
            $oldmsgfound = 1;
            $oldsubject  = (string2msgattr($FDB{$mymessageid}))[$_SUBJECT];
         }

         ow::dbm::closedb(\%FDB, $savedb) or
            openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($savedb));

         if ($oldmsgfound) {
            if ($savefolder eq 'saved-drafts' && $subject eq $oldsubject) {
               # remove old draft if the subject is the same
               if (operate_message_with_ids('delete', [$mymessageid], $savefile, $savedb) > 0) {
                  folder_zapmessages($savefile, $savedb);
               } else {
                  $saveerrstr = gettext('Cannot delete message ID from file:') . " $mymessageid\:$savefile";
                  $saveerr++;
                  $do_save = 0;
               }
            } else {
               # user changed the subject, so save it as a new message with
               # its own unique mymessageid (used by compose() later)
               $mymessageid = generate_messageid($from);
               param(-name=>'mymessageid', -value=>$mymessageid);

               # store the old attachments uid so we can migrate
               # all this messages attachments to our new message
               my $old_attachments_uid = $attachments_uid;

               # generate a new attachments_uid for our new mymessageid
               $attachments_uid = length $mymessageid > 22 ? substr($mymessageid,0,22) : $mymessageid;
               $attachments_uid =~ s#[<>@"'&;]##g;

               # build list of existing attachments to rename to this new uid
               opendir(SESSIONSDIR, $config{ow_sessionsdir}) or
                 openwebmailerror(gettext('Cannot open directory:') . " $config{ow_sessionsdir} ($!)");

               my @renamequeue = map  {
                                        my $newfilename = $_;
                                        $newfilename =~ s/\Q$old_attachments_uid\E/$attachments_uid/g;
                                        [ ow::tool::untaint("$config{ow_sessionsdir}/$_"), ow::tool::untaint("$config{ow_sessionsdir}/$newfilename") ]
                                      }
                                 grep { m/^(\Q$thissession-$old_attachments_uid-\Eatt\d+)$/ }
                                 readdir(SESSIONSDIR);

               closedir(SESSIONSDIR) or
                 openwebmailerror(gettext('Cannot close directory:') . " $config{ow_sessionsdir} ($!)");

               # rename the attachment session files on disk to the new uid
               rename($_->[0], $_->[1]) for @renamequeue;

               # update the r_attfiles array with the new uid info
               $_->{file} =~ s/\Q$old_attachments_uid\E/$attachments_uid/ for @{$r_attfiles};

               # update the body param cid and loc with the new uid for when we go back to compose()
               my $original_body = param('body') || '';
               $original_body =~ s/\Q$old_attachments_uid\E/$attachments_uid/g;
               param(-name=>'body', -value=>$original_body);
            }
         }

         if (sysopen($folderhandle, $savefile, O_RDWR)) {
            $messagestart = (stat($folderhandle))[7];
            seek($folderhandle, $messagestart, 0); # seek end manually to cover tell() bug in perl 5.8
         } else {
            $saveerrstr = gettext('Cannot open file:') . " $savefile";
            $saveerr++;
            $do_save = 0;
         }
      } else {
         $saveerrstr = gettext('Cannot lock file:') . " $savefile";
         $saveerr++;
         $do_save = 0;
      }
   }

   # nothing to do, return error msg immediately
   if ($do_send == 0 && $do_save == 0) {
      openwebmailerror($saveerrstr) if $saveerr;

      print redirect(
                      -location => qq|$config{ow_cgiurl}/openwebmail-main.pl?| .
                                   qq|action=listmessages| .
                                   qq|&sessionid=$thissession| .
                                   qq|&sort=$sort| .
                                   qq|&msgdatetype=$msgdatetype| .
                                   qq|&page=$page| .
                                   qq|&folder=| . ow::tool::escapeURL($folder)
                    );
   }

   # Add a 'From ' as delimeter for locally saved message
   my $s = "From $user ";

   if ($config{delimiter_use_GMT}) {
      $s .= ow::datetime::dateserial2delimiter(ow::datetime::gmtime2dateserial(), '', $prefs{daylightsaving}, $prefs{timezone}) . "\n";
   } else {
      # use server localtime for delimiter
      $s .= ow::datetime::dateserial2delimiter(ow::datetime::gmtime2dateserial(), ow::datetime::gettimeoffset(), $prefs{daylightsaving}, $prefs{timezone}) . "\n";
   }
   print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);
   $messageheader .= $s;

   if ($realname ne '') {
      $s = "From: " . ow::mime::encode_mimewords(qq|"$realname" <$from>|, ('Charset' => $composecharset)) . "\n";
   } else {
      $s = "From: " . ow::mime::encode_mimewords(qq|$from|, ('Charset' => $composecharset)) . "\n";
   }
   dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
   $messageheader .= $s;

   if ($to ne '') {
      $s = "To: " . ow::mime::encode_mimewords(folding(join(', ', ow::tool::str2list($to))), ('Charset' => $composecharset)) . "\n";
      dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
      $messageheader .= $s;
   } elsif ($bcc ne '' && $cc eq '') {
      # recipients in Bcc only, To and Cc are null
      $s = "To: undisclosed-recipients: ;\n";
      print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);
      $messageheader .= $s;
   }

   if ($cc ne '') {
      $s = "Cc: " . ow::mime::encode_mimewords(folding(join(', ', ow::tool::str2list($cc))), ('Charset' => $composecharset)) . "\n";
      dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
      $messageheader .= $s;
   }

   if ($bcc ne '') {
      # put bcc header in folderfile only, not in outgoing msg
      $s = "Bcc: " . ow::mime::encode_mimewords(folding(join(', ', ow::tool::str2list($bcc))), ('Charset' => $composecharset)) . "\n";
      print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);
      $messageheader .= $s;
   }

   $s  = '';
   $s .= "Reply-To: " . ow::mime::encode_mimewords(folding(join(', ', ow::tool::str2list($replyto))), ('Charset' => $composecharset)) . "\n" if $replyto;
   $s .= "Subject: " . ow::mime::encode_mimewords($subject, ('Charset' => $composecharset)) . "\n";
   $s .= "Date: $date\n";
   $s .= "Message-Id: $mymessageid\n";
   $s .= "In-Reply-To: $inreplyto\n" if $inreplyto;
   $s .= "References: $references\n" if $references;
   $s .= "Priority: $priority\n" if $priority && $priority ne 'normal';
   $s .= safexheaders($config{xheaders});
   if ($confirmreading) {
      if ($replyto ne '') {
         $s .= "X-Confirm-Reading-To: " . ow::mime::encode_mimewords(folding(join(', ', ow::tool::str2list($replyto))), ('Charset' => $composecharset)) . "\n";
         $s .= "Disposition-Notification-To: " . ow::mime::encode_mimewords(folding(join(', ', ow::tool::str2list($replyto))), ('Charset' => $composecharset)) . "\n";
      } else {
         $s .= "X-Confirm-Reading-To: $from\n";
         $s .= "Disposition-Notification-To: $from\n";
      }
   }
   $s .= "MIME-Version: 1.0\n";
   dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
   $messageheader .= $s;

   my $contenttype = '';
   my $boundary1 = "----=OPENWEBMAIL_ATT_" . rand();
   my $boundary2 = "----=OPENWEBMAIL_ATT_" . rand();
   my $boundary3 = "----=OPENWEBMAIL_ATT_" . rand();

   # organize attachments into two categories: mixed and related
   # related attachments will be referenced by cid or loc
   my @related = ();
   my @mixed   = ();
   foreach my $r_att (@{$r_attfiles}) {
      if (exists $r_att->{referencecount} && $r_att->{referencecount} > 0 && $msgformat ne 'text') {
         push(@related, $r_att);
      } else {
         $r_att->{referencecount} = 0;
         push(@mixed, $r_att);
      }
   }

   if (scalar @mixed > 0) {
      $contenttype = "multipart/mixed;";

      $s = qq|Content-Type: multipart/mixed;\n| .
           qq|\tboundary="$boundary1"\n|;

      dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
      print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);
      $messageheader .= $s . "Status: R\n";

      dump_str(
                qq|\nThis is a multi-part message in MIME format.\n|,
                $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
              );

      if (scalar @related > 0) {
         # has related att AND has mixed att
         if ($msgformat eq 'html') {
            dump_str(
                      qq|\n--$boundary1\n| .
                      qq|Content-Type: multipart/related;\n| .
                      qq|\ttype="text/html";\n| .
                      qq|\tboundary="$boundary2"\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_bodyhtml(
                           \$body, $boundary2, $composecharset, $msgformat, $smtp,
                           $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );
            dump_atts(
                       \@related, $boundary2, $composecharset, $smtp, $folderhandle,
                       $do_send, $do_save, \$senderr, \$saveerr
                     );

         } elsif ($msgformat eq "both") {
            $contenttype = "multipart/related;";

            dump_str(
                      qq|\n--$boundary1\n| .
                      qq|Content-Type: multipart/related;\n| .
                      qq|\ttype="multipart/alternative";\n| .
                      qq|\tboundary="$boundary2"\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_str(
                      qq|\n--$boundary2\n|.
                      qq|Content-Type: multipart/alternative;\n|.
                      qq|\tboundary="$boundary3"\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_bodytext(
                           \$body, $boundary3, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_bodyhtml(
                           \$body, $boundary3, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_str(
                      qq|\n--$boundary3--\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_atts(
                       \@related, $boundary2, $composecharset,
                       $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                     );
         }

         dump_str(
                   qq|\n--$boundary2--\n|,
                   $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                 );
      } else {
         # no related att, has mixed att
         if ($msgformat eq 'text') {
            dump_bodytext(
                           \$body, $boundary1, $composecharset,  $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

         } elsif ($msgformat eq 'html') {
            dump_bodyhtml(
                           \$body, $boundary1, $composecharset,  $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

         } elsif ($msgformat eq 'both') {
            dump_str(
                      qq|\n--$boundary1\n| .
                      qq|Content-Type: multipart/alternative;\n| .
                      qq|\tboundary="$boundary2"\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_bodytext(
                           \$body, $boundary2, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_bodyhtml(
                           \$body, $boundary2, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_str(
                      qq|\n--$boundary2--\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );
         }
      }

      dump_atts(
                 \@mixed, $boundary1, $composecharset,
                 $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
               );

      dump_str(
                qq|\n--$boundary1--\n|,
                $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
              );
   } else {
      if (scalar @related > 0) {
         # has related att, no mixed att
         if ($msgformat eq 'html') {
            $contenttype = "multipart/related;";

            $s = qq|Content-Type: multipart/related;\n| .
                 qq|\ttype="text/html";\n| .
                 qq|\tboundary="$boundary1"\n|;

            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);

            $messageheader .= $s . "Status: R\n";

            dump_str(
                      qq|\nThis is a multi-part message in MIME format.\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_bodyhtml(
                           \$body, $boundary1, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_atts(
                       \@related, $boundary1, $composecharset,
                       $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                     );
         } elsif ($msgformat eq "both") {
            $contenttype = "multipart/related;";

            $s = qq|Content-Type: multipart/related;\n| .
                 qq|\ttype="multipart/alternative";\n| .
                 qq|\tboundary="$boundary1"\n|;

            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);

            $messageheader .= $s . "Status: R\n";

            dump_str(
                      qq|\nThis is a multi-part message in MIME format.\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_str(
                      qq|\n--$boundary1\n| .
                      qq|Content-Type: multipart/alternative;\n| .
                      qq|\tboundary="$boundary2"\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_bodytext(
                           \$body, $boundary2, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_bodyhtml(
                           \$body, $boundary2, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_str(
                      qq|\n--$boundary2--\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_atts(
                       \@related, $boundary1, $composecharset,
                       $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                     );
         }

         dump_str(
                   qq|\n--$boundary1--\n|,
                   $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                 );
      } else {
         # no related att, no mixed att
         if ($msgformat eq 'text') {
            $contenttype = "text/plain; charset=$composecharset";

            $s = qq|Content-Type: text/plain; charset=$composecharset\n|;

            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);

            $messageheader .= $s . "Status: R\n";

            $smtp->datasend("\n$body\n") or $senderr++ if ($do_send && !$senderr);

            $body =~ s/^From />From /gm;
            print $folderhandle "\n$body\n" or $saveerr++ if ($do_save && !$saveerr);

            if ( $config{'mailfooter'}=~/[^\s]/) {
               $s = str2str($config{mailfooter}, $msgformat) . "\n";
               $smtp->datasend($s) or $senderr++ if ($do_send && !$senderr);
            }
         } elsif ($msgformat eq 'html') {
            $contenttype = "text/html; charset=$composecharset";

            $s = qq|Content-Type: text/html; charset=$composecharset\n| .
                 qq|Content-Transfer-Encoding: quoted-printable\n|;

            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);

            $messageheader .= $s . "Status: R\n";

            $s = qq|\n| . ow::mime::encode_qp($body) . qq|\n|;
            $smtp->datasend($s) or $senderr++ if ($do_send && !$senderr);

            $s =~ s/^From />From /gm;
            print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);

            if ( $config{'mailfooter'}=~/[^\s]/) {
               $s = ow::mime::encode_qp(str2str($config{mailfooter}, $msgformat))."\n";
               $smtp->datasend($s) or $senderr++ if ($do_send && !$senderr);
            }
         } elsif ($msgformat eq 'both') {
            $contenttype = "multipart/alternative;";

            $s = qq|Content-Type: multipart/alternative;\n| .
                 qq|\tboundary="$boundary1"\n|;

            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);

            $messageheader .= $s . "Status: R\n";

            dump_str(
                      qq|\nThis is a multi-part message in MIME format.\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );

            dump_bodytext(
                           \$body, $boundary1, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_bodyhtml(
                           \$body, $boundary1, $composecharset, $msgformat,
                           $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                         );

            dump_str(
                      qq|\n--$boundary1--\n|,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr
                    );
         }
      }
   }

   # terminate this message
   $smtp->dataend() or $senderr++ if ($do_send && !$senderr);

   # ensure a blank line between messages for local saved msgs
   print $folderhandle "\n" or $saveerr++ if ($do_save && !$saveerr);

   if ($do_send) {
      if (!$senderr) {
         $smtp->quit();
         open(STDERR, ">&SAVEERR"); # redirect stderr back
         close(SAVEERR);

         my @r = ();
         push(@r, "to=$to") if $to;
         push(@r, "cc=$cc") if $cc;
         push(@r, "bcc=$bcc") if $bcc;
         my $m = "send message - subject=" . (iconv($composecharset, $prefs{fscharset}, $subject))[0] . " - " . join(', ', @r);
         writelog($m);
         writehistory($m);
      } else {
         $smtp->close() if $smtp;   # close smtp if it was successfully opened
         open(STDERR, ">&SAVEERR"); # redirect stderr back
         close(SAVEERR);

         if ($senderrstr eq '') {
            $senderrstr = gettext('Sorry, there was an unknown problem sending your message.');

            if ($do_save && $savefolder eq 'saved-drafts') {
               my $draft_url = qq|$config{ow_cgiurl}/openwebmail-send.pl?action=compose&composetype=editdraft&folder=| .
                               ow::tool::escapeURL($savefolder) .
                               qq|&sessionid=$thissession&message_id=| .
                               ow::tool::escapeURL($mymessageid);

               $senderrstr .= qq|<br>\n<a href="$draft_url">| . gettext('Please check the message saved in the draft folder, and try again.') . qq|</a>\n|;
            }

            # get the output from the SMTP server/client conversation
            my $smtperr = readsmtperr($smtperrfile);

            $senderrstr .= qq|<br><br>\n| .
                           qq|<form method="post" action="#" name="errorwindow">\n| .
                           qq|<textarea rows="10" cols="72" name="smtperror" wrap="soft">\n| .
                           ow::htmltext::str2html($smtperr) . qq|\n| .
                           qq|</textarea>\n| .
                           qq|</form>|;
            $smtperr =~ s/\n/\n /gs;
            $smtperr =~ s/\s+$//;
            writelog("send message error - smtp error ...\n $smtperr");
            writehistory("send message error - smtp error");
         }
      }
   } else {
      open(STDERR, ">&SAVEERR"); # redirect stderr back
      close(SAVEERR);
   }

   unlink($smtperrfile);

   if ($do_save) {
      if (!$saveerr) {
         # update the database with this saved message attributes
         close($folderhandle);
         $messagesize = (stat($savefile))[7] - $messagestart;

         my @attr = ();
         $attr[$_OFFSET] = $messagestart;

         $attr[$_TO] = $to;
         $attr[$_TO] = $cc if $attr[$_TO] eq '';
         $attr[$_TO] = $bcc if $attr[$_TO] eq '';

         # some dbm(ex:ndbm on solaris) can only has value shorter than
         # 1024 byte, so we cut $_to to 256 byte to make dbm happy
         if (length($attr[$_TO]) > 256) {
            $attr[$_TO] = substr($attr[$_TO], 0, 252) . '...';
         }

         if ($realname) {
            $attr[$_FROM] = qq|"$realname" <$from>|;
         } else {
            $attr[$_FROM] = qq|$from|;
         }

         $attr[$_DATE]         = $dateserial;
         $attr[$_RECVDATE]     = $dateserial;
         $attr[$_SUBJECT]      = $subject;
         $attr[$_CONTENT_TYPE] = $contenttype;

         ($attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]) = iconv($composecharset, 'utf-8', $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]);

         $attr[$_STATUS] = 'R';
         $attr[$_STATUS] .= 'I' if $priority eq 'urgent';

         # flags used by openwebmail internally
         $attr[$_STATUS] .= 'T' if scalar @{$r_attfiles} > 0;

         $attr[$_REFERENCES]   = $references;
         $attr[$_CHARSET]      = $composecharset;
         $attr[$_SIZE]         = $messagesize;
         $attr[$_HEADERSIZE]   = length($messageheader);
         $attr[$_HEADERCHKSUM] = ow::tool::calc_checksum(\$messageheader);

         my %FDB = ();

         ow::dbm::opendb(\%FDB, $savedb, LOCK_EX) or
            openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($savedb));

         $FDB{ALLMESSAGES}++;
         $FDB{$mymessageid} = msgattr2string(@attr);
         $FDB{METAINFO}     = ow::tool::metainfo($savefile);
         $FDB{LSTMTIME}     = time();

         ow::dbm::closedb(\%FDB, $savedb) or writelog("cannot close db $savedb");
      } else {
         # there was an error
         truncate($folderhandle, ow::tool::untaint($messagestart));

         close($folderhandle);

         my %FDB = ();

         ow::dbm::opendb(\%FDB, $savedb, LOCK_EX) or
            openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($savedb));

         $FDB{METAINFO} = ow::tool::metainfo($savefile);
         $FDB{LSTMTIME} = time();

         ow::dbm::closedb(\%FDB, $savedb) or writelog("cannot close db $savedb");
      }

      ow::filelock::lock($savefile, LOCK_UN) or writelog("cannot unlock file $savefile");
   }

   # status update (mark referenced message as answered) and folderdb update.
   # This must be done AFTER the above do_savefolder block since the start of
   # the savemessage would be changed by status_update if the savedmessage is
   # on the same folder as the answered message
   if ($do_send && !$senderr && $inreplyto) {
      my @checkfolders=();

      # if the current folder is the sent/draft folder, we try to find the original
      # message from the other folders. Otherwise we just check the current folder
      if ($folder eq 'sent-mail' || $folder eq 'saved-drafts' ) {
         my (@validfolders, $inboxusage, $folderusage);
         getfolders(\@validfolders, \$inboxusage, \$folderusage);
         foreach (@validfolders) {
            push(@checkfolders, $_) if $_ ne 'sent-mail' || $_ ne 'saved-drafts';
         }
      } else {
         push(@checkfolders, $folder);
      }

      # identify where the original message is
      foreach my $foldername (@checkfolders) {
         my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldername);

         my (%FDB, $oldstatus, $found);

         ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or
            openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb));

         if (defined $FDB{$inreplyto}) {
            $oldstatus = (string2msgattr($FDB{$inreplyto}))[$_STATUS];
            $found = 1;
         }

         ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

         if ($found) {
            if ($oldstatus !~ m/a/i) {
               # oldstatus is "not answered", try to mark answered if get filelock
               if (ow::filelock::lock($folderfile, LOCK_EX)) {
                  update_message_status($inreplyto, $oldstatus . 'A', $folderdb, $folderfile);
                  ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
               } else {
                  writelog("cannot lock file $folderfile");
               }
            }

            last;
         }
      }
   }

   if ($senderr) {
      openwebmailerror($senderrstr, 'passthrough');
   } elsif ($saveerr) {
      openwebmailerror($saveerrstr);
   } else {
      if ($sendbutton) {
         # clean up attachments
         delete_attachments($attachments_uid);

         my $sentsubject = (iconv($composecharset, $prefs{charset}, $subject || gettext('(no subject)')))[0];

         print redirect(
                         -location => qq|$config{ow_cgiurl}/openwebmail-main.pl?| .
                                      qq|action=listmessages| .
                                      qq|&sessionid=$thissession| .
                                      qq|&sort=$sort| .
                                      qq|&msgdatetype=$msgdatetype| .
                                      qq|&page=$page| .
                                      qq|&sentsubject=| . ow::tool::escapeURL($sentsubject) .
                                      qq|&folder=| . ow::tool::escapeURL($folder)
                       );
      } else {
         # save draft, call getfolders to recalc used quota
         if ($quotalimit > 0 && $quotausage + $messagesize > $quotalimit) {
            $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
         }
         return(compose());
      }
   }
}

sub dump_str {
   # write a string to a smtp (if do_send) and folderhandle (if do_save)
   my ($s, $smtp, $folderhandle, $do_send, $do_save, $r_senderr, $r_saveerr) = @_;
   $smtp->datasend($s)    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
   print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});
}

sub dump_bodytext {
   my ($r_body, $boundary, $composecharset, $msgformat,
       $smtp, $folderhandle, $do_send, $do_save, $r_senderr, $r_saveerr) = @_;

   my $s = qq|\n--$boundary\n| .
           qq|Content-Type: text/plain; charset=$composecharset\n| .
           qq|Content-Transfer-Encoding: 8bit\n\n|;

   if ($msgformat eq 'text') {
      $s .= qq|${$r_body}\n|;
   } else {
      $s .= ow::htmltext::html2text(${$r_body}) . qq|\n|;
   }
   $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});

   $s =~ s/^From / From/gm;
   print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});

   if ($config{mailfooter} =~ m/[^\s]/) {
      $s = str2str($config{mailfooter}, $msgformat) . "\n";
      $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});
   }
}

sub dump_bodyhtml {
   my ($r_body, $boundary, $composecharset, $msgformat,
       $smtp, $folderhandle, $do_send, $do_save, $r_senderr, $r_saveerr) = @_;

   my $s = qq|\n--$boundary\n| .
           qq|Content-Type: text/html; charset=$composecharset\n| .
           qq|Content-Transfer-Encoding: quoted-printable\n\n|;

   if ($msgformat eq 'text') {
      $s .= ow::mime::encode_qp(ow::htmltext::text2html(${$r_body})) . qq|\n|;
   } else {
      $s .= ow::mime::encode_qp(${$r_body}) . qq|\n|;
   }
   $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});

   $s =~ s/^From / From/gm;
   print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});

   if ($config{mailfooter} =~ m/[^\s]/) {
      $s = ow::mime::encode_qp(str2str($config{mailfooter}, $msgformat)) . "\n";
      $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});
   }
}

sub dump_atts {
   my ($r_atts, $boundary, $composecharset, $smtp, $folderhandle,
       $do_send, $do_save, $r_senderr, $r_saveerr) = @_;

   my $s = '';

   foreach my $r_att (@{$r_atts}) {
      $smtp->datasend("\n--$boundary\n")    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
      print $folderhandle "\n--$boundary\n" or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});

      my $attfile    = "$config{ow_sessionsdir}/$r_att->{file}";
      my $referenced = $r_att->{referencecount};

      sysopen(ATTFILE, $attfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $attfile ($!)");

      # print attheader line by line
      while (defined($s = <ATTFILE>)) {
         # remove contentid from attheader if it was set by openwebmail but
         # not referenced, since outlook will treat an attachment as invalid
         # if it has content-id but has not been referenced
         next if ($s =~ m/^Content\-Id: <?att\d{8}/ && !$referenced);

         $s =~ s/^(.+name="?)([^"]+)("?.*)$/_convert_attfilename($1, $2, $3, $composecharset)/ie;
         $smtp->datasend($s)    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
         print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});
         last if $s =~ /^\s+$/;
      }

      # print attbody block by block
      while (read(ATTFILE, $s, 32768)) {
         $smtp->datasend($s)    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
         print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});
      }

      close(ATTFILE) or
         openwebmailerror(gettext('Cannot close file:') . " $attfile ($!)");
   }

   return;
}

sub _convert_attfilename {
   # convert filename in attheader to same charset as message itself when sending
   my ($prefix, $name, $postfix, $targetcharset) = @_;

   my $origcharset = '';
   $origcharset = $1 if $name =~ m#=\?([^?]*)\?[bq]\?[^?]+\?=#xi;
   return "$prefix$name$postfix" if $origcharset eq '' || $origcharset eq $targetcharset;

   if (is_convertible($origcharset, $targetcharset)) {
      $name = ow::mime::decode_mimewords($name);
      $name = (iconv($origcharset, $targetcharset, $name))[0];
      $name = ow::mime::encode_mimewords($name, ('Charset' => $targetcharset));
   }

   return "$prefix$name$postfix";
}

sub folding {
   # folding the to, cc, bcc field so it won't violate the 998 char
   # limit (defined in RFC 2822 2.2.3) after base64/qp encoding
   # ps: since qp may extend strlen by 3 times, we use 998/3=332 as limit
   my $string = shift;

   return $string if length($string) < 330;

   my $folding = '';
   my $line    = '';

   foreach my $token (ow::tool::str2list($string)) {
      if (length($line) + length($token) < 330) {
         $line .= ",$token";
      } else {
         $folding .= "$line,\n   ";
         $line = $token;
      }
   }

   $folding .= $line;

   $folding =~ s/^,//;

   return($folding);
}

sub readsmtperr {
   # extract the SMTP conversation errors from the smtp error file, scrub, and return
   my $smtperrorfile = shift;

   my $content   = '';
   my $linecount = 0;

   sysopen(F, $smtperrorfile, O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $smtperrorfile ($!)");

   while (<F>) {
      s/\s*$//;
      if (m/(>>>.*$)/ || m/(<<<.*$)/) {
         $content .= "$1\n";
         $linecount++;
         if ($linecount == 50) {
            my $snip = (-s $smtperrorfile) - 512 - tell(F);
            if ($snip > 512) {
               seek(F, $snip, 1);
               $_ = <F>;
               $snip += length($_);
               $content .= "\n" . sprintf(ngettext('%d byte snipped ...', '%d bytes snipped ...', $snip), $snip) . "\n\n";
            }
         }
      }
   }

   close(F) or
      openwebmailerror(gettext('Cannot close file:') . " $smtperrorfile ($!)");

   return $content;
}

sub replyreceipt {
   # this subroutine is called from the read_readmessage.tmpl
   # it sends read receipts for messages that request it
   # and outputs the result into the popup window created by read_readmessage.tmpl
   my $messageid = param('message_id') || openwebmailerror(gettext('No message ID provided for replyreceipt'));

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   my %FDB = ();

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
      openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb));

   my @attr = string2msgattr($FDB{$messageid});

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

   my $success = 0;

   if ($attr[$_SIZE] > 0) {
      my $header = '';

      # get message header
      sysopen(FOLDER, $folderfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($folderfile) . " ($!)");

      seek (FOLDER, $attr[$_OFFSET], 0) or
         openwebmailerror(gettext('Cannot seek in file:') . ' ' . f2u($folderfile) . " ($!)");

      while (<FOLDER>) {
         last if $_ eq "\n" && $header =~ m/\n$/;
         $header .= $_;
      }

      close(FOLDER) or
         openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($folderfile) . " ($!)");

      # get notification-to
      if ($header =~ m/^Disposition-Notification-To:\s?(.*?)$/im) {
         my $to        = $1;
         my $date      = ow::datetime::dateserial2datefield(ow::datetime::gmtime2dateserial(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
         my $userfroms = get_userfroms();

         my $from = (grep { $header =~ m/$_/ } keys %{$userfroms})[0] || $prefs{email};

         my $realname = $userfroms->{$from};
         $realname =~ s/['"]/ /g; # Get rid of shell escape attempts
         $from     =~ s/['"]/ /g; # Get rid of shell escape attempts

         my @recipients = ();
         foreach my $to_recipient (ow::tool::str2list($to)) {
            my $addr = (ow::tool::email2nameaddr($to_recipient))[1];
            next if ($addr eq '' || $addr =~ m/\s/);
            push (@recipients, $addr);
         }

         # generate a messageid for the message we're composing
         my $mymessageid = generate_messageid($from);

         my $smtp    = '';
         my $timeout = 120;
         $timeout    = 30 if scalar @{$config{smtpserver}} > 1; # cycle through available smtp servers faster
         $timeout   += 60 if scalar @recipients > 1; # more than 1 recipient

         # try to connect to one of the smtp servers available
         my $smtpserver = '';
         foreach $smtpserver (@{$config{smtpserver}}) {
            my $connectmsg = "send message - trying to connect to smtp server $smtpserver\:$config{smtpport}";
            writelog($connectmsg);
            writehistory($connectmsg);

            $smtp = Net::SMTP->new(
                                    $smtpserver,
                                    Port    => $config{smtpport},
                                    Timeout => $timeout,
                                    Hello   => ${$config{domainnames}}[0]
                                  );

            if ($smtp) {
               $connectmsg = "send message - connected to smtp server $smtpserver\:$config{smtpport}";
               writelog($connectmsg);
               writehistory($connectmsg);
               last;
            } else {
               $connectmsg = "send message - error connecting to smtp server $smtpserver\:$config{smtpport}";
               writelog($connectmsg);
               writehistory($connectmsg);
            }
         }

         unless ($smtp) {
            # we did not connect to any smtp servers successfully
            openwebmailerror(gettext('Cannot open any of the following SMTP servers:') . ' ' . join(', ', @{$config{smtpserver}}) . gettext('at SMTP port:') . " $config{smtpport}");
         }

         # SMTP SASL authentication (PLAIN only)
         if ($config{smtpauth}) {
            my $auth = $smtp->supports('AUTH');
            $smtp->auth($config{smtpauth_username}, $config{smtpauth_password}) or
               openwebmailerror(gettext('Network server error:') . " ($smtpserver - " . ow::htmltext::str2html($smtp->message) . ')', 'passthrough');
         }

         $smtp->mail($from);

         my @ok = $smtp->recipient(@recipients, { SkipBad => 1 });

         if (scalar @ok < scalar @recipients) {
            # Sending of reply receipt should fail if there exists any failing address in list
            $smtp->close();
            openwebmailerror(gettext('The recipients list could not be validated. Please check the recipients and try again.'));
         }

         $smtp->data();

         # TODO: The reply receipt should be in the character set and language of the original message if we can support it.
         # TODO: Only then switch to english. The mess below is a crazy mixture of UTF8 and the users preferred charset.

         my $s = '';

         if ($realname ne '') {
            $s .= "From: " . ow::mime::encode_mimewords(qq|"$realname" <$from>|, ('Charset' => $prefs{charset})) . "\n";
         } else {
            $s .= "From: " . ow::mime::encode_mimewords(qq|$from|, ('Charset' => $prefs{charset})) . "\n";
         }

         $s .= "To: " . ow::mime::encode_mimewords(folding(join(', ', ow::tool::str2list($to))), ('Charset' => $prefs{charset})) . "\n";

         $s .= "Reply-To: " . ow::mime::encode_mimewords($prefs{replyto}, ('Charset' => $prefs{charset})) . "\n" if $prefs{replyto};

         # reply with english if sender has different charset than us
         my $is_samecharset = 0;

         # replies in local language currently disabled, utf-8 is whole world
         # $is_samecharset=1 if ( $attr[$_CONTENT_TYPE]=~/charset="?\Q$prefs{charset}\E"?/i);

         if ($is_samecharset) {
            $s .= "Subject: " . ow::mime::encode_mimewords(gettext('Read receipt:') . " $attr[$_SUBJECT]", ('Charset' => $prefs{charset})) . "\n";
         } else {
            $s .= "Subject: " . ow::mime::encode_mimewords("Read receipt: $attr[$_SUBJECT]", ('Charset' => 'utf-8')) . "\n";
         }

         $s .= "Date: $date\n" .
               "Message-Id: $mymessageid\n" .
               safexheaders($config{xheaders}) .
               "MIME-Version: 1.0\n";

         if ($is_samecharset) {
            $s .= "Content-Type: text/plain; charset=$prefs{charset}\n\n" .
                  gettext('Your message:') . "\n\n" .
                  '   ' . gettext('To:') . " $attr[$_TO]\n" .
                  '   ' . gettext('Subject:') . " $attr[$_SUBJECT]\n" .
                  '   ' . gettext('Delivered:') . ' ' .
                  ow::datetime::dateserial2str($attr[$_DATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                               $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}) .
                  "\n\n" .
                  gettext('was read on:') . ' ' .
                  ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial(), $prefs{timeoffset}, $prefs{daylightsaving},
                                               $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}) .
                  ".\n\n";
         } else {
            $s .= "Content-Type: text/plain; charset=utf-8\n\n" .
                  "Your message:\n\n" .
                  "  To: $attr[$_TO]\n" .
                  "  Subject: $attr[$_SUBJECT]\n" .
                  "  Delivered: " .
                  ow::datetime::dateserial2str($attr[$_DATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                               $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}) .
                  "\n\n" .
                  "was read on: " .
                  ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial(), $prefs{timeoffset}, $prefs{daylightsaving},
                                               $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}) .
                  ".\n\n";
         }

         $s .= str2str($config{mailfooter}, 'text') . "\n" if $config{mailfooter} =~ m/[^\s]/;

         if (!$smtp->datasend($s) || !$smtp->dataend()) {
            $smtp->close();
            openwebmailerror(gettext('Sorry, there was an unknown problem sending your message.'));
         }

         $smtp->quit();
      }

      $success = 1;
   }

   my $template = HTML::Template->new(
                                        filename          => get_template('send_replyreceipt.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      folder          => $folder,
                      sort            => $sort,
                      msgdatetype     => $msgdatetype,
                      page            => $page,
                      longpage        => $longpage,
                      searchtype      => $searchtype,
                      keyword         => $keyword,
                      url_cgi         => $config{ow_cgiurl},
                      url_html        => $config{ow_htmlurl},
                      use_texticon    => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont   => $prefs{usefixedfont},
                      charset         => $prefs{charset},
                      iconset         => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # send_replyreceipt.tmpl
                      success         => $success,
                      messageid       => $messageid,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

