#!/usr/bin/perl -w

# This script is intended to be run from a cron job.

# This script indexes MHonArc directories using Namazu's mknmz
# utility. It's run from cron, so be careful what changes you make here!

$|++;
use strict;

use vars qw($global);

# configuration
$global->{mboxarchiveroot} = "/usr/local/majordomo/lists/openwebmail.acatysmoof.com";
$global->{wwwarchiveroot} = "/home/alex/openwebmail.acatysmoof.com/archive";

my $update = -e "$global->{wwwarchiveroot}/search/NMZ.i"?"--update=$global->{wwwarchiveroot}/search":'';

# index the archive for searching
# print "/usr/local/bin/mknmz --quiet --mhonarc --check-filesize $update --output-dir=$global->{wwwarchiveroot}/search --template-dir=$global->{wwwarchiveroot}/search/templates $global->{wwwarchiveroot}/html\n";

system("/usr/local/bin/mknmz --quiet --mhonarc --check-filesize $update --output-dir=$global->{wwwarchiveroot}/search --template-dir=$global->{wwwarchiveroot}/search/templates $global->{wwwarchiveroot}/html") == 0 or die("mknmz failed: $? $! $@\n");


