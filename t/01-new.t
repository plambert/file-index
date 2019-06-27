#!/usr/bin/env perl

use Modern::Perl qw/2016/;
use Test::More tests => 1;

use lib './lib';
use File::Index;
use Try::Tiny;

my $index;

try {
  $index=File::Index->new;
}
catch {
  diag "failed to create File::Index object: $_\n";
};

ok defined($index), "create File::Index object";
