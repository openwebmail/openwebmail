#
# vcard.pl - read/write address book vCard data
#
# Description:
# This is a companion script to vfile.pl and is meant to be called from within
# that script. This script does not do any character decoding/conversion, so if
# you try to use it directly it will fail on files with 16/32UTF double byte
# characters (ie Japanese).
# See vfile.pl for usage instuctions.
#
# Author:
# Alex Teslik <alex@acatysmoof.com>
#
# Versions:
# 20040325 - Initial version.
#

use strict;
use MIME::QuotedPrint;
use MIME::Base64;
use CGI::Carp qw(fatalsToBrowser carpout);

use vars qw($vcarddebug %special_property_handlers);

#print header();
$vcarddebug = 0;
#$prodid_string = "$config{'name'} $config{'version'} $config{'releasedate'}";

# Map the known propertyname to its special parser or writer handler. You can use
# this as a hook to add special parsing routines for a specific propertyvalue.
# This supports the "X-" extension defined in the RFC. (e.g:
# X-SOMECOMPANY-SOMEPROPERTYNAME). Propertynames with no value means no special
# handler, which is okay. The value of that propertyname will not be modified at
# all and will be returned as is. Propertynames that are not defined here at all
# are also returned as-is. We try to define all propertynames explicitly here to
# avoid any question as to whether a propertyname value gets modified by a
# handler or not.
# The number assigned to each propertyname is the order that the properties get
# written out to vcard files. There are gaps in case other properties arise that
# need to get put inbetween.
%special_property_handlers = (
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
   'BDAY'        => [\&parsevcard_BDAY,\&outputvcard_BDAY,120],             # vCard 2.1 and 3.0
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
   'X-OWM-CUSTOM'  => [\&parsevcard_X_OWM_CUSTOM,\&outputvcard_X_OWM_CUSTOM,330],   # Openwebmail: user custom field
   'X-OWM-CHARSET' => ['','',340],                                                  # Openwebmail: vcard character set support
   'X-OWM-UID'     => [\&parsevcard_X_OWM_UID,'',350],                              # Openwebmail: unique id
);

