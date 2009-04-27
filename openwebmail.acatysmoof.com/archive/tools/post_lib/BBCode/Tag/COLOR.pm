# $Id: COLOR.pm 82 2005-08-26 09:22:17Z chronos $
package BBCode::Tag::COLOR;
use base qw(BBCode::Tag::Inline);
use BBCode::Util qw(:parse encodeHTML);
use strict;
use warnings;
our $VERSION = '0.02';

sub BodyPermitted($):method {
	return 1;
}

sub NamedParams($):method {
	return qw(VAL);
}

sub DefaultParam($):method {
	return 'VAL';
}

sub validateParam($$$):method {
	my($this,$param,$val) = @_;

	if($param eq 'VAL') {
		my $color = parseColor($val);
		if(defined $color) {
			return $color;
		} else {
			die qq(Invalid value "$val" for [COLOR]);
		}
	}
	return $this->SUPER::validateParam($param,$val);
}

sub replace($):method {
	my $this = shift;
	my $that = BBCode::Tag->new($this->parser, 'FONT', [ 'COLOR', $this->param('VAL') ]);
	$that->pushBody($this->body);
	return $that;
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
