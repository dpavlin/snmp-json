#!/usr/bin/perl
use warnings;
use strict;

use SNMP::Multi;
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

@printers = @ARGV if @ARGV;

my %vars = qw[
model		.1.3.6.1.2.1.25.3.2.1.3.1
serial		.1.3.6.1.2.1.43.5.1.1.17
pages		.1.3.6.1.2.1.43.10.2.1.4.1.1
@message	.1.3.6.1.2.1.43.18.1.1.8
@message	.1.3.6.1.2.1.43.16
@consumable_name	.1.3.6.1.2.1.43.11.1.1.6.1
@consumable_max		.1.3.6.1.2.1.43.11.1.1.8.1
@consumable_curr	.1.3.6.1.2.1.43.11.1.1.9.1
];

my @oids = sort { length $a <=> length $b } values %vars;
my $oid2name;
$oid2name->{ $vars{$_} } = $_ foreach keys %vars;

my $sm = SNMP::Multi->new(
	Method    => 'bulkwalk',
	Community => $community,
	Requests  => SNMP::Multi::VarReq->new(
		hosts => [ @printers ],
		vars  => [ map { [ $_ ] } values %vars ],
    ),
	Timeout     => 1,
	Retries     => 0,
) or die $SNMP::Multi::error;

warn "# working on: ", join(' ', @printers),$/;

my $resp = $sm->execute() or die $sm->error();

foreach my $host ( $resp->hosts ) {
	my $status;

	foreach my $result ( $host->results ) {
		if ( $result->error ) {
			warn "ERROR: $host ", $result->error;
			next;
		}

		foreach my $v ( $result->varlists ) {
			foreach my $i ( @$v ) {
				my ( $oid, undef, $val, $fmt ) = @$i;
				$oid =~ s/^iso/.1/;
				if ( my $name = $oid2name->{$oid} ) {
					$status->{$name} = $val;
				} else {
					my $oid_base;
					foreach ( @oids ) {
						my $oid_part = substr($oid,0,length($_));
						if ( $oid_part eq $_ ) {
							$oid_base = $oid_part;
							last;
						}
					}

					my $name = $oid2name->{$oid_base} || die "no name for $oid_base in ",dump( $oid2name );
					if ( $name =~ s/^\@// ) {
						push @{ $status->{$name} }, $val;
					} else {
						$status->{$name} = $val;
					}
				}
			}
		}

	}

	foreach my $group ( grep { /\w+_\w+/ } keys %$status ) {
		my ( $prefix,$name ) = split(/_/,$group,2);
		foreach my $i ( 0 .. $#{ $status->{$group} } ) {
			$status->{$prefix}->[$i]->{$name} = $status->{$group}->[$i];
		}
		delete $status->{$group};
	}

	print "$host = ",dump($status);
}

