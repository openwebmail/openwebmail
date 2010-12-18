
#                              The BSD License
#
#  Copyright (c) 2009-2010, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# vfile.pl - read vFile, determine vFile data type, load type parser,
#            pass file to parser, return hash of data

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);

require "modules/filelock.pl";	# openwebmail filelocking routines
require "shares/iconv.pl";	# openwebmail iconv routines

use vars qw(%supported_parsers %prefs);

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

sub readvfile {
   # This is a base function for extracting vfile objects from a file or string. It goes line by
   # line through a file and passes each vfile it finds to the appropriate parser handler for that
   # vfile type. It does some basic cleaning up of the vfile before passing it to its parser
   # handler. A vfile object starts with a BEGIN block and ends with an END block. The BEGIN block
   # value determines which parser the complete vfile object is passed to for further processing.
   # The parser should populate the hashref that is passed to it with a data structure
   # representing the vfile object. If no parser is available for the vfile object type defined in
   # the BEGIN block then we don't know how to further parse the data and -1 is returned to the
   # caller. If no vfile object type is detected (the file has no vfile data in it at all) then -1
   # is returned to the caller.
   my ($vfile, $r_searchtermshash, $r_onlyreturn) = @_;

   my $depth             = 0;
   my $vcontents         = '';
   my $vtype             = '';
   my $vversion          = '';
   my %allparsedvobjects = ();
   my $beginvfile        = '';

   return if !defined $vfile || $vfile =~ m/^(?:\s+)?$/;

   if ($vfile !~ m/[\r\n]/ && -f $vfile) {
      # process vfile as a file
      return unless -s $vfile;

      ow::filelock::lock($vfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . " $vfile");

      sysopen(VFILE, $vfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $vfile ($!)");

      parsevfileline(
                       $_,
                       \$depth,
                       \$vcontents,
                       \$vtype,
                       \$vversion,
                       \%allparsedvobjects,
                       \$beginvfile,
                       $r_searchtermshash,
                       $r_onlyreturn
                    ) while <VFILE>;

      close(VFILE) or
         openwebmailerror(gettext('Cannot close file:') . " $vfile ($!)");

      ow::filelock::lock($vfile, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . " $vfile");
   } else {
      # process vfile as a string
      parsevfileline(
                       "$_\r\n",
                       \$depth,
                       \$vcontents,
                       \$vtype,
                       \$vversion,
                       \%allparsedvobjects,
                       \$beginvfile,
                       $r_searchtermshash,
                       $r_onlyreturn
                    ) for split(/\r\n/, $vfile);
   }

   openwebmailerror(gettext('Invalid vfile does not contain an equal number of begin and end blocks.')) if $depth != 0;
   openwebmailerror(gettext('Invalid vfile does not contain any begin blocks.')) unless defined $beginvfile && $beginvfile ne '';

   return \%allparsedvobjects;
}

sub parsevfileline {
   # given a single line from a vfile, parse the line
   # and populate some variables with the result
   my ($currentline, $r_depth, $r_vcontents, $r_vtype, $r_vversion,
       $r_allparsedvobjects, $r_beginvfile, $r_searchtermshash, $r_onlyreturn) = @_;

   return unless defined $currentline && $currentline !~ m/^(?:\s+)?$/;

   $currentline = decodeUTF($currentline);

   # Standardize CRLF,LF,and CR into CRLF
   $currentline =~ s/\r\n/\@\@\@/g;
   $currentline =~ s/\r/\@\@\@/g;
   $currentline =~ s/\n/\@\@\@/g;
   $currentline =~ s/\@\@\@/\r\n/g;

   # No whitespace in front of BEGIN END or VERSION lines
   # This is not to spec, but it fixes a lot more vFiles
   # in the wild than it breaks.
   # BUT IT BREAKS AGENTS WHERE END OR BEGIN GET WRAPPED
   # $currentline =~ s/^\s+(BEGIN:|END:|VERSION:)/$1/i;

   # A special case for vCards:
   # Fix AGENT on same line as BEGIN block when rest of AGENT is not on
   # the same line. This is out of 2.1 spec, but they are out there.
   # vCard 2.1 example  vCard 2.1 example 2  vCard 3.0 example (literal '\n')
   # -----------------  -------------------  --------------------------------
   # AGENT:             AGENT:BEGIN:VCARD    AGENT:BEGIN:VCARD\nFN:John Doe
   # BEGIN:VCARD        FN:John Doe
   # FN:John Doe
   if ($currentline =~ m/^(?:\s+)?AGENT:(?:.*)?BEGIN:/i) {
      unless ($currentline =~ m/\\n/i) { # don't do it to version 3.0 AGENTs
         $currentline =~ s/AGENT:(?:.*)?BEGIN:/AGENT:\nBEGIN:/i;
         ${$r_depth}++;
      }
   }

   if ($currentline =~ m/^BEGIN:/i) {
      ${$r_beginvfile} = 1;

      my $linefeeds = $currentline =~ tr/\r/\r/;

      if ($linefeeds > 1) {
         my $r_fromstring = readvfile($currentline, $r_searchtermshash, $r_onlyreturn);
         $r_allparsedvobjects->{$_} = $r_fromstring->{$_} for keys %{$r_fromstring};
      } else {
         $currentline =~ s/^BEGIN:(?:\s+)?(\S+)(?:\s+)?$/BEGIN:$1\r\n/i;
         ${$r_depth}++;
         ${$r_vtype} = lc $1 unless defined ${$r_vtype} && ${$r_vtype} ne '';
         ${$r_vcontents} .= $currentline if ${$r_depth} > 0;
      }
   } elsif ($currentline =~ m/^VERSION:/i) {
      $currentline =~ s/^VERSION:(?:\s+)?(\S+)(?:\s+)?$/VERSION:$1\r\n/i;
      ${$r_vversion} = $1 unless defined ${$r_vversion} && ${$r_vversion} ne '';
      ${$r_vcontents} .= $currentline if ${$r_depth} > 0;
   } elsif ($currentline =~ m/^END:/i) {
      $currentline =~ s/^END:(?:\s+)?(\S+)(?:\s+)?$/END:$1\r\n/i;
      ${$r_vcontents} .= $currentline if ${$r_depth} > 0;
      return if length($1) > 10; # an agent END happened to get wrapped to the front of the line
      ${$r_depth}--;
      my $vendtype = lc $1;
      if (${$r_depth} == 0) {
         if ($vendtype eq ${$r_vtype}) {
            if (defined ${$r_vversion} && ${$r_vversion} ne '') {
               # The end of the object we have been parsing.
               # Send it to a parser for further handling.
               if (defined $supported_parsers{${$r_vtype}}) {
                  # load the parser
                  eval {require "shares/$supported_parsers{${$r_vtype}}[0]"};
                  openwebmailerror(gettext('Cannot load vfile parser module:') . " shares/$supported_parsers{${$r_vtype}}[0]  ($@)") if $@;

                  my $r_parsedvobject = $supported_parsers{${$r_vtype}}[1]->(${$r_vcontents},${$r_vversion},$r_onlyreturn);

                  foreach my $objectid (keys %{$r_parsedvobject}) {
                     if (
                           defined $r_searchtermshash
                           && defined $r_searchtermshash->{'X-OWM-CHARSET'}
                           && defined $r_searchtermshash->{'X-OWM-CHARSET'}[0]{VALUE}
                        ) {
                        my $r_clone = entry_clone_iconv(
                                                          $r_searchtermshash->{'X-OWM-CHARSET'}[0]{VALUE},          # keyword charset
                                                          $r_parsedvobject->{$objectid}{'X-OWM-CHARSET'}[0]{VALUE}, # abook record charset
                                                          $r_searchtermshash
                                                       );

                        $r_allparsedvobjects->{$objectid} = $r_parsedvobject->{$objectid}
                           if is_entry_matched(\%{$r_parsedvobject->{$objectid}}, $r_clone);
                     } else {
                        $r_allparsedvobjects->{$objectid} = $r_parsedvobject->{$objectid}
                           if is_entry_matched(\%{$r_parsedvobject->{$objectid}}, $r_searchtermshash);
                     }
                  }

                  # clear vars
                  ${$r_vcontents} = '';
                  ${$r_vtype}     = '';
                  ${$r_vversion}  = '';
               } else {
                  openwebmailerror(gettext('No parser available for vfile type:') . " ${$r_vtype}");
               }
            } else {
               openwebmailerror(gettext('Invalid vfile object does not have a defined version number.'));
            }
         } else {
            openwebmailerror(gettext('Invalid vfile object begin and end property types mismatch.'));
         }
      }
   } else {
      ${$r_vcontents} .= $currentline if ${$r_depth} > 0;
   }
}

sub outputvfile {
   my ($outputtype, $r_data, $version, $r_exclude_propertynames) = @_;

   if (defined $supported_parsers{$outputtype}[2]) {
      # load the parser
      eval { require "shares/$supported_parsers{$outputtype}[0]" };
      openwebmailerror(gettext('Cannot load vfile parser module:') . " shares/$supported_parsers{$outputtype}[0]  ($@)") if $@;

      # return the output text
      return $supported_parsers{$outputtype}[2]->($r_data, $version, $r_exclude_propertynames);
   } else {
      openwebmailerror(gettext('No parser available for vfile type:') . " $outputtype");
   }
}

sub decodeUTF {
   # UTF-16/32 detection and conversion
   # Apple's iChat saves vcards in UTF-16BE. Grrr.
   # Read http://www.unicode.org/unicode/faq/utf_bom.html
   # Text::Iconv is required to already have been loaded.
   my $chars = shift;

   return unless defined $chars && $chars ne '';

   # Text::Iconv.pm loaded?
   return $chars unless defined $INC{'Text/Iconv.pm'};

   my $format    = '';
   my $converter = '';
   my $newchars  = '';

   if ($chars =~ m/\x00/s) {
      # strip all byte order markers
      $chars =~ s/\x00\x00\xFE\xFF//s; # UTF-32BE
      $chars =~ s/\xFF\xFE\x00\x00//s; # UTF-32LE
      $chars =~ s/\xFE\xFF//s;         # UTF-16BE
      $chars =~ s/\xFF\xFE//s;         # UTF-16LE
      $chars =~ s/\xEF\xBB\xBF//s;     # UTF-8

      if ($chars =~ m/\x00\x00\x00/s) {
         $format = $chars =~ m/^\x00/s ? 'UTF-32BE' : 'UTF-32LE';
      } else {
         $format = $chars =~ /^\x00/s ? 'UTF-16BE' : 'UTF-16LE';
      }

      # Text::Iconv->raise_error(1); # Conversion errors raise exceptions
      $converter=Text::Iconv->new($format, 'UTF-8');
   }

   if ($converter) {
      $newchars = $converter->convert($chars);

      # If the conversion failed we will get undef $newchars
      # This is a last chance fallback fix that sometimes works:
      # stripping the newlines before decoding
      my $fallback = 0;

      if (!defined $newchars) {
         $fallback = 1;
         chomp($chars);
         $newchars = $converter->convert($chars);
      }

      openwebmailerror(gettext('UTF encoded vfile cannot be properly decoded.')) unless defined $newchars;

      return ($fallback ? "$newchars\r\n" : $newchars);
   } else {
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
   # there will not be anything to match during the search.
   my ($r_entry, $r_searchterm, $matched) = @_;

   # no searchterms returns a match
   return 1 unless defined $r_searchterm;

   # a negated match has already been determined
   return 0 if defined $matched && $matched == 0;

   if (ref $r_searchterm eq 'HASH' && ref $r_entry eq 'HASH') {
      foreach my $hashterm (keys %{$r_searchterm}) {
         if ($r_entry->{$hashterm}) {
            $matched = 1; # in case we're only looking for propertyvalue match
            $matched = is_entry_matched($r_entry->{$hashterm}, $r_searchterm->{$hashterm}, $matched);
         } else {
            # no matching hash
            $matched = 0;
         }
      }
   } elsif (ref $r_searchterm eq 'ARRAY' && ref $r_entry eq 'ARRAY') {
      foreach my $arrayterm (@{$r_searchterm}) {
         for(my $index = 0; $index <= $#{$r_entry}; $index++) {
            my $entryarray = $r_entry->[$index];
            if (defined $entryarray && defined $arrayterm) {
               $matched = is_entry_matched($entryarray, $arrayterm, $matched);
               if ($matched == 0 && $index < $#{$r_entry}) {
                  # this one does not match, but mabye the next one will
                  $matched = undef;
               } elsif ($matched == 1) {
                  return $matched;
               }
            }
         }
      }
   } elsif (ref $r_searchterm eq 'SCALAR' && ref $r_entry eq 'SCALAR') {
      return is_entry_matched(${$r_entry}, ${$r_searchterm}, $matched);
   } else {
      if ($r_entry =~ m/\Q$r_searchterm\E/i || (ow::tool::is_regex($r_searchterm) && $r_entry =~ m/$r_searchterm/i) ) {
         $matched = 1;
      } else {
         # We negate a previous match here in case the user
         # is searching for multiple match criteria and one
         # of the match criteria does not match.
         $matched = 0;
      }
   }

   return $matched if defined $matched;
}

sub entry_clone_iconv {
   # clone the iconved $r_entry to $r_clone
   # hash of X-OWM-CHARSET is not copied so the entry could be matched by records of different charset
   my ($fromcharset, $tocharset, $r_entry) = @_;

   my $r_clone = undef;

   if (ref $r_entry eq 'HASH') {
      $r_clone = {};

      foreach my $key (keys %{$r_entry}) {
         $r_clone->{$key} = entry_clone_iconv($fromcharset, $tocharset, $r_entry->{$key})
            if defined $r_entry->{$key} && $key ne 'X-OWM-CHARSET';
      }

      return $r_clone;
   } elsif (ref $r_entry eq 'ARRAY') {
      $r_clone = [];

      foreach my $element (@{$r_entry}) {
         push(@{$r_clone}, entry_clone_iconv($fromcharset, $tocharset, $element));
      }

      return $r_clone;
   } elsif (ref $r_entry eq 'SCALAR') {
      my $clone = entry_clone_iconv($fromcharset, $tocharset, ${$r_entry});
      return \$clone;
   } else {
      return (iconv($fromcharset, $tocharset, $r_entry))[0];
   }
}

1;
