#!/usr/bin/perl
#
# this is used for debuging aut_*pl modules under auth/
# change the module name to the one you want to test
#

# change the following path to your openwebmail cgi-bin directory
push (@INC, '/usr/local/www/cgi-bin/openwebmail');

use strict; no strict 'vars';
use vars qw (%config);
%config=( passwd_minlen => 1 );

my ($authfile, $user, $passwd, $newpasswd)=@ARGV;
if ($user eq "") {
   print "authtest.pl [authfile] [username] [oldpassword] [newpassword]\n".
         "eg1: authtest auth_unix.pl username pwd\n".
         "eg2: authtest auth_unix.pl username pwd1 pwd2\n";
   exit 1;
}

require "auth/auth.pl";
ow::auth::load($authfile);

my ($ret, $errmsg)=ow::auth::check_userpassword(\%config, $user, $passwd);
print "user=$user, pwd=$passwd, check pwd ret=$ret, err=$errmsg\n";

if ($newpasswd ne '') {
   ($ret, $errmsg)=ow::auth::change_userpassword(\%config, $user, $passwd, $newpasswd);
   print "user=$user, pwd=$passwd, newpwd=$newpasswd, change pwd ret=$ret, err=$errmsg\n";
}
