package ow::mime;
#
# mime.pl - mime words encoding/decoding routines
#
# All functions comes from the Words.pm (author: eryq@zeegee.com)
# in the MIME-tools-6.200_02.tar.gz package.
# http://search.cpan.org/~dskoll/MIME-tools-5.502/lib/MIME/Words.pm
#
# This module requires MIME-Base64 perl module (MIME-Base64-2.12.tar.gz)
# Note: The encoding/decoding speed would be much faster if you install
# MIME-Base64 with XS support
#

use strict;
use warnings FATAL => 'all';

use MIME::Base64;
use MIME::QuotedPrint;
use vars qw($NONPRINT $BIG5CHARS $WORDCHARS);

$NONPRINT  = "\\x00-\\x1F\\x7F-\\xFF";  # Nonprintables (controls + x7F + 8bit):
$BIG5CHARS = "0-9 \\x40-\\xFF";         # char used in big5 words
$WORDCHARS = "a-zA-Z0-9 \\x7F-\\xFF";   # char used in regular words

sub decode_content {
   # decode content based on the provided encoding
   # base64 content is tested to make sure it contains no illegal
   # characters before decoding, since MIME::Base64 does not return
   # error codes or messages on bad decodes based on illegal chars
   my ($content, $encoding) = @_;

   return $content unless defined $content && defined $encoding;

   $encoding =~ m/^quoted-printable/i                               ? return decode_qp($content)     :
   $encoding =~ m/^base64/i && $content !~ m#[^A-Za-z0-9+/=\n\r]#sg ? return decode_base64($content) :
   $encoding =~ m/^x-uuencode/i                                     ? return uudecode($content)      :

   return $content;
}

sub decode_mimewords {
    my $encstr = shift;
    my %params = @_;

    return (wantarray ? () : $encstr) unless defined $encstr;

    my @tokens = ();
    $@ = ''; # error-return

    # Collapse boundaries between adjacent encoded words:
    $encstr =~ s{(\?\=)\s*(\=\?)}{$1$2}gs;
    pos($encstr) = 0;
    # print STDOUT "ENC = [", $encstr, "]\n";

    # Decode:
    my $charset  = '';
    my $encoding = '';
    my $enc      = '';
    my $dec      = '';

    while (1) {
	last if pos($encstr) >= length($encstr);
	my $pos = pos($encstr); # save it

	# Case 1: are we looking at "=?..?..?="?
	if ($encstr =~    m{\G             # from where we left off..
			    =\?([^?]*)     # "=?" + charset +
			     \?([bq])      #  "?" + encoding +
			     \?([^?]+)     #  "?" + data maybe with spcs +
			     \?=           #  "?="
			    }xgi) {
	    ($charset, $encoding, $enc) = ($1, lc($2), $3);
	    $dec = (($encoding eq 'q') ? _decode_Q($enc) : _decode_B($enc));
	    push @tokens, [$dec, $charset];
	    next;
	}

	# Case 2: are we looking at a bad "=?..." prefix?
	# We need this to detect problems for case 3, which stops at "=?":
	pos($encstr) = $pos; # reset the pointer

	if ($encstr =~ m{\G=\?}xg) {
	    $@ .= qq|unterminated "=?..?..?=" in "$encstr" (pos $pos)\n|;
	    push @tokens, ['=?'];
	    next;
	}

	# Case 3: are we looking at ordinary text?
	pos($encstr) = $pos; # reset the pointer
	if ($encstr =~ m{\G                # from where we left off...
			 ([\x00-\xFF]*?    #   shortest possible string,
			  \n*)             #   followed by 0 or more NLs,
		         (?=(\Z|=\?))      # terminated by "=?" or EOS
			}xg) {
	    length($1) or die "mime: empty token";
	    push @tokens, [$1];
	    next;
	}

	# Case 4: bug!
	die "mime: unexpected case:\n($encstr) pos $pos";
    }

    return (wantarray ? @tokens : join('', map { $_->[0] } @tokens));
}

