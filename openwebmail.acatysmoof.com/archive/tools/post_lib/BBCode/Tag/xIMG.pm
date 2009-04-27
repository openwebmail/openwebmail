# $Id: xIMG.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::xIMG;
use base qw(BBCode::Tag::Inline);
use BBCode::Util qw(:parse :encode :text);
use strict;
use warnings;
our $VERSION = '0.01';

sub Tag($):method {
	return 'IMG';
}

sub BodyPermitted($):method {
	return 1;
}

sub replace($):method {
	my $this = shift;
	my $text = $this->bodyHTML;
	my $url = parseURL decodeHTML $text;

	if(defined $url) {
		return BBCode::Tag->new(
			$this->parser,
			'IMG',
			[ undef, $url->as_string ],
			[ 'ALT', textALT($url) ],
		);
	} else {
		return BBCode::Tag->new($this->parser, 'TEXT', [ undef, $text ]);
	}
}

sub toBBCode($):method {
	return shift->replace->toBBCode;
}

sub toHTML($):method {
	return shift->replace->toHTML;
}

sub toLinkList($):method {
	return shift->replace->toLinkList;
}

1;
