#!/usr/bin/perl -w

# This script is intended to be run from a cron job.

# This script converts all of the mbox archives in the openwebmail
# majordomo2 area to browseable, searchable web based archives.
# It uses mhonarc to convert the mbox files to html, and namazu to
# index the html files and provide a search interface.
# I wrote this because majordomo2 already has web based archive
# support, but its not nearly as developed as it needs to be for a
# normal person to use it. Secondly, I wrote this because the only
# other option was using mharc, but it is a lot of code for something
# that is really not that difficult.

$|++;
use strict;
use HTML::Template;

use vars qw($global);

# configuration
$global->{mboxarchiveroot} = "/usr/local/majordomo/lists/openwebmail.acatysmoof.com";
$global->{wwwarchiveroot} = "/home/alex/openwebmail.acatysmoof.com/archive";
$global->{reconvert} = ((defined $ARGV[0] && $ARGV[0] eq "reconvert")?"-add -reconvert":"-add");

# keep track of archive to generate index pages
my $globalindex;

# process
my @dirs = reverse dirlist($global->{mboxarchiveroot}, qr/^owm-/);
for(my $i=0;$i<=$#dirs;$i++) {
   my $index;
   my $dir = $dirs[$i];
   next if ($dir eq "owm-test");

   if (!-e "$global->{wwwarchiveroot}/html/$dir") {
      mkdir "$global->{wwwarchiveroot}/html/$dir" or die("Can't make dir \"$global->{wwwarchiveroot}/html/$dir\"\n");
   }

   my @files = filelist("$global->{mboxarchiveroot}/$dir/files/public/archive", qr/^$dir/);

   for(my $j=0;$j<=$#files;$j++) {
      my $file = $files[$j];
      my $source = "$global->{mboxarchiveroot}/$dir/files/public/archive/$file";
      my $target = "$global->{wwwarchiveroot}/html/$dir/$file"; # a dir named after the file to store the file's contents

      if (!-e "$target") {
         mkdir "$target" or die("Can't make dir $target\n");
      }

      # set some environment variables to pass into mhonarc
      $ENV{'LIST-NAME'} = uc($dir);
      $ENV{'PERIOD-PREV'} = ((($j - 1) > 0) && (exists $files[$j-1]))?$files[$j-1]:'';
      $ENV{'PERIOD-NEXT'} = exists $files[$j+1]?$files[$j+1]:'';

      # create the html archive
      system("/usr/local/bin/mhonarc -rcfile $global->{wwwarchiveroot}/tools/owm.mrc $global->{reconvert} -outdir $target $global->{mboxarchiveroot}/$dir/files/public/archive/$file") == 0 or die("Mhonarc failed: $!\n");
      print "\n\n";

      # keep track for later
      $file =~ m/(.*)\.(\d{4})(\d{2})$/;
      my ($listname, $thisyear, $thismonth) = ($1, $2, $3);
      $index->{$listname}{$thisyear}{$thismonth} = { MONTH => $thismonth, POSTS => scalar filelist($target, qr/msg.*html/), DIR => "/archive/html/$dir/$file" };
   }

   # this dir has been completely processed. Build the index for it.
   my $listdesc = {
                    'owm-announce' => "Announcements of New Releases and important security issues",
                       'owm-devel' => "Feature Requests, Bug Reports, and General Development",
                        'owm-i18n' => "Translators, Localization, and Internationalization",
                       'owm-users' => "Help for Systems Administrators and End Users",
                  };
   my $monthnow = sprintf("%02d", ((localtime(time))[4] + 1));
   my $yearnow = ((localtime(time))[5] + 1900);
   push(@{$index->{LISTS}}, { LISTNAME => $dir,
                              LISTDESC => $listdesc->{$dir},
                               YEARS => [ map {
                                                my $year = $_;
                                                {
                                                  YEAR => $year,
                                                  MONTHS => [ map {
                                                                    my $month = sprintf("%02d", $_);
                                                                    $month = 0 if "$year$month" gt "$yearnow$monthnow";
                                                                    exists $index->{$dir}{$year}{$month}?
                                                                    $index->{$dir}{$year}{$month}:
                                                                    { MONTH => $month, POSTS => 0, DIR => "#" }
                                                                  } (1..12)
                                                            ]
                                                }
                                              } sort keys %{$index->{$dir}}
                                        ]
                            });

   delete $index->{$dir}; # only the LISTS are left

   # load the template
   my $template = HTML::Template->new(filename => "$global->{wwwarchiveroot}/tools/index.tmpl", loop_context_vars => 1, global_vars => 1);
   $template->param(\%{$index});

   # write it
   my $indexfile = "$global->{wwwarchiveroot}/html/$dir/index.htm";
   open(INDEX, ">$indexfile") or die("I can't open index file for writing $indexfile: $!\n");
   print INDEX $template->output;
   close(INDEX);

   # store this list in the global
   push(@{$globalindex->{LISTS}}, $index->{LISTS}[0]);
}


# load the global template
my $template = HTML::Template->new(filename => "$global->{wwwarchiveroot}/tools/index.tmpl", loop_context_vars => 1, global_vars => 1);
$template->param(\%{$globalindex});

# write it
my $globalindexfile = "$global->{wwwarchiveroot}/html/index.htm";
open(INDEX, ">$globalindexfile") or die("I can't open index file for writing $globalindexfile: $!\n");
print INDEX $template->output;
close(INDEX);

my $archivelevelindex = "$global->{wwwarchiveroot}/index.htm";
open(INDEX, ">$archivelevelindex") or die("I can't open index file for writing $archivelevelindex: $!\n");
print INDEX $template->output;
close(INDEX);


sub filelist {
   my ($dir, $exp) = @_;
   return unless -e "$dir";
   $exp = qr/.*/ unless defined $exp;
   opendir(DIR, "$dir") or die("Can't open dir $dir\n");
   my @files = sort grep { !m/^\.{1,2}/ && -f "$dir/$_" && m/$exp/} readdir(DIR);
   closedir(DIR);
   return @files;
}

sub dirlist {
   my ($dir, $exp) = @_;
   return unless -e "$dir";
   $exp = qr/.*/ unless defined $exp;
   opendir(DIR, "$dir") or die("Can't open dir $dir\n");
   my @dirs = sort grep { !m/^\.{1,2}/ && -d "$dir/$_" && m/$exp/} readdir(DIR);
   closedir(DIR);
   return @dirs;
}

