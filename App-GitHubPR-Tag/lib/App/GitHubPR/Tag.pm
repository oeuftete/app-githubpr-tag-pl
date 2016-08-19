package App::GitHubPR::Tag;

use Moose;
use Net::GitHub;

with 'MooseX::Getopt';

# Options
has 'mergeable' =>
    ( is => 'rw', isa => 'Bool', predicate => 'has_mergeable' );
has 'dry-run' => ( is => 'rw', isa => 'Bool', accessor => 'dry_run' );
has 'repo-user' =>
    ( is => 'rw', isa => 'Str', required => 1, accessor => 'repo_user' );
has 'repo-name' =>
    ( is => 'rw', isa => 'Str', required => 1, accessor => 'repo_name' );
has 'tag' => ( is => 'rw', isa => 'Str', required => 1 );

# Internal
has '_github' => (
    is      => 'ro',
    isa     => 'Net::GitHub::V3',
    lazy    => 1,
    default => sub {
        Net::GitHub::V3->new(
            access_token => $ENV{GITHUB_ACCESS_TOKEN},
            api_throttle => 0,
        );
    },
    traits => ['NoGetopt'],
);

has 'pull_request' => (
    is      => 'rw',
    isa     => 'Net::GitHub::V3::PullRequests',
    builder => '_build_pull_request',
    handles => ['pull'],
    traits  => ['NoGetopt'],
);

sub _build_pull_request {
    my $self = shift;
    $self->_github->pull_request;
}

has '_prs' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build__prs',
    traits  => ['NoGetopt'],
);

sub _build__prs {
    my $self = shift;
    $self->pull_request->pulls( { state => 'open' } );
}

#  TODO: Why is this needed?  If I put the set_default_user_repo method call
#  in the builder, the user and name attributes are randomly undef.
sub init_pull_request {
    my $self = shift;
    $self->pull_request->set_default_user_repo( $self->repo_user,
        $self->repo_name );
}

1;
