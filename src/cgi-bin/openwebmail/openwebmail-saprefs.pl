#!/usr/bin/perl -T

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

use strict;
use warnings;

use vars qw($SCRIPT_DIR);

if (-f "/etc/openwebmail_path.conf") {
   my $pathconf = "/etc/openwebmail_path.conf";
   open(F, $pathconf) or die("Cannot open $pathconf: $!");
   my $pathinfo = <F>;
   close(F) or die("Cannot close $pathconf: $!");
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die("SCRIPT_DIR cannot be set") if ($SCRIPT_DIR eq '');
push (@INC, $SCRIPT_DIR);
push (@INC, "$SCRIPT_DIR/lib");

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH}='/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use CGI 3.31 qw(-private_tempfiles :cgi charset);
use CGI::Carp qw(fatalsToBrowser carpout);
use HTML::Template 2.9;

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config $thissession %prefs);
use vars qw($homedir);

# extern vars
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy
use vars qw($htmltemplatefilters);                 # defined in ow-shared.pl

# local globals
use vars qw($folder $messageid);
use vars qw($sort $page);
use vars qw($prefs_caller);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
$SIG{PIPE} = \&openwebmail_exit;	# for user stop
$SIG{TERM} = \&openwebmail_exit;	# for user stop
userenv_init();

if (!$config{enable_webmail} || !$config{enable_saprefs}) {
   openwebmailerror("$lang_text{webmail} $lang_err{access_denied}");
}

$folder       = param('folder')       || 'INBOX';
$page         = param('page')         || 1;
$sort         = param('sort')         || $prefs{sort} || 'date_rev';
$messageid    = param('message_id')   || '';
$prefs_caller = param('prefs_caller') || '';
my $action    = param('action')       || '';

writelog("debug - request saprefs begin, action=$action") if $config{debug_request};

$action eq 'edittest'         ? edittest()                     :
$action eq 'addtest'          ? modtest("add")                 :
$action eq 'deletetest'       ? modtest("delete")              :
$action eq 'editwhitelist'    ? editlist("whitelist")          :
$action eq 'addwhitelist'     ? modlist("add", "whitelist")    :
$action eq 'deletewhitelist'  ? modlist("delete", "whitelist") :
$action eq 'editblacklist'    ? editlist("blacklist")          :
$action eq 'addblacklist'     ? modlist("add", "blacklist")    :
$action eq 'deleteblacklist'  ? modlist("delete", "blacklist") :
   openwebmailerror("Action $lang_err{has_illegal_chars}");

writelog("debug - request saprefs end, action=$action") if $config{debug_request};

openwebmail_requestend();

# BEGIN SUBROUTINES

