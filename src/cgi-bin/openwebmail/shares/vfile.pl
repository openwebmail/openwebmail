# vfile.pl - read vFile, determine vFile data type, load type parser,
#            pass file to parser, return hash of data
#
# Author: Alex Teslik <alex@acatysmoof.com>
#
# Versions:
# 20040325 - Initial version.

use strict;
use Fcntl qw(:DEFAULT :flock);
#use CGI::Carp qw(fatalsToBrowser carpout);
#use Text::Iconv;	# let caller do this, as Text::Icon may be unavailable on some platform

require "modules/filelock.pl";	# openwebmail filelocking routines
require "shares/iconv.pl";	# openwebmail iconv routines

use vars qw($vfiledebug %supported_parsers %prefs);

$vfiledebug = 0;
print header() . "<pre>" if $vfiledebug;

my %supported_parsers = (
                         'vcard'       => [    'vcard.pl' ,\&parsevcard     ,\&outputvcard],
                         # NOT SUPPORTED...YET
                         # 'vcal'      => [     'vcal.pl' ,\&parsevcal      ,\&outputvcal],
                         # 'vevent'    => [   'vevent.pl' ,\&parsevevent    ,\&outputvevent],
                         # 'vtodo'     => [    'vtodo.pl' ,\&parsevtodo     ,\&outputvtodo],
                         # 'vjournal'  => [ 'vjournal.pl' ,\&parsevjournal  ,\&outputvjournal],
                         # 'vfreebusy' => ['vfreebusy.pl' ,\&parsevfreebusy ,\&outputvfreebusy],
                         # 'vtimezone' => ['vtimezone.pl' ,\&parsevtimezone ,\&outputvtimezone],
                        );


