# $Id: IMG.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::IMG;
use base qw(BBCode::Tag::Inline);
use BBCode::Util qw(:parse encodeHTML);
use strict;
use warnings;
our $VERSION = '0.01';

sub BodyPermitted($):method {
	return 0;
}

sub NamedParams($):method {
	return qw(SRC ALT W H);
}

sub RequiredParams($):method {
	return qw(SRC);
}

sub DefaultParam($):method {
	return 'SRC';
}

sub validateParam($$$):method {
	my($this,$param,$val) = @_;
	if($param eq 'SRC') {
		my $url = parseURL($val);
		if(defined $url) {
			return $url->as_string;
		} else {
			die qq(Invalid value "$val" for [IMG]);
		}
	}
	if($param eq 'W' or $param eq 'H') {
		return parseNum $val;
	}
	return $this->SUPER::validateParam($param,$val);
}

my %pmap = (SRC => 'src', ALT => 'alt', W => 'width', H => 'height');
sub toHTML($):method {
	my $this = shift;
	my $ret = '<img';
	my @p = $this->params;
	while(@p) {
		my($k,$v) = splice @p, 0, 2;
		$k = $pmap{$k} if exists $pmap{$k};
		$ret .= sprintf ' %s="%s"', $k, encodeHTML($v);
	}
	$ret .= ' />';
	return $ret;
}

sub toLinkList($;$):method {
	my $this = shift;
	my $ret = @_ ? shift : [];
	push @$ret, [ 1, $this->Tag, $this->param('SRC'), $this->param('ALT') ];
	return $this->SUPER::toLinkList($ret);
}

1;
