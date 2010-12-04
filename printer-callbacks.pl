#!/usr/bin/perl
use warnings;
use strict;

use Net::SNMP;
use Data::Dump qw(dump);

my $dir = 'public/json/monitor/printers/';
$dir = "/tmp/printers-" unless -d $dir;

use JSON;
sub save_json {
	my ( $ip, $json ) = @_;
	my $path = $dir . $ip;
	open(my $fh, '>', $path) || die "$path: $!";
	print $fh encode_json $json;
	close($fh);
	warn "# $path ", -s $path, " bytes\n";
}

sub iso_datetime {
	my ($ss,$mm,$hh,$d,$m,$y) = localtime(time);
	return sprintf "%04d-%02d-%02dT%02d:%02d:%02d", $y+1900, $m, $d, $hh, $mm, $ss;
}

my $log_path = join('.', $dir . (split(/T/,iso_datetime,2))[0], 'json');
open(my $log, '>>', $log_path) || die "$log_path: $!";

my $community = 'public';
my @printers = qw(
10.60.0.20

10.60.0.40

10.60.3.15
10.60.3.17
);

@printers = @ARGV if @ARGV;

my %vars = qw[
info				iso.3.6.1.2.1.1.1.0
hostname			iso.3.6.1.2.1.43.5.1.1.16.1
serial				iso.3.6.1.2.1.43.5.1.1.17.1
pages				iso.3.6.1.2.1.43.10.2.1.4.1.1
@message			iso.3.6.1.2.1.43.18.1.1.8
@consumable.name	iso.3.6.1.2.1.43.11.1.1.6.1
@consumable.max		iso.3.6.1.2.1.43.11.1.1.8.1
@consumable.curr	iso.3.6.1.2.1.43.11.1.1.9.1
@tray.dim_x			iso.3.6.1.2.1.43.8.2.1.4.1
@tray.dim_y			iso.3.6.1.2.1.43.8.2.1.5.1
@tray.max			iso.3.6.1.2.1.43.8.2.1.9.1
@tray.capacity		iso.3.6.1.2.1.43.8.2.1.10.1
@tray.name			iso.3.6.1.2.1.43.8.2.1.13.1
];

our $response;

sub columns_cb {
	my ( $session, $oid2name ) = @_;

	my $ip = $session->hostname;

	if ( ! defined $session->var_bind_list ) {
		warn "ERROR: $ip ", $session->error, "\n";
		warn dump($session);
		return;
	}


	warn "# $ip var_bind_list ", dump( $session->var_bind_list );
	my $results = $session->var_bind_list;
	$response->{$ip}->{ip} ||= $ip;
	$response->{$ip}->{utime} ||= time();
	# oid_lex_sort would be wonderfull to use here, but it doesn't work
	foreach my $r_oid ( sort {
			my ($af,$bf) = ($a,$b);
			$af =~ s{\.(\d+)$}{sprintf("%03d",$1)}eg;
			$bf =~ s{\.(\d+)$}{sprintf("%03d",$1)}eg;
			$af cmp $bf
	} keys %$results ) {
		my $var = $results->{$r_oid};
		my $oid = (grep {
			substr($r_oid,0,length($_)) eq $_
		} keys %$oid2name)[0] || die "no name for $r_oid in ",dump($oid2name);
		my $name = $oid2name->{$oid};
		if ( $name =~ m{^\@} ) {
			my $no_prefix = $name;
			$no_prefix =~ s{^\@}{};
			push @{ $response->{$ip}->{ $no_prefix } }, $var;
		} else {
			$response->{$ip}->{ $name } = $var;
		}
	}

	warn "## $ip response ",dump($response->{$ip});
}

foreach my $host ( @printers ) {

	my ( $snmp, $err ) = Net::SNMP->session(
		-hostname => $host,
		-version => 1,
		-community => $community,
		-timeout => 2,
		-retries => 0,
		-nonblocking => 1,
	);

	if ( ! $snmp ) {
		warn "ERROR: $host $err\n";
		next;
	}

	my @columns;
	my @vars;
	my $oid2name;
	while ( my ($name,$oid) = each %vars ) {
		warn "# $name $oid\n";
		$oid =~ s{^iso}{.1};
		if ( $name =~ m/^\@/ ) {
			push @columns, $oid;
		} else {
			push @vars, $oid;
		}
		$oid2name->{$oid} = $name;
	}
	$snmp->get_request( -varbindlist => [ @vars ], -callback => [ \&columns_cb, $oid2name ] );
	$snmp->get_entries( -columns =>  [ @columns ], -callback => [ \&columns_cb, $oid2name ] );

}

warn "# dispatch requests for ",dump(@printers);
snmp_dispatcher;

foreach my $ip ( keys %$response ) {

	my $status = $response->{$ip};
	foreach my $group ( grep { /\w+\.\w+/ } keys %$status ) {
		my ( $prefix,$name ) = split(/\./,$group,2);
		if ( ref $status->{$group} eq 'ARRAY' ) { # some consumables are non-repeatable on low-end devices
			foreach my $i ( 0 .. $#{ $status->{$group} } ) {
				$status->{$prefix}->[$i]->{$name} = $status->{$group}->[$i];
			}
		} else {
			$status->{$prefix}->[0]->{$name} = $status->{$group};
		}
		delete $status->{$group};
	}

	print "$ip ",dump($status);
	save_json $ip => $response->{$ip};
	print $log encode_json($response->{$ip}),"\n";
}

close($log);
warn "# log $log_path ", -s $log_path, " bytes\n";

