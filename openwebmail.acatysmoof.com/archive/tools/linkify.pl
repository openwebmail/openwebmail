##---------------------------------------------------------------------------##
##  File:
##      linkify.pl
##  Author:
##      Alex Teslik <alex@acatysmoof.com>
##      -modified from the OpenWebMail Project htmltext.pl
##  Description:
##	Library defines filter routine to convert FQDN or URLs to links
##      for MHonArc, unless they are already linked with <a> tags.
##	Filter routine can be registered with the following:
##	    <MIMEFILTERS>
##	    text/html; linkify::filter; linkify.pl
##	    </MIMEFILTERS>

##  ALEX: put this file at /usr/local/share/MHonArc


##---------------------------------------------------------------------------##
##    MHonArc -- Internet mail-to-HTML converter
##    Copyright (C) 1995-2000	Earl Hood, mhonarc@mhonarc.org
##
##    This program is free software; you can redistribute it and/or modify
##    it under the terms of the GNU General Public License as published by
##    the Free Software Foundation; either version 2 of the License, or
##    (at your option) any later version.
##
##    This program is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##    GNU General Public License for more details.
##
##    You should have received a copy of the GNU General Public License
##    along with this program; if not, write to the Free Software
##    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
##---------------------------------------------------------------------------##


package linkify;

##---------------------------------------------------------------------------
##	This filter converts FQDNs and URLs into actual links. Convenient for
##      those times when lazy writers don't make their URLs actual links.
##
##	Arguments:
##
##      None

sub filter {
    my($fields, $data, $isdecode, $args) = @_;
    $args = ''  unless defined $args;

    # convert url or FQDN to link
    $$data=~s#(?<![="])(https?|ftp|mms|nntp|news|gopher|telnet)://([\w\d\-\.]+?/?[^\s\(\)\<\>\x80-\xFF]*[\w/])([\b|\n| ]*)#<a href="$1://$2" target="_blank">$1://$2</a>$3#igs;
    $$data=~s!([\b|\n| ]+)(www\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)!$1<a href="http://$2" target="_blank">$2</a>$3!igs;
    $$data=~s!([\b|\n| ]+)(ftp\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)!$1<a href="ftp://$2" target="_blank">$2</a>$3!igs;

    ($$data);
}

1;


