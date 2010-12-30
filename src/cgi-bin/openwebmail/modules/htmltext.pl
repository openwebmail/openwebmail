
#                              The BSD License
#
#  Copyright (c) 2008, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# htmltext.pl:
# routines to convert strings from text to html or from html to text

package ow::htmltext;

use strict;
use warnings;

sub html2text {
   my $t = shift;
   return $t unless defined $t && $t =~ m/\S/;

   # turn <pre>...</pre> into pure html with <br>
   $t =~ s#<!--+-->#\n#isg;
   $t =~ s#\s*<pre[^\<\>]*?>(.*?)</pre>\s*#_pre2html($1)#iges;

   $t =~ s#¡@#  #g; # clean chinese big5 space char
   $t =~ s#&nbsp;# #g;
   $t =~ s#[ \t]+# #g;
   $t =~ s#^\s+##mg;
   $t =~ s#\s+$# #mg;
   $t =~ s#[\r\n]+##g;

   $t =~ s#<!--.*?-->##sg;
   $t =~ s#<style(?: [^\<\>]*)?>.*?</style>##isg;
   $t =~ s#<script(?: [^\<\>]*)?>.*?</script>##isg;
   $t =~ s#<noframes(?: [^\<\>]*)?>.*?</noframes>##isg;
   $t =~ s#<i?frame[^\<\>]* src="?([^\<\>\s\"]*)"?[^\<\>]*>(.*?</iframe>)?#\n$1\n#isg;

   $t =~ s#<p(?: [^\<\>]*)?>#ESCAPE_P#ig;
   $t =~ s#<div(?: [^\<\>]*)?>#ESCAPE_DIV#ig;

   # this should be processed before </td> <-> space replacement,
   # or </p>|</div>|\s before </td> won't be found
   $t =~ s#<(?:span|font|b|i|a)(?: [^\<\>]*)?>##isg;
   $t =~ s#</(?:th|tr|span|font|b|i|a)>##ig;

   # this should be processed before <table> <-> \n replacement,
   # or it will eat \n of <table> in recursive table
   $t =~ s#<td(?: [^\<\>]*)?>(?:ESCAPE_P|ESCAPE_DIV|</p>|</div>|\s)*</td>##isg;
   $t =~ s#<td(?: [^\<\>]*)?>(?:ESCAPE_P|ESCAPE_DIV|\s)*# #isg;
   $t =~ s#(?:</p>|</div>|\s)*</td># #isg;

   $t =~ s#<(?:table|tbody|th|tr)(?: [^\<\>]*)?>#\n#isg;
   $t =~ s#</(?:table|tbody)>#\n#ig;

   $t =~ s#<(?:ol|ul)(?: [^\<\>]*)?>#\n#ig;
   $t =~ s#</(?:ol|ul)>#\n#ig;
   $t =~ s#(?:</p>|</div>|\s)*<li>(?:ESCAPE_P|ESCAPE_DIV|\s)*#\n* #isg;

   $t =~ s#ESCAPE_P\s*(?:</p>)*#\n\n#isg;
   $t =~ s#</p>#\n\n#ig;

   $t =~ s#ESCAPE_DIV\s*(?:</div>)*#\n\n#isg;
   $t =~ s#</div>#\n\n#ig;

   $t =~ s#<select(?: [^\<\>]*)?>(<option(?: [^\<\>]*)?>)?#(#isg;
   $t =~ s#</select>#)#ig;
   $t =~ s#<option(?: [^\<\>]*)?>#,#isg;
   $t =~ s#<input[^\<\>]* type=['"]?radio['"]?[^\<\>]*># *#isg;

   $t =~ s#</?title>#\n\n#ig;
   $t =~ s#<br ?/?>#\n#ig;
   $t =~ s#<hr(?: [^\<\>]*)?>#\n-----------------------------------------------------------------------\n#ig;

   $t =~ s#<[^\<\>]+?>##sg;

   $t =~ s#&lt;#<#g;
   $t =~ s#&gt;#>#g;
   $t =~ s#&amp;#&#g;
   $t =~ s#&quot;#\"#g;
   $t =~ s#&copy;#(C)#g;

   $t =~ s#^\s+##;
   $t =~ s#(?:[ |\t]*\n){2,}#\n\n#sg;

   return($t);
}

sub _pre2html {
   my $t = shift;
   return $t unless defined $t && $t =~ m/\S/;

   # $t =~ s#\"#&quot;#g;
   # $t =~ s#<#&lt;#g;
   # $t =~ s#>#&gt;#g;
   $t =~ s#</(?:p|div|table|th|tr)> *\r?\n#</$1>ESCAPE_NEWLINE#ig;
   $t =~ s#\n#<br>\n#g;
   $t =~ s#ESCAPE_NEWLINE#\n#ig;
   return $t;
}

sub text2html {
   my $t = shift;
   my $skiplinkify = shift || 0;

   return $t unless defined $t && $t =~ m/\S/;

   $t =~ s/&#(\d{2,3});/ESCAPE_UNICODE_$1/g;
   $t =~ s#&#ESCAPE_AMP#g;

   # the spaces around these are removed later
   $t =~ s#"# &quot; #g;
   $t =~ s#<# &lt; #g;
   $t =~ s#># &gt; #g;

   unless ($skiplinkify) {
      # convert urls or FQDNs to links
      $t =~ s#(https?|ftp|mms|nntp|news|gopher|telnet)://([\w\d\-\.]+?/?[^\s\(\)\<\>\x80-\xFF]*[\w/])([\b|\n| ]*)#<a href="$1://$2" target="_blank">$1://$2</a>$3#igs;
      $t =~ s#([\b|\n| ]+)(www\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)#$1<a href="http://$2" target="_blank">$2</a>$3#igs;
      $t =~ s#([\b|\n| ]+)(ftp\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)#$1<a href="ftp://$2" target="_blank">$2</a>$3#igs;
   }

   # remove the blank inserted just now
   $t =~ s# (&quot;|&lt;|&gt;) #$1#g;

   $t =~ s# {2}# &nbsp;#g;
   $t =~ s#\t# &nbsp;&nbsp;&nbsp;&nbsp;#g;
   $t =~ s#\n# <br>\n#g;

   $t =~ s#ESCAPE_AMP#&#g;
   $t =~ s#&(?![A-Za-z0-9]{2,8};)#&amp;#g;
   $t =~ s/ESCAPE_UNICODE_(\d{2,3})/&#$1;/g;

   return $t;
}

sub text2html_nolink { return text2html(shift,1) };

sub str2html {
   my $t = shift;

   return $t unless defined $t && $t =~ m/\S/;

   $t =~ s/&#(\d\d\d+);/ESCAPE_UNICODE_$1/g;
   $t =~ s/&/ESCAPE_AMP/g;

   $t =~ s/"/&quot;/g;
   $t =~ s/</&lt;/g;
   $t =~ s/>/&gt;/g;

   $t =~ s/ESCAPE_AMP/&amp;/g;
   $t =~ s/ESCAPE_UNICODE_(\d\d\d+)/&#$1;/g;

   return($t);
}

1;
