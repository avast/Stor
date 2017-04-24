#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Mojo::UserAgent;
use Digest::SHA qw(sha256_hex);
use Path::Tiny;
use Syntax::Keyword::Try;

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

    kill 'TERM', $pid;
}
else {      # child
    exec 'CONFIG_FILE=$PWD/t/stor-config.json PERL5LIB=$PWD/lib script/stor daemon';
    die 'Exec failed';
}