sub parsevcard {
   # Parse vCard 2.1 and 3.0 format. Decode encoded strings and binary data. Pass
   # the final decoded value to a defined parser subroutine for that value name. Get
   # the parsed value back from that special sub and return a reference to a hash
   # data structure representing the vcard.
   my ($vcard, $version, $r_onlyreturn) = @_;

   my %parsedvcard = ();

   print "parsevcard: vCard looks like:\n\"$vcard\"\n\n" if $vcarddebug;
   print "parsevcard: version:\"$version\"\n" if $vcarddebug;

   # Get the line delimiters in order
   $vcard =~ s/(\S)\s+$/$1\r\n/g; # end of lines should always be a single CRLF

   # UNFOLD THE VCARD
   # The line delimiter is CRLF for vCard 2.1.
   # Replace CRLF+single whitespace character with single whitespace character.
   # refer to vCard 2.1 specification section 2.1.3
   $vcard =~ s/\r\n([ \t])/$1/sg if ($version <= 2.1);
   # The line delimiter is CRLF for vCard 3.0.
   # Replace CRLF+single whitespace character with nothing.
   # refer to RFC-2425 section 5.8.1
   $vcard =~ s/\r\n[ \t]//sg if ($version == 3.0);

   print "parsevcard: vCard has been reformatted:\n$vcard\n\n" if $vcarddebug;

   my ($depth, $appendnext, $propertykey, $propertygroup,
       $propertyname, $propertyvalue, @propertyparams,
       $encoding, $types_ref, $numberoftypes) = ();

   foreach my $line (split(/\n/,$vcard)) {
      $line =~ s/\r//g; # remove carriage-returns
      if ($line =~ m/^(?:\s+)?$/) {
         print "\nSkipping empty line:\"$line\"\n" if $vcarddebug;
         next; # skip blank lines
      }

      print "\n  processing line: '$line'\n" if $vcarddebug;
      print "       appendnext: $appendnext\n" if $vcarddebug;
      print "         encoding: $encoding\n" if $vcarddebug;
      print "            depth: $depth\n" if $vcarddebug;

      if ($appendnext) {
         if ($encoding =~ m/QUOTED-PRINTABLE/) {
            # append the next quoted-printable line to the propertyvalue
            $propertyvalue .= $line."\n";
            if ($line =~ m/\=$/) {
               print "NEXT LINE" if $vcarddebug;
               $propertyvalue =~ s/=[\r\n]$//s; # unfold quoted-printable
               next; # append the next line
            } else {
               chomp($propertyvalue);
               print " appending done - new propertyvalue:\n$propertyvalue\n" if $vcarddebug;
               # All the new lines are appended.
               # Decode the encoded block now that we have it all.
               $propertyvalue = decode_qp($propertyvalue);
            }
         } elsif ($encoding =~ m/BASE64/ || $encoding =~ m/^B$/) {
            # Decode the encoded block.
            $propertyvalue = decode_base64($propertyvalue);

            # special processing of this base64 block?
            if ($special_property_handlers{$propertyname}[0]) {
               ($propertyname, $propertyvalue, $propertygroup, $types_ref) = $special_property_handlers{$propertyname}[0]->($propertyname, $propertyvalue, $version, $propertygroup, $types_ref, $r_onlyreturn);
            }

            # store
            print "storing decoded base64 propertyvalue for $propertyname\n" if $vcarddebug;
            $parsedvcard{$propertyname}[@{$parsedvcard{$propertyname}}]{'VALUE'} = $propertyvalue;
            $parsedvcard{$propertyname}[(@{$parsedvcard{$propertyname}} - 1)]{'TYPES'} = $types_ref;

            print "\n\nStarting new property set.\n" if $vcarddebug;
            ($propertykey, $propertygroup, $propertyvalue, $encoding, $numberoftypes) = ();
         } elsif ($encoding =~ m/AGENT/) {
            if ($line =~ /^BEGIN:/i) {
               $depth++;
               print "BEGIN block AGENT - setting depth to $depth\n" if $vcarddebug;
            } elsif ($line =~ /^END:/i) {
               $depth--;
               $propertyvalue .= "$line\n" if ($depth >= 1);
               $line = '';
               print "END block AGENT - setting depth to $depth\n" if $vcarddebug;
            }
            if ($depth >= 2) {
               $propertyvalue .= "$line\n";
               next;
            }
         }
         $appendnext = 0;
      }

      if ($line =~ /^END:/i) {
         $depth--;
         print "END block detected - setting depth to $depth\n" if $vcarddebug;
         if ($depth == 1) { $propertyvalue .= $line };
      } elsif ($line =~ /^BEGIN:/i) {
         $depth++;
         print "BEGIN block detected - setting depth to $depth\n" if $vcarddebug;
         next; # don't record BEGIN blocks
      }

      if ($depth == 1) {
         # propertyvalue may already be defined from encoding loops
         if ($propertyvalue eq undef && $propertykey eq undef) {

            # protect escaped semi-colon, colon, comma characters
            # with placeholders. We will convert them back later.
            vcard_protect_chars($line);

            ($propertykey, $propertyvalue) = $line =~ m/(\S+?):(.*)$/;

            @propertyparams = split(/;/, uc($propertykey));
            $propertyname = shift(@propertyparams);

            $propertyname =~ s/^\s+//; # no leading whitespace
            $propertyname =~ s/\s+$//; # no trailing whitespace
            $propertyvalue =~ s/^\s+//; # no leading whitespace
            $propertyvalue =~ s/\s+$//; # no trailing whitespace

            # property grouping support
            if ($propertyname =~ m/\./) {
               ($propertygroup, $propertyname) = split(/\./,$propertyname);
               if ($propertygroup =~ m/(?:\\n|\n)/i) {
                  croak("Group names may not contain carriage-return characters. Error: $propertygroup\n");
               }
            }

            # SOMEGROUP.TEL;TYPE=HOME,WORK:555-1212
            print "      propertykey: $propertykey\n" if $vcarddebug;                 # SOMEGROUP.TEL;TYPE=HOME,WORK
            print "     propertyname: $propertyname\n" if $vcarddebug;                # TEL
            print "    propertygroup: $propertygroup\n" if $vcarddebug;               # SOMEGROUP
            if ($vcarddebug) { print "   propertyparams: $_\n" for @propertyparams }; # [HOME,WORK] (as an array)
            print "    propertyvalue: $propertyvalue\n" if $vcarddebug;               # 555-1212

            # skip to next if necessary
            if (defined $r_onlyreturn && $propertyname ne "AGENT" && $propertyname ne "X-OWM-UID" && $propertyname ne "N") {
               # Don't skip AGENT - we may want the specific info in those embedded cards
               # Don't skip X-OWM-UID - or else it will be auto-assigned a new X-OWM-UID later, bad!
               # Don't skip N - we need it to build FN later
               if (exists(${$r_onlyreturn}{$propertyname})) {
                  print "R_ONLYRETURN: ${$r_onlyreturn}{$propertyname}\n" if $vcarddebug;
               } else {
                  # don't process this one. clear vars.
                  ($propertyname, $propertykey, $propertygroup, $propertyvalue) = ();
                  print "R_ONLYRETURN skipping...\n" if $vcarddebug;
                  next;
               }
            }

            # process propertyparams types array into a hash
            my %types = ();
            foreach my $propertytype (@propertyparams) {
               print "processing property parameter: '$propertytype'\n" if $vcarddebug;
               my ($key, $value);

               if ($propertytype =~ m/=/) {
                  ($key, $value) = split(/=/,$propertytype);
               } else {
                  $value = $propertytype;
                  $key = 'TYPE';
               }

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
                     print "activating appendnext for base64\n" if $vcarddebug;
                  }
                  # decode the one-line quoted-printables
                  $propertyvalue = decode_qp($propertyvalue);
               }

               # Assignments to the %types hash are flipped value=key on purpose.
               # Its easier to access later and values, not keys, are unique here.
               # vCard 2.1 only allows types like WORK
               # vCard 3.0 allows grouped types like WORK,VOICE,PREF
               # so we need to break them apart.
               print "adding to \%types: value:$value key:$key\n" if $vcarddebug;
               for (split(/,/, $value)) {
                  # unprotect semi-colon, colon, and comma characters
                  vcard_unprotect_chars($key,$_);
                  if ($key =~ m/(?:\\n|\n)/i || m/(?:\\n|\n)/i) {
                     croak("Property types may not contain carriage-return characters. Error: $key=$value\n");
                  }

                  $types{$_} = $key;
                  $numberoftypes++;
               };
            }
            $types_ref =  $numberoftypes ? \%types : undef;

            if ($propertyname eq "AGENT" && $propertyvalue eq undef) {
               $encoding = "AGENT";
               $appendnext = 1;
            }
         }

         next if $appendnext; # grab any extra lines needed and decode
         $propertyvalue = undef if $propertyvalue =~ m/^\s+$/; # undef all whitespace final values

         # Apply specific parsing to the propertyvalue based on the propertyname. This is
         # where hooks for specific propertynames get called, like parsevcard_ADR() to
         # process ADDRESS information. The hooks are defined as subroutines in the
         # special_property_handlers hash. Propertyname parsers can even call
         # parsevcard(), which is what enables recursive parsing.
         if ($special_property_handlers{$propertyname}[0]) {
            ($propertyname, $propertyvalue, $propertygroup, $types_ref) = $special_property_handlers{$propertyname}[0]->($propertyname, $propertyvalue, $version, $propertygroup, $types_ref, $r_onlyreturn);
         }

         # Unescape semi-colon, colon, return, and comma characters
         # It is also important to notice that base64 and qp decoded
         # $propertyvalues are not affected by these substitutions since
         # they never get here in the code.
         vcard_unprotect_chars($propertyvalue, $propertygroup, $propertyname);
         $propertyvalue =~ s/\\n/\n/ig;

         print "       FINALVALUE: $propertyvalue\n" if $vcarddebug;
         print "       FINALGROUP: $propertygroup\n" if $vcarddebug;
         print "       FINALTYPES: $types_ref\n" if $vcarddebug;

         my %finalparsedresult = ('VALUE' => $propertyvalue,
                                  'GROUP' => $propertygroup,
                                  'TYPES' => $types_ref);

         for (keys %finalparsedresult) { delete $finalparsedresult{$_} if $finalparsedresult{$_} eq '' };

         croak("vCard is not formatted properly. Propertyname cannot be determined on vcard line: \"$line\". vCard looks like:\n$vcard\n\n") if $propertyname eq undef;

         push(@{$parsedvcard{$propertyname}}, \%finalparsedresult) if $finalparsedresult{'VALUE'};

         # reset vars except for the propertyname in case it points
         # to an embedded vcard and we need it in the next loop.
         ($propertyname, $propertykey, $propertygroup, $propertyvalue, $encoding, $numberoftypes, $types_ref) = ();
      } elsif ($depth > 1) {
         # We are inside an embedded vFile. Append this line to the propertyvalue
         # until we get out of this embedded vFile (meaning depth <= 1).
         # The AGENT propertyname supports embedded vCards.
         $propertyvalue .= $line."\n";
      }
   }

   # don't allow multiple instances of these propertynames
   foreach my $limited (qw(N FN VERSION PROFILE BDAY REV TZ GEO PRODID SORT-STRING UID X-OWM-UID X-OWM-GROUP X-OWM-BOOK X-OWM-CHARSET)) {
      if (exists $parsedvcard{$limited} && defined $parsedvcard{$limited}[1]) {
         croak("Illegal vCard. The $limited propertyname can only exist once.\n\n$vcard\n\n");
      }
   }

   # define FN using N if FN not defined
   if (defined $parsedvcard{'N'} && $parsedvcard{'FN'} eq undef) {
      my $is_FN_required=1;
      $is_FN_required=0 if (defined $r_onlyreturn && !exists ${$r_onlyreturn}{'FN'});
      if ($is_FN_required) {


         $parsedvcard{'FN'}[0]{'VALUE'} .= $parsedvcard{'N'}[0]{'VALUE'}{'NAMEPREFIX'} if defined $parsedvcard{'N'}[0]{'VALUE'}{'NAMEPREFIX'};

         if (defined $parsedvcard{'N'}[0]{'VALUE'}{'GIVENNAME'} &&
             defined $parsedvcard{'N'}[0]{'VALUE'}{'FAMILYNAME'} &&
            $parsedvcard{'N'}[0]{'VALUE'}{'GIVENNAME'}=~/^[\xA1-\xF9][\x40-\x7E\xA1-\xFE]/) {		# chinese name
            $parsedvcard{'FN'}[0]{'VALUE'} .= " " . $parsedvcard{'N'}[0]{'VALUE'}{'FAMILYNAME'}		# big5:[A1-F9][40-7E,A1-FE], gb2312:[A1-F9][A1-FE]
                                                  . $parsedvcard{'N'}[0]{'VALUE'}{'GIVENNAME'};
            $parsedvcard{'FN'}[0]{'VALUE'} .= " " . $parsedvcard{'N'}[0]{'VALUE'}{'ADDITIONALNAMES'} if defined $parsedvcard{'N'}[0]{'VALUE'}{'ADDITIONALNAMES'};
         } else {
            $parsedvcard{'FN'}[0]{'VALUE'} .= " " . $parsedvcard{'N'}[0]{'VALUE'}{'GIVENNAME'} if defined $parsedvcard{'N'}[0]{'VALUE'}{'GIVENNAME'};
            $parsedvcard{'FN'}[0]{'VALUE'} .= " " . $parsedvcard{'N'}[0]{'VALUE'}{'ADDITIONALNAMES'} if defined $parsedvcard{'N'}[0]{'VALUE'}{'ADDITIONALNAMES'};
            $parsedvcard{'FN'}[0]{'VALUE'} .= " " . $parsedvcard{'N'}[0]{'VALUE'}{'FAMILYNAME'} if defined $parsedvcard{'N'}[0]{'VALUE'}{'FAMILYNAME'};
         }

         $parsedvcard{'FN'}[0]{'VALUE'} .= " " . $parsedvcard{'N'}[0]{'VALUE'}{'NAMESUFFIX'} if defined $parsedvcard{'N'}[0]{'VALUE'}{'NAMESUFFIX'};
         $parsedvcard{'FN'}[0]{'VALUE'} =~ s/^\s+//g; # no leading whitespace
      }
   }

   # remove N if it is no longer needed
   if (defined $r_onlyreturn) {
      if (!exists ${$r_onlyreturn}{'N'}) {
         delete $parsedvcard{'N'};
      }
   }

   # assign mandatory properties:
   ($propertyname, $parsedvcard{'X-OWM-UID'}[0]{'VALUE'}) = $special_property_handlers{'X-OWM-UID'}[0]->('X-OWM-UID',$parsedvcard{'X-OWM-UID'}[0]{'VALUE'});
   ($propertyname, $parsedvcard{'REV'}[0]{'VALUE'}) = $special_property_handlers{'REV'}[0]->('REV',$parsedvcard{'REV'}[0]{'VALUE'});

   # mandatory properties exist or croak
   if (!defined $r_onlyreturn) {
      croak("The N property is required and does not exist.\n") unless defined $parsedvcard{'N'}[0]{'VALUE'};
      if ($version == 3.0) { croak("The FN property is required and does not exist.\n") unless defined $parsedvcard{'FN'}[0]{'VALUE'} };
   }

   # The returned card should be the id of this card pointing
   # to a hash of all of the card data.
   my %finalcard = ();
   $finalcard{$parsedvcard{'X-OWM-UID'}[0]{'VALUE'}} = \%parsedvcard;

   # don't return X-OWM-UID when we only want partial info returned, unless specified
   if (defined $r_onlyreturn) {
      # make sure to delete X-OWM-UID last or other deletes will create it again
      if (!exists ${$r_onlyreturn}{'X-OWM-UID'}) {
         delete $finalcard{$parsedvcard{'X-OWM-UID'}[0]{'VALUE'}}{'X-OWM-UID'};
      }
   }

   if ($vcarddebug) {
      if (defined $r_onlyreturn) {
         print "r_onlyreturn defined\n";
         # print Dumper($r_onlyreturn);
      } else {
         print "r_onlyreturn is undefined\n";
      }
   }

   return (\%finalcard);
}

