package Pequod;
use Dancer ':syntax';

use Crypt::Simple qw(encrypt decrypt);
use HTTP::Request;
use List::UtilsBy qw(nsort_by);
use LWP::UserAgent;

my $base_url = "http://apps.rackspace.com/versions/webmail/8.6.0-ALPHA/ext/api/rest.php?0/user";

before sub {
    if (! session('email') && request->path_info !~ m{^/login}) {
        request->path_info('/login');
    }
};

get '/login' => sub { template 'login' };

post '/login' => sub {
    my $email = params->{email};
    my $password = params->{password};
    my $res = agent($email, $password)->get($base_url);
    if ($res and $res->status_line =~ /^2/) {
        session email => params->{email};
        session password => encrypt params->{password};
        redirect uri_for '/';
    } else {
        session email => undef;
        redirect uri_for '/login', { failed => 1 };
    }
};

get '/logout' => sub {
    session email => undef;
    my $uri = request->base;
    redirect uri_for '/';
};

get '/' => sub {
    my $email = session 'email';
    my $res = agent()->get(notes_url());
    my $data = from_json $res->content;
    my @notes = reverse nsort_by { $_->{metadata}{modified} } @{$data->{notes}};
    template notes => {
        notes => \@notes,
        data_url => 'data-url="#/"',
        #params->{is_redirect} ? (data_url => 'data-url="#/"') : (),
    }
};

get '/notes/:note_id' => sub {
    my $email = session 'email';
    my $note_id = params->{note_id};
    my $res = agent()->get(notes_url() . "/$note_id");
    my $data = eval { from_json $res->content };
    if ($@) {
        status 500;
        return 'could not parse json from note: ' . $res->content;
    }
    template edit_note => {
        note => $data,
    }
};

get '/add' => sub {
    template edit_note => {
        is_new => 1,
    }
};

post '/notes' => sub {
    debug scalar params;
    my $note_id = params->{note_id};
    my $subject = params->{subject};
    my $content = params->{content};
    if (params->{delete_note}) {
        my $req = HTTP::Request->new(DELETE => notes_url() . "/$note_id");
        my $res = agent()->request($req);
    } elsif (params->{save_note}) {
        my $req = HTTP::Request->new(POST => notes_url());
        $req->header(Content_Type => 'application/json');
        my $json = to_json {
            subject => $subject,
            content => $content,
        };
        $req->content($json);
        my $res = agent()->request($req);
    } elsif (params->{edit_note}) {
        my $req = HTTP::Request->new(PUT => notes_url() . "/$note_id");
        $req->header(Content_Type => 'application/json');
        my $json = to_json {
            subject => $subject,
            content => $content,
        };
        $req->content($json);
        my $res = agent()->request($req);
    }
    redirect uri_for '/';
};

sub notes_url {
    my $email = session 'email';
    return "$base_url/$email/notes";
}

sub agent {
    my ($email, $password) = @_;
    if (not $email) {
        $email = session 'email';
        $password = decrypt(session 'password');
    }
    my $agent = LWP::UserAgent->new();
    $agent->credentials('apps.rackspace.com:80', 'webmail', $email, $password);
    $agent->default_header(Accept => 'application/json');
    return $agent;
}

true;
