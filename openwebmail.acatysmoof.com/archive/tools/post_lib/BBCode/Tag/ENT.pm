# $Id: ENT.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::ENT;
use base qw(BBCode::Tag);
use BBCode::Util qw(:parse);
use strict;
use warnings;
our $VERSION = '0.01';

sub Class($):method {
	return qw(TEXT INLINE);
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
		my $ent = parseEntity($val);
		if(defined $ent) {
			return $ent;
		} else {
			die qq(Invalid value "$val" for [ENT]);
		}
	}
	return $this->SUPER::validateParam($param,$val);
}

sub toHTML($):method {
	my $this = shift;
	my $ent = $this->param('VAL');
	return "&$ent;" if defined $ent;
	return "";
}

1;
