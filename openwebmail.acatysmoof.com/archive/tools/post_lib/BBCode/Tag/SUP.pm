# $Id: SUP.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::SUP;
use base qw(BBCode::Tag::Simple BBCode::Tag::Inline);
use strict;
use warnings;
our $VERSION = '0.01';

sub BodyPermitted($):method {
	return 1;
}

1;