sub parsevcard_N {
   my ($name, $value, $version, $group, $r_types) = @_;
   my ($n_familyname, $n_givenname, $n_additionalnames, $n_nameprefix, $n_namesuffix) = split(/\;/,$value);
   if ($n_familyname.$n_givenname.$n_additionalnames.$n_nameprefix.$n_namesuffix eq '') {
      croak("Name must be defined.\n");
   }
   vcard_unprotect_chars($n_familyname, $n_givenname, $n_additionalnames, $n_nameprefix, $n_namesuffix);
   $value = { 'FAMILYNAME' => $n_familyname,
              'GIVENNAME'  => $n_givenname,
              'ADDITIONALNAMES' => $n_additionalnames,
              'NAMEPREFIX' => $n_nameprefix,
              'NAMESUFFIX' => $n_namesuffix };
   for (keys %{$value}) {
      ${$value}{$_} =~ s/^\s+//g; # No leading whitespace
      delete ${$value}{$_} if ${$value}{$_} eq undef; # Delete empty keys
   }
   return ($name, $value, $group, $r_types);
}

sub parsevcard_BDAY {
   # We have decided to only support ISO-8601 in two formats:
   # YYYY-MM-DD and YYYYMMDD
   # If anyone wants to implement complete ISO-8601 support for
   # other formats specified as acceptable in RFC 2426 section 3.1.5
   # for the BDAY property, please be my guest (and superstar).
   my ($name, $value, $version, $group, $r_types) = @_;
   my ($bdayyear, $bdaymonth, $bdayday);
   if ($value =~ m/^(\d{4})-?(\d{1,2})-?(\d{1,2})$/) { # ISO-8601
      ($bdayyear, $bdaymonth, $bdayday) = ($1, sprintf("%02d",$2), sprintf("%02d",$3));
      my $defined = 0;
      if ($bdayyear ne '') {
         $defined++;
         if ($bdayyear =~ m/^\d+$/) {
            if ($bdayyear < 0 || $bdayyear > 9999) {
               croak("The birthday year must a number between 0 and 9999\n\nBDAY:$value\n\n");
            }
         } else {
            croak("The birthday year value must be a number.\n\nBDAY:$value\n\n");
         }
      }
      if ($bdaymonth ne '') {
         $defined++;
         if ($bdaymonth =~ m/^\d+$/) {
            if ($bdaymonth < 1 || $bdaymonth > 12) {
               croak("The birthday month must be a number between 1 and 12\n\nBDAY:$value\n\n");
            }
         } else {
            croak("The birthday month value must be a number.\n\nBDAY:$value\n\n");
         }
      }
      if ($bdayday ne '') {
         $defined++;
         if ($bdayday =~ m/^\d+$/) {
            if ($bdayday < 1 || $bdayday > 31) {
               croak("The birthday day must be a number between 1 and 31\n\nBDAY:$value\n\n");
            } else {
               my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
               $days_in_month[2]++ if ( ($bdayyear%4)==0 && (($bdayyear%100)!=0||($bdayyear%400)==0) );
               if ($bdayday > $days_in_month[$bdaymonth]) {
                  croak("There are only $days_in_month[$bdaymonth] days in month $bdaymonth.\n\nBDAY:$value\n\n");
               }
            }
         } else {
            croak("The birthday day value must be a number.\n\nBDAY:$value\n\n");
         }
      }
      if ($defined > 0 && $defined < 3) {
         croak("The birthday day, month, and year must all be defined. You cannot only define some of them.\n\nBDAY:$value\n\n");
      }
      $value = { 'YEAR' => $bdayyear,
                 'MONTH' => $bdaymonth,
                 'DAY' => $bdayday };
   } else {
      if ($value ne '') {
         croak("The BDAY value is invalid. BDAY values must all be numeric and can only be separated by dashes.\n\nBDAY:$value\n\n");
      }
   }
   for (keys %{$value}) {
      ${$value}{$_} =~ s/^\s+//g; # No leading whitespace
      delete ${$value}{$_} if ${$value}{$_} eq undef; # Delete empty keys
   }
   return ($name, $value, $group, $r_types);
}

