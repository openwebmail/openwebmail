package openwebmail::auth_mysql_vmail;
use strict;
#
# auth_mysql_vmail.pl - authenticate user with MySQL, where required fields
#                       are in more tables (like in vmail-sql).
# v1.5
# 2002/04/23 Zoltan Kovacs, werdy.AT.freemail.hu
#

#
# The sample config made for vmail-sql.
#
# This is the table which holds information about domains in vmail-sql (got from vmail-sql's README).
# CREATE TABLE domain (
#         domain_name VARCHAR(255) PRIMARY KEY,   # domain name
#         unix_user VARCHAR(255),                 # which Unix user owns files etc.
#         password_hash VARCHAR(255),             # admin password for this domain
#         path VARCHAR(255),                      # base path for this domain
#         max_popbox INT                          # maximum number of popboxes in this domain
# ) ;
#
# This is the table which holds user's informations in vmail-sql (got from vmail-sql's README).
# CREATE TABLE popbox (
#         domain_name VARCHAR(255) not null,      # domain this refers to
#         local_part VARCHAR(255) not null,       # username for this POP box
#         password_hash VARCHAR(255),             # hash of this user's password
#         mbox_name VARCHAR(255),                 # appended to domain.path
#         PRIMARY KEY (domain_name(16), local_part(32));
# ) ;
#

########################
# MySQL access options #
########################
my %mysql_auth=(
   mysql_server         => "localhost",	# MySQL server
   mysql_database       => "vmail",	# MySQL database
   mysql_user           => "",		# MySQL username
   mysql_passwd         => "",		# MySQL password
   password_hash_method => "MD5"	# supported methods: md5 and plaintext
);

#################
# MySQL queries #
#################
#userlist:        sql cmd to get user's list ###
#user_password:   sql cmd to get user's password (you can use _user_ and _domain_ variables)
#user_homedir:    sql cmd to get user's home directory (you can use _user_ and _domain_ variables)
#unix_user:       sql cmd to get real unix user (you can use _user_ and _domain_ variables)
#chnage_password: sql cmd to change user's password (you can use _user_, _domain_ and _new_password_ variables)
my %mysql_query=(
   userlist        => "SELECT local_part FROM popbox ORDER BY local_part",
   user_password   => "SELECT password_hash FROM popbox WHERE local_part='_user_' AND domain_name='_domain_'",
   user_homedir    => "",
   unix_user       => "SELECT domain.unix_user FROM domain LEFT JOIN popbox ON domain.domain_name=popbox.domain_name WHERE popbox.mbox_name='_user_' AND popbox.domain_name='_domain_'",
   change_password => "UPDATE popbox SET password_hash='_new_password_' WHERE local_part='_user_' AND domain_name='_domain_'"
);

################### No configuration required from here ###################

use DBI;
use Digest::MD5;

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : user doesn't exist
sub get_userinfo {
   my ($r_config, $user)=@_;
   my ( $unix_user, $gid, $uid, $home, $key, $domain );

   return(-2, 'User is null') if (!$user);
   if ( $user =~ /^(.*)\@(.*)$/ ) {
      ($user, $domain) = ($1, $2);
   }

   mysql_command("USE $mysql_auth{mysql_database}")==0 or
      return(-3, "MySQL connect error");

   my $q;
   if ( $mysql_query{user_homedir} ) {
      $q=$mysql_query{user_homedir};
      $q=~s/_user_/$user/g; $q=~s/_domain_/$domain/g;
      ( $home ) = mysql_command($q);
   }
   $q=$mysql_query{unix_user};
   $q=~s/_user_/$user/g; $q=~s/_domain_/$domain/g;
   ( $unix_user ) = mysql_command($q);

   mysql_command("EXIT")==0 or
      return(-3, "MySQL disconnect error");

   ( $uid, $gid ) = ( getpwnam($unix_user) )[2,3];
   return (-4, "User $user doesn't exist") if ( !$unix_user || !$uid || !$gid );

   return (0, '', "",$uid,$gid,$home);
}

