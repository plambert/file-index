#!/usr/bin/env perl

use Modern::Perl qw/2016/;
use Test::More tests => 6;
use lib './lib';
use File::Index;
use Path::Tiny;
use Try::Tiny;

my $index;
my $dbfile=Path::Tiny->tempfile;
my $tempdir=Path::Tiny->tempdir;
my $file=path $tempdir, "testfile.txt";
my $file_content="this is a test\n";

try {
  $index=File::Index->new(dbfile => $dbfile);
}
catch {
  diag "failed to create File::Index object: $_\n";
  fail "create File::Index object";
};

my $time=time;
$file->spew($file_content);

$file->chmod(0000);

$index->add($file);

my $result;
open my $sql, '-|', 'sqlite3', '-line', $dbfile, 'SELECT * FROM entries;' or die $!;
while(<$sql>) {
  if (m{^\s*(\S+)\s=\s(.*)$}) {
    $result->{$1}=$2;
  }
  else {
    diag "cannot parse output: $_";
    $result->{__FAILURE__}+=1;
  }
}
close $sql;

if ($result->{__FAILURE__}) {
  BAIL_OUT "there were errors parsing the sqlite3 output";
  exit;
}

diag "output:";
diag sprintf "%s = %s", $_, $result->{$_} for sort keys %$result;

is $result->{filename}, $file->basename, "correct file name";
is $result->{filepath}, $file->realpath->parent, "correct file path";
is $result->{size}, length($file_content), "correct file size";
is $result->{mode}, 32768, "correct file mode";
ok $result->{index_time} >= $time, "correct index time";
is $result->{mtime}, $file->stat->mtime, "correct mtime";