sub readvfilesfromfile {
   # This is a base function for extracting vFile objects from a file. It goes line
   # by line through a file and passes each vFile it finds to the appropriate parser
   # handler for that vFile type. It does some basic cleaning up of the vFile before
   # passing it to its parser handler. A vFile object starts with a BEGIN block and
   # ends with an END block. The BEGIN block value determines which parser the
   # complete vFile object is passed to for further processing. The parser should
   # populate the hashref that is passed to it with a data structure representing
   # the vfile object. If no parser is available for the vFile object type defined
   # in the BEGIN block then we don't know how to further parse the data and -1 is
   # returned to the caller. If no vFile object type is detected (the file has no
   # vFile data in it at all) then -1 is returned to the caller.
   my ($vFile, $r_searchtermshash, $r_onlyreturn) = @_;

   return if (-s "$vFile" == 0);

   ow::filelock::lock($vFile, LOCK_EX|LOCK_NB) or croak("Couldnt lock $vFile for write");
   sysopen(VFILE, $vFile, O_RDONLY) or croak("I can't open $vFile<br>\n");

   my $depth = 0;
   my ($vcontents, $vtype, $vversion, %allparsedvobjects, $beginvfile);

   print "I am in readvfilesfromfile subroutine.<br><br>\n\n" if $vfiledebug;

   # Parse the vFile and pass it to the parser if it is valid.
   while (<VFILE>) {
      if (m/^(?:\s+)?$/) {
         print "Skipping line:\"$_\"\n" if $vfiledebug;
         next; # skip blank lines
      }

      my $currentline = $_;
      print "readvfilesfromfile: reading line:\"$currentline\"\n" if $vfiledebug;

      $currentline = decodeUTF($currentline);

      # Standardize CRLF,LF,and CR into CRLF
      $currentline =~ s/\r\n/\@\@\@/g;
      $currentline =~ s/\r/\@\@\@/g;
      $currentline =~ s/\n/\@\@\@/g;
      $currentline =~ s/\@\@\@/\r\n/g;

      print "readvfilesfromfile after UTF: reading line:\"$currentline\"\n" if $vfiledebug;

      # No whitespace in front of BEGIN END or VERSION lines
      # This is not to spec, but it fixes a lot more vFiles
      # in the wild than it breaks.
      # BUT IT BREAKS AGENTS WHERE END OR BEGIN GET WRAPPED
      # $currentline =~ s/^\s+(BEGIN:|END:|VERSION:)/$1/i;

      # A special case for vCards:
      # Fix AGENT on same line as BEGIN block when rest of AGENT is not on
      # the same line. This is out of 2.1 spec, but they're out there.
      # vCard 2.1 example  vCard 2.1 example 2  vCard 3.0 example (literal '\n')
      # -----------------  -------------------  --------------------------------
      # AGENT:             AGENT:BEGIN:VCARD    AGENT:BEGIN:VCARD\nFN:John Doe
      # BEGIN:VCARD        FN:John Doe
      # FN:John Doe
      if ($currentline =~ m/^(?:\s+)?AGENT:(?:.*)?BEGIN:/i) {
         unless ($currentline =~ m/\\n/i) { # don't do it to version 3.0 AGENTs
            $currentline =~ s/AGENT:(?:.*)?BEGIN:/AGENT:\nBEGIN:/i;
            $depth++;
         }
      }

      if ($currentline =~ m/^BEGIN:/i) {
         $beginvfile = 1;
         my $linefeeds = $currentline =~ tr/\r/\r/;
         if ($linefeeds > 1) {
            print "$linefeeds LF detected. Must be a single string vFile. Passing line to readvfilesfromstring...\n" if $vfiledebug;
            my $r_fromstring = readvfilesfromstring($currentline, $r_searchtermshash, $r_onlyreturn);
            $allparsedvobjects{$_} = ${$r_fromstring}{$_} for (keys %{$r_fromstring});
         } else {
            $currentline =~ s/^BEGIN:(?:\s+)?(\S+)(?:\s+)?$/BEGIN:$1\r\n/i;
            $depth++;
            print " ----- Bdepth: $depth\n" if $vfiledebug;
            $vtype = lc $1 unless defined $vtype;
            $vcontents .= $currentline if $depth > 0;
         }
      } elsif ($currentline =~ m/^VERSION:/i) {
         $currentline =~ s/^VERSION:(?:\s+)?(\S+)(?:\s+)?$/VERSION:$1\r\n/i;
         $vversion = $1 unless defined $vversion;
         print " ----- Vdepth: $depth $vversion\n" if $vfiledebug;
         $vcontents .= $currentline if $depth > 0;
      } elsif ($currentline =~ m/^END:/i) {
         $currentline =~ s/^END:(?:\s+)?(\S+)(?:\s+)?$/END:$1\r\n/i;
         $vcontents .= $currentline if $depth > 0;
         next if length($1) > 10; # an agent END happened to get wrapped to the front of the line
         $depth--;
         print " ----- Edepth: $depth\n" if $vfiledebug;
         my $vendtype = lc $1;
         if ($depth == 0) {
            if ($vendtype == $vtype) {
               if (defined $vversion) {
                  # The end of the object we've been parsing.
                  # Send it to a parser for further handling.
                  print "\nThe vFile type is $vtype\n" if $vfiledebug;
                  if (defined $supported_parsers{$vtype}) {
                     # load the parser
                     print "\nvcontents:\n\"$vcontents\"\n" if $vfiledebug;
                     print "\nversion:\n\"$vversion\"\n" if $vfiledebug;
                     eval {require "shares/$supported_parsers{$vtype}[0]"};
                     croak("Cannot load the shares/$supported_parsers{$vtype}[0] module. $@\n") if $@;

                     my $r_parsedvobject = $supported_parsers{$vtype}[1]->($vcontents,$vversion,$r_onlyreturn);
                     foreach my $objectid (keys %{$r_parsedvobject}) {
                        if (defined $r_searchtermshash &&	# avoid changing the stru of $r_searchtermhash carefully, tung
                            defined ${$r_searchtermshash}{'X-OWM-CHARSET'} &&
                            defined ${$r_searchtermshash}{'X-OWM-CHARSET'}[0]{VALUE}) {
                           my $r_clone=entry_clone_iconv(${$r_searchtermshash}{'X-OWM-CHARSET'}[0]{VALUE},		# keyword charset
                                                         ${$r_parsedvobject}{$objectid}{'X-OWM-CHARSET'}[0]{VALUE},	# abook record charset
                                                         $r_searchtermshash);
                           if (is_entry_matched(\%{$r_parsedvobject->{$objectid}}, $r_clone)) {
                              $allparsedvobjects{$objectid} = ${$r_parsedvobject}{$objectid};
                           }
                        } else {
                           if (is_entry_matched(\%{$r_parsedvobject->{$objectid}}, $r_searchtermshash)) {
                              $allparsedvobjects{$objectid} = ${$r_parsedvobject}{$objectid};
                           }
                        }
                     }
                     ($vcontents, $vtype, $vversion) = (); # clear
                  } else {
                     print "\nvcontents croak:\n$vcontents\n" if $vfiledebug;
                     croak("vFile objects of type \"$vtype\" are not supported yet.\n");
                  }
               } else {
                  croak("vFile object does not have a defined version number. Invalid vFile object.\n");
               }
            } else {
               croak("vFile object begin and end types don't match. Invalid vFile object.\n");
            }
         }
      } else {
         print " ----- depth: $depth\n" if $vfiledebug;
         $vcontents .= $currentline if $depth > 0;
      }
   }

   print "\nand thats the end of the readvfilesfromfile sub.\n" if $vfiledebug;

   # croak these for now. Change to return -1 after testing is complete.
   croak("Invalid vFile \"$vFile\": detected number of BEGIN and END blocks are not equal.\n") if $depth != 0;
   croak("Invalid vFile \"$vFile\": No valid BEGIN blocks found.\n") if $beginvfile eq undef;

   close(VFILE) || croak("Can't close filehandle VFILE");
   ow::filelock::lock($vFile, LOCK_UN);

   return (\%allparsedvobjects);
}

