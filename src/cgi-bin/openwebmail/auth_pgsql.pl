#
# auth_pg.pl - authenticate user with DBD::Pg
#
# 2002/05/08 Oliver Smith - oliver@kfs.org
# 2002/03/07 Alan Sung - AlanSung@dragon2.net (orig: auth_mysql.pl)
#

my $SQLHost = "localhost";	# INSERT THE PGSQL SERVER IP HERE.
my $sqlusr = "openwebmail";	# INSERT THE PGSQL USER HERE.
my $sqlpwd = "openwebpass";	# INSERT THE PGSQL PASSWORD HERE.

my $auth_db = "db_auth";
my $auth_table = "t_users";
my $field_username = "name";
my $field_password = "passwd";
my $field_realname = "gecos";
my $field_uid = "uid";
my $field_gid = "gid";
my $field_home = "homedir";

my $pass_type	= "cleartxt"; 		# crypt, cleartxt

################### No configuration required from here ###################

use strict;
use DBI;

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $home);

   my $dbh = DBI->connect("dbi:Pg:dbname=$auth_db;host=$SQLHost", $sqlusr, $sqlpwd)
      or die "Cannot connect to db server: ", $DBI::errstr, "\n";
   my $queryStr =qq|select $field_uid, $field_gid, $field_realname, $field_home from $auth_table where $field_username='$user'|;
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


sub get_userlist {      # only used by openwebmail-tool.pl -a
   my @userlist=();

   my $dbh = DBI->connect("dbi:Pg:dbname=$auth_db;host=$SQLHost", $sqlusr,$sqlpwd)
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

   my $dbh = DBI->connect("dbi:Pg:dbname=$auth_db;host=$SQLHost", $sqlusr,$sqlpwd)
      or die "Cannot connect to db server: ", $DBI::errstr, "\n";
   my $queryStr = qq|select $field_username, $field_password from $auth_table where $field_username='$user'|;
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
         if ($pass_type eq "cleartxt") {
	    if ($tmp_pwd eq $password) {
	       return 0;
	    } else {
	       return -4;
	    }
         } elsif ($pass_type eq "crypt") {
	    if ($tmp_pwd eq crypt($password, $tmp_pwd)) {
               return 0;
	    } else {
	       return -4;
	    }
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

   if ($pass_type eq "crypt") { # encrypt the passwd
      srand();
      my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
      my $salt=substr($table, int(rand(length($table))), 1).
               substr($table, int(rand(length($table))), 1);
      $newpassword = crypt($newpassword, $salt);
   }

   my $dbh = DBI->connect("dbi:Pg:dbname=$auth_db;host=$SQLHost", $sqlusr,$sqlpwd)
      or die "Cannot connect to db server: ", $DBI::errstr, "\n";
   my $queryStr = qq|update $auth_table set $field_password='$newpassword' where $field_username='$user'|;
   my $sth = $dbh->prepare($queryStr)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
   $sth->execute
      or die "Can't execute SQL statement: ", $sth->errstr(), "\n";
   $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";

   return 0;
}

1;

