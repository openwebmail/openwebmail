#!/usr/local/bin/perl
use strict;
no strict 'vars';
push (@INC, '/usr/local/www/cgi-bin/neomail', ".");
use Fcntl qw(:DEFAULT :flock);

require "neomail.conf";
require "demime.pl";
require "maildb.pl";

if ( $#ARGV ==1 ) {
  unlink ("$ARGV[0].db", "$ARGV[0].dir", "$ARGV01].pag");
  update_headerdb($ARGV[0], $ARGV[1]);
} else {
  print "makedb [headerdb] [spoolfile]\n";
}
