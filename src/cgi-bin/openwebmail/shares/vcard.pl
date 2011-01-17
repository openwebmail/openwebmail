
#                              The BSD License
#
#  Copyright (c) 2009-2011, The OpenWebMail Project
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

# vcard.pl - read/write address book vCard data
#
# This is a companion script to vfile.pl and is meant to be called from within
# that script. This script does not do any character decoding/conversion, so if
# you try to use it directly it will fail on files with 16/32UTF double byte
# characters (ie Japanese).
#
# See vfile.pl for usage instuctions.

use strict;
use warnings FATAL => 'all';

use MIME::QuotedPrint;
use MIME::Base64;
use CGI::Carp qw(fatalsToBrowser carpout);

use vars qw(%property_handlers);

# Map the known propertyname to its parser or writer handler. You can use
# this as a hook to add parsing routines for a specific propertyvalue.
# This supports the "X-" extension defined in the RFC. (e.g:
# X-SOMECOMPANY-SOMEPROPERTYNAME). Propertynames with no value means no defined
# handler, which is okay. The value of that propertyname will not be modified at
# all and will be returned as is. Propertynames that are not defined here at all
# are also returned as-is. We try to define all propertynames explicitly here to
# avoid any question as to whether a propertyname value gets modified by a
# handler or not.
# The number assigned to each propertyname is the order that the properties get
# written out to vcard files. There are gaps in case other properties arise that
# need to get put inbetween.
%property_handlers = (
   # These propertynames are defined in the RFC and vCard specification
   'SOURCE'      => ['','',270],                                            # vCard 3.0
   'NAME'        => ['','',260],                                            # vCard 3.0
   'PROFILE'     => ['','',250],                                            # vCard 3.0
   'BEGIN'       => ['','',0],                                              # vCard 2.1 (required) and 3.0 (required)
   'END'         => ['','',10000],                                          # vCard 2.1 (required) and 3.0 (required)
   'FN'          => ['','',20],                                             # vCard 2.1 and 3.0 (required)
   'N'           => [\&parsevcard_N,\&outputvcard_N,10],                    # vCard 2.1 (required) and 3.0 (required)
   'NICKNAME'    => ['','',30],                                             # vCard 3.0
   'PHOTO'       => ['','',200],                                            # vCard 2.1 and 3.0
   'BDAY'        => ['',\&outputvcard_BDAY,120],                            # vCard 2.1 and 3.0 (always parsed into X-OWM-BDAY)
   'ADR'         => [\&parsevcard_ADR,\&outputvcard_ADR,60],                # vCard 2.1 and 3.0
   'LABEL'       => ['','',70],                                             # vCard 2.1 and 3.0
   'TEL'         => ['','',50],                                             # vCard 2.1 and 3.0
   'EMAIL'       => ['','',40],                                             # vCard 2.1 and 3.0
   'MAILER'      => ['','',150],                                            # vCard 2.1 and 3.0
   'TZ'          => [\&parsevcard_TZ,\&outputvcard_TZ,130],                 # vCard 2.1 and 3.0
   'GEO'         => [\&parsevcard_GEO,\&outputvcard_GEO,140],               # vCard 2.1 and 3.0
   'TITLE'       => ['','',80],                                             # vCard 2.1 and 3.0
   'ROLE'        => ['','',100],                                            # vCard 2.1 and 3.0
   'LOGO'        => ['','',210],                                            # vCard 2.1 and 3.0
   'AGENT'       => [\&parsevcard_AGENT,\&outputvcard_AGENT,240],           # vCard 2.1 and 3.0
   'ORG'         => [\&parsevcard_ORG,\&outputvcard_ORG,90],                # vCard 2.1 and 3.0
   'CATEGORIES'  => [\&parsevcard_CATEGORIES,\&outputvcard_CATEGORIES,160], # vCard 3.0
   'NOTE'        => ['','',110],                                            # vCard 2.1 and 3.0
   'PRODID'      => ['','',290],                                            # vCard 3.0
   'REV'         => [\&parsevcard_REV,\&outputvcard_REV,300],               # vCard 2.1 and 3.0
   'SORT-STRING' => ['','',170],                                            # vCard 3.0
   'SOUND'       => ['','',220],                                            # vCard 2.1 and 3.0
   'UID'         => ['','',190],                                            # vCard 2.1 and 3.0
   'URL'         => ['','',180],                                            # vCard 2.1 and 3.0
   'VERSION'     => ['','',5],                                              # vCard 2.1 (required) and 3.0 (required)
   'CLASS'       => ['','',280],                                            # vCard 3.0
   'KEY'         => ['','',230],                                            # vCard 2.1 and 3.0

   # These are X- extension propertynames
   'X-OWM-BOOK'    => ['','',310],                                                  # Openwebmail: remember addressbook name
   'X-OWM-GROUP'   => ['','',320],                                                  # Openwebmail: vcard is a group if defined
   'X-OWM-BDAY'    => [\&parsevcard_X_OWM_BDAY,\&outputvcard_X_OWM_BDAY,325],       # Openwebmail: partial bday information support
   'X-OWM-CUSTOM'  => [\&parsevcard_X_OWM_CUSTOM,\&outputvcard_X_OWM_CUSTOM,330],   # Openwebmail: user custom field
   'X-OWM-CHARSET' => ['','',340],                                                  # Openwebmail: vcard character set support
   'X-OWM-UID'     => [\&parsevcard_X_OWM_UID,'',350],                              # Openwebmail: unique id
);

