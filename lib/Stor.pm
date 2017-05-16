package Stor;

our $VERSION = '0.2.0';


use Mojo::Base -base;
use Syntax::Keyword::Try;
use Path::Tiny;
use List::Util qw(shuffle min max);
use List::MoreUtils qw(first_index);
use Digest::SHA qw(sha256_hex);

use feature 'signatures';
no warnings 'experimental::signatures';

has 'storage_pairs';

sub about ($self, $c) {
    $c->render(status => 200, text => "This is " . __PACKAGE__ . " $VERSION");
}

sub status ($self, $c) {
    for my $storage ($self->_get_shuffled_storages()) {
        die "Storage $storage isn't a directory"
            if !path($storage)->is_dir();

        my $mountpoint = qx(df --output=target $storage | tail -n 1);
        chomp $mountpoint;
        die "Storage $storage is not mounted"
            if $mountpoint eq '/';
    }

    $c->render(status => 200, text => 'OK');
}

sub get ($self, $c) {
    my $sha = $c->param('sha');
    try {
        die "Given hash '$sha' isn't SHA256\n" if $sha !~ /^[A-Fa-f0-9]{64}$/;
        my $paths = $self->_lookup($sha);
        die "File '$sha' not found" if !@$paths;
        my $path = $paths->[0];
        $c->res->headers->content_length(-s $path);
        $self->_stream_found_file($c, $path);
    }
    catch {
        $c->app->log->debug("$@");
        $c->render(status => 404, text => $@);
    }
}

sub post ($self, $c) {
    my $sha  = $c->param('sha');
    my $file = $c->req->content->asset;

    if ($sha !~ /^[A-Fa-f0-9]{64}$/) {
        $c->render(status => 412, text => "Givenl hash '$sha' isn't sha256");
        return
    }

    if (my @paths = @{$self->_lookup($sha, 1)}) {
        $c->render(status => 200, json => \@paths);
        return
    }

    my $content_sha = sha256_hex($file->slurp());
    if ($sha ne $content_sha) {
        $c->render(status => 412, text =>
            "Content sha256 $content_sha doesn't match given sha256 $sha");
        return
    }

    try {
        my $storage_pair = $self->pick_storage_pair_for_file($file);
        my $paths = $self->save_file($file, $sha, $storage_pair);
        $c->render(status => 201, json => $paths);
    }
    catch {
        if ($@ =~ /Not enough space on storages/) {
            $c->render(status => 507, text => $@);
            return
        }
        $c->render(status => 500, text => $@);
        return
    }
}

sub pick_storage_pair_for_file ($self, $file) {
    my @free_space = map {$_ - $file->size()}
                        @{ $self->get_storages_free_space() };
    die 'Not enough space on storages' if !grep {$_ > 0} @free_space;

    my $index = 0;
    if (!grep {$_ > 1_000_000_000} @free_space) {
        # we are short on space, pick the storage with most space
        $index = first_index {$_ == max(@free_space)} @free_space;
    }
    else {
        # there are several having enough space
        # pick randomly transforming space to probabilities
        my @probabilities = map { $_ / sum(@free_space) } @free_space;
        my $random = rand();

        my $cumulative_probability = 0;
        for my $prob (@probabilities) {
            $cumulative_probability += $prob;
            last if $random < $cumulative_probability;
            $index++
        }
    }

    return $self->storage_pairs->[$index]
}

sub get_storages_free_space($self) {
    my @free_space = map {min map {$self->get_storage_free_space($_)} @$_}
                        @{$self->storage_pairs};

    return \@free_space
}

sub get_storage_free_space($self, $storage) {
    return int(qx(df --output=avail $storage | tail -n 1))
}

sub save_file ($self, $file, $sha, $storage_pair) {
    my @paths = map { path($_, $self->_sha_to_filepath($sha)) } @$storage_pair;
    $_->parent->mkpath() for @paths;
    my $first_path = shift @paths;
    $file->move_to($first_path);
    $first_path->copy($_) for @paths;
}

