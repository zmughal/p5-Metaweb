package Metaweb;

use warnings;
use strict;

use base qw(Class::Accessor);
use URI::Escape;
use LWP::UserAgent;
use JSON;
use Metaweb::Result;

__PACKAGE__->mk_accessors(qw(
    username
    password
    server
    login_url
    query_url
    credentials
    ua
    raw_result
    err_code
    err_message
));

=head1 NAME

Metaweb - Perl interface to the Metaweb/Freebase API

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Metaweb;

    my $mw = Metaweb->new({
        username => $username,
        password => $password
    });
    $mw->login();
    my $result = $mw->query($mql);

=head1 DESCRIPTION

This is a Perl interface to the Metaweb database, best known through the
application Freebase (http://freebase.com).  Freebase is currently in
alpha release, with world-readable data but requiring an invitation and
login to be able to update/write data.

This module is very much alpha code.  It has lots of stuff not
implemented and will undergo significant changes.  Breakage may occur
between versions, so consider yourself warned.

=head2 new 

Instantiate a Metaweb client object.  Takes various options including:

=over 4

=item username

The username to login with

=item password

The password to login with

=back

=cut

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, $class;
    $self->username($args->{username});
    $self->password($args->{password});
    $self->server($args->{server}       || 'http://www.freebase.com');
    $self->query_url($args->{query_url} || '/api/service/mqlread');
    $self->login_url($args->{login_url} || '/api/account/login');;
    return $self;
}

=head2 username()

Get/set default login username.

=head2 password()

Get/set default login password.

=head2 server()

Get/set server to login to.  Defaults to 'http://www.freebase.com'.

=head2 login_url()

Get/set the URL to login to, relative to the server.  Defaults to
'/api/account/login'.

=head2 query_url()

Get/set the URL to perform queries, relative to the server.  Defaults to
'/api/service/mqlread'.

=head2 login()

Perform a login to the Metaweb server and pick up the necessary cookie.
Optionally takes a hashref of arguments including username, password,
server, and login_url which will be used only for this login and not set
on the object.  (Generally you'll want to set those details when you
create the metaweb object.)

=cut

sub login {
    my ($self, $args) = @_;

    my $username = $args->{username}   || $self->username()  || warn "Username not specified";
    my $password = $args->{password}   || $self->password()  || warn "Password not specified";
    my $server = $args->{server}       || $self->server()    || warn "Server not specified";
    my $login_url = $args->{login_url} || $self->login_url() || warn "Login URL not specified";

    print "Server: $server\n";
    print "Login URL: $login_url\n";

    unless ($self->ua()) {
        $self->ua(LWP::UserAgent->new());
    }
    my $res = $self->ua->post("$server$login_url", {username=>$username,password=>$password});

    my $raw = $res->header('Set-Cookie'); 
    unless ($raw) {
        warn "Couldn't login to $server";
        return undef;
    }
    my @cookies = split(', ',$raw);        # Break cookies at commas

    # Each cookie is broken into fields with semicolons. 
    # We want the only first field of each cookie
    my $credentials = ''; # We'll accumulate login credentials here
    for my $cookie (@cookies) {                        # Loop through cookies
        my @parts = split(";", $cookie);               # Split each one on ;
        $credentials = $credentials . $parts[0] . ';'; # Remember first part
    }
    chop($credentials);   # Remove trailing semicolon
    $self->credentials($credentials);
    $self->ua->default_header('Cookie' => $credentials);

    return 1;
}

=head2 query()

Perform a MQL query.  Takes a query as a Perl data structure that's
converted to JSON using the L<JSON> module's C<objToJson()> method.
The MQL envelope will automatically be put around the query.

=cut

sub query {
    my ($self, $args) = @_;

    warn "Query name not specified" unless $args->{name};
    warn "Query not specified"      unless $args->{query};

    $args->{query} = objToJson($args->{query});
    my $raw = $self->json_query($args);
    my $outer = jsonToObj($raw);
    my $inner = $outer->{$args->{name}};
    
    if ($inner->{code} !~ m|^/api/status/ok|) {  # If the query was not okay
        my $err = $inner->{messages}[0];
        $self->err_code($err->{code});
        $self->err_message($err->{message});
        return undef;
    }

    my $result = Metaweb::Result->new($inner->{result});
    return $result;
}

=head2 json_query

Like C<query()> only it accepts and returns JSON, without converting
to/from Perl.  The expected JSON format is more or less everything that
follows "query:" in the MQL, i.e.:

    my $json_query = q({
        "type":"/music/artist",
        "name":"The Police",
        "album":[]
    });

C<raw_result()> is still set as a side effect, but C<error()> is *not*
set, as we'd need to parse the JSON to get at it and the whole point of
this is that it's unparsed.

=cut

sub json_query {
    my ($self, $args) = @_;

    warn "Query name not specified" unless $args->{name};
    warn "Query not specified"      unless $args->{query};

    unless ($self->ua()) {
        $self->ua(LWP::UserAgent->new());
    }

    my $envelope = qq(
    {
      "$args->{name}": {
        "query": $args->{query}
      }
    }
    ); 

    $envelope = uri_escape($envelope);
    my $server    = $args->{server}    || $self->server()    || warn "Server not specified";
    my $query_url = $args->{query_url} || $self->query_url() || warn "Query URL not specified";

    my $url = $server . $query_url . "?queries=" . $envelope;
    my $response = $self->ua->get($url);
    if ($response->is_success()) {
        my $raw = $response->content();
        $self->raw_result($raw);
        return $raw;
    }
}

=head2 raw_result()

The raw JSON from the response.  This is set by both C<query()> and
C<json_query()>.

=head2 err_code()

Set on error by C<query()>.  C<json_query()> doesn't set this; you need
to parse the JSON yourself.

=head2 err_message()

Set on error by C<query()>.  C<json_query()> doesn't set this; you need
to parse the JSON yourself.

=head1 AUTHOR

Kirrily Robert, C<< <skud at cpan.og> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-metaweb at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Metaweb>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Metaweb

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Metaweb>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Metaweb>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Metaweb>

=item * Search CPAN

L<http://search.cpan.org/dist/Metaweb>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to the following people with whom I have discussed Metaweb Perl
APIs recently...

    Hayden Stainsby (CPAN: HDS)
    Kirsten Jones (CPAN: SYNEDRA)

=head1 COPYRIGHT & LICENSE

Copyright 2007 Kirrily Robert, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Metaweb
