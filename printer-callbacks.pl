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
@consumable_name	iso.3.6.1.2.1.43.11.1.1.6.1.1
@consumable_max		iso.3.6.1.2.1.43.11.1.1.8.1
@consumable_curr	iso.3.6.1.2.1.43.11.1.1.9.1
@tray_dim_x			iso.3.6.1.2.1.43.8.2.1.4.1
@tray_dim_y			iso.3.6.1.2.1.43.8.2.1.5.1
@tray_max			iso.3.6.1.2.1.43.8.2.1.9.1
@tray_capacity		iso.3.6.1.2.1.43.8.2.1.10.1
@tray_name			iso.3.6.1.2.1.43.8.2.1.13.1
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
	while ( my ($r_oid,$val) = each %$results ) {
		if ( $name =~ m{^\@} ) {
			my $offset = $1 - 1 if $r_oid =~ m{^\Q$oid\E\.?(\d+)};
			$response->{ $session->hostname }->{ $name }->[ $offset ] = $results->{$r_oid};
		} else {
			$response->{ $session->hostname }->{ $name } = $results->{$r_oid};
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

print dump($response);
