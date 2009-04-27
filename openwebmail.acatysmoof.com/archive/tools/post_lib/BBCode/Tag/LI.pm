# $Id: LI.pm 116 2006-01-10 16:41:53Z chronos $
package BBCode::Tag::LI;
use base qw(BBCode::Tag::Simple BBCode::Tag);
use strict;
use warnings;
our $VERSION = '0.22';

sub BodyPermitted($):method {
	return 1;
}

sub BodyTags($):method {
	# Really, should be :LIST :INLINE, but people do strange things...
	return qw(:LIST :BLOCK :INLINE);
}

sub toHTML($):method {
	return shift->SUPER::toHTML(@_)."\n";
}

1;
