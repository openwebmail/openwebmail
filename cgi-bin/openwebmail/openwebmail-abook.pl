#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009-2014, The OpenWebMail Project
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


# Additional information about the addressbook implementation is available at:
# http://openwebmail.acatysmoof.com/doc/tech/addressbook

# Developers should familiarize themselves with the vcard hash
# data structure format described above before coding in this module

use strict;
use warnings FATAL => 'all';

use vars qw($SCRIPT_DIR);

if (-f '/etc/openwebmail_path.conf') {
   my $pathconf = '/etc/openwebmail_path.conf';
   open(F, $pathconf) or die "Cannot open $pathconf: $!";
   my $pathinfo = <F>;
   close(F) or die "Cannot close $pathconf: $!";
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die 'SCRIPT_DIR cannot be set' if $SCRIPT_DIR eq '';
push (@INC, $SCRIPT_DIR);
push (@INC, "$SCRIPT_DIR/lib");

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH} = '/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use CGI 3.31 qw(-private_tempfiles :cgi charset);
use CGI::Carp qw(fatalsToBrowser carpout);

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mailparse.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/adrbook.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/lockget.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs $icons);

# extern vars
use vars qw($htmltemplatefilters $po);                                                                            # defined in ow-shared.pl
use vars qw($_CHARSET);                                                                                           # defined in maildb.pl
use vars qw(%charset_convlist);                                                                                   # defined in iconv.pl

# local globals
use vars qw($folder $messageid $sort $msgdatetype $page $longpage $searchtype $keyword);
use vars qw($abookfolder $abookpage $abooklongpage $abooksort $abooksearchtype $abookkeyword $abookcollapse);
use vars qw($quotausage $quotalimit);
use vars qw($supportedformats);

my $supportedformats = {
                          'csv'      => { extension => 'csv' },
                          'tab'      => { extension => 'tab' },
                          'vcard2.1' => { extension => 'vcf' },
                          'vcard3.0' => { extension => 'vcf' },
                       };


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the addressbook module is not enabled.')) if !$config{enable_addressbook};

# convert old proprietary addressbooks to the new vcard format
convert_addressbook('user', $prefs{charset});

# webmail globals
$folder          = param('folder') || 'INBOX';
$page            = param('page') || 1;
$longpage        = param('longpage') || 0;
$sort            = param('sort') || $prefs{sort} || 'date_rev';
$searchtype      = param('searchtype') || '';
$keyword         = param('keyword') || '';
$msgdatetype     = param('msgdatetype') || $prefs{msgdatetype};
$messageid       = param('message_id') || '';

# webaddr globals
$abookfolder     = param('abookfolder') || cookie("ow-abookfolder-$domain-$user") || 'ALL';
$abookpage       = param('abookpage') || 1;
$abooklongpage   = param('abooklongpage') || 0;
$abooksort       = param('abooksort') || $prefs{abook_sort} || 'fullname';
$abooksearchtype = param('abooksearchtype') || ($prefs{abook_defaultfilter} ? $prefs{abook_defaultsearchtype} : '');
$abookkeyword    = param('abookkeyword') || ($prefs{abook_defaultfilter} ? $prefs{abook_defaultkeyword} : '');
$abookcollapse   = defined param('abookcollapse') ? param('abookcollapse') : $prefs{abook_collapse};

if (param('clearsearchbutton')) {
  $abookkeyword  = '';
  $abooklongpage = 0;
  $abookpage     = 1;
}

# does the requested book exist (mabye it was just deleted)
$abookfolder = 'ALL' if $abookfolder ne 'ALL' && !-e abookfolder2file($abookfolder);

# refresh ldapcache addressbook
refresh_ldapcache();

my $action = param('action') || '';
writelog("debug_request :: request abook begin, action=$action - " . __FILE__ . ':' . __LINE__) if $config{debug_request};

$action eq "addrlistview"          ? addrlistview()          :
$action eq "addrcardview"          ? addrcardview()          :
$action eq "addrselectpopup"       ? addrselectpopup()       :
$action eq "addreditform"          ? addreditform()          :
$action eq "addrviewatt"           ? addrviewatt()           :
$action eq "addredit"              ? addredit()              :
$action eq "addrexport"            ? addrexport()            :
$action eq "addrimport"            ? addrimport()            :
$action eq "addrimportform"        ? addrimportform()        :
$action eq "addrimportfieldselect" ? addrimportfieldselect() :
$action eq "addrimportattachment"  ? addrimportattachment()  :
$action eq "addrbookedit"          ? addrbookedit()          :
$action eq "addrbookdownload"      ? addrbookdownload()      :
$action eq "addrautosuggest"       ? addrautosuggest()       :
openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request abook end, action=$action - " . __FILE__ . ':' . __LINE__) if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub refresh_ldapcache {
   # update a local "ldapcache" addressbook with changes in a remote ldap directory
   my $ldapcachefile = abookfolder2file('ldapcache');

   return 0 unless $config{enable_ldap_abook};
   return 0 unless ow::tool::has_module('Net/LDAP.pm');

   if (-f $ldapcachefile) {
      my $nowtime  = time();
      my $filetime = (stat($ldapcachefile))[9];
      return 0 if ($nowtime - $filetime < $config{ldap_abook_cachelifetime} * 60); # file is up to date

      # mark file with current time, so no other process will try to update this file
      my ($origruid, $origeuid, $origegid) = ow::suid::set_uid_to_root();
      utime($nowtime, $nowtime, $ldapcachefile);
      ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   }

   local $| = 1; # flush all output

   if (fork() == 0) {
      # child
      writelog("debug_fork :: refresh_ldapcache_abookfile process forked - " . __FILE__ . ':' . __LINE__) if $config{debug_fork};

      close(STDIN);  # close fd0
      close(STDOUT); # close fd1
      close(STDERR); # close fd2

      # perl automatically chooses the lowest available file
      # descriptor, so open some fake ones to occupy 0,1,2 to
      # avoid warnings
      sysopen(FDZERO, '/dev/null', O_RDONLY); # occupy fd0
      sysopen(FDONE, '/dev/null', O_WRONLY);  # occupy fd1
      sysopen(FDTWO, '/dev/null', O_WRONLY);  # occupy fd2

      local $SIG{__WARN__} = sub { writelog(@_); exit(1) };
      local $SIG{__DIE__}  = sub { writelog(@_); exit(1) };

      my @ldaplist = (); # keep the order in global addressbook

      my $ldap = Net::LDAP->new($config{ldap_abook_host}) or openwebmail_exit(1);

      my $mesg = $ldap->bind(
                              $config{ldap_abook_user}, # DN
                              password => $config{ldap_abook_password},
                            );

      if ($config{ldap_abook_container} ne '') {
         $mesg = $ldap->search(
                                base   => "$config{ldap_abook_container},$config{ldap_abook_base}",
                                filter => "($config{ldap_abook_prefix}=*)",
                                scope  => 'one',
                              );
      } else {
         $mesg = $ldap->search(
                                base   => $config{ldap_abook_base},
                                filter => "($config{ldap_abook_prefix}=*)",
                                scope  => 'one',
                              );
      }

      foreach my $ou ($mesg->sorted()) {
         my $ouname = $ou->get_value($config{ldap_abook_prefix});

         my $mesg2 = '';

         if ($config{ldap_abook_container} ne '') {
            $mesg2 = $ldap->search(
                                    base   => "$config{ldap_abook_prefix}=" .
                                              $ou->get_value($config{ldap_abook_prefix}) .
                                              ",$config{ldap_abook_container},$config{ldap_abook_base}",
                                    filter => '(cn=*)',
                                  );
         } else {
            $mesg2 = $ldap->search(
                                    base   => "$config{ldap_abook_prefix}=" .
                                              $ou->get_value($config{ldap_abook_prefix}) .
                                              ",$config{ldap_abook_base}",
                                    filter => '(cn=*)',
                                  );
         }

         foreach my $entry ($mesg2->sorted()) {
            my $name  = $entry->get_value('cn');
            my $email = $entry->get_value('mail');
            my $note  = $entry->get_value('note');
            next if $email =~ m/^\s*$/; # skip null
            push(@ldaplist, [ $name, $email, $note ]);
         }
      }

      undef $ldap; # release LDAP connection

      my @entries = ();

      # convert entries to vcards for local storage
      foreach my $r_a (@ldaplist) {
         my ($name, $email, $note) = @{$r_a}[0,1,2];

         # X-OWM-ID
         # generate deterministic xowmuid for entries on LDAP
         # since ldapcache may be refreshed between user accesses
         my $k = $name . $email;
         $k = ow::tool::calc_checksum(\$k); # md5 result
         $k =~ s/(.)/sprintf('%02x',ord($1))/eg;
         $k = uc($k.$k);
         my $xowmuid = substr($k, 0,8) . '-' . substr($k,8,6) . '-' . substr($k,14,12) . '-' . substr($k,26,4);

         # REV
         my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
         my $rev = ($uid_year+1900) . ($uid_mon+1) . $uid_mday . 'T' . $uid_hour . $uid_min . $uid_sec . 'Z';

         # Name MUST be defined
         $name = gettext('Name') if $name eq '' || $name =~ m/^\s+$/;

         # Start output
         my ($first, $mid, $last, $nick) = _parse_username($name);

         foreach ($first, $mid, $last, $nick) {
            $_ .= ' ' if $_ =~ m/\\$/;
         }

         push(@entries, qq|BEGIN:VCARD\r\n| .
                        qq|VERSION:3.0\r\n| .
                        qq|N:$last;$first;$mid;;\r\n|
             );

         push(@entries, qq|NICKNAME:$nick\r\n|) if $nick ne '';

         # get all the emails
         my @emails = split(/,/, $email);
         foreach my $e (sort @emails) {
            $e =~ s/\\$//; # chop off trailing slash that escaped comma char
            push(@entries, qq|EMAIL:$e\r\n|) if defined $e;
         }

         # how we handle distribution lists
         push(@entries, qq|X-OWM-GROUP:$name\r\n|) if scalar @emails > 1;

         push(@entries, qq|NOTE:$note\r\n|) if $note ne '';

         push(@entries, qq|REV:$rev\r\n| .
                        qq|X-OWM-UID:$xowmuid\r\n| .
                        qq|END:VCARD\r\n\r\n|
             );
      }

      # write out the new converted addressbook
      my ($origruid, $origeuid, $origegid) = ow::suid::set_uid_to_root();
      if (ow::filelock::lock($ldapcachefile, LOCK_EX|LOCK_NB)) {
         if (sysopen(ADRBOOK, $ldapcachefile, O_WRONLY|O_TRUNC|O_CREAT)) {
            print ADRBOOK @entries;
            close(ADRBOOK);
         }
         ow::filelock::lock($ldapcachefile, LOCK_UN);
      }
      chmod(0444, $ldapcachefile); # set it to readonly
      ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

      close(FDZERO);
      close(FDONE);
      close(FDTWO);

      openwebmail_exit(0);
   }

   return 1;
}

