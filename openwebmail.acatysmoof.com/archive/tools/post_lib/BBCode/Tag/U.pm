# $Id: U.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::U;
use base qw(BBCode::Tag::Inline);
use strict;
use warnings;
our $VERSION = '0.01';

sub BodyPermitted($):method {
	return 1;
}

sub toHTML($):method {
	my $this = shift;
	my $pfx = $this->parser->css_prefix;
	my $css = $this->parser->css_direct_styles ? qq( style="text-decoration: underline") : "";

	# my $ret = qq(<span class="${pfx}u"$css>);
	my $ret = qq(<u>);
	foreach($this->body) {
		$ret .= $_->toHTML;
	}
	$ret .= '</u>';
	# $ret .= '</span>';
	return $ret;
}

1;
