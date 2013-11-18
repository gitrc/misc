#!/usr/bin/perl -w
#
#
# Radware Alteon WebOS XML API over SSL w/client cert
#
# There's nothing "Web" about this.
#
# Rod Cordova (@gitrc)
#
# December 2010
#

use strict;
use IO::Socket::SSL;    #qw(debug3);

my $debug = 1;

my @xmlconfig;		# these are sample commands actual ones will include real servers and matching groups
push @xmlconfig, qq {<Cli Command="/c/ip/if 100/en"/>};
push @xmlconfig, qq {<Cli Command="/c/l3/if 100/addr 10.1.0.188"/>};
push @xmlconfig, qq {<Cli Command="/c/l3/if 100/mask 255.255.255.0"/>};

my $client = IO::Socket::SSL->new(
    PeerAddr      => '10.100.0.1',
    PeerPort      => '443',
    SSL_use_cert  => '1',
    SSL_key_file  => "alteon-client.key",
    SSL_cert_file => "alteon-client.crt",
  )

  || die "[ERROR] " . IO::Socket::SSL::errstr();

print "[DEBUG] SSL connected.\n" if $debug;

# just in case... failsafe
alarm(10);
$SIG{ALRM} = sub {
    die "[ERROR] Socket timed out.\n";
};

# start talking
send_socket(qq {<?xml version="1.0" encoding="UTF-8"?>});
send_socket(
qq {<AlteonConfig xmlns:xsi="http://www.w3.org/2001/XMLSchemainstance" xsi:noNamespaceSchemaLocation="AOSConfig.xsd" Version="1">}
);

# loop through the changes
foreach my $line (@xmlconfig) {
    send_socket($line);
}

# finish the payload and check for apply response
send_socket(qq {<Cli Command="apply"/>});
send_socket(qq {</AlteonConfig>});

# we did not time out
alarm(0);

# the end
$client->close;
exit 0;


# subs 
sub send_socket {
    my $data = shift;
    print $client $data;
    print "[DEBUG] Sent $data\n" if $debug;

    sysread( $client, my $ack, 8192 )
      || die "[ERROR] No response from server.\n";
    if ( $data =~ /apply/ || $data =~ /AlteonConfig/ ) {
        die "[ERROR] Push failed: $ack\n" if $ack =~ /(Error|Warning)/i;
        print "[DEBUG] Response: $ack\n" if $debug;
    }
    else {
        die "[ERROR] Push failed: $ack\n" unless $ack =~ /commands executed/;
        print "[DEBUG] Response: $ack\n" if $debug;
    }
}
