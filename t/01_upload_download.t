#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Mojo::UserAgent;
use Digest::SHA qw(sha256_hex);
use Path::Tiny;
use Syntax::Keyword::Try;
use Cpanel::JSON::XS;

my @storages = (
    Path::Tiny->tempdir(),
    Path::Tiny->tempdir(),
    Path::Tiny->tempdir(),
    Path::Tiny->tempdir(),
);

my $cfg = {
    storage_pairs => [
        [ $storages[0]->stringify(), $storages[1]->stringify(), ],
        [ $storages[2]->stringify(), $storages[3]->stringify(), ],
    ],
    secret => 'test secret',
};

my $cfg_file = Path::Tiny->tempfile();

$cfg_file->spew(encode_json($cfg));

my $pid = fork();
die "fork() failed: $!" unless defined $pid;

if ($pid) { # parent
    sleep 2;
    try {
        my $ua = Mojo::UserAgent->new();
        my $content = 'Content!' . rand;
        my $sha = sha256_hex($content);

        my $tx = $ua->post("http://localhost:3000/$sha" => {} => $content);
        is($tx->res->code, 201, 'file created');
        my $received = $ua->get("http://localhost:3000/$sha")->result->body;
        is($received, $content, 'received what we had sent');
    }
    catch {
        fail("an error caught: $@");
    }

    kill 'HUP', -$pid; #negative pid to kill whole process tree
    waitpid $pid, 0
}
else {      # child
    setpgrp(0, 0); #process group (to enable killing whole process tree)
    exec "CONFIG_FILE=$cfg_file PERL5LIB=\$PWD/lib:\$PERL5LIB script/stor daemon";
    die 'Exec failed';
}
