#
# htmltext.pl - html/text transformation routine
#
# 2001/12/21 tung@turtle.ee.ncku.edu.tw
#
use strict;

sub html2text {
   my $t=$_[0];

   $t=~s![ \t]+! !g;
   $t=~s![\r\n]+!!g;
   $t=~s|<style>.*?</style>||isg;
   $t=~s|<script>.*?</script>||isg;

   $t=~s!<title[^\<\>]*?>!\n\n!ig;
   $t=~s!</title>!\n\n!ig;
   $t=~s!<(?:br|br /)>!\n!ig;
   $t=~s!<hr[^\<\>]*?>!\n-----------------------------------------------------------------------\n!ig;

   $t=~s!<(?:p|p .*?)>\s?</p>!\n\n!ig;
   $t=~s!<(?:p|p .*?)>!\n\n!ig;
   $t=~s!</p>!\n\n!ig;

   $t=~s!<(?:div|div .*?)>\s?</div>!\n\n!ig;
   $t=~s!<(?:div|div .*?)>!\n\n!ig;
   $t=~s!</div>!\n\n!ig;

   $t=~s!<(?:ol|ul)[^\<\>]*?>!\n!ig;
   $t=~s!</(?:ol|ul)>!\n!ig;
   $t=~s!<li>!\n* !ig;

   $t=~s!<(?:th|tr)[^\<\>]*?>!\n!ig;
   $t=~s!</(?:th|tr)>! !ig;
   $t=~s!<td[^\<\>]*?>! !ig;
   $t=~s!</td>! !ig;

   $t=~s!<--.*?-->!!isg;

   $t=~s!<[^\<\>]*?>!!gsm;

   $t=~s!&nbsp;! !g;
   $t=~s!&lt;!<!g;
   $t=~s!&gt;!>!g;
   $t=~s!&amp;!&!g;
   $t=~s!&quot;!\"!g;

   $t=~s!^\s+!!;
   $t=~s! *\n *\n\s+!\n\n!g;

   return($t);
}

sub text2html {
   my $t=$_[0];

   $t=~s/&#(\d\d\d+);/ESCAPE_UNICODE_$1/g;
   $t=~s/&/ESCAPE_AMP/g;

   $t=~s/\"/ &quot; /g;
   $t=~s/</ &lt; /g;
   $t=~s/>/ &gt; /g;

   $t=~s!(https?|ftp|mms|nntp|news|gopher|telnet)://([\w\d\-\.]+?/?[^\s<>]*[\w/])([\b|\n| ]*)!<a href="$1://$2" target="_blank">$1://$2</a>$3!gs;
   $t=~s!([\b|\n| ]+)(www\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)!$1<a href="http://$2" target="_blank">$2</a>$3!igs;
   $t=~s!([\b|\n| ]+)(ftp\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)!$1<a href="ftp://$2" target="_blank">$2</a>$3!igs;

   # remove the blank inserted just now
   $t=~s/ (&quot;|&lt;|&gt;) /$1/g;

   $t=~s/ {2}/ &nbsp;/g;
   $t=~s/\t/ &nbsp;&nbsp;&nbsp;&nbsp;/g;
   $t=~s/\n/ <BR>\n/g;

   $t=~s/ESCAPE_AMP/&amp;/g;
   $t=~s/ESCAPE_UNICODE_(\d\d\d+)/&#$1;/g;

   return($t);
}

sub str2html {
   my $t=$_[0];

   $t=~s/&#(\d\d\d\d);/ESCAPE_UNICODE_$1/g;
   $t=~s/&/ESCAPE_AMP/g;

   $t=~s/\"/&quot;/g;
   $t=~s/</&lt;/g;
   $t=~s/>/&gt;/g;

   $t=~s/ESCAPE_AMP/&amp;/g;
   $t=~s/ESCAPE_UNICODE_(\d\d\d\d)/&#$1;/g;

   return($t);
}

sub char2html_german {	# encode german umlauts
   my $t=$_[0];
   $t=~s/ä/&auml;/g;
   $t=~s/Ä/&Auml;/g;
   $t=~s/ü/&uuml;/g;
   $t=~s/Ü/&Uuml;/g;
   $t=~s/ö/&ouml;/g;
   $t=~s/Ö/&Ouml;/g;
   $t=~s/ß/&szlig;/g;
   return($t);
}

1;
