#!/usr/bin/perl
#
# this is used for debuging auth_pam.pl routines only...
#
use strict;
no strict 'vars';
push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");

sub log_time {
   print(join(" ", @_), "\n");
}

require "auth_pam.pl";

my ($user, $passwd, $newpasswd)=@ARGV;

if ($user eq "") {
   print "pamtest.pl [username] [oldpassword] [newpassword]\n";
}

$<=$>;

print "user=$user, pass=$passwd, newpass=$newpasswd\n";

print "check_userpassword ret=",
      check_userpassword($user, $passwd), 
      "\n";

print "\n\n";

print "change_userpassword ret=",
      change_userpassword($user, $passwd, $newpasswd), 
      "\n";