sub parsevcard {
   # Parse vCard 2.1 and 3.0 format. Decode encoded strings and binary data. Pass
   # the final decoded value to a defined parser subroutine for that value name. Get
   # the parsed value back from that parser sub and return a reference to a hash
   # data structure representing the vcard.
   my ($vcard, $version, $r_onlyreturn) = @_;

   my %parsedvcard = ();

   # Get the line delimiters in order
   $vcard =~ s/(\S)\s+$/$1\r\n/g; # end of lines should always be a single CRLF

   # UNFOLD THE VCARD
   # The line delimiter is CRLF for vCard 2.1.
   # Replace CRLF+single whitespace character with single whitespace character.
   # refer to vCard 2.1 specification section 2.1.3
   $vcard =~ s/\r\n([ \t])/$1/sg if $version <= 2.1;

   # The line delimiter is CRLF for vCard 3.0.
   # Replace CRLF+single whitespace character with nothing.
   # refer to RFC-2425 section 5.8.1
   $vcard =~ s/\r\n[ \t]//sg if $version == 3.0;

   my $depth          = 0;
   my $appendnext     = 0;
   my $propertykey    = undef;
   my $propertygroup  = undef;
   my $propertyname   = undef;
   my $propertyvalue  = undef;
   my @propertyparams = ();
   my $encoding       = undef;
   my $types_ref      = {};
   my $numberoftypes  = 0;

   foreach my $line (split(/\n/,$vcard)) {
      $line =~ s/\r//g; # remove carriage returns

      next if $line =~ m/^(?:\s+)?$/; # skip blank lines

      if ($appendnext) {
         if ($encoding =~ m/QUOTED-PRINTABLE/) {
            # append the next quoted-printable line to the propertyvalue
            $propertyvalue .= $line . "\n";
            if ($line =~ m/\=$/) {
               $propertyvalue =~ s/=[\r\n]$//s; # unfold quoted-printable
               next;                            # append the next line
            } else {
               chomp($propertyvalue);
               # All the new lines are appended.
               # Decode the encoded block now that we have it all.
               $propertyvalue = decode_qp($propertyvalue);
            }
         } elsif ($encoding =~ m/BASE64/ || $encoding =~ m/^B$/) {
            # Decode the encoded block.
            $propertyvalue = decode_base64($propertyvalue);

            # defined property_handler processing of this base64 block?
            if (exists $property_handlers{$propertyname} && defined $property_handlers{$propertyname}[0] && ref $property_handlers{$propertyname}[0] eq 'CODE') {
               ($propertyname, $propertyvalue, $propertygroup, $types_ref) = $property_handlers{$propertyname}[0]->($propertyname, $propertyvalue, $version, $propertygroup, $types_ref, $r_onlyreturn);
            }

            # store
            my $pos = exists $parsedvcard{$propertyname} ? scalar @{$parsedvcard{$propertyname}} : 0;
            $parsedvcard{$propertyname}[$pos]{VALUE} = $propertyvalue;
            $parsedvcard{$propertyname}[$pos]{TYPES} = $types_ref;

            $propertykey   = undef;
            $propertygroup = undef;
            $propertyvalue = undef;
            $encoding      = undef;
            $numberoftypes = 0;
         } elsif ($encoding =~ m/AGENT/) {
            if ($line =~ m/^BEGIN:/i) {
               $depth++;
            } elsif ($line =~ m/^END:/i) {
               $depth--;
               $propertyvalue .= "$line\n" if $depth >= 1;
               $line = '';
            }

            if ($depth >= 2) {
               $propertyvalue .= "$line\n";
               next;
            }
         }

         $appendnext = 0;
      }

      if ($line =~ m/^END:/i) {
         $depth--;
         $propertyvalue .= $line if $depth == 1;
      } elsif ($line =~ m/^BEGIN:/i) {
         $depth++;
         next; # do not record BEGIN blocks
      }

      if ($depth == 1) {
         # propertyvalue may already be defined from encoding loops
         if (!defined $propertyvalue && !defined $propertykey) {

            # protect escaped semi-colon, colon, comma characters
            # with placeholders. We will convert them back later.
            vcard_protect_chars($line);

            ($propertykey, $propertyvalue) = $line =~ m/(\S+?):(.*)$/;

            @propertyparams = split(/;/, uc($propertykey));

            $propertyname = shift @propertyparams;
            $propertyname =~ s/^\s+//; # no leading whitespace
            $propertyname =~ s/\s+$//; # no trailing whitespace

            $propertyvalue =~ s/^\s+//; # no leading whitespace
            $propertyvalue =~ s/\s+$//; # no trailing whitespace

            # property grouping support
            if ($propertyname =~ m/\./) {
               ($propertygroup, $propertyname) = split(/\./, $propertyname);
               openwebmailerror(gettext('A contact group name contains an invalid carriage return:') . " ($propertygroup)")
                  if $propertygroup =~ m/(?:\\n|\n)/i;
            }

            # skip to next line if necessary
            # do not skip AGENT - we may want the specific info in those embedded cards
            # do not skip X-OWM-UID - or else it will be auto-assigned a new X-OWM-UID later, bad!
            # do not skip N - we need it to build FN later
            # do not skip REV - or else every rev in the folder gets changed when any card is saved
            if (defined $r_onlyreturn && $propertyname !~ m/^(?:AGENT|X\-OWM\-UID|N|REV)$/) {
               unless (exists $r_onlyreturn->{$propertyname}) {
                  # do not process this one. clear vars.
                  $propertyname  = undef;
                  $propertykey   = undef;
                  $propertygroup = undef;
                  $propertyvalue = undef;
                  next;
               }
            }

            # process propertyparams types array into a hash
            my %types = ();
            foreach my $propertytype (@propertyparams) {
               my ($key, $value) = ($propertytype =~ m/=/ ? split(/=/, $propertytype) : ($propertytype, 'TYPE'));

               # does the propertytype tell us the propertyvalue is encoded?
               if ($value =~ m/QUOTED-PRINTABLE/ || $value =~ m/BASE64/ || $value =~ m/^B$/) {
                  $encoding = $value;

                  if ($encoding =~ m/QUOTED-PRINTABLE/ && $propertyvalue =~ m/=$/) {
                     # we need to get the next line(s) before decoding
                     $propertyvalue .= "\n";
                     $appendnext = 1;
                  }

                  if ($encoding =~ m/BASE64/ || $encoding =~ m/^B$/) {
                     $value = 'BASE64'; # standardize type name for hash
                     $appendnext = 1;
                  }

                  # decode the one-line quoted-printables
                  $propertyvalue = decode_qp($propertyvalue);
               }

               # Assignments to the %types hash are flipped value=key on purpose.
               # Its easier to access later and values, not keys, are unique here.
               # vCard 2.1 only allows types like WORK
               # vCard 3.0 allows grouped types like WORK,VOICE,PREF
               # so we need to break them apart.
               foreach my $valuepart (split(/,/, $value)) {
                  # unprotect semi-colon, colon, and comma characters
                  vcard_unprotect_chars($key, $valuepart);

                  openwebmailerror(gettext('A contact property type contains an invalid carriage return:') . " ($key=$valuepart)")
                     if $key =~ m/(?:\\n|\n)/i || $valuepart =~ m/(?:\\n|\n)/i;

                  $types{$valuepart} = $key;

                  $numberoftypes++;
               }
            }

            $types_ref =  $numberoftypes ? \%types : undef;

            if ($propertyname eq 'AGENT' && (!defined $propertyvalue || defined $propertyvalue && $propertyvalue eq '')) {
               $encoding   = 'AGENT';
               $appendnext = 1;
            }
         }

         # grab any extra lines needed and decode
         next if $appendnext;

         # undef all whitespace final values
         $propertyvalue = undef if $propertyvalue =~ m/^\s+$/;

         # the vcard spec does not support partial BDAY information
         # Always parse the BDAY propertyname value into the X-OWM-BDAY
         # propertyname which supports partial BDAY information
         $propertyname = 'X-OWM-BDAY' if $propertyname eq 'BDAY';

         # Apply specific parsing to the propertyvalue based on the propertyname. This is
         # where hooks for specific propertynames get called, like parsevcard_ADR() to
         # process ADDRESS information. The hooks are defined as subroutines in the
         # property_handlers hash. Propertyname parsers can even call
         # parsevcard(), which is what enables recursive parsing.
         if (exists $property_handlers{$propertyname} && defined $property_handlers{$propertyname}[0] && ref $property_handlers{$propertyname}[0] eq 'CODE') {
            ($propertyname, $propertyvalue, $propertygroup, $types_ref) =
               $property_handlers{$propertyname}[0]->($propertyname, $propertyvalue, $version, $propertygroup, $types_ref, $r_onlyreturn);
         }

         # Unescape semi-colon, colon, return, and comma characters
         # It is also important to notice that base64 and qp decoded
         # $propertyvalues are not affected by these substitutions since
         # they never get here in the code.
         vcard_unprotect_chars($propertyvalue, $propertygroup, $propertyname);

         $propertyvalue =~ s/\\n/\n/ig;

         my %finalparsedresult = (
                                    'VALUE' => $propertyvalue,
                                    'GROUP' => $propertygroup,
                                    'TYPES' => $types_ref
                                 );

         foreach my $key (keys %finalparsedresult) {
            delete $finalparsedresult{$key} unless defined $finalparsedresult{$key} && $finalparsedresult{$key} ne '';
         }

         openwebmailerror(gettext('Invalid propertyname while parsing contact line:') . " ($line)")
            unless defined $propertyname;

         push(@{$parsedvcard{$propertyname}}, \%finalparsedresult) if defined $finalparsedresult{VALUE} && $finalparsedresult{VALUE};

         # reset vars
         $propertyname  = undef;
         $propertykey   = undef;
         $propertygroup = undef;
         $propertyvalue = undef;
         $encoding      = undef;
         $numberoftypes = 0;
         $types_ref     = {};
      } elsif ($depth > 1) {
         # We are inside an embedded vFile. Append this line to the propertyvalue
         # until we get out of this embedded vFile (meaning depth <= 1).
         # The AGENT propertyname supports embedded vCards.
         $propertyvalue .= $line . "\n";
      }
   }

   # do not allow multiple instances of these propertynames
   foreach my $limited (qw(N FN VERSION PROFILE BDAY REV TZ GEO PRODID SORT-STRING UID X-OWM-UID X-OWM-GROUP X-OWM-BOOK X-OWM-CHARSET)) {
      if (exists $parsedvcard{$limited} && defined $parsedvcard{$limited}[1]) {
         openwebmailerror(gettext('Invalid contact contains more than one value for property:') . " ($limited)");
      }
   }

   # define FN using N if FN not defined
   if (
         (defined $parsedvcard{N} && !defined $parsedvcard{FN})
         &&
         (!defined $r_onlyreturn || (defined $r_onlyreturn && exists $r_onlyreturn->{FN}))
      ) {
      $parsedvcard{FN}[0]{VALUE} .= $parsedvcard{N}[0]{VALUE}{NAMEPREFIX} if defined $parsedvcard{N}[0]{VALUE}{NAMEPREFIX};

      if (
            defined $parsedvcard{N}[0]{VALUE}{GIVENNAME}
            && defined $parsedvcard{N}[0]{VALUE}{FAMILYNAME}
            && $parsedvcard{N}[0]{VALUE}{GIVENNAME} =~ m/^[\xA1-\xF9][\x40-\x7E\xA1-\xFE]/
         ) {
         # chinese name
         # big5:[A1-F9][40-7E,A1-FE], gb2312:[A1-F9][A1-FE]
         $parsedvcard{FN}[0]{VALUE} .= ' ' . $parsedvcard{N}[0]{VALUE}{FAMILYNAME} . $parsedvcard{N}[0]{VALUE}{GIVENNAME};
         $parsedvcard{FN}[0]{VALUE} .= ' ' . $parsedvcard{N}[0]{VALUE}{ADDITIONALNAMES} if defined $parsedvcard{N}[0]{VALUE}{ADDITIONALNAMES};
      } else {
         $parsedvcard{FN}[0]{VALUE} .= ' ' . $parsedvcard{N}[0]{VALUE}{GIVENNAME} if defined $parsedvcard{N}[0]{VALUE}{GIVENNAME};
         $parsedvcard{FN}[0]{VALUE} .= ' ' . $parsedvcard{N}[0]{VALUE}{ADDITIONALNAMES} if defined $parsedvcard{N}[0]{VALUE}{ADDITIONALNAMES};
         $parsedvcard{FN}[0]{VALUE} .= ' ' . $parsedvcard{N}[0]{VALUE}{FAMILYNAME} if defined $parsedvcard{N}[0]{VALUE}{FAMILYNAME};
      }

      $parsedvcard{FN}[0]{VALUE} .= ' ' . $parsedvcard{N}[0]{VALUE}{NAMESUFFIX} if defined $parsedvcard{N}[0]{VALUE}{NAMESUFFIX};
      $parsedvcard{FN}[0]{VALUE} =~ s/^\s+//g; # no leading whitespace
   }

   # remove N if it is no longer needed
   delete $parsedvcard{N} if defined $r_onlyreturn && !exists $r_onlyreturn->{N};

   # assign mandatory properties:
   $parsedvcard{'X-OWM-UID'}[0]{VALUE} = ($property_handlers{'X-OWM-UID'}[0]->('X-OWM-UID', $parsedvcard{'X-OWM-UID'}[0]{VALUE}))[1];
   $parsedvcard{REV}[0]{VALUE} = ($property_handlers{REV}[0]->('REV', ''))[1]
      unless defined $parsedvcard{REV}[0]{VALUE} && ref $parsedvcard{REV}[0]{VALUE} eq 'HASH';

   # mandatory properties exist or croak
   if (!defined $r_onlyreturn) {
      openwebmailerror(gettext('The name of the contact is required and does not exist.')) if !defined $parsedvcard{N}[0]{VALUE};
      openwebmailerror(gettext('The full name of the contact is required and does not exist.')) if !defined $parsedvcard{FN}[0]{VALUE} && $version == '3.0';
   }

   # The returned card should be the id of this card pointing to a hash of all of the card data.
   my %finalcard = ($parsedvcard{'X-OWM-UID'}[0]{VALUE} => \%parsedvcard);

   # do not return X-OWM-UID when we only want partial info returned, unless specified
   # make sure to delete X-OWM-UID last or other deletes will create it again
   delete $finalcard{$parsedvcard{'X-OWM-UID'}[0]{VALUE}}->{'X-OWM-UID'} if defined $r_onlyreturn && !exists $r_onlyreturn->{'X-OWM-UID'};

   return \%finalcard;
}