sub _lookup ($self, $sha, $return_all_paths = '') {
    my @paths;
    for my $storage ($self->_get_shuffled_storages()) {
        my $file_path = path($storage, $self->_sha_to_filepath($sha));
        if ($file_path->is_file) {
            push @paths, $file_path;
            return \@paths if !$return_all_paths
        }
    }

    return \@paths
}

sub _sha_to_filepath($self, $sha) {
    my $filename = uc($sha) . '.dat';
    my @subdir = unpack 'A2A2A2', $filename;

    return join '/', @subdir, $filename
}


sub _stream_found_file($self, $c, $path) {

    my $fh = $path->openr_raw();

    my $drain; $drain = sub {
        my ($c) = @_;

        my $chunk;
        if (read($fh, $chunk, 1024 * 1024) == 0) {
            close($fh);
            $drain = undef;
        }

        $c->write($chunk, $drain)
    };
    $c->$drain;
}

sub _get_shuffled_storages($self) {

    my (@storages1, @storages2);
    for my $pair (shuffle @{$self->storage_pairs}) {
        my $rand = int(rand(2));
        push @storages1, $pair->[$rand];
        push @storages2, $pair->[1 - $rand];
    }

    return @storages1, @storages2
}


1;
__END__


=encoding utf-8

=head1 NAME

Stor - Save/retrieve a file to/from primary storage

=head1 SYNOPSIS

    # retrieve a file
    curl http://stor-url/946a5ec1d49e0d7825489b1258476fdd66a3e9370cc406c2981a4dc3cd7f4e4f

    # store a file
    curl -X POST --data @my_file http://stor-url/946a5ec1d49e0d7825489b1258476fdd66a3e9370cc406c2981a4dc3cd7f4e4f

=head1 DESCRIPTION

Stor is an HTTP API to primary storage. You provide a SHA256 hash and get the file contents, or you provide a SHA256 hash and a file contents and it gets stored to primary storages.

=head2 Service Responsibility

=over

=item provide HTTP API

=item redundancy support

=item resource allocation

=back

=head2 API

=head3 HEAD /:sha

=head3 GET /:sha

=head4 200 OK

File exists

Headers:

    Content-Length - file size of file

GET return content of file in body

=head4 404 Not Found

Sample not found


=head3 POST /:sha

save sample to n-tuple of storages

For authentication use Basic access authentication

compare SHA and sha256 of file

=head4 200 OK

file exists

Headers:

Body:

    {
        "locations": {
            "nfs":  ["server1:/some_path/to/file", "server2:/another_path/to/file"],
            "cifs": ["\\\\server1\\share\\path\\to\\file", "\\\\server2\\share\\path\\to\\file"]
        }
    }

=head4 201 Created

file was added to all storages

Body:

    {
        "locations": {
            "nfs":  ["server1:/some_path/to/file", "server2:/another_path/to/file"],
            "cifs": ["\\\\server1\\share\\path\\to\\file", "\\\\server2\\share\\path\\to\\file"]
        }
    }

=head4 401 Unauthorized

Bad authentication

=head4 412 Precondition Failed

content mismatch - sha256 of content not equal SHA

=head4 507 Insufficient Storage

There is not enough space on storage to save the file.

Headers:

    Content-Sha-256 - sha256 of content


=head3 GET /status

=head4 200 OK

all storages are available

=head4 503

some storage is unavailable

=head3 GET /storages

return list of storages and disk usage

=head2 Redundancy Support

for redundancy we need support defined n-tuple of storages

n-tuple of storages must works minimal 1 for GET and all for POST

pseudo-example of n-tuple of storages definition:

    [
        ["storage1", "storage2"],
        ["storage3", "storage4"]
    ]

in pseudo-example case we must new sample save to storage1 and storage2 or storage3 and storage4

=head2 Resource Allocation

save samples to n-tuple of storages with enough of resources => service responsibility is check disk usage

nice to have is balanced samples to all storages equally



=head1 LICENSE

Copyright (C) Avast Software

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Miroslav Tynovsky E<lt>tynovsky@avast.comE<gt>

=cut

