package ow::suid;
use strict;
#
# suid.pl - set ruid/euid/egid of process
#

########## No configuration required from here ###################

require "modules/tool.pl";

my %conf;
if (($_=ow::tool::find_configfile('etc/suid.conf', 'etc/defaults/suid.conf')) ne '') {
   my ($ret, $err)=ow::tool::load_configfile($_, \%conf);
   die $err if ($ret<0);
}
my $has_savedsuid_support = $conf{'has_savedsuid_support'} || 'no';

########## end init ##############################################

# openwebmail drop euid root after user has been authenticated
# this routine save root to ruid in case system doesn't support saved-euid
# so we can give up euid root temporarily and get it back later.
sub set_euid_egids {
   my ($euid, @egids)=@_;
   # trick: 2nd parm will be ignore, so we repeat parm 1 twice
   $) = join(" ", $egids[0], @egids);
   if ($> != $euid) {
      $<=$> if ($has_savedsuid_support ne 'yes' && $>==0);
      $> = $euid;
   }
   return;
}

# the following two are used to switch euid/euid back to root temporarily
# when user has been authenticated
sub set_uid_to_root {
   my ($origruid, $origeuid, $origegid)=( $<, $>, $) );
   $> = 0; 	# first set the user to root
   $) = 0; 	# set effective group to root
   $< = $>;	# set real user to root,
                # since 1. some cmds checks ruid even euid is already root
                #       2. some shells(eg:bash) switch euid back to ruid before execution
   return ($origruid, $origeuid, $origegid);
}

sub restore_uid_from_root {
   my ($ruid, $euid, $egid)=@_;
   $) = $egid;
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
   $>=0; $(=$); $<=$euid; $>=$euid;
   return
}

1;
