#!/usr/bin/perl
#
# script to convert chinese big5 to gb2312
#
my (%config, $content);
$config{'ow_mapsdir'}="/usr/local/www/cgi-bin/openwebmail/etc/maps";
$config{'dbm_ext'}=".db";
$config{'dbmopen_ext'}="";

while (<>) {
   $content.=$_;
}
print b2g($content);

# generic routines ##################################################################
sub b2g {
   my $str = $_[0];

   if ( -f "$config{'ow_mapsdir'}/b2g$config{'dbm_ext'}") {
      my %B2G;
      dbmopen (%B2G, "$config{'ow_mapsdir'}/b2g$config{'dbmopen_ext'}", undef);
      $str =~ s/([\x81-\xFE][\x40-\x7E\xA1-\xFE])/$B2G{$1}/eg;
      dbmclose(%B2G);
   }
   return $str;
}
