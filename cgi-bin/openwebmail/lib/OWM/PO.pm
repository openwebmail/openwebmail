package OWM::PO;

use strict;
use warnings;

use vars '$VERSION';
$VERSION = '0.01';

=head1 SYNOPSIS

Pure-perl OO interface to retrieve message strings from PO files without using gettext.

=head1 USAGE

 use PO;

 my $po = PO->read(file => 'it_IT.ISO8859-1.po'); # get the Italian messages
 print $po->msgstr("Translate this");   # returns "Traducelo" (Italian for "Translate this")

 # plurals are also supported:

 my $number_of_friends = 5;
 my $text = $po->msgstr("I have %d friends", $number_of_friends); # returns "Ho %d amici"

 # which you can then properly format using sprintf
 sprintf($text, $number_of_friends); # returns "Ho 5 amici"

=head1 THANKS

Heavily borrowed, but slightly modified, from Mark Overmeer's C<Log::Report::Lexicon::POTcompact>

=head1 AUTHOR

Alex Teslik <alex@acatysmoof.com>

=cut

sub new { &read(@_) }

sub read {
   my ($class, %args) = @_;

   my $self = bless {}, $class;

   my $file = $args{file} || die("No file specified");
   $file = "${file}.po" if (!-e $file && $file !~ m/\.po$/i && -e "${file}.po");

   $self->{filename} = $file;

   my ($last, $msgid, @msgstr);

   open(POFILE, "<$file") || die("Unable to open po file $file: $!");

   while (<POFILE>) {
      next if m/^#/;

      if (m/^\s*$/) {
         # start a new msgid
         if (@msgstr) {
            $self->{index}{$msgid} = @msgstr > 1 ? [@msgstr] : $msgstr[0];
            ($msgid, @msgstr) = ();
         }
         next;
      }

      if (s/^msgid\s+//) {
         $msgid      = _unescape($_);
         $last       = \$msgid;
      } elsif (s/^msgstr\[(\d+)\]\s*//) {
         $msgstr[$1] = _unescape($_);
         $last       = \$msgstr[$1];
      } elsif (s/^msgstr\s+//) {
         $msgstr[0]  = _unescape($_);
         $last       = \$msgstr[0];
      } elsif ($last && m/^\s*\"/) {
         $$last     .= _unescape($_);
      }
   }

   if (scalar @msgstr) {
      # don't forget the last
      $self->{index}{$msgid} = (scalar @msgstr > 1 ? \@msgstr : $msgstr[0]);
   }

   close (POFILE) || die("close failed on file $file");

   for (split(/[\r\n]+/,$self->msgid(''))) {
      $self->{header}{lc($1)} = (defined $2?$2:0) if (m/^([^:]+):\s*([^\n]*?)\;?\s*$/);
   }

   $self->{algorithm} = _plural_algorithm($self->header('plural-forms'));
   $self->{nrplurals} = _nr_plurals($self->header('plural-forms'));

   return $self;
}

sub index     {shift->{index}}

sub filename  {shift->{filename}}

sub nrPlurals {shift->{nrplurals}}

sub algorithm {shift->{algorithm}}

sub header {
   my $self = shift;
   my $key  = lc(shift);
   return $self->{header}{$key} if exists $self->{header}{$key};
}

sub msgid {
   my $self  = shift;
   my $msgid = shift;
   return $self->{index}{$msgid};
}

sub msgstr {
   my $self  = shift;
   my $msgid = shift;
   my $count = shift;
   my $po = $self->{index}{$msgid} or return undef;

   # no plurals defined
   ref $po or return $po;

   return ($po->[$self->{algorithm}->(defined $count ? $count : 1)] || $po->[$self->{algorithm}->(1)]);
}

sub _plural_algorithm {
   my $plural_forms = shift || '';
   my $algorithm = $plural_forms =~ m/plural\=([n%!=><\s\d|&?:()]+)/ ? $1 : "n!=1";
   $algorithm =~ s/\bn\b/(\$_[0])/g;
   my $code  = eval "sub {$algorithm}";
   die("invalid plural-form algorithm $algorithm") if ($@);
   return $code;
}

sub _nr_plurals {
   my $plural_forms = shift || '';
   $plural_forms =~ m/\bnplurals\=(\d+)/ ? $1 : 2;
}

sub _unescape {
   my $text = shift;
   unless( $text =~ m/^\s*\"(.*)\"\s*$/ ) {
      warn("string '$text' not between quotes");
      return $text;
   }
   return unescape_chars($1);
}

my %unescape = (
                  '\a'   => "\a",
                  '\b'   => "\b",
                  '\f'   => "\f",
                  '\n'   => "\n",
                  '\r'   => "\r",
                  '\t'   => "\t",
                  '\"'   => '"',
                  '\\\\' => '\\' ,
                  '\e'   => "\x1b",
                  '\v'   => "\x0b"
               );

sub unescape_chars {
   my $str = shift;
   $str =~ s/(\\.)/$unescape{$1} || $1/ge;
   return $str;
}

1;