sub parsevcard_N {
   my ($name, $value, $version, $group, $r_types) = @_;

   my ($n_familyname, $n_givenname, $n_additionalnames, $n_nameprefix, $n_namesuffix) = split(/\;/, $value);

   foreach ($n_familyname, $n_givenname, $n_additionalnames, $n_nameprefix, $n_namesuffix) {
      $_ = '' unless defined;
      s/^\s+//;
      s/\s+$//;
   }

   openwebmailerror(gettext('Contact name must be defined.'))
      if $n_familyname eq '' && $n_givenname eq '' && $n_additionalnames eq '' && $n_nameprefix eq '' && $n_namesuffix eq '';

   vcard_unprotect_chars($n_familyname, $n_givenname, $n_additionalnames, $n_nameprefix, $n_namesuffix);

   $value = {
               'FAMILYNAME'      => $n_familyname,
               'GIVENNAME'       => $n_givenname,
               'ADDITIONALNAMES' => $n_additionalnames,
               'NAMEPREFIX'      => $n_nameprefix,
               'NAMESUFFIX'      => $n_namesuffix
            };

   foreach my $key (keys %{$value}) {
      # delete empty keys
      delete $value->{$key} unless $value->{$key};
   }

   return ($name, $value, $group, $r_types);
}

sub parsevcard_ADR {
   my ($name, $value, $version, $group, $r_types) = @_;

   my (
         $adr_postofficeaddress,
         $adr_extendedaddress,
         $adr_street,
         $adr_locality,
         $adr_region,
         $adr_postalcode,
         $adr_country
      ) = split(/\;/, $value);

   vcard_unprotect_chars(
                           $adr_postofficeaddress,
                           $adr_extendedaddress,
                           $adr_street,
                           $adr_locality,
                           $adr_region,
                           $adr_postalcode,
                           $adr_country
                        );

   $value = {
               POSTOFFICEADDRESS => $adr_postofficeaddress,
               EXTENDEDADDRESS   => $adr_extendedaddress,
               STREET            => $adr_street,
               LOCALITY          => $adr_locality,
               REGION            => $adr_region,
               POSTALCODE        => $adr_postalcode,
               COUNTRY           => $adr_country
            };

   foreach my $key (keys %{$value}) {
      if (!defined $value->{$key}) {
         delete $value->{$key};
         next;
      }

      # No carriage returns in address lines. Thats what LABEL is for.
      $value->{$key} =~ s/[\r\n]+/ /g;

      $value->{$key} =~ s/^\s+//g;
      $value->{$key} =~ s/\s+$//g;

      delete $value->{$key} unless $value->{$key};
   }

   return ($name, $value, $group, $r_types);
}

