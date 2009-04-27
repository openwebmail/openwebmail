# $Id: QUOTE.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::QUOTE;
use base qw(BBCode::Tag::Block);
use BBCode::Util qw(:parse &encodeHTML);
use HTML::Entities;
use strict;
use warnings;
our $VERSION = '0.01';

sub BodyPermitted($):method {
	return 1;
}

sub NamedParams($):method {
	return qw(SRC FOLLOW CITE);
}

sub RequiredParams($):method {
	return ();
}

sub DefaultParam($):method {
	return 'SRC';
}

sub validateParam($):method {
	my($this,$param,$val) = @_;
	if($param eq 'CITE') {
		my $url = parseURL($val);
		if(defined $url) {
			return $url->as_string;
		} else {
			die qq(Invalid value "$val" for [QUOTE CITE]);
		}
	}
	return $this->SUPER::validateParam($param,$val);
}

sub toHTML($):method {
	my $this = shift;
	my $pfx = $this->parser->css_prefix;

	my $who = $this->param('SRC');
	my $cite = $this->param('CITE');
	my $body = $this->bodyHTML;

	$who = (defined $who ? encodeHTML($who).' wrote' : 'quote');
	if(defined $cite) {
		$who =
			'<a href="'.encodeHTML($cite).'"'.
			($this->isFollowed ? '' : ' rel="nofollow"').
			'>'.
			$who.
			'</a>';
	}
	$who .= ':';

#	return
#		qq(<div class="${pfx}quote">\n).
#		qq(<div class="${pfx}quote-head">$who</div>\n).
#		qq(<blockquote class="${pfx}quote-body").(defined $cite ? ' cite="'.encodeHTML($cite).'"' : '').qq(>\n).
#		qq($body\n).
#		qq(</blockquote>\n).
#		qq(</div>\n);
	return
		qq(<br/><br/><b>$who</b><br/>\n).
                qq(<pre).(defined $cite ? ' cite="'.encodeHTML($cite).'"' : '').
                qq( class="quote" width="100%">\n) . encodeHTML($body) . qq(\n</pre>\n);
}

sub toLinkList($;$):method {
	my $this = shift;
	my $ret = @_ ? shift : [];
	my $src = $this->param('SRC');
	my $cite = $this->param('CITE');
	if(defined $cite) {
		push @$ret, [ $this->isFollowed, $this->Tag, $cite, $src ];
	}
	return $this->SUPER::toLinkList($ret);
}

1;