sub encode_mimeword {
    my $word = shift;
    my $encoding = uc(shift || 'Q');
    my $charset  = uc(shift || 'UTF-8');
    my $encfunc  = (($encoding eq 'Q') ? \&_encode_Q : \&_encode_B);
    "=?$charset?$encoding?" . &$encfunc($word) . "?=";
}

sub encode_mimewords {
    my ($rawstr, %params) = @_;

    $rawstr = '' unless defined $rawstr;

    my $charset = $params{Charset} || 'UTF-8';

    # my $encoding = lc($params{Encoding} || 'q');
    # q is used if there are english words in the string
    my $encoding = defined $params{Encoding} && $params{Encoding} ne ''
                   ? lc($params{Encoding})
                   : $rawstr =~ m/[A-Za-z]{4}/ ? 'q' : 'b';

    # determine chars used in a word based on the charset
    my $wordchars = lc($charset) eq 'big5' ? $BIG5CHARS : $WORDCHARS;

    ### Encode any "words" with unsafe characters.
    ### We limit such words to 18 characters, to guarantee that
    ### the worst-case encoding give us no more than 75 characters (rfc2047, section2)
    # 18*3   + ~7+10   < 75  under Q encoding (7 is =? ?Q? ?=, 10 is charsetname)
    # 40/6*8 + ~7+10+3 < 75  under B encoding (7 is =? ?B? ?=, 10 is charsetname, 3 is base64 padding)
    my $maxlen = $encoding eq 'q' ? 18 : 40;

    my $word;
    #$rawstr =~ s{([a-zA-Z0-9\x7F-\xFF]{1,18})}{	### get next "word"
    #$rawstr =~ s{([a-zA-Z0-9 \x7F-\xFF]{1,18})}{	### get next "word" with space encoded
    $rawstr =~ s{([$wordchars]{1,$maxlen})}{		### get next "word"
	$word = $1;
	(($word !~ /[$NONPRINT]/o)
	 ? $word                                                ### no unsafe chars
	 : encode_mimeword($word, $encoding, $charset))         ### has unsafe chars
    }xeg;
    $rawstr =~ s/\?==\?/?= =?/g;                          ### rfc2047

    return $rawstr;
}

# _decode_Q STRING
#     Private: used by _decode_header() to decode "Q" encoding, which is
#     almost, but not exactly, quoted-printable.  :-P
sub _decode_Q {
    my $str = shift;
    $str =~ s/_/\x20/g;                                # RFC-1522, Q rule 2
    $str =~ s/=([\da-fA-F]{2})/pack("C", hex($1))/ge;  # RFC-1522, Q rule 1
    $str;
}

# _encode_Q STRING
#     Private: used by _encode_header() to decode "Q" encoding, which is
#     almost, but not exactly, quoted-printable.  :-P
sub _encode_Q {
    my $str = shift;
    $str =~ s{([_\?\=$NONPRINT])}{sprintf("=%02X", ord($1))}eog;
    $str =~ s/ /_/g;
    $str;
}

# _decode_B STRING
#     Private: used by _decode_header() to decode "B" encoding.
sub _decode_B {
    my $str = shift;
    decode_base64($str);
}

# _encode_B STRING
#     Private: used by _decode_header() to decode "B" encoding.
sub _encode_B {
    my $str = shift;
    encode_base64($str, '');
}

# this is used to decode fileblock generated by uuencode program
sub uudecode ($) {
    local($^W) = 0; # unpack("u",...) gives bogus warning in 5.00[123]
    my $res = "";
    my $line;

    foreach $line ( split(/\n/, $_[0]) ) {	# $_[0] is string to decode
       my $len = substr($line,0,1);
       $line=substr($line,1);
       $res .= unpack("u", $len . $line );	# uudecode
    }
    $res;
}

1;