sub readvfilesfromstring {
   # This is a base function for extracting vFile objects from a string.
   my ($vFile, $r_searchtermshash, $r_onlyreturn) = @_;

   my $depth = 0;
   my ($vcontents, $vtype, $vversion, %allparsedvobjects, $beginvfile);

   print "I am in readvfilesfromSTRING subroutine.<br><br>\n\n" if $vfiledebug;

   $vFile = decodeUTF($vFile);

   # Standardize CRLF,LF,and CR into CRLF
   $vFile =~ s/\r\n/\@\@\@/g;
   $vFile =~ s/\r/\@\@\@/g;
   $vFile =~ s/\n/\@\@\@/g;
   $vFile =~ s/\@\@\@/\r\n/g;
   print "\nFormatted vFile:\"$vFile\"\n" if $vfiledebug;

   # Parse the vFile and pass it to the parser if it is valid.
   for (split(/\r\n/,$vFile)) {
      if (m/^(?:\s+)?$/) {
         print "Skipping line:\"$_\"\n" if $vfiledebug;
         next; # skip blank lines
      }

      my $currentline = "$_\r\n";
      print "readvfilesfromSTRING: reading line:\"$currentline\"\n" if $vfiledebug;

      $currentline = decodeUTF($currentline);

      # Standardize CRLF,LF,and CR into CRLF
      $currentline =~ s/\r\n/\@\@\@/g;
      $currentline =~ s/\r/\@\@\@/g;
      $currentline =~ s/\n/\@\@\@/g;
      $currentline =~ s/\@\@\@/\r\n/g;

      print "readvfilesfromSTRING after UTF: reading line:\"$currentline\"\n" if $vfiledebug;

      # No whitespace in front of BEGIN END or VERSION lines
      # This is not to spec, but it fixes a lot more vFiles
      # in the wild than it breaks.
      # BUT IT BREAKS AGENTS WHERE END OR BEGIN GET WRAPPED
      # $currentline =~ s/^\s+(BEGIN:|END:|VERSION:)/$1/i;

      # A special case for vCards:
      # Fix AGENT on same line as BEGIN block when rest of AGENT is not on
      # the same line. This is out of 2.1 spec, but they're out there.
      # vCard 2.1 example  vCard 2.1 example 2  vCard 3.0 example (literal '\n')
      # -----------------  -------------------  --------------------------------
      # AGENT:             AGENT:BEGIN:VCARD    AGENT:BEGIN:VCARD\nFN:John Doe
      # BEGIN:VCARD        FN:John Doe
      # FN:John Doe
      if ($currentline =~ m/^(?:\s+)?AGENT:(?:.*)?BEGIN:/i) {
         unless ($currentline =~ m/\\n/i) { # don't do it to version 3.0 AGENTs
            $currentline =~ s/AGENT:(?:.*)?BEGIN:/AGENT:\nBEGIN:/i;
            $depth++;
         }
      }

      if ($currentline =~ m/^BEGIN:/i) {
         $beginvfile = 1;
         my $linefeeds = $currentline =~ tr/\r/\r/;
         if ($linefeeds > 1) {
            print "$linefeeds LF detected. Must be a single string vFile. Passing line to readvfilesfromstring...\n" if $vfiledebug;
            my $r_fromstring = readvfilesfromstring($currentline, $r_searchtermshash, $r_onlyreturn);
            $allparsedvobjects{$_} = ${$r_fromstring}{$_} for (keys %{$r_fromstring});
         } else {
            $currentline =~ s/^BEGIN:(?:\s+)?(\S+)(?:\s+)?$/BEGIN:$1\r\n/i;
            $depth++;
            print " ----- Bdepth: $depth\n" if $vfiledebug;
            $vtype = lc $1 unless defined $vtype;
            $vcontents .= $currentline if $depth > 0;
         }
      } elsif ($currentline =~ m/^VERSION:/i) {
         $currentline =~ s/^VERSION:(?:\s+)?(\S+)(?:\s+)?$/VERSION:$1\r\n/i;
         $vversion = $1 unless defined $vversion;
         print " ----- Vdepth: $depth $vversion\n" if $vfiledebug;
         $vcontents .= $currentline if $depth > 0;
      } elsif ($currentline =~ m/^END:/i) {
         $currentline =~ s/^END:(?:\s+)?(\S+)(?:\s+)?$/END:$1\r\n/i;
         $vcontents .= $currentline if $depth > 0;
         next if length($1) > 10; # an agent END happened to get wrapped to the front of the line
         $depth--;
         print " ----- Edepth: $depth\n" if $vfiledebug;
         my $vendtype = lc $1;
         if ($depth == 0) {
            if ($vendtype == $vtype) {
               if (defined $vversion) {
                  # The end of the object we've been parsing.
                  # Send it to a parser for further handling.
                  print "\nThe vFile type is $vtype\n" if $vfiledebug;
                  if (defined $supported_parsers{$vtype}) {
                     # load the parser
                     print "\nvcontents:\n\"$vcontents\"\n" if $vfiledebug;
                     print "\nversion:\n\"$vversion\"\n" if $vfiledebug;
                     eval {require "shares/$supported_parsers{$vtype}[0]"};
                     croak("Cannot load the shares/$supported_parsers{$vtype}[0] module. $@\n") if $@;

                     my $r_parsedvobject = $supported_parsers{$vtype}[1]->($vcontents,$vversion,$r_onlyreturn);
                     foreach my $objectid (keys %{$r_parsedvobject}) {
                        if (defined $r_searchtermshash &&	# avoid changing the stru of $r_searchtermhash carefully, tung
                            defined ${$r_searchtermshash}{'X-OWM-CHARSET'} &&
                            defined ${$r_searchtermshash}{'X-OWM-CHARSET'}[0]{VALUE}) {
                           my $r_clone=entry_clone_iconv(${$r_searchtermshash}{'X-OWM-CHARSET'}[0]{VALUE},		# keyword charset
                                                         ${$r_parsedvobject}{$objectid}{'X-OWM-CHARSET'}[0]{VALUE},	# abook record charset
                                                         $r_searchtermshash);
                           if (is_entry_matched(\%{$r_parsedvobject->{$objectid}}, $r_clone)) {
                              $allparsedvobjects{$objectid} = ${$r_parsedvobject}{$objectid};
                           }
                        } else {
                           if (is_entry_matched(\%{$r_parsedvobject->{$objectid}}, $r_searchtermshash)) {
                              $allparsedvobjects{$objectid} = ${$r_parsedvobject}{$objectid};
                           }
                        }
                     }
                     ($vcontents, $vtype, $vversion) = (); # clear
                  } else {
                     print "\nvcontents croak:\n$vcontents\n" if $vfiledebug;
                     croak("vFile objects of type \"$vtype\" are not supported yet.\n");
                  }
               } else {
                  croak("vFile object does not have a defined version number. Invalid vFile object.\n");
               }
            } else {
               croak("vFile object begin and end types don't match. Invalid vFile object.\n");
            }
         }
      } else {
         print " ----- depth: $depth\n" if $vfiledebug;
         $vcontents .= $currentline if $depth > 0;
      }
   }

   print "\nand thats the end of the readvfilesfromSTRING sub.\n" if $vfiledebug;

   croak("Invalid vFile \"$vFile\": detected number of BEGIN and END blocks are not equal.\n") if $depth != 0;
   croak("Invalid vFile \"$vFile\": No valid BEGIN blocks found.\n") if $beginvfile eq undef;

   return (\%allparsedvobjects);
}

