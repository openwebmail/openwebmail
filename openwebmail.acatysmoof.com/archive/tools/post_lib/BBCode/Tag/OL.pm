# $Id: OL.pm 79 2005-08-26 04:04:10Z chronos $
package BBCode::Tag::OL;
use base qw(BBCode::Tag::LIST);
use strict;
use warnings;
our $VERSION = '0.01';

sub ListDefault($):method {
	return qw(ol);
}

1;