sub parsevcard_TZ {
   my ($name, $value, $version, $group, $r_types) = @_;

   # capture the utc format string
   # support for the vcard 3.0 single value format:
   # -05:00; EST; Raleigh/North America
   # in addition to the more minimal format:
   # -05:00
   $value = (split(/;/, $value))[0] if $value =~ m/;/;

   if (defined $value) {
      if (my ($plusminus,$hour,$min) = $value =~ m/^([+-])?(\d{2}):?(\d{2})$/) { # -05:00 0500 +05:00
         openwebmailerror(gettext('The timezone hour must be a number from 0 to 13.'))
            if $hour < 0 || $hour > 13;

         openwebmailerror(gettext('The timezone minute must be either 00 or 30.'))
            unless $min == 0 || $min == 30;

         $value = ((defined $plusminus && $plusminus eq '-') ? '-' : '+') . $hour . $min;
      } else {
         openwebmailerror(gettext('The timezone value is invalid:') . " ($value)")
            if $value ne '';
      }
   }

   return ($name, $value, $group, $r_types);
}

sub parsevcard_GEO {
   # Values should be in decimal degrees to six decimal places.
   # To convert degrees-minutes-seconds to decimal degrees:
   # decimal_degrees = degrees + minutes/60 + seconds/3600
   # Consult RFC 2426 section 3.4.2 for a good explanation.
   # +lat=N -lat=S +long=E -long=W
   my ($name, $value, $version, $group, $r_types) = @_;

   if (defined $value) {
      my ($geo_latitude, $geo_longitude) = $value =~ m/(\S+)[,;:](\S+)/;

      $geo_latitude  = '' unless defined $geo_latitude;
      $geo_latitude  =~ s/\s+//g;
      $geo_longitude = '' unless defined $geo_longitude;
      $geo_longitude =~ s/\s+//g;

      openwebmailerror(gettext('Invalid latitude format.') . " ($geo_latitude)")
         unless $geo_latitude =~ m/^([+-])?(\d+)\.?(\d+)?$/;

      $geo_latitude = "$2" . ($3 ? ".$3" : ".0");
      $geo_latitude = ($1 ? $1 : '') . sprintf("%.6f", $geo_latitude);

      openwebmailerror(gettext('Invalid longitude format.') . " ($geo_longitude)")
         unless $geo_longitude =~ m/^([+-])?(\d+)\.?(\d+)?$/;

      $geo_longitude = "$2" . ($3 ? ".$3" : ".0");
      $geo_longitude = ($1 ? $1 : '') . sprintf("%.6f", $geo_longitude);

      $value = {
                  LATITUDE  => $geo_latitude,
                  LONGITUDE => $geo_longitude,
               };

      foreach my $key (keys %{$value}) {
         $value->{$key} =~ s/\s+//g;

         delete $value->{$key} unless $value->{$key} ne '';
      }
   }

   return ($name, $value, $group, $r_types);
}

sub parsevcard_AGENT {
   my ($name, $value, $version, $group, $r_types, $r_onlyreturn) = @_;

   if ($r_types->{URI} || $r_types->{TEXT} || $r_types->{URL}) {
      # This AGENT value is just a string of text, url, or uri. No vcard here.
      return ($name, $value, $group, $r_types);
   } else {
      # Assume AGENT is an embedded vcard.
      $value =~ s/\\n/\n/gi;
      $value =~ s/\@\@\@/\\;/g;
      $value =~ s/\#\@\#/\\:/g;
      $value =~ s/\^\@\^/\\,/g;
      $r_types->{VCARD} = 'VALUE';
      return ($name, \%{parsevcard($value, $version, $r_onlyreturn)}, $group, $r_types);
   }
}

sub parsevcard_ORG {
   my ($name, $value, $version, $group, $r_types) = @_;

   if (defined $value) {
      my ($org_organizationname, @org_organizationalunits) = split(/\;/, $value);

      $org_organizationname = '' unless defined $org_organizationname;

      vcard_unprotect_chars($org_organizationname);
      vcard_unprotect_chars(@org_organizationalunits);

      s/^\s+//g for @org_organizationalunits; # No leading whitespace
      s/\s+$//g for @org_organizationalunits; # No trailing whitespace

      $value = {
                  ORGANIZATIONNAME    => $org_organizationname,
                  ORGANIZATIONALUNITS => scalar @org_organizationalunits
                                         ? \@org_organizationalunits
                                         : undef,
               };

      foreach my $key (keys %{$value}) {
         if (defined $value->{$key}) {
            $value->{$key} =~ s/^\s+//g; # No leading whitespace
            $value->{$key} =~ s/\s+$//g; # No trailing whitespace
         }

         delete $value->{$key} unless defined $value->{$key} && $value->{$key};
      }
   }

   return ($name, $value, $group, $r_types);
}

sub parsevcard_CATEGORIES {
   my ($name, $value, $version, $group, $r_types) = @_;

   if (defined $value) {
      my @categories = split(/,/, $value);

      s/^\s+//g for @categories; # No leading whitespace
      s/\s+$//g for @categories; # No trailing whitespace

      vcard_unprotect_chars(@categories);

      $value = {
                  CATEGORIES => scalar @categories
                                ? \@categories
                                : undef,
               };

      foreach my $key (keys %{$value}) {
         delete $value->{$key} unless defined $value->{$key} && $value->{$key};
      }
   }

   return ($name, $value, $group, $r_types);
}

sub parsevcard_REV {
   my ($name, $value, $version, $group, $r_types) = @_;

   my ($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year,$rev_wday,$rev_yday,$rev_isdst) = gmtime(time);
   $rev_mon++;
   $rev_year += 1900;

   if (defined $value && $value =~ m/^(\d{4})-?(\d{2})-?(\d{2})T?(\d{2})?\:?(\d{2})?\:?(\d{1,2})?Z?/) {
      $rev_year = $1;
      $rev_mon  = $2;
      $rev_mday = $3;
      $rev_hour = $4;
      $rev_min  = $5;
      $rev_sec  = $6;
   }

   $value = {
               YEAR   => $rev_year,
               MONTH  => $rev_mon,
               DAY    => $rev_mday,
               HOUR   => $rev_hour,
               MINUTE => $rev_min,
               SECOND => $rev_sec,
            };

   return ($name, $value, $group, $r_types);
}

