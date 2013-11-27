package ow::htmlrender;

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

# routines to reformat html for inline display.
# Used by openwebmail-read.pl and openwebmail-viewatt.pl.
#
# it is suggested these routines be called in the following order:
# html4nobase, html4link, html4disablejs, html4disableemblink, html4blockimages, html4attachment, html4mailto, html2table

use strict;
use warnings FATAL => 'all';

require "modules/tool.pl";

my @jsevents = (
                 'onAbort', 'onBlur', 'onChange', 'onClick', 'onDblClick', 'onDragDrop',
                 'onError', 'onFocus', 'onKeyDown', 'onKeyPress', 'onKeyUp', 'onLoad',
                 'onMouseDown', 'onMouseMove', 'onMouseOut', 'onMouseOver', 'onMouseUp',
                 'onMove', 'onReset', 'onResize', 'onSelect', 'onSubmit', 'onUnload',
                 'window.open', '@import', 'window.location', 'location.href', 'document.url',
                 'document.location', 'document.referrer'
               );

sub html4nobase {
   # since this routine deals with the base directive it must be called
   # first before any other routines in this module when converting html
   my $html = shift;

   my $urlbase = '';

   if ($html =~ m#<base\s+href\s*=\s*['"]?([^<>]*?)['"]?>#i) {
      $urlbase = $1;
      $urlbase =~ s#/[^/]+$#/#;
   }

   $html =~ s#<base\s+([^<>]*?)>##gi;

   if ($urlbase ne '' && $urlbase !~ m/^file:/i) {
      $html =~ s#(<a\s+href|background|src|method|action)(=\s*['"]?)#$1$2$urlbase#gi;
      # recover links that should not be changed by base directive
      $html =~ s#\Q$urlbase\E(http://|https://|ftp://|mms://|cid:|mailto:|\#)#$1#gi;
   }

   return $html;
}

sub html4link {
   # this routine is used to add target=_blank to links in a html message
   # so clicking on it will open a new window
   my $html = shift;
   $html =~ s#(<a\s+[^<>]*?>)#_link_target_blank($1)#igems;
   return $html;
}

