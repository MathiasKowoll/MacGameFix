#!/usr/bin/perl
# Scoped, lossless Steam VDF edits. Never edit while Steam can overwrite its file.
# SPDX-License-Identifier: GPL-3.0-or-later
use strict; use warnings; use JSON::PP; use File::Path qw(make_path); use File::Copy qw(copy); use Text::ParseWords qw(shellwords);
my ($mode,$prefix)=@ARGV;
die "usage: fh6-launch-options.pl status|preflight|install|restore|diagnostics-on|diagnostics-off PREFIX\n" unless defined $prefix && $mode =~ /^(status|preflight|install|restore|diagnostics-on|diagnostics-off)$/;
my $steam="$ENV{HOME}/Library/Application Support/Steam";
my $journal="$prefix/.mgf-fh6-launch-options.json";
my %required=(NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=>'1',NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=>'0',NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=>'1',NOTPROTON_ROSETTA_TRAP_BOOST=>'1');
# MGF_FH6_CHAIN_IN_NTDLL=1: the ntdll.dll being installed (engine patch wine-11.21/0025) turns
# the exception chain and the ALU bridge on by itself for the guarded FH6 build, and the
# bridge resume was always off by default. Only the priority plugin's switch is still needed,
# and the variables an earlier install wrote are taken out again, each only with the exact
# value MacGameFix wrote. Any other ntdll keeps all four, as before.
my $in_ntdll=($ENV{MGF_FH6_CHAIN_IN_NTDLL}//'') eq '1';
my %ours=(NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=>'1',NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=>'0',NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=>'1',NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=>'0');
%required=(NOTPROTON_ROSETTA_TRAP_BOOST=>'1') if $in_ntdll;
sub readfile { my($f)=@_;open my $h,'<',$f or die "$f: $!\n";local $/;return <$h>; }
sub decode_vdf { my($s)=@_;$s =~ s/\\([\\"])/$1/g;return $s; }
sub encode_vdf { my($s)=@_;$s =~ s/([\\"])/\\$1/g;return '"'.$s.'"'; }
sub locate {
 my($text)=@_;my @stack;my $pending;my @matches;my $insert;
 pos($text)=0;
 while($text =~ /\G(?:\s+|\/\/[^\n]*(?:\n|$)|("(?:\\.|[^"\\])*"|[{}]))/gc){
  next unless defined $1;my $token=$1;my $start=$-[1];my $end=$+[1];
  if($token eq '{'){die "Malformed Steam config\n" unless defined $pending;push @stack,lc $pending;undef $pending;next;}
  if($token eq '}'){die "Malformed Steam config\n" if defined $pending || !@stack; if(join('/',@stack) eq 'userlocalconfigstore/software/valve/steam/apps/2483190'){$insert=$start;} pop @stack;next;}
  my $value=decode_vdf(substr($token,1,-1));
  if(!defined $pending){$pending=$value;next;}
  if(join('/',@stack) eq 'userlocalconfigstore/software/valve/steam/apps/2483190' && lc($pending) eq 'launchoptions'){push @matches,[$start,$end,$value];}
  undef $pending;
 }
 die "Ambiguous or malformed Steam config\n" if @stack || defined $pending || @matches>1 || substr($text,pos($text)//0) =~ /\S/;
 return $matches[0] if @matches;return defined($insert)?[$insert,$insert,'']:undef;
}
sub options {
 my($old,$overrides,$defaults,$remove)=@_;$remove//={};my $s=$old; $s='%command%' unless $s =~ /\S/;
 # Only leading environment assignments are managed; a custom wrapper is retained but refused.
 my @tokens;pos($s)=0;
 while($s =~ /\G\s*((?:[^\s"'\\]|"(?:\\.|[^"\\])*"|'[^']*'|\\.)+)/gc){push @tokens,[$-[1],$+[1],$1];}
 my %seen;my @edits;my $command=0;
 for my $t(@tokens){my @word=shellwords($t->[2]);die "Unsupported launch option quoting\n" unless @word==1;my $w=$word[0];if($w eq '%command%'){$command=1;last;}
  die "FH6 has a custom launch wrapper; keep it and configure the compatibility variables manually.\n" unless $w =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/s;
  my($k,$v)=($1,$2);die "Duplicate FH6 launch variable: $k\n" if $seen{$k}++ && exists $overrides->{$k};
  push @edits,[$t->[0],$t->[1],"$k=$overrides->{$k}"] if exists $overrides->{$k} && $v ne $overrides->{$k};
  if(!exists $overrides->{$k} && exists $remove->{$k} && $v eq $remove->{$k}){my $e=$t->[1];pos($s)=$e;$e=$+[0] if $s =~ /\G\s+/gc;push @edits,[$t->[0],$e,''];$seen{$k}=0;}
 }
 die "FH6 launch options have no %command% placeholder\n" unless $command;
 for my $e(reverse @edits){substr($s,$e->[0],$e->[1]-$e->[0],$e->[2]);}
 my @add;for my $k(sort keys %$overrides){push @add,"$k=$overrides->{$k}" unless $seen{$k};}
 for my $k(sort keys %$defaults){push @add,"$k=$defaults->{$k}" unless $seen{$k} || exists $overrides->{$k};}
 return (@add?join(' ',@add).' ':'').$s;
}
my @files;
# Enumerate account directories without shell expansion.
opendir(my $users,"$steam/userdata") or die "Steam user settings were not found. Start this game once in Steam.\n";
@files=map { "$steam/userdata/$_/config/localconfig.vdf" } grep { /^\d+$/ && -f "$steam/userdata/$_/config/localconfig.vdf" } readdir($users);closedir $users;
my $saved=-f $journal?decode_json(readfile($journal)):{};my @changes;my $found=0;
for my $f(sort @files){my $text=readfile($f);my $loc=locate($text);next unless $loc;++$found;my $old=$loc->[2];my $new;
 if($mode eq 'restore'){
  next unless exists $saved->{$f};
  die "FH6 launch options changed since installation; restore refused to preserve your edits.\n" unless $old eq $saved->{$f}{installed};
  $new=$saved->{$f}{original};
 } else {
  my %set=%required;my %default;
  if($mode =~ /^diagnostics-(on|off)$/){my $v=$1 eq 'on'?'1':'0';$set{NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS}=$v;$set{MTL_HUD_ENABLED}=$v;$set{MTL_HUD_LOG_ENABLED}=$v;}
  elsif($mode ne 'status' && !$in_ntdll){$default{NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS}='0';}
  my %remove;%remove=%ours if $in_ntdll && $mode ne 'status';
  $new=options($old,\%set,\%default,\%remove);
 }
 next if $new eq $old;
 my $replacement=encode_vdf($new);$replacement='"LaunchOptions" '.$replacement."\n\t\t\t\t\t" if $loc->[0]==$loc->[1];
 my $next=$text;substr($next,$loc->[0],$loc->[1]-$loc->[0],$replacement);
 push @changes,[$f,$text,$next,$old,$new];
}
die "FH6 is missing from Steam user settings. Start it once before installing.\n" unless $found;
if($mode eq 'status'){print @changes?"absent\n":"installed\n";exit(@changes?1:0);}
if(@changes){my $ps=`/bin/ps -axo comm=`;die "Quit Steam before MacGameFix applies FH6 launch options; nothing was changed.\n" if $ps =~ m{(?:/Steam\.app/Contents/MacOS/steam|/steam_osx)\s*$}m;}
exit 0 if $mode eq 'preflight';
# Recheck all files before the first write; atomic replacement preserves unrelated VDF text.
for my $c(@changes){die "Steam settings changed; retry with Steam closed.\n" unless readfile($c->[0]) eq $c->[1];}
for my $c(@changes){my($f,$before,$after,$old,$new)=@$c;
 if($mode ne 'restore'){$saved->{$f}//={original=>$old};$saved->{$f}{installed}=$new;}
 my $backup="$f.mgf-fh6-backup";copy($f,$backup) or die "$backup: $!\n" unless -e $backup;
 open my $o,'>',"$f.mgf-new" or die $!;print $o $after;close $o or die $!;chmod((stat($f))[2]&07777,"$f.mgf-new");rename "$f.mgf-new",$f or die $!;
}
if($mode eq 'restore'){unlink $journal if -f $journal;}elsif(@changes){open my $o,'>',"$journal.tmp" or die $!;print $o JSON::PP->new->canonical->pretty->encode($saved);close $o;rename "$journal.tmp",$journal or die $!;}
print "FH6 launch options ready.\n";
