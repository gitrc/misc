#!/usr/bin/perl -w
#
# Populate a MySQL table with guest & host relationships
#
# Rod Cordova (@gitrc)
#
#


use strict;
use warnings;
use VMware::VIRuntime;
use VMware::VILib;
use DBI;
use Data::Dumper;

# Defining attributes for a required option named 'dc' that
# accepts a string.
#
my %opts = (
        dcname => {
        type => "=s",
        help => "Datacenter name",
        required => 0,
    },
);
Opts::add_options(%opts);

# Parse all connection options (both built-in and custom), and then
# connect to the server
Opts::parse();
Opts::validate();
Util::connect();

my $datacenter = Opts::get_option('dcname') || 'mydc';

my $datacenter_view = Vim::find_entity_view(view_type => 'Datacenter', filter => {'name' => $datacenter});
my $vm_view = Vim::find_entity_views(view_type => 'VirtualMachine', begin_entity => $datacenter_view);

my %vmhash;
my %notes;
my %power;

foreach my $vm (@$vm_view) {

# Major speed boost here by specifying the property we want in the query otherwise the whole host object comes back...
my $hostmor = Vim::get_view(mo_ref => $vm->runtime->host, properties => ['name'] );
$vmhash{$vm->name} = $hostmor->{'name'};
$notes{$vm->name} = $vm->summary->config->annotation;
$power{$vm->name} = $vm->runtime->powerState->val;
}


# Disconnect from the server
Util::disconnect();

# MySQL DB inserts
#
my $dbname = "vminfo";
my $dbhost = "localhost";
my $dbuser = "root";
my $dbpass = "";

my $dbh = DBI->connect("DBI:mysql:$dbname", $dbuser, $dbpass)
        or die("ERROR: Could not connect to MYSQL database - " . $DBI::errstr);

my $table = 'esxwho';
#my $truncate_table = "TRUNCATE $table";
my $drop_table = "DROP TABLE $table";
my $create_table = "CREATE TABLE esxwho(vmname VARCHAR(255), power VARCHAR(255), hostname VARCHAR(255), notes VARCHAR(255))";

my $stmt = $dbh->prepare($drop_table);
$stmt->execute() or die("ERROR: Could not drop table");

$stmt = $dbh->prepare($create_table);
$stmt->execute() or die("ERROR: Could not create table");

foreach my $vm (keys %vmhash)
{

my $insert = "INSERT INTO $table VALUES (?, ?, ?, ?);";
$stmt   = $dbh->prepare($insert);

$stmt->execute($vm,$power{$vm},$vmhash{$vm},$notes{$vm})
        or die("ERROR: Could not insert record - " . $dbh->errstr);
}
