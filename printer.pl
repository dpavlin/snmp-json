#!/usr/bin/perl
use warnings;
use strict;

use Net::SNMP;
use Data::Dump qw(dump);

my $community = 'public';
my @printers = qw(
10.60.3.15
10.60.3.17

10.60.3.19
10.60.3.21

10.60.3.23
10.60.3.25

10.60.3.27
10.60.3.29

10.60.3.31
10.60.3.33

10.60.3.35
10.60.3.37
);

my %vars = qw[
model		.1.3.6.1.2.1.25.3.2.1.3.1
serial		.1.3.6.1.2.1.43.5.1.1.17
pages		.1.3.6.1.2.1.43.10.2.1.4.1.1
@message	.1.3.6.1.2.1.43.18.1.1.8
@message	.1.3.6.1.2.1.43.16
];

foreach my $host ( @printers ) {

	my ( $snmp, $err ) = Net::SNMP->session(
		-hostname => $host,
		-version => 1,
		-community => $community,
		-timeout => 1,
		-retries => 0,
	);

	if ( ! $snmp ) {
		warn "ERROR: $host $err\n";
		next;
	}

	while ( my ($name,$oid) = each %vars ) {
		warn "# $name $oid\n";
		if ( $name =~ m/^\@/ ) {
			my $result = $snmp->get_entries( -columns => [ $oid ] );
			printf "%s\t%s\t%s\t%s\n", $host, $name, $oid, dump($result) if $result;
		} else {
			my $result = $snmp->get_request( -varbindlist => [ $oid ] );
			printf "%s\t%s\t%s\t%s\n", $host, $name, $oid, $result->{$oid} if exists $result->{$oid};
		}
	}

}

