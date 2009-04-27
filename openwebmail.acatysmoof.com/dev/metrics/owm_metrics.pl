#!/usr/bin/perl -w

# create a summary of OpenWebMail installations by parsing
# the installation notifications received by email.

$|++;
use strict;
use Email::Folder;
use Date::Manip;
use GD::Graph::bars3d;

my $folder = Email::Folder->new("/home/openwebmail_spools/alex/mail/list_owm-stats");

my (%os, %perlversion, %owmversion, %bydate);

my $froms = {}; # keep track of froms to avoid dups

while (my $message = $folder->next_message) {
   # OS: FreeBSD 4.10-RELEASE-p5 i386
   # Perl: 5.008005
   # WebMail: Open WebMail 2.51 20050627

   my $from = $message->header("From");
   $froms->{$from}++;

   if ($froms->{$from} == 1) {
      my $body = $message->body;

      my ($os)          = $body =~ m/OS:\s+?(.*?)[\n\r]+/s;
      my ($perlversion) = $body =~ m/Perl:\s+?(.*?)[\n\r]+/s;
      my ($owmversion)  = $body =~ m/WebMail:\s+?(.*?)[\n\r]+/s;

      if (!defined $os || !defined $perlversion || !defined $owmversion) {
         print "FAILED -------------------\n$body\n\n";
      } else {
         $os{$os}++;
         $perlversion{$perlversion}++;
         $owmversion =~ s/Open ?WebMail/OpenWebMail/i;
         $owmversion{$owmversion}++;

#         print "message:\n";
#         print "$body\n";
#         print "os match: $os\n";
#         print "perlversion match: $perlversion\n";
#         print "owmversion match: $owmversion\n";
#         sleep 10;
      }

      my $received = $message->header('Date');
      my $localreceived = localtime UnixDate($received, "%s");
      my ($year, $month, $day, $hour) = split(" ", UnixDate($localreceived, "%Y %m %d %H"));

      $bydate{"$year$month$day"}++;
   }
}

# process the data into meaningful arrays
my @os_by_popularity = ( map { $_->[0] }
                        sort { $b->[1] <=> $a->[1] }
                         map { [$_, $os{$_}] } keys %os )[0 .. 24];

my @perlversion_popularity =  map { $_->[0] }
                             sort { $b->[1] <=> $a->[1] }
                              map { [$_, $perlversion{$_}] } keys %perlversion;

my @owmversion_popularity =  ( map { $_->[0] }
                              sort { $b->[1] <=> $a->[1] }
                               map { [$_, $owmversion{$_}] } keys %owmversion )[0 .. 24];

# make the graphs
my (@data, $graph) = ();
my $date_now = localtime(time);
# white, lgray, gray, dgray, black, lblue, blue, dblue, gold, lyellow,
# yellow, dyellow, lgreen, green, dgreen, lred, red, dred, lpurple,
# purple, dpurple, lorange, orange, pink, dpink, marine, cyan, lbrown, dbrown.
@data = (
          \@os_by_popularity,                    # x-axis (os names)
          [ map { $os{$_} } @os_by_popularity ]  # y-axis (number of installs)
        );

$graph = new GD::Graph::bars3d( 600, 600 );
$graph->set(
            title   => "OpenWebMail Top 25 Operating Systems",
            x_label => "As of $date_now",
            y_label => 'Number of installs',

            t_margin => 20,
            b_margin => 20,
            l_margin => 20,
            r_margin => 20,
            transparent => 0,
            x_labels_vertical => 1,
            bar_depth => 2,
            show_values => 1,
            values_space => 5,
            values_vertical => 0,
            bgclr   => 'white',
            fgclr   => 'white',
            boxclr   => undef,
            cycle_clrs => 1,
            dclrs => [ qw(dblue blue lblue blue) ],
           );
open(IMG, '>/home/alex/openwebmail.acatysmoof.com/dev/metrics/os.png') or die $!;
binmode IMG;
print IMG $graph->plot(\@data)->png;


@data = (
          \@perlversion_popularity,                             # x-axis (perl versions)
          [ map { $perlversion{$_} } @perlversion_popularity ]  # y-axis (number of installs)
        );

$graph = new GD::Graph::bars3d( 600, 600 );
$graph->set(
            title   => 'OpenWebMail Installs by Perl Version',
            x_label => "As of $date_now",
            y_label => 'Number of installs',

            t_margin => 20,
            b_margin => 20,
            l_margin => 20,
            r_margin => 20,
            transparent => 0,
            x_labels_vertical => 1,
            bar_depth => 2,
            show_values => 1,
            values_space => 5,
            values_vertical => 0,
            bgclr   => 'white',
            fgclr   => 'white',
            boxclr   => undef,
            cycle_clrs => 1,
            dclrs => [ qw(dblue blue lblue blue) ],
           );
open(IMG, '>/home/alex/openwebmail.acatysmoof.com/dev/metrics/perl.png') or die $!;
binmode IMG;
print IMG $graph->plot(\@data)->png;


@data = (
          \@owmversion_popularity,                            # x-axis (owm versions)
          [ map { $owmversion{$_} } @owmversion_popularity ]  # y-axis (number of installs)
        );

$graph = new GD::Graph::bars3d( 600, 600 );
$graph->set(
            title   => 'OpenWebMail Top 25 Installed Versions',
            x_label => "As of $date_now",
            y_label => 'Number of installs',

            t_margin => 20,
            b_margin => 20,
            l_margin => 20,
            r_margin => 20,
            transparent => 0,
            x_labels_vertical => 1,
            bar_depth => 2,
            show_values => 1,
            values_space => 5,
            values_vertical => 0,
            bgclr   => 'white',
            fgclr   => 'white',
            boxclr   => undef,
            cycle_clrs => 1,
            dclrs => [ qw(dblue blue lblue blue) ],
           );
open(IMG, '>/home/alex/openwebmail.acatysmoof.com/dev/metrics/owm.png') or die $!;
binmode IMG;
print IMG $graph->plot(\@data)->png;



@data = (
          [ (reverse sort keys %bydate)[0 .. 24] ],                     # x-axis (install date)
          [ map { $bydate{$_} } (reverse sort keys %bydate)[0 .. 24] ]  # y-axis (number of installs)
        );

$graph = new GD::Graph::bars3d( 600, 600 );
$graph->set(
            title   => 'OpenWebMail Install Activity Last 25 Days',
            x_label => "As of $date_now",
            y_label => 'Number of installs',

            t_margin => 20,
            b_margin => 20,
            l_margin => 20,
            r_margin => 20,
            transparent => 0,
            x_labels_vertical => 1,
            bar_depth => 2,
            show_values => 1,
            values_space => 5,
            values_vertical => 0,
            bgclr   => 'white',
            fgclr   => 'white',
            boxclr   => undef,
            cycle_clrs => 1,
            dclrs => [ qw(dblue blue lblue blue) ],
           );
open(IMG, '>/home/alex/openwebmail.acatysmoof.com/dev/metrics/date.png') or die $!;
binmode IMG;
print IMG $graph->plot(\@data)->png;

