#
# datetime.pl - date/time routines supporting timezone and daylightsaving
#
# This module uses gmtime(), timegm() to convert time between date array and seconds
# It uses time_gm2local(), time_local2gm() with parameter $timeoffset, $daylightsaving
# to convert time between gm seconds and local seconds,
# so it can handle multiple timezones other than where the server is.
#

package ow::datetime;

use strict;
use warnings FATAL => 'all';

use Time::Local;
use Fcntl qw(O_RDONLY);
use POSIX qw(tzset);

use vars qw(%months @month_en @wday_en %tzoffset);

%months   = (
               Jan => 1,
               Feb => 2,
               Mar => 3,
               Apr => 4,
               May => 5,
               Jun => 6,
               Jul => 7,
               Aug => 8,
               Sep => 9,
               Oct => 10,
               Nov => 11,
               Dec => 12,
            );

@month_en = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

@wday_en  = qw(Sun Mon Tue Wed Thu Fri Sat);

%tzoffset = qw(
                 ACDT +1030  ACST +0930  ADT  -0300  AEDT +1100  AEST +1000
                 AHDT -0900  AHST -1000  AKDT -0800  AKST -0900  AST  -0400
                 AT   -0200  AWDT +0900  AWST +0800  AZST +0400  BAT  +0300
                 BDST +0200  BET  -1100  BRST -0200  BRT  -0300  BST  -0300
                 BT   +0300  BZT2 -0300  CADT +1030  CAST +0930  CAT  -1000
                 CCT  +0800  CDT  -0500  CED  +0200  CEST +0200  CET  +0100
                 CST  -0600  EAST +1000  EDT  -0400  EED  +0300  EEST +0300
                 EET  +0200  EST  -0500  FST  +0200  FWT  +0100  GMT  +0000
                 GST  +1000  HADT -0900  HAST -1000  HDT  -0900  HKT  +0800
                 HST  -1000  IDLE +1200  IDLW -1200  IDT  +0300  IST  +0530
                 IT   +0330  JST  +0900  JT   +0700  KST  +0900  MDT  -0600
                 MED  +0200  MEST +0200  MESZ +0200  MET  +0100  MEWT +0100
                 MEZ  +0100  MSD  +0400  MSK  +0300  MST  -0700  MT   +0800
                 NDT  -0230  NFT  -0330  NST  +0630  NT   -1100  NZ   +1100
                 NZDT +1300  NZST +1200  NZT  +1200  PDT  -0700  PHT  +0800
                 PST  -0800  ROK  +0900  SAD  +1000  SAST +0900  SAT  +0900
                 SDT  +1000  SGT  +0800  SST  +0200  SWT  +0100  USZ3 +0400
                 USZ4 +0500  USZ5 +0600  USZ6 +0700  UT   +0000  UTC  +0000
                 UZ10 +1100  WAT  -0100  WEST +0100  WET  +0000  WST  +0800
                 YDT  -0800  YST  -0900  ZP4  +0400  ZP5  +0500  ZP6  +0600
              );

sub gettimeoffset {
   # notice the difference between localtime and gmtime includes the dst shift, so we remove
   # the dstshift before returning the timeoffset since whether dst shift should be used
   # depends on the date to be converted
   my $timenow   = time();                              # the UTC sec from 1970/01/01
   my @localized = localtime($timenow);                 # (sec,min,hour,mday,mon,year,wday,yday,isdst)
   my $seconds   = timegm(@localized[0..5]) - $timenow; # diff between local and UTC (timegm from Time::Local)

   my $is_dst = $localized[8];
   $seconds -= 3600 if $is_dst;

   return sprintf(seconds2timeoffset($seconds));
}

sub timeoffset2seconds {
   my $timeoffset = shift || '';

   my $seconds = 0;

   if ($timeoffset =~ m/^[+-]?(\d\d)(\d\d)$/) {
      $seconds = ($1 * 60 + $2) * 60;
      $seconds *= -1 if $timeoffset =~ m/^-/;
   }

   return $seconds;
}

