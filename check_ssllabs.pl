#!/usr/bin/perl
##############################################################################
# check_ssllabs.pl
# Nagios Plugin for testing your rating on ssllabs.com
# Simon Lauger <simon@lauger.name>
#
# https://github.com/slauger/check_ssllabs
#
# Copyright 2015-2017 Simon Lauger
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##############################################################################

use strict;
use warnings;

use LWP;
use JSON;
use URI::Escape;
use Data::Dumper;
use Nagios::Plugin;

my $plugin = Nagios::Plugin->new(
	plugin		=> 'check_ssllabs',
	shortname	=> 'SSL Labs',
	version		=> '0.0.1',
	url		=> 'https://github.com/slauger/check_ssllabs',
	blurb		=> 'Nagios Plugin for testing SSL rating for a website on ssllabs.com',
	usage		=> 'Usage: %s -H <hostname>',
	license		=> 'http://www.apache.org/licenses/LICENSE-2.0',
 	extra		=> ''
);

my @args = (
	{
		spec => 'hostname|H=s',
		usage => '-H, --hostname=STRING',
		desc => 'DNS name of the website to test',
		required => 1,
	},
);

foreach my $arg (@args) {
	add_arg($plugin, $arg);
}

$plugin->getopts;

check_ssllabs($plugin);

sub add_arg
{
	my $plugin = shift;
	my $arg    = shift;

	my $spec     = $arg->{'spec'};
	my $help     = $arg->{'usage'};
	my $default  = $arg->{'default'};
	my $required = $arg->{'required'};

	if (defined $arg->{'desc'}) {
		my @desc;

		if (ref($arg->{'desc'})) {
			@desc = @{$arg->{'desc'}};
		}
		else {
			@desc = ( $arg->{'desc'} );
		}

		foreach my $d (@desc) {
			$help .= "\n   $d";
		}
	}

	$plugin->add_arg(
		spec     => $spec,
		help     => $help,
		default  => $default,
		required => $required,
	);
}

sub check_ssllabs {

	my $plugin  = shift;
	my $params  = shift;
		
	my $lwp = LWP::UserAgent->new(
		env_proxy => 1, 
		keep_alive => 1, 
		timeout => $plugin->opts->timeout, 
		ssl_opts => { 
			verify_hostname => 1, 
			SSL_verify_mode => 1
		},
	);

	my $url     = undef;
	my $baseurl = 'https://api.ssllabs.com/api/v2/';

	$url = $baseurl . 'analyze?host=' . $plugin->opts->hostname;
	
	my $request = HTTP::Request->new(GET => $url);
	$request->header('Content-Type', 'application/json');
	my $response = $lwp->request($request);
	
	if ($plugin->opts->verbose) {
		print Dumper($response->content);
	}
	
	if (HTTP::Status::is_error($response->code)) {
		$plugin->nagios_die($response->content);
	} else {
		$response = JSON->new->allow_blessed->convert_blessed->decode($response->content);
	}
	
	if ($response->{status} eq 'DNS') {
		$plugin->nagios_exit(OK, 'result not yet available (test still resolving DNS)');
	} elsif ($response->{status} eq 'IN_PROGRESS') {
		$plugin->nagios_exit(OK, 'result not yet available (test still in progress)');
	} elsif ($response->{status} eq 'READY') {
		foreach my $endpoint (@{$response->{endpoints}}) {
			if ($endpoint->{grade} eq 'A+') {
				$plugin->add_message(OK, $response->{host} . ' (' . $endpoint->{ipAddress} . ') rated with grade ' . $endpoint->{grade} . ';');
			} elsif ($endpoint->{grade} eq 'A' || $endpoint->{grade} eq 'A-') {
				$plugin->add_message(WARNING, $response->{host} . ' (' . $endpoint->{ipAddress} . ') rated with grade ' . $endpoint->{grade} . ';');
			} else {
				$plugin->add_message(CRITICAL, $response->{host} . ' (' . $endpoint->{ipAddress} . ') rated with grade ' . $endpoint->{grade} . ';');
			}
		}
		my ($code, $message) = $plugin->check_messages;
		$plugin->nagios_exit($code, $message);
	} else {
		$plugin->nagios_die(WARNING, 'unkown status code');
	}
}
