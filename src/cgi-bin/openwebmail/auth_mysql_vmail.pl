#
# auth_mysql_vmail.pl - authenticate user with MySQL, where required fields 
#                       are in more tables (like in vmail-sql).
# v1.5
# 2002/04/23 Zoltan Kovacs - werdy@freemail.hu
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

my ( %mysql_auth, %mysql_query );

########################
# MySQL access options #
########################
$mysql_auth{mysql_server} = "localhost";	# MySQL server
$mysql_auth{mysql_database} = "vmail";		# MySQL database
$mysql_auth{mysql_user} = "";			# MySQL username
$mysql_auth{mysql_passwd} = "";			# MySQL password
$mysql_auth{password_hash_method} = "MD5";	# supported methods: md5 and plaintext


#################
# MySQL queries #
#################

# How can get user's list ###
$mysql_query{userlist} = "SELECT local_part FROM popbox ORDER BY local_part";

# How can get user's password (you can use _user_ and _domain_ variables)
$mysql_query{user_password} = "SELECT password_hash FROM popbox WHERE local_part='_user_' AND domain_name='_domain_'";

# How can get user's home directory (you can use _user_ and _domain_ variables)
$mysql_query{user_homedir} = "";

# How can get real unix user (you can use _user_ and _domain_ variables)
$mysql_query{unix_user} = "SELECT domain.unix_user FROM domain LEFT JOIN popbox ON domain.domain_name=popbox.domain_name WHERE popbox.mbox_name='_user_' AND popbox.domain_name='_domain_'";

# How can change user's password (you can use _user_, _domain_ and _new_password_ variables)
$mysql_query{change_password} = "UPDATE popbox SET password_hash='_new_password_' WHERE local_part='_user_' AND domain_name='_domain_'";

################### No configuration required from here ###################

use strict;
use DBI;
if ( $mysql_auth{password_hash_method} =~ /md5/i ) { use Digest::MD5; }

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub get_userinfo {
    my $user = $_[0];
    my ( $unix_user, $gid, $uid, $home, $key, $domain );

    return -2 if ( !$user );
    if ( $user =~ /^(.*)\@(.*)$/ ) { ($user,$domain) = ($1,$2); }

    foreach ( keys %mysql_query ) {
	$mysql_query{$_} =~ s/_user_/$user/g;
	$mysql_query{$_} =~ s/_domain_/$domain/g;
    }

    if ( !&mysql_command("USE $mysql_auth{mysql_database}") )  {
        ( $home ) = &mysql_command($mysql_query{user_homedir}) if ( $mysql_query{user_homedir} );
        ( $unix_user ) = &mysql_command($mysql_query{unix_user});
    } else { return -3; }
    &mysql_command("EXIT");

    ( $uid, $gid ) = ( getpwnam($unix_user) )[2,3];

    return -3 if ( !$unix_user || !$uid || !$gid );
    return ("",$uid,$gid,$home);
}

sub get_userlist { # only used by checkmail.pl -a
    my @userlist;

    if ( !&mysql_command("USE $mysql_auth{mysql_database}") ) {
	@userlist = &mysql_command( $mysql_query{userlist} );
    } else { return -3; }
    &mysql_command("EXIT");

    return @userlist;
}

#  0 : ok
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
    my ($user, $passwd)=@_;
    my ( $passwd_hash, $domain );

    return -2 if ( !$user || !$passwd );
    if ( $user =~ /^(.*)\@(.*)$/ ) { ($user,$domain) = ($1,$2); }

    $mysql_query{user_password} =~ s/_user_/$user/g;
    $mysql_query{user_password} =~ s/_domain_/$domain/g;

    if ( !&mysql_command("USE $mysql_auth{mysql_database}") ) {
	( $passwd_hash ) = &mysql_command( $mysql_query{user_password} );
    } else { return -3; }
    &mysql_command("EXIT");

    if ( $mysql_auth{password_hash_method} =~ /plaintext/i ) {
	return 0 if ( $passwd_hash eq $passwd );
    } elsif ( $mysql_auth{password_hash_method} =~ /md5/i ) {
	$passwd_hash =~ s/^\{.*\}(.*)$/$1/;
	return 0 if ( $passwd_hash eq Digest::MD5::md5_hex($passwd) );
    }
    	
    return -4;
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub change_userpassword {
    my ($user, $oldpasswd, $newpasswd)=@_;
    my $domain;

    return -2 if ( !$user || !$oldpasswd || !$newpasswd );
    return -4 if ( &check_userpassword ($user,$oldpasswd) );
    if ( $user =~ /^(.*)\@(.*)$/ ) { ($user,$domain) = ($1,$2); }

    $mysql_query{change_password} =~ s/_user_/$user/g;
    $mysql_query{change_password} =~ s/_domain_/$domain/g;

    if ( !&mysql_command("USE $mysql_auth{mysql_database}") ) {
	if ( $mysql_auth{password_hash_method} =~ /plaintext/i ) {
	    $mysql_query{change_password} =~ s/_new_password_/$newpasswd/g;
	    return -3 if ( &mysql_command( $mysql_query{change_password} ) );
	} elsif ( $mysql_auth{password_hash_method} =~ /md5/i ) {
	    $newpasswd = "{md5}".Digest::MD5::md5_hex($newpasswd);
	    $mysql_query{change_password} =~ s/_new_password_/$newpasswd/g;
	    return -3 if ( &mysql_command( $mysql_query{change_password} ) );
	}
    } else { return -3; }
    &mysql_command("EXIT");
}

#  0 : ok
# -1 : MySQL error
sub mysql_command {
    my @query = @_;
    my ( @result, @row, $sth );

    for ( 0 .. $#query ) {
	if ( $query[$_] =~ /^SELECT/ ) {
    	    $sth = $main::dbh->prepare( $query[$_] );
	    $sth->execute() || return -1;
    	    while ( @row = $sth->fetchrow_array ) { push @result,@row; }
	    $sth->finish();
	} elsif ( $query[$_] =~ /^USE (.*)$/ ) {
	    $main::dbh = DBI->connect("DBI:mysql:database=$1:host=$mysql_auth{mysql_server}",$mysql_auth{mysql_user},$mysql_auth{mysql_passwd}) || return -1;
	    return 0;
	} elsif ( $query[$_] eq "EXIT" ) {
	    $main::dbh->disconnect() || return -1;
	    return 0;
	} else {
	    $main::dbh->do( $query[$_] ) || return -1;
	    return 0;
	}
    }

    return @result;
}

1;
