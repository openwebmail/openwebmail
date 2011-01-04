
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

# calbook.pl - read and write calendar books

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);

require "shares/ow-shared.pl"; # openwebmailerror and gettext support

sub readcalbook {
   # read the user calendar and put the records into 2 hashes.

   # %items:
   # The keys are the index numbers of the items.
   # The value of each key is a hashref of this item's fields.

   # %indexes:
   # The keys are an idate string, number, or regex.
   # The value of each key is an arrayref of the indexes that belong to this idate.

   # $indexshift:
   # This is used to shift the index number so records in multiple calendars won't collide
   my ($calbook, $r_items, $r_indexes, $indexshift) = @_;

   my $item_count = 0;

   return $item_count unless -f $calbook;

   sysopen(CALBOOK, $calbook, O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $calbook ($!)");

   while (<CALBOOK>) {
      # skip blanks and comments
      next if m/^#/ || m/^\s*$/;

      chomp;

      my @a     = split(/\@{3}/, $_);
      my $index = $a[0] + $indexshift;

      $a[9] = 1 if !defined $a[9] || $a[9] eq '';

      $r_items->{$index} = {
                              idate         => $a[1],
                              starthourmin  => $a[2],
                              endhourmin    => $a[3],
                              string        => $a[4],
                              link          => $a[5],
                              email         => $a[6],
                              eventcolor    => $a[7] || 'none',
                              charset       => $a[8] || '',
                              eventreminder => $a[9],
                           };

      my $idate = $a[1];
      $idate = '*' if $idate =~ m/[^\d]/; # use '*' for regex date

      $r_indexes->{$idate} = [] unless exists $r_indexes->{$idate};

      push(@{$r_indexes->{$idate}}, $index);

      $item_count++;
   }

   close(CALBOOK) or
      openwebmailerror(gettext('Cannot close file:') . " $calbook ($!)");

   return $item_count;
}

sub writecalbook {
   my ($calbook, $r_items) = @_;

   my @indexlist = sort {
                          $r_items->{$a}{idate} cmp $r_items->{$b}{idate}
                          || $r_items->{$a}{string} cmp $r_items->{$b}{string}
                        } keys %{$r_items};

   $calbook = ow::tool::untaint($calbook);

   if (! -f $calbook) {
      # create the calbook file
      sysopen(CALBOOK, $calbook, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $calbook ($!)");

      close(CALBOOK) or
         openwebmailerror(gettext('Cannot close file:') . " $calbook ($!)");
   }

   ow::filelock::lock($calbook, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . " $calbook ($!)");

   sysopen(CALBOOK, $calbook, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . " $calbook ($!)");

   my $written = 0;
   foreach my $eventid (@indexlist) {
      print CALBOOK join('@@@',
                           $eventid,
                           $r_items->{$eventid}{idate},
                           $r_items->{$eventid}{starthourmin},
                           $r_items->{$eventid}{endhourmin},
                           $r_items->{$eventid}{string},
                           $r_items->{$eventid}{link},
                           $r_items->{$eventid}{email},
                           $r_items->{$eventid}{eventcolor} || 'none',
                           $r_items->{$eventid}{charset} || '',
                           $r_items->{$eventid}{eventreminder}
                        ) . "\n";
      $written++;
   }

   close(CALBOOK) or
      openwebmailerror(gettext('Cannot close file:') . " $calbook ($!)");

   ow::filelock::lock($calbook, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . " $calbook ($!)");

   return $written;
}

1;
