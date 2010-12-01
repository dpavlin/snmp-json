#!/usr/bin/perl
use warnings;
use strict;

use Net::SNMP;
use Data::Dump qw(dump);

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
pages				iso.3.6.1.2.1.43.10.2.1.4.1
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
	my ( $session, $oid, $name ) = @_;

	if ( ! defined $session->var_bind_list ) {
		warn "ERROR: ",$session->hostname, " $oid $name ", $session->error, "\n";
		warn dump($session);
		return;
	}


	warn "# $oid $name var_bind_list ", dump( $session->var_bind_list );
	my $results = $session->var_bind_list;
	# oid_lex_sort would be wonderfull to use here, but it doesn't work
	foreach my $r_oid ( sort {
			my ($af,$bf) = ($a,$b);
			$af =~ s{\.(\d+)$}{sprintf("%03d",$1)}eg;
			$bf =~ s{\.(\d+)$}{sprintf("%03d",$1)}eg;
			$af cmp $bf
	} keys %$results ) {
		my $var = $results->{$r_oid};
		if ( $name =~ m{^\@} ) {
			my $no_prefix = $name;
			$no_prefix =~ s{^\@}{};
			push @{ $response->{ $session->hostname }->{ $no_prefix } }, $var;
		} else {
			$response->{ $session->hostname }->{ $name } = $var;
		}
	}
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

	while ( my ($name,$oid) = each %vars ) {
		warn "# $name $oid\n";
		$oid =~ s{^iso}{.1};
		if ( $name =~ m/^\@/ ) {
			$snmp->get_entries( -columns => [ $oid ], -callback => [ \&columns_cb, $oid, $name ] );
		} else {
			$snmp->get_request( -varbindlist => [ $oid ], -callback => [ \&columns_cb, $oid, $name ] );
		}
	}

}

warn "# dispatch requests for ",dump(@printers);
snmp_dispatcher;

foreach my $ip ( keys %$response ) {

	my $status = $response->{$ip};
	foreach my $group ( grep { /\w+\.\w+/ } keys %$status ) {
		my ( $prefix,$name ) = split(/\./,$group,2);
		foreach my $i ( 0 .. $#{ $status->{$group} } ) {
			$status->{$prefix}->[$i]->{$name} = $status->{$group}->[$i];
		}
		delete $status->{$group};
	}

	print "$ip ",dump($status);
}
