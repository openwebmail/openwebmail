# $Id: EMAIL.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::EMAIL;
use base qw(BBCode::Tag);
use BBCode::Util qw(:parse encodeHTML);
use strict;
use warnings;
our $VERSION = '0.01';

sub Class($):method {
	return qw(LINK INLINE);
}

sub BodyPermitted($):method {
	return 1;
}

sub BodyTags($):method {
	return qw(:INLINE !:LINK);
}

sub NamedParams($):method {
	return qw(HREF);
}

sub DefaultParam($):method {
	return 'HREF';
}

sub validateParam($$$):method {
	my($this,$param,$val) = @_;

	if($param eq 'HREF') {
		my $url = parseMailURL($val);
		if(defined $url) {
			return $url->to;
		} else {
			die qq(Invalid value "$val" for [EMAIL]);
		}
	}
	return $this->SUPER::validateParam($param,$val);
}

sub toHTML($):method {
	my $this = shift;
	my $ret = '<a href="mailto:'.encodeHTML($this->param('HREF')).'">';
	foreach($this->body) {
		$ret .= $_->toHTML;
	}
	$ret .= '</a>';

	return $ret;
}

sub toLinkList($;$):method {
	my $this = shift;
	my $ret = @_ ? shift : [];
	push @$ret, [ $this->isFollowed, $this->Tag, $this->param('HREF'), $this->bodyHTML ];
	return $this->SUPER::toLinkList($ret);
}

1;