sub parsevcard_X_OWM_BDAY {
   # We have decided to only support ISO-8601 in two formats:
   # YYYY-MM-DD and YYYYMMDD
   # TODO: implement complete ISO-8601 support for other formats
   # specified as acceptable in RFC 2426 section 3.1.5 for the BDAY
   # property
   # the vcard spec does not support partial BDAY date storage
   # so we support it with the X-OWM-BDAY propertyname
   my ($name, $value, $version, $group, $r_types) = @_;

   if (defined $value) {
      if ($value =~ m/^(\d{4})?-?(\d{1,2})?-?(\d{1,2})?$/) {
         # ISO-8601 format confirmed
         my $bdayyear  = defined $1 ? $1 : '';
         my $bdaymonth = defined $2 ? sprintf('%02d',$2) : '';
         my $bdayday   = defined $3 ? sprintf('%02d',$3) : '';

         $bdayyear  = '' if $bdayyear  < 1 || $bdayyear  > 9999;
         $bdaymonth = '' if $bdaymonth < 1 || $bdaymonth > 12;
         $bdayday   = '' if $bdayday   < 1 || $bdayday   > 31;

         if ($bdayyear ne '' && $bdaymonth ne '' && $bdayday ne '') {
            # verify valid number of days for this birthday month
            my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
            $days_in_month[2]++ if $bdayyear % 4 == 0 && ($bdayyear % 100 != 0 || $bdayyear % 400 == 0);

            openwebmailerror(gettext('The birth day exceeds the maximum number of days in the selected birth month.'))
               if $bdayday > $days_in_month[$bdaymonth];
         }

         $value = {
                     YEAR  => $bdayyear,
                     MONTH => $bdaymonth,
                     DAY   => $bdayday,
                  };
      } else {
         openwebmailerror(gettext('The birthday value is invalid:') . " ($value)")
            if $value ne '';
      }

      foreach my $key (keys %{$value}) {
         $value->{$key} =~ s/^\s+//g;
         $value->{$key} =~ s/\s+$//g;
         delete $value->{$key} unless $value->{$key};
      }
   }

   return ($name, $value, $group, $r_types);
}

sub parsevcard_X_OWM_UID {
   # This vCard implementation demands a X-OWM-UID for all objects,
   # which is a unique id for tracking the vcard in the software.
   # Therefore, if a X-OWM-UID is not found for an object, then
   # this parser will add one, free of charge ;)
   my ($name, $value, $version, $group, $r_types) = @_;

   $value = generate_xowmuid() unless defined $value;

   return ($name, $value, $group, $r_types);
}

sub parsevcard_X_OWM_CUSTOM {
   my ($name, $value, $version, $group, $r_types) = @_;

   if (defined $value) {
      my ($customname, @customvalues) = split(/\;/, $value);

      $customname = '' unless defined $customname;

      vcard_unprotect_chars($customname);
      vcard_unprotect_chars(@customvalues);

      s/^\s+//g for @customvalues; # No leading whitespace
      s/\s+$//g for @customvalues; # No trailing whitespace

      $value = {
                  CUSTOMNAME   => $customname,
                  CUSTOMVALUES => scalar @customvalues
                                  ? \@customvalues
                                  : undef,
               };

      foreach my $key (keys %{$value}) {
         if (defined $value->{$key}) {
            $value->{$key} =~ s/^\s+//g; # No leading whitespace
            $value->{$key} =~ s/\s+$//g; # No trailing whitespace
         }

         delete $value->{$key} unless defined $value->{$key};
      }
   }

   return ($name, $value, $group, $r_types);
}

