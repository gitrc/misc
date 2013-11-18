#!/usr/bin/perl -w
#
#
# Pull the HTML table from New Relic with transaction errors for the last 24 hours for a specific application and email it
#
# Rod Cordova (@gitrc)
#
# November 2012
#

use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use MIME::Lite;
use strict;

# app id, destination email, account id go here - account id because subs have diff ids

my %apps = (
    NNNNNN => [ 'App 1', 'email1@example.com,email2@example.com', 'NNNNNN' ],
    
    NNNNNN => [ 'App 2', 'email1@example.com,email2@email.com', 'NNNNNN' ],
);


foreach my $app ( sort keys %apps ) {

my $t_url='https://rpm.newrelic.com/session';

my $login='apiuser@example.com';
my $password='hello_world';
my $submit_value='Login_submit';


# No mods should be needed below

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)");

$ua->cookie_jar(HTTP::Cookies->new(file => "cookies.nr.txt", autosave => 1, ignore_discard => 1));

my $content = $ua->request(POST $t_url , [ 'login[email]' => $login , 'login[password]' => $password, loginSubmit => $submit_value ] )->as_string;

my $url = qq {https://rpm.newrelic.com/accounts/$apps{$app}[2]/applications/$app/traced_errors?tw%5Bdur%5D=last_24_hours};

$content = $ua->request(GET $url )->as_string;

$content =~ m/<thead>(.*)<\/table>/gs;
my $table = $1;
$table =~ s/<span>/<p>/g;
$table =~ s/<\/span>/<\/p>/g;

my $baseurl = 'https://rpm.newrelic.com/accounts';
$table =~ s/\/accounts/$baseurl/g;

my $output;
$output .=  "<table>\n";
my @table = split('\n', $table);
foreach my $line (@table)
{
next if $line =~ /sort_order/;
$output .= "$line\n";
}
$output .= "</table>\n";

# Generate the Email

### Create a new multipart message:
    my $msg = MIME::Lite->new(
        From    => 'New Relic Reports <devops@example.com>',
        To      => $apps{$app}[1],
        Subject => "[New Relic]: Daily Error report for $apps{$app}[0]",
        Type    => 'multipart/mixed'
    );

    #$msg->add('X-Priority' => 1);

### Add parts (each "attach" has same arguments as "new"):
    $msg->attach(
        Type => 'text/html',
        Data => $output
    );

    # send the email
    MIME::Lite->send( 'smtp', 'localhost', Timeout => 10 );
    $msg->send();

}
