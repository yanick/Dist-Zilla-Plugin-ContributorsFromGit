package Dist::Zilla::Plugin::ContributorsFromGit;

# ABSTRACT: Populate your 'CONTRIBUTORS' POD from the list of git authors

use utf8;
use v5.10;

use Reindeer;
use Encode qw(decode_utf8);
use autobox::Core;
use autobox::Junctions;
use File::Which 'which';
use List::AllUtils qw{ apply max uniq };
use File::ShareDir::ProjectDistDir;
use YAML::Tiny;
use Path::Class;

use autodie 'system';
use IPC::System::Simple ( ); # explict dep for autodie system

use aliased 'Dist::Zilla::Stash::PodWeaver';

with
    'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::RegisterStash',
    'Dist::Zilla::Role::MetaProvider',
    ;

has _contributor_list => (
    is      => 'lazy',
    isa     => 'ArrayRef[Str]',
    builder => sub {
        my $self = shift @_;
        my @authors = $self->zilla->authors->flatten;

        ### and get our list from git, filtering: "@authors"
        my @contributors = uniq
            map  { $self->_contributor_emails->{$_} // $_ }
            grep { $_ ne 'Your Name <you@example.com>'   }
            grep { @authors->none eq $_                  }
            map  { decode_utf8($_)                       }
            map  { chomp; s/^\s*\d+\s*//; $_             }
            `git shortlog -s -e`
            ;

        return \@contributors;
    },
);

has _contributor_emails => (
    is       => 'lazy',
    isa      => HashRef[Str],
    init_arg => undef,

    builder => sub {

        my $mapping = YAML::Tiny
            ->read(
                file(
                    dist_dir('Dist-Zilla-Plugin-ContributorsFromGit'),
                    'author-emails.yaml',
                ),
            )
            ->[0]
            ;

        my $_map_it = sub {
            my ($canonical, @alternates) = @_;
            return ( map { $_ => $canonical } @alternates );
        };

        return {
            map { $_map_it->($_ => $mapping->{$_}->flatten) }
            $mapping->keys->flatten
        };
    },
);

sub before_build {
    my $self = shift @_;

    # skip if we can't find git
    unless (which 'git') {
        $self->log('The "git" executable has not been found');
        return;
    }

    # XXX we should also check here that we're in a git repo, but I'm going to
    # leave that for the git stash (when it's not vaporware)

    ### get our stash, config...
    my $stash   = $self->zilla->stash_named('%PodWeaver');
    do { $stash = PodWeaver->new; $self->_register_stash('%PodWeaver', $stash) }
        unless defined $stash;
    my $config       = $stash->_config;
    my @contributors = $self->_contributor_list->flatten;

    my $i = 0;
    do { $config->{"Contributors.contributors[$i]"} = $_; $i++ }
        for @contributors;

    # add contributor names as stopwords
    $i = 0;
    my @stopwords = uniq
        apply { split / /        }
        apply { /^(.*) <.*$/; $1 }
        @contributors
        ;
    do { $config->{"StopWords.include[$i]"} = $_; $i++ }
        for @stopwords;

    return;
}

sub metadata {
    my $self = shift @_;
    my $list = $self->_contributor_list;
    return @$list ? { 'x_contributors' => $list } : {};
}

__PACKAGE__->meta->make_immutable;
!!42;
__END__

=for :stopwords zilla BeforeBuild metacpan shortlog committer mailmap

=for Pod::Coverage before_build metadata

=head1 SYNOPSIS

    ; in your dist.ini
    [ContributorsFromGit]

    ; in your weaver.ini
    [Contributors]

=head1 DESCRIPTION

This plugin makes it easy to acknowledge the contributions of others by
populating a L<%PodWeaver|Dist::Zilla::Stash::PodWeaver> stash with the unique
list of all git commit authors reachable from the current HEAD.

=head1 OVERVIEW

On collecting the unique list of reachable commit authors from git, we search
and remove any git authors from the list of authors L<Dist::Zilla> knows
about.  We then look for a stash named C<%PodWeaver>; if we don't find one
then we create an instance of L<Dist::Zilla::Stash::PodWeaver> and register it
with our zilla instance.  Then we add the list of contributors (the filtered
git authors list) to the stash in such a way that
L<Pod::Weaver::Section::Contributors> can find them.

Note that you do not need to have the C<%PodWeaver> stash created; it will be
added if it is not found.  However, your L<Pod::Weaver> config (aka
c<weaver.ini>) must include the
L<Contributors|Pod::Weaver::Section::Contributors> section plugin.

=head2 Dist::Zilla Phase

This plugin runs during the L<BeforeBuild|Dist::Zilla::Role::BeforeBuild>
phase.

=head2 Metadata Keys

The list of contributors is also added to distribution metadata under the custom
C<x_contributors> key.  (e.g. in C<META.yml>, C<META.json>, etc)

If you have duplicate contributors because of differences in committer name
or email you can use a C<.mailmap> file to canonicalize contributor names
and emails.  See L<git help shortlog|git-shortlog(1)> for details.

=head1 METACPAN CONTRIBUTOR MATCHING

L<MetaCPAN|http://metacpan.org> will attempt to match a contributor address
back to a PAUSE account.  However, it (currently) can only do that if the
contributor's email address is their C<PAUSEID@cpan.org> address.  There are
two mechanisms for helping to resolve this, if your commits are not using this
address.

Both of these approaches have pros and cons that have been discussed at
levels nearing the heat brought to any discussion of religion, homosexuality,
or Chief O'Brien's actual rank at any ST:TNG convention.  However, they both
have the advantage of *working*, and through different modes of action.  You
are free to use one, both or neither.  These are only important if you're not
committing with your C<@cpan.org> email address B<and> want the MetaCPAN to
link to your author page from the page of the package you contributed to.

=head2 Using a .mailmap file

See C<git help shortlog> for help on how to use this.  A C<.mailmap> file must
be maintained in each repository using it.

=head2 Globally, via the authors mapping

This package contains a YAML file containing a mapping of C<@cpan.org> author
addresses; this list is consulted while building the contributors list, and
can be used to replace a non-cpan.org address with one.

To add to or modify this mapping, please feel free to fork, add your alternate
email addresses to C<share/author-emails.yaml>, and submit a pull-request for
inclusion.  It'll be merged and released; as various authors update their set
of installed modules and cut new releases, the mapping will appear.

=head1 SEE ALSO

L<Pod::Weaver::Section::Contributors>

L<Dist::Zilla::Stash::PodWeaver>

=cut
