# 
# auth_ldap.pl - authenticate user with LDAP
# 
# 2002/01/27 Ivan Cerrato - pengus@libero.it
#
# Based on auth_unix.pl written by tung@turtle.ee.ncku.edu.tw 
#

my $ldapHost = "HOSTNAME";	# INSERT THE LDAP SERVER IP HERE.
my $cn = "cn=LOGIN";		# INSERT THE LDAP USER HERE.
my $dc1 = "dc=DC1";		# INSERT THE FIRST DC HERE.
my $dc2 = "dc=DC2";		# INSERT THE SECOND DC HERE.
my $pwd = "PASSWORD";		# INSERT THE LDAP PASSWORD HERE.

################### No configuration required from here ###################

use Net::LDAP;

my $ldapBase = "$dc1, $dc2";
my $dn = "$cn, $dc1, $dc2";
my $ldap = Net::LDAP->new($ldapHost) or die "$@";

$ldap->bind ( dn        =>      $dn,
              password  =>      $pwd);

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $homedir);

   my $list = $ldap->search (
                             base    => $ldapBase,
                             filter  => "(&(objectClass=posixAccount)(uid=$user))",
                             attrs   => ['uidNumber','gidNumber','gecos','homeDirectory']
                             );

   if ($list->count eq 0) {
	return -1;
	}
   else {
	$entry = $list->entry(0);

        $uid = $entry->get_value("uidNumber");
        $gid = $entry->get_value("gidNumber");
        $gecos = $entry->get_value("gecos");
        $home = $entry->get_value("homeDirectory");

	return($gecos, $uid, $gid, $home);
	}
}

sub get_userlist {      # only used by checkmail.pl -a
   my @userlist=();

   my $list = $ldap->search (
                             base    => $ldapBase,
                             filter  => "(&(objectClass=posixAccount))",
                             attrs   => ['uid']
                             );

   my $num = $list->count;

   for ($i = 0; $i < $num; $i++) {
	my $entry = $list->entry($i);
	push (@userlist, $entry->get_value("uid"));
	}

   return (@userlist);
}

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect

sub check_userpassword {
   my ($user, $password)=@_;

   return -2 unless ( $user ne "" && $password ne "");

   my $list = $ldap->search (
                             base    => $ldapBase,
                             filter  => "(&(objectClass=posixAccount)(uid=$user))",
                             attrs   => ['userPassword']
                             );

   if ($list->count eq 0) {
        return -4;
        }
   else {
	my $entry = $list->entry(0);
	$tmp_pwd = $entry->get_value("userPassword");

	$c_pwd = substr($tmp_pwd, 7, 13);
	$salt = substr($c_pwd, 0, 2);

	if ($c_pwd eq crypt($password, $salt)) {
        	return 0;
		}
	else {
		return -4;
		}
        }   
}

#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect

sub change_userpassword {
   my ($user, $oldpassword, $newpassword)=@_;
   my ($u, $p, $misc, $encrypted);
   my $content="";
   my $line;

   return -2 unless ( $user ne "" && $oldpassword ne "" && $newpassword ne "" );
   return -2 if (length($newpassword)<4);

   my $test = &check_userpassword ($user, $oldpassword);
   return -4 unless $test eq 0;

   srand();
   my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
   my $salt=substr($table, int(rand(length($table))), 1).
            substr($table, int(rand(length($table))), 1);

   $encrypted = "{CRYPT}" . crypt($newpassword, $salt);

   my $mesg = $ldap->modify (
                             dn      =>      'uid=' . $user . ', ou=People, ' . $dc1 . ', ' . $dc2,
                             replace =>      {'userPassword'	=>	$encrypted}
                            );

   return 0;
}

1;