sub outputvcard {
   # Take a vCard data structure and output a vCard in either 2.1 or 3.0 format.
   my ($r_vcards, $version, $r_exclude_propertynames) = @_;

   $version = '3.0' if !defined $version || $version eq '';

   my $output = '';

   foreach my $xowmuid (sort keys %{$r_vcards}) {
      if (!defined $xowmuid || $xowmuid eq '') {
         # require an xowmuid
         my $uid = generate_xowmuid();

         $r_vcards->{$uid} = $r_vcards->{$xowmuid};
         delete $r_vcards->{$xowmuid};
         $xowmuid = $uid;
      }

      # the vcard spec does not support partial BDAY information
      # output the X-OWM-BDAY propertyname value as a BDAY propertyname
      # if all of the date values are present and valid
      # otherwise output as X-OWM-BDAY which accepts partial information
      if (
            exists $r_vcards->{$xowmuid}{'X-OWM-BDAY'}
            && defined $r_vcards->{$xowmuid}{'X-OWM-BDAY'}[0]{VALUE}
            && (exists $r_vcards->{$xowmuid}{'X-OWM-BDAY'}[0]{VALUE}{YEAR}  && $r_vcards->{$xowmuid}{'X-OWM-BDAY'}[0]{VALUE}{YEAR}  ne '')
            && (exists $r_vcards->{$xowmuid}{'X-OWM-BDAY'}[0]{VALUE}{MONTH} && $r_vcards->{$xowmuid}{'X-OWM-BDAY'}[0]{VALUE}{MONTH} ne '')
            && (exists $r_vcards->{$xowmuid}{'X-OWM-BDAY'}[0]{VALUE}{DAY}   && $r_vcards->{$xowmuid}{'X-OWM-BDAY'}[0]{VALUE}{DAY}   ne '')
         ) {
         $r_vcards->{$xowmuid}{BDAY} = $r_vcards->{$xowmuid}{'X-OWM-BDAY'};
         delete $r_vcards->{$xowmuid}{'X-OWM-BDAY'};
      }

      my @vcard = ();

      # get the order of the propertynames as described by %property_handlers
      # to ensure all our cards propertynames write out in the same order every time.
      my @sortedpropertynames =  map { $_->[1] }
                                sort { $a->[0] <=> $b->[0] || lc $a->[1] cmp lc $b->[1] }
                                 map { [ defined($property_handlers{$_}[2]) ? $property_handlers{$_}[2] : 9999, $_ ] }
                                keys %{$r_vcards->{$xowmuid}};

      foreach my $propertyname (@sortedpropertynames) {
         next if exists $r_exclude_propertynames->{$propertyname};
         next if $propertyname =~ m/^(BEGIN|END|VERSION)$/i;
         for (my $entrynum = 0; $entrynum < @{$r_vcards->{$xowmuid}{$propertyname}}; $entrynum++) {
            # Make a copy of this entry and work from that so we do not modify
            # the original data structure in case caller needs to use it later.
            my %entry = %{$r_vcards->{$xowmuid}{$propertyname}[$entrynum]};
            my $entry = \%entry;

            # Apply property_handler before we try further parsing.
            # Some values need to be converted to single text strings before they get processed.
            $entry = $property_handlers{$propertyname}[1]->($entry,$version)
                        if exists $property_handlers{$propertyname}
                           && defined $property_handlers{$propertyname}[1]
                           && ref $property_handlers{$propertyname}[1] eq 'CODE';

            my $typeoutput  = '';
            my $groupoutput = '';
            my $valueoutput = '';
            my $encoding    = '';

            # Prepare the value output string
            $valueoutput = $entry->{VALUE};

            # skip empty properties
            next unless defined $valueoutput && $valueoutput ne '';

            # Standardize CRLF,LF,and CR into CR for the value
            if ($propertyname !~ m/^(?:PHOTO|KEY|LOGO|SOUND)$/) {
               $valueoutput =~ s/\r\n/\@\@\@/g;
               $valueoutput =~ s/\r/\@\@\@/g;
               $valueoutput =~ s/\n/\@\@\@/g;
               $valueoutput =~ s/\@\@\@/\n/g;
            }

            # Escape the value unless it was already escaped by the property handler.
            # Property handlers can introduce comma field delimiters, so do not change this.
            vcard_escape_chars($valueoutput) unless exists $property_handlers{$propertyname} && ref $property_handlers{$propertyname}[1] eq 'CODE';
            $valueoutput =~ s/\n/\\n/g if $version == 3.0;

            # Prepare the types output string
            if (defined $entry->{TYPES}) {
               my %fliptypes = ();

               foreach my $type (sort keys %{$entry->{TYPES}}) {
                  my $escapedtype = $type;
                  vcard_escape_chars2($escapedtype, $entry->{TYPES}{$type});

                  # this is to support bad implementations that do stuff
                  # against spec like: TYPE=QUOTED-PRINTABLE
                  $entry->{TYPES}{$type} = 'ENCODING'
                    if (
                          $entry->{TYPES}{$type} eq 'TYPE'
                          && (
                                $escapedtype =~ m/QUOTED-PRINTABLE/i
                                || $escapedtype =~ m/^B$/i
                                || $escapedtype =~ m/BASE64/i
                             )
                       );

                  # detect value encoding directive here
                  $encoding = $escapedtype if $entry->{TYPES}{$type} =~ m/^ENCODING$/i;

                  if ($version <= 2.1) {
                     $escapedtype = 'BASE64' if $escapedtype =~ m/^B$/i;

                     # Quoted-printable is preferred for most propertynames
                     # if any encoding at all is defined
                     if ($propertyname !~ m/^(?:PHOTO|LOGO|SOUND|KEY)$/i && $escapedtype eq 'BASE64') {
                        $encoding = $escapedtype = 'QUOTED-PRINTABLE';
                     }

                     $typeoutput .= $entry->{TYPES}{$type} . '=' . $escapedtype . ';';
                  } elsif ($version == 3.0) {
                     # Adhere to RFC 2426 section 5: Differences from vCard 2.1
                     if ($escapedtype =~ m/QUOTED-PRINTABLE/i || $escapedtype =~ m/BASE64/i) {
                        # version 3.0 does not support or allow quoted-printable.
                        # encode all quoted-printables as base64.
                        $encoding = $escapedtype = 'B';
                     } elsif ($entry->{TYPES}{$type} eq 'CHARSET') {
                        # version 3.0 does not support or allow charset
                        next;
                     }

                     # group like types
                     $fliptypes{$entry->{TYPES}{$type}} .= "$escapedtype,";
                  }
               }

               if ($version <= 2.1) {
                  if ((length $valueoutput > 76 || $valueoutput =~ m/\n/) && $encoding eq undef && $propertyname ne 'AGENT') {
                     $typeoutput .= 'ENCODING=QUOTED-PRINTABLE;';
                     $encoding = 'QUOTED-PRINTABLE';
                  }
               } elsif ($version == 3.0) {
                  foreach my $type (sort keys %fliptypes) {
                     $fliptypes{$type} =~ s/,$//; # no trailing comma
                     $typeoutput .= $type . '=' . $fliptypes{$type} . ';';
                  }
               }

               openwebmailerror(gettext('A contact contains a property with illegal characters in the property type:') . " ($xowmuid :: $propertyname)")
                  if $typeoutput =~ m/[\n\r]/;

               # no trailing, only leading semi-colon
               $typeoutput =~ s/(.*);$/;$1/;
            } else {
               # no types were defined - do we need to add some?
               if ($version <= 2.1) {
                  # Microsoft Outlook does not know how to unwrap lines and completely ignores the line wrapping
                  # specifications described in the RFCs (shock and surprise). So, make long lines quoted-
                  # printable for outlook compatibility. :(
                  if (($valueoutput =~ m/\n/ || length $valueoutput > 76) && $encoding eq undef && $propertyname ne 'AGENT') {
                     $typeoutput = ';ENCODING=QUOTED-PRINTABLE';
                     $encoding = 'QUOTED-PRINTABLE';
                  }
               }
            }

            # Prepare the group output string
            if (defined $entry->{GROUP}) {
               vcard_escape_chars2($entry->{GROUP});

               $groupoutput = $entry->{GROUP} . '.';

               openwebmailerror(gettext('A contact contains a property with illegal characters in the property group:') . " ($xowmuid :: $propertyname)")
                  if $groupoutput =~ m/[\n\r]/;
            }

            # Encode the value output string (or binary info) if needed
            if ($encoding =~ m/^B$/i || $encoding =~ m/BASE64/i) {
               # unescape and encode the value
               $valueoutput =~ s/\\n/\n/g if $version == 3.0;
               vcard_unescape_chars($valueoutput);
               $valueoutput = encode_base64($valueoutput,'');

               # BASE64s should start on new line and end with a blank line in vCard 2.1
               # BASE64 output needs to be folded here for vCard 2.1 or else it will not get
               # folded because it contains no whitespace
               if ($version <= 2.1) {
                  $valueoutput = "\r\n $valueoutput\r\n";
                  $valueoutput =~ s/(.{75})/$1\r\n /g;
               }
            } elsif ($encoding =~ m/QUOTED-PRINTABLE/i) {
               # The spec does not say to do this, but it conforms the output much better
               # $valueoutput =~ s/\t/    /g; # commented out for now

               # unescape and encode the value
               vcard_unescape_chars($valueoutput);
               $valueoutput =~ s/\r\n/\n/g; # per vCard 2.1 section 2.1.3 - to get =0D=0A
               $valueoutput =~ s/\r/\n/g;   # per vCard 2.1 section 2.1.3 - to get =0D=0A
               $valueoutput =~ s/\n/\r\n/g; # per vCard 2.1 section 2.1.3 - to get =0D=0A
               $valueoutput = encode_qp($valueoutput, '');
            }

            # Assemble our final output for this property name entry
            my $finaloutput = $groupoutput . $propertyname . $typeoutput . ':' . $valueoutput . "\n";

            # In recursive scenarios we need to trim the ending to avoid multiple CRs
            $finaloutput =~ s/(\r|\\n|\n)+$/\n/;

            # standardize line endings
            $finaloutput =~ s/\s+$/\r\n/g;

            # Fold the output per RFC specs
            if (length $finaloutput > 76) {
               if ($encoding =~ m/QUOTED-PRINTABLE/i) {
                  $finaloutput =~ s/(.{70,74}[^=])([^=\s])/$1=\r\n$2/g;
               } else {
                  if ($version <= 2.1) {
                     # any line longer than 76 characters will already be quoted-printable
                     # (thanks Microsoft), so do not worry about folding.
                  } elsif ($version == 3.0) {
                     # Folding can be on any character. Lines should be
                     # 76 characters wide.
                     $finaloutput =~ s/(.{75})/$1\r\n /g;
                  }
               }
            }

            # Append this entry to the vcard output
            push(@vcard,$finaloutput);
         }
      }

      unshift(@vcard, ("BEGIN:VCARD\r\n","VERSION:$version\r\n")); # append to head
      push(@vcard, "END:VCARD\r\n\r\n");                           # append to tail

      $output .= join('', @vcard);
   }

   # This routine is recursive, so do not mess with the output!!!
   return $output;
}