sub edittest {
   my $saprefsfile = "$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs($saprefsfile);

   my @testnames = sort (keys %{$r_rules});

   my $i = 1;

   my $testloop = [];

   foreach my $testname (@testnames) {
      my %test = %{${$r_rules}{$testname}};

      # modification on these records are not supported
      next if ($test{type} eq 'meta'
               || defined $test{ifunset}
               || defined $test{tflags});

      my $score = '';
      if (defined ${$test{score}}[0]) {
         $score = ${$test{score}}[0];
      } else {
         $score = 1;                           # default 1 for no score test
         $score = 0.01 if $testname =~ m/^T_/; # default 0.01 if test is for testing only
      }
      push(@{$testloop}, {
                           url_cgi        => $config{ow_cgiurl},
                           folder         => $folder,
                           page           => $page,
                           sort           => $sort,
                           message_id     => $messageid,
                           sessionid      => $thissession,
                           prefs_caller   => $prefs_caller,
                           uselightbar    => $prefs{uselightbar},
                           odd            => $i % 2,
                           testnum        => $i,
                           testname       => $testname,
                           testdesc       => $test{desc},
                           testtype       => $test{type},
                           testheaderattr => $test{headerattr},
                           testop         => $test{op},
                           pattern        => $test{pattern},
                           ignorecase     => $test{modifier} =~ m/i/ ? 1 : 0,
                           singleline     => $test{modifier} =~ m/s/ ? 1 : 0,
                           score          => $score,
                         }
          );
      $i++;
   }

   my @scores = (0);
   for (my $i = 0.1; $i < 1; $i += 0.1) {
      push @scores, $i, -$i;
   }
   for (my $i = 1.5; $i < 11; $i += 0.5) {
      push @scores, $i, -$i;
   }
   map {
      push @scores, $_, -$_;
   } (11..20, 30, 40, 50, 100, 200);
   @scores = sort {$b <=> $a} @scores;

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("sa_edittest.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template  => get_header($config{header_template_file}),

                      # standard params
                      use_texticon     => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html         => $config{ow_htmlurl},
                      url_cgi          => $config{ow_cgiurl},
                      iconset          => $prefs{iconset},
                      sessionid        => $thissession,
                      message_id       => $messageid,
                      folder           => $folder,
                      sort             => $sort,
                      page             => $page,
                      (map { $_, $prefs{$_} } grep { m/^iconset_/ } keys %prefs),

                      # sa_edittest.pl
                      prefs_caller     => $prefs_caller,
                      callerfoldername => ($lang_folders{$folder} || f2u($folder)),
                      testloop         => $testloop,
                      scoreloop        => [
                                            map { {
                                                    option   => $_,
                                                    label    => $_,
                                                    selected => $_ eq 0 ? 1 : 0
                                                } } @scores
                                          ],

                      # footer.tmpl
                      footer_template  => get_footer($config{footer_template_file}),
                   );
   httpprint([], [$template->output]);
}