sub _link_target_blank {
   my $link = shift;

   return $link if $link =~ m/(?:target=|javascript:|href=['"]?#)/i;

   $link =~ s#<a\s+([^<>]*?)>#<a $1 target="_blank">#is;

   return $link;
}

sub html4noframe {
   # this routine is used to resolve framesets in html by
   # converting <frame ...> into <iframe width="100%"..></iframe>
   # so html with framesets can be displayed correctly inside the message body
   my $html = shift;
   $html =~ s#(<frame\s+[^<>]*?>)#_frame2iframe($1)#igems;
   return $html;
}

sub _frame2iframe {
   my $frame = shift;
   return '' if ($frame !~ m#src\s*=\s*#i); # remove remote frames
   $frame =~ s#<frame #<iframe width="100%" height="250" #is;
   $frame .= '</iframe>';
   return $frame;
}

sub html4disablejs {
   # this routine disables the javascript in an html message
   # to avoid the user being hijacked by some evil programs
   my $html = shift;

   foreach my $event (@jsevents) {
      $html =~ s/$event/disable_$event/isg;
   }

   # disable javascript code blocks
   $html =~ s#<script([^<>]*?)>#<disable_script$1>\n<!--\n#isg;
   $html =~ s#<!--\s*<!--#<!--#isg;
   $html =~ s#</script>#\n//-->\n</disable_script>#isg;
   $html =~ s#//-->\s*//-->#//-->#isg;

   # disable inline javascript
   $html =~ s#<([^<]*?[='"\s]+)javascript:#<$1disable_javascript:#isg;

   # disable inline css expression javascript
   # IE 7 and earlier and IE 8 in quirks mode only
   # like: background-color:expression(alert('hacked') && true ? "#000000" : "#ffffff")
   # like: height:     expression(document.body.offsetHeight - 20 + "px");
   $html =~ s#:\s*expression\(#:expression(return void(0);#isg;

   return $html;
}

sub html4disableembcode {
   # this routine disables embed, applet, object tags in an html message
   # to avoid user being hijacked by some evil programs
   my $html = shift;
   foreach my $tag (qw(embed applet object)) {
      $html =~ s#<\s*$tag([^<>]*?)>#<disable_$tag$1>#isg;
      $html =~ s#<\s*/$tag([^<>]*?)>#</disable_$tag$1>#isg;
   }
   $html =~ s#<\s*param ([^<>]*?)>#<disable_param $1>#isg;
   return $html;
}

sub html4disableemblink {
   # this routine disables the embedded CGI in a html message
   # to avoid user email addresses being confirmed by spammer through embedded CGIs
   my ($html, $disableemblink, $blankimgurl) = @_;
   return $html if !defined $disableemblink || $disableemblink eq 'none';
   $html =~ s#(src|background)\s*=\s*(["']?https?://[\w\.\-]+?/?[^\s<>]*)([\b|\n| ]*)#_clean_emblink($1,$2,$3,$disableemblink,$blankimgurl)#egis;

   # disallow inline data sources
   $html =~ s#(src)\s*=\s*(["']?data:[^\s<>]*)([\b|\n| ]*)#_clean_emblink($1,$2,$3,$disableemblink,$blankimgurl)#egis;
   return $html;
}

sub _clean_emblink {
   my ($type, $url, $end, $disableemblink, $blankimgurl) = @_;

   if ($url !~ /\Q$ENV{HTTP_HOST}\E/is) { # non-local URL found
      $url =~ s/["']//g; # remove leading " or '

      return(qq|$type="$blankimgurl" border="1" title="embedded CGI removed by OWM" alt="embedded CGI removed by OWM: $url" onclick="window.open('$url', '_extobj');"$end|)
        if $disableemblink eq 'cgionly' && $url =~ m/\?/s;

      return(qq|$type="$blankimgurl" border="1" title="embedded link removed by OWM" alt="embedded link removed by OWM: $url" onclick="window.open('$url', '_extobj');"$end|)
        if $disableemblink eq 'all';
   }

   return("$type=$url".$end);
}

sub html4blockimages {
   # disable inline images to avoid user email addresses being
   # confirmed by spammers through link tracking callbacks
   # users may choose to disable this on a per-email basis
   # or by updating their preferences
   my ($html, $blankimgurl, $r_blockimagestoggle) = @_;

   my $original_html = "$html";

   # like: src="http://example.com/youremail.jpg"
   $html =~ s#(src|background)\s*=\s*(['"]?https?://[\w\.\-]+?/?[^\s<>]*)([\b|\n| ]*)#_clean_imglink($1,$2,$3,$blankimgurl)#egis;
   # like: style=background-image:url("http://example.com/youremail.jpg")
   $html =~ s#\s*url\s*\((['"]?https?://[\w\.\-]+?/?[^\s\)]*)\)([\b|\n| ]*)#_clean_styleimglink($1,$2,$blankimgurl)#egis;

   # if images blocked, turn on the switch to unblock them
   ${$r_blockimagestoggle}++ if $original_html ne $html;

   return $html;
}

sub _clean_imglink {
   my ($type, $url, $end, $blankimgurl) = @_;
   $url =~ s/["']//g;
   return(qq|$type="$blankimgurl" border="1" alt="inline image blocked by OWM: $url" $end|);
}

sub _clean_styleimglink {
   my ($url, $end, $blankimgurl) = @_;
   return(qq|url('$blankimgurl')$end|);
}

sub html4attachments {
   # this routine is used to resolve cid or loc in an html message to
   # the cgi openwebmail-viewatt.pl links of cross referenced mime objects
   # this is for read message
   my ($html, $r_attachments, $scripturl, $scriptparm) = @_;

   for (my $i = 0; $i <= $#{$r_attachments}; $i++) {
      my $filename = ow::tool::escapeURL($r_attachments->[$i]{filename});
      my $link = qq|$scripturl/$filename?$scriptparm&amp;attachment_nodeid=$r_attachments->[$i]{nodeid}&amp;|;

      my $cid = $r_attachments->[$i]{'content-id'} || '';
      my $loc = $r_attachments->[$i]{'content-location'} || '';

      $r_attachments->[$i]{referencecount} = 0;

      # replace all the content-id (cid:) occurences
      $r_attachments->[$i]{referencecount}++ if ($cid ne '' && $html =~ s#=['"]*(?:cid:)+\Q$cid\E['"]*#="$link"#sig);

      # replace all the content-location occurences
      $r_attachments->[$i]{referencecount}++ if ($loc ne '' && $html =~ s#=(?:cid:|['"])*\Q$loc\E['"]*#="$link"#sig);

      # ugly hack for strange CID
      if (
            $r_attachments->[$i]{referencecount} == 0
            && $filename ne ''
            &&
              (
                $html =~ s#CID:\{[\d\w\-]+\}/$filename#$link#sig
                || $html =~ s#(background|src)\s*=\s*['"][^\s\<\>"']{0,256}?/$filename['"]#$1="$link"#sig
              )
         ) {
         $r_attachments->[$i]{referencecount}++;
      }
   }

   return $html;
}

sub html4attfiles {
   # this routine is used to resolve cid or loc in a html message to
   # the cgi openwebmail-viewatt.pl links of cross referenced mime objects
   # this is for message composing
   my ($html, $r_attfiles, $scripturl, $scriptparm) = @_;

   for (my $i = 0; $i <= $#{$r_attfiles}; $i++) {
      my $filename = ow::tool::escapeURL($r_attfiles->[$i]{name});
      my $link = qq|$scripturl/$filename?$scriptparm&amp;attfile=$r_attfiles->[$i]{file}&amp;|;

      my $cid = $r_attfiles->[$i]{'content-id'} || '';
      my $loc = $r_attfiles->[$i]{'content-location'} || '';

      $r_attfiles->[$i]{referencecount} = 0;

      # replace all the content-id (cid:) occurences
      $r_attfiles->[$i]{referencecount}++ if ($cid ne '' && $html =~ s#=['"]*(?:cid:)+\Q$cid\E['"]*#="$link"#sig);

      # replace all the content-location occurences
      $r_attfiles->[$i]{referencecount}++ if ($loc ne '' && $html =~ s#=(?:cid:|['"])*\Q$loc\E['"]*#="$link"#sig);

      # ugly hack for strange CID
      if (
            $r_attfiles->[$i]{referencecount} == 0
            && $filename ne ''
            &&
              (
                $html =~ s#CID:\{[\d\w\-]+\}/$filename#$link#sig
                || $html =~ s#(background|src)\s*=\s*['"][^\s\<\>"']{0,256}?/$filename['"]#$1="$link"#sig
              )
         ) {
         $r_attfiles->[$i]{referencecount}++;
      }
   }

   return $html;
}

sub html4attfiles_link2cid {
   # this routine is used to revert links of crossreferenced mime objects
   # back to their cid or loc equivelents. This is the reverse operation
   # of html4attfiles() and is used for message sending
   my ($html, $r_attfiles, $scripturl) = @_;
   $html =~ s#(src|background|href)\s*=\s*(['"]?\Q$scripturl\E/?[^\s<>]*[\w/"'])([\b|\n| ]*)#_link2cid($1,$2,$3, $r_attfiles)#egis;
   return($html);
}

sub _link2cid {
   my ($type, $url, $end, $r_attfiles) = @_;

   for (my $i = 0; $i <= $#{$r_attfiles}; $i++) {
      my $filename    = $r_attfiles->[$i]{name};
      my $attfileparm = "attfile=$r_attfiles->[$i]{file}";
      if ($url =~ m#\Q$attfileparm\E#) {
         $r_attfiles->[$i]{referencecount}++;

         my $cid = "cid:$r_attfiles->[$i]{'content-id'}";
         return(qq|$type="$cid"$end|) if $cid ne 'cid:';

         my $loc = $r_attfiles->[$i]{'content-location'};
         return(qq|$type="$loc"$end|) if $loc;

         # construct strange cid from attserial
         my ($attserial) = $r_attfiles->[$i]{file} =~ m#([\w\d\-]+)$#;
         return(qq|$type="cid:$attserial/$filename"$end|) if $filename;
      }
   }

   return("$type=$url$end");
}

sub html4mailto {
   # this routine changes mailto: links into native composemessage links
   # so that clicking a mailto will launch an internal composemessage session
   # to work with the base directive we use full urls
   # to keep compatibility with undecoded base64 blocks we create the new url
   # as a separated line
   my ($html, $ow_sendurl) = @_;

   $html =~ s/(=\s*"'?)mailto:\s*([^"'>]*?)(["'>])/_mailtoparm($1,$2,$ow_sendurl,$3)/egis;

   return $html;
}

sub _mailtoparm {
   # convert standard mailto links into internal composemessage links
   my ($mailtoprefix, $mailtourl, $ow_sendurl, $mailtosuffix) = @_;

   $mailtourl = '' unless defined $mailtourl;
   $mailtourl =~ s#&amp;#&#g;
   $mailtourl =~ s#\?#&#;
   $mailtourl =~ s#&#&amp;#g;

   return $mailtoprefix . $ow_sendurl . "&amp;to=" . ow::tool::escapeURL($mailtourl) . $mailtosuffix;
}

sub html2table {
   # remove body tags and encapsulate html in a table for message reading
   my $html = _htmlclean(shift);
   $html =~ s#<body([^<>]*?)>#<table cellpadding="2" cellspacing="0" border="0" width="100%" $1><tr><td>#is;
   $html =~ s#</body>#</td></tr></table>#is;
   return $html;
}

sub html2block {
   # remove html body tags for message composing
   my $html = _htmlclean(shift);
   $html =~ s#<body([^<>]*?)>##is;
   $html =~ s#</body>##is;
   return $html;
}

sub _htmlclean {
   my $html = shift;

   $html =~ s#<!doctype[^<>]*?>##is;
   $html =~ s#<html[^<>]*?>##is;
   $html =~ s#</html>##is;
   $html =~ s#<head>.*?</head>##is;
   $html =~ s#<head>##is;
   $html =~ s#</head>##is;
   $html =~ s#<meta[^<>]*?>##gis;
   $html =~ s#<!--.*?-->##gis;
   $html =~ s#<style[^<>]*?>#\n<!-- style begin\n#gis;
   $html =~ s#</style>#\nstyle end -->\n#gis;
   $html =~ s#(<[^<>]*?stylesheet[^<>]*?>)#<!-- stylesheet link removed by OWM: $1 -->#gis;
   $html =~ s#(<[^<>]*?prefetch[^<>]*?>)#<!-- prefetch link removed by OWM: $1 -->#gis;
   $html =~ s#(<div[^<>]*?)position\s*:\s*absolute\s*;([^<>]*?>)#$1$2#gis;
   $html =~ s#(style\s*=\s*['"]?[^"'>]*?)position\s*:\s*absolute\s*;([^"'>]*?['"]?)#$1$2#gis;

   return $html;
}

1;
