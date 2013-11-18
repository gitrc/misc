#!/usr/bin/perl -w
#
#
# Pull the HTML table from New Relic with slow queries for the last 24 hours for a specific application and email it
#
# Rod Cordova (@gitrc)
#
# June 2013
#

use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use MIME::Lite;
use strict;

# combine the two hashes below as in newrelic_reports_errors.pl

# appid to name hash
my %apps = ( 'NNNNNN' => 'My App Name', 
             'NNNNNN' => 'My Other App',    
);

# app id to email hash
my %emails = ('NNNNNN' => 'email@host',
		'NNNNNN' => 'email@host',
);

my $accountId = 'NNNNNN';

# No mods should be needed below

foreach my $app ( sort keys %apps ) {

my $t_url='https://rpm.newrelic.com/session';

my $login='apiuser@example.com';
my $password='hellonewrelic';
my $submit_value='Login_submit';


my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)");

$ua->cookie_jar(HTTP::Cookies->new(file => "cookies.nr.txt", autosave => 1, ignore_discard => 1));

my $content = $ua->request(POST $t_url , [ 'login[email]' => $login , 'login[password]' => $password, loginSubmit => $submit_value ] )->as_string;

my $url = qq {https://rpm.newrelic.com/accounts/$accounId/applications/$app/databases/load_sql_traces?limit=25};

my $time = qq {https://rpm.newrelic.com/set_time_window?back=https%3A%2F%2Frpm.newrelic.com%2Faccounts%2F114589%2Fapplications%2F$app%2Fdatabases&tw%5Bfrom_local%5D=true&tw%5Bdur%5D=last_24_hours};

$ua->request(GET $time)->as_string;

$content = $ua->request(GET $url )->as_string;

$content =~ m/<thead>(.*)<\/table>/gs;
my $table = $1;
$table =~ s/<span>/<p>/g;
$table =~ s/<\/span>/<\/p>/g;

my $baseurl = "https://rpm.newrelic.com/accounts/$accountId/applications/$app/databases";

$table =~ s/#id=/$baseurl#id=/g;
my $remove = qq{<td class=\'disrespect_visited\' colspan=\'3\'><a href="#" class="show_more">Show more SQL traces</a></td>};

$table =~ s/$remove//;

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
        From    => 'New Relic Reports <nobody@example.com>',
        To      => $emails{$app},
	Cc	=> 'devops@example.com',
        Subject => "[New Relic]: Daily Slow Query report for $apps{$app}",
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
