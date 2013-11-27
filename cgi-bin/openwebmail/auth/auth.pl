package ow::auth;
#
# auth.pl - parent package of all auth modules
#

use strict;
use warnings FATAL => 'all';

require "modules/suid.pl";
require "modules/tool.pl";

sub load {
   my $authfile  = shift;
   my $ow_cgidir = defined $main::SCRIPT_DIR ? $main::SCRIPT_DIR : $INC[$#INC];
   ow::tool::loadmodule(
                          'ow::auth::internal',
                          "$ow_cgidir/auth",
                          $authfile,
                          'get_userinfo',
                          'get_userlist',
                          'check_userpassword',
                          'change_userpassword'
                       );
}

sub get_userlist {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::get_userlist(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

sub get_userinfo {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::get_userinfo(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

sub check_userpassword {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::check_userpassword(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

sub change_userpassword {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::change_userpassword(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

1;
