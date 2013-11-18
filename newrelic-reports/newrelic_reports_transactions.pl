#!/usr/bin/perl -w
#
#
# Pull the HTML table from New Relic with slow transactions for the last 24 hours for a specific application and email it
#
# Rod Cordova (@gitrc)
#
# November 2012
#

use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use HTTP::Headers;
use MIME::Lite;
use Data::Dumper;
use strict;

# app id and destination email go below

my %apps = ( 'XXXXXX' => 'My App 1', 
             'YYYYYY' => 'App_2',    
             'ZZZZZZ'=> 'App_3',
);

my %emails = ( 'XXXXXX' => 'devops@example.com',
               'YYYYYY' => 'devops@example.com',
               'ZZZZZZ' => 'devops@example.com',
);


foreach my $app ( sort keys %apps ) {

my $t_url='https://rpm.newrelic.com/session';

my $login='apiuser@example.com';
my $password='devops';
my $submit_value='Login_submit';

my $acctId = 'NNNNNN';

# No mods should be needed below

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)");

$ua->cookie_jar(HTTP::Cookies->new(file => "cookies.nr.txt", autosave => 1, ignore_discard => 1));

my $content = $ua->request(POST $t_url , [ 'login[email]' => $login , 'login[password]' => $password, loginSubmit => $submit_value ] )->as_string;

my $url = qq {https://rpm.newrelic.com/accounts/$acctId/applications/$app/transactions?tw[dur]=last_24_hours};
$content = $ua->request(GET $url )->as_string;

$content =~ m/window._token\s=\s\'(.*)\'/;
my $token = $1;
#print "DEBUG: $token\n";


# send the tokenized ajax request for the content we want
my $post_url = qq {https://rpm.newrelic.com/accounts/$acctId/applications/$app/transaction_traces/search_results};

my $headers = new HTTP::Headers(
    'X-Csrf-Token' => $token,
    'X-Requested-With' => 'XMLHttpRequest',
    'Accept' => 'text/html, */*; q=0.01',
    'Accept-Language' => 'en-US,en;q=0.5',
);

my $request = new HTTP::Request( "POST", $post_url, $headers );

my $payload = 'transactions_page=1&include_more_browser_traces=0&transaction_trace_limit=100';
$request->content($payload);
$request->content_type('application/x-www-form-urlencoded; charset=UTF-8');

my $response = $ua->request($request);
$content  = $response->content;

#print Dumper "$content\n";


$content =~ m/<thead>(.*)<\/table>/gs;
my $table = $1;
$table =~ s/<span>/<p>/g;
$table =~ s/<\/span>/<\/p>/g;

my $baseurl = "https://rpm.newrelic.com/accounts/$acctId/applications/$app/transactions";
$table =~ s/href=\'/href=\'$baseurl/g;

my $output;
$output .=  "<table>\n";
my @table = split('\n', $table);
foreach my $line (@table)
{
next if $line =~ /sort_order/;
$output .= "$line\n";
}
$output .= "</table>\n";

#print Dumper "$output\n";
#exit 0;

# Generate the Email

### Create a new multipart message:
    my $msg = MIME::Lite->new(
        From    => 'New Relic Reports <devops@example.com>',
        To      => $emails{$app},
        Subject => "[New Relic]: Daily Slow Transactions report for $apps{$app}",
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
