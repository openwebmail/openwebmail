#!/usr/bin/perl
#
# preload.pl - simple http client to active openwebmail service on web server
#
# 2003/03/24 tung.AT.turtle.ee.ncku.edu.tw
#
# This script can work as a CGI or command line tool.
# It is used to preload openwebmail scripts in persistent mode,
# so the user won't encounter the script startup delay.
#
use strict;
foreach (qw(ENV BASH_ENV CDPATH IFS TERM)) {delete $ENV{$_}}; $ENV{PATH}='/bin:/usr/bin'; # secure ENV

# encrypted password for cgi access
#
# To have a new encrypted passwd for this:
# 1. htpasswd -c /tmp/test guest
# 2. enter password
# 3. copy the encrypted field in /tmp/test to this
#
my $cgipwd="MW7y7p8tQsXpU"; # pwd=speedycgi, CHNANGE IT AS SOON AS POSSIBLE

# where the web server is
my $httphost="127.0.0.1";
my $httpport="80";

# url prefix of openwebmail scripts,
# it should be the same as option ow_cgiurl in openwebmail.conf
my $cgiurl="/cgi-bin/openwebmail";

########## No configuration required from here ###################

use Socket;
use IO::Socket;

# all openwebmail scripts to preload,
# used in cgi mode or if --all is specified in command mode
my @scripts=(
   'openwebmail.pl',
   'openwebmail-main.pl',
   'openwebmail-prefs.pl',
   'openwebmail-read.pl',
   'openwebmail-viewatt.pl',
   'openwebmail-send.pl',
   'openwebmail-abook.pl',
   'openwebmail-cal.pl',
   'openwebmail-webdisk.pl',
   'openwebmail-folder.pl',
   'openwebmail-spell.pl',
   'openwebmail-advsearch.pl',
);

# -q option set this to 1, then no output, useful for cronatb
my $quiet=0;

########## MAIN ##################################################
my %param=ReadParse();

if (defined $ENV{'GATEWAY_INTERFACE'}) {	# CGI mode
   local $|=1;
   print qq|Content-type: text/html\n\n|.
         qq|<html><body>\n|.
         qq|<h2>Open WebMail Preload Page</h2>\n|;
   if (defined $param{'password'} &&
       crypt($param{'password'},$cgipwd) eq $cgipwd){
      print qq|<pre>\n|;
      preload($quiet, $httphost, $httpport, $cgiurl, @scripts);
      print qq|</pre>\n|;
      print qq|<form method="post" action="$cgiurl/preload.pl" enctype="application/x-www-form-urlencoded">\n|.
            qq|<input type="submit" name=" Clear " value=" Clear " />\n|.
            qq|</form>\n|;
   } else {
      sleep 8 if (defined $param{'password'});
      print qq|<form method="post" action="$cgiurl/preload.pl" enctype="application/x-www-form-urlencoded">\n|.
            qq|Access Password : \n|.
            qq|<input type="password" name="password"  size="16" />\n|.
            qq|<br><br>\n|.
            qq|<input type="submit" name=" Submit " value=" Submit " />\n|.
            qq|</form>\n|;
   }
   print qq|<a href='$cgiurl/openwebmail.pl'>Login Open WebMail</a>\n|.
         qq|</body></html>\n|;

} else {					# cmd mode
   my @preloadscripts;
   foreach (@ARGV) {
      if (/^\-q/ || /^\-\-quiet/) {
         $quiet=1;
      } elsif (/^--all/) {
         @preloadscripts=@scripts;
      } elsif (/^openwebmail.+pl$/) {
         push(@preloadscripts, $_);
      }
   }
   if ($#preloadscripts>=0) {
      exit preload($quiet, $httphost, $httpport, $cgiurl, @preloadscripts);
   } else {
      print "Syntax: preload.pl [-q] [--all]\n",
            "        preload.pl [-q] openwebmail_scriptnames...\n";
      exit 1;
   }
}

########## ROUTINES ##############################################
sub preload {
   my ($quiet, $httphost, $httpport, $cgiurl, @scripts)=@_;

   foreach my $script (@scripts) {
      my $result='';
      print "Loading $script..." if (!$quiet);

      my  $remote_sock=new IO::Socket::INET(Proto=>'tcp',
	                                    PeerAddr=>$httphost,
                                            PeerPort=>$httpport);
      if (! $remote_sock ) {
         print "connect error!\n" if (!$quiet);
         return -1;
      }
      $remote_sock->autoflush(1);

      print $remote_sock "GET $cgiurl/$script HTTP/1.0\n\n";
      while (<$remote_sock>) {
         s/[\s\t]+$//;
         $result .= "$_\n";
      }
      close($remote_sock);

      print "done.\n" if (!$quiet);
   }
   return 0;
}

# routine from netjack.pm at http://www.the42.net/jack
# by PJ Goodwin <pj_at_the42.net>
sub ReadParse {
   my (%param, $string);

   if ($ENV{'REQUEST_METHOD'} eq "GET") {
      $string = $ENV{'QUERY_STRING'};
   } elsif ($ENV{'REQUEST_METHOD'} eq "POST") {
      read(STDIN, $string, $ENV{'CONTENT_LENGTH'});
   } else {
      $string = $ARGV[0];
   }
   $string =~ s/\+/ /g;		# conv + to spaces
   $string =~ s/%(..)/pack("c", hex($1))/ge;

   foreach (split(/&/, $string)) {
      s|[^\-a-zA-Z0-9_\.@=/+\/\,\(\)!\s]|_|g;		# rm bad char
      my ($key, $val)=split(/=/, $_, 2);		# split into key and value.
      $param{$key} .= '\0' if (defined $param{$key});	# \0 is multiple separator
      $param{$key} .= $val;
   }
   return %param;
}
