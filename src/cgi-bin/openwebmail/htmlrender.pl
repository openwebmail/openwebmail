#
# htmlrender.pl - html attachment rendering routines
#
# 2001/12/21 tung@turtle.ee.ncku.edu.tw
#
# it is suggested calling these following routine in the following order:
# html4nobase, html4link, html4disablejs, html4disableembcgi,
# html4attachment, html4mailto, html2table
#

# since this routine deals with base directive,
# it must be called first before other html...routines when converting html
sub html4nobase {
   my $html=$_[0];
   my $urlbase;
   if ( $html =~ m!\<base\s+href\s*=\s*"?([^\<\>]*?)"?\>!i ) {
      $urlbase=$1;
      $urlbase=~s!/[^/]+$!/!;
   }

   $html =~ s!\<base\s+([^\<\>]*?)\>!!gi;
   if ( ($urlbase ne "") && ($urlbase !~ /^file:/) ) {
      $html =~ s!(\<a\s+href|background|src|method|action)(=\s*"?)!$1$2$urlbase!gi;
      # recover links that should not be changed by base directive
      $html =~ s!\Q$urlbase\E(http://|https://|ftp://|mms://|cid:|mailto:|#)!$1!gi;
   }
   return($html);
}

my @jsevents=('onAbort', 'onBlur', 'onChange', 'onClick', 'onDblClick',
              'onDragDrop', 'onError', 'onFocus', 'onKeyDown', 'onKeyPress',
              'onKeyUp', 'onLoad', 'onMouseDown', 'onMouseMove', 'onMouseOut',
              'onMouseOver', 'onMouseUp', 'onMove', 'onReset', 'onResize',
              'onSelect', 'onSubmit', 'onUnload');

# this routine is used to add target=_blank to links in a html message
# so clicking on it will open a new window
sub html4link {
   my $html=$_[0];
   $html=~s/(<a\s+[^\<\>]*?>)/_link_target_blank($1)/igems;
   return($html);
}

sub _link_target_blank {
   my $link=$_[0];
#   foreach my $event (@jsevents) {
#      return($link) if ($link =~ /$event/i);
#   }
   if ($link =~ /target=/i ||
       $link =~ /javascript:/i ||
       $link =~ /href="?#/i ) {
      return($link);
   }
   $link=~s/<a\s+([^\<\>]*?)>/<a $1 target=_blank>/is;
   return($link);
}

# this routine is used to resolve frameset in html by
# converting <frame ...> into <iframe width="100%"..></iframe>
# so html with frameset can be displayed correctly inside the message body
sub html4noframe {
   my $html=$_[0];
   $html=~s/(<frame\s+[^\<\>]*?>)/_frame2iframe($1)/igems;
   return($html);
}

sub _frame2iframe {
   my $frame=$_[0];
   return "" if ( $frame!~/src=/i );
   $frame=~s/<frame /<iframe width="100%" height="250" /is;
   $frame.=qq|</iframe>|;
   return($frame);
}

# this routine disables the javascript in a html message
# to avoid user being hijacked by some evil programs
sub html4disablejs {
   my $html=$_[0];
   my $event;

   foreach $event (@jsevents) {
      $html=~s/$event/_$event/imsg;
   }
   $html=~s/<script([^\<\>]*?)>/<disable_script$1>\n<!--\n/imsg;
   $html=~s/<!--\s*<!--/<!--/imsg;
   $html=~s/<\/script>/\n\/\/-->\n<\/disable_script>/imsg;
   $html=~s/\/\/-->\s*\/\/-->/\/\/-->/imsg;
   $html=~s/<([^\<\>]*?)javascript:([^\<\>]*?)>/<$1disable_javascript:$2>/imsg;

   return($html);
}

# this routine disables the embedded CGI in a html message
# to avoid user email addresses being confirmed by spammer through embedded CGIs
sub html4disableembcgi {
   my $html=$_[0];
   $html=~s!(src|background)\s*=\s*("?https?://[\w\.\-]+?/?[^\s<>]*[\w/])([\b|\n| ]*)!_clean_embcgi($1,$2,$3)!egis;
   return($html);
}

sub _clean_embcgi {
   my ($type, $url, $end)=@_;

   if ($url=~/\?/s && $url !~ /\Q$ENV{'HTTP_HOST'}\E/is) { # non local CGI found
      $url=~s/["']//g;
      return("alt='Embedded CGI removed by $config{'name'}.\n$url'".$end);
   } else {
      return("$type=$url".$end);
   }
}

# this routine is used to resolve crossreference inside attachments
# by converting them to request attachment from openwebmail cgi
sub html4attachments {
   my ($html, $r_attachments, $scripturl, $scriptparm)=@_;
   my $i;

   for ($i=0; $i<=$#{$r_attachments}; $i++) {
      my $filename=escapeURL(${${$r_attachments}[$i]}{filename});
      my $link="$scripturl/$filename?$scriptparm&amp;attachment_nodeid=${${$r_attachments}[$i]}{nodeid}&amp;";
      my $cid="cid:"."${${$r_attachments}[$i]}{id}";
      my $loc=${${$r_attachments}[$i]}{location};

      if ( ($cid ne "cid:" && $html =~ s#\Q$cid\E#$link#ig ) ||
           ($loc ne "" && $html =~ s#\Q$loc\E#$link#ig ) ||
           # ugly hack for strange CID
           ($filename ne "" && $html =~ s#CID:\{[\d\w\-]+\}/$filename#$link#ig )
         ) {
         # this attachment is referenced by the html
         ${${$r_attachments}[$i]}{referencecount}++;
      }
   }
   return($html);
}

# this routine chnage mailto: into webmail composemail function
# to make it works with base directive, we use full url
# to make it compatible with undecoded base64 block,
# we put new url into a seperate line
sub html4mailto {
   my ($html, $scripturl, $scriptparm)=@_;
   $html =~ s/(=\s*"?)mailto:\s?([^\s]*?)\s?(\s|"?\s*\>)/$1\n$scripturl\?$scriptparm&amp;to=$2\n$3/ig;
   return($html);
}

sub html2table {
   my $html=$_[0];

   $html =~ s#<!doctype[^\<\>]*?\>##i;
   $html =~ s#\<html[^\>]*?\>##i;
   $html =~ s#\</html\>##i;
   $html =~ s#\<head\>##i;
   $html =~ s#\</head\>##i;
   $html =~ s#\<meta[^\<\>]*?\>##gi;
   $html =~ s#\<body([^\<\>]*?)\>#\<table width=100% border=0 cellpadding=2 cellspacing=0 $1\>\<tr\>\<td\>#i;
   $html =~ s#\</body\>#\</td\>\</tr\>\</table\>#i;

   $html =~ s#\<!--.*?--\>##ges;
   $html =~ s#\<style[^\<\>]*?\>#\n\<!-- style begin\n#gi;
   $html =~ s#\</style\>#\nstyle end --\>\n#gi;
   $html =~ s#\<[^\<\>]*?stylesheet[^\<\>]*?\>##gi;
   $html =~ s#(\<div[^\<\>]*?)position\s*:\s*absolute\s*;([^\<\>]*?\>)#$1$2#gi;

   return($html);
}

1;