sub addrlistview {
   # list all addresses in the selected abookfolder
   # or ALL abookfolders if no abookfolder is defined
   # allow user to make selections from the list

   # 4 modes available for displaying selectable checkboxes
   # default  : display selectable email addresses for to, cc, bcc, and xowmuids for select
   # compose  : display selectable email addresses for to, cc, bcc. No select box
   # group    : display selectable email addresses for to. No cc, bcc, or select boxes
   # export   : display selectable xowmuids for select. No to, cc, or bcc boxes
   my $mode = param('mode') || 'default';

   # get the list of checked tos, ccs, bccs, and xowmuids
   # these fields appear more than once in the form
   # the cgi param function automatically returns them all to us as an array
   my @tos      = param('clearall') ? () : param('to');
   my @ccs      = param('clearall') ? () : param('cc');
   my @bccs     = param('clearall') ? () : param('bcc');
   my @xowmuids = param('clearall') ? () : param('xowmuid');

   # separate into individual addresses and eliminate duplicates
   my (%unique_to, %unique_cc, %unique_bcc, %unique_xowmuid) = ((),(),(),());
   @tos      = sort { lc $a cmp lc $b } grep { defined && m/\S/ && !$unique_to{$_}{count}++ } map { ow::tool::str2list($_) } @tos;
   @ccs      = sort { lc $a cmp lc $b } grep { defined && m/\S/ && !$unique_cc{$_}{count}++ } map { ow::tool::str2list($_) } @ccs;
   @bccs     = sort { lc $a cmp lc $b } grep { defined && m/\S/ && !$unique_bcc{$_}{count}++ } map { ow::tool::str2list($_) } @bccs;
   @xowmuids = sort grep { !$unique_xowmuid{$_}++ } @xowmuids;

   # process move, copy, deletes
   if (param('moveselected') || param('copyselected') || param('deleteselected')) {
      addrmovecopydelete(@xowmuids);
      @xowmuids = ();
   }

   # process quickadds
   addredit() if param('quickadd');

   # load up the list of...
   my @readableabookfolders = get_readable_abookfolders();
   my @writableabookfolders = get_writable_abookfolders();

   # set the possible destination folders
   my @destinationfolders = grep { $_ ne $abookfolder } @writableabookfolders;
   my $is_abookfolder_writable = $abookfolder eq 'ALL' || scalar grep { $_ eq $abookfolder } @writableabookfolders;
   push(@destinationfolders, 'DELETE') if $is_abookfolder_writable;

   # figure out which addressbook folder to open
   my @viewabookfolders = grep { $abookfolder eq $_ } @readableabookfolders;

   # if viewabookfolders is empty its because user has the magic 'ALL' book selected
   # or they selected a book they do not have read perms on, in which case default to
   # the magic 'ALL'
   @viewabookfolders = @readableabookfolders if scalar @viewabookfolders < 1;

   # figure out the order of what the user wants to see displayed
   my @fieldorder = grep { !m/^none$/i } split(/\s*[,\s]\s*/, $prefs{abook_listviewfieldorder});
   $fieldorder[0] = 'fullname' unless scalar @fieldorder > 0;

   if ($mode =~ m/^(?:compose|group)$/) {
      # only show name and email type headers in these modes
      @fieldorder = grep { m/^(fullname|nicknames|prefix|first|middle|last|suffix|email)$/ } @fieldorder;

      # force an email header if there was not one before
      push(@fieldorder, 'email') unless scalar grep { m/^email$/ } @fieldorder;
   }

   # build a search?
   # create a vcard data structure from the search terms. we can then compare this
   # vcard data structure to each parsed vcard to determine a match
   my %fieldmap = (
                     'fullname'   => 'FN',
                     'nicknames'  => 'NICKNAME',
                     'prefix'     => 'NAMEPREFIX',
                     'first'      => 'GIVENNAME',
                     'middle'     => 'ADDITIONALNAMES',
                     'last'       => 'FAMILYNAME',
                     'suffix'     => 'NAMESUFFIX',
                     'email'      => 'EMAIL',
                     'phone'      => 'TEL',
                     'note'       => 'NOTE',
                     'categories' => 'CATEGORIES',
                  );

   # list all of the contacts that match the search criteria
   # or 'ALL' contacts if there is no active search
   my $searchterms = {};
   if ($abooksearchtype ne '' && defined $abookkeyword && $abookkeyword ne '' && $abookkeyword !~ m/^\s+$/) {
      if ($abooksearchtype =~ m/^(?:prefix|first|middle|last|suffix)$/) {
         $searchterms->{N}[0]{VALUE}{$fieldmap{$abooksearchtype}} = $abookkeyword;
      } elsif ($abooksearchtype eq 'categories') {
         $searchterms->{CATEGORIES}[0]{VALUE}{CATEGORIES}[0] = $abookkeyword;
      } else {
         $searchterms->{$fieldmap{$abooksearchtype}}[0]{VALUE} = $abookkeyword;
      }

      $searchterms->{'X-OWM-CHARSET'}[0]{VALUE} = $prefs{charset};
   }

   # do not return full vcard data structures
   # only return the fields we need, to keep memory down
   my $only_return = {                       # Always return these ones because:
                       'CATEGORIES'    => 1, # Categories is always a searchable parameter
                       'SORT-STRING'   => 1, # We need to be able to do sort overrides
                       'X-OWM-CHARSET' => 1, # The charset of data in this vcard
                       'X-OWM-GROUP'   => 1, # There is special handling for group entries
                     };

   $only_return->{$_} = 1 for map { m/^(?:prefix|first|middle|last|suffix)$/ ? 'N' : $fieldmap{$_} } @fieldorder;

   # load the contacts: read each abook and save the matches to our contacts list
   my $contacts = {};

   foreach my $abookfoldername (@viewabookfolders) {
      my $abookfile = abookfolder2file($abookfoldername);

      # filter based on searchterms and prune based on only_return
      my $thisbook = readadrbook($abookfile, (scalar keys %{$searchterms} ? $searchterms : undef), $only_return);

      foreach my $xowmuid (keys %{$thisbook}) {
         $contacts->{$xowmuid} = $thisbook->{$xowmuid};                    # add it to our contacts
         $contacts->{$xowmuid}{'X-OWM-BOOK'}[0]{VALUE} = $abookfoldername; # remember the source book
      }
   }

   # first, internally sort the contacts so that PREF fields appear first
   # and then fields are sorted case-insensitively by VALUE
   $contacts = internal_sort($contacts);

   # then, sort the xowmuids by the selected abooksort order
   my ($abooksort_short) = $abooksort =~ m/^([a-z]+)/; # exclude '_rev'

   # if the sort is by a field we are not displaying, change the sort to the first field of our display
   $abooksort = $abooksort_short = $fieldorder[0] unless scalar grep { $abooksort_short eq $_ } @fieldorder;

   my $sort_reverse = $abooksort =~ m/_rev$/;

   my @sorted_xowmuids = $abooksort_short =~ m/^(?:fullname|nicknames|email|phone|note)$/
                         ? sort {
                                  exists $contacts->{$b}{$fieldmap{$abooksort_short}}
                                  <=> # force contacts that do not have our sort field to the end of the array
                                  exists $contacts->{$a}{$fieldmap{$abooksort_short}}

                                  ||

                                  ( # sort by the chosen sort field
                                   exists $contacts->{($sort_reverse ? $b : $a)}{$fieldmap{$abooksort_short}}
                                   ? lc $contacts->{($sort_reverse ? $b : $a)}{$fieldmap{$abooksort_short}}[0]{VALUE}
                                   : ''
                                  )
                                  cmp
                                  (
                                   exists $contacts->{($sort_reverse ? $a : $b)}{$fieldmap{$abooksort_short}}
                                   ? lc $contacts->{($sort_reverse ? $a : $b)}{$fieldmap{$abooksort_short}}[0]{VALUE}
                                   : ''
                                  )

                                  ||

                                  ( # then sort by last name
                                   exists $contacts->{($sort_reverse ? $b : $a)}{N} && exists $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{last}}
                                   ? lc $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{last}}
                                   : ''
                                  )
                                  cmp
                                  (
                                   exists $contacts->{($sort_reverse ? $a : $b)}{N} && exists $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{last}}
                                   ? lc $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{last}}
                                   : ''
                                  )

                                  ||

                                  ( # then sort by first name
                                   exists $contacts->{($sort_reverse ? $b : $a)}{N} && exists $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{first}}
                                   ? lc $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{first}}
                                   : ''
                                  )
                                  cmp
                                  (
                                   exists $contacts->{($sort_reverse ? $a : $b)}{N} && exists $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{first}}
                                   ? lc $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{first}}
                                   : ''
                                  )

                                  ||

                                  ( # then sort by full name
                                   exists $contacts->{($sort_reverse ? $b : $a)}{$fieldmap{fullname}}
                                   ? lc $contacts->{($sort_reverse ? $b : $a)}{$fieldmap{fullname}}[0]{VALUE}
                                   : ''
                                  )
                                  cmp
                                  (
                                   exists $contacts->{($sort_reverse ? $a : $b)}{$fieldmap{fullname}}
                                   ? lc $contacts->{($sort_reverse ? $a : $b)}{$fieldmap{fullname}}[0]{VALUE}
                                   : ''
                                  )
                                } keys %{$contacts}
                         : sort {
                                  (exists $contacts->{$b}{N} && exists $contacts->{$b}{N}[0]{VALUE}{$fieldmap{$abooksort_short}})
                                  <=> # force contacts that do not have our sort field to the end of the array
                                  (exists $contacts->{$a}{N} && exists $contacts->{$a}{N}[0]{VALUE}{$fieldmap{$abooksort_short}})

                                  ||

                                  ( # sort by the chosen sort field
                                    exists $contacts->{$a}{N} && exists $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{$abooksort_short}}
                                    ? $abooksort_short eq 'last' && exists $contacts->{($sort_reverse ? $b : $a)}{'SORT-STRING'}
                                      ? lc $contacts->{($sort_reverse ? $b : $a)}{'SORT-STRING'}[0]{VALUE}
                                      : lc $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{$abooksort_short}}
                                    : ''
                                  )
                                  cmp
                                  (
                                    exists $contacts->{$a}{N} && exists $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{$abooksort_short}}
                                    ? $abooksort_short eq 'last' && exists $contacts->{($sort_reverse ? $a : $b)}{'SORT-STRING'}
                                      ? lc $contacts->{($sort_reverse ? $a : $b)}{'SORT-STRING'}[0]{VALUE}
                                      : lc $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{$abooksort_short}}
                                    : ''
                                  )

                                  ||

                                  ( # then sort by last name
                                   exists $contacts->{($sort_reverse ? $b : $a)}{N} && exists $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{last}}
                                   ? lc $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{last}}
                                   : ''
                                  )
                                  cmp
                                  (
                                   exists $contacts->{($sort_reverse ? $a : $b)}{N} && exists $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{last}}
                                   ? lc $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{last}}
                                   : ''
                                  )

                                  ||

                                  ( # then sort by first name
                                   exists $contacts->{($sort_reverse ? $b : $a)}{N} && exists $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{first}}
                                   ? lc $contacts->{($sort_reverse ? $b : $a)}{N}[0]{VALUE}{$fieldmap{first}}
                                   : ''
                                  )
                                  cmp
                                  (
                                   exists $contacts->{($sort_reverse ? $a : $b)}{N} && exists $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{first}}
                                   ? lc $contacts->{($sort_reverse ? $a : $b)}{N}[0]{VALUE}{$fieldmap{first}}
                                   : ''
                                  )

                                  ||

                                  ( # then sort by full name
                                   exists $contacts->{($sort_reverse ? $b : $a)}{$fieldmap{fullname}}
                                   ? lc $contacts->{($sort_reverse ? $b : $a)}{$fieldmap{fullname}}[0]{VALUE}
                                   : ''
                                  )
                                  cmp
                                  (
                                   exists $contacts->{($sort_reverse ? $a : $b)}{$fieldmap{fullname}}
                                   ? lc $contacts->{($sort_reverse ? $a : $b)}{$fieldmap{fullname}}[0]{VALUE}
                                   : ''
                                  )
                                } keys %{$contacts};

   # build the showcheckedloop of checked contacts to show to the user
   my $showchecked = [];
   if (param('showchecked')) {
      $showchecked = [
                        {
                                  to => 1,
                           addresses => [ map { { row => $_ + 1, address => $tos[$_] } } (0..$#tos) ],
                        },
                        {
                                  cc => 1,
                           addresses => [ map { { row => $_ + 1, address => $ccs[$_] } } (0..$#ccs) ],
                        },
                        {
                                 bcc => 1,
                           addresses => [ map { { row => $_ + 1, address => $bccs[$_] } } (0..$#bccs) ],
                        },
                        {
                             xowmuid => 1,
                        }
                     ];

      if ($mode ne 'group' && $mode ne 'compose') {
         # calculate the xowmuid addresses as human readable values
         my $row = 1;
         foreach my $xowmuid (@sorted_xowmuids) {
            if (exists $unique_xowmuid{$xowmuid}) {
               my $name = exists $contacts->{$xowmuid}{FN}
                          ? $contacts->{$xowmuid}{FN}[0]{VALUE}
                          : join (' ',  map { $contacts->{$xowmuid}{N}[0]{VALUE}{$_} }
                                       grep {
                                              exists $contacts->{$xowmuid}{N}[0]{VALUE}{$_}
                                              && defined $contacts->{$xowmuid}{N}[0]{VALUE}{$_}
                                            } qw(NAMEPREFIX GIVENNAME ADDITIONALNAMES FAMILYNAME NAMESUFFIX)
                                 );

               $name =~ s/"/\\"/g;

               my $address = exists $contacts->{$xowmuid}{EMAIL}
                             ? exists $contacts->{$xowmuid}{'X-OWM-GROUP'}
                               ? $contacts->{$xowmuid}{EMAIL}[0]{VALUE}
                               : ($name ? qq|$name <$contacts->{$xowmuid}{EMAIL}[0]{VALUE}>| : $contacts->{$xowmuid}{EMAIL}[0]{VALUE})
                             : $name;

               push(@{$showchecked->[3]{addresses}}, { row => $row++, address => $address, });
            }
         }
      }

      splice(@{$showchecked}, 0, 3) if $mode eq 'export';  # remove to, cc, bcc in export mode
      splice(@{$showchecked}, 1, 3) if $mode eq 'group';   # remove cc, bcc, xowmuid in group mode
      splice(@{$showchecked}, 3, 1) if $mode eq 'compose'; # remove xowmuid in compose mode
   }

   # calculate how many pages we have and which contacts are on this page
   my $addrperpage = $prefs{abook_addrperpage} || 10;
   my $showaddrperpage = $abooklongpage ? $addrperpage : 1000;
   $addrperpage = 5 if $mode eq 'export';
   $addrperpage = 1000 if $abooklongpage;

   my $totaladdrs = scalar keys %{$contacts};
   my $totalpages = int($totaladdrs / $addrperpage + 0.999999);
   $totalpages    = 1 if $totalpages == 0;

   $abookpage     = 1 if $abookpage < 1;
   $abookpage     = $totalpages if $abookpage > $totalpages;

   my $firstaddr = (($abookpage - 1) * $addrperpage) + 1;
   my $lastaddr  = $firstaddr + $addrperpage - 1;
   $lastaddr     = $totaladdrs if $lastaddr > $totaladdrs;

   # purge vcards we will not be displaying to reduce memory used
   for(my $i = 0; $i < scalar @sorted_xowmuids; $i++) {
      delete $contacts->{$sorted_xowmuids[$i]} if $i < $firstaddr-1 || $i >= $lastaddr;
   }

   # process each contact that will be displayed
   foreach my $i (($firstaddr-1)..($lastaddr-1)) {
      my $xowmuid = $sorted_xowmuids[$i];

      my $maxrowspan = (
                          sort { $b <=> $a }
                          map { exists $contacts->{$xowmuid}{$_} ? scalar @{$contacts->{$xowmuid}{$_}} : 0 }
                          map { m/^(?:prefix|first|middle|last|suffix)$/ ? 'N' : $fieldmap{$_} } @fieldorder
                       )[0];

      my $CHARSET = exists $contacts->{$xowmuid}{'X-OWM-CHARSET'}
                    ? $contacts->{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}
                    : $prefs{charset};

      # put contact data in cols/rows based on fieldorder
      for(my $col = 0; $col < scalar @fieldorder; $col++) {
         my $field    = $fieldorder[$col];
         my $fieldmap = $fieldorder[$col] =~ m/^(?:prefix|first|middle|last|suffix)$/ ? 'N' : $fieldmap{$fieldorder[$col]};

         for(my $row = 0; $row < $maxrowspan; $row++) {
            my $is_collapsed = param('resetcollapse')
                               ? $abookcollapse
                               : defined param("collapse_$xowmuid") ? param("collapse_$xowmuid") : $abookcollapse;

            if ($row == 0) {
               $contacts->{$xowmuid}{rows}[$row]{show_collapse} = $maxrowspan > 1 ? 1 : 0;
               $contacts->{$xowmuid}{rows}[$row]{collapse}      = $is_collapsed;
               $contacts->{$xowmuid}{rows}[$row]{url_html}      = $config{ow_htmlurl};
               $contacts->{$xowmuid}{rows}[$row]{use_texticon}  = $prefs{iconset} =~ m/^Text$/ ? 1 : 0;
               $contacts->{$xowmuid}{rows}[$row]{iconset}       = $prefs{iconset};
               $contacts->{$xowmuid}{rows}[$row]{$_}            = $icons->{$_} for keys %{$icons};
            }

            last if $is_collapsed == 1 && $row > 0;

            if (exists $contacts->{$xowmuid}{$fieldmap} && defined $contacts->{$xowmuid}{$fieldmap}[$row]) {
               my $FIELD = $contacts->{$xowmuid}{$fieldmap}[$row];

               # use a specific transformation subroutine if one is defined for this
               # field propertyname, or else just use a generic subroutine
               if (!exists $FIELD->{transformed}) {
                  no strict 'refs';
                  my $sub = "HT_$fieldmap";
                  $sub =~ s/-/_/g; # X-OWM-CUSTOM ==> X_OWM_CUSTOM
                  ($FIELD, $CHARSET) = defined *$sub{CODE} ? $sub->($FIELD, $CHARSET) : HT_GENERIC->($FIELD, $CHARSET);
                  $FIELD->{transformed} = 1;
               }

               if ($fieldmap eq 'FN' || $fieldmap eq 'N') {
                  $FIELD->{is_group} = exists $contacts->{$xowmuid}{'X-OWM-GROUP'};
               }

               if ($fieldmap eq 'NOTE') {
                  ($FIELD->{shortnote}) = $FIELD->{VALUE} =~ m/^(.{15,30})\s/;
                  $FIELD->{shortnote}   = $FIELD->{VALUE} unless defined $FIELD->{shortnote};
                  $FIELD->{shortnote}   = substr($FIELD->{VALUE}, 0, 15) if length $FIELD->{shortnote} > 30 && length $FIELD->{VALUE} > 15;
                  $FIELD->{shortnote}  .= ' ...' if $FIELD->{shortnote} ne $FIELD->{VALUE};

                  # calculate where the popup should be
                  $FIELD->{noteoffset} = $col + 1 > (scalar @fieldorder / 2) + .5 ? -350 : 150;

                  # escape for html and linkify text
                  $FIELD->{VALUE} = ow::htmltext::text2html($FIELD->{VALUE});

                  # escape " and <> from the linkify, for js popup
                  # HT escapes for js, but cannot simultaneously escape html
                  $FIELD->{VALUE} =~ s/"/&quot;/g;
                  $FIELD->{VALUE} =~ s/</&lt;/g;
                  $FIELD->{VALUE} =~ s/>/&gt;/g;
               }

               if ($fieldmap eq 'EMAIL') {
                  # update the field information
                  $FIELD->{name} = exists $contacts->{$xowmuid}{FN}
                                   ? $contacts->{$xowmuid}{FN}[0]{VALUE}
                                   : join (' ',  map { $contacts->{$xowmuid}{N}[0]{VALUE}{$_} }
                                                grep {
                                                        exists $contacts->{$xowmuid}{N}[0]{VALUE}{$_}
                                                        && defined $contacts->{$xowmuid}{N}[0]{VALUE}{$_}
                                                     } qw(NAMEPREFIX GIVENNAME ADDITIONALNAMES FAMILYNAME NAMESUFFIX)
                                          );

                  $FIELD->{email} = exists $contacts->{$xowmuid}{'X-OWM-GROUP'}
                                    ? $FIELD->{VALUE}
                                    : ($FIELD->{name} ? qq|"$FIELD->{name}" <$FIELD->{VALUE}>| : $FIELD->{VALUE});

                  $FIELD->{cannot_link} = length $FIELD->{email} > 1500 ? 1 : 0;
                  $FIELD->{group_count} = exists $FIELD->{is_group} ? scalar @{$contacts->{$xowmuid}{EMAIL}} - 1 : 0;
                  $FIELD->{row}         = $row;

                  # update the row information
                  $contacts->{$xowmuid}{rows}[$row]{email}    = $FIELD->{email};
                  $contacts->{$xowmuid}{rows}[$row]{is_group} = exists $FIELD->{is_group} ? 1 : 0;

                  # check this row?
                  my @members = ow::tool::str2list($contacts->{$xowmuid}{rows}[$row]{email});

                  if ((scalar grep { exists $unique_to{$_} && !exists $unique_to{$_}->{checked} } @members) == scalar @members) {
                     $contacts->{$xowmuid}{rows}[$row]{to_checked} = 1;
                     $unique_to{$_}->{checked}++ for @members;
                  }

                  if ((scalar grep { exists $unique_cc{$_} && !exists $unique_cc{$_}->{checked} } @members) == scalar @members) {
                     $contacts->{$xowmuid}{rows}[$row]{cc_checked} = 1;
                     $unique_cc{$_}->{checked}++ for @members;
                  }

                  if ((scalar grep { exists $unique_bcc{$_} && !exists $unique_bcc{$_}->{checked} } @members) == scalar @members) {
                     $contacts->{$xowmuid}{rows}[$row]{bcc_checked} = 1;
                     $unique_bcc{$_}->{checked}++ for @members;
                  }

                  # force check all group members if the all_members (row 0) box is checked
                  if (exists $FIELD->{is_group} && $row > 0) {
                     $contacts->{$xowmuid}{rows}[$row]{to_checked}  = 1
                       if exists $contacts->{$xowmuid}{rows}[0]{to_checked} && $contacts->{$xowmuid}{rows}[0]{to_checked} == 1;

                     $contacts->{$xowmuid}{rows}[$row]{cc_checked}  = 1
                       if exists $contacts->{$xowmuid}{rows}[0]{cc_checked} && $contacts->{$xowmuid}{rows}[0]{cc_checked} == 1;

                     $contacts->{$xowmuid}{rows}[$row]{bcc_checked} = 1
                       if exists $contacts->{$xowmuid}{rows}[0]{bcc_checked} && $contacts->{$xowmuid}{rows}[0]{bcc_checked} == 1;
                  }
               }

               # standard params
               $FIELD->{sessionid}       = $thissession;
               $FIELD->{folder}          = $folder;
               $FIELD->{sort}            = $sort;
               $FIELD->{msgdatetype}     = $msgdatetype;
               $FIELD->{page}            = $page;
               $FIELD->{longpage}        = $longpage;
               $FIELD->{searchtype}      = $searchtype;
               $FIELD->{keyword}         = $keyword;
               $FIELD->{url_cgi}         = $config{ow_cgiurl};
               $FIELD->{url_html}        = $config{ow_htmlurl};
               $FIELD->{use_texticon}    = $prefs{iconset} =~ m/^Text$/ ? 1 : 0;
               $FIELD->{use_fixedfont}   = $prefs{usefixedfont};
               $FIELD->{iconset}         = $prefs{iconset};
               $FIELD->{$_}              = $icons->{$_} for keys %{$icons};
               $FIELD->{charset}         = $prefs{charset};

               # addressbook params
               $FIELD->{abookfolder}     = $abookfolder;
               $FIELD->{abookpage}       = $abookpage;
               $FIELD->{abooklongpage}   = $abooklongpage;
               $FIELD->{abooksort}       = $abooksort;
               $FIELD->{abooksearchtype} = $abooksearchtype;
               $FIELD->{abookkeyword}    = $abookkeyword;
               $FIELD->{abookcollapse}   = $abookcollapse;

               $FIELD->{odd}             = $i % 2 == 0 ? 0 : 1;
               $FIELD->{xowmuid}         = $xowmuid;
               $FIELD->{xowmbook}        = $contacts->{$xowmuid}{'X-OWM-BOOK'}[0]{VALUE};
               $FIELD->{use_lightbar}    = $prefs{uselightbar};

               push(@{$contacts->{$xowmuid}{rows}[$row]{cols}[$col]{$field}}, $FIELD);
            } else {
               $contacts->{$xowmuid}{rows}[$row]{cols}[$col] = {
                                                                         empty => 1,
                                                                  use_lightbar => $prefs{uselightbar},
                                                                           odd => $i % 2 == 0 ? 0 : 1,
                                                               };
            }

            $contacts->{$xowmuid}{rows}[$row]{row}            = $row;
            $contacts->{$xowmuid}{rows}[$row]{odd}            = $i % 2 == 0 ? 0 : 1;
            $contacts->{$xowmuid}{rows}[$row]{first_row}      = $row == 0 ? 1 : 0;
            $contacts->{$xowmuid}{rows}[$row]{xowmuid}        = $xowmuid;
            $contacts->{$xowmuid}{rows}[$row]{use_lightbar}   = $prefs{uselightbar};
            $contacts->{$xowmuid}{rows}[$row]{contact_number} = $i + 1;

            if ($col + 1 == scalar @fieldorder) {
               $contacts->{$xowmuid}{rows}[$row]{xowmuid_checked} = scalar grep { $_ eq $xowmuid } @xowmuids;
               @xowmuids = grep { $_ ne $xowmuid } @xowmuids if $contacts->{$xowmuid}{rows}[$row]{xowmuid_checked} > 0;
            }

            $contacts->{$xowmuid}{rows}[$row]{row_checked} = exists $contacts->{$xowmuid}{rows}[$row]{to_checked}
                                                             && $contacts->{$xowmuid}{rows}[$row]{to_checked}
                                                             || exists $contacts->{$xowmuid}{rows}[$row]{cc_checked}
                                                             && $contacts->{$xowmuid}{rows}[$row]{cc_checked}
                                                             || exists $contacts->{$xowmuid}{rows}[$row]{bcc_checked}
                                                             && $contacts->{$xowmuid}{rows}[$row]{bcc_checked}
                                                             || exists $contacts->{$xowmuid}{rows}[$row]{xowmuid_checked}
                                                             && $contacts->{$xowmuid}{rows}[$row]{xowmuid_checked};
         }
      }
   }

   my $exportformat   = param('exportformat') || 'vcard3.0';
   my $exportcharset  = param('exportcharset') || $prefs{charset} || 'none';
   my %exportcharsets = map { $ow::lang::charactersets{$_}[1] => 1 } keys %ow::lang::charactersets;

   my $templatefile = $mode eq 'compose' ? 'abook_listviewcompose.tmpl' :
                      $mode eq 'group'   ? 'abook_listviewgroup.tmpl'   :
                      $mode eq 'export'  ? 'abook_listviewexport.tmpl'  :
                      'abook_listview.tmpl';

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template($templatefile),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      sessionid                  => $thissession,
                      folder                     => $folder,
                      sort                       => $sort,
                      msgdatetype                => $msgdatetype,
                      page                       => $page,
                      longpage                   => $longpage,
                      searchtype                 => $searchtype,
                      keyword                    => $keyword,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont              => $prefs{usefixedfont},
                      use_lightbar               => $prefs{uselightbar},
                      charset                    => $prefs{charset},
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder                => $abookfolder,
                      abookpage                  => $abookpage,
                      abooklongpage              => $abooklongpage,
                      abooksort                  => $abooksort,
                      abooksearchtype            => $abooksearchtype,
                      abookkeyword               => $abookkeyword,
                      abookcollapse              => $abookcollapse,

                      # abook_listview[group|export|compose].tmpl
                      enable_webmail             => $config{enable_webmail},
                      messageid                  => $messageid,
                      enable_calendar            => $config{enable_calendar},
                      calendar_defaultview       => $prefs{calendar_defaultview},
                      enable_addressbook         => $config{enable_addressbook},
                      enable_webdisk             => $config{enable_webdisk},
                      enable_sshterm             => $config{enable_sshterm},
                      use_ssh2                   => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar" ? 1 : 0,
                      use_ssh1                   => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar" ? 1 : 0,
                      enable_preference          => $config{enable_preference},
                      quotaoverlimit             => ($quotalimit > 0 && $quotausage > $quotalimit) ? 1 : 0,
                      availablefreespace         => $config{abook_maxsizeallbooks} - userabookfolders_totalsize(),
                      abookfolderselectloop      => [
                                                      map { {
                                                              is_defaultabookfolder => is_defaultabookfolder($_),
                                                              "option_$_"           => 1,
                                                              option                => $_,
                                                              label                 => f2u($_),
                                                              selected              => $abookfolder eq $_ ? 1 : 0,
                                                              is_global             => is_abookfolder_global($_),
                                                              is_writable           => is_abookfolder_writable($_),
                                                          } } ('ALL', @readableabookfolders)
                                                    ],
                      is_abookfolderdefault      => is_defaultabookfolder($abookfolder),
                      "abookfolder_$abookfolder" => 1,
                      abookfolder_label          => f2u($abookfolder),
                      writableabookfolders       => scalar @writableabookfolders,
                      confirmmsgmovecopy         => $prefs{confirmmsgmovecopy},
                      is_right_to_left           => exists $ow::lang::RTL{$prefs{locale}} && $ow::lang::RTL{$prefs{locale}} ? 1 : 0,
                      totalpages                 => $totalpages,
                      nextpage                   => $abookpage < $totalpages ? ($abookpage + 1) : 0,
                      prevpage                   => ($abookpage - 1) || 0,
                      enable_move                => (scalar @destinationfolders > 0 && $is_abookfolder_writable) ? 1 : 0,
                      enable_copy                => scalar @destinationfolders > 0 ? 1 : 0,
                      enable_delete              => $is_abookfolder_writable ? 1 : 0,
                      destinationselectloop      => [
                                                       map { {
                                                                is_defaultabookfolder => is_defaultabookfolder($_),
                                                                "option_$_"           => 1,
                                                                option                => $_,
                                                                label                 => f2u($_),
                                                                selected              => $_ eq $destinationfolders[0] ? 1 : 0,
                                                                is_global             => is_abookfolder_global($_),
                                                           } } @destinationfolders
                                                    ],
                      searchtypeselectloop       => [
                                                       map { {
                                                                "option_$_" => $_,
                                                                selected    => defined $abooksearchtype ? $_ eq $abooksearchtype : $_ eq $fieldorder[0],
                                                           } } (@fieldorder, 'categories')
                                                    ],
                      pageselectloop             => [
                                                       map { {
                                                                option   => $_,
                                                                label    => $_,
                                                                selected => $_ eq $abookpage ? 1 : 0,
                                                           } } grep {
                                                                       $_ == 1
                                                                       || $_ == $totalpages
                                                                       || abs($_ - $abookpage) < 10
                                                                       || abs($_ - $abookpage) < 100 && $_ % 10 == 0
                                                                       || abs($_ - $abookpage) < 1000 && $_ % 100 == 0
                                                                       || $_ % 1000 == 0
                                                                    } (1..$totalpages)
                                                    ],
                      tosloop                    => [ map { { to      => $_ } } grep { !exists $unique_to{$_}{checked} } @tos ],
                      ccsloop                    => [ map { { cc      => $_ } } grep { !exists $unique_cc{$_}{checked} } @ccs ],
                      bccsloop                   => [ map { { bcc     => $_ } } grep { !exists $unique_bcc{$_}{checked} } @bccs ],
                      xowmuidsloop               => [ map { { xowmuid => $_ } } @xowmuids ],
                      abook_addrperpage          => $addrperpage,
                      abook_addrperpagestring    => sprintf(ngettext('%d address per page','%d addresses per page',$showaddrperpage), $showaddrperpage),
                      enable_quickadd            => is_abookfolder_writable($abookfolder) && $action ne 'addrimportattachment',
                      showbuttons_before         => $prefs{abook_buttonposition} ne 'after' ? 1 : 0, # before or both
                      fieldorderloop             => [
                                                       map { {
                                                                $_              => 1,
                                                                is_sort_key     => $abooksort_short eq $_ ? 1 : 0,
                                                                is_sort_reverse => $sort_reverse,
                                                                url_html        => $config{ow_htmlurl},
                                                                use_texticon    => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                                                iconset         => $prefs{iconset},
                                                                (map { $_, $icons->{$_} } keys %{$icons}),
                                                           } } @fieldorder
                                                    ],
                      contactsloop               => [
                                                       map {
                                                              $contacts->{$sorted_xowmuids[$_]}
                                                           } (($firstaddr-1)..($lastaddr-1))
                                                    ],
                      showbuttons_after          => $prefs{abook_buttonposition} ne 'before' ? 1 : 0, # after or both
                      showchecked                => param('showchecked') ? 1 : 0,
                      showcheckedloop            => $showchecked,
                      fontsize                   => $prefs{fontsize},
                      languagedirection          => $ow::lang::RTL{$prefs{locale}} ? 'rtl' : 'ltr',
                      clear_all                  => param('clearall') ? 1 : 0,
                      compose                    => param('compose') ? 1 : 0,
                      mode                       => $mode,
                      selectdone                 => param('selectdone') ? 1 : 0,
                      group_selects              => join("\n",(scalar @tos > 0 ? @tos : ())),
                      composeto_selects          => join(', ',(scalar @tos > 0 ? @tos : ())),
                      composecc_selects          => join(', ',(scalar @ccs > 0 ? @ccs : ())),
                      composebcc_selects         => join(', ',(scalar @bccs > 0 ? @bccs : ())),
                      exportformat               => $exportformat,
                      exportformatsloop          => [
                                                       map { {
                                                                "option_$_" => 1,
                                                                selected    => $exportformat eq $_ ? 1 : 0,
                                                           } } sort keys %{$supportedformats}
                                                    ],
                      exportcharset              => $exportcharset,
                      exportcharsetdisabled      => $exportformat =~ m/vcard/i ? 1 : 0,
                      exportcharsetloop          => [
                                                       map { {
                                                                option   => $_,
                                                                label    => $_,
                                                                selected => $exportcharset eq $_ ? 1 : 0,
                                                           } } sort keys %exportcharsets
                                                    ],
                      exportxowmuidsloop         => [ map { { xowmuid => $_ } } keys %unique_xowmuid ],

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   my $abookfolder_cookie = cookie(
                                    -name  => "ow-abookfolder-$domain-$user",
                                    -value => $abookfolder,
                                    -path  => '/'
                                  );

   httpprint(($mode eq '' ? [-cookie=>[$abookfolder_cookie]] : []), [$template->output]);
}

sub addrselectpopup {
   # open a template to grab field values from the opener window
   # in order to display addresses as already selected
   # then auto-submit the form in the template to go to the listview
   my $mode = param('mode') || ''; # group or compose

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('abook_selectgrabber.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # standard params
                      sessionid       => $thissession,
                      folder          => $folder,
                      sort            => $sort,
                      msgdatetype     => $msgdatetype,
                      page            => $page,
                      longpage        => $longpage,
                      searchtype      => $searchtype,
                      keyword         => $keyword,
                      url_cgi         => $config{ow_cgiurl},
                      url_html        => $config{ow_htmlurl},
                      use_texticon    => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont   => $prefs{usefixedfont},
                      use_lightbar    => $prefs{uselightbar},
                      charset         => $prefs{charset},
                      iconset         => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder     => $abookfolder,
                      abookpage       => $abookpage,
                      abooklongpage   => $abooklongpage,
                      abooksort       => $abooksort,
                      abooksearchtype => $abooksearchtype,
                      abookkeyword    => $abookkeyword,
                      abookcollapse   => $abookcollapse,

                      # abook_selectpopup.tmpl
                      mode            => $mode,
                   );

   httpprint([], [$template->output]);
}

sub addrmovecopydelete {
   # given a list of xowmuid's, move, copy, or delete them and save
   # out the sourcebooks or targetbooks that have been modified
   my @xowmuids = @_;

   return 0 unless scalar @xowmuids;

   my $targetfolder = param('destinationabook');

   my $operation = $targetfolder eq 'DELETE'
                   ? param('moveselected') || param('deleteselected') ? 'delete' : return 0
                   : param('moveselected') ? 'move' : 'copy';

   # get the full path to all of the needed source books
   my %allabookfolders = ();
   if ($abookfolder eq 'ALL') {
      %allabookfolders =  map { $_ => abookfolder2file($_) }
                         grep { m/^[^.]/ && !/^categories\.cache$/ }
                         get_readable_abookfolders();
   } else {
      $allabookfolders{$abookfolder} = abookfolder2file($abookfolder);
      openwebmailerror(gettext('The addressbook does not exist:') . ' ' . f2u($abookfolder)) if !-f $allabookfolders{$abookfolder};
   }

   # calculate the available free space
   my $availfreespace = $config{abook_maxsizeallbooks} - userabookfolders_totalsize();

   # load the destination book
   my $targetfile = '';
   my $targetbook = '';
   if ($targetfolder ne 'DELETE') {
      $targetfile = abookfolder2file($targetfolder);

      openwebmailerror(gettext('The addressbook does not exist:') . ' ' . f2u($targetfolder)) if !-f $targetfile;
      openwebmailerror(gettext('The destination folder is read-only:') . ' ' . f2u($targetfolder)) if !-w $targetfile;

      $targetbook = readadrbook($targetfile, undef, undef);
   }

   my $changedtarget = 0;

   # load the addressbooks and perform the move/copy/delete
   foreach my $abookfolder (keys %allabookfolders) {
      my $sourcefile = ow::tool::untaint($allabookfolders{$abookfolder});
      my $sourcebook = readadrbook($sourcefile, undef, undef);
      my $changedsource = 0;
      foreach my $xowmuid (@xowmuids) {
         if (exists $sourcebook->{$xowmuid}) {
            if ($operation eq 'move') {
               next if $sourcefile eq $targetfile; # nothing to do

               if (!is_abookfolder_writable($abookfolder)) {
                  if (is_abookfolder_global($abookfolder)) {
                     openwebmailerror(gettext('You do not have permission to edit the global addressbook.'));
                  } else {
                     openwebmailerror(gettext('The addressbook folder is read-only:') . " $abookfolder");
                  }
               }

               $targetbook->{$xowmuid} = $sourcebook->{$xowmuid}; # copy ref

               delete $sourcebook->{$xowmuid};
               writelog("move contact - $xowmuid from $abookfolder to $targetfolder");
               writehistory("move contact - $xowmuid from $abookfolder to $targetfolder");
               $changedsource++;
               $changedtarget++;
            } elsif ($operation eq 'delete') {
               if (!is_abookfolder_writable($abookfolder)) {
                  if (is_abookfolder_global($abookfolder)) {
                     openwebmailerror(gettext('You do not have permission to edit the global addressbook.'));
                  } else {
                     openwebmailerror(gettext('The addressbook folder is read-only:') . " $abookfolder");
                  }
               }

               delete $sourcebook->{$xowmuid};
               writelog("delete contact - $xowmuid from $abookfolder");
               writehistory("delete contact - $xowmuid from $abookfolder");
               $changedsource++;
            } elsif ($operation eq 'copy') {
               # generate a new xowmuid for each one being copied
               my $newxowmuid = generate_xowmuid();

               if ($sourcefile eq $targetfile) {
                  $sourcebook->{$newxowmuid} = deepcopy($sourcebook->{$xowmuid}); # de-reference and copy
                  $sourcebook->{$newxowmuid}{'X-OWM-UID'}[0]{VALUE} = $newxowmuid;
                  $changedsource++;
               } else {
                  $targetbook->{$newxowmuid} = deepcopy($sourcebook->{$xowmuid}); # de-reference and copy
                  $targetbook->{$newxowmuid}{'X-OWM-UID'}[0]{VALUE} = $newxowmuid;
                  $changedtarget++;
               }
               writelog("copy contact - $xowmuid from $abookfolder to $targetfolder");
               writehistory("copy contact - $xowmuid from $abookfolder to $targetfolder");
            }
         }
      }

      # save out the source book IF it was changed
      if ($changedsource) {
         my $writeoutput = outputvfile('vcard',$sourcebook);

         ow::filelock::lock($sourcefile, LOCK_EX|LOCK_NB) or
            openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($sourcefile) . " ($!)");

         sysopen(TARGET, $sourcefile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($sourcefile) . " ($!)");

         print TARGET $writeoutput;

         close(TARGET) or
            openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($sourcefile) . " ($!)");

         ow::filelock::lock($sourcefile, LOCK_UN) or writelog("cannot lock file $sourcefile");
      }
   }

   if ($changedtarget && $targetfolder ne 'DELETE') {
      # save out the targetbook
      my $writeoutput = outputvfile('vcard',$targetbook);

      # check for space
      # during a move the size will be exactly the same overall
      # during a copy this may croak - but no information will be lost
      my $writesizekb = length($writeoutput) / 1024;
      if (($writesizekb > $availfreespace) || !is_quota_available($writesizekb)) {
         openwebmailerror(gettext('The addressbook size exceeds the available free space.'));
      }

      ow::filelock::lock($targetfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($targetfile));

      sysopen(TARGET, $targetfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($targetfile) . " ($!)");

      print TARGET $writeoutput;

      close(TARGET) or
         openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($targetfile) . " ($!)");

      ow::filelock::lock($targetfile, LOCK_UN) or writelog("cannot unlock file $targetfile");
   }

   return 1;
}

sub addrbookedit {
   # manage the list of addressbooks for this user
   my $function = param('function') || '';
   addrbookadd()    if $function eq 'add';
   addrbookdelete() if $function eq 'delete';
   addrbookrename() if $function eq 'rename';

   # load the stats for each readable addressbook
   my $stats = {};

   my @readable_abookfolders = grep { !is_abookfolder_global($_) } get_readable_abookfolders();
   my @global_abookfolders   = get_global_abookfolders();

   foreach my $abookfolder (@readable_abookfolders) {
      my $abookfile = abookfolder2file($abookfolder);
      my $thisbook  = readadrbook($abookfile, undef, {N => 1});
      $stats->{$abookfolder}{entries} = scalar keys %{$thisbook};
      $stats->{$abookfolder}{size}    = (-s $abookfile);
      $stats->{totalentries} += $stats->{$abookfolder}{entries};
      $stats->{totalsizes}   += $stats->{$abookfolder}{size};
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('abook_editbooks.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      sessionid                  => $thissession,
                      folder                     => $folder,
                      sort                       => $sort,
                      msgdatetype                => $msgdatetype,
                      page                       => $page,
                      longpage                   => $longpage,
                      searchtype                 => $searchtype,
                      keyword                    => $keyword,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont              => $prefs{usefixedfont},
                      use_lightbar               => $prefs{uselightbar},
                      charset                    => $prefs{charset},
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder                => $abookfolder,
                      abookpage                  => $abookpage,
                      abooklongpage              => $abooklongpage,
                      abooksort                  => $abooksort,
                      abooksearchtype            => $abooksearchtype,
                      abookkeyword               => $abookkeyword,
                      abookcollapse              => $abookcollapse,

                      # abook_editbooks.tmpl
                      enable_webmail             => $config{enable_webmail},
                      messageid                  => $messageid,
                      enable_calendar            => $config{enable_calendar},
                      calendar_defaultview       => $prefs{calendar_defaultview},
                      enable_addressbook         => $config{enable_addressbook},
                      enable_webdisk             => $config{enable_webdisk},
                      enable_sshterm             => $config{enable_sshterm},
                      use_ssh2                   => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar" ? 1 : 0,
                      use_ssh1                   => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar" ? 1 : 0,
                      enable_preference          => $config{enable_preference},
                      quotaoverlimit             => ($quotalimit > 0 && $quotausage > $quotalimit) ? 1 : 0,
                      availablefreespace         => $config{abook_maxsizeallbooks} - userabookfolders_totalsize(),
                      is_abookfolderdefault      => is_defaultabookfolder($abookfolder),
                      "abookfolder_$abookfolder" => 1,
                      abookfolder_label          => f2u($abookfolder),
                      foldername_maxlength       => $config{foldername_maxlen},
                      foldername_maxlengthstring => sprintf(ngettext('%d character', '%d characters', $config{foldername_maxlen}), $config{foldername_maxlen}),
                      addressbooksloop           => [
                                                       map { {
                                                                # standard params
                                                                sessionid             => $thissession,
                                                                folder                => $folder,
                                                                sort                  => $sort,
                                                                msgdatetype           => $msgdatetype,
                                                                page                  => $page,
                                                                longpage              => $longpage,
                                                                searchtype            => $searchtype,
                                                                keyword               => $keyword,
                                                                url_cgi               => $config{ow_cgiurl},
                                                                url_html              => $config{ow_htmlurl},
                                                                use_texticon          => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                                                use_fixedfont         => $prefs{usefixedfont},
                                                                iconset               => $prefs{iconset},
                                                                (map { $_, $icons->{$_} } keys %{$icons}),

                                                                # addressbook params
                                                                abookpage             => $abookpage,
                                                                abooklongpage         => $abooklongpage,
                                                                abooksort             => $abooksort,
                                                                abooksearchtype       => $abooksearchtype,
                                                                abookkeyword          => $abookkeyword,
                                                                abookcollapse         => $abookcollapse,
                                                                abookfolder           => $readable_abookfolders[$_],
                                                                is_abookfolderdefault => is_defaultabookfolder($readable_abookfolders[$_]),
                                                                "abookfolder_$readable_abookfolders[$_]" => 1,
                                                                abookfolder_label     => f2u($readable_abookfolders[$_]),
                                                                abookfolder_size      => lenstr($stats->{$readable_abookfolders[$_]}{size}, 0),
                                                                abookfolder_entries   => $stats->{$readable_abookfolders[$_]}{entries},
                                                                is_writable           => is_abookfolder_writable($readable_abookfolders[$_]),
                                                                count                 => $_,
                                                                odd                   => $_ % 2 == 0 ? 0 : 1,
                                                           } }
                                                       (0..$#readable_abookfolders)
                                                    ],
                      globaladdressbooksloop     => [
                                                       map { {
                                                                # standard params
                                                                sessionid             => $thissession,
                                                                folder                => $folder,
                                                                sort                  => $sort,
                                                                msgdatetype           => $msgdatetype,
                                                                page                  => $page,
                                                                longpage              => $longpage,
                                                                searchtype            => $searchtype,
                                                                keyword               => $keyword,
                                                                url_cgi               => $config{ow_cgiurl},
                                                                url_html              => $config{ow_htmlurl},
                                                                use_texticon          => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                                                use_fixedfont         => $prefs{usefixedfont},
                                                                iconset               => $prefs{iconset},
                                                                (map { $_, $icons->{$_} } keys %{$icons}),

                                                                # addressbook params
                                                                abookpage             => $abookpage,
                                                                abooklongpage         => $abooklongpage,
                                                                abooksort             => $abooksort,
                                                                abooksearchtype       => $abooksearchtype,
                                                                abookkeyword          => $abookkeyword,
                                                                abookcollapse         => $abookcollapse,
                                                                abookfolder           => $global_abookfolders[$_],
                                                                is_abookfolderdefault => is_defaultabookfolder($global_abookfolders[$_]),
                                                                "abookfolder_$global_abookfolders[$_]" => 1,
                                                                abookfolder_label     => f2u($global_abookfolders[$_]),
                                                                abookfolder_size      => lenstr($stats->{$global_abookfolders[$_]}{size}, 0),
                                                                abookfolder_entries   => $stats->{$global_abookfolders[$_]}{entries},
                                                                odd                   => $_ % 2 == 0 ? 0 : 1,
                                                           } }
                                                       (0..$#global_abookfolders)
                                                    ],
                      totalentries               => $stats->{totalentries},
                      totalsizes                 => lenstr($stats->{totalsizes}, 1),

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub addrbookadd {
   # add a new addressbook
   my $abookfoldernew = param('abookfoldernew') || '';
   $abookfoldernew =~ s#^[\s\\//]+##;
   $abookfoldernew =~ s/\s+$//;
   $abookfoldernew = u2f(ow::tool::untaint(safefoldername($abookfoldernew)));

   openwebmailerror(gettext('Illegal characters in folder name:') . ' ' . f2u($abookfoldernew))
     unless is_safefoldername($abookfoldernew);

   return if $abookfoldernew eq '';

   my $abookfilenew = abookfolder2file($abookfoldernew);

   openwebmailerror(gettext('The addressbook folder name already exists:') . ' ' .  f2u($abookfoldernew))
      if -e $abookfilenew || is_defaultabookfolder($abookfoldernew);

   openwebmailerror(sprintf(ngettext('The addressbook folder name exceeds the %d character limit:', 'The addressbook folder name exceeds the %d character limit:', $config{foldername_maxlen}), $config{foldername_maxlen}) . ' ' .  f2u($abookfoldernew))
      if length($abookfoldernew) > $config{foldername_maxlen};

   sysopen(NEWBOOK, $abookfilenew, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . " $abookfilenew ($!)");

   close(NEWBOOK) or writelog("cannot close file $abookfilenew");

   writelog("add addressbook - $abookfoldernew");
   writehistory("add addressbook - $abookfoldernew");

   return; # back to addrbookedit
}

sub addrbookdelete {
   # delete an existing addressbook
   my $targetbook = param('targetbook') || '';

   $abookfolder  = ow::tool::untaint(safefoldername($targetbook));
   return if $abookfolder eq '';

   my $abookfile = abookfolder2file($abookfolder);

   openwebmailerror(gettext('The addressbook does not exist:') . ' ' . f2u($abookfolder) . " ($!)")
      unless -e $abookfile;

   unlink($abookfile) or
      openwebmailerror(gettext('Cannot delete file:') . ' ' . f2u($abookfolder) . " ($!)");

   writelog("delete addressbook - $abookfolder");
   writehistory("delete addressbook - $abookfolder");

   return; # back to addrbookedit
}

sub addrbookrename {
   # rename an existing addressbook
   my $targetbook     = param('targetbook') || '';
   my $abookfoldernew = param('abookfoldernew') || '';

   $abookfoldernew =~ s#^[\s\\//]+##;
   $abookfoldernew =~ s/\s+$//;
   $abookfoldernew = u2f(ow::tool::untaint(safefoldername($abookfoldernew)));

   openwebmailerror(gettext('Illegal characters in folder name:') . ' ' . f2u($abookfoldernew))
     unless is_safefoldername($abookfoldernew);

   return if $abookfoldernew eq '';

   my $abookfilenew = abookfolder2file($abookfoldernew);

   $abookfolder  = ow::tool::untaint(safefoldername($targetbook));
   my $abookfile = abookfolder2file($abookfolder);

   openwebmailerror(gettext('The addressbook folder name already exists:') . ' ' . f2u($abookfoldernew))
      if -e $abookfilenew || is_defaultabookfolder($abookfoldernew);

   openwebmailerror(sprintf(ngettext('The addressbook folder name exceeds the %d character limit:', 'The addressbook folder name exceeds the %d character limit:', $config{foldername_maxlen}), $config{foldername_maxlen}) . ' ' .  f2u($abookfoldernew))
      if length($abookfoldernew) > $config{foldername_maxlen};

   rename($abookfile, $abookfilenew) or
      openwebmailerror(gettext('Cannot rename file:') . " $abookfile ($!)");

   writelog("rename addressbook - $abookfolder to $abookfoldernew");
   writehistory("rename addressbook - $abookfolder to $abookfoldernew");

   return; # back to addrbookedit
}

sub addrbookdownload {
   # send the entire addressbook file to the user
   $abookfolder  = ow::tool::untaint(safefoldername($abookfolder));
   my $abookfile = abookfolder2file($abookfolder);

   ow::filelock::lock($abookfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($abookfile));

   my $cmd         = '';
   my $contenttype = '';
   my $filename    = '';

   if (($cmd = ow::tool::findbin('zip')) ne '') {
      $contenttype = 'application/x-zip-compressed';
      $filename    = "$abookfolder.vcf.zip";
      open(T, "-|") or
         do {
              open(STDERR,">/dev/null");
              exec(ow::tool::untaint($cmd), "-qj", "-", $abookfile);
              exit 9
            };
   } elsif (($cmd = ow::tool::findbin('gzip')) ne '') {
      $contenttype = 'application/x-gzip-compressed';
      $filename    = "$abookfolder.vcf.gz";
      open(T, "-|") or
         do {
               open(STDERR,">/dev/null");
               exec(ow::tool::untaint($cmd), "-c", $abookfile);
               exit 9
            };
   } else {
      $contenttype = 'application/x-vcard';
      $filename    = "$abookfolder.vcf";
      sysopen(T, $abookfile, O_RDONLY);
   }

   $filename =~ s/\s+/_/g;

   # disposition:attachment default to save
   print qq|Connection: close\n| .
         qq|Content-Type: $contenttype; name="$filename"\n| .

         # ie5.5 is broken with content-disposition: attachment
         (
           $ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/
           ? qq|Content-Disposition: filename="$filename"\n|
           : qq|Content-Disposition: attachment; filename="$filename"\n|
         ) .

         "\n";

   my $buff = '';
   print $buff while read(T, $buff, 32768);

   close(T);

   ow::filelock::lock($abookfile, LOCK_UN);

   writelog("download addressbook - $abookfolder");
   writehistory("download addressbook - $abookfolder");

   return;
}

sub addrcardview {
   # given an xowmuid, output a summary of the contact, similar to a rolodex card
   my $rootxowmuid    = param('rootxowmuid') || '';
   my $xowmuid        = param('xowmuid') || $rootxowmuid;

   openwebmailerror(gettext('A valid xowmuid must be provided.')) unless defined $xowmuid && $xowmuid;

   my @readableabookfolders = get_readable_abookfolders();

   # find the first xowmuid match for contact information
   my $contact   = {};
   my $abookfile = '';
   foreach my $folder (@readableabookfolders) {
      $abookfolder  = $folder;
      $abookfile    = abookfolder2file($folder);
      my $thisbook  = readadrbook($abookfile, undef, undef);

      foreach my $thisbook_xowmuid (keys %{$thisbook}) {
         if ($thisbook_xowmuid eq $xowmuid) {
            $contact->{$xowmuid} = $thisbook->{$thisbook_xowmuid};
            last;
         }
      }

      last if scalar keys %{$contact};
   }

   # find out composecharset before processing each vcard propertyname so they iconv properly
   my $composecharset = $contact->{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE} || $prefs{charset};

   # TODO: the logic here could probably improve to handle more scenarios - this is the legacy logic
   # TODO: this logic also exists in -send.pl and should be refactored to -shared.pl
   if ($composecharset ne $prefs{charset}) {
      my $composelocale = $prefs{language} . "." . ow::lang::charset_for_locale($composecharset);
      if (exists $config{available_locales}->{$composelocale}) {
         # switch to this character set in the users preferred language if it exists
         $prefs{locale}  = $composelocale;
         $prefs{charset} = $composecharset;
      } else {
         # or else switch to en_US.UTF-8 and hope for the best
         $prefs{locale}  = 'en_US.UTF-8';
         $prefs{charset} = $composecharset;
      }
   }

   $po = loadlang($prefs{locale});
   charset($prefs{charset}) if $CGI::VERSION >= 2.58; # setup charset of CGI module

   #################################################
   # transform $contact for HTML::Template display #
   #################################################

   # all supported propertynames are listed here
   # unsupported propertynames will be displayed generically
   my %propertynames = (
                          BEGIN   => 1, END        => 1, REV      => 1, VERSION       => 1,
                          PROFILE => 1, CATEGORIES => 1, PHOTO    => 1, N             => 1,
                          FN      => 1, SOUND      => 1, NICKNAME => 1, 'SORT-STRING' => 1,
                          BDAY    => 1, EMAIL      => 1, TEL      => 1, ADR           => 1,
                          LABEL   => 1, LOGO       => 1, TITLE    => 1, ROLE          => 1,
                          ORG     => 1, URL        => 1, TZ       => 1, GEO           => 1,
                          MAILER  => 1, NOTE       => 1, KEY      => 1, AGENT         => 1,
                          CLASS   => 1, SOURCE     => 1, NAME     => 1, UID           => 1,
                          PRODID  => 1,

                          'X-OWM-UID'     => 1, 'X-OWM-BOOK'    => 1,
                          'X-OWM-GROUP'   => 1, 'X-OWM-CHARSET' => 1,
                          'X-OWM-CUSTOM'  => 1, 'X-OWM-BDAY'    => 1,
                       );

   # bundle information from one property into another property so they can be displayed together
   my %bundlemap = (LABEL => 'ADR', TITLE => 'ORG', ROLE => 'ORG');
   foreach my $from_property (keys %bundlemap) {
      if (exists $contact->{$xowmuid}{$from_property}) {
         my $to_property = $bundlemap{$from_property};

         $contact->{$xowmuid}{$to_property}[$_]{VALUE}{$from_property} = $contact->{$xowmuid}{$from_property}[$_]{VALUE}
           for(0..$#{$contact->{$xowmuid}{$from_property}});

         delete $contact->{$xowmuid}{$from_property};
      }
   }

   # internally sort the contacts so that PREF fields appear first
   # and the fields are sorted case-insensitively by VALUE
   $contact = internal_sort($contact);

   # transform each field to be HTML::Template friendly
   foreach my $propertyname (keys %{$contact->{$xowmuid}}) {
      my $CHARSET = exists $contact->{$xowmuid}{'X-OWM-CHARSET'}
                    ? $contact->{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}
                    : $prefs{charset};

      # set the selected email address to the same as the one being used to view this card
      if ($propertyname eq 'EMAIL') {
         my $selected_email = param('email') || '';
         my $name  = exists $contact->{$xowmuid}{FN}
                     ? $contact->{$xowmuid}{FN}[0]{VALUE}
                     : join (' ',  map { $contact->{$xowmuid}{N}[0]{VALUE}{$_} }
                                  grep {
                                         exists $contact->{$xowmuid}{N}[0]{VALUE}{$_}
                                         && defined $contact->{$xowmuid}{N}[0]{VALUE}{$_}
                                       } qw(NAMEPREFIX GIVENNAME ADDITIONALNAMES FAMILYNAME NAMESUFFIX)
                            );

         $name =~ s/"/\\"/g;

         foreach my $FIELD (@{$contact->{$xowmuid}{EMAIL}}) {
            $FIELD->{selected}    = 1 if $FIELD->{VALUE} eq $selected_email;
            $FIELD->{nameaddress} = $name ? qq|"$name" <$FIELD->{VALUE}>| : $FIELD->{VALUE};
         }
      }

      for(my $i = 0; $i < scalar @{$contact->{$xowmuid}{$propertyname}}; $i++) {
         my $FIELD = $contact->{$xowmuid}{$propertyname}[$i];

         $FIELD->{sessionid}       = $thissession;
         $FIELD->{url_cgi}         = $config{ow_cgiurl};
         $FIELD->{url_html}        = $config{ow_htmlurl};
         $FIELD->{use_texticon}    = $prefs{iconset} =~ m/^Text$/ ? 1 : 0;
         $FIELD->{iconset}         = $prefs{iconset};
         $FIELD->{$_}              = $icons->{$_} for keys %{$icons};

         $FIELD->{count}           = $i;
         $FIELD->{editformcaller}  = param('editformcaller') || '';
         $FIELD->{xowmuid}         = $xowmuid;
         $FIELD->{rootxowmuid}     = $rootxowmuid;
         $FIELD->{abookfolder}     = $abookfolder;
         $FIELD->{abookpage}       = $abookpage;
         $FIELD->{abooklongpage}   = $abooklongpage;
         $FIELD->{abooksort}       = $abooksort;
         $FIELD->{abooksearchtype} = $abooksearchtype;
         $FIELD->{abookkeyword}    = $abookkeyword;
         $FIELD->{abookcollapse}   = $abookcollapse;
         $FIELD->{folder}          = $folder;
         $FIELD->{sort}            = $sort;
         $FIELD->{msgdatetype}     = $msgdatetype;
         $FIELD->{page}            = $page;
         $FIELD->{longpage}        = $longpage;
         $FIELD->{searchtype}      = $searchtype;
         $FIELD->{keyword}         = $keyword;

         # HT_ signifies a sub to format a field for HTML::Template looping
         # call a defined subroutine for this field (like HT_ADR), or else just run it generic (HT_GENERIC)
         no strict 'refs';
         my $sub = "HT_$propertyname";
         $sub =~ s/-/_/g; # X-OWM-CUSTOM becomes X_OWM_CUSTOM
         ($FIELD, $CHARSET) = defined *$sub{CODE} ? $sub->($FIELD, $CHARSET) : HT_GENERIC->($FIELD, $CHARSET);

         $contact->{$xowmuid}{$propertyname}[$i] = $FIELD;

         if (!exists $propertynames{$propertyname}) {
            $FIELD->{propertyname} = $propertyname;
            if (exists $FIELD->{TYPES}) {
               $FIELD->{TYPES}[$_]{propertyname} = $propertyname for (0..$#{$FIELD->{TYPES}});
            }
            push(@{$contact->{$xowmuid}{UNSUPPORTED}}, $FIELD);
         }
      }
   }

   $contact->{$xowmuid}{sessionid}    = $thissession;
   $contact->{$xowmuid}{url_cgi}      = $config{ow_cgiurl};
   $contact->{$xowmuid}{url_html}     = $config{ow_htmlurl};
   $contact->{$xowmuid}{use_texticon} = $prefs{iconset} =~ m/^Text$/ ? 1 : 0;
   $contact->{$xowmuid}{iconset}      = $prefs{iconset};
   $contact->{$xowmuid}{$_}           = $icons->{$_} for keys %{$icons};

   #############################################
   # $contact is not modified after this point #
   #############################################

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('abook_cardview.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template         => get_header($config{header_template_file}),

                      # standard params
                      sessionid               => $thissession,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,
                      url_cgi                 => $config{ow_cgiurl},
                      url_html                => $config{ow_htmlurl},
                      use_texticon            => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont           => $prefs{usefixedfont},
                      use_lightbar            => $prefs{uselightbar},
                      iconset                 => $prefs{iconset},
                      charset                 => $prefs{charset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder             => $abookfolder,
                      abookpage               => $abookpage,
                      abooklongpage           => $abooklongpage,
                      abooksort               => $abooksort,
                      abooksearchtype         => $abooksearchtype,
                      abookkeyword            => $abookkeyword,
                      abookcollapse           => $abookcollapse,

                      # abook_cardview.tmpl
                      messageid               => $messageid,
                      quotaoverlimit          => ($quotalimit > 0 && $quotausage > $quotalimit) ? 1 : 0,

                      xowmuid                 => $xowmuid,
                      rootxowmuid             => $rootxowmuid,
                      contactloop             => [ $contact->{$xowmuid} ],
                   );

   httpprint([], [$template->output]);
}

sub addrautosuggest {
   # given a field of email addresses, look at the last typed
   # text and provide address options to complete it
   my $fieldname      = param('fieldname') || '';
   my $fieldvalue     = param('fieldvalue') || '';
   my $composecharset = param('composecharset') || $prefs{charset};

   my @addresses = ow::tool::str2list($fieldvalue);

   my $searchstring = pop(@addresses) || '';

   my $matches = {};

   if ($searchstring) {
      my @readableabookfolders = get_readable_abookfolders();

      # do not return full vcard data structures
      # only return the fields we need, to keep memory down
      my $only_return = {                       # Always return these ones because:
                          'SORT-STRING'   => 1, # We need to be able to do sort overrides
                          'X-OWM-CHARSET' => 1, # The charset of data in this vcard
                          'X-OWM-GROUP'   => 1, # There is special handling for group entries
                          'N'             => 1,
                          'FN'            => 1,
                          'EMAIL'         => 1,
                          'NICKNAME'      => 1,
                        };

      foreach my $abookfoldername (@readableabookfolders) {
         my $abookfile = abookfolder2file($abookfoldername);

         # filter based on searchterms and prune based on only_return
         my $thisbook = readadrbook($abookfile, undef, $only_return);

         foreach my $xowmuid (keys %{$thisbook}) {
            next if exists $thisbook->{$xowmuid}{'X-OWM-GROUP'};
            next unless exists $thisbook->{$xowmuid}{EMAIL};

            my $charset = $thisbook->{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE} || $prefs{charset};

            my $name = exists $thisbook->{$xowmuid}{FN}
                       ? $thisbook->{$xowmuid}{FN}[0]{VALUE}
                       : join (' ',  map { $thisbook->{$xowmuid}{N}[0]{VALUE}{$_} }
                                    grep {
                                           exists $thisbook->{$xowmuid}{N}[0]{VALUE}{$_}
                                           && defined $thisbook->{$xowmuid}{N}[0]{VALUE}{$_}
                                         } qw(NAMEPREFIX GIVENNAME ADDITIONALNAMES FAMILYNAME NAMESUFFIX)
                              );

            next unless defined $name && $name;

            my $name_escaped = $name;
            $name_escaped =~ s/"/\\"/g;

            foreach my $email (@{$thisbook->{$xowmuid}{EMAIL}}) {
               my $option         = qq|$name <$email->{VALUE}>|;
               my $option_escaped = qq|"$name_escaped" <$email->{VALUE}>|;

               if (
                     $option =~ m/\Q$searchstring\E/i
                     || (exists $thisbook->{$xowmuid}{NICKNAME} && scalar grep { $_->{VALUE} =~ m/\Q$searchstring\E/i } @{$thisbook->{$xowmuid}{NICKNAME}})
                  ) {
                  # escape " and <> from the option_escape
                  # HT escapes for js, but cannot simultaneously escape html
                  $option_escaped = join(', ', (@addresses, (iconv($charset, $composecharset, $option_escaped))[0]));
                  $option_escaped =~ s/"/&quot;/g;
                  $option_escaped =~ s/</&lt;/g;
                  $option_escaped =~ s/>/&gt;/g;
                  $option_escaped .= ', ' if $option_escaped;

                  $matches->{(iconv($charset, $composecharset, $option))[0]} = $option_escaped;
                  last if scalar keys %{$matches} == 10;
               }
            }

            last if scalar keys %{$matches} == 10;
         }

         last if scalar keys %{$matches} == 10;
      }
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('abook_autosuggest.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # abook_autosuggest.tmpl
                      matchesloop => [
                                        map { {
                                                 option_escaped => $matches->{$_},
                                                 option         => $_,
                                                 fieldname      => $fieldname,
                                            } } sort keys %{$matches},
                                     ],
                   );

   httpprint([], [$template->output]);
}

sub addreditform {
   # given a rootxowmuid, output the form to edit its fields
   my $rootxowmuid    = param('rootxowmuid') || '';
   my $xowmuid        = param('xowmuid') || $rootxowmuid;
   my $editformcaller = param('editformcaller') || '';
   my $formchange     = param('formchange') || '';
   my $upload         = param('upload') || '';
   my $webdisksel     = param('webdisksel') || '';

   # first time called?
   deleteattachments() if param('action') eq 'addreditform';

   my @writableabookfolders = get_writable_abookfolders();
   openwebmailerror(gettext('All addressbooks are read-only.')) unless scalar @writableabookfolders;

   $abookfolder  = ow::tool::untaint(safefoldername($abookfolder));
   my $abookfile = abookfolder2file($abookfolder);

   my $completevcard = {};  # will contain all of the data for this card
   my $contact       = {};  # will point to a level of data in $completevcard

   # load up the vcard with the rootxowmuid from the abookfile
   if ($rootxowmuid) {
      my $searchterms = { 'X-OWM-UID' => [ { 'VALUE' => $rootxowmuid } ] }; # only pull this card
      $completevcard  = readadrbook($abookfile, (keys %{$searchterms} ? $searchterms : undef), undef);
      openwebmailerror("The X-OWM-UID does not match any contacts in the $abookfile addressbook\n") unless scalar keys %{$completevcard};
   }

   # defined targetagent describes the agent we want to display:
   # root contact      : targetagent=undefined
   # 1st agent         : targetagent=1,0   where 1 is traversedirection and 0 is targetagent
   # 1st agent's agent : targetagent=1,0,0 where 1 is traversedirection and 0,0 is targetagent
   # where             : <traversedirection>,<agent position(s)>[,<last agent position>]
   # Traverse direction can be 'access agent'(1) or 'access parent'(-1).
   # Last should only be used if traversedirection is -1
   # (so we know what card to save the form data to before we traverse to the parent)
   # targetagent can be a recursively deep map: 1,0,2,0,1
   my ($traversedirection, @targetagent) = defined param('targetagent') ? split(/,/, param('targetagent')) : (0,());

   # we need to pop off the last value if we're traversing up
   pop(@targetagent) if defined $traversedirection && $traversedirection == -1;
   my $targetdepth = scalar @targetagent;

   # start the target on the root contact
   my $target = $completevcard->{$rootxowmuid};

   # keep breadcrumbs of our contactpath in case we traverse to an agent
   my $contactpath = [ { name => $target->{FN}[0]{VALUE}, charset => $target->{'X-OWM-CHARSET'}[0]{VALUE} || $prefs{charset} } ];

   # Align $target so it is pointing to the vcard data we want to modify
   for(my $depth = 1; $depth <= $targetdepth; $depth++) { # 0,0
      if (exists $target->{AGENT}[$targetagent[$depth-1]]{VALUE}) {
         foreach my $agentxowmuid (keys %{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}}) {
            $target = $target->{AGENT}[$targetagent[$depth-1]]{VALUE}{$agentxowmuid};
            $xowmuid = $agentxowmuid;
            push(@{$contactpath}, { name => $target->{FN}[0]{VALUE}, charset => $target->{'X-OWM-CHARSET'}[0]{VALUE} || $prefs{charset}, depth => scalar @{$contactpath} });
         }
      } else {
         # we're creating a new agent from scratch
         $target->{AGENT}[$targetagent[$depth-1]]{TYPES}{VCARD} = 'TYPE';
         $target = $target->{AGENT}[$targetagent[$depth-1]]{VALUE}{''};
         push(@{$contactpath}, { newagent => 1, charset => $prefs{charset}, depth => scalar @{$contactpath} });
      }
   }

   $contact->{$xowmuid} = $target;

   if ($formchange || $upload || $webdisksel) {
      # are we modifying the contact (formchanging or uploading something)?
      # replace the contact data with the form data
      my $formdata = addreditform_to_vcard();
      delete $contact->{$xowmuid}{$_} for keys %{$contact->{$xowmuid}};
      $contact->{$xowmuid}{$_} = $formdata->{$_} for keys %{$formdata};
   }

   # find out composecharset before processing each vcard propertyname so they iconv properly
   my $composecharset = $contact->{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE} || $prefs{charset};

   # iconv the contactpath names and add params for icon support
   $contactpath = [
                     map { {
                              newagent     => $_->{newagent} ? 1 : 0,
                              name         => (iconv($_->{charset}, $composecharset, $_->{name}))[0],
                              depth        => $_->{depth},
                              sessionid    => $thissession,
                              url_cgi      => $config{ow_cgiurl},
                              url_html     => $config{ow_htmlurl},
                              use_texticon => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                              iconset      => $prefs{iconset},
                              (map { $_, $icons->{$_} } keys %{$icons}),
                         } } @{$contactpath}
                  ];

   # TODO: the logic here could probably improve to handle more scenarios - this is the legacy logic
   # TODO: this logic also exists in -send.pl and should be refactored to -shared.pl
   if ($composecharset ne $prefs{charset}) {
      my $composelocale = $prefs{language} . "." . ow::lang::charset_for_locale($composecharset);
      if (exists $config{available_locales}->{$composelocale}) {
         # switch to this character set in the users preferred language if it exists
         $prefs{locale}  = $composelocale;
         $prefs{charset} = $composecharset;
      } else {
         # or else switch to en_US.UTF-8 and hope for the best
         $prefs{locale}  = 'en_US.UTF-8';
         $prefs{charset} = $composecharset;
      }
   }

   $po = loadlang($prefs{locale});
   charset($prefs{charset}) if $CGI::VERSION >= 2.58; # setup charset of CGI module

   # charset conversion menu (convto)
   my %allsets      = ();
   my @convtolist   = ($composecharset);
   my %convtolabels = ($composecharset => "$composecharset *");

   $allsets{$_} = 1 for keys %charset_convlist, map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets;

   delete $allsets{$composecharset};

   if (exists $charset_convlist{$composecharset} && defined $charset_convlist{$composecharset}) {
      foreach my $convtocharset (sort @{$charset_convlist{$composecharset}}) {
         if (is_convertible($composecharset, $convtocharset)) {
            push(@convtolist, $convtocharset);
            $convtolabels{$convtocharset} = "$composecharset > $convtocharset";

            delete $allsets{$convtocharset};
         }
      }
   }

   push(@convtolist, sort keys %allsets);


   #################################################
   # transform $contact for HTML::Template display #
   #################################################

   # all supported propertynames are listed here
   # unsupported propertynames will be displayed generically
   my %propertynames = (
                          BEGIN   => 1, END        => 1, REV      => 1, VERSION       => 1,
                          PROFILE => 1, CATEGORIES => 1, PHOTO    => 1, N             => 1,
                          FN      => 1, SOUND      => 1, NICKNAME => 1, 'SORT-STRING' => 1,
                          BDAY    => 1, EMAIL      => 1, TEL      => 1, ADR           => 1,
                          LABEL   => 1, LOGO       => 1, TITLE    => 1, ROLE          => 1,
                          ORG     => 1, URL        => 1, TZ       => 1, GEO           => 1,
                          MAILER  => 1, NOTE       => 1, KEY      => 1, AGENT         => 1,
                          CLASS   => 1, SOURCE     => 1, NAME     => 1, UID           => 1,
                          PRODID  => 1,

                          'X-OWM-UID'     => 1, 'X-OWM-BOOK'    => 1,
                          'X-OWM-GROUP'   => 1, 'X-OWM-CHARSET' => 1,
                          'X-OWM-CUSTOM'  => 1, 'X-OWM-BDAY'    => 1,
                       );

   # bundle information from one property into another property so they can be displayed together
   my %bundlemap = (LABEL => 'ADR', TITLE => 'ORG', ROLE => 'ORG');
   foreach my $from_property (keys %bundlemap) {
      if (exists $contact->{$xowmuid}{$from_property}) {
         my $to_property = $bundlemap{$from_property};

         $contact->{$xowmuid}{$to_property}[$_]{VALUE}{$from_property} = $contact->{$xowmuid}{$from_property}[$_]{VALUE}
           for(0..$#{$contact->{$xowmuid}{$from_property}});

         delete $contact->{$xowmuid}{$from_property};
      }
   }

   # internally sort the contacts so that PREF fields appear first
   # and the fields are sorted case-insensitively by VALUE
   $contact = internal_sort($contact);

   # force undefined supported propertynames to render in the form by defining them
   foreach my $propertyname (keys %propertynames) {
      next if $propertyname =~ m/^(?:PHOTO|LOGO|SOUND)$/;
      if (!exists $contact->{$xowmuid}{$propertyname}[0]{VALUE}) {
         $contact->{$xowmuid}{$propertyname}[0] = {
                                                    VALUE        => '',
                                                    count        => 0,
                                                    sessionid    => $thissession,
                                                    url_cgi      => $config{ow_cgiurl},
                                                    url_html     => $config{ow_htmlurl},
                                                    use_texticon => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                                    iconset      => $prefs{iconset},
                                                    (map { $_, $icons->{$_} } keys %{$icons}),
                                                  };
      }
   }

   # transform each field to be HTML::Template friendly
   foreach my $propertyname (keys %{$contact->{$xowmuid}}) {
      my $CHARSET = exists $contact->{$xowmuid}{'X-OWM-CHARSET'}
                    ? $contact->{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}
                    : $prefs{charset};

      for(my $i = 0; $i < scalar @{$contact->{$xowmuid}{$propertyname}}; $i++) {
         my $FIELD = $contact->{$xowmuid}{$propertyname}[$i];

         $FIELD->{sessionid}    = $thissession;
         $FIELD->{url_cgi}      = $config{ow_cgiurl};
         $FIELD->{url_html}     = $config{ow_htmlurl};
         $FIELD->{use_texticon} = $prefs{iconset} =~ m/^Text$/ ? 1 : 0;
         $FIELD->{iconset}      = $prefs{iconset};
         $FIELD->{$_}           = $icons->{$_} for keys %{$icons};

         $FIELD->{count}        = $i;
         $FIELD->{deleteable}   = $propertyname =~ m/^(?:NICKNAME|EMAIL|TEL|ADR|ORG|URL|TZ|GEO|MAILER|NOTE|X-OWM-CUSTOM)$/
                                  ? scalar @{$contact->{$xowmuid}{$propertyname}} > 1 ? 1 : 0
                                  : $i > 0 ? 1 : 0;

         if ($propertyname eq 'AGENT') {
            $FIELD->{has_targetagent} = scalar @targetagent ? 1 : 0;
            $FIELD->{targetagentpath} = scalar @targetagent ? join(',',@targetagent) : '';
         }

         # call a defined subroutine for this field (like HT_ADR), or else just run it generic (HT_GENERIC)
         no strict 'refs';
         my $sub = "HT_$propertyname";
         $sub =~ s/-/_/g; # X-OWM-CUSTOM becomes X_OWM_CUSTOM
         ($FIELD, $CHARSET) = defined *$sub{CODE} ? $sub->($FIELD, $CHARSET) : HT_GENERIC->($FIELD, $CHARSET);

         $contact->{$xowmuid}{$propertyname}[$i] = $FIELD;

         if (!exists $propertynames{$propertyname}) {
            $FIELD->{propertyname} = $propertyname;
            if (exists $FIELD->{TYPES}) {
               $FIELD->{TYPES}[$_]{propertyname} = $propertyname for (0..$#{$FIELD->{TYPES}});
            }
            push(@{$contact->{$xowmuid}{UNSUPPORTED}}, $FIELD);
         }
      }

      if ($propertyname =~ m/(?:URL|NICKNAME)/) {
         # mark the last entry so we know when to put the field tip text
         $contact->{$xowmuid}{$propertyname}[$#{$contact->{$xowmuid}{$propertyname}}]{last} = 1;
      } elsif ($propertyname eq 'EMAIL' && param('editgroupform')) {
         # this is a group form - concatenate all the emails into one field
         $contact->{$xowmuid}{EMAIL}[0]{allemail} = join("\n", map { $_->{VALUE} } @{$contact->{$xowmuid}{EMAIL}}) ;
         # and remove the other fields so we do not loop through them during display
         splice(@{$contact->{$xowmuid}{EMAIL}},1,$#{$contact->{$xowmuid}{EMAIL}}) if scalar @{$contact->{$xowmuid}{EMAIL}} > 1;
      }
   }

   $contact->{$xowmuid}{sessionid}               = $thissession;
   $contact->{$xowmuid}{url_cgi}                 = $config{ow_cgiurl};
   $contact->{$xowmuid}{url_html}                = $config{ow_htmlurl};
   $contact->{$xowmuid}{use_texticon}            = $prefs{iconset} =~ m/^Text$/ ? 1 : 0;
   $contact->{$xowmuid}{iconset}                 = $prefs{iconset};
   $contact->{$xowmuid}{$_}                      = $icons->{$_} for keys %{$icons};
   $contact->{$xowmuid}{is_abookfolder_writable} = is_abookfolder_writable($abookfolder);
   $contact->{$xowmuid}{has_targetagent}         = scalar @targetagent ? 1 : 0;
   $contact->{$xowmuid}{targetagentpath}         = scalar @targetagent ? join(',',@targetagent) : '';
   $contact->{$xowmuid}{totalagents}             = $contact->{$xowmuid}{AGENT}[0]{VALUE} ? scalar @{$contact->{$xowmuid}{AGENT}} : 0;
   $contact->{$xowmuid}{targetdepth}             = $targetdepth;
   $contact->{$xowmuid}{availableattspace}       = int($config{abook_attlimit} - ((getattfilesinfo())[0] / 1024) + .5);
   $contact->{$xowmuid}{can_save}                = (is_abookfolder_writable($abookfolder) || $xowmuid eq '') ? 1 : 0;

   #############################################
   # $contact is not modified after this point #
   #############################################

   my $templatefile = param('editgroupform') ? 'abook_editgroupform.tmpl' : 'abook_editcontactform.tmpl';

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template($templatefile),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      sessionid                  => $thissession,
                      folder                     => $folder,
                      sort                       => $sort,
                      msgdatetype                => $msgdatetype,
                      page                       => $page,
                      longpage                   => $longpage,
                      searchtype                 => $searchtype,
                      keyword                    => $keyword,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont              => $prefs{usefixedfont},
                      use_lightbar               => $prefs{uselightbar},
                      charset                    => $prefs{charset},
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder                => $abookfolder,
                      abookpage                  => $abookpage,
                      abooklongpage              => $abooklongpage,
                      abooksort                  => $abooksort,
                      abooksearchtype            => $abooksearchtype,
                      abookkeyword               => $abookkeyword,
                      abookcollapse              => $abookcollapse,

                      # abook_edit(contact|group)form.tmpl
                      enable_webmail             => $config{enable_webmail},
                      messageid                  => $messageid,
                      enable_calendar            => $config{enable_calendar},
                      weekstart                  => $prefs{calendar_weekstart},
                      calendar_defaultview       => $prefs{calendar_defaultview},
                      enable_addressbook         => $config{enable_addressbook},
                      enable_webdisk             => $config{enable_webdisk},
                      enable_sshterm             => $config{enable_sshterm},
                      use_ssh2                   => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar" ? 1 : 0,
                      use_ssh1                   => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar" ? 1 : 0,
                      enable_preference          => $config{enable_preference},
                      quotaoverlimit             => ($quotalimit > 0 && $quotausage > $quotalimit) ? 1 : 0,
                      availablefreespace         => $config{abook_maxsizeallbooks} - userabookfolders_totalsize(),
                      is_abookfolderdefault      => is_defaultabookfolder($abookfolder),
                      "abookfolder_$abookfolder" => 1,
                      abookfolder_label          => f2u($abookfolder),
                      is_caller_readmessage      => $editformcaller eq 'readmessage' ? 1 : 0,
                      is_caller_listmessages     => $editformcaller eq 'listmessages' ? 1 : 0,
                      is_caller_ALL              => $editformcaller eq 'ALL' ? 1 : 0,
                      is_caller_abookfolder      => $editformcaller !~ m/(?:readmessage|listmessages|ALL)/ ? 1 : 0,
                      editformcaller             => $editformcaller,
                      xowmuid                    => $xowmuid,
                      rootxowmuid                => $rootxowmuid,
                      has_targetagent            => scalar @targetagent ? 1 : 0,
                      targetagentpath            => scalar @targetagent ? join(',',@targetagent) : '',
                      writableabooksloop         => [
                                                      map { {
                                                              is_defaultabookfolder => is_defaultabookfolder($_),
                                                              "option_$_"           => 1,
                                                              option                => $_,
                                                              label                 => f2u($_),
                                                              selected              => $abookfolder eq $_ ? 1 : 0,
                                                              is_global             => is_abookfolder_global($_),
                                                          } } @writableabookfolders
                                                    ],
                      convtoselectloop           => [
                                                      map { {
                                                              option   => $_,
                                                              label    => exists $convtolabels{$_} ? $convtolabels{$_} : $_,
                                                              selected => $composecharset eq $_ ? 1 : 0,
                                                          } } @convtolist
                                                    ],
                      composecharset             => $composecharset,
                      contactpath                => $contactpath,
                      contactloop                => [ $contact->{$xowmuid} ],
                      makelabel                  => -f "$config{ow_htmldir}/javascript/make_label_$prefs{locale}.js" ? "make_label_$prefs{locale}" : 'make_label',
                      jumptolastchanged          => $formchange =~ m/^(EMAIL|TEL|ADR|ORG|URL|X-OWM-CUSTOM|PHOTO|SOUND|LOGO|KEY|AGENT)/ ? $1 :
                                                    $upload ? param('UPLOAD.TYPE') : 0,
                      selectpopupwidth           => $prefs{abook_width}  eq 'max' ? 0 : $prefs{abook_width},
                      selectpopupheight          => $prefs{abook_height} eq 'max' ? 0 : $prefs{abook_height},
                      abook_defaultkeyword       => $prefs{abook_defaultfilter} ? $prefs{abook_defaultkeyword} : '',
                      abook_defaultsearchtype    => $prefs{abook_defaultfilter} ? $prefs{abook_defaultsearchtype} : '',

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub addreditform_merge_nested {
   # merges source data structure into target. Allows multiple nests to
   # be processed onto the same target - filling the array slots instead
   # of overwriting them with undef values.
   # Needed mostly for the ORG and X-OWM-CUSTOM datatypes that have
   # nested arrays in their data structure.
   # Be careful if you're changing this, its recursive and infinite!
   my ($r_target, $r_source) = @_;

   if (ref($r_source) eq 'HASH') {
      foreach my $key (keys %{$r_source}) {
         if (!exists $r_target->{$key}) {
            $r_target->{$key} = $r_source->{$key};
         }
         if (ref($r_source->{$key}) eq 'HASH') {
            addreditform_merge_nested(\%{$r_target->{$key}}, \%{$r_source->{$key}});
         } elsif (ref($r_source->{$key}) eq 'ARRAY') {
            addreditform_merge_nested(\@{$r_target->{$key}}, \@{$r_source->{$key}});
         } elsif (ref($r_source->{$key}) eq 'SCALAR') {
            addreditform_merge_nested(\${$r_target->{$key}}, \${$r_source->{$key}});
         } else {
            $r_target->{$key} = $r_source->{$key};
         }
      }
   } elsif (ref($r_source) eq 'ARRAY') {
      for(my $pos=0; $pos < scalar @{$r_source}; $pos++) {
         if (defined $r_source->[$pos]) {
            if (!defined $r_target->[$pos]) { # no danger of array overwrite
               $r_target->[$pos] = $r_source->[$pos];
            }
         } else {
            if (defined $r_target->[$pos]) {
               next; # preserve the value in the target
            } else {
               $r_target->[$pos] = $r_source->[$pos];
            }
         }
         if (ref($r_source->[$pos]) eq 'HASH') {
            addreditform_merge_nested(\%{$r_target->[$pos]}, \%{$r_source->[$pos]});
         } elsif (ref($r_source->[$pos]) eq 'ARRAY') {
            addreditform_merge_nested(\@{$r_target->[$pos]}, \@{$r_source->[$pos]});
         } elsif (ref($r_source->[$pos]) eq 'SCALAR') {
            addreditform_merge_nested(\${$r_target->[$pos]}, \${$r_source->[$pos]});
         } else {
            $r_target->[$pos] = $r_source->[$pos];
         }
      }
   } elsif (ref($r_source) eq 'SCALAR') {
      if (defined ${$r_source}) {
         ${$r_target} = ${$r_source};
      }
   } else {
      $r_target = $r_source;
   }
}

sub addreditform_to_vcard {
   # load the information coming from the html form and return it as a vcard hash structure
   # this is called when the user is performing a formchange or an upload to the form
   # it is also called from the addrimport subroutine to process csv and tab imports
   my $convfrom = param('convfrom');
   my $convto   = param('X-OWM-CHARSET.0.VALUE');

   # we need to force the FN value into N to make the card valid if its a group.
   if (param('editgroupform')) {
      param(-name => 'N.0.VALUE.GIVENNAME', -value => ucfirst(gettext('group')));
      param(-name => 'N.0.VALUE.FAMILYNAME', -value => param('FN.0.VALUE'));

      # break group EMAIL.0.VALUE into individual emails
      my $groupemails = param('EMAIL.0.VALUE') || '';
      my @groupemails = ow::tool::str2list($groupemails);
      param(-name => "EMAIL.$_.VALUE", -value => $groupemails[$_]) for (0..$#groupemails);
   }

   # get the full list of form field names
   my @form = param();

   my $formdata = {};

   # capture all of the form fields into a vcard structure
   foreach my $field (sort @form) {
      my ($propertyname,$index,$datatype,$nested) = $field =~ m/^(\S+?)\.(\d+)\.(VALUE|GROUP|TYPE)\.?(\S+)?$/;

      # catch "preferred" values
      # they are the only exception to the PROPERTYNAME.INDEX.DATATYPE.NESTED1.NESTED2
      # rule since preferred fields are named like EMAIL.preferred or TEL.preferred
      if ((!defined $propertyname || $propertyname eq '') && $field =~ m/^(\S+?)\.preferred$/) {
         $propertyname = $1;
         $index = param("$propertyname.preferred");
         $formdata->{$propertyname}[$index]{TYPES}{'PREF'} = 'TYPE';
         next;
      }

      # a non-vcard form element (like action)?
      next unless defined $datatype;

      my $value = param($field);

      if ($datatype eq 'VALUE') {
         if (defined $nested) {
            # create the nested data structure
            my %nest = ();
            my @nestkeys = split(/\./, $nested); # ORG.0.VALUE.ORGANIZATIONALUNITS.0
            for(my $pos = $#nestkeys; $pos >= 0; $pos--) { # start from the end of nestkeys
               if ($nestkeys[$pos] =~ m/^\d+$/) { # this is an array nest
                  if (defined $nestkeys[$pos+1]) { # there is a next one
                     # this one should ref to the next one
                     $nest{$nestkeys[$pos]}[$nestkeys[$pos]] = $nest{$nestkeys[$pos+1]};
                     delete $nest{$nestkeys[$pos+1]};
                  } else { # there is no next one - assign value
                     $nest{$nestkeys[$pos]}[$nestkeys[$pos]] = (iconv($convfrom, $convto, $value))[0];
                  }
               } else { # this is a hash nest
                  if (defined $nestkeys[$pos+1]) { # there is a next one
                     $nest{$nestkeys[$pos]}{$nestkeys[$pos]} = $nest{$nestkeys[$pos+1]};
                     delete $nest{$nestkeys[$pos+1]};
                  } else { # there is no next one - assign value
                     $nest{$nestkeys[$pos]}{$nestkeys[$pos]} = (iconv($convfrom, $convto, $value))[0];
                  }
               }

               if ($pos == 0) {
                  %nest = %{$nest{$nestkeys[0]}};
                  addreditform_merge_nested(\%{$formdata->{$propertyname}[$index]{VALUE}}, \%nest);
               }
            }
         } else {
            $formdata->{$propertyname}[$index]{VALUE} = (iconv($convfrom, $convto, $value))[0];
         }
      } elsif ($datatype eq 'GROUP') {
         $formdata->{$propertyname}[$index]{GROUP} = (iconv($convfrom, $convto, $value))[0];
      } elsif ($datatype eq 'TYPE') {
         my @types = param($field);
         foreach my $type (@types) {
            next if $type eq 'PREF' && $propertyname =~ m/^(?:EMAIL|TEL|ADR)$/;
            $formdata->{$propertyname}[$index]{TYPES}{(iconv($convfrom, $convto, $type))[0]} = 'TYPE';
         }
      } else {
         openwebmailerror(gettext('Unsupported vcard datatype:') . " $datatype");
      }
   }

   # process formchange adds (EMAIL,0,1) or removes (EMAIL,5,-1)
   # formchange can also point to nested fields like ORG.0.VALUE.ORGANIZATIONALUNITS,0,1
   if (param('formchange')) {
      my ($formchange,$formchangeindex,$formchangeamount) = split(/,/, param('formchange'));

      $formchangeamount = 0 unless defined $formchangeamount;

      if ($formchangeamount > 0 || $formchangeamount < 0) {
         # figure out the form change target
         my $formchangetarget = $formdata;

         foreach my $nestlevel (split(/\./, $formchange)) {
            if ($nestlevel =~ m/^\d+$/) {
               $formchangetarget = $formchangetarget->[$nestlevel];
            } else {
               $formchangetarget = $formchangetarget->{$nestlevel};
            }
         }

         if ($formchangeamount > 0) {
            push(@{$formchangetarget}, $formchange =~ m/(?:ORGANIZATIONALUNITS|CUSTOMVALUES)/ ? '' : { VALUE => '' }); # add an item
         } else {
            splice(@{$formchangetarget},$formchangeindex,1); # remove an item
         }
      }
   }

   return $formdata;
}

sub addredit {
   my $formchange = param('formchange') || '';
   my $upload     = param('upload') || '';
   my $webdisksel = param('webdisksel') || '';

   if ($formchange) {
      #############################################################
      # not ready to process yet, just modifying the form         #
      # the form changes will be handled by addreditform_to_vcard #
      #############################################################
      addreditform();
   } elsif (param('cancelparent')) {
      #################################################################
      # cancel the editing of an AGENT and move back up to the parent #
      #################################################################
      my ($traversedirection, @targetagent) = defined param('targetagent') ? split(/,/, param('targetagent')) : (0,());
      openwebmailerror(gettext('Invalid traverse direction:') . " $traversedirection") unless $traversedirection == -1;
      pop(@targetagent);
      param(-name => "targetagent", -value => scalar @targetagent ? '0,' . join(',',@targetagent) : 0);
      addreditform();
   } elsif ($upload || $webdisksel) {
      #################################################
      # not ready to process yet, uploading something #
      #################################################
      my $uploadtype = param('UPLOAD.TYPE') || '';
      my $uri        = param('UPLOAD.URI')  || '';
      my $attachment = param('UPLOAD.FILE') || '';

      # remove $thissession from uri if it is a OWM link (user linked from webdisk)
      $uri =~ s/\Q$thissession\E/\%THISSESSION\%/;

      openwebmailerror(gettext('Unsupported upload type:') . " $uploadtype")
        if ($uploadtype !~ m/(?:PHOTO|SOUND|LOGO|KEY|AGENT)/); # someone is playing around

      # list of extensions we will accept as uploads
      my %approvedext = (
                          'PHOTO' => { # according to vCard RFC
                                       'GIF'   => 'Graphics Interchange Format',
                                       'CGM'   => 'ISO Computer Graphics Metafile',
                                       'WMF'   => 'Microsoft Windows Metafile',
                                       'BMP'   => 'Microsoft Windows Bitmap',
                                       'MET'   => 'IBM PM Metafile',
                                       'PMB'   => 'IBM PM Bitmap',
                                       'DIB'   => 'MS Windows DIB',
                                       'PICT'  => 'Apple Picture Format',
                                       'TIFF'  => 'Tagged Image File Format',
                                       'PS'    => 'Adobe Postscript Format',
                                       'PDF'   => 'Adobe Page Description Format',
                                       'JPEG'  => 'ISO JPEG Format',
                                       'MPEG'  => 'ISO MPEG Format',
                                       'MPEG2' => 'ISO MPEG Version 2 Format',
                                       'AVI'   => 'Intel AVI Format',
                                       'QTIME' => 'Apple Quicktime Format',

                                       # approved by OWM
                                       'PIC'   => 'Apple Picture Format',
                                       'TIF'   => 'Tagged Image File Format',
                                       'JPG'   => 'ISO JPEG Format',
                                       'MPG'   => 'ISO MPEG Format',
                                       'MPG2'  => 'ISO MPEG Version 2 Format',
                                       'MOV'   => 'Apple Quicktime Format',
                                       'SWF'   => 'Macromedia Shockwave Flash',
                                       'PNG'   => 'Portable Network Graphics',
                                     },
                          'SOUND' => { # according to vCard RFC
                                       'WAVE'  => 'Microsoft WAVE Format',
                                       'PCM'   => 'MIME basic audio type',
                                       'AIFF'  => 'AIFF Format',

                                       # approved by OWM
                                       'WAV'   => 'Microsoft WAVE Format',
                                       'AIFC'  => 'AIFF Format',
                                       'AIF'   => 'AIFF Format',
                                       'AU'    => 'Sun Audio Format',
                                     },
                            'KEY' => { # according to vCard RFC
                                       'X509'  => 'X.509 Public Key Certificate',
                                       'PGP'   => 'IETF Pretty Good Privacy Key',

                                       # approved by OWM
                                       'GPG'   => 'GNU Privacy Guard',
                                     },
                           'LOGO' => { # according to vCard RFC
                                       'GIF'   => 'Graphics Interchange Format',
                                       'CGM'   => 'ISO Computer Graphics Metafile',
                                       'WMF'   => 'Microsoft Windows Metafile',
                                       'BMP'   => 'Microsoft Windows Bitmap',
                                       'MET'   => 'IBM PM Metafile',
                                       'PMB'   => 'IBM PM Bitmap',
                                       'DIB'   => 'MS Windows DIB',
                                       'PICT'  => 'Apple Picture Format',
                                       'TIFF'  => 'Tagged Image File Format',
                                       'PS'    => 'Adobe Postscript Format',
                                       'PDF'   => 'Adobe Page Description Format',
                                       'JPEG'  => 'ISO JPEG Format',
                                       'MPEG'  => 'ISO MPEG Format',
                                       'MPEG2' => 'ISO MPEG Version 2 Format',
                                       'AVI'   => 'Intel AVI Format',
                                       'QTIME' => 'Apple Quicktime Format',

                                       # approved by OWM
                                       'PIC'   => 'Apple Picture Format',
                                       'TIF'   => 'Tagged Image File Format',
                                       'JPG'   => 'ISO JPEG Format',
                                       'MPG'   => 'ISO MPEG Format',
                                       'MPG2'  => 'ISO MPEG Version 2 Format',
                                       'MOV'   => 'Apple Quicktime Format',
                                       'SWF'   => 'Macromedia Shockwave Flash',
                                       'PNG'   => 'Portable Network Graphics',
                                     },
                          'AGENT' => { 'VCF'   => 'Versit Card Format' },
                        );

      # TODO : a lot of this upload code is duplicated in openwebmail-send
      # TODO : it would probably be worthwhile to abstract uploading into ow-shared

      my ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

      my $attname = '';
      my $attcontenttype = '';

      if ($webdisksel || $attachment) {
         if ($attachment) {
            my $composecharset = param('X-OWM-CHARSET.0.VALUE') || $prefs{charset};

            # Convert :: back to the ' like it should be.
            $attname = $attachment;
            $attname =~ s/::/'/g;

            # Trim the path info from the filename
            if ($composecharset eq 'big5' || $composecharset eq 'gb2312') {
               $attname = ow::tool::zh_dospath2fname($attname); # dos path
            } else {
               $attname =~ s|^.*\\||; # dos path
            }

            $attname =~ s|^.*/||; # unix path
            $attname =~ s|^.*:||; # mac path and dos drive

            if (defined CGI::uploadInfo($attachment)) {
               # CGI::uploadInfo($attachment) returns a hash ref of the browser info about the attachment
               $attcontenttype = CGI::uploadInfo($attachment)->{'Content-Type'} || 'application/octet-stream';
            } else {
               # browser did not tell us. Can we figure it out?
               my $ext = uc(ow::tool::contenttype2ext(ow::tool::ext2contenttype($attname)));
               if (exists $approvedext{$uploadtype}{$ext}) {
                  $attcontenttype = ow::tool::ext2contenttype($attname);
               } else {
                  $attcontenttype = 'application/octet-stream';
               }
            }

            $attachment = CGI::upload('UPLOAD.FILE'); # get the CGI.pm filehandle in a strict safe way
         } elsif ($webdisksel && $config{enable_webdisk}) {
            my $webdiskrootdir = ow::tool::untaint($homedir . absolute_vpath("/", $config{webdisk_rootpath}));
            my $vpath = absolute_vpath('/', $webdisksel);
            my $vpathstr = f2u($vpath);

            verify_vpath($webdiskrootdir, $vpath);

            openwebmailerror(gettext('File does not exist:') . " $vpathstr") if !-f "$webdiskrootdir/$vpath";

            $attachment = do { no warnings 'once'; local *FH };
            sysopen($attachment, "$webdiskrootdir/$vpath", O_RDONLY) or
               openwebmailerror(gettext('Cannot open file:') . " $vpathstr ($!)");
            $attname = $vpath;
            $attname =~ s#/$##;   # strip trailing slash
            $attname =~ s#^.*/##;
            $attcontenttype = ow::tool::ext2contenttype($vpath);
         }

         if ($attachment) {
            if ($config{abook_attlimit} > 0 && (($attfiles_totalsize + (-s $attachment)) > ($config{abook_attlimit} * 1024))) {
               close($attachment);
               openwebmailerror(sprintf(ngettext('The attachment exceeds the %d KB limit.','The attachment exceeds the %d KB limit.', $config{abook_attlimit}), $config{abook_attlimit}));
            }

            my $attserial = time() . join('', map { int(rand(10)) }(1..9));

            sysopen(ATTFILE, "$config{ow_sessionsdir}/$thissession-vcard$attserial", O_WRONLY|O_TRUNC|O_CREAT) or
               openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$thissession-vcard$attserial ($!)");

            binmode ATTFILE; # to ensure images do not corrupt

            my $buff    = '';
            my $attsize = 0;

            while (read($attachment, $buff, 400*57)) {
               $attsize += length($buff);
               print ATTFILE $buff;
            }

            close(ATTFILE) or
               openwebmailerror(gettext('Cannot close file:') . " $config{ow_sessionsdir}/$thissession-vcard$attserial ($!)");

            close($attachment); # close tmpfile created by CGI.pm

            # Check that agents only contain a single contact and are valid files
            if ($uploadtype eq 'AGENT') {
               my $test = readadrbook("$config{ow_sessionsdir}/$thissession-vcard$attserial", undef, undef);
               if (keys %{$test} > 1) {
                  openwebmailerror(gettext('An agent upload may only contain one contact.'));
               }
            }

            $attfiles_totalsize += $attsize;

            my $uploadextension = uc(ow::tool::contenttype2ext($attcontenttype));

            # fix firefox labelling of uploaded material
            $uploadextension = 'PGP' if $attcontenttype eq 'application/pgp-keys' && $uploadextension eq 'BIN' && $uploadtype eq 'KEY';
            $uploadextension = 'GPG' if $attcontenttype eq 'application/octet-stream' && $uploadextension eq 'BIN' && $uploadtype eq 'KEY';

            # add the uploaded thing
            if (exists $approvedext{$uploadtype}{$uploadextension}) {
               # what is the index number for this new upload?
               my @form     = param();
               my $newindex = 0;

               foreach my $field (sort @form) {
                  my ($propertyname,$index,$datatype,$nestedhashes) = $field =~ m/^(\S+?)\.(\d+)\.(VALUE|GROUP|TYPE)\.?(\S+)?$/;
                  $newindex++ if $index == $newindex && $propertyname eq $uploadtype;
               }

               # add this value to the param list for later processing
               param(-name => "$uploadtype.$newindex.VALUE", -value => $attserial);

               if ($uploadtype eq 'AGENT') {
                  param(-name => "$uploadtype.$newindex.TYPE", -value => [$uploadextension, 'VCARD']);
               } else {
                  param(-name => "$uploadtype.$newindex.TYPE", -value => [$uploadextension, 'BASE64']);
               }
            } else {
               # remove the unauthorized upload temp file
               unlink("$config{ow_sessionsdir}/$thissession-vcard$attserial");
               openwebmailerror(gettext('The upload is not an approved file or type:') . " $uploadtype ($attcontenttype $uploadextension)");
            }
         }
      } elsif ($uri) {
         # what is the index number for this new upload?
         my @form     = param();
         my $newindex = 0;

         # which index is this upload going to be of this type? i.e. - is this picture #2,#3,etc?
         foreach my $field (sort @form) {
            my ($propertyname,$index,$datatype,$nestedhashes) = $field =~ m/^(\S+?)\.(\d+)\.(VALUE|GROUP|TYPE)\.?(\S+)?$/;
            $newindex++ if $index == $newindex && $propertyname eq $uploadtype;
         }

         # url may be something like http://www.site.com/pic.pl?number=5
         # in which case we will have no idea what the extension is - so just blindly accept the value
         param(-name => "$uploadtype.$newindex.VALUE", -value => $uri);

         # can we figure out the extension?
         my $uploadextension = uc(ow::tool::contenttype2ext(ow::tool::ext2contenttype(lc($uri))));
         if (exists $approvedext{$uploadtype}{$uploadextension}) {
            param(-name => "$uploadtype.$newindex.TYPE", -value => [$uploadextension, 'URI']);
         } else {
            param(-name => "$uploadtype.$newindex.TYPE", -value => ['URI']);
         }
      }

      addreditform();
   } else {
      ######################################################################
      # Finally, ready to process form data.                               #
      # We're here for one of two possible reasons:                        #
      #  - we want to save the form data to a card. Simple. In this case   #
      #    we are here from addreditform or we are here from quickadd.     #
      #  - we want to access an agent. Before we do so we need to save the #
      #    the data of the card we're currently on.                        #
      ######################################################################
      my $rootxowmuid    = param('rootxowmuid') || '';
      my $xowmuid        = $rootxowmuid;

      my $completevcard = {};  # will contain all of the data for this card
      my $contact       = {};  # will point to a level of data in $completevcard

      $abookfolder  = ow::tool::untaint(safefoldername($abookfolder));
      my $abookfile = abookfolder2file($abookfolder);

      openwebmailerror(gettext('You do not have permission to edit the global addressbook.'))
         if is_abookfolder_global($abookfolder) && !is_abookfolder_writable($abookfolder);

      # load up the vcard with the rootxowmuid from the abookfile
      if ($rootxowmuid) {
         my $searchterms = { 'X-OWM-UID' => [ { 'VALUE' => $rootxowmuid } ] }; # only pull this card
         $completevcard  = readadrbook($abookfile, (keys %{$searchterms} ? $searchterms : undef), undef);
         openwebmailerror(gettext('The xowmuid does not match any contacts in the addressbook:') . " $rootxowmuid\:$abookfile") unless scalar keys %{$completevcard};
      } else {
         $completevcard->{$rootxowmuid} = {};
      }

      # align contact as described by the targetagent
      my ($traversedirection, @targetagent) = defined param('targetagent') ? split(/,/, param('targetagent')) : (0,());

      # if we're going into another agent we want to save the level above it
      pop(@targetagent) if $traversedirection == 1;
      my $targetdepth = scalar @targetagent;

      # start the target on the root contact
      my $target = $completevcard->{$rootxowmuid};

      # Align $target so it is pointing to the vcard data we want to modify
      for(my $depth = 1; $depth <= $targetdepth; $depth++) { # 0,0
         if (exists $target->{AGENT}[$targetagent[$depth-1]]{VALUE}) {
            foreach my $agentxowmuid (keys %{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}}) {
               $target  = $target->{AGENT}[$targetagent[$depth-1]]{VALUE}{$agentxowmuid};
               $xowmuid = $agentxowmuid;
            }
         } else {
            # we're creating a new agent from scratch
            $xowmuid = '';
            param(-name => "X-OWM-UID.0.VALUE", -value => $xowmuid);
            $target->{AGENT}[$targetagent[$depth-1]]{TYPES}{VCARD} = 'TYPE';
            $target->{AGENT}[$targetagent[$depth-1]]{VALUE}{$xowmuid} = {};
            $target = $target->{AGENT}[$targetagent[$depth-1]]{VALUE}{$xowmuid};
         }
      }

      $contact->{$xowmuid} = $target;

      # replace the contact data with the form data
      my $formdata = addreditform_to_vcard();
      delete $contact->{$xowmuid}{$_} for keys %{$contact->{$xowmuid}};
      $contact->{$xowmuid}{$_} = $formdata->{$_} for keys %{$formdata};

      # Convert all BASE64 and VCARD files in the sessions directories to be included in the vcard.
      foreach my $propertyname (qw(PHOTO LOGO SOUND KEY AGENT)) {
         if (exists $contact->{$xowmuid}{$propertyname}) {
            for(my $index = 0; $index < scalar @{$contact->{$xowmuid}{$propertyname}}; $index++) {
               if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}) {
                  if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{BASE64} ||
                      exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{VCARD}) {
                     my $fileserial = $contact->{$xowmuid}{$propertyname}[$index]{VALUE};

                     # make fileserial safe in case someone is getting tricky
                     $fileserial = ow::tool::untaint(safefoldername($fileserial));
                     my $targetfile = "$config{ow_sessionsdir}/$thissession-vcard$fileserial";
                     if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{VCARD}) {
                        $contact->{$xowmuid}{$propertyname}[$index]{VALUE} = readadrbook("$targetfile",undef,undef); # attach vcard file
                     } else {
                        sysopen(FILE, $targetfile, O_RDWR|O_CREAT) or
                          openwebmailerror(gettext('Cannot open file:') . " $targetfile ($!)");

                        $contact->{$xowmuid}{$propertyname}[$index]{VALUE} = do { local $/; <FILE> }; # attach binary file

                        close FILE or
                          openwebmailerror(gettext('Cannot close file:') . " $targetfile ($!)");
                     }
                     unlink($targetfile);
                  }
               }
            }
         }
      }

      # unbundle the propertynames we bundled previously
      my %unbundlemap = ( 'ADR' => ['LABEL'], 'ORG' => ['TITLE','ROLE'] );
      foreach my $key (keys %unbundlemap) {
         if (exists $contact->{$xowmuid}{$key}) {
            for(my $index = 0; $index < scalar @{$contact->{$xowmuid}{$key}}; $index++) {
               foreach my $target (@{$unbundlemap{$key}}) {
                  if (exists $contact->{$xowmuid}{$key}[$index]{VALUE}{$target}) {
                     $contact->{$xowmuid}{$target}[$index]{VALUE} = $contact->{$xowmuid}{$key}[$index]{VALUE}{$target};
                     delete $contact->{$xowmuid}{$key}[$index]{VALUE}{$target};
                  }
                  if (exists $contact->{$xowmuid}{$key}[$index]{GROUP}) {
                     $contact->{$xowmuid}{$target}[$index]{GROUP} = $contact->{$xowmuid}{$key}[$index]{GROUP};
                  }
                  if (exists $contact->{$xowmuid}{$key}[$index]{TYPES}) {
                     $contact->{$xowmuid}{$target}[$index]{TYPES} = $contact->{$xowmuid}{$key}[$index]{TYPES};
                  }
                  # special cases
                  if ($target eq 'LABEL') {
                     $contact->{$xowmuid}{$target}[$index]{TYPES}{BASE64} = 'ENCODING';
                  }
               }
            }
         }
      }

      ################################################################################
      # The form has been laid into $contact (and by reference into $completevcard). #
      # Time to output the completecard.                                             #
      ################################################################################

      # outputvfile will check values and add X-OWM-UID if needed.
      # readvfile will make it a hash, double check values,
      # and add any missing propertynames.
      $completevcard = readvfile(outputvfile('vcard',$completevcard));

      # reset $xowmuid in case outputvfile assigned one because it was blank before.
      # $xowmuid would be blank if we were coming from a new card.
      my $oldxowmuid = $xowmuid;
      $xowmuid = $_ for keys %{$completevcard};

      if ($oldxowmuid eq '' && $rootxowmuid eq '') {
         # we were blank before everywhere - must be our first card.
         # set param to remember in case we are traversing into an agent.
         param(-name => 'rootxowmuid', -value => $xowmuid, -override => 1);
         $rootxowmuid = $xowmuid;
      }

      # update the revision time of this card
      update_revision_time($completevcard->{$xowmuid}{REV}[0]);

      # load up the entire addressbook to save out the changed card
      my $completebook = readadrbook($abookfile, undef, undef);

      # and overwrite the target card with the new data...
      $completebook->{$rootxowmuid} = $completevcard->{$rootxowmuid};

      # and write it out!
      my $writeoutput = outputvfile('vcard',$completebook);

      ow::filelock::lock($abookfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($abookfile));

      sysopen(TARGET, $abookfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($abookfile) . " ($!)");

      print TARGET $writeoutput;

      close(TARGET) or
         openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($abookfile) . " ($!)");

      ow::filelock::lock($abookfile, LOCK_UN) or writelog("cannot unlock file $abookfile");

      writelog("edit contact - $rootxowmuid from $abookfolder");
      writehistory("edit contact - $rootxowmuid from $abookfolder");

      # display it
      if ($traversedirection == 1 || $traversedirection == -1) {
         # continue on to display the targetagent
         # now that this level is saved
         addreditform();
      } else {
         my $editformcaller = param('editformcaller') || '';
         if ($editformcaller eq 'readmessage') {
            print redirect(-location => qq|$config{ow_cgiurl}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession| .
                                        qq|&amp;folder=|      . ow::tool::escapeURL($folder)      .
                                        qq|&amp;page=|        . ow::tool::escapeURL($page)        .
                                        qq|&amp;longpage=|    . ow::tool::escapeURL($longpage)    .
                                        qq|&amp;sort=|        . ow::tool::escapeURL($sort)        .
                                        qq|&amp;searchtype=|  . ow::tool::escapeURL($searchtype)  .
                                        qq|&amp;keyword=|     . ow::tool::escapeURL($keyword)     .
                                        qq|&amp;msgdatetype=| . ow::tool::escapeURL($msgdatetype) .
                                        qq|&amp;message_id=|  . ow::tool::escapeURL($messageid)
                          );
         } elsif ($editformcaller eq 'listmessages') {
            print redirect(-location => qq|$config{ow_cgiurl}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession| .
                                        qq|&amp;folder=|      . ow::tool::escapeURL($folder)      .
                                        qq|&amp;page=|        . ow::tool::escapeURL($page)        .
                                        qq|&amp;longpage=|    . ow::tool::escapeURL($longpage)    .
                                        qq|&amp;sort=|        . ow::tool::escapeURL($sort)        .
                                        qq|&amp;searchtype=|  . ow::tool::escapeURL($searchtype)  .
                                        qq|&amp;keyword=|     . ow::tool::escapeURL($keyword)     .
                                        qq|&amp;msgdatetype=| . ow::tool::escapeURL($msgdatetype) .
                                        qq|&amp;message_id=|  . ow::tool::escapeURL($messageid)
                          );
         } elsif (param('quickadd')) {
            return 0;
         } else {
            addrlistview();
         }
      }
   }
}

sub addrviewatt {
   my $file = param('file') || openwebmailerror(gettext('No named file to view'));
   my $type = param('type') || ''; # undef makes application/octet-stream

   $type = lc $type;

   my $contenttype = ow::tool::ext2contenttype($type);
   my $ext = ow::tool::contenttype2ext($contenttype);
   $ext = 'unknown' if $ext eq 'bin';

   my $target = ow::tool::untaint("$config{ow_sessionsdir}/$thissession-vcard$file");

   sysopen(FILE, $target, O_RDONLY) or
     openwebmailerror(gettext('Cannot open file:') . " $target ($!)");

   my $attbody = do {local $/; <FILE> }; # slurp

   close FILE or
     openwebmailerror(gettext('Cannot close file:') . " $target ($!)");

   my $length = length $attbody;
   if ($length > 512 && is_http_compression_enabled()) {
      my $zattbody = Compress::Zlib::memGzip($attbody);
      my $zlen = length $zattbody;
      my $zattheader = qq|Content-Encoding: gzip\n| .
                       qq|Vary: Accept-Encoding\n| .
                       qq|Content-Length: $zlen\n| .
                       qq|Connection: close\n| .
                       qq|Content-Type: $contenttype; name="inline.$ext"\n| .
                       qq|Content-Disposition: inline; filename="$file.$ext"\n|;
      print $zattheader, "\n", $zattbody;
   } else {
      my $attheader = qq|Content-Length: $length\n| .
                      qq|Connection: close\n| .
                      qq|Content-Type: $contenttype; name="inline.$ext"\n| .
                      qq|Content-Disposition: inline; filename="$file.$ext"\n|;
      print $attheader, "\n", $attbody;
   }
}

sub update_revision_time {
   my $r_rev = shift;

   my ($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year,$rev_wday,$rev_yday,$rev_isdst) = gmtime(time);
   $rev_mon++;
   $rev_year += 1900;

   $r_rev->{VALUE}{SECOND} = $rev_sec;
   $r_rev->{VALUE}{MINUTE} = $rev_min;
   $r_rev->{VALUE}{HOUR}   = $rev_hour;
   $r_rev->{VALUE}{DAY}    = $rev_mday;
   $r_rev->{VALUE}{MONTH}  = $rev_mon;
   $r_rev->{VALUE}{YEAR}   = $rev_year;
}

sub deleteattachments {
   # remove all the attachments associated with this vcard from the sessions directories
   my @delfiles  = ();
   my @sessfiles = ();

   opendir(SESSIONSDIR, $config{ow_sessionsdir}) or
      openwebmailerror(gettext('Cannot open directory:') . " $config{ow_sessionsdir} ($!)");

   @sessfiles = readdir(SESSIONSDIR);

   closedir(SESSIONSDIR) or
      openwebmailerror(gettext('Cannot close directory:') . " $config{ow_sessionsdir} ($!)");

   foreach my $attfile (@sessfiles) {
      push(@delfiles, ow::tool::untaint("$config{ow_sessionsdir}/$attfile"))
         if ($attfile =~ m/^(\Q$thissession\E\-vcard\d+)$/);
   }

   unlink(@delfiles) if $#delfiles >= 0;
}

sub getattfilesinfo {
   my @attfiles  = ();
   my $totalsize = 0;

   opendir(SESSIONSDIR, $config{ow_sessionsdir}) or
      openwebmailerror(gettext('Cannot open directory:') . " $config{ow_sessionsdir} ($!)");

   my @sessfiles = readdir(SESSIONSDIR);

   closedir(SESSIONSDIR) or
      openwebmailerror(gettext('Cannot close directory:') . " $config{ow_sessionsdir} ($!)");

   foreach my $sessionfile (@sessfiles) {
      if ($sessionfile =~ /^(\Q$thissession\E\-vcard\d+)$/) {
         my $size = -s "$config{ow_sessionsdir}/$sessionfile";

         push(@attfiles, { file => $1, size => $size });

         $totalsize += $size;
      }
   }

   return ($totalsize, \@attfiles);
}

sub get_writable_abookfolders {
   my @userbooks   = grep { is_abookfolder_writable($_) } get_user_abookfolders();
   my @globalbooks = grep { is_abookfolder_writable($_) } get_global_abookfolders();
   return(@userbooks, @globalbooks);
}

sub is_abookfolder_writable {
   my $abookfoldername = shift;

   my $webaddrdir = dotpath('webaddr');

   if ($abookfoldername eq 'ALL') {
      return 0;
   } elsif (-f "$config{ow_addressbooksdir}/$abookfoldername") {
      return 1 if $config{abook_globaleditable} && -w "$config{ow_addressbooksdir}/$abookfoldername";
   } else {
      return 1 if -w "$webaddrdir/$abookfoldername";
   }
   return 0;
}

sub userabookfolders_totalsize {
   my $totalsize = 0;

   $totalsize += (-s abookfolder2file($_)) for get_user_abookfolders();

   return int($totalsize / 1024 + 0.5);
}

sub is_quota_available {
   my $writesize = shift;

   if ($quotalimit > 0 && $quotausage + $writesize > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
      return 0 if ($quotausage + $writesize > $quotalimit);
   }

   return 1;
}

sub deepcopy {
    # a shameless rip from http://www.stonehenge.com/merlyn/UnixReview/col30.html
    # this should probably be moved to the ow::tool at some point.
    my $this = shift;
    if (not ref $this) {
       $this;
    } elsif (ref $this eq 'ARRAY') {
       [map deepcopy($_), @$this];
    } elsif (ref $this eq 'HASH') {
       scalar { map { $_ => deepcopy($this->{$_}) } keys %$this };
    } else {
       croak("unsupported datatype for deepcopy: $_");
    }
}

sub addrimportform {
   # this is step 1 of 3 of the import process
   # the user chooses the format and uploads the file for import
   my $importformat      = param('importformat') || 'vcard3.0';
   my $importcharset     = param('importcharset') || $prefs{charset} || 'none';
   my $importdestination = param('importdestination') || '';

   my %importcharsets    = map { $ow::lang::charactersets{$_}[1] => 1 } keys %ow::lang::charactersets;

   my @allabookfolders = get_readable_abookfolders();

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('abook_importform.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      sessionid                  => $thissession,
                      folder                     => $folder,
                      sort                       => $sort,
                      msgdatetype                => $msgdatetype,
                      page                       => $page,
                      longpage                   => $longpage,
                      searchtype                 => $searchtype,
                      keyword                    => $keyword,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont              => $prefs{usefixedfont},
                      use_lightbar               => $prefs{uselightbar},
                      charset                    => $prefs{charset},
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder                => $abookfolder,
                      abookpage                  => $abookpage,
                      abooklongpage              => $abooklongpage,
                      abooksort                  => $abooksort,
                      abooksearchtype            => $abooksearchtype,
                      abookkeyword               => $abookkeyword,
                      abookcollapse              => $abookcollapse,

                      #abook_importform.tmpl
                      is_abookfolderdefault      => is_defaultabookfolder($abookfolder),
                      "abookfolder_$abookfolder" => 1,
                      abookfolder_label          => f2u($abookfolder),
                      availablefreespace         => $config{abook_maxsizeallbooks} - userabookfolders_totalsize(),
                      abookimportlimit           => $config{abook_importlimit},
                      programname                => $config{name},
                      importformatsloop          => [
                                                       map { {
                                                                "option_$_" => 1,
                                                                selected    => $_ eq $importformat ? 1 : 0,
                                                           } } sort keys %{$supportedformats}
                                                    ],
                      importcharsetdisabled      => $importformat =~ m/vcard/i ? 1 : 0,
                      importcharsetloop          => [
                                                       map { {
                                                                option   => $_,
                                                                label    => $_,
                                                                selected => $_ eq $importcharset ? 1 : 0,
                                                           } } sort keys %importcharsets
                                                    ],
                      importdestinationloop      => [
                                                       map { {
                                                                is_defaultabookfolder => is_defaultabookfolder($_),
                                                                "option_$_"           => 1,
                                                                option                => $_,
                                                                label                 => f2u($_),
                                                                selected              => $_ eq $importdestination ? 1 : 0,
                                                           } } get_writable_abookfolders(),
                                                    ],

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub addrimportfieldselect {
   # this is step 2 of 3 of the import process
   # allow the user to define the list of the fields in a csv or tab import
   # vcard imports bypass this and immediately go to step 3
   my $importfile        = param('importfile')   || openwebmailerror(gettext('A file must be selected for import.'));
   my $importformat      = param('importformat') || openwebmailerror(gettext('An import format must be chosen.'));
   my $importdestination = param('importdestination') || openwebmailerror(gettext('An import destination must be chosen.'));
   my $importcharset     = param('importcharset') || $prefs{charset} || 'none';

   my %importcharsets    = map { $ow::lang::charactersets{$_}[1] => 1 } keys %ow::lang::charactersets;

   # Convert :: back to the ' like it should be.
   $importfile =~ s/::/'/g;

   # Trim the path info from the filename
   if ($importcharset eq 'big5' || $importcharset eq 'gb2312') {
      $importfile = ow::tool::zh_dospath2fname($importfile); # dos path
   } else {
      $importfile =~ s|^.*\\||; # dos path
   }

   $importfile =~ s|^.*/||; # unix path
   $importfile =~ s|^.*:||; # mac path and dos drive

   openwebmailerror(gettext('The chosen import format is unsupported. Please go back and chose a different one:') . " $importformat")
     unless exists $supportedformats->{$importformat};

   my ($importfileext) = $importfile =~ m/\.(...)$/;
   openwebmailerror(gettext('The file extension is incorrect for the chosen import format. The recommended extension for the format is:') . " ($importformat\: $supportedformats->{$importformat}{extension})")
     unless lc $importfileext eq $supportedformats->{$importformat}{extension} || $importfile =~ m/^\d+$/;

   # get the CGI.pm filehandle in a strict safe way
   my $importfilehandle = CGI::upload('importfile');

   my $importfilesize = (-s $importfilehandle);
   openwebmailerror(gettext('The import file is 0 bytes.')) if $importfilesize == 0;

   my $importfilesizekb = sprintf("%0.2f", $importfilesize / 1024);
   openwebmailerror(gettext('The import file size exceeds the available quota space.')) unless is_quota_available($importfilesizekb);

   openwebmailerror(gettext('The import file size exceeds the import file size limit:') . ' ' . lenstr($importfilesizekb, 1) . ' > ' . lenstr($config{abook_importlimit}, 1))
     if $config{abook_importlimit} > 0 && $importfilesizekb > $config{abook_importlimit};

   if ($config{abook_maxsizeallbooks} > 0) {
      # load up the list of all books
      my @allabookfolders = get_readable_abookfolders();

      # calculate the available free space
      my $availfreespace = $config{abook_maxsizeallbooks} - userabookfolders_totalsize();
      openwebmailerror(gettext('The import file size exceeds the available free space:') . ' ' . lenstr($importfilesizekb, 1) . ' > ' . lenstr($availfreespace, 1))
        if $importfilesizekb > $availfreespace;
   }

   # save the uploaded file to the sessions directory
   my $attserial = time() . join('', map { int(rand(10)) }(1..9));

   sysopen(ATTFILE, "$config{ow_sessionsdir}/$thissession-vcard$attserial", O_WRONLY|O_TRUNC|O_CREAT) or
     openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$thissession-vcard$attserial ($!)");
   binmode ATTFILE; # to ensure images do not corrupt

   my $buff = '';
   my $attsize = 0;
   while (read($importfilehandle, $buff, 400*57)) {
      $attsize += length($buff);
      print ATTFILE $buff;
   }

   close ATTFILE or
     openwebmailerror(gettext('Cannot close file:') . " $config{ow_sessionsdir}/$thissession-vcard$attserial ($!)");
   seek $importfilehandle,0,0; # reset the filehandle position to zero

   # remember the serial number to recall it later
   param(-name => 'importserial', -value => $attserial, -override => 1);

   # SKIP THE FIELD SELECTION FOR VCARD IMPORTS
   return addrimport() if $importformat =~ m/^(?:vcard2.1|vcard3.0)$/;

   # slurp in the import file
   sysread $importfilehandle, my $importfilecontents, -s $importfilehandle;
   close($importfilehandle); # close tmpfile created by CGI.pm

   # parse it to get the fields that are currently defined
   my $fieldseparator = $importformat =~ m/^csv$/ ? ',' : "\t";
   my $records = parse_fsv($importfilecontents, $fieldseparator);

   # check that each record has the same number of fields
   my %recordsizes = map { scalar @{$_}, 1 } @{$records};

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template('abook_importfieldselect.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      sessionid                  => $thissession,
                      folder                     => $folder,
                      sort                       => $sort,
                      msgdatetype                => $msgdatetype,
                      page                       => $page,
                      longpage                   => $longpage,
                      searchtype                 => $searchtype,
                      keyword                    => $keyword,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      use_fixedfont              => $prefs{usefixedfont},
                      use_lightbar               => $prefs{uselightbar},
                      charset                    => $prefs{charset},
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # addressbook params
                      abookfolder                => $abookfolder,
                      abookpage                  => $abookpage,
                      abooklongpage              => $abooklongpage,
                      abooksort                  => $abooksort,
                      abooksearchtype            => $abooksearchtype,
                      abookkeyword               => $abookkeyword,
                      abookcollapse              => $abookcollapse,

                      # abook_importfieldselect.tmpl
                      is_abookfolderdefault      => is_defaultabookfolder($abookfolder),
                      "abookfolder_$abookfolder" => 1,
                      abookfolder_label          => f2u($abookfolder),
                      availablefreespace         => $config{abook_maxsizeallbooks} - userabookfolders_totalsize(),
                      is_inconsistentdata        => scalar keys %recordsizes > 1 ? 1 : 0,
                      importfile                 => $importfile,
                      importserial               => $attserial,
                      importformat               => $importformat,
                      importcharset              => $importcharset,
                      importdestination          => $importdestination,
                      importfieldsloop           => [
                                                       map { {
                                                                odd             => $_ % 2 == 0 ? 0 : 1,
                                                                datasampleone   => $records->[0][$_],
                                                                datasampletwo   => $records->[1][$_],
                                                                datasamplethree => $records->[2][$_],
                                                           } } (0..$#{$records->[0]})
                                                    ],

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub addrimport {
   # this is step 3 of 3 of the import process
   # the uploaded file has been placed in the sessions directory (addrimportform)
   # the user has defined all of the fields, if required (addrimportfieldselect)
   # we are now ready to convert the import data to vcard and save it
   my $importfile        = param('importfile')   || openwebmailerror(gettext('A file must be selected for import.'));
   my $importformat      = param('importformat') || openwebmailerror(gettext('An import format must be chosen.'));
   my $importdestination = param('importdestination') || openwebmailerror(gettext('An import destination must be chosen.'));
   my $importserial      = param('importserial') || openwebmailerror(gettext('Import file has no auto assigned serial number.'));
   my $importcharset     = param('importcharset') || $prefs{charset} || 'none';
   my $importfirstrow    = param('importfirstrow') || 0;
   my @importfields      = param('importfield');


   @importfields = () unless defined $importfields[0];

   my %importcharsets    = map { $ow::lang::charactersets{$_}[1] => 1 } keys %ow::lang::charactersets;

   openwebmailerror(gettext('Illegal character set for import')) unless exists $importcharsets{$importcharset};

   openwebmailerror(gettext('Illegal serial for import')) if $importserial !~ m/^\d+$/;

   # read the import data from the sessions directory
   my $importsessionfile = ow::tool::untaint("$config{ow_sessionsdir}/$thissession-vcard$importserial");

   sysopen(FILE, $importsessionfile, O_RDONLY) or
     openwebmailerror(gettext('Cannot open file:') . " $importsessionfile ($!)");
   my $importfilecontents = do {local $/; <FILE> }; # slurp
   close FILE or
     openwebmailerror(gettext('Cannot close file:') . " $importsessionfile ($!)");

   # translate the import data into a vcard data structure
   my $newaddrinfo = $importformat =~ m/^(?:vcard2.1|vcard3.0)/ ? importvcard($importfilecontents) :
                     $importformat =~ m/^(?:csv|tab)/ ? importfsv($importfilecontents, $importformat, $importcharset, $importfirstrow, @importfields) :
                     openwebmailerror(gettext('Invalid import format:') . " $importformat");

   # write out the result
   if ($importdestination eq 'newaddressbook') {
      # write the import to a new addressbook
      my $fname = $importfile;

      # Convert :: back to the ' like it should be.
      $fname =~ s/::/'/g;

      # Trim the path info from the filename
      if ($prefs{charset} eq 'big5' || $prefs{charset} eq 'gb2312') {
         $fname = ow::tool::zh_dospath2fname($fname); # dos path
      } else {
         $fname =~ s#^.*\\##; # dos path
      }
      $fname =~ s#^.*/##; # unix path
      $fname =~ s#^.*:##; # mac path and dos drive

      my $newbookfile = ow::tool::untaint(abookfolder2file($fname));

      openwebmailerror(gettext('Addressbook already exists:') . ' ' . f2u($fname))
        if -e $newbookfile || $fname =~ m/^(?:ALL|DELETE)$/;

      my $writeoutput = outputvfile('vcard', $newaddrinfo);

      sysopen(IMPORT, $newbookfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($fname) . " ($!)");
      print IMPORT $writeoutput;
      close(IMPORT) or
         openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($fname) . " ($!)");

      writelog("import addressbook - upload new book $fname");
      writehistory("import addressbook - upload new book $fname");
      $abookfolder = $fname;
   } else {
      # append the import to a selected book
      my $targetfile = ow::tool::untaint(abookfolder2file($importdestination));
      my $targetbook = readadrbook($targetfile, undef, undef);

      # merge the new data
      foreach my $xowmuid (keys %{$newaddrinfo}) {
         $targetbook->{$xowmuid} = $newaddrinfo->{$xowmuid};
      }

      # stringify it
      my $writeoutput = outputvfile('vcard', $targetbook);

      # overwrite the targetfile with the new data
      ow::filelock::lock($targetfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($targetfile) . " ($!)");

      sysopen(TARGET, $targetfile, O_WRONLY|O_TRUNC|O_CREAT) or
        openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($targetfile) . " ($!)");

      print TARGET $writeoutput;

      close(TARGET) or
        openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($targetfile) . " ($!)");

      ow::filelock::lock($targetfile, LOCK_UN);

      writelog("import addressbook - " . scalar keys(%{$newaddrinfo}) . " contacts to $importdestination");
      writehistory("import addressbook - " . scalar keys(%{$newaddrinfo}) . " contacts to $importdestination");

      # done
      $abookfolder = $importdestination;
   }

   # import done - go back to the listing
   addrlistview();
}

sub importvcard {
   # accepts a vCard string and returns a vCard hash data structure

   # shares/adrbook.pl already loads shares/vfile.pl which contains
   # the routine we need for parsing vcard data. So this import is
   # the easiest one to do.
   my $importdata = shift;
   return readvfile($importdata);
}

sub importfsv {
   # accepts a csv or tab string and returns a vCard hash data structure
   my ($importdata, $importformat, $importcharset, $importfirstrow, @importfields) = @_;

   openwebmailerror(gettext('No import fields have been defined.'))
     if (scalar grep { !m/^none$/ } @importfields) == 0;

   my %validfields = (
                        PROFILE  => 1, CATEGORIES    => 1, N     => 1, FN     => 1, SOUND        => 1,
                        NICKNAME => 1, 'SORT-STRING' => 1, EMAIL => 1, TEL    => 1, 'X-OWM-BDAY' => 1,
                        ADR      => 1, LABEL         => 1, TITLE => 1, ROLE   => 1, ORG          => 1,
                        URL      => 1, TZ            => 1, GEO   => 1, MAILER => 1, NOTE         => 1,
                        CLASS    => 1, SOURCE        => 1, NAME  => 1, UID    => 1, PRODID       => 1,
                     );

   # validate and rename importfields so they can be
   # automatically processed by addreditform_to_vcard
   # example: ADR.VALUE.STREET ==> ADR.0.VALUE.STREET
   # be careful to maintain the importfield order so we
   # properly remap the old field names to the new field names
   my %fieldcount = ();
   for(my $i = 0; $i < scalar @importfields; $i++) {
      my $fieldname = $importfields[$i];

      next if $fieldname eq 'none';

      my ($propertyname, $datatype, @attributes) = split(/\./, $fieldname);

      $propertyname = '' unless defined $propertyname;
      $datatype     = '' unless defined $datatype;

      openwebmailerror(gettext('Invalid property name for import:') . " $propertyname")
        unless exists $validfields{$propertyname};

      openwebmailerror(gettext('Invalid datatype for import:') . " $datatype")
        if $datatype !~ m/(?:VALUE|GROUP|TYPE)/;

      $fieldcount{$fieldname}++;

      my $newfieldname = "$propertyname." . ($fieldcount{$fieldname} - 1) . ".$datatype";
      $newfieldname .= '.' . join('.', @attributes) if scalar @attributes > 0;
      $importfields[$i] = $newfieldname;
   }

   # get the records from the import
   my $fieldseparator = $importformat =~ m/^csv$/ ? ',' : "\t";
   my $records = parse_fsv($importdata, $fieldseparator);

   my $vcardhash = {};

   for(my $i = 0; $i < scalar @{$records}; $i++) {
      next if $i == 0 && $importfirstrow == 0;

      for(my $p = 0; $p < scalar @importfields; $p++) {
         next if $importfields[$p] eq 'none';
         param(-name => $importfields[$p], -value => $records->[$i][$p]);
      }

      my $importrecord = addreditform_to_vcard();
      $importrecord->{'X-OWM-CHARSET'}[0]{VALUE} = $importcharset;

      $importrecord->{N}[0]{VALUE}{GIVENNAME} = 'undefined'
                                                unless exists $importrecord->{N}
                                                && exists $importrecord->{N}[0]{VALUE}
                                                && exists $importrecord->{N}[0]{VALUE}{GIVENNAME}
                                                && $importrecord->{N}[0]{VALUE}{GIVENNAME} =~ m/\S/;

      my $record_xowmuid = make_xowmuid();
      $vcardhash->{$record_xowmuid}{$_} = $importrecord->{$_} for keys %{$importrecord};
      $vcardhash->{$record_xowmuid}{'X-OWM-UID'}[0]{VALUE} = $record_xowmuid;
   }

   return $vcardhash;
}

sub parse_fsv {
   # given a string of data, parse it as a list of field separated values (usually comma or tab)
   my ($data, $fieldseparator) = @_;

   # Parse the character separated file
   # There may be fields which have double-quotes, linebreaks,
   # commas, and tabs inside them, inside double-quotes!

   $data =~ s/\r?\n|\r/::safe_newline::/g;                                # DOS/UNIX independent line breaks
   $data =~ s/"($fieldseparator|::safe_newline::)/::safe_qfend::$1/g;     # end of a quoted field
   $data =~ s/(^|$fieldseparator|::safe_newline::)"/$1::safe_qfstart::/g; # start of a quoted field
   $data =~ s/""/::safe_quote::/g;                                        # quotes inside a field

   while ($data =~ s/(::safe_qfstart::(?:(?!::safe_qfend::).)*?)$fieldseparator(.+?::safe_qfend::)/$1::safe_infs::$2/g) {};
   while ($data =~ s/(::safe_qfstart::(?:(?!::safe_qfend::).)*?)::safe_newline::(.+?::safe_qfend::)/$1\n$2/gs) {};

   $data =~ s/$fieldseparator/::safe_fs::/g;   # unique field separator
   $data =~ s/::safe_infs::/$fieldseparator/g; # restore tab/quote inside fields
   $data =~ s/::safe_quote::/"/g;              # restore quotes inside fields
   $data =~ s/::safe_(?:qfstart|qfend):://g;   # rm field-delimiting quotes (not needed anymore)

   my @records = ();
   foreach my $record (split(/::safe_newline::/, $data)) {
      push(@records, [ map { s/^ +| +$|'//g; $_ } split(/::safe_fs::/, $record) ]);
   }

   return \@records;
}

sub make_xowmuid {
   # generate an xowmuid like: 20040909-073403-35PDGCRZE5OQ-HVLF
   my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
   my @chars = ( 'A' .. 'Z', 0 .. 9 );
   my $uid = ($uid_year + 1900) .
             sprintf("%02d", ($uid_mon + 1)) .
             sprintf("%02d", $uid_mday) .
             '-' .
             sprintf("%02d", $uid_hour) .
             sprintf("%02d", $uid_min) .
             sprintf("%02d", $uid_sec) .
             '-' .
             (join '', map { $chars[rand @chars] } 1..12) .
             '-' .
             (join '', map { $chars[rand @chars] } 1..4);
   return $uid;
}

sub addrexport {
   # This sub does the actual exporting. It does not generate the export form.
   # The export form is the 'export' mode of the listview subroutine.
   my $exportformat = param('exportformat') || 'vcard3.0';

   openwebmailerror(gettext('The chosen export format is not supported:') . " $exportformat")
     unless exists $supportedformats->{$exportformat};

   my @xowmuids = param('xowmuid');

   return addrlistview() unless scalar @xowmuids;

   # separate into individual addresses and eliminate duplicates
   my %unique_xowmuid = ();
   @xowmuids = sort grep { !$unique_xowmuid{$_}++ } @xowmuids;

   my $exportbody        = '';
   my $exportcontenttype = '';
   my $exportfilename    = '';

   # load up the list of available books
   my @allabookfolders = get_readable_abookfolders();

   # load the addresses - only the required information
   my $addresses   = {};
   my $searchterms = { 'X-OWM-UID' => [ { VALUE => join("|", @xowmuids) } ] };

   foreach my $folder (@allabookfolders) {
      my $abookfile = abookfolder2file($folder);
      my $thisbook  = readadrbook($abookfile, $searchterms, undef);

      # remember what book this address came from
      foreach my $xowmuid (keys %{$thisbook}) {
         $addresses->{$xowmuid} = $thisbook->{$xowmuid};
         # The exports should have Product ID of the version of OWM they were exported from
         $addresses->{$xowmuid}{PRODID}[0]{VALUE} = "$config{name} $config{version} $config{releasedate}";
      }
   }

   # figure the version request
   my ($version) = $exportformat =~ m/^vcard([\d.]+)/;
   $version = '' unless defined $version;

   # now send the vCard hash structure to the exporter to get the converted data for export
   ($exportbody, $exportcontenttype, $exportfilename) = $exportformat =~ m/^vcard[\d.]+$/ ? exportvcard($addresses, $version) :
                                                        $exportformat =~ m/^csv$/         ? exportfsv($addresses, 'csv')      :
                                                        $exportformat =~ m/^tab$/         ? exportfsv($addresses, 'tab')      :
                                                        openwebmailerror(gettext('Invalid export format:') . " $exportformat");

   # send the export data to the browser
   my $exportlength = length($exportbody);
   my $exportheader .= qq|Connection: close\n| .
                       qq|Content-Type: $exportcontenttype; name="$exportfilename"\n| .

                       # ie5.5 is broken with content-disposition: attachment
                       (
                         $ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/
                         ? qq|Content-Disposition: filename="$exportfilename"\n|
                         : qq|Content-Disposition: attachment; filename="$exportfilename"\n|
                       );

   # should we gzip it?
   if ($exportlength > 512 && is_http_compression_enabled()) {
      $exportbody   = Compress::Zlib::memGzip($exportbody);
      $exportlength = length($exportbody);
      $exportheader .= qq|Content-Encoding: gzip\n|.
                       qq|Vary: Accept-Encoding\n|;
   }

   $exportheader .= qq|Content-Length: $exportlength\n|;

   print $exportheader, "\n", $exportbody;
}

sub exportvcard {
   # accepts a vCard hash data structure and returns a vCard format string.
   # shares/adrbook.pl autoloads /shares/vfile.pl which contains outputvfile
   my ($r_addresses, $version) = @_;
   my ($exportcontenttype, $exportfilename) = ('application/x-vcard', (gettext('Export') . '.vcf'));
   my $exclude_propertynames = { 'X-OWM-UID' => 1 };
   return (outputvfile('vcard', $r_addresses, $version, $exclude_propertynames), $exportcontenttype, $exportfilename);
}

sub exportfsv {
   # given a vcard hash data structure, output a field separated list (usually comma or tab)
   # the export order is sorted alphanumerically and cannot be chosen by the user at this time
   my ($r_addresses, $exportformat) = @_;

   my $exportfilename = gettext('Export') . '.' . $exportformat;

   my %fieldnames = ();
   my @records    = ();

   foreach my $xowmuid (keys %{$r_addresses}) {
      my $flathash = make_flathash($r_addresses->{$xowmuid});
      $fieldnames{$_}++ for keys %{$flathash}; # store unique field names
      push(@records, $flathash);
   }

   my $fieldseparator = $exportformat eq 'csv' ? ',' : "\t";

   my $exportdata = join($fieldseparator, sort keys %fieldnames) . "\n"; # first row defining all fields

   foreach my $record (@records) {
      $exportdata .= join($fieldseparator, map {
                                                  my $field = exists $record->{$_} ? $record->{$_} : '';
                                                  $field =~ s/"/""/g;
                                                  $field =~ m/(?:$fieldseparator|\n)/ ? qq|"$field"| : $field
                                                } sort keys %fieldnames
                         ) . "\n";
   }

   return ($exportdata, 'text/plain', $exportfilename);
}

sub make_flathash {
   # This sub will get one vcard structure and make a "flat" hash
   # (i.e., one key per scalar value), which is then used to export to
   # the other formats.
   # TODO: there should be an infinitely recursive flatten sub for
   # HASH, ARRAY, SCALAR and references at arbitrary depth
   my $vcard = shift;
   my $exportcharset = param('exportcharset') || '';

   my %flathash = ();

   foreach my $propertyname (keys %{$vcard}) {
      next if ($propertyname =~ /^(?:PHOTO|LOGO|SOUND|KEY|AGENT)$/);
      for (my $i = 0; $i < scalar @{$vcard->{$propertyname}}; $i++) {
         if (exists $vcard->{$propertyname}[$i]{VALUE}) {
            if (ref($vcard->{$propertyname}[$i]{VALUE}) eq 'HASH') {
               foreach my $key (sort keys %{$vcard->{$propertyname}[$i]{VALUE}}) {
                  if ($vcard->{$propertyname}[$i]{VALUE}{$key} =~ m/\S/) {
                     if (ref($vcard->{$propertyname}[$i]{VALUE}{$key}) eq 'ARRAY') {
                        for (my $j = 0; $j < scalar @{$vcard->{$propertyname}[$i]{VALUE}{$key}}; $j++) {
                           # flatkey like: ORG_00_ORGANIZATIONALUNITS_00
                           my $flatkey = join('_', ($propertyname, sprintf("%02d", $i), $key, sprintf("%02d", $j)));
                           $flathash{$flatkey} = $vcard->{$propertyname}[$i]{VALUE}{$key}[$j];
                        }
                     } else {
                        # flatkey like: N_00_GIVENNAME
                        my $flatkey = join('_', ($propertyname, sprintf("%02d", $i), $key));
                        $flathash{$flatkey} = $vcard->{$propertyname}[$i]{VALUE}{$key};
                     }
                  }
               }
            } elsif ($vcard->{$propertyname}[$i]{VALUE} =~ m/\S/) {
               # flatkey like: EMAIL_00
               my $flatkey = join('_', ($propertyname, sprintf("%02d", $i)));
               $flathash{$flatkey} = $vcard->{$propertyname}[$i]{VALUE};
            }

            if (exists $vcard->{$propertyname}[$i]{TYPES}) {
               # flatkey like: EMAIL_00_TYPE
               my $flatkey = join('_', ($propertyname, sprintf("%02d", $i), 'TYPE'));
               $flathash{$flatkey} = join("; ", sort keys %{$vcard->{$propertyname}[$i]{TYPES}});
            }

            if (exists $vcard->{$propertyname}[$i]{GROUP}) {
               # flatkey like: EMAIL_00_GROUP
               my $flatkey = join('_', ($propertyname, sprintf("%02d", $i), 'GROUP'));
               $flathash{$flatkey} = $vcard->{$propertyname}[$i]{GROUP};
            }
         }
      }
   }

   $flathash{'X-OWM-CHARSET'} = $prefs{charset} unless exists $flathash{'X-OWM-CHARSET'};

   if (
        $exportcharset ne 'none'
        && $flathash{'X-OWM-CHARSET'} ne $exportcharset
        && is_convertible($flathash{'X-OWM-CHARSET'}, $exportcharset)
      ) {
      $flathash{$_} = (iconv($flathash{'X-OWM-CHARSET'}, $exportcharset, $flathash{$_}))[0] for keys %flathash;
      $flathash{'X-OWM-CHARSET'} = $exportcharset;
   }

   return \%flathash;
}

sub addrimportattachment {
   # import an attachment node from a given message (presumably a vcard, but import will check that)
   my $nodeid    = param('attachment_nodeid') || openwebmailerror(gettext('No attachment node id provided'));
   my $attname   = param('attname');
   my $attmode   = param('attmode') || 'simple';
   my $headers   = param('headers') || $prefs{headers} || 'simple';
   my $receivers = param('receivers') || 'simple';
   my $convfrom  = param('convfrom') || '';

   # Convert :: back to the ' like it should be.
   $attname =~ s/::/'/g;

   # Trim the path info from the attname
   if ($prefs{'charset'} eq 'big5' || $prefs{'charset'} eq 'gb2312') {
      $attname = ow::tool::zh_dospath2fname($attname); # dos path
   } else {
      $attname =~ s|^.*\\||; # dos path
   }
   $attname =~ s|^.*/||; # unix path
   $attname =~ s|^.*:||; # mac path and dos drive

   my ($content, $contentfilesize) = getmessageattachment($folder, $messageid, $nodeid);

   my $contentfilesizekb = sprintf("%0.2f", $contentfilesize / 1024);

   openwebmailerror(gettext('The import file size exceeds the available quota space.')) unless is_quota_available($contentfilesizekb);

   openwebmailerror(gettext('The import file size exceeds the import file size limit:') . ' ' . lenstr($contentfilesizekb, 1) . ' > ' . lenstr($config{abook_importlimit}, 1))
      if $config{abook_importlimit} > 0 && $contentfilesizekb > $config{abook_importlimit};

   if ($config{abook_maxsizeallbooks} > 0) {
      # load up the list of all books
      my @allabookfolders = get_readable_abookfolders();

      # calculate the available free space
      my $availfreespace = $config{abook_maxsizeallbooks} - userabookfolders_totalsize();
      openwebmailerror(gettext('The import file size exceeds the available free space:') . ' ' . lenstr($contentfilesizekb, 1) . ' > ' . lenstr($availfreespace, 1))
         if $contentfilesizekb > $availfreespace;
   }

   openwebmailerror(gettext('The import file is 0 bytes.')) if $contentfilesize == 0;

   my $attvcards = importvcard($content);

   undef $content; # free memory

   # load the existing book
   my $importdest = $attname || gettext('attachment');
   my $targetfile = ow::tool::untaint(abookfolder2file($importdest));
   my $targetbook = {};

   if (-e $targetfile) {
      $targetbook = readadrbook($targetfile, undef, undef);
   } else {
      # create the book file
      sysopen(TARGET, $targetfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($targetfile) . " ($!)");
      close(TARGET) or
        openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($targetfile) . " ($!)");
   }

   # merge the new data
   foreach my $xowmuid (keys %{$attvcards}) {
      $targetbook->{$xowmuid} = $attvcards->{$xowmuid};
   }

   # stringify it
   my $writeoutput = outputvfile('vcard', $targetbook);

   # overwrite the targetfile with the new data
   ow::filelock::lock($targetfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(gettext('Cannot lock file:') . ' '  . f2u($targetfile) . " ($!)");
   sysopen(TARGET, $targetfile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($targetfile) . " ($!)");
   print TARGET $writeoutput;
   close(TARGET) or
     openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($targetfile) . " ($!)");
   ow::filelock::lock($targetfile, LOCK_UN);

   writelog("import addressbook from attachment - " . scalar keys(%{$attvcards}) . " contacts to $importdest");
   writehistory("import addressbook from attachment - " . scalar keys(%{$attvcards}) . " contacts to $importdest");

   # done
   $abookfolder = $importdest;
   addrlistview();
}

sub getmessageattachment {
   # retreive a specific attachment node from a given message id in a given mail spool
   my ($folder, $messageid, $nodeid) = @_;

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);
   my $folderhandle = do { no warnings 'once'; local *FH };

   my $block   = '';
   my $msgsize = lockget_message_block($messageid, $folderfile, $folderdb, \$block);
   openwebmailerror(gettext('Message ID can no longer be found:') . " $messageid") if $msgsize <= 0;

   my @attr = get_message_attributes($messageid, $folderdb);

   my $convfrom = param('convfrom') || '';
   if ($convfrom eq '') {
      if (is_convertible($attr[$_CHARSET], $prefs{charset})) {
         $convfrom = lc($attr[$_CHARSET]);
      } else {
         $convfrom ="none\.$prefs{charset}";
      }
   }

   # return a specific attachment
   my ($header, $body, $r_attachments) = ow::mailparse::parse_rfc822block(\$block, '0', $nodeid);
   undef($block);

   my $r_attachment = {};
   for (my $i = 0; $i <= $#{$r_attachments}; $i++) {
      if ($r_attachments->[$i]{nodeid} eq $nodeid) {
         $r_attachment = $r_attachments->[$i];
      }
   }

   if (defined $r_attachment) {
      my $charset     = $r_attachment->{filenamecharset} || $r_attachment->{charset} || $convfrom || $attr[$_CHARSET];
      my $contenttype = $r_attachment->{'content-type'};
      my $filename    = $r_attachment->{filename};
      my $content     = ow::mime::decode_content(${$r_attachment->{r_content}}, $r_attachment->{'content-transfer-encoding'});

      $filename =~ s/\s$//;

      return ($content, length($content));
   }

   return ('',0);
}

sub internal_sort {
   # given a hash of one or more complete vcard contacts
   # internally sort each vcard field to ensure:
   #  - the fields with PREF types appear first
   #  - the fields are grouped per the GROUP attribute
   #  - the field are sorted case-insensitively by VALUE
   my $contacts = shift;

   my %sort_priority = (
                          TEL => {
                                    'PREF'  => '0', 'CAR'   => '4', 'VIDEO' => '8',
                                    'HOME'  => '1', 'FAX'   => '5', 'MSG'   => '9',
                                    'WORK'  => '2', 'PAGER' => '6', 'BBS'   => '10',
                                    'CELL'  => '3', 'VOICE' => '7', 'ISDN'  => '11',
                                    'MODEM' => '12',
                                 },
                          ADR => {
                                    'PREF'   => 0, 'DOM'    => 3,
                                    'HOME'   => 1, 'INTL'   => 4,
                                    'WORK'   => 2, 'POSTAL' => 5,
                                    'PARCEL' => 6,
                                 }
                       );

   foreach my $xowmuid (keys %{$contacts}) {
      foreach my $propertyname (keys %{$contacts->{$xowmuid}}) {
         if ($propertyname =~ m/^(?:TEL|ADR)$/) {
            # order the fields by sort priority
            @{$contacts->{$xowmuid}{$propertyname}} = sort {
                                                   my $aPri = 13; # assign lowest priority by default
                                                   my $bPri = 13; # assign lowest priority by default

                                                   # figure out the highest priority number
                                                   foreach my $type (keys %{$sort_priority{$propertyname}}) {
                                                      $aPri = $sort_priority{$propertyname}{$type}
                                                        if exists $a->{TYPES} && exists $a->{TYPES}{$type} && $sort_priority{$propertyname}{$type} < $aPri;
                                                      $bPri = $sort_priority{$propertyname}{$type}
                                                        if exists $b->{TYPES} && exists $b->{TYPES}{$type} && $sort_priority{$propertyname}{$type} < $bPri;
                                                   }

                                                   # Now compare based on priority, group name, then value (~~~ sorts last)
                                                   $aPri <=> $bPri
                                                   || (exists $a->{GROUP} ? lc $a->{GROUP} : '') cmp (exists $b->{GROUP} ? lc $b->{GROUP} : '')
                                                   || ($a->{VALUE} eq '' ? '~~~' : lc $a->{VALUE}) cmp ($b->{VALUE} eq '' ? '~~~' : lc $b->{VALUE})
                                                 } @{$contacts->{$xowmuid}{$propertyname}};
         } elsif ($propertyname eq 'EMAIL') {
            # order the EMAIL fields alphabetically - pop the PREF (exists=0) to the top via Schwartzian transform
            @{$contacts->{$xowmuid}{EMAIL}} = map  { $_->[3] }
                                              sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] }
                                              map  {
                                                     [
                                                       exists $_->{TYPES} ? (exists $_->{TYPES}{PREF} ? 0 : 1) : 1,
                                                       exists $_->{GROUP} ? lc $_->{GROUP} : '',
                                                       $_->{VALUE} eq '' ? '~~~' : lc $_->{VALUE}, # ~~~ sorts last
                                                       $_
                                                     ]
                                                   } @{$contacts->{$xowmuid}{EMAIL}};

            if ($action eq 'addrlistview' || ($action eq 'addredit' && param('save'))) {
               if (exists $contacts->{$xowmuid}{'X-OWM-GROUP'}) {
                 # collapse all the email addresses into an additional "All Members" entry
                 unshift(@{$contacts->{$xowmuid}{EMAIL}}, {
                                                             VALUE    => join (', ', map { $_->{VALUE} }
                                                                         @{$contacts->{$xowmuid}{EMAIL}}),
                                                             is_first => 1,
                                                          }
                        );
                 $_->{is_group} = 1 for @{$contacts->{$xowmuid}{EMAIL}};
               }
            }
         }
         # do not generically sort the remaining propertynames because we
         # want them to remain in the order they are created in the editform
      }
   }

   return $contacts;
}

sub HT_GENERIC {
   # transform the data structure of a vcard field for display using HTML::Template
   # note: all scalars are iconv converted to the pref charset for display here too
   my ($FIELD, $CHARSET) = @_;

   my $no_iconv = shift || 0;

   foreach my $property (qw(VALUE TYPES)) {
      if (exists $FIELD->{$property}) {
         if (ref $FIELD->{$property} eq 'HASH') {
            # make directly accessable keys for HT from the $property hash
            $FIELD->{$_} = ($no_iconv ? $FIELD->{$property}{$_} : (iconv($CHARSET, $prefs{charset}, $FIELD->{$property}{$_}))[0])
                           for keys %{$FIELD->{$property}};

            if ($property eq 'TYPES') {
               # make TYPES HT loopable
               $FIELD->{$property} = [ map { { type => $_, count => $FIELD->{count} } } keys %{$FIELD->{$property}} ];
            }
         } else {
            $FIELD->{$property} = $no_iconv ? $FIELD->{$property} : (iconv($CHARSET, $prefs{charset}, $FIELD->{$property}))[0];
         }
      }
   }

   return ($FIELD, $CHARSET);
}

sub HT_X_OWM_CUSTOM {
   my ($FIELD, $CHARSET) = HT_GENERIC(@_);

   # make CUSTOMVALUES HT loopable
   my $valuescount = -1;
   $FIELD->{CUSTOMVALUES}[0] = '' unless exists $FIELD->{CUSTOMVALUES};
   @{$FIELD->{CUSTOMVALUES}} = map {
                                      $valuescount++;
                                      {
                                         count        => $FIELD->{count},
                                         value        => (iconv($CHARSET, $prefs{charset}, $_))[0],
                                         valuescount  => $valuescount,
                                         url_html     => $config{ow_htmlurl},
                                         use_texticon => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                         iconset      => $prefs{iconset},
                                         (map { $_, $icons->{$_} } keys %{$icons}),
                                         deleteable   => scalar @{$FIELD->{CUSTOMVALUES}} > 1 ? 1 : 0,
                                      }
                                   } @{$FIELD->{CUSTOMVALUES}};
   $FIELD->{CUSTOMVALUES}[$#{$FIELD->{CUSTOMVALUES}}]{last} = 1;

   return ($FIELD, $CHARSET);
}

sub HT_ORG {
   my ($FIELD, $CHARSET) = HT_GENERIC(@_);

   # make ORGANIZATIONALUNITS HT loopable
   my $unitcount = -1;
   $FIELD->{ORGANIZATIONALUNITS}[0] = '' unless exists $FIELD->{ORGANIZATIONALUNITS};
   @{$FIELD->{ORGANIZATIONALUNITS}} = map {
                                            $unitcount++;
                                            {
                                              count        => $FIELD->{count},
                                              unit         => (iconv($CHARSET, $prefs{charset}, $_))[0],
                                              unitcount    => $unitcount,
                                              url_html     => $config{ow_htmlurl},
                                              use_texticon => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                              iconset      => $prefs{iconset},
                                              (map { $_, $icons->{$_} } keys %{$icons}),
                                              deleteable   => scalar @{$FIELD->{ORGANIZATIONALUNITS}} > 1 ? 1 : 0,
                                            }
                                          } @{$FIELD->{ORGANIZATIONALUNITS}};
   $FIELD->{ORGANIZATIONALUNITS}[$#{$FIELD->{ORGANIZATIONALUNITS}}]{last} = 1;

   return ($FIELD, $CHARSET);
}

sub HT_TZ {
   my ($FIELD, $CHARSET) = HT_GENERIC(@_);

   my %timezonelabels = (
                           '-1200' => gettext('International Date Line West'),
                           '-1100' => gettext('Nome, Anadyr'),
                           '-1000' => gettext('Alaska-Hawaii Standard'),
                           '-0900' => gettext('Yukon Standard'),
                           '-0800' => gettext('Pacific Standard'),
                           '-0700' => gettext('Mountain Standard'),
                           '-0600' => gettext('Central Standard'),
                           '-0500' => gettext('Eastern Standard'),
                           '-0400' => gettext('Atlantic Standard'),
                           '-0330' => gettext('Newfoundland Standard'),
                           '-0300' => gettext('Atlantic Daylight'),
                           '-0230' => gettext('Newfoundland Daylight'),
                           '-0200' => gettext('Azores, South Sandwich Islands'),
                           '-0100' => gettext('West Africa'),
                           '+0000' => gettext('Greenwich Mean'),
                           '+0100' => gettext('Central European'),
                           '+0200' => gettext('Eastern European'),
                           '+0300' => gettext('Baghdad, Moscow, Nairobi'),
                           '+0330' => gettext('Tehran'),
                           '+0400' => gettext('Abu Dhabi, Volgograd, Kabul'),
                           '+0500' => gettext('Karachi'),
                           '+0530' => gettext('India'),
                           '+0600' => gettext('Dhaka'),
                           '+0630' => gettext('Rangoon'),
                           '+0700' => gettext('Bangkok, Jakarta'),
                           '+0800' => gettext('China Coast'),
                           '+0900' => gettext('Japan Standard'),
                           '+0930' => gettext('Australia Central Standard'),
                           '+1000' => gettext('Australia Eastern Standard'),
                           '+1030' => gettext('Lord Howe Island'),
                           '+1100' => gettext('Australia Eastern Summer'),
                           '+1200' => gettext('International Date Line East'),
                           '+1300' => gettext('New Zealand Daylight'),
                        );

   $FIELD->{tzselectloop} = [
                              map { {
                                      option   => $_,
                                      label    => "$_ -  $timezonelabels{$_}",
                                      selected => $FIELD->{VALUE}
                                                  ? $FIELD->{VALUE} eq $_  ? 1 : 0
                                                  : $prefs{timeoffset} eq $_ ? 1 : 0
                                  } } qw(
                                          -1200 -1100 -1000 -0900 -0800 -0700 -0600
                                          -0500 -0400 -0330 -0300 -0230 -0200 -0100
                                          +0000
                                          +0100 +0200 +0300 +0330 +0400 +0500 +0530 +0600 +0630
                                          +0700 +0800 +0900 +0930 +1000 +1030 +1100 +1200 +1300
                                        )
                            ];

   return ($FIELD, $CHARSET);
}

sub HT_X_OWM_BDAY {
   my ($FIELD, $CHARSET) = HT_GENERIC(@_);

   $FIELD->{age} = calculate_age(
                                  exists $FIELD->{YEAR}  ? $FIELD->{YEAR}  : '',
                                  exists $FIELD->{MONTH} ? $FIELD->{MONTH} : '',
                                  exists $FIELD->{DAY}   ? $FIELD->{DAY}   : '',
                                );

   return ($FIELD, $CHARSET);
}

sub HT_PHOTO {
   my ($FIELD, $CHARSET) = HT_BINARYDATA(@_);

   $FIELD->{filetype} = 'JPEG' unless defined $FIELD->{filetype};

   return ($FIELD, $CHARSET);
}

sub HT_LOGO {
   my ($FIELD, $CHARSET) = HT_BINARYDATA(@_);

   $FIELD->{filetype} = 'JPEG' unless defined $FIELD->{filetype};

   return ($FIELD, $CHARSET);
}

sub HT_SOUND {
   my ($FIELD, $CHARSET) = HT_BINARYDATA(@_);

   $FIELD->{filetype}    = 'WAV' unless defined $FIELD->{filetype};
   $FIELD->{is_phonetic} = exists $FIELD->{URI} && $FIELD->{VALUE} =~ m#^(?:https?|ftp)://#i ? 0 : 1;

   return ($FIELD, $CHARSET);
}

sub HT_KEY {
   my ($FIELD, $CHARSET) = HT_BINARYDATA(@_);

   $FIELD->{filetype}     = 'GPG' unless defined $FIELD->{filetype};
   $FIELD->{even}         = $FIELD->{count} % 2 == 0 ? 1 : 0;
   $FIELD->{unknown_type} = !exists $FIELD->{GPG} && !exists $FIELD->{X509} && !exists $FIELD->{PGP} ? 1 : 0;

   return ($FIELD, $CHARSET);
}

sub HT_AGENT {
   my ($FIELD, $CHARSET) = HT_BINARYDATA(@_);

   $FIELD->{filetype}     = 'VCF' unless defined $FIELD->{filetype};
   $FIELD->{even}         = $FIELD->{count} % 2 == 0 ? 1 : 0;
   $FIELD->{unknown_type} = !exists $FIELD->{VCARD} ? 1 : 0;

   if (exists $FIELD->{VCARD} && !exists $FIELD->{URI}) {
      # AGENT card got pulled off into a file in the sessions dir
      # retrieve it so that we can get the full name of the agent person
      my $targetfile = ow::tool::untaint("$config{ow_sessionsdir}/$thissession-vcard$FIELD->{VALUE}");
      my $agentvcard = readadrbook($targetfile, undef, undef);

      foreach my $agentowmuid (keys %{$agentvcard}) {
         $FIELD->{agentname} = (iconv($agentvcard->{$agentowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{charset}, $agentvcard->{$agentowmuid}{FN}[0]{VALUE}))[0];
      }

      $FIELD->{is_abookfolder_writable} = is_abookfolder_writable($abookfolder);
   }

   return ($FIELD, $CHARSET);
}

sub HT_BINARYDATA {
   my ($FIELD, $CHARSET) = HT_GENERIC(@_,'no_iconv');

   if (exists $FIELD->{TYPES}) {
      if (ref $FIELD->{TYPES} eq 'ARRAY') {
         # determine the filetype for display or embedding
         $FIELD->{filetype} = (grep { !m/(?:BASE64|URI)/ } map { $_->{type} } @{$FIELD->{TYPES}})[0];
      }

      if (exists $FIELD->{URL} || exists $FIELD->{URI}) {
         # force URI only for H::T
         $FIELD->{URI} = exists $FIELD->{URI} ? $FIELD->{URI} : $FIELD->{URL};
         delete $FIELD->{URL};

         # unwrap <a> linked values
         $FIELD->{VALUE} = $1 if $FIELD->{VALUE} =~ m/href="?([^" >]+)/i;
         $FIELD->{show_inline} = scalar grep { m/^(?:GIF|JPE?G|PNG)$/ } keys %{$FIELD};
      } elsif (exists $FIELD->{BASE64} || exists $FIELD->{VCARD}) {
         unless (param('upload') || param('webdisksel') || param('formchange')) {
            # save the inline data to a temp file in the user session folder
            # so that we can show the file by directly linking to it
            my $fileserial = time() . join('', map { int rand(10) } (1..9));

            sysopen(FILE, "$config{ow_sessionsdir}/$thissession-vcard$fileserial", O_WRONLY|O_TRUNC|O_CREAT) or
              openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$thissession-vcard$fileserial ($!)");

            binmode FILE; # prevent corruption

            # write the already decoded binary data to the temp file
            # it has already been decoded from BASE64 by the vcard routines
            print FILE $FIELD->{VCARD} ? outputvfile('vcard', $FIELD->{VALUE}) : $FIELD->{VALUE};
            close FILE or
              openwebmailerror(gettext('Cannot close file:') . " $config{ow_sessionsdir}/$thissession-vcard$fileserial ($!)");

            # replace the VALUE with the location of this temp file
            $FIELD->{VALUE} = $fileserial;
         }
      }
   }

   return ($FIELD, $CHARSET);
}

sub HT_ADR {
   my ($FIELD, $CHARSET) = HT_GENERIC(@_);

   $FIELD->{enable_map} = cookie('ow-browserjavascript') eq 'dom' ? 1 : 0;

   $FIELD->{mapquery} = join(',',
                              map { $FIELD->{$_} }
                              grep { exists $FIELD->{$_} }
                              qw(STREET EXTENDEDADDRESS POSTOFFICEADDRESS LOCALITY REGION POSTALCODE COUNTRY)
                            );
   $FIELD->{mapquery} =~ s/ /+/g;

   return ($FIELD, $CHARSET);
}

sub HT_CLASS {
   my ($FIELD, $CHARSET) = HT_GENERIC(@_);

   $FIELD->{classselectloop} = [
                                  map { {
                                          "option_$_" => 1,
                                          selected    => $FIELD->{VALUE} eq $_ ? 1 : 0,
                                      } } qw(PUBLIC PRIVATE)
                               ];

   push(@{$FIELD->{classselectloop}}, { option_OTHER => uc $FIELD->{VALUE}, selected => 1 })
     if $FIELD->{VALUE} && $FIELD->{VALUE} !~ m/(?:PUBLIC|PRIVATE)/;

   return ($FIELD, $CHARSET);
}

sub calculate_age {
   # given a year, month, and day, return the age in number of years
   my ($year,$month,$day) = @_;

   $year  = 0 unless defined $year and $year;
   $month = 0 unless defined $month and $month;
   $day   = 0 unless defined $day and $day;

   return '' unless $year;

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
   my ($currentyear, $currentmonth, $currentday) = (ow::datetime::seconds2array($localtime))[5,4,3];
   $currentyear += 1900;
   $currentmonth++;

   my $age = $currentyear - $year;

   # subtract 1 from age if birthday has not happened yet
   $age-- if ($age > 0 && $month && $currentmonth < $month)
             ||
             ($age > 0 && $month && $day && $month == $currentmonth && $currentday < $day);

   return $age;
}