sub outputvfile {
   my ($outputtype, $r_data, $version, $r_exclude_propertynames) = @_;
   my $outputtext='';
   if (defined $supported_parsers{$outputtype}[2]) {
      # load the parser
      eval {require "shares/$supported_parsers{$outputtype}[0]"};
      croak("Cannot load the shares/$supported_parsers{$outputtype}[0] module. $@\n") if $@;

      $outputtext = $supported_parsers{$outputtype}[2]->($r_data, $version, $r_exclude_propertynames);
   } else {
      croak("Output type \"$outputtype\" is not supported at this time\n");
   }
   return $outputtext;
}

sub decodeUTF {
   # UTF-16/32 detection and conversion
   # Apple's iChat saves vcards in UTF-16BE. Grrr.
   # Read http://www.unicode.org/unicode/faq/utf_bom.html
   # Text::Iconv is required to already have been loaded.
   my ($chars) = @_;
   return unless defined $chars;
   return $chars if (!defined $INC{'Text/Iconv.pm'});	# Text::Iconv.pm not loaded

   print "converting chars: $chars\n" if $vfiledebug;
   my ($format, $converter, $newchars);
   if ($chars =~ m/\x00/s) {
      # strip all byte order markers
      $chars =~ s/\x00\x00\xFE\xFF//s; # UTF-32BE
      $chars =~ s/\xFF\xFE\x00\x00//s; # UTF-32LE
      $chars =~ s/\xFE\xFF//s;         # UTF-16BE
      $chars =~ s/\xFF\xFE//s;         # UTF-16LE
      $chars =~ s/\xEF\xBB\xBF//s;     # UTF-8

      print "BOM stripped chars: $chars\n" if $vfiledebug;

      if ($chars =~ m/\x00\x00\x00/s) {
         if ($chars =~ m/^\x00/s) {
            $format="UTF-32BE";
         } else {
            $format="UTF-32LE";
         }
      } else {
         if ($chars =~ /^\x00/s) {
            $format="UTF-16BE";
         } else {
            $format="UTF-16LE";
         }
      }
      print "detected format: $format\n" if $vfiledebug;
      # Text::Iconv->raise_error(1);     # Conversion errors raise exceptions
      $converter=Text::Iconv->new($format,"UTF-8");
   }

   if ($converter) {
      $newchars = $converter->convert($chars);

      # If the conversion failed we will get undef $newchars
      # This is a last chance fallback fix that sometimes works:
      # stripping the newlines before decoding
      my $fallback = 0;
      if ($newchars eq undef) {
         print "falling back to try to decode these chars again!\n" if $vfiledebug;
         $fallback = 1;
         chomp($chars);
         $newchars = $converter->convert($chars);
      }
      croak("This file is in $format format but cannot be properly decoded. $@\n") if ($newchars eq undef);
      print "converted chars: $newchars\n" if $vfiledebug;
      $fallback ? return "$newchars\r\n" : return $newchars;
   } else {
      print "No character decoding necessary\n" if $vfiledebug;
      return $chars;
   }
}

