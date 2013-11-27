#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(:config auto_abbrev);
use File::Basename;
use Locale::PO;

use vars qw($VERSION $PROGRAM);

$VERSION = '20100829';
$PROGRAM = File::Basename::basename($0,(qw(.pl .exe)));

use vars qw($opt);

#=========================
# Set Default User Options
#=========================
$opt->{files}  = undef;
$opt->{output} = undef;
$opt->{help}   = undef;

#=====================================================
# Override default options with user-specified options
#=====================================================
my $result = GetOptions(
                          'files=s{,}' => \@{$opt->{files}},  # {,} = one or more arguments
                          'output=s'   => \$opt->{output},
                          'help'       => \&help,
                       );

if ($result == 0) {
   print "The command line could not be processed properly.\n";
   print "Please run '$PROGRAM -help' for usage information.\n\n";
   exit 1;
}

my @not_files = grep { !-f $_ } @{$opt->{files}};
die("The following are not files:\n" . join("\n", @not_files) . "\n") if scalar @not_files;
die("The output file must be defined\n") unless defined $opt->{output} && $opt->{output};
die("The output file must end with a .pot extension\n") if $opt->{output} !~ m/\.pot$/i;
die("The output file already exists\n") if -f $opt->{output};

my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = gmtime(time);
$year += 1900;
my $datestring = sprintf('%04d-%02d-%02d %02d:%02d+0000', $year, $month + 1, $mday, $hour, $min);

my $pot = {};

$pot->{''} = new Locale::PO(
                              -msgid  => '',
                              -msgstr => "Project-Id-Version: OpenWebMail\\n" .
                                         "POT-Creation-Date: $datestring\\n" .
                                         "Last-Translator: OpenWebMail Team <openwebmail\@acatysmoof.com>\\n" .
                                         "Language-Team: OpenWebMail Team <openwebmail\@acatysmoof.com>\\n" .
                                         "MIME-Version: 1.0\\n" .
                                         "Content-Type: text/plain; charset=utf-8\\n" .
                                         "Content-Transfer-Encoding: 8bit\\n" .
                                         "Plural-Forms: nplurals=2; plural=n != 1;\\n" .
                                         "X-Poedit-SourceCharset: utf-8\\n"
                           );

my $msgids = {};

foreach my $file (@{$opt->{files}}) {
   die "Argument $file is not a file" unless -f $file;

   print "Processing file $file.....\n";

   open(FILE, "<$file") || die "Cannot open file $file :: $!";

   while(my $line = <FILE>) {
      # $line =~ s/\\'/'/; # unquote ' characters
      # push(@{$msgids->{singulars}{$1}}, ($file . ':' . $.)) while $line =~ m#(?<!n)gettext\(["'](.+?)["']\)#ig;
      while ($line =~ m/ngettext\('([^']+)', *'([^']+)', *[^)]+\)/ig) {
         # plurals
         $msgids->{plurals}{"$1$2"}{singular} = $1;
         $msgids->{plurals}{"$1$2"}{plural}   = $2;
         push(@{$msgids->{plurals}{"$1$2"}{references}}, ($file . ':' . $.));
      }

      while ($line =~ m#(?<!n)gettext\(["'](.+?)["']\)#ig) {
         # singular
         push(@{$msgids->{singulars}{$1}}, ($file . ':' . $.));
      }
   }

   close(FILE) || die "Cannot close file $file :: $!";
}

$pot->{$_} = new Locale::PO(
                              -msgid     => $_,
                              -msgstr    => '',
                              -reference => join(', ', sort @{$msgids->{singulars}{$_}}),
                           ) for keys %{$msgids->{singulars}};

$pot->{$_} = new Locale::PO(
                              -msgid        => $msgids->{plurals}{$_}{singular},
                              -msgid_plural => $msgids->{plurals}{$_}{plural},
                              -msgstr_n     => {
                                                  0 => '',
                                                  1 => '',
                                               },
                              -reference    => join(', ', sort @{$msgids->{plurals}{$_}{references}}),
                           ) for keys %{$msgids->{plurals}};

Locale::PO->save_file_fromhash($opt->{output}, $pot);

print "POT file $opt->{output} was generated.\n";

sub help {
   if (eval 'require Pod::Text') {
      my $parser = Pod::Text->new(
                                   sentence => 0,
                                   width    => 90,
                                   margin   => 3,
                                 );
      $parser->parse_from_file($0);
   } else {
      die("Showing help requires the Pod::Text module, which cannot be found: $@");
   }

   exit 0;
}

=pod

=head1 NAME

owm-xgettext

=head1 SYNOPSIS

Extracts message id strings from text files and outputs a POT file

=head1 DESCRIPTION

A POT file is a PO Template - a file that contains plain text message id strings that are to be later translated into other languages.

This program extracts strings from text files such as html template files (tmpl) and perl source code (pl) and generates a GNU gettext compatible POT file, much in the same way as the GNU xgettext utility extracts message id strings from files written in other programming languages. The GNU xgettext utility does not process HTML files or javascript, so this simple script was created as an alternative.

Message strings contained in the input text files are expected to be identified by the following syntax:

gettext('Some string inside single quotes to be translated')

ngettext('singular string %d', 'plural string %d', $number)

The text files to be processed are expected to be written in English in the UTF8, ISO8859-1, or ASCII character sets. Other character sets will likely fail.

=head1 OPTIONS

Any option below can be included more than once on the commandline. Any option can be abbreviated to its minimum uniqueness.

=over 4

=item files (required)

A file or files to process

=item output (required)

The name of the POT file to create. It must end with a .pot extension.

=item help

This help file

=back

=head1 USAGE

owm-xgettext -files <files_to_process> -output owm.pot

owm-xgettext -f <files_to_process> -o owm.pot

=cut

