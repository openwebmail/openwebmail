#
# lunar.pl - convert solar calendar to chinese lunar calendar
#
# 2002/11/15 tung.AT.turtle.ee.ncku.edu.tw
#

use strict;
use vars qw(%config);
use Fcntl qw(:DEFAULT :flock);

sub mkdb_lunar {
   my %LUNAR;
   my $lunardb=ow::tool::untaint("$config{'ow_mapsdir'}/lunar");

   ow::dbm::open(\%LUNAR, $lunardb, LOCK_EX, 0644) or return -1;
   sysopen(T, $config{'lunar_map'}, O_RDONLY);
   $_=<T>; $_=<T>;
   while (<T>) {
      s/\s//g;
      my @a=split(/,/, $_, 2);
      $LUNAR{$a[0]}=$a[1];
   }
   close(T);
   ow::dbm::close(\%LUNAR, $lunardb);

   return 0;
}

sub solar2lunar {
   my ($year, $mon, $day)=@_;
   my ($lyear, $lmon, $lday);

   my $lunardb=ow::tool::untaint("$config{'ow_mapsdir'}/lunar");
   if (ow::dbm::exist($lunardb)) {
      my %LUNAR;
      my $date=sprintf("%04d%02d%02d", $year, $mon, $day);
      ow::dbm::open(\%LUNAR, $lunardb, LOCK_SH);
      ($lyear, $lmon, $lday)=split(/,/, $LUNAR{$date});
      ow::dbm::close(\%LUNAR, $lunardb);
   }

   return($lyear, $lmon, $lday);
}

sub lunar2big5str {
   my ($lmon, $lday)=@_;
   return ($lmon.$lday) if ($lmon!~/\d/ || $lday!~/\d/);

   my @lmonstr=('', '正月', '二月', '三月', '四月', '五月', '六月',
                    '七月', '八月', '九月', '十月', '葭月', '臘月');
   my @ldaystr=('', '初一', '初二', '初三', '初四', '初五',
                    '初六', '初七', '初八', '初九', '初十',
                    '十一', '十二', '十三', '十四', '十五',
                    '十六', '十七', '十八', '十九', '二十',
                    '廿一', '廿二', '廿三', '廿四', '廿五',
                    '廿六', '廿七', '廿八', '廿九', '三十');

   if ($lmon=~/^\+(\d+)/) {
      return "閏".$lmonstr[$1].$ldaystr[$lday];
   } else {
      return $lmonstr[$lmon].$ldaystr[$lday];
   }
}

1;