#  0 : ok
# -1 : function not supported
# -3 : authentication system/internal error
sub get_userlist { # only used by openwebmail-tool.pl -a
   my $r_config=$_[0];
   my @userlist;

   mysql_command("USE $mysql_auth{mysql_database}")==0 or
      return(-3, "MySQL connect error");

   @userlist = &mysql_command( $mysql_query{userlist} );

   mysql_command("EXIT")==0 or
      return(-3, "MySQL disconnect error");

   return (0, '', @userlist);
}

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($r_config, $user, $passwd)=@_;
   return (-2, "User or password is null") if (!$user||!$passwd);

   my ( $passwd_hash, $domain );
   if ( $user =~ /^(.*)\@(.*)$/ ) { ($user,$domain) = ($1,$2); }

   mysql_command("USE $mysql_auth{mysql_database}")==0 or
      return(-3, "MySQL connect error");

   my $q=$mysql_query{user_password};
   $q=~s/_user_/$user/g; $q=~s/_domain_/$domain/g;
   ( $passwd_hash ) = &mysql_command($q);

   mysql_command("EXIT")==0 or
      return(-3, "MySQL disconnect error");

   if ( $mysql_auth{password_hash_method} =~ /plaintext/i ) {
      return (0,'') if ( $passwd_hash eq $passwd );
   } elsif ( $mysql_auth{password_hash_method} =~ /md5/i ) {
      $passwd_hash =~ s/^\{.*\}(.*)$/$1/;
      return (0, '') if ( $passwd_hash eq Digest::MD5::md5_hex($passwd) );
   }

   return (-4, 'username/password incorrect');
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
   my ($r_config, $user, $oldpasswd, $newpasswd)=@_;
   return (-2, "User or password is null") if (!$user||!$oldpasswd||!$newpasswd);
   return (-2, "Password too short") if (length($newpasswd)<${$r_config}{'passwd_minlen'});

   my ($ret, $errmsg)=check_userpassword($r_config, $user, $oldpasswd);
   return($ret, $errmsg) if ($ret!=0);

   my $domain;
   if ( $user =~ /^(.*)\@(.*)$/ ) { ($user,$domain) = ($1,$2); }

   mysql_command("USE $mysql_auth{mysql_database}")==0 or
      return(-3, "MySQL connect error");

   my $q=$mysql_query{change_password};
   $q=~s/_user_/$user/g; $q=~s/_domain_/$domain/g;
   if ( $mysql_auth{password_hash_method} =~ /plaintext/i ) {
      $q=~ s/_new_password_/$newpasswd/g;
   } elsif ( $mysql_auth{password_hash_method} =~ /md5/i ) {
      $newpasswd = "{md5}".Digest::MD5::md5_hex($newpasswd);
      $q =~ s/_new_password_/$newpasswd/g;
   }
   return (-3, 'MySQL update error') if ( mysql_command($q)!=0 );

   mysql_command("EXIT")==0 or
      return(-3, "MySQL disconnect error");

   return(0, '');
}


################### misc support routine ###################

#  0 : ok
# -1 : MySQL error
sub mysql_command {
   my @query = @_;
   my (@result, @row, $sth);

   for ( 0 .. $#query ) {
      if ( $query[$_] =~ /^USE (.*)$/ ) {
         $main::dbh = DBI->connect("DBI:mysql:database=$1:host=$mysql_auth{mysql_server}",
				$mysql_auth{mysql_user},$mysql_auth{mysql_passwd}) or return -1;
         return 0;
      } elsif ( $query[$_] eq "EXIT" ) {
         $main::dbh->disconnect() or return -1;
         return 0;
      } elsif ( $query[$_] =~ /^SELECT/ ) {
         $sth = $main::dbh->prepare( $query[$_] );
         $sth->execute() or return -1;
         while ( @row = $sth->fetchrow_array ) { push @result,@row; }
         $sth->finish();
      } else {
         $main::dbh->do( $query[$_] ) or return -1;
         return 0;
      }
   }
   return (@result);
}

1;
