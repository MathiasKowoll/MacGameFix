#!/usr/bin/perl
# Put variables into one Steam game's launch options and take them out again, losslessly.
#
#   steam-launch-options.pl status|preflight|install|restore APPID JOURNAL KEY=VALUE...
#
# status     exit 0 and "installed" when every KEY=VALUE is in the game's launch options in
#            every Steam account that has the game; else "absent", exit 1. Reads only.
# preflight  what install would refuse, without writing.
# install    each missing KEY=VALUE goes in front of the options; a KEY with another value
#            gets ours. JOURNAL records what each account had, so restore can give it back.
# restore    a KEY that still has our value is taken out, or gets back the value it had;
#            one the user changed since is theirs and stays. JOURNAL is removed.
#
# Only leading VAR=value words before %command% are looked at: options with a wrapper are
# refused, and everything else in them is kept byte for byte, as is the rest of the file.
# Steam rewrites localconfig.vdf when it quits, so nothing is written while it runs.
# The same VDF reader as fh6-launch-options.pl, for any app id.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
use strict; use warnings; use JSON::PP; use File::Copy qw(copy); use Text::ParseWords qw(shellwords);
my ($mode,$app,$journal,@pairs)=@ARGV;
die "usage: steam-launch-options.pl status|preflight|install|restore APPID JOURNAL KEY=VALUE...\n"
  unless defined $journal && $mode =~ /^(status|preflight|install|restore)$/ && $app =~ /^\d+$/ && @pairs;
