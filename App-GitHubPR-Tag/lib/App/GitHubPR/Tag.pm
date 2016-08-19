package App::GitHubPR::Tag;

use feature qw/say/;

use Moose;
use Net::GitHub;
use Try::Tiny::Retry ':all';

with 'MooseX::Getopt';

# Options
has 'dry-run' => ( is => 'rw', isa => 'Bool', accessor => 'dry_run' );
has 'repo-user' =>
    ( is => 'rw', isa => 'Str', required => 1, accessor => 'repo_user' );
has 'repo-name' =>
    ( is => 'rw', isa => 'Str', required => 1, accessor => 'repo_name' );
has 'tag' => ( is => 'rw', isa => 'Str', required => 1 );

# Internal
has 'github' => (
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

has 'pr_api' => (
    is      => 'rw',
    isa     => 'Net::GitHub::V3::PullRequests',
    default => sub {
        my $self = shift;
        $self->github->pull_request;
    },
    handles => ['pull'],
    traits  => ['NoGetopt'],
);

has 'issues_api' => (
    is      => 'rw',
    isa     => 'Net::GitHub::V3::Issues',
    default => sub {
        my $self = shift;
        $self->github->issue;
    },
    handles =>
        [ 'delete_issue_label', 'issue_labels', 'replace_issue_label' ],
    traits => ['NoGetopt'],
);

has '_prs' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build__prs',
    traits  => ['NoGetopt'],
);

sub _build__prs {
    my $self = shift;
    $self->pr_api->pulls( { state => 'open' } );
}

#  TODO: Why is this needed?  If I put the set_default_user_repo method call
#  in the builder, the user and name attributes are randomly undef.
sub init_repo {
    my $self = shift;
    $self->pr_api->set_default_user_repo( $self->repo_user,
        $self->repo_name );
    $self->issues_api->set_default_user_repo( $self->repo_user,
        $self->repo_name );
}

sub pr_merge_state {
    my $self      = shift;
    my $pr_number = shift;
    my $pr_merge_state;

    retry {
        $pr_merge_state = $self->pull($pr_number)->{mergeable_state};
        if ( $pr_merge_state eq 'unknown' ) {
            die 'unknown status';
        }
    }
    retry_if {/unknown status/}
    delay {    # 10 retries, 1s wait
        return if $_[0] >= 10;
        sleep 1;
    }
    catch { warn "Status for $pr_number unknown: will be ignored." };

    return $pr_merge_state;
}

sub update_pr_tags {
    my $self = shift;
    for my $pr ( @{ $self->_prs } ) {
        my $pr_number      = $pr->{number};
        my $pr_title       = $pr->{title};
        my $pr_merge_state = $self->pr_merge_state($pr_number);

        return if $pr_merge_state eq 'unknown';

        my @pr_labels = map { $_->{name} } $self->issue_labels($pr_number);

        my $tag = $self->tag;

        say "$pr_number: $pr_title: $pr_merge_state";
        if ( ( $pr_merge_state ne 'dirty' ) && ( grep {/$tag/} @pr_labels ) )
        {
            say "  Removing [$tag] on [$pr_number]...";
            if ( !$self->dry_run ) {
                $self->delete_issue_label( $pr_number, $tag );
            }
        }

        if ( ( $pr_merge_state eq 'dirty' ) && ( !grep {/$tag/} @pr_labels ) )
        {
            say "  Adding [$tag] on [$pr_number]...";
            if ( !$self->dry_run ) {
                $self->replace_issue_label( $pr_number,
                    [ @pr_labels, $tag ] );
            }
        }
    }
}

1;
