#!/usr/bin/perl
#
# userstat.pl - a mail status javascript generator for static html page
#
# 2003/10/08 tung.AT.turtle.ee.ncku.edu.tw
#
# This script is designed to be used by static html pages to
# display openwebmail user mail/calendar status dynamically.
# All you need to do is to include the following block in html source code.
#
# <table cellspacing=0 cellpadding=0><tr><td>
# <script language="JavaScript"
# src="http://you_server_domainname/cgi-bin/openwebmail/userstat.pl">
# </script>
# </td></tr></table>
#
use strict;
use CGI qw(-private_tempfiles :standard);

# where to find the openwebmail scripts
my $ow_cgidir="/usr/local/www/cgi-bin/openwebmail";
my $ow_cgiurl="/cgi-bin/openwebmail";

# play newmail sound if cgi param playsound==1
my $soundurl="/openwebmail/sounds/YouGotMail.English.wav";

# status text to be displayed
my %text = (
   has_newmail   => "_USER_ has 1 new mail",
   has_newmails  => "_USER_ has _N_ new mails",
   has_mail      => "_USER_ has 1 mail",
   has_mails     => "_USER_ has _N_ mails",
   has_newevent  => "_USER_ has new event",
   has_event     => "_USER_ has event",
   user_calendar => "_USER_'s calendar"
);

########## No configuration required from here ###################

if (!defined $ENV{'GATEWAY_INTERFACE'}) {	# cmd mode
   print qq|\nThis script is designed to be used by static html pages to\n|.
         qq|display openwebmail user mail/calendar status dynamically.\n|.
         qq|All you need to do is to include the following block in html source code.\n\n|.
         qq|<table cellspacing=0 cellpadding=0><tr><td>\n|.
         qq|<script language="JavaScript"\n|.
         qq|src="http://you_server_domainname/cgi-bin/openwebmail/userstat.pl">\n|.
         qq|</script>\n|.
         qq|\nor\n\n|.
         qq|<table cellspacing=0 cellpadding=0><tr><td>\n|.
         qq|<script language="JavaScript"\n|.
         qq|src="http://you_server_domainname/cgi-bin/openwebmail/userstat.pl?loginname=someuser">\n|.
         qq|</script>\n|.
         qq|</td></tr></table>\n\n|;
   exit 1;
}

my $user=param('loginname')||cookie('ow-loginname')||'';
my $status='';
my $playsound = param('playsound')||'';
my $html=qq|<a href="_URL_" target="_blank" style="text-decoration: none">|.
         qq|<font color="_COLOR_">_TEXT_</font></a>|;

$user=~s/[\/\"\'\`\|\<\>\\\(\)\[\]\{\}\$\s;&]//g; # filter out dangerous chars
if ($user ne '' && length($user)<80) {
   $status=`$ow_cgidir/openwebmail-tool.pl -m -e $user`;
}
if ($user eq '' or
    $status eq '' or
    $status =~ /doesn't exist/) {
   sleep 8;
   print qq|Pragma: no-cache\n|.
         qq|Cache-control: no-cache,no-store\n|.
         qq|Content-Type: application/x-javascript\n\n|.
         qq|//\n|;
   exit 1;
}

if ($status =~ /has no mail/) {
   $html=~s|_URL_|$ow_cgiurl/openwebmail.pl?action=calmonth|;
   if ($status =~ /has new event/) {
      $html=~s|_COLOR_|#cc0000|;
      $html=~s|_TEXT_|$text{'has_newevent'}|;
   } elsif ($status =~ /has event/) {
      $html=~s|_COLOR_|#000000|;
      $html=~s|_TEXT_|$text{'has_event'}|;
   } else {
      $html=~s|_COLOR_|#000000|;
      $html=~s|_TEXT_|$text{'user_calendar'}|;
   }
} else {
   $html=~s|_URL_|$ow_cgiurl/openwebmail.pl|;
   if ($status =~ /has (\d+) new mail/) {
      my $n=$1;
      if ($n>1) {
         $html=~s|_TEXT_|$text{'has_newmails'}|;
         $html=~s|_N_|$n|;
      } else {
         $html=~s|_TEXT_|$text{'has_newmail'}|;
      }
      $html=~s|_COLOR_|#cc0000|;
      if ($playsound) {
         $html.=qq|<embed src="$soundurl" autostart=true hidden=true>|;
      }
   } elsif ($status =~ /has (\d+) mail/) {
      my $n=$1;
      if ($n>1) {
         $html=~s|_TEXT_|$text{'has_mails'}|;
         $html=~s|_N_|$n|;
      } else {
         $html=~s|_TEXT_|$text{'has_mail'}|;
      }
      $html=~s|_COLOR_|#000000|;
   }
}
$html=~s|_TEXT_|Open WebMail|;
$html=~s/_USER_/$user/g;
$html=~s|_COLOR_|#000000|;
$html=~s/'/\\'/g;

print qq|Pragma: no-cache\n|.
      qq|Cache-control: no-cache,no-store\n|.
      qq|Content-Type: application/x-javascript\n\n|.
      qq|document.write('$html');\n|;

exit 0;
