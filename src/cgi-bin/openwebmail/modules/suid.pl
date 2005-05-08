package ow::suid;
#
# suid.pl - set ruid/euid/egid of process
#

########## No configuration required from here ###################

use strict;
require "modules/tool.pl";

my %conf;
if (($_=ow::tool::find_configfile('etc/suid.conf', 'etc/defaults/suid.conf')) ne '') {
   my ($ret, $err)=ow::tool::load_configfile($_, \%conf);
   die $err if ($ret<0);
}
my $has_savedsuid_support = $conf{'has_savedsuid_support'} || 'no';

########## end init ##############################################
# turn gid string notation into numbers
# remove duplicated numbers, and try to conver euid arg1 bug
sub gidarray2array {
   my (@gids, %found);
   foreach my $gidstr (@_) {
      foreach my $gid (split(/\s+/, $gidstr)) {
         next if (defined $found{$gid} || $gid eq '');
         push(@gids, $gid); $found{$gid}=1;
      }
   }
   # when we use $)=@gids to set $), the $gids[1] arg will be ignored,
   # so we repeat $gids[0] as $gids[1] in return value
   # to conver this strange behavior, tricky!
   return($gids[0], @gids);
}

# openwebmail drop euid root after user has been authenticated
# this routine save root to ruid in case system doesn't support saved-euid
# so we can give up euid root temporarily and get it back later.
sub set_euid_egids {
   my ($euid, @egids)=@_;
   @egids=gidarray2array(@egids);

   $) = join(" ",@egids);	# set EGID
   $( = $egids[0];		# set RGID
   if ($> != $euid) {
      # set RUID
      if ($has_savedsuid_support ne 'yes') {
         $< = 0 if ($>==0);	# keep euid0 in ruid before drop euid0
      } else {
         $< = $euid;		# switch to new euid
      }
      $> = $euid;		# set EUID
   }
   return;
}

# the following two are used to switch euid/euid back to root temporarily
# when user has been authenticated
sub set_uid_to_root {
   my ($origruid, $origeuid, $origegid)=( $<, $>, $) );
   $> = 0; 	# first set the user to root
   $) = "0 0"; 	# set effective group to root
   $< = $>;	# set real user to root,
                # since 1. some cmds checks ruid even euid is already root
                #       2. some shells(eg:bash) switch euid back to ruid before execution
   return ($origruid, $origeuid, $origegid);
}

sub restore_uid_from_root {
   my ($ruid, $euid, $egid)=@_;
   $) = join(" ", gidarray2array($egid));
   $< = $ruid;
   $> = $euid;
   return;
}

# drop ruid/rgid by setting ruid=euid, rgid=egid, to guarentee process
# forked later will have ruid=euid=current euid
#
# on system without savedsuid support (which store 0 in ruid),
# drop ruid 0 will lose root privilege forever,
# so this routine is used in 'forked then die' process only in openwebmail,
# or owm won't get root back in persistence mode
#
# ps: perl process will invoke shell to execute commands in the following cases
#     a. open with pipe |
#     b. command within ``
#     c. command passed to system() or exec() as a whole string
#        and the string has shell escape char in it
#
#     When bash is started and parent ruid!=0,
#     it will have ruid=parent ruid, euid=parnet ruid (for security reason, I guess)
#     instead of ruid=parnet ruid, euid=parent euid
#
#     So the command executed by shell may have different euid than perl process
#
sub drop_ruid_rgid {
   my $euid=$>;
   my @egids=gidarray2array($));
   $>=0; $(=$egids[0]; $<=$euid; $>=$euid;
   return
}

1;
