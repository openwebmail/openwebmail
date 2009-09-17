#!/usr/bin/perl

# parses a virtusertable text file and outputs the result:
# a mapping of virtual addresses to real addresses
# the reverse mapping of real addresses to virtual addresses

# virtusertable files are usually located in /etc/mail
# and are part of sendmail

use strict;
use warnings;
use Fcntl qw(:DEFAULT :flock);
use Data::Dumper;
$Data::Dumper::Sortkeys++;

die "First arg should be the virtusertable to parse" unless $ARGV[0];

my %DB = ();
my %DBR = ();

my $loginuser = 'alex';

   sysopen(VIRT, $ARGV[0], O_RDONLY);
   while (<VIRT>) {
      s/^\s+//; # remove leading whitespace
      s/\s+$//; # remove trailing whitespace
      s/#.*$//; # remove trailing comments and comment lines

      my ($virtual_address, $real_address) = split(/\s+/);

      next unless defined $virtual_address && $virtual_address ne '';
      next unless defined $real_address && $real_address ne '' && $real_address !~ m/^\s*error:/;

      print "line: " . __LINE__ . ", va: $virtual_address ra: $real_address\n";

      my ($virtual_localpart, $virtual_domain) = split(/\@/,$virtual_address);

      print "line: " . __LINE__ . ", val: $virtual_localpart vad: $virtual_domain\n";

      # replace real address substitution placeholders such as %1
      if ($real_address =~ m/\%1/) {
         print "line: " . __LINE__ . ", ra: $real_address\n";
         if (defined $virtual_localpart && $virtual_localpart ne '') {
            $real_address =~ s/\%1/$virtual_localpart/g;
         print "line: " . __LINE__ . ", ra: $real_address\n";
         } else {
            $real_address =~ s/\%1/$loginuser/g;
            $virtual_address = "$loginuser\@$virtual_domain";
         print "line: " . __LINE__ . ", ra: $real_address\n";
         }
      }

      # add to the virtdb
      $DB{$virtual_address} = $real_address;

      # add to the reverse virtdb
      $DBR{$real_address} .= defined $DBR{$real_address} ? ",$virtual_address" : $virtual_address;

      print "\n\n";
   }
   close(VIRT);

   print Dumper(\%DB, \%DBR);


