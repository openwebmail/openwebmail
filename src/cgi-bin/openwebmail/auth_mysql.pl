# 
# auth_mysql.pl - authenticate user with MySQL
# 
# 2002/03/07 Alan Sung - AlanSung@dragon2.net
#
my $MySQLHost = "dragon2.net";	# INSERT THE MYSQL SERVER IP HERE.
my $sqlusr = "";		# INSERT THE MYSQL USER HERE.
my $sqlpwd = "";		# INSERT THE MYSQL PASSWORD HERE.

my $auth_db = "auth_db";
my $auth_table = "auth_user";
my $field_username = "username";
my $field_password = "password";
my $field_realname = "realname";
my $field_uid = "u_id";
my $field_gid = "g_id";
my $field_home = "home";

################### No configuration required from here ###################

use DBI;

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $home);

   my $dbh = DBI->connect("dbi:mysql:$auth_db;host=$MySQLHost", $sqlusr,$sqlpwd)
      or die "Cannot connect to db server: ", $DBI::errstr, "\n";
   my $queryStr =qq|select $field_uid, $field_gid, $field_realname, $field_home from $auth_table where $field_username="$user"|;
   my $sth = $dbh->prepare($queryStr)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
   $sth->execute
      or die "Can't execute SQL statement: ", $sth->errstr(), "\n";

   if ($sth->rows eq 0) {
      $sth->finish;
      $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
      return -1;
   } else {
      if (my $result = $sth->fetchrow_hashref()) {
         $sth->finish;
         $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
	 return($result->{$field_realname}, $result->{$field_uid}, $result->{$field_gid}, $result->{$field_home});
      }
   }
}


# Not Yet Implement for MySQL
sub get_userlist {      # only used by checkmail.pl -a
   my @userlist=();

   my $dbh = DBI->connect("dbi:mysql:$auth_db;host=$MySQLHost", $sqlusr,$sqlpwd)
      or die "Cannot connect to db server: ", $DBI::errstr, "\n";
   my $queryStr = qq|select $field_username from $auth_table|;
   my $sth = $dbh->prepare($queryStr)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
   $sth->execute
      or die "Can't execute SQL statement: ", $sth->errstr(), "\n";

   my @data;
   while (@data = $sth->fetchrow_array()) {	# only 1 field here
      push (@userlist, $data[0]);
   }
   $sth->finish;
   $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";

   return(@userlist)
}


#  0 : ok
# -1 : username incorrect
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($user, $password)=@_;

   return -2 unless ( $user ne "" && $password ne "");

   my $dbh = DBI->connect("dbi:mysql:$auth_db;host=$MySQLHost", $sqlusr,$sqlpwd)
      or die "Cannot connect to db server: ", $DBI::errstr, "\n";
   my $queryStr = qq|select $field_username, $field_password from $auth_table where $field_username="$user"|;
   my $sth = $dbh->prepare($queryStr)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
   $sth->execute
      or die "Can't execute SQL statement: ", $sth->errstr(), "\n";

   if ($sth->rows eq 0) {
      $sth->finish;
      $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
      return -1;
   } else {
      if (my $result = $sth->fetchrow_hashref()) {
         $sth->finish;
         $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
	 my $tmp_pwd = $result->{$field_password};
	 if ($tmp_pwd ne $password) {
	    return -4;
	 } else {
	    return 0;
	 }
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

   my $dbh = DBI->connect("dbi:mysql:$auth_db;host=$MySQLHost", $sqlusr,$sqlpwd)
      or die "Cannot connect to db server: ", $DBI::errstr, "\n";
   my $queryStr = qq|update $auth_table set $field_password="$newpassword" where $field_username="$user"|;
   my $sth = $dbh->prepare($queryStr)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
   $sth->execute
      or die "Can't execute SQL statement: ", $sth->errstr(), "\n";
   $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";

   return 0;
}

1;
