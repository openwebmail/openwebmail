
#                              The BSD License
#
#  Copyright (c) 2009-2013, The OpenWebMail Project
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

# auth_ldap.pl - authenticate user with LDAP

package ow::auth_ldap;

use strict;
use warnings FATAL => 'all';

use Net::LDAP;

require "modules/tool.pl";

my %conf = ();
if (($_ = ow::tool::find_configfile('etc/auth_ldap.conf', 'etc/defaults/auth_ldap.conf')) ne '') {
   my ($ret, $err) = ow::tool::load_configfile($_, \%conf);
   die $err if $ret < 0;
} else {
   die "Config file auth_ldap.conf not found!";
}

my $ldapHost = $conf{ldaphost} || '';
my $ou  = exists $conf{ou}  && defined $conf{ou}  ? "ou=$conf{ou}"  : 'ou=';
my $cn  = exists $conf{cn}  && defined $conf{cn}  ? "cn=$conf{cn}"  : 'cn=';
my $dc1 = exists $conf{dc1} && defined $conf{dc1} ? "dc=$conf{dc1}" : 'dc=';
my $dc2 = exists $conf{dc2} && defined $conf{dc2} ? "dc=$conf{dc2}" : 'dc=';
my $pwd = $conf{password};

my $ldapBase = "$dc1, $dc2";

sub get_userinfo {
   #  0 : ok
   # -2 : parameter format error
   # -3 : authentication system/internal error
   # -4 : user doesn't exist
   my ($r_config, $user) = @_;

   return(-2, 'User is null') if !defined $user || $user eq '';

   my $ldap = Net::LDAP->new($ldapHost) or return(-3, "LDAP error $@");

   $ldap->bind(dn=>"$cn, $dc1, $dc2", password =>$pwd) or  return(-3, "LDAP error $@");

   my $list = $ldap->search(
                              base    => $ldapBase,
                              filter  => "(&(objectClass=posixAccount)(uid=$user))",
                              attrs   => ['uidNumber','gidNumber','gecos','homeDirectory']
                           ) or return(-3, "LDAP error $@");

   undef($ldap); # disconnect

   if ($list->count eq 0) {
      return (-4, "User $user does not exist");
   } else {
      my $entry   = $list->entry(0);
      my $uid     = $entry->get_value('uidNumber')     || '';
      my $gid     = $entry->get_value('gidNumber')     || '';
      my $gecos   = $entry->get_value('gecos')         || '';
      my $homedir = $entry->get_value('homeDirectory') || '';

      return(0, '', $gecos, $uid, $gid, $homedir);
   }
}

sub get_userlist {
   # only used by openwebmail-tool.pl -a
   #  0 : ok
   # -1 : function not supported
   # -3 : authentication system/internal error
   my $r_config = shift;

   my $ldap = Net::LDAP->new($ldapHost) or return(-3, "LDAP error $@");

   $ldap->bind(dn=>"$cn, $dc1, $dc2", password =>$pwd) or  return(-3, "LDAP error $@");

   my $list = $ldap->search(
                              base    => $ldapBase,
                              filter  => "(&(objectClass=posixAccount))",
                              attrs   => ['uid']
                           ) or return(-3, "LDAP error $@");

   undef($ldap); # disconnect

   my $num = $list->count;

   my @userlist=();

   for (my $i = 0; $i < $num; $i++) {
      my $entry = $list->entry($i);
      push(@userlist, ($entry->get_value('uid') || ''));
   }

   return (0, '', @userlist);
}

sub check_userpassword {
   #  0 : ok
   # -2 : parameter format error
   # -3 : authentication system/internal error
   # -4 : password incorrect
   my ($r_config, $user, $password) = @_;

   return (-2, 'User or password is null')
      if !defined $user || $user eq '' || !defined $password || $password eq '';

   my $ldap = Net::LDAP->new($ldapHost) or return(-3, "LDAP error $@");
   # $ldap->bind (dn=>"$cn, $dc1, $dc2", password =>$pwd) or  return(-3, "LDAP error $@");

   # Attempt to bind using the username and password provided.
   # (For a secure LDAP config, only auth should be allowed for
   # any user other than self and rootdn.)
   my $mesg = $ldap->bind(
                            dn       => "uid=$user, $ou, $dc1, $dc2",
                            password => $password
                         );

   undef($ldap); # disconnect

   return (-4, 'username/password incorrect') if $mesg->code != 0;

   return (0, '');
}

sub change_userpassword {
   #  0 : ok
   # -1 : function not supported
   # -2 : parameter format error
   # -3 : authentication system/internal error
   # -4 : password incorrect
   my ($r_config, $user, $oldpassword, $newpassword) = @_;

   return (-2, 'User or password is null')
      if !defined $user
         || $user eq ''
         || !defined $oldpassword
         ||  $oldpassword eq ''
         || !defined $newpassword
         || $newpassword eq '';

   return (-2, "Password too short") if length($newpassword) < $r_config->{passwd_minlen};

   my ($ret, $errmsg) = check_userpassword($r_config, $user, $oldpassword);

   return($ret, $errmsg) if $ret != 0;

   my @salt_chars = ('a'..'z','A'..'Z','0'..'9');
   my $salt = $salt_chars[rand(62)] . $salt_chars[rand(62)];
   my $encrypted = "{CRYPT}" . crypt($newpassword, $salt);

   my $ldap = Net::LDAP->new($ldapHost) or return(-3, "LDAP error $@");
   $ldap->bind(dn=>"$cn, $dc1, $dc2", password =>$pwd) or return(-3, "LDAP error $@");

   my $mesg = $ldap->modify(
                              dn      => "uid=$user, $ou, $dc1, $dc2",
                              replace => {'userPassword'=>$encrypted}
                           );

   undef($ldap); # disconnect

   return (0, '');
}

1;