sub seconds2timeoffset {
   my $seconds = shift;
   my $abs_seconds = abs $seconds;
   return sprintf('%s%02d%02d', ($seconds >= 0 ? '+' : '-'), int($abs_seconds / 3600), int(($abs_seconds % 3600) / 60));
}

sub seconds2array {
   # given seconds since the epoch, return an array
   # ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) at GMT
   my $seconds_since_epoch = shift;
   return gmtime($seconds_since_epoch);
}

sub array2seconds {
   # given a datetime, return the number of seconds to
   # that datetime since the system epoch in GMT
   my ($sec, $min, $hour, $d, $m, $y) = @_;

   # replace any invalid inputs with the "now" values for that input field
   # in order to avoid unexpected error exceptions from the timegm routine
   my @t = gmtime();
   $sec  = $t[0] if !defined $sec  || $sec < 0  || $sec > 59;
   $min  = $t[1] if !defined $min  || $min < 0  || $min > 59;
   $hour = $t[2] if !defined $hour || $hour < 0 || $hour > 23;
   $d    = $t[3] if !defined $d    || $d < 1    || $d > 31;
   $m    = $t[4] if !defined $m    || $m < 0    || $m > 11;
   $y    = $t[5] if !defined $y    || $y < 70   || $y > 137; # invalid if outside 1970...2037

   if ($d > 28) {
      my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
      my $year = 1900 + $y;
      $days_in_month[2]++ if $year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0);
      $d = $days_in_month[$m + 1] if $d > $days_in_month[$m + 1];
   }

   return timegm($sec, $min, $hour, $d, $m, $y); # Time::Local module
}