my %want;
for my $p(@pairs){die "not KEY=VALUE: $p\n" unless $p =~ /^([A-Za-z_][A-Za-z0-9_]*)=([^\s"'\\]*)$/;$want{$1}=$2;}
my $steam="$ENV{HOME}/Library/Application Support/Steam";
my $where="userlocalconfigstore/software/valve/steam/apps/$app";
sub readfile { my($f)=@_;open my $h,'<',$f or die "$f: $!\n";local $/;return <$h>; }
sub decode_vdf { my($s)=@_;$s =~ s/\\([\\"])/$1/g;return $s; }
sub encode_vdf { my($s)=@_;$s =~ s/([\\"])/\\$1/g;return '"'.$s.'"'; }
# [start, end, value] of the app's LaunchOptions, or an empty span where the field can go in.
sub locate {
 my($text)=@_;my @stack;my $pending;my @matches;my $insert;
 pos($text)=0;
 while($text =~ /\G(?:\s+|\/\/[^\n]*(?:\n|$)|("(?:\\.|[^"\\])*"|[{}]))/gc){
  next unless defined $1;my $token=$1;my $start=$-[1];my $end=$+[1];
  if($token eq '{'){die "Malformed Steam config\n" unless defined $pending;push @stack,lc $pending;undef $pending;next;}
  if($token eq '}'){die "Malformed Steam config\n" if defined $pending || !@stack;$insert=$start if join('/',@stack) eq $where;pop @stack;next;}
  my $value=decode_vdf(substr($token,1,-1));
  if(!defined $pending){$pending=$value;next;}
  push @matches,[$start,$end,$value] if join('/',@stack) eq $where && lc($pending) eq 'launchoptions';
  undef $pending;
 }
 die "Ambiguous or malformed Steam config\n" if @stack || defined $pending || @matches>1 || substr($text,pos($text)//0) =~ /\S/;
 return $matches[0] if @matches;return defined($insert)?[$insert,$insert,'']:undef;
}
# The leading VAR=value words: [start, end, key, value] each. Dies on a wrapper or no %command%.
sub words {
 my($s)=@_;my @out;pos($s)=0;
 while($s =~ /\G\s*((?:[^\s"'\\]|"(?:\\.|[^"\\])*"|'[^']*'|\\.)+)/gc){
  my($a,$b,$t)=($-[1],$+[1],$1);my @w=shellwords($t);die "Unsupported launch option quoting\n" unless @w==1;
  return \@out if $w[0] eq '%command%';
  die "The launch options start with a program, not variables; set the variables by hand.\n" unless $w[0] =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/s;
  push @out,[$a,$b,$1,$2];
 }
 die "The launch options have no %command%\n";
}
# The options with %$set given (KEY=>VALUE) and %$drop taken out (KEY=>VALUE they must still have).
sub edit {
 my($old,$set,$drop)=@_;my $s=$old;$s='%command%' unless $s =~ /\S/;
 my @w=@{words($s)};my %seen;my @edits;
 for my $t(@w){my($a,$b,$k,$v)=@$t;
  if(exists $set->{$k}){push @edits,[$a,$b,"$k=$set->{$k}"] if $v ne $set->{$k};$seen{$k}=1;}
  elsif(exists $drop->{$k} && $v eq $drop->{$k}){pos($s)=$b;my $e=$b;$e=$+[0] if $s =~ /\G\s+/gc;push @edits,[$a,$e,''];}
 }
 for my $e(sort { $b->[0] <=> $a->[0] } @edits){substr($s,$e->[0],$e->[1]-$e->[0],$e->[2]);}
 my @add=map { "$_=$set->{$_}" } grep { !$seen{$_} } sort keys %$set;
 return (@add?join(' ',@add).' ':'').$s;
}
sub current { my($old)=@_;my %h;my $s=$old =~ /\S/?$old:'%command%';$h{$_->[2]}//=$_->[3] for @{words($s)};return \%h; }
my @files;
if(opendir(my $users,"$steam/userdata")){
 @files=sort map { "$steam/userdata/$_/config/localconfig.vdf" } grep { /^\d+$/ && -f "$steam/userdata/$_/config/localconfig.vdf" } readdir($users);
 closedir $users;
}
my $saved=-f $journal?decode_json(readfile($journal)):{};
my @changes;my $found=0;my $missing=0;
for my $f(@files){
 my $text=readfile($f);my $loc=locate($text);next unless $loc;++$found;my $old=$loc->[2];my $new;
 my $have=current($old);
 if($mode eq 'status'){ for my $k(keys %want){ $missing++ unless defined $have->{$k} && $have->{$k} eq $want{$k}; } next; }
 if($mode eq 'restore'){
  next unless exists $saved->{$f} && exists $saved->{$f}{vars};my %set;my %drop;
  for my $k(keys %{$saved->{$f}{vars}}){
   my $ours=$saved->{$f}{vars}{$k}{ours};my $was=$saved->{$f}{vars}{$k}{was};
   next unless defined $have->{$k} && $have->{$k} eq $ours;
   if(defined $was){$set{$k}=$was;}else{$drop{$k}=$ours;}
  }
  # Keys restored to an earlier value keep their place; the others go.
  $new=edit($old,\%set,\%drop);$new='' if $saved->{$f}{empty} && $new eq '%command%';
 } else {
  $new=edit($old,\%want,{});
  if($mode eq 'install'){
   $saved->{$f}{empty}=JSON::PP::true if !exists $saved->{$f} && $old !~ /\S/;
   for my $k(keys %want){
    next if (exists $saved->{$f} && exists $saved->{$f}{vars} && exists $saved->{$f}{vars}{$k}) || (defined $have->{$k} && $have->{$k} eq $want{$k});
    $saved->{$f}{vars}{$k}={ours=>$want{$k},was=>$have->{$k}};
   }
  }
 }
 next if $new eq $old;
 my $replacement=encode_vdf($new);$replacement='"LaunchOptions" '.$replacement."\n\t\t\t\t\t" if $loc->[0]==$loc->[1];
 my $next=$text;substr($next,$loc->[0],$loc->[1]-$loc->[0],$replacement);
 push @changes,[$f,$text,$next];
}
if($mode eq 'status'){ my $ok=$found && !$missing;print $ok?"installed\n":"absent\n";exit($ok?0:1); }
die "The game is missing from Steam's user settings. Start it once in Steam first.\n" unless $found || $mode eq 'restore';
if(@changes){my $ps=`/bin/ps -axo comm=`;die "Quit Steam first: it rewrites the launch options when it quits. Nothing was changed.\n" if $ps =~ m{(?:/Steam\.app/Contents/MacOS/steam|/steam_osx)\s*$}m;}
exit 0 if $mode eq 'preflight';
for my $c(@changes){die "Steam's settings changed meanwhile; try again with Steam closed.\n" unless readfile($c->[0]) eq $c->[1];}
for my $c(@changes){my($f,$before,$after)=@$c;
 my $backup="$f.mgf-backup";copy($f,$backup) or die "$backup: $!\n" unless -e $backup;
 open my $o,'>',"$f.mgf-new" or die "$f.mgf-new: $!\n";print $o $after;close $o or die "$f.mgf-new: $!\n";
 chmod((stat($f))[2]&07777,"$f.mgf-new");rename "$f.mgf-new",$f or die "$f: $!\n";
}
if($mode eq 'restore'){unlink $journal if -f $journal;}
elsif(%$saved){open my $o,'>',"$journal.tmp" or die "$journal.tmp: $!\n";print $o JSON::PP->new->canonical->pretty->encode($saved);close $o;rename "$journal.tmp",$journal or die "$journal: $!\n";}
print "launch options ready\n";