sub modtest {
   my $mode     =  shift;
   my $testname =  param('testname') || '';
   $testname    =~ s/^\s*//;
   $testname    =~ s/\s*$//;
   return edittest() if ($testname eq '');

   my %test;
   my $saprefsfile = "$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs($saprefsfile);

   if ($mode eq 'add') {
      $test{type} =  param('testtype');
      $test{type} =~ s/^\s*//;
      $test{type} =~ s/\s*$//;

      $test{pattern} = param('pattern');

      # remove preceding/trailing spaces and // from pattern
      $test{pattern} =~ s/^\s*\///;
      $test{pattern} =~ s/\/\s*$//;

      # ensure all / are properly escaped
      $test{pattern} =~ s#\\/#/#g;
      $test{pattern} =~ s#/#\\/#g;

      if ($test{type} ne ''
         && $test{pattern} ne ''
         && ow::tool::is_regex($test{pattern})) {

         $test{desc} = param('testdesc') if (param('testdesc') ne '');

         if ($test{type} eq 'header') {
            $test{headerattr} = param('testheaderattr') || 'ALL';
            $test{op}         = param('testop')         || '=~';
         }

         $test{modifier}  =  '';
         $test{modifier} .= 'i' if (param('ignorecase') == 1);
         $test{modifier} .= 's' if (param('singleline') == 1);

         $test{score}     = [sprintf("%4.2f", param('score'))];

         ${$r_rules}{$testname} = \%test;
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   } elsif ($mode eq 'delete') {
      if (defined ${$r_rules}{$testname}) {
         delete ${$r_rules}{$testname};
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   }
   return edittest();
}

sub editlist {
   my ($listtype) = @_;

   return edittest() if ($listtype ne 'whitelist' && $listtype ne 'blacklist');

   my $saprefsfile = "$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs($saprefsfile);

   my @list;
   if ($listtype eq 'whitelist') {
      @list = sort (keys %{$r_whitelist_from});
   } else {
      @list = sort (keys %{$r_blacklist_from});
   }

   my $i = 1;

   my $testloop = [];

   foreach my $email (@list) {
      next if $email !~ m/^(?:[a-zA-Z0-9!#\$%&'*+-\/=?^_`.{|}~]{1,64}@)?[%*a-zA-Z0-9.-]{4,255}$/; # rfc3696

      push(@{$testloop}, {
                           url_cgi      => $config{ow_cgiurl},
                           folder       => $folder,
                           page         => $page,
                           sort         => $sort,
                           message_id   => $messageid,
                           sessionid    => $thissession,
                           prefs_caller => $prefs_caller,
                           uselightbar  => $prefs{uselightbar},
                           odd          => $i % 2,
                           email        => $email,
                           whitelist    => $listtype eq 'whitelist' ? 1 : 0
                         }
          );
      $i++;
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("sa_editlist.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template  => get_header($config{header_template_file}),

                      # standard params
                      use_texticon     => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html         => $config{ow_htmlurl},
                      url_cgi          => $config{ow_cgiurl},
                      iconset          => $prefs{iconset},
                      sessionid        => $thissession,
                      message_id       => $messageid,
                      folder           => $folder,
                      sort             => $sort,
                      page             => $page,
                      (map { $_, $prefs{$_} } grep { m/^iconset_/ } keys %prefs),

                      # sa_edittest.pl
                      prefs_caller     => $prefs_caller,
                      callerfoldername => ($lang_folders{$folder} || f2u($folder)),
                      testloop         => $testloop,
                      whitelist        => $listtype eq 'whitelist' ? 1 : 0,

                      # footer.tmpl
                      footer_template  => get_footer($config{footer_template_file}),
                   );
   httpprint([], [$template->output]);
}

sub modlist {
   my ($mode, $listtype) = @_;
   return edittest() if ($listtype ne 'whitelist' && $listtype ne 'blacklist');

   my $email =  param('email') || '';
   $email    =~ s/^\s*//;
   $email    =~ s/\s*$//;
   return editlist($listtype) if ($email eq '' || $email !~ m/^(?:[a-zA-Z0-9!#\$%&'*+-\/=?^_`.{|}~]{1,64}@)?[%*a-zA-Z0-9.-]{4,255}$/); # rfc3696

   my $saprefsfile = "$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs($saprefsfile);

   my $r_list;
   if ($listtype eq 'whitelist') {
      $r_list = $r_whitelist_from;
   } else {
      $r_list = $r_blacklist_from;
   }

   if ($mode eq 'add') {
      if (!defined ${$r_list}{$email}) {
         ${$r_list}{$email} = 1;
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   } elsif ($mode eq 'delete') {
      if (defined ${$r_list}{$email}) {
         delete ${$r_list}{$email};
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   }

   return editlist($listtype);
}

sub read_saprefs {
   my ($file) = @_;
   my (@lines, @datas, %rules, %whitelist_from, %blacklist_from);

   ow::filelock::lock($file, LOCK_SH);
   if (!sysopen(F, $file, O_RDONLY)) {
      ow::filelock::lock($file, LOCK_UN);
      return(\@datas, \%rules, \%whitelist_from, \%blacklist_from);
   }
   while(<F>) {
      s/\s*$//;
      push(@lines, $_);
   }
   close(F);

   for (my $i = 0; $i <= $#lines; $i++) {
      my $line = $lines[$i];

      # ruleset related lines
      if ($line =~ /^(?:score|describe|tflags|header|uri|body|full|rawbody|meta)\s/) {
         while (defined $lines[$i + 1] && $lines[$i + 1] =~ /^ /) {
            $i++;
            $line .= $lines[$i];
            $line =~ s/\s*$//;
         }

         my ($key, $testname, $value);
         ($key, $testname, $value) = split(/\s+/, $line, 3);

         if ($key eq 'score') {
            $rules{$testname}{score} = [split(/\s+/, $value)];

         } elsif ($key eq 'describe') {
            $rules{$testname}{desc} = $value;

         } elsif ($key eq 'tflags') {
            $rules{$testname}{tflags} = [split(/\s+/, $value)];

         } elsif ($key =~ /^(?:header|uri|body|full|rawbody|meta)$/) {
            $rules{$testname}{type} = $key;

            if ($key eq 'meta') {
               $rules{$testname}{expression} = $value;
            } else {
               my ($headerattr, $op, $pattern);
               if ($key eq 'header') {
                  ($headerattr, $op, $pattern) = split(/\s+/, $value, 3);
                  $rules{$testname}{headerattr} = $headerattr;
                  $rules{$testname}{op} = $op;
               } else {
                  $pattern = $value;
               }
               $rules{$testname}{ifunset}  = $1 if ($pattern =~ s/\s*\[\s*if-unset:\s(.*)\]$//);
               $rules{$testname}{modifier} = $1 if ($pattern =~ s/\/([oigms]+)$/\//);
               $pattern =~ s/^\s*\///;
               $pattern =~ s/\/\s*$//;
               $rules{$testname}{pattern} = $pattern;
            }
         }
      } elsif ($line =~ /^whitelist_from\s/) {
         my @list = split(/\s+/, $line);
         shift @list;
         foreach (@list) { $whitelist_from{$_} = 1 }

      } elsif ($line =~ /^blacklist_from\s/) {
         my @list = split(/\s+/, $line);
         shift @list;
         foreach (@list) { $blacklist_from{$_} = 1 }

      } else {
         push(@datas, $line);
      }
   }

   close(F);
   ow::filelock::lock($file, LOCK_UN);

   return(\@datas, \%rules, \%whitelist_from, \%blacklist_from);
}

sub write_saprefs {
   my ($file, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from)=@_;

   my @p = split(/\//, $file);
   pop @p;
   my $dir = join('/', @p);
   mkdir ($dir, 0700) if (!-d $dir);

   ow::filelock::lock($file, LOCK_EX|LOCK_NB);
   if (!sysopen(F, $file, O_WRONLY|O_TRUNC|O_CREAT)) {
      ow::filelock::lock($file, LOCK_UN);
      return -1;
   }

   my $data = join("\n", @{$r_datas});
   $data =~ s/\n\n+/\n\n/g;
   print F $data;

   my $s;
   my @list = sort (keys %{$r_whitelist_from});
   foreach my $email (@list) {
      if (length($s)+length($email)>60) {
         print F "whitelist_from $s\n";
         $s = '';
      }
      $s .= ' ' if ($s ne '');
      $s .= $email;
   }
   print F "whitelist_from $s\n" if ($s ne '');
   print F "\n";

   $s = '';
   @list = sort (keys %{$r_blacklist_from});
   foreach my $email (@list) {
      if (length($s) + length($email) > 60) {
         print F "blacklist_from $s\n";
         $s = '';
      }
      $s .= ' ' if ($s ne '');
      $s .= $email;
   }
   print F "blacklist_from $s\n" if ($s ne '');
   print F "\n";

   my @testnames = sort { $a cmp $b } keys %{$r_rules};
   foreach my $testname (@testnames) {
      my %test = %{${$r_rules}{$testname}};
      if (defined $test{type}) {
         if ($test{type} eq 'meta') {
            print "meta $testname\t\t$test{expression}\n";
         } else {
            my $pattern = '/' . $test{pattern} . '/';
            $pattern   .= $test{modifier} if (defined $test{modifier});
            $pattern   .= " [if-unset: $test{ifunset}]" if (defined $test{ifunset});
            if ($test{type} eq 'header') {
               print F "header\t\t$testname\t\t$test{headerattr} $test{op} $pattern\n";
            } else {
               print F "$test{type}\t\t$testname\t\t$pattern\n";
            }
         }
      }

      if (defined $test{score}) {
         print F "score\t\t$testname\t\t" . join(' ', @{$test{score}}) . "\n";
      }
      if (defined $test{tflags}) {
         print F "tflags\t\t$testname\t\t" . join(' ', @{$test{tflags}}) . "\n";
      }
      if (defined $test{desc}) {
         print F "describe\t$testname\t\t$test{desc}\n";
      }
      print F "\n";
   }

   close(F);
   ow::filelock::lock($file, LOCK_UN);

   return 0;
}