sub outputvcard_N {
   my ($r_entry, $version) = @_;

   my $n_familyname      = $r_entry->{VALUE}{FAMILYNAME} || '';
   my $n_givenname       = $r_entry->{VALUE}{GIVENNAME} || '';
   my $n_additionalnames = $r_entry->{VALUE}{ADDITIONALNAMES} || '';
   my $n_nameprefix      = $r_entry->{VALUE}{NAMEPREFIX} || '';
   my $n_namesuffix      = $r_entry->{VALUE}{NAMESUFFIX} || '';

   openwebmailerror(gettext('At least one name attribute of a contact must be defined.'))
      if $n_familyname . $n_givenname . $n_additionalnames . $n_nameprefix . $n_namesuffix eq '';

   vcard_escape_chars($n_familyname,$n_givenname,$n_additionalnames,$n_nameprefix,$n_namesuffix);

   $r_entry->{VALUE} = join(';', $n_familyname, $n_givenname, $n_additionalnames, $n_nameprefix, $n_namesuffix);

   return $r_entry;
}

sub outputvcard_BDAY {
   # We have decided to only support ISO-8601 in two formats:
   # YYYY-MM-DD and YYYYMMDD
   # If anyone wants to implement complete ISO-8601 support for
   # other formats specified as acceptable in RFC 2426 section 3.1.5
   # for the BDAY property, please be my guest.
   my ($r_entry, $version) = @_;

   my $bdayyear  = $r_entry->{VALUE}{YEAR}  || undef;
   my $bdaymonth = $r_entry->{VALUE}{MONTH} || undef;
   my $bdayday   = $r_entry->{VALUE}{DAY}   || undef;

   openwebmailerror(gettext('The birthday year must be a number between 1 and 9999.'))
      if defined $bdayyear && ($bdayyear !~ m/^\d{1,4}$/ || ($bdayyear < 1 || $bdayyear > 9999));

   openwebmailerror(gettext('The birthday month must be a number between 1 and 12.'))
      if defined $bdaymonth && ($bdaymonth !~ m/^\d{1,2}$/ || ($bdaymonth < 1 || $bdaymonth > 12));

   if (defined $bdayday) {
      openwebmailerror(gettext('The birthday day must be a number between 1 and 31.'))
         if $bdayday !~ m/^\d{1,2}$/ || ($bdayday < 1 || $bdayday > 31);

      if (defined $bdayyear && defined $bdaymonth) {
         my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
         $days_in_month[2]++ if $bdayyear % 4 == 0 && ($bdayyear % 100 != 0 || $bdayyear % 400 == 0);

         openwebmailerror(gettext('The birth day exceeds the maximum number of days in the selected birth month.'))
            if $bdayday > $days_in_month[$bdaymonth];
      }
   }

   if (defined $bdayyear || defined $bdaymonth || defined $bdayday) {
      if (!defined $bdayyear || !defined $bdaymonth || !defined $bdayday) {
         openwebmailerror(gettext('The day, month, and year must all be defined to store a birthday for a contact.'));
      } else {
         $r_entry->{VALUE} = sprintf("%04d-%02d-%02d",$bdayyear,$bdaymonth,$bdayday);
      }
   } else {
      $r_entry->{VALUE} = '';
   }

   return $r_entry;
}

sub outputvcard_ADR {
   my ($r_entry, $version) = @_;

   my $country           = $r_entry->{VALUE}{COUNTRY} || '';
   my $extendedaddress   = $r_entry->{VALUE}{EXTENDEDADDRESS} || '';
   my $locality          = $r_entry->{VALUE}{LOCALITY} || '';
   my $region            = $r_entry->{VALUE}{REGION} || '';
   my $street            = $r_entry->{VALUE}{STREET} || '';
   my $postalcode        = $r_entry->{VALUE}{POSTALCODE} || '';
   my $postofficeaddress = $r_entry->{VALUE}{POSTOFFICEADDRESS} || '';

   vcard_escape_chars($country,$extendedaddress,$locality,$region,$street,$postalcode,$postofficeaddress);

   if ("$country$extendedaddress$locality$region$street$postalcode$postofficeaddress" eq '') {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(';',$postofficeaddress,$extendedaddress,$street,$locality,$region,$postalcode,$country);
   }

   return $r_entry;
}

sub outputvcard_TZ {
   # format like: -05:00
   my ($r_entry, $version) = @_;

   $r_entry->{VALUE} = '' unless defined $r_entry->{VALUE};

   if (my ($plusminus,$hour,$min) = $r_entry->{VALUE} =~ m/^([+-])?(\d{2}):?(\d{2})$/) { # -05:00 0500 +05:00
      openwebmailerror(gettext('The timezone hour must be a number from 0 to 13.'))
         if $hour < 0 || $hour > 13;

      openwebmailerror(gettext('The timezone minute must be either 00 or 30.'))
         unless $min == 0 || $min == 30;

      $r_entry->{VALUE} = ((defined $plusminus && $plusminus eq '-') ? '-' : '') . $hour . ':' . $min;
   } else {
      openwebmailerror(gettext('The timezone value is invalid:') . " ($r_entry->{VALUE})")
         if $r_entry->{VALUE} ne '';
   }

   return $r_entry;
}

sub outputvcard_GEO {
   # Values should be in decimal degrees to six decimal places per RFC.
   my ($r_entry, $version) = @_;

   my $geo_longitude = $r_entry->{VALUE}{LONGITUDE} || '';
   my $geo_latitude  = $r_entry->{VALUE}{LATITUDE}  || '';

   $geo_longitude =~ s/\s+//g;
   $geo_latitude  =~ s/\s+//g;

   if ($geo_longitude =~ m/^([+-])?(\d+)\.?(\d+)?$/) {
      $geo_longitude = "$2" . ($3 ? ".$3" : ".0");
      $geo_longitude = ($1 ? $1 : '') . sprintf('%.6f', $geo_longitude);
   } else {
      openwebmailerror(gettext('Invalid longitude format.')) if $geo_longitude ne '';
   }

   if ($geo_latitude =~ m/^([+-])?(\d+)\.?(\d+)?$/) {
      $geo_latitude = "$2" . ($3 ? ".$3" : ".0");
      $geo_latitude = ($1 ? $1 : '') . sprintf('%.6f', $geo_latitude);
   } else {
      openwebmailerror(gettext('Invalid latitude format.')) if $geo_latitude ne '';
   }

   openwebmailerror(gettext('Both latitude and longitude must be defined.'))
      if ($geo_latitude eq '' && $geo_longitude ne '')
         || ($geo_latitude ne '' && $geo_longitude eq '');

   if ($geo_longitude eq '' && $geo_latitude eq '') {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(';', ($geo_latitude, $geo_longitude));
   }

   return $r_entry;
}

sub outputvcard_AGENT {
   my ($r_entry, $version) = @_;

   if (exists $r_entry->{TYPES}{VCARD} && defined $r_entry->{TYPES}{VCARD}) {
      $r_entry->{VALUE} = outputvcard($r_entry->{VALUE}, $version);

      # The BEGIN should start on its own line
      $r_entry->{VALUE} =~ s/^/\r\n/;

      # The result will be folded, which we do not want yet because the
      # final folding happens after this. We do not want double folding
      # so unfold it here.
      if ($version <= 2.1) {
         $r_entry->{VALUE} =~ s/\r\n([ \t])/$1/sg;
      } elsif ($version == 3.0) {
         $r_entry->{VALUE} =~ s/\r\n[ \t]//sg;

         # CRs should be literal string '\n'
         $r_entry->{VALUE} =~ s/\r\n/\n/g;
         $r_entry->{VALUE} =~ s/\n/\\n/g;
      }
   }

   return $r_entry;
}

