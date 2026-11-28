#!/usr/bin/perl
# EA SPORTS FC 27's latest squads, as EA pushes them to the game online, put where the game loads
# saved squads from.
#
#   fc27-squads.pl <prefix>            add the newest squad file if the prefix lacks it
#   fc27-squads.pl <prefix> --check    say what EA has and whether the prefix has it
#
# <prefix> is the folder holding drive_c. fc27-le-play.sh runs this at each Play, in the
# background, so the game is never held up by it.
#
# EA publishes the squads for each platform on its content server: rosterupdate.xml names the
# newest file, a compressed database. No account and no game are needed to read them. It is
# unpacked and wrapped in the header of a saved squad file, and written to
# AppData/Local/EA SPORTS FC 27/settings as Squads<date>000000, so the game lists it under
# Customise > Squads > Load Squads as EA_Squads<date>000000. A file already there is never
# replaced, and nothing is written when EA has nothing new. Faces are not in it: a new face
# comes with a game update.
#
# The unpacker and the saved file's layout are xAranaktu's, from FIFASquadFileDownloader (MIT),
# https://github.com/xAranaktu/FIFASquadFileDownloader; this writes the same bytes as its
# main.py for the same download (checked on 2026-11-28 with squads 1199). Perl and curl, which
# every Mac has: macOS's python3 asks to install the developer tools where they are not.
#
# MGF_FC27_SQUADS_URL replaces EA's server (a file:// folder in the tests).
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
use strict;
use warnings;

my $SERVER = $ENV{MGF_FC27_SQUADS_URL}
  || 'https://eafc27.content.easports.com/fc/fltOnlineAssets/27A3C9F1-6B2E-4D7A-8C1F-2E9B5A4D6C7E/2027/';
$SERVER .= '/' unless $SERVER =~ m{/$};
my $SETTINGS = 'drive_c/users/steamuser/AppData/Local/EA SPORTS FC 27/settings';
my $PLATFORM = 'pc64';

my ($pfx, $mode) = @ARGV;
$mode //= '';
die "usage: fc27-squads.pl <prefix> [--check]\n" unless defined $pfx && ($mode eq '' || $mode eq '--check');
$pfx =~ s{/+$}{};
my $dir = "$pfx/$SETTINGS";
-d $dir or die "no $SETTINGS in $pfx: start the game once\n";

sub fetch {
    my ($url, $max) = @_;
    open(my $c, '-|', '/usr/bin/curl', '-fsSL', '--max-time', $max, $url) or die "curl: $!\n";
    binmode $c;
    local $/;
    my $data = <$c>;
    close $c or die "could not download $url\n";
    return $data // '';
}

my $xml = fetch($SERVER . 'fc/fclive/genxtitle/rosterupdate.xml', 20);
$xml =~ m{<squadInfo platform="\Q$PLATFORM\E">(.*?)</squadInfo>}s or die "EA's rosterupdate.xml has no $PLATFORM entry\n";
my $info = $1;
my ($ver) = $info =~ m{<dbMajor>(\d+)</dbMajor>};
my ($loc) = $info =~ m{<dbMajorLoc>([^<]+)</dbMajorLoc>};
defined $ver && defined $loc or die "EA's $PLATFORM entry names no squad file\n";
my ($date) = $loc =~ m{/squads_(\d{8})_[^/]*$} or die "unexpected squad file name: $loc\n";
my $name = "Squads${date}000000";
my $dest = "$dir/$name";
print "EA has squads version $ver of $date: $name\n";
if (-e $dest) { print "the prefix has it\n"; exit 0; }
if ($mode eq '--check') { print "the prefix does not have it yet\n"; exit 0; }

my $packed = fetch($SERVER . $loc, 180);
my $db = unpack_db($packed);
my $file = saved_file($db, $name);
open(my $o, '>:raw', "$dest.part") or die "cannot write $dest.part: $!\n";
print $o $file;
close $o or die "cannot write $dest.part: $!\n";
rename("$dest.part", $dest) or die "cannot name $dest: $!\n";
printf "wrote %s (%d bytes): in the game, Customise > Squads > Load Squads, EA_%s\n", $dest, length($file), $name;

# EA's compressed database to the plain one (xAranaktu's unpacker).
sub unpack_db {
    my ($in) = @_;
    my $size = unpack('N', "\0" . substr($in, 2, 3));
    my $out = "DB\x00\x08";
    my ($ip, $len, $last) = (10, length($in), 0);
    my $copy = sub {
        my ($off, $n) = @_;
        my $src = length($out) - $off;
        die "a copy reaches before the start\n" if $src < 0;
        while ($n > 0) {   # an overlapping copy repeats what it has just written
            my $k = $n < $off ? $n : $off;
            $out .= substr($out, $src, $k);
            $src += $k; $n -= $k;
        }
    };
    my $lit = sub { my ($n) = @_; $out .= substr($in, $ip, $n); $ip += $n; };
    while ($ip < $len && length($out) < $size) {
        my $c = ord(substr($in, $ip++, 1));
        $last = $c;
        if (!($c & 0x80)) {
            my $b1 = ord(substr($in, $ip++, 1));
            $lit->($c & 3);
            $copy->($b1 + (($c & 0x60) << 3) + 1, (($c >> 2) & 7) + 3);
        } elsif (!($c & 0x40)) {
            my ($b2, $b3) = unpack('C2', substr($in, $ip, 2)); $ip += 2;
            $lit->($b2 >> 6);
            $copy->(((($b2 & 0x3F) << 8) | $b3) + 1, ($c & 0x3F) + 4);
        } elsif (!($c & 0x20)) {
            my ($b2, $b3, $b4) = unpack('C3', substr($in, $ip, 3)); $ip += 3;
            $lit->($c & 3);
            $copy->(((($c & 0x10) << 12) | ($b2 << 8) | $b3) + 1, $b4 + (($c & 0x0C) << 6) + 5);
        } else {
            my $n = ($c & 0x1F) * 4 + 4;
            last if $n > 0x70;
            $lit->($n);
        }
    }
    my $tail = $last & 3;
    if ($tail && length($out) < $size) {
        my $n = $size - length($out); $n = $tail if $n > $tail;
        $lit->($n);
    }
    $out = substr($out, 0, $size) if length($out) > $size;
    length($out) == $size or die sprintf("the squad database unpacked to %d bytes, its header says %d\n", length($out), $size);
    return $out;
}

# The plain database wrapped as a saved squad file (xAranaktu's layout).
sub saved_file {
    my ($db, $name) = @_;
    my $bnry_size = 45985;
    my $bnry = "BNRY\x00\x00\x00\x02LTLE\x01\x01\x03\x00\x00\x00cds\x01\x00\x00\x00\x00\x01\x03\x00\x00\x00cds";
    my $sign = "FBCHUNKS\x01\x00";
    my $prefix = $sign . pack('V V', 1126 - length($sign) - 8, 48 + 4 + length($db) + $bnry_size);
    my $title = substr("EA_$name", 0, 40);
    $prefix .= $title . ("\0" x 7) . 'Aranaktu';
    $prefix .= "\0" x (1126 - length($prefix));
    my $header = "SaveType_Squads\x00" . ("\0" x 32);
    return $prefix . $header . pack('V', length($db) + $bnry_size) . $db . $bnry . ("\0" x ($bnry_size - length($bnry)));
}