sub is_entry_matched {
   # This code compares two data structures for a match. If the second data
   # structure (r_entry) contains all the data points of the first data
   # structure (r_searchterm), then say it is matched.
   # This searchtool can match any two perl data structures against each
   # other provided the data structures are comprised of only HASH, ARRAY,
   # or SCALAR data types.
   # In the example of matching vcards, r_searchterm needs to be a vcard
   # data structure if you expect to get any matches.
   # For example:
   # $r_searchtermshash = { 'EMAIL' => [ { 'VALUE' => "Alex|Bob" } ] };
   # will match all vCards that have an email with a value of Alex or Bob.
   # If you are also using %only_return, then %only_return MUST include
   # the same propertynames as the ones you are searching for, or else
   # there won't be anything to match during the search.
   my ($r_entry, $r_searchterm, $matched)=@_;

   if ($r_searchterm eq undef) { return 1; } # no searchterms returns a match

   print "=============SEARCHING=============:\n" if $vfiledebug;
   print "     r_entry: \"$r_entry\"\n" if $vfiledebug;
   print "r_searchterm: \"$r_searchterm\"\n" if $vfiledebug;
   print "match status: $matched\n" if $vfiledebug;
   print Dumper($r_entry,$r_searchterm) if $vfiledebug;;

   if (defined $matched && $matched == 0) { return 0; } # a negated match has already been determined

   if (ref($r_searchterm) eq 'HASH' && ref($r_entry) eq 'HASH') {
      foreach my $hashterm (keys %{$r_searchterm}) {
         print "    hashterm: \"$hashterm\"\n" if $vfiledebug;
         if (${$r_entry}{$hashterm}) {
            print "$hashterm exists in both. Recursing search...\n" if $vfiledebug;
            $matched = 1; # in case we're only looking for propertyvalue match
            $matched = is_entry_matched(${$r_entry}{$hashterm},${$r_searchterm}{$hashterm},$matched);
         } else {
            # no matching hash
            $matched = 0;
         }
      }
   } elsif (ref($r_searchterm) eq 'ARRAY' && ref($r_entry) eq 'ARRAY') {
      foreach my $arrayterm (@{$r_searchterm}) {
         for(my $index=0; $index <= $#{$r_entry}; $index++) {
            my $entryarray = ${$r_entry}[$index];
            if (defined $entryarray && defined $arrayterm) {
               $matched = is_entry_matched($entryarray,$arrayterm,$matched);
               if ($matched == 0 && $index < $#{$r_entry}) {
                  # this one doesn't match, but mabye the next one will
                  print "---index $index of $#{$r_entry} didn't match.\n" if $vfiledebug;
                  print "---giving the next array a shot\n" if $vfiledebug;
                  $matched = undef;
               } elsif ($matched == 1) {
                  return $matched;
               }
            }
         }
      }
   } elsif (ref($r_searchterm) eq 'SCALAR' && ref($r_entry) eq 'SCALAR') {
      return is_entry_matched(${$r_entry},${$r_searchterm},$matched);

   } else {
      print "======= CHECKING ACTUAL VALUES =======\n" if $vfiledebug;
      print "r_entry: \"$r_entry\"\n" if $vfiledebug;
      print "r_searchterm: \"$r_searchterm\"\n" if $vfiledebug;
      if ($r_entry =~ m/\Q$r_searchterm\E/i || (ow::tool::is_regex($r_searchterm) && $r_entry =~ m/$r_searchterm/i) ) {
         $matched = 1;
         print "MATCHED\n" if $vfiledebug;
      } else {
         # We negate a previous match here in case the user
         # is searching for multiple match criteria and one
         # of the match criteria does not match.
         $matched = 0;
         print "NOT MATCHED\n" if $vfiledebug;
      }
   }

   return $matched if defined $matched;
}


# clone the iconved $r_entry to $r_clone
# hash of X-OWM-CHARSET is not copied so the entry could be matched by records of different charset
sub entry_clone_iconv {
   my ($fromcharset, $tocharset, $r_entry)=@_;

   if (ref($r_entry) eq 'HASH') {
      my $r_clone={};
      foreach my $key (keys %{$r_entry}) {
         if (defined ${$r_entry}{$key} && $key ne 'X-OWM-CHARSET') {
             ${$r_clone}{$key}=entry_clone_iconv($fromcharset, $tocharset, ${$r_entry}{$key});
         }
      }
      return $r_clone;
   } elsif (ref($r_entry) eq 'ARRAY') {
      my $r_clone=[];
      foreach my $element (@{$r_entry}) {
         push(@{$r_clone}, entry_clone_iconv($fromcharset, $tocharset, $element));
      }
      return $r_clone;
   } elsif (ref($r_entry) eq 'SCALAR') {
      my $clone=entry_clone_iconv($fromcharset, $tocharset, ${$r_entry});
      return \$clone;
   } else {
      return (iconv($fromcharset, $tocharset, $r_entry))[0];
   }
}

print "</pre>" if $vfiledebug;

1;
