package ow::quota;
#
# quota.pl - parent package of all quota modules
#

use strict;
use warnings;

require "modules/suid.pl";
require "modules/tool.pl";

sub load {
   my $quotafile = shift;
   my $ow_cgidir = defined $main::SCRIPT_DIR ? $main::SCRIPT_DIR : $INC[$#INC];
   ow::tool::loadmodule(
                          'ow::quota::internal',
                          "$ow_cgidir/quota",
                          $quotafile,
                          'get_usage_limit'
                       );
}

sub get_usage_limit {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD};
   undef $SIG{CHLD};

   my ($origruid, $origeuid, $origegid) = ow::suid::set_uid_to_root();
   my @results = ow::quota::internal::get_usage_limit(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

   return @results;
}

1;
