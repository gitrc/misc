#!/usr/bin/perl -w
#
# Generate phpsysinfo compatible XML
# Requires Net::CIDR too
#
# Rod Cordova (@gitrc)
#
# Feb 2007

use strict;
use XML::Simple;
use Sys::Hostname;
use Sys::Statistics::Linux;
use XML::Simple;

#use Data::Dumper;
use Net::Server;

use base qw(Net::Server::Fork);

### run the server
__PACKAGE__->run;
exit;

###----------------------------------------------------------------###

### set up some server parameters
sub configure_hook {
    my $self = shift;

    $self->{server}->{port}       = '*:6666';        # port and addr to bind
    $self->{server}->{user}       = 'nobody';        # user to run as
    $self->{server}->{group}      = 'nobody';        # group to run as
    $self->{server}->{setsid}     = 1;               # daemonize
    $self->{server}->{cidr_allow} = '10.0.0.1/32';   # allow/deny IP
}

sub process_request {
    my $self = shift;

    my $distroicon = "Redhat.png";
    my $lxs        = Sys::Statistics::Linux->new(
        memstats  => 1,
        netstats  => 1,
        sysinfo   => 1,
        loadavg   => 1,
        diskusage => 1
    );

    #sleep(1); #  these stats dont require deltas
    my $stat      = $lxs->get;
    my $netstats  = $stat->netstats;
    my $diskstats = $stat->diskusage;

    my $netdevnames;
    foreach my $key ( $stat->netstats ) {
        push(
            @{$netdevnames},
            {
                Name    => $key,
                RxBytes => $netstats->{$key}->{'rxbyt'},
                TxBytes => $netstats->{$key}->{'txbyt'},
                Errors  => int(
                    $netstats->{$key}->{'rxerrs'} +
                      $netstats->{$key}->{'txerrs'}
                ),
                Drops => int(
                    $netstats->{$key}->{'rxdrop'} +
                      $netstats->{$key}->{'txdrop'}
                )
            }
        );
    }

    my $mounts;
    foreach my $key ( $stat->diskusage ) {
        push(
            @{$mounts},
            {
                Device     => { 'Name' => $key },
                Mountpoint => $diskstats->{$key}->{'mountpoint'},
                Percent    => $diskstats->{$key}->{'usageper'},
                Free       => $diskstats->{$key}->{'free'},
                Used       => $diskstats->{$key}->{'usage'},
                Size       => $diskstats->{$key}->{'total'}
            }
        );
    }

    #print Dumper($stat);

    my $sys      = $stat->sysinfo;
    my $hostname = $sys->{'hostname'};
    my $version  = $sys->{'release'};
    my $load     = $stat->loadavg;
    my $meminfo  = $stat->memstats;
    my $mem_app =
      $meminfo->{'memused'} - $meminfo->{'cached'} - $meminfo->{'buffers'};
    my $mem_pct_total =
      int( $meminfo->{'memused'} * 100 / $meminfo->{'memtotal'} );
    my $mem_pct_app = int( $mem_app * 100 / $meminfo->{'memtotal'} );
    my $mem_pct_cached =
      int( 100 * $meminfo->{'cached'} / $meminfo->{'memtotal'} );
    my $mem_pct_buffers =
      int( 100 * $meminfo->{'buffers'} / $meminfo->{'memtotal'} );

    sub cpuinfo {
        my ( $cpumodel, $cpusmp, $cpumhz, $cpucache, $cpubogomips );
        open( CPUINFO, "/proc/cpuinfo" ) or return undef;
        while (<CPUINFO>) {
            if (/^model name\s+\:\s+(.*?)$/) {
                if ( defined $cpumodel ) {
                    if ( defined $cpusmp ) {
                        $cpusmp++;
                    }
                    else {
                        $cpusmp = 2;
                    }
                }
                else {
                    $cpumodel = $1;
                }
            }
            elsif (/^cpu MHz\s+:\s+([\d\.]*)/) {
                $cpumhz = $1;
            }
            elsif (/^cache size\s+:\s+(.*)/) {
                $cpucache = $1;
            }
            elsif (/^bogomips\s+:\s+([\d\.]*)/) {
                $cpubogomips += $1;
            }
        }
        my $cpunumber = $cpusmp;
        $cpunumber = 1 unless $cpunumber;
        return ( $cpumodel, $cpumhz, $cpucache, $cpubogomips, $cpunumber );
    }

    my ( $cpumodel, $cpumhz, $cpucache, $cpubogomips, $cpunumber ) = cpuinfo();

    # generate PCI list
    my @pcidev = qx|/sbin/lspci|;
    my $pcids;

    foreach my $pcidevice (@pcidev) {
        if ( $pcidevice =~ m/([A-Z].*)/ ) {
            next if $pcidevice =~ /bridge|hub|Unknown/io;
            push( @{$pcids}, { Name => $1 } );
        }
    }

    # get SCSI
    my @scsi = cat("/proc/scsi/scsi");
    my @vendor;
    my @model;
    my @type;
    foreach my $line (@scsi) {
        if ( $line =~ m/Vendor:\s+([^\s]+)\s+Model:\s+([^\s]+)\s/ ) {
            push( @vendor, $1 );
            push( @model,  $2 );
        }
        elsif ( $line =~ m/Type:\s+([^\s]+)\s/ ) {
            push( @type, "($1)" );
        }

    }

    my $scsidevices;
    my $i = 0;

    sub join_array {
        my ( $a, $b, $c ) = @_;
        foreach (@$a) {

            #push(@scsidevices, "@$a[$i] @$b[$i] @$c[$i]");
            push( @{$scsidevices}, { Name => "@$a[$i] @$b[$i] @$c[$i]" } );
            $i++;
        }
    }

    &join_array( \@vendor, \@model, \@type );
    push( @{$scsidevices}, { Name => "No SCSI disks attached" } ) if ($i eq 0);

    # get local IP addresses
    my @ips = qx(/sbin/ip addr);

    my @ipaddrs;
    foreach my $ip (@ips) {
        if ( $ip =~ m/inet\s(\d+.\d+.\d+.\d+)/ ) {
            next if $ip =~ /127.0.0.1/io;
            push( @ipaddrs, $1 );
        }
    }

    # get uptime
    my $uptime;
    open( UPTIME, "/proc/uptime" ) or return undef;
    while (<UPTIME>) {
        if (/(\w+\W+\d+)/) {
            $uptime = $1;
        }
    }

    # Distro Name
    my $distro = cat("/etc/redhat-release");

    # User count
    $_ = ( @_ = split / /, qx|users| );
    my $users = $_;

        # dmi via sysfs
        my $mfg;
        my $type;
        my $serial;
    if (-e "/sys/class/dmi/id")
        {
                $mfg = cat("/sys/class/dmi/id/sys_vendor");
                $type = cat("/sys/class/dmi/id/product_name");
                $serial = cat("/sys/class/dmi/id/product_serial");
        }

my($model) = $type;
$model =~ m/(\-\[(\d\d\d\d))/;
my $stype = $2;

###################################
    # XMLout hash
###################################
    my %sysinfo = (
        Vitals => {
            Hostname   => $hostname,
            IPAddr     => "@ipaddrs",
            Kernel     => $version,
            Distro     => $distro,
            Distroicon => $distroicon,
            Uptime     => $uptime,
            Users      => $users,
            LoadAvg    => "$load->{'avg_1'} $load->{'avg_5'} $load->{'avg_15'}"
        },
        Network  => { NetDevice => [ @{$netdevnames} ] },
        Hardware => {
                        DMI => [
                                {
                                        Mfg             => $mfg,
                                        Type    => $type,
                                        Serial  => $serial,
                                        Stype   => $stype
                                }
                                        ],
            CPU => [
                {
                    Number   => $cpunumber,
                    Model    => $cpumodel,
                    Cpuspeed => $cpumhz,
                    Cache    => $cpucache,
                    Bogomips => $cpubogomips
                }
            ],
            PCI  => { Device => [ @{$pcids} ] },
            SCSI => { Device => [ @{$scsidevices} ] }

        },
        Memory => {
            Free           => $meminfo->{'memfree'},
            Used           => $meminfo->{'memused'},
            Total          => $meminfo->{'memtotal'},
            Percent        => $mem_pct_total,
            App            => $mem_app,
            AppPercent     => $mem_pct_app,
            Buffers        => $meminfo->{'buffers'},
            BuffersPercent => $mem_pct_buffers,
            Cached         => $meminfo->{'cached'},
            CachedPercent  => $mem_pct_cached
        },
        Swap => {
            Free    => $meminfo->{'swapfree'},
            Used    => $meminfo->{'swapused'},
            Total   => $meminfo->{'swaptotal'},
            Percent => $meminfo->{'swapusedper'}
        },
        FileSystem => { Mount => [ @{$mounts} ] }

    );

    sub cat {
        open MYFILE, $_[0] or die "$!";
        @_ = <MYFILE>;
        close MYFILE;
        return (wantarray) ? @_ : join "", @_;
    }

    my $xsimple = XML::Simple->new();
    print $xsimple->XMLout(
        \%sysinfo,
        noattr   => 1,
        rootname => 'phpsysinfo',
        xmldecl  => '<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE phpsysinfo SYSTEM "phpsysinfo.dtd">'
    );
}
1;