sub parsevcard_ADR {
   my ($name, $value, $version, $group, $r_types) = @_;
   my ($adr_postofficeaddress, $adr_extendedaddress, $adr_street,
       $adr_locality, $adr_region, $adr_postalcode, $adr_country) = split(/\;/,$value);
   vcard_unprotect_chars($adr_postofficeaddress, $adr_extendedaddress, $adr_street,
                         $adr_locality, $adr_region, $adr_postalcode, $adr_country);
   $value = { 'POSTOFFICEADDRESS' => $adr_postofficeaddress,
              'EXTENDEDADDRESS' => $adr_extendedaddress,
              'STREET' => $adr_street,
              'LOCALITY' => $adr_locality,
              'REGION' => $adr_region,
              'POSTALCODE' => $adr_postalcode,
              'COUNTRY' => $adr_country };
   for (keys %{$value}) {
      # No carriage returns in address lines. Thats what LABEL is for.
      ${$value}{$_} =~ s/[\r\n]+/ /g;
      # No leading whitespace
      ${$value}{$_} =~ s/^\s+//g;
      # Delete empty keys
      delete ${$value}{$_} if ${$value}{$_} eq undef;
   }
   return ($name, $value, $group, $r_types);
}

sub parsevcard_TZ {
   my ($name, $value, $version, $group, $r_types) = @_;
   if ($value =~ m/;/) {
      # support for the vcard 3.0 single value format
      # which looks like: -05:00; EST; Raleigh/North America
      # in addition to the more popular format like: -05:00
      my ($utc_offset, $othercrap) = split(/;/,$value);
      $value = $utc_offset;
   }
   if ($value =~ m/^([+-])?(\d{2}):?(\d{2})$/) { #-05:00 0500 +05:00
      if ($2 < 0 || $2 > 13) {
         croak("Timezone hour must be a valid number from 0 to 13.\n\nTZ:$value\n\n");
      } elsif ($3 != 0) {
         if ($3 != 30) {
            croak("Timezone minute must be either 00 or 30.\n\nTZ:$value\n\n");
         }
      }
      $value = (($1 eq '-')?'-':'+').$2.$3;
   } else {
      if ($value ne '') {
         croak("Timezone can only contain numeric characters, +, and -.\n\nTZ:$value\n\n");
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
   my ($geo_latitude, $geo_longitude) = $value =~ m/(\S+)[,;:](\S+)/;
   $geo_latitude =~ s/\s+//g;
   $geo_longitude =~ s/\s+//g;
   if ($geo_latitude =~ m/^([+-])?(\d+)\.?(\d+)?$/) {
      $geo_latitude = "$2".($3?".$3":".0");
      $geo_latitude = ($1?$1:'').sprintf("%.6f",$geo_latitude);
   } else {
      croak("The GEO value is not valid. Numeric characters, +, and - only:\n\nGEO:$value\n\n");
   }
   if ($geo_longitude =~ m/^([+-])?(\d+)\.?(\d+)?$/) {
      $geo_longitude = "$2".($3?".$3":".0");
      $geo_longitude = ($1?$1:'').sprintf("%.6f",$geo_longitude);
   } else {
      croak("The GEO value is not valid. Numeric characters, +, and - only:\n\nGEO:$value\n\n");
   }
   $value = { 'LATITUDE'  => $geo_latitude,
              'LONGITUDE' => $geo_longitude };
   for (keys %{$value}) {
      ${$value}{$_} =~ s/\s+//g; # No whitespace
      delete ${$value}{$_} if ${$value}{$_} eq undef; # Delete empty keys
   }
   return ($name, $value, $group, $r_types);
}

sub parsevcard_AGENT {
   my ($name, $value, $version, $group, $r_types, $r_onlyreturn) = @_;
   if ($r_types->{URI} || $r_types->{TEXT} || $r_types->{URL}) {
      # This AGENT value is just a string of text,url, or uri. No vcard here.
      return($name, $value, $group, $r_types);
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
   my ($org_organizationname, @org_organizationalunits) = split(/\;/,$value);
   vcard_unprotect_chars($org_organizationname);
   vcard_unprotect_chars(@org_organizationalunits);
   s/^\s+//g for @org_organizationalunits; # No leading whitespace
   my $org_organizationalunits = @org_organizationalunits ? \@org_organizationalunits : undef;
   $value = { 'ORGANIZATIONNAME' => $org_organizationname,
              'ORGANIZATIONALUNITS' => $org_organizationalunits };
   for (keys %{$value}) {
      ${$value}{$_} =~ s/^\s+//g; # No leading whitespace
      delete ${$value}{$_} if ${$value}{$_} eq undef; # Delete empty keys
   }
   return ($name, $value, $group, $r_types);
}

sub parsevcard_CATEGORIES {
   my ($name, $value, $version, $group, $r_types) = @_;
   my @categories = split(/,/,$value);
   s/^\s+//g for @categories; # No leading whitespace
   vcard_unprotect_chars(@categories);
   my $categories = @categories ? \@categories : undef;
   $value = { 'CATEGORIES' => $categories };
   for (keys %{$value}) { delete ${$value}{$_} if ${$value}{$_} eq undef; }
   return ($name, $value, $group, $r_types);
}

sub parsevcard_REV {
   my ($name, $value, $version, $group, $r_types) = @_;
   my ($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year,$rev_wday,$rev_yday,$rev_isdst);
   if ($value =~ m/^(\d{4})-?(\d{2})-?(\d{2})T?(\d{2})?\:?(\d{2})?\:?(\d{1,2})?Z?/) {
      ($rev_year, $rev_mon, $rev_mday, $rev_hour, $rev_min, $rev_sec) =
         $value =~ m/^(\d{4})-?(\d{2})-?(\d{2})T?(\d{2})?\:?(\d{2})?\:?(\d{1,2})?Z?/;
   } else {
      # REV is either undefined or doesn't jive - make a new one
      ($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year,$rev_wday,$rev_yday,$rev_isdst) = gmtime(time);
      $rev_mon++; $rev_year+=1900;
   }
   $value = { 'YEAR' => $rev_year,
              'MONTH' => $rev_mon,
              'DAY' => $rev_mday,
              'HOUR' => $rev_hour,
              'MINUTE' => $rev_min,
              'SECOND' => $rev_sec };
   for (keys %{$value}) {
      ${$value}{$_} =~ s/^\s+//g; # No leading whitespace
      delete ${$value}{$_} if ${$value}{$_} eq undef; # Delete empty keys
   }
   return ($name, $value, $group, $r_types);
}

sub parsevcard_X_OWM_UID {
   # This vCard implementation demands a X-OWM-UID for all objects,
   # which is a unique id for tracking the vcard in the software.
   # Therefore, if a X-OWM-UID is not found for an object, then
   # this parser will add one, free of charge ;)
   my ($name, $value, $version, $group, $r_types) = @_;
   if (defined $value) {
      return ($name, $value, $group, $r_types);
   } else {
      my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
      my @chars = ( 'A' .. 'Z', 0 .. 9 );
      my $longrandomstring = join '', map { $chars[rand @chars] } 1..12;
      my $shortrandomstring = join '', map { $chars[rand @chars] } 1..4;
      my $uid = ($uid_year+1900).sprintf("%02d",($uid_mon+1)).sprintf("%02d",$uid_mday)."-".
                sprintf("%02d",$uid_hour).sprintf("%02d",$uid_min).sprintf("%02d",$uid_sec)."-".
                $longrandomstring."-".$shortrandomstring;
      return ($name, $uid, $group, $r_types);
   }
}

sub parsevcard_X_OWM_CUSTOM {
   my ($name, $value, $version, $group, $r_types) = @_;
   my ($customname, @customvalues) = split(/\;/,$value);
   vcard_unprotect_chars($customname);
   vcard_unprotect_chars(@customvalues);
   s/^\s+//g for @customvalues; # No leading whitespace
   my $customvalues = @customvalues ? \@customvalues : undef;
   $value = { 'CUSTOMNAME' => $customname,
              'CUSTOMVALUES' => $customvalues };
   for (keys %{$value}) {
      ${$value}{$_} =~ s/^\s+//g; # No leading whitespace
      delete ${$value}{$_} if ${$value}{$_} eq undef; # Delete empty keys
   }
   return ($name, $value, $group, $r_types);
}

sub outputvcard {
   # Take a vCard data structure and output a vCard in either 2.1 or 3.0 format.
   my ($r_vcards, $version, $r_exclude_propertynames) = @_;

   my $vcarddebugoutput = 0;

   print "OUTPUTVCARD-----------------\n" if $vcarddebugoutput;

   $version = "3.0" if ($version eq undef || $version eq '');

   my $output = '';

   foreach my $xowmuid (sort keys %{$r_vcards}) {
      print "Card before xowmuid check: \"$xowmuid\n\"" if $vcarddebugoutput;
      if ($xowmuid eq undef || $xowmuid eq '') {
         # require an xowmuid
         my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
         my @chars = ( 'A' .. 'Z', 0 .. 9 );
         my $longrandomstring = join '', map { $chars[rand @chars] } 1..12;
         my $shortrandomstring = join '', map { $chars[rand @chars] } 1..4;
         my $uid = ($uid_year+1900).sprintf("%02d",($uid_mon+1)).sprintf("%02d",$uid_mday)."-".
                   sprintf("%02d",$uid_hour).sprintf("%02d",$uid_min).sprintf("%02d",$uid_sec)."-".
                   $longrandomstring."-".$shortrandomstring;
         $r_vcards->{$uid} = $r_vcards->{$xowmuid};
         delete $r_vcards->{$xowmuid};
         $xowmuid = $uid;
      }
      print "Card after xowmuid check: \"$xowmuid\n\"" if $vcarddebugoutput;

      my @vcard = ();
      # get the order of the propertynames as described by %special_property_handlers
      # to ensure all our cards propertynames write out in the same order every time.
      my @sortedpropertynames =  map { $_->[1] }
                                sort { $a->[0] <=> $b->[0] || lc($a->[1]) cmp lc($b->[1]) }
                                 map { [ defined($special_property_handlers{$_}[2])?$special_property_handlers{$_}[2]:9999 , $_ ] }
                                keys %{${$r_vcards}{$xowmuid}};

      foreach my $propertyname (@sortedpropertynames) {
         print "Propertyname: $propertyname\n" if $vcarddebugoutput;
         next if (exists($r_exclude_propertynames->{$propertyname}));
         next if $propertyname =~ m/^(BEGIN|END|VERSION)$/i;
         for (my $entrynum=0;$entrynum<@{$r_vcards->{$xowmuid}{$propertyname}};$entrynum++) {
            print "Entrynum: $entrynum\n" if $vcarddebugoutput;

            # Make a copy of this entry and work from that so we don't modify
            # the original data structure in case caller needs to use it later.
            my %entry = %{$r_vcards->{$xowmuid}{$propertyname}[$entrynum]};
            my $entry = \%entry;

            # Apply special handling before we try further parsing.
            # Some values need to be converted to single text strings before they get processed.
            if ($special_property_handlers{$propertyname}[1]) {
               $entry = $special_property_handlers{$propertyname}[1]->($entry,$version);
            }

            my $typeoutput = '';
            my $groupoutput = '';
            my $valueoutput = '';
            my $encoding = '';

            # Prepare the value output string
            $valueoutput = $entry->{'VALUE'};

            # Standardize CRLF,LF,and CR into CR for the value
            if ($propertyname !~ m/^(?:PHOTO|KEY|LOGO|SOUND)$/) {
               $valueoutput =~ s/\r\n/\@\@\@/g;
               $valueoutput =~ s/\r/\@\@\@/g;
               $valueoutput =~ s/\n/\@\@\@/g;
               $valueoutput =~ s/\@\@\@/\n/g;
            }

            next if ($valueoutput eq undef || $valueoutput eq ''); # skip empty properties

            # Escape the value unless it was already escaped by the special handler.
            # Special handlers can introduce comma field delimiters, so don't change this.
            vcard_escape_chars($valueoutput) unless $special_property_handlers{$propertyname}[1];
            $valueoutput =~ s/\n/\\n/g if ($version == 3.0);

            # Prepare the types output string
            if (defined $entry->{'TYPES'}) {
               my %fliptypes = ();
               foreach my $type (keys %{$entry->{'TYPES'}}) {
                  my $escapedtype = $type;
                  vcard_escape_chars2($escapedtype, ${$entry}{'TYPES'}{$type});

                  # this is to support crappy implementations that do stuff
                  # against spec like: TYPE=QUOTED-PRINTABLE
                  if (${$entry}{'TYPES'}{$type} eq 'TYPE' && ($escapedtype =~ m/QUOTED-PRINTABLE/i || $escapedtype =~ m/^B$/i || $escapedtype =~ m/BASE64/i)) {
                     ${$entry}{'TYPES'}{$type} = 'ENCODING';
                  }

                  # detect value encoding directive here
                  if (${$entry}{'TYPES'}{$type} =~ m/^ENCODING$/i) {
                     $encoding = $escapedtype;
                  }

                  if ($version <= 2.1) {
                     $escapedtype = 'BASE64' if ($escapedtype =~ m/^B$/i);

                     # Quoted-printable is preferred for most propertynames
                     # if any encoding at all is defined
                     if ($propertyname !~ m/^(?:PHOTO|LOGO|SOUND|KEY)$/i && $escapedtype eq 'BASE64') {
                        $encoding = $escapedtype = 'QUOTED-PRINTABLE';
                     }
                     $typeoutput .= ${$entry}{'TYPES'}{$type} . "=" . $escapedtype . ";";
                  } elsif ($version == 3.0) {
                     # Adhere to RFC 2426 section 5: Differences from vCard 2.1
                     if ($escapedtype =~ m/QUOTED-PRINTABLE/i || $escapedtype =~ m/BASE64/i) {
                        # version 3.0 does not support or allow quoted-printable.
                        # encode all quoted-printables as base64.
                        $encoding = $escapedtype = 'B';
                     } elsif (${$entry}{'TYPES'}{$type} eq 'CHARSET') {
                        # version 3.0 does not support or allow charset
                        next;
                     }

                     # group like types
                     $fliptypes{${$entry}{'TYPES'}{$type}} .= "$escapedtype,";
                  }
               }
               if ($version <= 2.1) {
                  if (((length($valueoutput) > 76) || $valueoutput =~ m/\n/) && $encoding eq undef && $propertyname ne "AGENT") {
                     $typeoutput .= "ENCODING=QUOTED-PRINTABLE;";
                     $encoding = "QUOTED-PRINTABLE";
                  }
               } elsif ($version == 3.0) {
                  foreach my $type (sort keys %fliptypes) {
                     $fliptypes{$type} =~ s/,$//; # no trailing comma
                     $typeoutput .= $type . "=" . $fliptypes{$type} . ";";
                  }
               }
               croak("Illegal characters in $xowmuid property $propertyname types\n") if $typeoutput =~ m/[\n\r]/;
               $typeoutput =~ s/(.*);$/;$1/; # no trailing, only leading semi-colon
            } else {
               # no types were defined - do we need to add some?
               if ($version <= 2.1) {
                  # Microsoft Outlook doesn't know how to unwrap lines and completely ignores the line wrapping
                  # specifications described in the RFCs (shock and surprise). So, make long lines quoted-
                  # printable for outlook compatibility. :(
                  if (($valueoutput =~ m/\n/ || length($valueoutput) > 76) && $encoding eq undef && $propertyname ne "AGENT") {
                     $typeoutput = ";ENCODING=QUOTED-PRINTABLE";
                     $encoding = "QUOTED-PRINTABLE";
                  }
               }
            }

            print "Typeoutput: $typeoutput\n" if $vcarddebugoutput;

            # Prepare the group output string
            if (defined ${$entry}{'GROUP'}) {
               vcard_escape_chars2(${$entry}{'GROUP'});
               $groupoutput = ${$entry}{'GROUP'} . ".";
               croak("Illegal characters in $xowmuid property $propertyname group\n") if $groupoutput =~ m/[\n\r]/;
            }

            print "Groupoutput: $groupoutput\n" if $vcarddebugoutput;
            print "Detected encoding: $encoding\n" if $vcarddebugoutput;

            # Encode the value output string (or binary info) if needed
            if ($encoding =~ m/^B$/i || $encoding =~ m/BASE64/i) {
               # unescape and encode the value
               $valueoutput =~ s/\\n/\n/g if ($version == 3.0);
               vcard_unescape_chars($valueoutput);
               $valueoutput = encode_base64($valueoutput,"");
               # BASE64's should start on new line and end with a blank line in vCard 2.1
               # BASE64 output needs to be folded here for vCard 2.1 or else it won't get
               # folded because it contains no whitespace
               if ($version <= 2.1) {
                  $valueoutput = "\r\n $valueoutput\r\n";
                  $valueoutput =~ s/(.{75})/$1\r\n /g;
               }
            } elsif ($encoding =~ m/QUOTED-PRINTABLE/i) {
               # The spec doesn't say to do this, but it conforms the output much better
               # $valueoutput =~ s/\t/    /g; # commented out for now

               # unescape and encode the value
               vcard_unescape_chars($valueoutput);
               $valueoutput =~ s/\r\n/\n/g; # per vCard 2.1 section 2.1.3 - to get =0D=0A
               $valueoutput =~ s/\r/\n/g; # per vCard 2.1 section 2.1.3 - to get =0D=0A
               $valueoutput =~ s/\n/\r\n/g; # per vCard 2.1 section 2.1.3 - to get =0D=0A
               $valueoutput = encode_qp($valueoutput,"");
            }

            print "Valueoutput: $valueoutput\n\n" if $vcarddebugoutput;

            # Assemble our final output for this property name entry
            my $finaloutput = $groupoutput . $propertyname . $typeoutput . ":" . $valueoutput ."\n";

            # In recursive scenarios we need to trim the ending to avoid multiple CRs
            $finaloutput =~ s/(\r|\\n|\n)+$/\n/;

            # standardize line endings
            $finaloutput =~ s/\s+$/\r\n/g;

            # Fold the output per RFC specs
            if (length($finaloutput) > 76) {
               if ($encoding =~ m/QUOTED-PRINTABLE/i) {
                  $finaloutput =~ s/(.{70,74}[^=])([^=\s])/$1=\r\n$2/g;
               } else {
                  if ($version <= 2.1) {
                     # any line longer than 76 characters will already be quoted-printable
                     # (thanks Microsoft), so don't worry about folding.
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

      unshift(@vcard,("BEGIN:VCARD\r\n","VERSION:$version\r\n")); # append to head
      push(@vcard,"END:VCARD\r\n\r\n"); # append to tail

      $output .= join('',@vcard);
   }

   # This routine is recursive, so don't mess with the output!!!
   return $output;
}

sub outputvcard_N {
   my ($r_entry, $version) = @_;
   my $n_familyname = ${$r_entry}{'VALUE'}{'FAMILYNAME'};
   my $n_givenname = ${$r_entry}{'VALUE'}{'GIVENNAME'};
   my $n_additionalnames = ${$r_entry}{'VALUE'}{'ADDITIONALNAMES'};
   my $n_nameprefix = ${$r_entry}{'VALUE'}{'NAMEPREFIX'};
   my $n_namesuffix = ${$r_entry}{'VALUE'}{'NAMESUFFIX'};
   if ($n_familyname.$n_givenname.$n_additionalnames.$n_nameprefix.$n_namesuffix eq '') {
      croak("At least one Name attribute must be defined.\n");
   }
   vcard_escape_chars($n_familyname,$n_givenname,$n_additionalnames,$n_nameprefix,$n_namesuffix);
   ${$r_entry}{'VALUE'} = join(";",$n_familyname,$n_givenname,$n_additionalnames,$n_nameprefix,$n_namesuffix);
   return($r_entry);
}

sub outputvcard_BDAY {
   # We have decided to only support ISO-8601 in two formats:
   # YYYY-MM-DD and YYYYMMDD
   # If anyone wants to implement complete ISO-8601 support for
   # other formats specified as acceptable in RFC 2426 section 3.1.5
   # for the BDAY property, please be my guest.
   my ($r_entry, $version) = @_;
   my $defined = 0;
   my $bdayyear = $r_entry->{VALUE}{YEAR};
   if ($bdayyear ne '') {
      $defined++;
      if ($bdayyear =~ m/^\d{4}$/) {
         if ($bdayyear < 0 || $bdayyear > 9999) {
            croak("The birthday year must a number between 0 and 9999\n");
         }
      } else {
         croak("The birthday year value must be a 4 digit number.\n");
      }
   }
   my $bdaymonth = $r_entry->{VALUE}{MONTH};
   if ($bdaymonth ne '') {
      $defined++;
      if ($bdaymonth =~ m/^\d{1,2}$/) {
         if ($bdaymonth < 1 || $bdaymonth > 12) {
            croak("The birthday month must be a number between 1 and 12\n");
         }
      } else {
         croak("The birthday month value must be a number between 1 and 12\n");
      }
   }
   my $bdayday = $r_entry->{VALUE}{DAY};
   if ($bdayday ne '') {
      $defined++;
      if ($bdayday =~ m/^\d{1,2}$/) {
         if ($bdayday < 1 || $bdayday > 31) {
            croak("The birthday day must be a number between 1 and 31\n");
         } else {
            my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
            $days_in_month[2]++ if ( ($bdayyear%4)==0 && (($bdayyear%100)!=0||($bdayyear%400)==0) );
            if ($bdayday > $days_in_month[$bdaymonth]) {
               croak("There are only $days_in_month[$bdaymonth] days in month $bdaymonth.\n");
            }
         }
      } else {
         croak("The birthday day value must be a number between 1 and 31\n");
      }
   }
   if ($defined > 0 && $defined < 3) {
      croak("Day, month, and year must all be defined for the birthday. You cannot only define some of them.\n");
   } elsif ($defined == 3) {
      $r_entry->{VALUE} = join("-",$bdayyear,sprintf("%02d",$bdaymonth),sprintf("%02d",$bdayday));
   } elsif ($defined == 0) {
      $r_entry->{VALUE} = ''; # don't store anything
   }
   return($r_entry);
}

sub outputvcard_ADR {
   my ($r_entry, $version) = @_;
   my $country = ${$r_entry}{VALUE}{COUNTRY};
   my $extendedaddress = ${$r_entry}{VALUE}{EXTENDEDADDRESS};
   my $locality = ${$r_entry}{VALUE}{LOCALITY};
   my $region = ${$r_entry}{VALUE}{REGION};
   my $street = ${$r_entry}{VALUE}{STREET};
   my $postalcode = ${$r_entry}{VALUE}{POSTALCODE};
   my $postofficeaddress = ${$r_entry}{VALUE}{POSTOFFICEADDRESS};
   vcard_escape_chars($country,$extendedaddress,$locality,$region,$street,$postalcode,$postofficeaddress);
   if ($country.$extendedaddress.$locality.$region.$street.$postalcode.$postofficeaddress eq '') {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(";",$postofficeaddress,$extendedaddress,$street,$locality,$region,$postalcode,$country);
   }
   return($r_entry);
}

sub outputvcard_TZ {
   # format like: -05:00
   my ($r_entry, $version) = @_;
   if ($r_entry->{VALUE} =~ m/^([+-])?(\d{2}):?(\d{2})$/) {
      if ($2 < 0 || $2 > 13) {
         croak("Timezone hour must be a valid number from 0 to 13.\n");
      } elsif ($3 != 0) {
         if ($3 != 30) {
            croak("Timezone minute must be either 00 or 30.\n");
         }
      }
      $r_entry->{VALUE} = (($1 eq '-')?'-':'').$2.':'.$3;
   } else {
      if ($r_entry->{VALUE} ne '') {
         croak("Timezone can only contain numeric characters, +, and -.\n");
      } else {
         $r_entry->{VALUE} = '';
      }
   }
   return($r_entry);
}

sub outputvcard_GEO {
   # Values should be in decimal degrees to six decimal places per RFC.
   my ($r_entry, $version) = @_;
   my $geo_longitude = $r_entry->{VALUE}{LONGITUDE};
   my $geo_latitude = $r_entry->{VALUE}{LATITUDE};
   $geo_longitude =~ s/\s+//g;
   $geo_latitude =~ s/\s+//g;
   if ($geo_longitude =~ m/^([+-])?(\d+)\.?(\d+)?$/) {
      $geo_longitude = "$2".($3?".$3":".0");
      $geo_longitude = ($1?$1:'').sprintf("%.6f",$geo_longitude);
   } else {
      if ($geo_longitude ne '') {
         croak("Longitude must be numeric characters, +, and - only.");
      }
   }
   if ($geo_latitude =~ m/^([+-])?(\d+)\.?(\d+)?$/) {
      $geo_latitude = "$2".($3?".$3":".0");
      $geo_latitude = ($1?$1:'').sprintf("%.6f",$geo_latitude);
   } else {
      if ($geo_latitude ne '') {
         croak("Latitude must be numeric characters, +, and - only.");
      }
   }
   if (($geo_latitude ne '' && $geo_longitude eq '') ||
       ($geo_longitude ne '' && $geo_latitude eq '')) {
      croak("Latitude and longitude must both be defined. You cannot only define one of the two.\n");
   }
   if ($geo_longitude eq '' && $geo_latitude eq '') {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(";",($geo_latitude,$geo_longitude));
   }
   return($r_entry);
}

sub outputvcard_AGENT {
   my ($r_entry, $version) = @_;
   if (${$r_entry}{'TYPES'}{'VCARD'}) {
      ${$r_entry}{'VALUE'} = outputvcard(${$r_entry}{'VALUE'},$version);
      # The BEGIN should start on its own line
      ${$r_entry}{'VALUE'} =~ s/^/\r\n/;
      # The result will be folded, which we don't want yet because the
      # final folding happens after this. We don't want double folding
      # so unfold it here.
      if ($version <= 2.1) {
         ${$r_entry}{'VALUE'} =~ s/\r\n([ \t])/$1/sg;
      } elsif ($version == 3.0) {
         ${$r_entry}{'VALUE'} =~ s/\r\n[ \t]//sg;
         # CRs should be literal string'\n'
         ${$r_entry}{'VALUE'} =~ s/\r\n/\n/g;
         ${$r_entry}{'VALUE'} =~ s/\n/\\n/g;
      }
   }
   return($r_entry);
}

sub outputvcard_ORG {
   my ($r_entry, $version) = @_;
   my $org_organizationname = $r_entry->{VALUE}{ORGANIZATIONNAME};
   my @org_organizationalunits = $r_entry->{VALUE}{ORGANIZATIONALUNITS} ? @{$r_entry->{VALUE}{ORGANIZATIONALUNITS}} : undef;
   vcard_escape_chars($org_organizationname);
   vcard_escape_chars(@org_organizationalunits);
   if ($org_organizationname eq '' && ($#org_organizationalunits < 0 || ($#org_organizationalunits == 0 && $org_organizationalunits[0] eq ''))) {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(";",$org_organizationname,@org_organizationalunits);
   }
   return($r_entry);
}

sub outputvcard_CATEGORIES {
   my ($r_entry, $version) = @_;
   my @categories = $r_entry->{VALUE}{CATEGORIES} ? @{$r_entry->{VALUE}{CATEGORIES}} : undef;
   vcard_escape_chars(@categories);
   $r_entry->{VALUE} = join(",",@categories);
   return($r_entry);
}

sub outputvcard_REV {
   my ($r_entry, $version) = @_;
   my $rev_sec = ${$r_entry}{VALUE}{SECOND};
   my $rev_min = ${$r_entry}{VALUE}{MINUTE};
   my $rev_hour = ${$r_entry}{VALUE}{HOUR};
   my $rev_mday = ${$r_entry}{VALUE}{DAY};
   my $rev_mon = ${$r_entry}{VALUE}{MONTH};
   my $rev_year = ${$r_entry}{VALUE}{YEAR};
   vcard_escape_chars($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year);
   ${$r_entry}{'VALUE'} = $rev_year."-".sprintf("%02d",$rev_mon)."-".sprintf("%02d",$rev_mday)."T".
                          sprintf("%02d",$rev_hour).":".sprintf("%02d",$rev_min).":".sprintf("%02d",$rev_sec)."Z";
   return($r_entry);
}

sub outputvcard_X_OWM_CUSTOM {
   my ($r_entry, $version) = @_;
   my $customname = $r_entry->{VALUE}{CUSTOMNAME};
   my @customvalues = $r_entry->{VALUE}{CUSTOMVALUES} ? @{$r_entry->{VALUE}{CUSTOMVALUES}} : undef;
   vcard_escape_chars($customname);
   vcard_escape_chars(@customvalues);
   if ($customname eq '' && ($#customvalues < 0 || ($#customvalues == 0 && $customvalues[0] eq ''))) {
      $r_entry->{VALUE} = '';
   } else {
      $r_entry->{VALUE} = join(";",$customname,@customvalues);
   }
   return($r_entry);
}

sub vcard_escape_chars {
   for (@_) {
      s#;#\\;#g;
      s#,#\\,#g;
   }
}

sub vcard_unescape_chars {
   for (@_) {
      s#\\;#;#g;
      s#\\,#,#g;
   }
}

sub vcard_escape_chars2 {
   for (@_) {
      s#;#\\;#g;
      s#:#\\:#g;
      s#,#\\,#g;
   }
}

sub vcard_unescape_chars2 {
   for (@_) {
      s#\\;#;#g;
      s#\\:#:#g;
      s#\\,#,#g;
   }
}

sub vcard_protect_chars {
   for (@_) {
      s/\\;/\@\@\@/g;
      s/\\:/\#\@\#/g;
      s/\\,/\^\@\^/g;
   }
}

sub vcard_unprotect_chars {
   for (@_) {
      s/\@\@\@/;/g;
      s/\#\@\#/:/g;
      s/\^\@\^/,/g;
   }
}

1;
