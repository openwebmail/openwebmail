
#                              The BSD License
#
#  Copyright (c) 2009-2011, The OpenWebMail Project
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

# adrbook.pl - The main front-end for reading and writing addressbook data

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

require "modules/filelock.pl"; # file locking support
require "shares/ow-shared.pl"; # openwebmailerror and gettext support
require "shares/vfile.pl";     # vfile reading support

use vars qw(%config);

sub readadrbook {
   my ($adrbookfile, $r_searchtermshash, $r_onlyreturn) = @_;
   # $adrbookfile is the full path to the addressbook file.
   #
   # $r_adrbookhash is a reference to a hash where all of the returned vcards
   # will be stored. This is usually passed into this subroutine empty since this
   # subroutine is designed to populate it with the data received from vfile.pl.
   #
   # $r_searchtermshash is a reference to a hash table in the same structure as a
   # vcard. Any parsed vcards that match the searchterm's vcard are returned. This is
   # handy because it allows the search functionality to be expanded if new vcard
   # properties are added over time.
   #
   # $r_onlyreturn is a hash of vcard propertynames. When this is defined, only
   # propertynames that exist in the $r_onlyreturn hash are returned in $r_adrbookhash.
   # This is a way to limit the memory requirement of the returned data. It also speeds
   # up processing considerably because during processing, values that are not
   # requested are skipped. Even if this is defined, the AGENT property must still be
   # processed because of it's recursive nature (however, only the defined $r_onlyreturn
   # propertynames are returned in the AGENT hash). Use of this option also turns off
   # data checking of vCard data, so propertynames that are normally mandatory are
   # allowed to be missing. You may even receive an empty hash! DATA RECEIVED WHEN USING
   # THIS OPTION DOES NOT REPRESENT THE FULL DATA OF THE VCARD, SO DO NOT NOT NOT SEND
   # THE DATA TO BE WRITTEN - ONLY THE PARTIAL DATA YOU REQUESTED WILL BE WRITTEN!
   # Example: %only_return = ('FN' => '1', 'EMAIL' => '1');
   openwebmailerror(gettext('File does not exist:') . " $adrbookfile") unless -f $adrbookfile;

   return readvfile($adrbookfile, $r_searchtermshash, $r_onlyreturn);
}

sub writeadrbook {
   # TODO:
   # use maildb.pl type of thing to deal with addressbook files
   # We don't want to slurp the entire addressbook into memory.
   my ($addrfile, $r_adrbookhash, $version) = @_;

   my $writeoutput = outputvfile('vcard', $r_adrbookhash, $version);

   # write out the data
   print "\nTHE WRITEOUTPUT IS:\n\"$writeoutput\"";
}

