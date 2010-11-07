package ow::auth;
#
# auth.pl - parent package of all auth modules
#

use strict;
require "modules/suid.pl";
require "modules/tool.pl";

sub load {
   my $authfile=$_[0];
   my $ow_cgidir=$INC[$#INC];	# get cgi-bin/openwebmail path from @INC
   loadmodule("ow::auth::internal",
              "$ow_cgidir/auth", $authfile,
              "get_userinfo",
              "get_userlist",
              "check_userpassword",
              "change_userpassword");
}

# use 'require' to load the package ow::$file
# then alias ow::$file::symbol to $newpkg::symbol
# through Glob and 'tricky' symbolic reference feature
sub loadmodule {
   my ($newpkg, $moduledir, $modulefile, @symlist)=@_;
   $modulefile=~s|/||g; $modulefile=~s|\.\.||g; # remove / and .. for path safety

   # this would be done only once because of %INC
   my $modulepath=ow::tool::untaint("$moduledir/$modulefile");
   require $modulepath;

   # . - is not allowed for package name
   my $modulepkg='ow::'.$modulefile;
   $modulepkg=~s/\.pl//;
   $modulepkg=~s/[\.\-]/_/g;

   # release strict refs until block end
   no strict 'refs';
   # use symbol table of package $modulepkg if no symbol passed in
   @symlist=keys %{$modulepkg.'::'} if ($#symlist<0);

   foreach my $sym (@symlist) {
      # alias symbol of sub routine into current package
      *{$newpkg.'::'.$sym}=*{$modulepkg.'::'.$sym};
   }

   return;
}

sub get_userlist {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD}; undef $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::get_userlist(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

sub get_userinfo {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD}; undef $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::get_userinfo(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

sub check_userpassword {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD}; undef $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::check_userpassword(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

sub change_userpassword {
   # disable $SIG{CHLD} temporarily in case module routine calls system()/wait()
   local $SIG{CHLD}; undef $SIG{CHLD};

   my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
   my @results=ow::auth::internal::change_userpassword(@_);
   ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   return @results;
}

1;
