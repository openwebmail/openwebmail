#!/usr/bin/perl
# Imports addresses (and groups) from hotmail into openwebmail
# by Niall Walsh <niall@pembrokecricket.com>  
#
# Usage: addrbook_hotmail2owm.pl filename (filename)
#
# Main address file must be called addresses.html
# All other files will be assumed to be groups
# Output is to addresses.owm
# Output is formatted for direct use in /home/$USER/mail/.address.book
#
open(OUT,">addresses.owm")||die "failed to open OUT (addresses.owm): $!";
while($filename=shift){
	open(IN,"$filename")||die "Failed to open IN ($filename): $!";
	if ($filename=~/addresses\.html/){
		my $nick,$email;
		while(<IN>){
			chomp;
			if (s/^.*javascript:DoEdit.+?\>(.+?)\<.*$/$1/){
				$nick=$_;
			} elsif (s/^.*javascript:DoCompose.+?\>(.+?)\<.*$/$1/){
				$email=$_;
				if (!($email=~/\,/)){
					print OUT join("@@@",$nick,$email)."\n";
				}
				$nick='';
				$email='';
			}
		}
	} else {
		my $group,@email,$temp;
		while(<IN>){
			s/\s*$//;
			chomp;
			if (s/^.*name\=\"alias\".+?value=\"(.+?)\".*$/$1/){
				$group=$_;
			} elsif (/name\=\"addrlist\"/){
				$line=$_;
				while($line!~/\<\/textarea\>/){
					$temp=<IN>;
					#neccessary if Windows involved (^M)
					$temp=~s/\s*$//;
					$line="$line "."$temp";
				}
				$temp='';
				$line=~s/\n//g;	
				$line=~s/^.*name\=\"addrlist\".+?\>(.+?)\<.+?$/$1/;
				@email=split(/\s+/,$line);
				print OUT join("@@@",$group,join(',',@email))."\n";
				$group='';
				@email=undef;
			}
		}
	}
	close(IN);
}
close(OUT);
