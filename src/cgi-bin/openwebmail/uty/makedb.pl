#!/usr/local/bin/perl
use strict;
no strict 'vars';
push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
use Fcntl qw(:DEFAULT :flock);

require "openwebmail.conf";
require "openwebmail-shared.pl";
require "mime.pl";
require "maildb.pl";

if ( $#ARGV ==1 ) {
  unlink ("$ARGV[0].db", "$ARGV[0].dir", "$ARGV01].pag");
  update_headerdb($ARGV[0], $ARGV[1]);
} else {
  print "makedb [headerdb] [folderfile]\n";
}