sub outputvcard_ORG {
   my ($r_entry, $version) = @_;

   my $org_organizationname    = exists $r_entry->{VALUE}{ORGANIZATIONNAME} ? $r_entry->{VALUE}{ORGANIZATIONNAME} : '';
   my @org_organizationalunits = exists $r_entry->{VALUE}{ORGANIZATIONALUNITS} ? @{$r_entry->{VALUE}{ORGANIZATIONALUNITS}} : ();

   vcard_escape_chars($org_organizationname);
   vcard_escape_chars(@org_organizationalunits);

   if (
         $org_organizationname eq ''
         && (
               $#org_organizationalunits < 0
               || ($#org_organizationalunits == 0 && $org_organizationalunits[0] eq '')
            )
      ) {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(';', $org_organizationname, @org_organizationalunits);
   }

   return $r_entry;
}

sub outputvcard_CATEGORIES {
   my ($r_entry, $version) = @_;

   my @categories = exists $r_entry->{VALUE}{CATEGORIES} ? @{$r_entry->{VALUE}{CATEGORIES}} : undef;

   vcard_escape_chars(@categories);

   $r_entry->{VALUE} = join(',', @categories);

   return $r_entry;
}

sub outputvcard_REV {
   my ($r_entry, $version) = @_;

   my $rev_sec  = $r_entry->{VALUE}{SECOND};
   my $rev_min  = $r_entry->{VALUE}{MINUTE};
   my $rev_hour = $r_entry->{VALUE}{HOUR};
   my $rev_mday = $r_entry->{VALUE}{DAY};
   my $rev_mon  = $r_entry->{VALUE}{MONTH};
   my $rev_year = $r_entry->{VALUE}{YEAR};

   vcard_escape_chars($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year);

   $r_entry->{VALUE} = $rev_year .
                       '-' .
                       sprintf("%02d-%02dT%02d:%02d:%02dZ",$rev_mon,$rev_mday,$rev_hour,$rev_min,$rev_sec);

   return $r_entry;
}

sub outputvcard_X_OWM_BDAY {
   # We have decided to only support ISO-8601 in two formats:
   # YYYY-MM-DD and YYYYMMDD
   # TODO: implement complete ISO-8601 support for other formats
   # specified as acceptable in RFC 2426 section 3.1.5 for the BDAY
   # property
   # the vcard spec does not support partial BDAY date storage
   # so we support it with this X-OWM-BDAY propertyname
   my ($r_entry, $version) = @_;

   my $bdayyear  = $r_entry->{VALUE}{YEAR}  || '';
   my $bdaymonth = $r_entry->{VALUE}{MONTH} || '';
   my $bdayday   = $r_entry->{VALUE}{DAY}   || '';

   openwebmailerror(gettext('The birthday year must be a number between 1 and 9999.'))
      if $bdayyear ne '' && ($bdayyear !~ m/^\d{1,4}$/ || ($bdayyear < 1 || $bdayyear > 9999));

   openwebmailerror(gettext('The birthday month must be a number between 1 and 12.'))
      if $bdaymonth ne '' && ($bdaymonth !~ m/^\d{1,2}$/ || ($bdaymonth < 1 || $bdaymonth > 12));

   openwebmailerror(gettext('The birthday day must be a number between 1 and 31.'))
      if $bdayday ne '' && ($bdayday !~ m/^\d{1,2}$/ || ($bdayday < 1 || $bdayday > 31));

   if ($bdayyear ne '' && $bdaymonth ne '' && $bdayday ne '') {
      my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
      $days_in_month[2]++ if $bdayyear % 4 == 0 && ($bdayyear % 100 != 0 || $bdayyear % 400 == 0);

      openwebmailerror(gettext('The birth day exceeds the maximum number of days in the selected birth month.'))
         if $bdayday > $days_in_month[$bdaymonth];
   }

   $bdayyear  = 0 unless $bdayyear;
   $bdaymonth = 0 unless $bdaymonth;
   $bdayday   = 0 unless $bdayday;

   $r_entry->{VALUE} = sprintf('%04d-%02d-%02d', $bdayyear, $bdaymonth, $bdayday);
   $r_entry->{VALUE} = '' if $r_entry->{VALUE} eq '0000-00-00';

   return $r_entry;
}

sub outputvcard_X_OWM_CUSTOM {
   my ($r_entry, $version) = @_;

   my $customname   = $r_entry->{VALUE}{CUSTOMNAME} || '';
   my @customvalues = $r_entry->{VALUE}{CUSTOMVALUES} ? @{$r_entry->{VALUE}{CUSTOMVALUES}} : undef;

   vcard_escape_chars($customname);
   vcard_escape_chars(@customvalues);

   if (
         $customname eq ''
         && (
               $#customvalues < 0
               || ($#customvalues == 0 && $customvalues[0] eq '')
            )
      ) {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(';', $customname, @customvalues);
   }

   return $r_entry;
}

sub generate_xowmuid {
   # xowmuid is required as the key for vcard data structure hashes
   # it must be unique for each vcard data structure
   # this routine generates a unique xowmuid every time it is called
   # an xowmuid looks like: 20040909-073403-35PDGCRZE5OQ-HVLF
   my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
   my @chars = ( 'A' .. 'Z', 0 .. 9 );
   my $longrandomstring  = join('', map { $chars[rand @chars] } 1..12);
   my $shortrandomstring = join('', map { $chars[rand @chars] } 1..4);
   my $uid = ($uid_year + 1900) .
             sprintf("%02d", ($uid_mon + 1)) .
             sprintf("%02d", $uid_mday) .
             '-' .
             sprintf("%02d", $uid_hour) .
             sprintf("%02d", $uid_min) .
             sprintf("%02d", $uid_sec) .
             '-' .
             $longrandomstring .
             '-' .
             $shortrandomstring;
   return $uid;
}

sub vcard_escape_chars {
   for (@_) {
      s#;#\\;#g if defined;
      s#,#\\,#g if defined;
   }
}

sub vcard_unescape_chars {
   for (@_) {
      s#\\;#;#g if defined;
      s#\\,#,#g if defined;
   }
}

sub vcard_escape_chars2 {
   for (@_) {
      s#;#\\;#g if defined;
      s#:#\\:#g if defined;
      s#,#\\,#g if defined;
   }
}

sub vcard_unescape_chars2 {
   for (@_) {
      s#\\;#;#g if defined;
      s#\\:#:#g if defined;
      s#\\,#,#g if defined;
   }
}

sub vcard_protect_chars {
   for (@_) {
      s/\\;/\@\@\@/g if defined;
      s/\\:/\#\@\#/g if defined;
      s/\\,/\^\@\^/g if defined;
   }
}

sub vcard_unprotect_chars {
   for (@_) {
      s/\@\@\@/;/g if defined;
      s/\#\@\#/:/g if defined;
      s/\^\@\^/,/g if defined;
   }
}

1;
