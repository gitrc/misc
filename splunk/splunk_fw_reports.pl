#!/usr/bin/perl -w
#
#
# Run Splunk searches (Cisco Security Suite app) manually (free version of Splunk does not have scheduler)
# Takes a given saved search, runs it, converts CSV to HTML and emails the output
#
# Tried to use XML::Feed::Atom but Splunk API is not pure Atom
# evidence @ https://gist.github.com/2892bbd5aeaeaf39534c
#
# Rod Cordova (@gitrc)
#
# August 2012
#

use strict;
use HTML::Template;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;
use Text::CSV;

my $ua = LWP::UserAgent->new();

# Saved search name and destination email go below

my %searches = ( 'Report Name Goes Here' => 'destination_email@addr', );

my $linkurl = 'https://splunk.fqdn/en-US/app/Splunk_CiscoSecuritySuite/flashtimeline?s=';

#
## No modifications should be necessary from this point forward
###


my $baseurl =
'http://localhost:8000/en-US/app/Splunk_CiscoSecuritySuite/flashtimeline?s=';
my $apiurl =
'https://localhost:8089/servicesNS/nobody/Splunk_CiscoSecuritySuite/saved/searches/';
foreach my $search ( sort keys %searches ) {

    my $escaped = uri_escape($search);
    my $request = HTTP::Request->new( GET => $apiurl . $search, );

    my $response = $ua->request($request);

    if ( !$response->is_success() ) {
        die('Failed to connect with Splunk');
    }
    my $dump = $response->content;

    $dump =~
m/\<entry\>.*\<title\>(.*)\<\/title\>.*\<s:key\sname=\"search\"\>.*\[(.*)\]\]\>\<\/s:key\>.*\<s:key\sname/s;
    my $title  = $1;
    my $params = $2;

    $request = HTTP::Request->new( POST => $apiurl . $escaped . '/dispatch', );

    $response = $ua->request($request);
    if ( !$response->is_success() ) {
        die('Failed to connect with Splunk');
    }
    my $dispatch = $response->content;

    $dispatch =~ m/\<sid\>(.*)\<\/sid\>/g;
    my $jobid = $1;
    my $count = 0;
    while () {
        die "ERROR: Search runtime took greater than 60 minutes"
          if ( $count >= 720 );
        sleep 5;
        $request =
          HTTP::Request->new( GET =>
"https://localhost:8089/servicesNS/admin/search/search/jobs/$jobid"
          );
        $response = $ua->request($request);
        if ( !$response->is_success() ) {
            die('Failed to connect with Splunk');
        }
        my $done = $response->content;
        last if ( $done =~ m/\<s:key\sname=\"isDone\"\>1\<\/s:key\>/g );
        $count++;
    }

    $request =
      HTTP::Request->new( GET =>
"https://localhost:8089/servicesNS/admin/search/search/jobs/$jobid/results?output_mode=csv",
      );

    $response = $ua->request($request);
    if ( !$response->is_success() ) {
        die('Failed to connect with Splunk');
    }
    my $result = $response->content;
    my @result;
#print "run: curl -k https://localhost:8089/servicesNS/admin/search/search/jobs/$jobid/results?output_mode=csv\n";
    open my $fh, '<', \$result or die $!;

    my $csv = Text::CSV->new( { sep_char => ',' } );
    while ( my $row = $csv->getline($fh) ) {
        $csv->combine(@$row);
        push @result, $csv->string();
    }

    map { $_ =~ s/\"//g; $_ } @result;

    my @table;
    foreach my $line (@result) {
        chomp $line;
        my @row = map { { cell => $_ } } split( /,/, $line );
        push @table, { row => \@row };
    }
    my $tmpl = HTML::Template->new( scalarref => \get_tmpl() );
    $tmpl->param( table => \@table );
    my $output =
qq {Name: $title<br>Query Terms: $params<br>Link: <a href="$linkurl$title">Run Report</a><br><br><table border=1>};
    $output .= $tmpl->output;
    $output .= '</table>';

    # Generate the Email
    use MIME::Lite;

### Create a new multipart message:
    my $msg = MIME::Lite->new(
        From    => 'splunk <splunk@example.com>',
        To      => $searches{$search},
        Subject => "Splunk Report: $title",
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

sub get_tmpl {
    return <<TMPL
<TMPL_LOOP table>
<tr>
<TMPL_LOOP row>
<td><TMPL_VAR cell></td></TMPL_LOOP>
</tr></TMPL_LOOP>
TMPL
}