sub convert_addressbook {
   # Read an old openwebmail proprietary addressbook format
   # and convert it into the new data structure for current use.
   # Note that there is no write routine for the old data format anymore.
   # This means that the data will be written back out to disk in
   # vCard format. This may break some third party scripts that rely
   # on the format being in the openwebmail proprietary format.
   my ($convertbook, $charset) = @_;
   $convertbook = 'user' if $convertbook eq '';

   my $converted         = gettext('Converted');
   my $oldadrbookfile    = '';
   my $newadrbookfile    = '';
   my $adrbookfilebackup = '';
   my $filemode          = 0600;

   if ($convertbook eq 'user') {
      my $webaddrdir  = dotpath('webaddr');

      $oldadrbookfile = dotpath('address.book');

      $newadrbookfile = "$webaddrdir/$converted";
      $newadrbookfile =~ s/[:@#$%^&*()!?|\\\[\]\/<>,`'+=\s]+$//; # no naughty filename

      $adrbookfilebackup = "$webaddrdir/.address.book.old";
      $filemode          = 0600; # read by owner only
   } elsif ($convertbook eq 'global') {
      $oldadrbookfile    = "$config{ow_etcdir}/address.book";
      $newadrbookfile    = "$config{ow_addressbooksdir}/$converted.global";
      $adrbookfilebackup = "$config{ow_addressbooksdir}/.address.book.global.old";
      $filemode          = 0644; # readable by others
   }

   return 0 if -z $oldadrbookfile || -f $newadrbookfile || -f $adrbookfilebackup;

   ow::filelock::lock($oldadrbookfile, LOCK_SH|LOCK_NB) or
      openwebmailerror(gettext('Cannot lock file:') . " $oldadrbookfile ($!)");

   sysopen(F, $oldadrbookfile, O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $oldadrbookfile ($!)");

   my $firstline = <F>;

   close(F) or
      openwebmailerror(gettext('Cannot close file:') . " $oldadrbookfile ($!)");

   ow::filelock::lock($oldadrbookfile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . " $oldadrbookfile ($!)");

   if (defined $firstline && $firstline =~ m/^BEGIN:VCARD/) {
      # oldadrbookfile is already in vcard format
      if ($oldadrbookfile ne $newadrbookfile) {
         rename($oldadrbookfile, $newadrbookfile) or
            openwebmailerror(gettext('Cannot rename file:') . " $oldadrbookfile -> $newadrbookfile ($!)");
         return 0;
      }
   }

   my $status = _convert_addressbook($oldadrbookfile, $newadrbookfile, $adrbookfilebackup, $charset, $filemode);

   return $status;
}

sub _convert_addressbook {
   my ($old, $new, $backup, $charset, $filemode) = @_;

   openwebmailerror(gettext('Backup file must be specified.'))
      if !defined $backup || $backup eq $old || $backup eq $new;

   return 0 if $old eq '' || ! -e $old; # no file to convert
   return 0 if -e $backup;              # was already run before so skip it

   my @entries = ();
   if (-s $old) { # file is not 0 bytes
      ow::filelock::lock($old, LOCK_EX|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . " $old ($!)");

      sysopen(ADRBOOK, $old, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $old ($!)");

      ow::filelock::lock($backup, LOCK_EX|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . " $backup ($!)");

      sysopen(ADRBOOKBACKUP, $backup, O_WRONLY|O_TRUNC|O_CREAT, $filemode) or
         openwebmailerror(gettext('Cannot open file:') . " $backup ($!)");

      my @chars = ( 'A' .. 'Z', 0 .. 9 );
      while (<ADRBOOK>) {
         print ADRBOOKBACKUP; # backup every line we process
         my ($name, $email, $note) = split(/\@\@\@/, $_, 3);
         adrbook_escape_chars($name, $email, $note);

         # X-OWM-ID
         my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
         $uid_year += 1900;
         $uid_mon  = sprintf('%02d', ($uid_mon + 1));
         $uid_mday = sprintf('%02d', $uid_mday);
         $uid_hour = sprintf('%02d', $uid_hour);
         $uid_min  = sprintf('%02d', $uid_min);
         $uid_sec  = sprintf('%02d', $uid_sec);

         my $longrandomstring  = join '', map { $chars[rand @chars] } 1..12;
         my $shortrandomstring = join '', map { $chars[rand @chars] } 1..4;

         my $x_owm_uid = $uid_year .
                         $uid_mon .
                         $uid_mday .
                         '-' .
                         $uid_hour .
                         $uid_min .
                         $uid_sec .
                         '-' .
                         $longrandomstring .
                         '-' .
                         $shortrandomstring;

         # REV
         my $rev = $uid_year . $uid_mon . $uid_mday . 'T' . $uid_hour . $uid_min . $uid_sec . 'Z';

         # Name MUST be defined
         $name = gettext('Name') if !defined $name || $name eq '' || $name =~ m/^\s+$/;

         # Start output
         my ($first, $mid, $last, $nick) = _parse_username($name);

         foreach ($first, $mid, $last, $nick) {
            $_ .= ' ' if $_ =~ m/\\$/; # chop off trailing slash that escaped comma char
         }

         push(@entries, qq|BEGIN:VCARD\r\n| .
                        qq|VERSION:3.0\r\n| .
                        qq|N:$last;$first;$mid;;\r\n|
             );
         push(@entries, "NICKNAME:$nick\r\n") if defined $nick && $nick ne '';

         # get all the emails
         my @emails = split(/,/, $email);
         foreach my $email (sort @emails) {
            $email =~ s/\\$//; # chop off trailing slash that escaped comma char
            push(@entries, "EMAIL:$email\r\n") if defined $email && $email ne '';
         }

         # how we handle distribution lists
         push(@entries, "X-OWM-GROUP:$name\r\n") if scalar @emails > 1;

         push(@entries, "NOTE:$note\r\n") if defined $note && $note ne '';
         push(@entries, qq|REV:$rev\r\n|.
                        qq|X-OWM-UID:$x_owm_uid\r\n|.
                        qq|END:VCARD\r\n\r\n|
             );
      }

      close(ADRBOOKBACKUP) or
         openwebmailerror(gettext('Cannot close file:') . " $backup ($!)");

      ow::filelock::lock($backup, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . " $backup ($!)");

      close(ADRBOOK) or
         openwebmailerror(gettext('Cannot close file:') . " $old ($!)");

      ow::filelock::lock($old, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . " $old ($!)");
   } else {
      # old addressbook is 0 bytes. Write an empty backup.
      ow::filelock::lock($backup, LOCK_EX|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . " $backup ($!)");

      sysopen(ADRBOOKBACKUP, $backup, O_WRONLY|O_TRUNC|O_CREAT, $filemode) or
         openwebmailerror(gettext('Cannot open file:') . " $backup ($!)");

      print ADRBOOKBACKUP @entries;

      close(ADRBOOKBACKUP) or
         openwebmailerror(gettext('Cannot close file:') . " $backup ($!)");

      ow::filelock::lock($backup, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . " $backup ($!)");
   }

   # write out the new converted addressbook
   ow::filelock::lock($new, LOCK_EX|LOCK_NB) or
      openwebmailerror(gettext('Cannot lock file:') . " $new ($!)");

   sysopen(ADRBOOKNEW, $new, O_WRONLY|O_TRUNC|O_CREAT, $filemode) or
      openwebmailerror(gettext('Cannot open file:') . " $new ($!)");

   print ADRBOOKNEW @entries;

   close(ADRBOOKNEW) or
      openwebmailerror(gettext('Cannot close file:') . " $new ($!)");

   ow::filelock::lock($new, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . " $new ($!)");

   writelog("convert addressbook - $old to vcard file $new");

   # remove the old book
   unlink($old) if $old ne $new;

   return 0;
}

sub adrbook_escape_chars {
   for (@_) {
      s#;#\\;#g;
      s#,#\\,#g;
      s#\s+$##;
      s#^\s+$##;
   }
}

sub _parse_username {
   # parse username, return (first, middle, last, nick)
   my $name = shift;
   $name =~ s/^\s+//;
   $name =~ s/\s+$//;

   my ($nick) = $name =~ s/\(\s*(.*)\s*\)//;                    # strip (...)
   $nick = '' unless defined $nick && $nick ne '';

   my @n = split(/\s+/, $name);
   if (scalar @n == 1) {
      my $len = length($name);
      if (
            (
               $len == 4                                        # chinese: LastFirst format
               || $len == 6
               || $len == 8
            )
            &&
            $name =~ m/^[\xA1-\xF9][\x40-\x7E\xA1-\xFE]/        # big5:[A1-F9][40-7E,A1-FE], gb2312:[A1-F9][A1-FE]
         ) {
         $name =~ m/^(..)(..)$/ || $name =~ /^(.*)(....)$/;
         return ($2, '', $1, $nick);
      } else {                                                  # First
         return ($name, '', '', $nick);
      }
   } elsif (scalar @n == 2) {
      if ($n[0] =~ /^(.+),/) {                                  # Last, First
         return ($n[1], '', $1, $nick);
      } else {                                                  # First Last
         return ($n[0], '', $n[1], $nick);
      }
   } elsif (scalar @n >= 3) {
      if ($name =~ m/(.+)\s+(st\.?|v[ao]n|d[aei]l?|d[ae]ll[ae])\s+(.+)/i) {
         my ($first, $last) = ($1, "$2 $3");
         if ($first=~/^(.+)\s+(\S+)$/) {                        # First Mid von Last
            return($1, $2, $last, $nick);
         } else {                                               # First von Last
            return($first, '', $last, $nick);
         }
      } else {                                                  # First ... Mid Last
         my $last = pop(@n);
         my $mid  = pop(@n);
         return(join(' ', @n), $mid, $last, $nick);
      }
   }
}

1;
