#
# auth_pgsql.pl - authenticate user with PostgreSQL
#
# 2002/04/05 Veselin Slavov vess@btc.net
#

#
# CREATE TABLE "users" (
#	"Uid"		serial,
#	"Gid"		int4,
#	"uname"		char(64),  -- username
#	"upass"		char(32),  -- password (cleartxt, MD5 or crypt)
#	"rname"		char(), -- realname
#	"MailDir"	char(64) -- Home Dir
#	);
#

my $PgHost	= "localhost";
my $PgPort	= "5432";
my $PgBase 	= "DATABASE_NAME";
my $PgUser	= "USERNAME";
my $PgPass 	= "PASSWORD";
my $PgPassType	= "crypt"; 		# crypt, md5, cleartxt

################### No configuration required from here ###################

use strict;
use Pg;
use MD5;

my $DB = Pg::connectdb("host='$PgHost' port='$PgPort' dbname='$PgBase' user='$PgUser' password='$PgPass'");

sub get_userinfo {
   my $user=$_[0];
   my ($uid, $gid, $realname, $homedir);

   my $q= qq/select "Uid", "Gid", "rname", "MailDir" from users where uname='$user'/;
   my @ret=();
   Pg::doQuery($DB,$q,\@ret);

   if ($ret[0][0] eq '') {
	return -1;
	}
   else {
        $uid 	  = $ret[0][0];
        $gid 	  = $ret[0][1];
        $realname = $ret[0][2];
        $homedir  = $ret[0][3];
	return($realname, $uid, $gid, $homedir);
	}
}


sub get_userlist {      # only used by openwebmail-tool.pl -a
   my @userlist=();
   my $q="select uname from users";
   Pg::doQuery($DB,$q,\@userlist);
   return (@userlist);
}


#  0 : ok
# -1 : function not supported
# -2 : parameter format error
# -3 : authentication system/internal error
# -4 : password incorrect
sub check_userpassword {
   my ($user, $password)=@_;
   return -2 unless ( $user ne "" && $password ne "");

   my @ret=();
   my $q="select upass from users where uname='$user'";
   Pg::doQuery($DB,$q,\@ret);

   if ($ret[0][0] eq '') {
        return -4;
        }
   else {
	my $tmp_pwd = $ret[0][0];
 	$tmp_pwd =~ s/ //g;

	CASE: for ($PgPassType){
	/cleartxt/ && do {		#if  cleartext password
	   	if ($tmp_pwd eq $password){
			return 0;
	   	} else {
			return -4;
	   	}
	     last};
	/crypt/ && do {			#if 	crypto password
		if ($tmp_pwd eq crypt($password, $tmp_pwd)) {
        		return 0;
		} else {
			return -4;
		}
	     last};

	/md5/ && do {			#if  md5 kode password
		my($m5) = new MD5;
		$m5->reset;
		$m5->add($password);
		my($mm)= $m5->digest();
		my($md5)= unpack("H*",$mm);
		if ($tmp_pwd eq $md5) {
			   return 0;
		 } else {
			   return -4;
		 }
	     last};
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
   my ($passwd);
   my $content="";
   my $line;

   return -2 unless ( $user ne "" && $oldpassword ne "" && $newpassword ne "" );
   return -2 if (length($newpassword)<4);

   my $test = &check_userpassword ($user, $oldpassword);
   return -4 unless $test eq 0;


	CASE: for ($PgPassType){
	/cleartxt/ && do {		#if  cleartext password
		$passwd=$newpassword;
		$passwd =~ tr/[a-z][A-Z][0-9]~!@#()-_.//dcs; # ignore some symbols
		return -2 unless $passwd eq $newpassword;
		last};
	/crypt/ && do {	#if 	crypto password
   		srand();
   		my $table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
   		my $salt=substr($table, int(rand(length($table))), 1).
            	substr($table, int(rand(length($table))), 1);
   		$passwd = crypt($newpassword, $salt);
		last};

	/md5/ && do {		#if  md5 kode password
		my($m5) = new MD5;
		$m5->reset;
		$m5->add($newpassword);
		my($mm)= $m5->digest();
		$passwd= unpack("H*",$mm);
		last};
	  }
	$DB->exec("update users set upass='$passwd' where uname='$user'");
   return 0;
}

1;
