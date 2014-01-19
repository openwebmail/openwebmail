
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

# filterbook.pl - read/write stationery book

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

use vars qw(%config);

sub sort_filterrules {
   # given a hash ref of filter rules, return them as a sorted array
   my $r_filterrules = shift;

   # filterrules prefered order, the smaller ones are prefered
   my %op_order = (
                     copy   => 0,
                     move   => 1,
                     delete => 2,
                  );

   my %ruletype_order = (
                           from        => 0,
                           to          => 1,
                           subject     => 2,
                           header      => 3,
                           smtprelay   => 4,
                           attfilename => 5,
                           textcontent => 6
                        );

   my %folder_order = (
                         # folders not listed have order 0
                         INBOX        => -1,
                         DELETE       => 1,
                         'virus-mail' => 2,
                         'spam-mail'  => 3,
                         'mail-trash' => 4
                      );

   return sort {
                  (defined $r_filterrules->{$a}{priority} ? $r_filterrules->{$a}{priority} : 9999)
                  <=>
                  (defined $r_filterrules->{$b}{priority} ? $r_filterrules->{$b}{priority} : 9999)

                  ||

                  (defined $op_order{$r_filterrules->{$a}{op}} ? $op_order{$r_filterrules->{$a}{op}} : 9999)
                  <=>
                  (defined $op_order{$r_filterrules->{$b}{op}} ? $op_order{$r_filterrules->{$b}{op}} : 9999)

                  ||

                  (defined $ruletype_order{$r_filterrules->{$a}{type}} ? $ruletype_order{$r_filterrules->{$a}{type}} : 9999)
                  <=>
                  (defined $ruletype_order{$r_filterrules->{$b}{type}} ? $ruletype_order{$r_filterrules->{$b}{type}} : 9999)

                  ||

                  (defined $folder_order{$r_filterrules->{$a}{dest}} ? $folder_order{$r_filterrules->{$a}{dest}} : 9999)
                  <=>
                  (defined $folder_order{$r_filterrules->{$b}{dest}} ? $folder_order{$r_filterrules->{$b}{dest}} : 9999)
               } keys %{$r_filterrules};
}

sub read_filterbook {
   my ($filterbookfile, $r_filterrules) = @_;

   if (-f $filterbookfile) {
      sysopen(FILTER, $filterbookfile, O_RDONLY) or
         return (-1, gettext('Cannot open file:') .  " $filterbookfile ($!)");

      while (my $line = <FILTER>) {
         chomp $line;
         if ($line =~ m/^\d+\@\@\@/) {
            # add valid rule only
            my %rule = ();
            @rule{'priority', 'type', 'inc', 'text', 'op', 'dest', 'enable', 'charset'} = split(/\@\@\@/, $line);
            $rule{dest} = safefoldername($rule{dest});

            next if (!is_defaultfolder($rule{dest}) && !$config{enable_userfolders});

            my $key = (iconv($rule{charset}, $prefs{charset}, join('@@@', @rule{'type', 'inc', 'text', 'dest'})))[0];
            $r_filterrules->{$key} = \%rule;
         }
      }

      close(FILTER) or
         return(-2, gettext('Cannot close file:') . " $filterbookfile ($!)");
   }

   return (0, '');
}

sub write_filterbook {
   my ($filterbookfile, $r_filterrules) = @_;

   my @sortedrules = sort_filterrules($r_filterrules);

   sysopen(FILTER, $filterbookfile, O_WRONLY|O_TRUNC|O_CREAT) or
      return (-1, gettext('Cannot open file:') . " $filterbookfile ($!)");

   foreach my $rule (@sortedrules) {
      my %rule = %{$r_filterrules->{$rule}};
      print FILTER join('@@@', $rule{priority},
                               $rule{type},
                               $rule{inc},
                               $rule{text},
                               $rule{op},
                               $rule{dest},
                               $rule{enable},
                               $rule{charset}
                       ) . "\n";
   }

   close(FILTER) or
      return(-2, gettext('Cannot close file:') . " $filterbookfile ($!)");

   return (0, '');
}

1;
