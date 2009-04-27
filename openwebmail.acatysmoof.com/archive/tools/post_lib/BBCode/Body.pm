# $Id: Body.pm 86 2005-08-27 10:39:44Z chronos $
package BBCode::Body;
use base qw(BBCode::Tag);
use BBCode::Tag::Block;
use HTML::Entities;
use strict;
use warnings;
our $VERSION = '0.20';

sub new($@):method {
	return shift->_create(@_);
}

sub Tag($):method {
	return 'BODY';
}

sub BodyPermitted($):method {
	return 1;
}

sub BodyTags($):method {
	return qw(:ALL BODY);
}

sub bodyHTML($):method {
	return BBCode::Tag::Block::bodyHTML(shift);
}

sub toBBCode($):method {
	my $this = shift;
	my $ret = "";
	foreach($this->body) {
		$ret .= $_->toBBCode;
	}
	return $ret;
}

sub toHTML($):method {
	my $this = shift;
	my $pfx = $this->parser->css_prefix;
	my $body = $this->bodyHTML;
#	return qq(<div class="${pfx}body">\n$body\n</div>\n);
	return qq(\n).decode_entities($body).qq(\n);
}

1;
