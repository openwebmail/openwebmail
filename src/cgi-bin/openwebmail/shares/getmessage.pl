
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

# getmessage.pl - get and parse a message

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);

use vars qw(%config);

sub getmessage {
   my ($user, $folder, $messageid, $mode) = @_;

   $mode = '' unless defined $mode && $mode eq 'all';

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   my $block   = '';

   # -1: lock/open error
   # -2: message id not in database
   # -3: invalid message size in database
   # -4: message size mismatch read error
   # -5: message start and end does not match index
   my $msgsize = lockget_message_block($messageid, $folderfile, $folderdb, \$block);

   my %message = ();

   if ($msgsize == -1) {
      openwebmailerror(gettext('Cannot lock or open file:') . " $folderfile");
   } elsif ($msgsize == -2) {
      return \%message;
   } elsif ($msgsize == -3 || $msgsize == -4 || $msgsize == -5) {
      # set metainfo=ERR to force reindex in next update_folderindex
      my %FDB = ();

      ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or
         openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb));

      @FDB{'METAINFO', 'LSTMTIME'} = ('ERR', -1);

      ow::dbm::closedb(\%FDB, $folderdb) or
         openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($folderdb));

      $msgsize = lockget_message_block($messageid, $folderfile, $folderdb, \$block);
      openwebmailerror(gettext('Error opening message:') . " $msgsize") if $msgsize < 0 && $msgsize != -2;
   }

   return \%message if $msgsize <= 0;

   $message{size} = $msgsize;

   # member: header, body, attachment
   #         return-path from to cc bcc reply-to date subject status
   #         message-id content-type encoding in-reply-to references priority
   $message{$_} = 'N/A' for qw(from to date subject content-type);
   $message{$_} = ''    for qw(return-path cc bcc reply-to status in-reply-to references charset priority);

   # $r_attachment is a reference to attachment array!
   if ($mode eq 'all') {
      ($message{header}, $message{body}, $message{attachment}) = ow::mailparse::parse_rfc822block(\$block, 0, 'all');
   } else {
      ($message{header}, $message{body}, $message{attachment}) = ow::mailparse::parse_rfc822block(\$block, 0, '');
   }

   return {} if $message{header} eq ''; # return empty hash if no header found

   ow::mailparse::parse_header(\$message{header}, \%message);

   $message{status} .= $message{'x-status'} if exists $message{'x-status'} && defined $message{'x-status'};

   # recover incomplete header attr for messages resent from a mailing list - tricky!
   if ($message{'content-type'} eq 'N/A') {
      if (defined $message{attachment}->[0]) {
         # message has attachment(s)
         $message{'content-type'} = 'multipart/mixed;';
      } elsif ($message{body} =~ m/^\n*([A-Za-z0-9+]{50,}\n?)+/s) {
         $message{'content-type'} = 'text/plain';
         $message{'content-transfer-encoding'} = 'base64';
      } elsif ($message{body} =~ m/(=[\dA-F][\dA-F]){3}/i) {
         $message{'content-type'} = 'text/plain';
         $message{'content-transfer-encoding'} = 'quoted-printable';
      }
   }

   my ($r_smtprelays, $r_connectfrom, $r_byas) = ow::mailparse::get_smtprelays_connectfrom_byas_from_header($message{header});

   foreach my $relay (@{$r_smtprelays}) {
      next if $relay !~ m/[\w\d\-_]+\.[\w\d\-_]+/;

      $message{smtprelay} = $relay;

      foreach my $localdomain (@{$config{domainnames}}) {
         if ($message{smtprelay} =~ $localdomain) {
            $message{smtprelay} = '';
            last;
         }
      }

      last if $message{smtprelay} ne '';
   }

   # remove [] around ip addr in mailheader
   # since $message{smtprelay} may be put into filterrule
   # and we do not want [] be treat as regular expression
   $message{smtprelay} =~ s/[\[\]]//g if defined $message{smtprelay};

   $message{status} .= 'I' if $message{priority} =~ m/urgent/i;
   $message{status} =~ s/\s//g;

   if ($message{'content-type'} =~ m/charset="?([^\s"';]*)"?\s?/i) {
      $message{charset} = $1;
   } elsif (defined @{$message{attachment}}) {
      my @att = @{$message{attachment}};

      foreach my $i (0 .. $#att) {
         if (defined $att[$i]->{charset} && $att[$i]->{charset} ne '') {
            $message{charset} = $att[$i]->{charset};
            last;
         }
      }
   }

   # ensure message charsetname is official
   $message{charset} = official_charset($message{charset});

   foreach (qw(from reply-to to cc bcc subject)) {
      $message{$_} = '' unless defined $message{$_};
      $message{$_} = decode_mimewords_iconv($message{$_}, 'utf-8') if $message{$_} ne 'N/A';
   }

   return \%message;
}

1;
