#!/usr/bin/perl
#
# preload.pl - simple http client to active openwebmail service on web server
#
# 2003/03/24 tung@turtle.ee.ncku.edu.tw
#
# This script can be used to preload openwebmail in persistent mode,
# so the user won't encounter the script startup delay.
#
use strict;
use Socket;
use IO::Socket;
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

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

# scripts to preload
# you may comment out infrequently used scripts to save some memory
# by putting a leading # in the first character of a line
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

############################# MAIN ############################
if (defined($ENV{'GATEWAY_INTERFACE'})) {	# CGI mode
   print "Content-type: text/html\n\n",
         "<html><body>\n",
         "<h2>Open WebMail Preload Page</h2>\n";
   if (defined(param('password')) &&
       crypt(param('password'),$cgipwd) eq $cgipwd){
      print " "x256, "\n"; # fill buffer so following output will show immediately
      print "<pre>\n";
      preload($quiet, $httphost, $httpport, $cgiurl, @scripts);
      print "</pre>\n";
      print startform(),
            submit(-name=>' Clear '),
            end_form();
   } else {
      sleep 8 if (defined(param('password')));
      print startform(),
            "Access Password : ",
            password_field(-name=>'password',
                           -default=>'',
                           -size=>'16',
                           -override=>'1'), 
            "\n<br><br>\n",
            submit(-name=>' Submit '),
            end_form();
   }
   print "\n<a href='/cgi-bin/openwebmail/openwebmail.pl'>Login Open WebMail</a>\n";
   print "</body></html>\n";

} else {					# cmd mode
   foreach (@ARGV) {
      $quiet=1 if (/-q/ || /--quiet/);
   }
   exit preload($quiet, $httphost, $httpport, $cgiurl, @scripts);
}

########################### ROUTINES ##########################
sub preload {
   my ($quiet, $httphost, $httpport, $cgiurl, @scripts)=@_;

   local $|=1;
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