sub makezonelist {
   # Creates the zonelist from the zoneinfo data
   my $zonetab = shift;

   if ($zonetab ne 'no' && sysopen(ZONETAB, $zonetab, O_RDONLY)) {
      my @zones = ();
      while (<ZONETAB>) {
         next if (/^#/);
         push(@zones, $1) if (/^\w\w\s\S+\s(\S+)/);
      }
      close(ZONETAB);

      # calculate the offset for each zone
      foreach (@zones) {
         $ENV{TZ} = ":$_";
         POSIX::tzset();
         my $t = time();                  # the UTC sec from 1970/01/01
         my @l = localtime($t);
         my $sec = timegm(@l[0..5]) - $t; # diff between local and UTC
         $sec -= 3600 if ($l[8]);         # is dst? (returned by localtime)
         my $offset = sprintf(seconds2timeoffset($sec));
         $_ = "$offset $_";
      }
      return @zones;
   } else {
      return ();
   }
}

sub is_dst {
   # Check if gmtime should be DST for timezone $timeoffset.
   # Since we use only 2 rules to calc daylight saving time for all timezones,
   # it is not very accurate but should be enough in most cases
   # reference: http://webexhibits.org/daylightsaving/g.html
   # If a timezone is provided, use this timezone data to define is_dst.
   # $gmtime is any time given in seconds from epoch
   my ($gmtime, $timeoffset, $timezone) = @_;

   if (defined $timezone && $timezone) {
      $ENV{TZ} = ":$timezone";
      POSIX::tzset();
      my $is_dst = (localtime($gmtime))[8];
      return $is_dst;
   } else {
      my ($month, $year) = (seconds2array($gmtime))[4,5]; # $month 0..11
      my $seconds = timeoffset2seconds($timeoffset);

      if (($seconds >= -9 * 3600) && ($seconds <= -3 * 3600)) {
         # very basic dst rule summary for the US
         # U.S. and Canada beginning in 2007:
         # Start: Second Sunday in March
         # End: First Sunday in November
         return 1 if $month >= 3 && $month <= 9;                         # April(3) through October(9)
         if ($month == 2) {
             my $startdstgmt         = array2seconds(0, 0, 2, 7, 2, $year);   # Mar/7 2:00am GMT ($sec, $min, $hour, $d, $m, $y)
             my $startdstgmtdow      = (seconds2array($startdstgmt))[6]; # weekday of Mar/7 GMT
             my $days_to_next_sunday = 7 - $startdstgmtdow;              # next Sunday after Mar/7 will always be the 2nd Sunday
             my $startdst            = $startdstgmt + $days_to_next_sunday * 86400 - $seconds;
             return 1 if $gmtime >= $startdst;
         } elsif ($month == 10) {
             my $enddstgmt           = array2seconds(0, 0, 2, 1, 10, $year);  # Nov/1 2:00am GMT ($sec, $min, $hour, $d, $m, $y)
             my $enddstgmtdow        = (seconds2array($enddstgmt))[6];   # weekday of Nov/1 GMT
             my $days_to_next_sunday = 7 - $enddstgmtdow;                # the first Sunday of Nov
             my $enddst              = $enddstgmt - ($days_to_next_sunday < 7 ? $days_to_next_sunday : 0) * 86400 - $seconds;
            return 1 if $gmtime <= $enddst;
         }
      } elsif ($seconds >= 0 && $seconds <= 6 * 3600 ) {
         # very basic dst rule summary for europe
         # Start: Last Sunday in March at 1 am UTC
         # End: Last Sunday in October at 1 am UTC
         return 1 if $month >= 3 && $month <= 8;                               # April(3) through September(8)
         if ($month == 2) {
            my $startdstgmt                = array2seconds(0, 0, 1, 31, 2, $year);  # Mar/31 1:00am GMT ($sec, $min, $hour, $d, $m, $y)
            my $startdstgmtdow             = (seconds2array($startdstgmt))[6]; # weekday of Mar/31 GMT
            my $seconds_to_previous_sunday = $startdstgmtdow * 86400;
            my $startdst                   = $startdstgmt - $seconds_to_previous_sunday;
            return 1 if $gmtime >= $startdst;
         } elsif ($month == 9) {
            my $enddstgmt                  =  array2seconds(0, 0, 1, 31, 9, $year); # Oct/31 1:00am GMT ($sec, $min, $hour, $d, $m, $y)
            my $enddstgmtdow               = (seconds2array($enddstgmt))[6];   # weekday of Oct/31 GMT
            my $seconds_to_previous_sunday = $enddstgmtdow * 86400;
            my $enddst                     = $enddstgmt - $seconds_to_previous_sunday;
            return 1 if $gmtime <= $enddst;
         }
      }

      return 0;
   }
}

sub time_gm2local {
   my ($g2l, $timeoffset, $daylightsaving, $timezone) = @_;

   # add a DST adjustment if this GMT falls in DST at our timeoffset or timezone
   $g2l += 3600 if $daylightsaving eq 'on' || ($daylightsaving eq 'auto' && is_dst($g2l, $timeoffset, $timezone));

   # add the offset from GMT to get us to our localtime
   $g2l += timeoffset2seconds($timeoffset) if $timeoffset;

   return $g2l;
}

sub time_local2gm {
   # given a time in seconds ($l2g), adjust that time to compensate for the timeoffset
   # from GMT in seconds and any daylight savings adjustments as well
   my ($l2g, $timeoffset, $daylightsaving, $timezone) = @_;

   $daylightsaving = '' unless defined $daylightsaving;
   $timezone       = '' unless defined $timezone;

   # remove the offset from GMT to get us back to GMT
   $l2g -= timeoffset2seconds($timeoffset);

   # remove a DST adjustment if this GMT falls in DST at our timeoffset or timezone
   $l2g -= 3600 if $daylightsaving eq 'on' || ($daylightsaving eq 'auto' && is_dst($l2g, $timeoffset, $timezone));

   return $l2g;
}

sub gmtime2dateserial {
   # dateserial is used as an equivalent internal format to gmtime
   # the is_dst effect will not be not counted in dateserial until
   # the dateserial is converted to datefield, delimeterfield or string
   # a serialized date looks like: 20090727074535
   my $time = shift || time();
   my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = seconds2array($time);
   return sprintf('%4d%02d%02d%02d%02d%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
}

sub dateserial2gmtime {
   # convert a serialize date like 20090727074535 back to a gmtime object
   my $serial = shift || '';
   my ($year, $mon, $mday, $hour, $min, $sec) = $serial =~ m/(\d{4})(\d\d)(\d\d)(\d\d)?(\d\d)?(\d\d)?/;
   return array2seconds(
                          (defined $sec  ? $sec         : -1),
                          (defined $min  ? $min         : -1),
                          (defined $hour ? $hour        : -1),
                          (defined $mday ? $mday        : -1),
                          (defined $mon  ? $mon - 1     : -1),
                          (defined $year ? $year - 1900 : -1)
                       );
}

sub delimiter2dateserial {
   # return dateserial of GMT
   my ($delimiter, $deliver_use_gmt, $daylightsaving, $timezone) = @_;

   # extract date from the 'From ' line, it must be in this form
   # From Tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
   # From Tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
   # From Nssb@thumper.bellcore.com Wed Mar 11 16:27:37 EST 1992
   return '' if $delimiter !~ m/(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+([A-Z]{3,4}\d?\s+)?(\d+)/;

   my ($wdaystr, $monstr, $mday, $hour, $min, $sec, $zone, $year) = ($1, $2, $3, $4, $5, $6, $7, $8);

   if ($year < 50) {
      $year += 2000; # 2 digit year
   } elsif ($year <= 1900) {
      $year += 1900;
   }

   my $mon = $months{$monstr};

   my $deliverytime = array2seconds($sec, $min, $hour, $mday, $mon - 1, $year - 1900);

   # we do not trust the zone abbreviation in delimiter line because it is not unique.
   # see http://www.worldtimezone.com/wtz-names/timezonenames.html for detail
   # since delimiter is written by local deliver we use gettimeoffset() instead
   $deliverytime = time_local2gm($deliverytime, gettimeoffset(), $daylightsaving, $timezone) unless $deliver_use_gmt;

   return gmtime2dateserial($deliverytime);
}

sub dateserial2delimiter {
   my ($dateserial, $timeoffset, $daylightsaving, $timezone) = @_;

   my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
      seconds2array(time_gm2local(dateserial2gmtime($dateserial), $timeoffset, $daylightsaving, $timezone));

   # From Tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
   return sprintf("%3s %3s %2d %02d:%02d:%02d %4d", $wday_en[$wday], $month_en[$mon], $mday, $hour, $min, $sec, $year + 1900);
}

sub datefield2dateserial {
   # given a datefield (Mon Aug 20 18:24 CST 2010) return a dateserial (20100820182400) in the GMT timezone
   my $datefield = shift;
   $datefield =~ s/GMT//;

   # defaults
   my ($gmsec,$gmmin,$gmhour,$gmmday,$gmmon,$gmyear,$gmwday,$gmyday,$gmisdst) = gmtime(time);
   my $sec        = '00';
   my $min        = '00';
   my $hour       = '02';
   my $mday       = '';
   my $mon        = '1';
   my $year       = $gmyear + 1900;
   my $timeoffset = '-0000';
   my $timezone   = 'GMT';
   my $ampm       = 'am';

   # figure out the values for this datefield string
   foreach my $string (split(/[\s,]+/, $datefield)) {
      if ($string =~ m/^\d\d?$/) {
         if ($string <= 31 && $mday eq '') {
            $mday = $string;
         } else {
            $year = $string + 1900;
            $year += 100 if $year < 1970;
         }
      } elsif ($string =~ m/^(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/i) {
         foreach my $i (0..11) {
            if ($string =~ m/^$month_en[$i]/i) {
               $mon = $i + 1;
               last;
            }
         }
      } elsif ($string =~ m/^\d{4}$/) {
         $year = $string;
      } elsif ($string =~ m/^(\d+):(\d+):?(\d+)?$/) {
         $hour = $1;
         $min  = $2;
         $sec  = defined $3 ? $3 : "00";
      } elsif ($string =~ m/^\(?([A-Z]{3,4}\d?)\)?$/) {
         $timezone = $1;
      } elsif ($string =~ m/^([\+\-]\d\d:?\d\d)$/) {
         $timeoffset = $1;
         $timeoffset =~ s/://;
      } elsif ($string =~ /^pm$/i) {
         $ampm = 'pm';
      }
   }

   $mday = '01' if $mday eq '';

   $hour += 12 if $hour < 12 && $ampm eq 'pm';
   $timeoffset = $tzoffset{$timezone} if $timeoffset eq '';

   my $seconds_since_epoch_GMT = array2seconds($sec, $min, $hour, $mday, $mon - 1, $year - 1900);

   # IMPORTANT:
   # The date field in a message header is generated by another machine
   # Both datetime and the timezone string in the date field already include the
   # daylight savings time shift so we do not do a daylight saving time adjustment here
   # 0 for daylightsavings adjustment, 0 for timezone

   # apply the timeoffset in seconds from GMT to get
   # us to the true seconds since the epoch in GMT
   my $true_seconds_since_epoch_GMT = time_local2gm($seconds_since_epoch_GMT, $timeoffset, 0, 0);

   return gmtime2dateserial($true_seconds_since_epoch_GMT);
}

sub dateserial2datefield {
   my ($dateserial, $timeoffset, $daylightsaving, $timezone) = @_;

   # both datetime and the timezone string in date field include the dst shift
   # so we calculate datetime, timeoffset_with_dst through timegm and timelocal
   my $timegm    = dateserial2gmtime($dateserial);
   my $timelocal = time_gm2local($timegm, $timeoffset, $daylightsaving, $timezone);
   my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = seconds2array($timelocal);

   my $timeoffset_with_dst = seconds2timeoffset($timelocal-$timegm);

   # Wed, 9 Sep 1998 19:30:17 +0800 (CST)
   return sprintf(
                   '%3s, %d %3s %4d %02d:%02d:%02d %s',
                   $wday_en[$wday], $mday, $month_en[$mon], $year+1900, $hour, $min, $sec, $timeoffset_with_dst
                 );
}

sub dateserial2str {
   my ($dateserial, $timeoffset, $daylightsaving, $format, $hourformat, $timezone) = @_;

   my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
      seconds2array(time_gm2local(dateserial2gmtime($dateserial), $timeoffset, $daylightsaving, $timezone));
   $year += 1900;
   $mon++;

   my $str = $format eq "mm/dd/yyyy" ? sprintf("%02d/%02d/%04d", $mon, $mday, $year) :
             $format eq "dd/mm/yyyy" ? sprintf("%02d/%02d/%04d", $mday, $mon, $year) :
             $format eq "yyyy/mm/dd" ? sprintf("%04d/%02d/%02d", $year, $mon, $mday) :
             $format eq "mm-dd-yyyy" ? sprintf("%02d-%02d-%04d", $mon, $mday, $year) :
             $format eq "dd-mm-yyyy" ? sprintf("%02d-%02d-%04d", $mday, $mon, $year) :
             $format eq "yyyy-mm-dd" ? sprintf("%04d-%02d-%02d", $year, $mon, $mday) :
             $format eq "mm.dd.yyyy" ? sprintf("%02d.%02d.%04d", $mon, $mday, $year) :
             $format eq "dd.mm.yyyy" ? sprintf("%02d.%02d.%04d", $mday, $mon, $year) :
             $format eq "yyyy.mm.dd" ? sprintf("%04d.%02d.%02d", $year, $mon, $mday) :
             sprintf("%02d/%02d/%04d", $mon, $mday, $year);

   if ($hourformat eq "12") {
      my ($h, $ampm) = hour24to12($hour);
      $str .= sprintf(" %02d:%02d:%02d $ampm", $h, $min, $sec);
   } else {
      $str .= sprintf(" %02d:%02d:%02d", $hour, $min, $sec);
   }

   return($str);
}

sub hour24to12 {
   my $hour = shift;
   my $ampm = "am";

   $hour =~ s/^0(.+)/$1/;
   if ($hour==24||$hour==0) {
      $hour = 12;
   } elsif ($hour > 12) {
      $hour = $hour - 12;
      $ampm = "pm";
   } elsif ($hour == 12) {
      $ampm = "pm";
   }
   return($hour, $ampm);
}
########## END HOUR24TO12 ########################################

sub days_in_month {
   # return the total number of days for a given month in a given year
   my ($year, $month) = @_;
   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++ if ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0));
   return $days_in_month[$month];
}

sub day_of_year {
   # return the number of a given day this year from 0 to 366
   my ($year, $month, $day) = @_;
   my $day_of_year = 0;
   foreach my $month_this_year (1..$month) {
      my $days_in_month = days_in_month($year, $month_this_year);
      $day_of_year += $days_in_month;
      $day_of_year -= $days_in_month - $day if $month_this_year == $month && $day < $days_in_month;
   }
   return $day_of_year;
}

sub days_in_year {
   # return the number of days in the given year
   my $year = shift;
   return ($year % 400 || $year % 100 || $year %4) ? 365 : 366;
}

sub week_of_year {
   # return the week number this year for the provided date. This follows
   # ISO 8601 provided the $weekstart is 1 (where 0 => Sunday, 1 => Monday, etc.)
   my ($year, $month, $day, $weekstart) = @_;

   my $day_of_year = day_of_year($year, $month, $day);

   my $weekday_number = (weekday_number($year, $month, $day) + 7 - $weekstart) % 7;

   my $day_of_nearest_thursday = $day_of_year - $weekday_number + 2;

   $day_of_nearest_thursday += days_in_year($year-1) if $day_of_nearest_thursday < 0;
   $day_of_nearest_thursday -= days_in_year($year) if $day_of_nearest_thursday > days_in_year($year);

   return (int($day_of_nearest_thursday / 7) + 1);
}

sub weekday_number {
   # return the weekday number for the given year, month, day
   my ($year, $month, $day) = @_;

   my $time           = ow::datetime::array2seconds(1, 1, 1, $day, $month - 1, $year - 1900);
   my $weekday_number = (ow::datetime::seconds2array($time))[6]; # 0 => Sunday, etc

   return $weekday_number;
}

sub yyyymmdd {
   # return the provided date formatted as a yyyymmdd string
   my ($year, $month, $day) = @_;

   my $date = sprintf("%04d%02d%02d", $year, $month, $day);

   my $dayofweek = $ow::datetime::wday_en[weekday_number($year, $month, $day)]; # Mon, Tues, etc
   my $date2     = sprintf("%04d,%02d,%02d,%s", $year, $month, $day, $dayofweek);

   return($date, $date2);
}


########## EASTER_MATCH ##########################################
# Allow use of expression 'easter +- offset' for month and day field in $idate
# Example: Mardi Gras is ".*,easter,easter-47,.*"
# Written by James Dugal, jpd@louisiana.edu, Sept. 2002
use vars qw(%_gregoria_cache %_orthodox_cache);
sub easter_match {
   my ($year, $month, $day, $idate) = @_;
   my @fields = split(/,/, $idate);
   return 0 unless ($year =~ /$fields[0]/);  # year matches?

   if ($idate =~ /easter/i) {
      $_gregoria_cache{$year}=[gregorian_easter($year)] if (!defined $_gregoria_cache{$year});
      $fields[1] =~ s/easter/${$_gregoria_cache{$year}}[0]/i;	# month
      $fields[2] =~ s/easter/${$_gregoria_cache{$year}}[1]/i;	# day
   } elsif ($idate =~ /orthodox/i) {
      $_orthodox_cache{$year}=[orthodox_easter($year)] if (!defined $_orthodox_cache{$year});
      $fields[1] =~ s/orthodox/${$_orthodox_cache{$year}}[0]/i;	# month
      $fields[2] =~ s/orthodox/${$_orthodox_cache{$year}}[1]/i;	# day
   } else {
      return 0;
   }

   if ($fields[1] =~ /^([\d+-]+)$/) {  #untaint
      local $1; 		# fix perl $1 taintness propagation bug
      $fields[1] = eval($1);	# allow simple arithmetic: easter-7  1+easter
   } else {
      return 0;  # bad syntax, only 0-9 + -  chars allowed
   }
   if ($fields[2] =~ /^([\d+-]+)$/) {  #untaint
      local $1; 		# fix perl $1 taintness propagation bug
      $fields[2] = eval($1);	# allow simple arithmetic: easter-7  1+easter
   } else {
      return 0;  # bad syntax, only 0-9 + -  chars allowed
   }
   # days_in_month ought to be pre-computed just once per $year, externally!
   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   if ( ($year%4)==0 && ( ($year%100)!=0 || ($year%400)==0 ) ) {
      $days_in_month[2]++;
   }
   if ($fields[1] > 0) { # same year, so proceed
      while($fields[2] > $days_in_month[$fields[1]]) {
         $fields[2] -= $days_in_month[$fields[1]];
         $fields[1]++;
      }
      while($fields[2] < 1) {
         $fields[1]--;
         $fields[2] += $days_in_month[$fields[1]];
      }
      return 1 if ($month == $fields[1] && $day == $fields[2]);
   }
   return 0;
}
########## END EASTER_MATCH ######################################

########## GREGORIAN_EASTER ######################################
# ($month, $day) = gregorian_easter($year);
# This subroutine returns the month and day of Easter in the given year,
# in the Gregorian calendar, which is what most of the world uses.
# Adapted from Rich Bowen's Date::Easter module ver 1.14
sub gregorian_easter {
   my $year = $_[0];
   my ( $G, $C, $H, $I, $J, $L, $month, $day, );
   $G = $year % 19;
   $C = int( $year / 100 );
   $H = ( $C - int( $C / 4 ) - int( ( 8 * $C ) / 25 ) + 19 * $G + 15 ) % 30;
   $I = $H - int( $H / 28 ) *
     ( 1 - int( $H / 28 ) * int( 29 / ( $H + 1 ) ) * int( ( 21 - $G ) / 11 ) );
   $J    = ( $year + int( $year / 4 ) + $I + 2 - $C + int( $C / 4 ) ) % 7;
   $L    = $I - $J;
   $month = 3 + int( ( $L + 40 ) / 44 );
   $day   = $L + 28 - ( 31 * int( $month / 4 ) );
   return ( $month, $day );
}
########## END GREGORIAN_EASTER ##################################

########## ORTHODOX_EASTER #######################################
# ($month, $day) = orthodox_easter($year);
# This subroutine returns the month and day of the Orthodox Easter
# in the given year, as celebrated in Greece and other Balcan
# countries, which is also related to Russian Orthodox easter.
# Written by Dimitrios Michelinakis, dimitris@michelinakis.gr, Jun. 2004
sub orthodox_easter {
   my $year = $_[0];
   my ($month);
   my $r1 = $year % 4;
   my $r2 = $year % 7;
   my $r3 = $year % 19;
   my $r4 = (19 * $r3 + 15) % 30;
   my $r5 = (2 * $r1 + 4 * $r2 + 6 * $r4 + 6) % 7;
   my $day = $r5 + $r4 + 13;
   if ($day > 39) {
      $day -= 39;
      $month = 5;
   } elsif ($day >9) {
      $day -= 9;
      $month = 4;
   } else {
      $day +=22;
      $month = 3;
   }
   return ( $month, $day );
}
########## END ORTHODOX_EASTER ###################################

1;
