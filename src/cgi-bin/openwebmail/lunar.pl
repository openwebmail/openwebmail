#
# lunar.pl - convert solar calendar to chinese lunar calendar
#
# 2002/11/15 tung.AT.turtle.ee.ncku.edu.tw
#
use strict;
use vars qw(%config);

sub mkdb_lunar {
   my $lunardb="$config{'ow_etcdir'}/lunar$config{'dbmopen_ext'}";
   ($lunardb =~ /^(.+)$/) && ($lunardb = $1);		# untaint ...
   my %LUNAR;
   dbmopen (%LUNAR, $lunardb, 0644) or return -1;
   open (T, "$config{'lunar_map'}");
   $_=<T>; $_=<T>;
   while (<T>) {
      my @a=split(/,/, $_);
      $LUNAR{$a[0]}="$a[1],$a[2]";
   }
   close(T);
   dbmclose(%LUNAR);
   return 0;
}

sub solar2lunar {
   my ($year, $month, $day)=@_;
   my ($lunar_year, $lunar_monthday);

   if ( -f "$config{'ow_etcdir'}/lunar$config{'dbm_ext'}" &&
       !-z "$config{'ow_etcdir'}/lunar$config{'dbm_ext'}" ) {
      my %LUNAR;
      my $date=sprintf("%04d%02d%02d", $year, $month, $day);
      dbmopen(%LUNAR, "$config{'ow_etcdir'}/lunar$config{'dbmopen_ext'}", undef);
      ($lunar_year, $lunar_monthday)=split(/,/, $LUNAR{$date});
      dbmclose(%LUNAR);
   }
   return($lunar_year, $lunar_monthday);
}

1;
