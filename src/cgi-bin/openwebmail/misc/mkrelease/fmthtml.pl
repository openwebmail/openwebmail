#!/usr/bin/perl
# reformat html for easy reading and make it easier
# to find the difference between different versions of a html
# example: perl path_to_fmthtml.pl `find SOMEDIR -type f -name "*html"`

foreach my $file (@ARGV) {
print "reformat $file...";
$content='';

open(F,$file);
while (<F>) {
   chomp;
   $content.= $_;
}
close(F);

# replacement
$content=~ s|\r||igms;
$content=~ s|\t| |igms;
foreach my $tag ( qw(a p h1 h2 h3 h4 li ul !-- css style script img meta div br table title body head html tr tbody th)) {
   $content=~ s|<$tag|\n<$tag|igms;
   $content=~ s|</$tag>|</$tag>\n|igms;
}
$content=~ s|-->|-->\n|igms;

# remove redundance

$content=~ s|^ *||igms;
$content=~ s| *$||igms;
$content=~ s|> *<|><|igms;
$content=~s|  *| |igms;
$content=~ s|\n *\n|\n\n|igms;
$content=~ s|\n\n+|\n\n|igms;

# final reformat
foreach my $tag ( qw(table)) {
   $content=~ s|<$tag|\n<$tag|igms;
   $content=~ s|</$tag>|</$tag>\n|igms;
}
$content=~ s|/tr>\n\n<tr|/tr>\n<tr|igms;
$content=~ s|<br>\n+|<br>\n|igms;
$content=~ s|\n+<br>|\n<br>|igms;
$content=~ s|^ *||igms;
$content=~ s| *$||igms;
$content=~ s|\n\n+|\n\n|igms;
$content=~ s|^\s||;

open(F, ">$file.tmp") || die "\n$file.tmp open error!\n";
print F $content || die "\n$file.tmp write error!\n";
close(F) || die "\n$file.tmp close error!\n";

rename("$file", "$file.old");
rename("$file.tmp", "$file");
unlink("$file.old");

print "done\n";

}
