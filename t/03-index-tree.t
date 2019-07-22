#!/usr/bin/env perl

# create a file structure in a temp directory, index it to a new db file, and
# verify the results...

use Modern::Perl qw/2016/;
use Test::More;
use lib './lib';
use File::Index;
use Path::Tiny;
use Try::Tiny;
use Digest::MD5 qw/md5_hex/;

my $index;
my $dbfile=Path::Tiny->tempfile;
my $tempdir=Path::Tiny->tempdir;

try {
  $index=File::Index->new(dbfile => $dbfile);
}
catch {
  diag "failed to create File::Index object: $_\n";
  BAIL_OUT "create File::Index object";
};

sub length_for_path {
  my $path=shift;
  my $digest=md5_hex $path;
  my $length=hex substr $digest, 0, 4;
  return $length;
}

sub make_content {
  my $count=shift;
  my @lines;
  for (1..$count) {
    push @lines, "line $_: " . ("blah " x int(rand(40))) . "blah\n";
  }
  return join '', @lines;
}

sub make_file {
  my $dir=path shift;
  my $path=path shift;
  my $content=make_content length_for_path $path->stringify;
  $path=path $dir => $path;
  $path->parent->mkpath unless -d $path->parent;
  $path->spew_raw($content);
}

sub make_dir {
  my $path=path @_;
  $path->mkpath;
}

sub make_tree {
  my $dir=path shift;
  my $count=0;
  while(@_) {
    my $type=shift;
    my $path=shift;
    my $mode=oct shift;
    $count += 1;
    if ($type eq 'file') {
      make_file $dir, $path;
    }
    elsif ($type eq 'dir') {
      make_dir $dir, $path;
    }
    else {
      diag "$0: ${type}: unknown type";
      die;
    }
    path($dir, $path)->chmod($mode);
  }
  return $count;
}

sub test_entry {
  my $index=shift;
  my $path=shift;
  my $entry=$index->by_path($path);
  if (defined $entry) {
    subtest "${path}: check entry", sub {
      plan tests => 7;
      pass "${path}: found entry";
      my $stat=$path->stat;
      is $entry->name, $path->basename, "correct file name";
      is $entry->path, $path->parent, "correct file path";
      is $entry->size, $stat->size, "correct file size";
      is $entry->mode, $stat->mode, "correct file mode";
      ok time - $entry->index_time < 5, "correct index time";
      is $entry->mtime, $stat->mtime, "correct mtime";
    };
  }
  else {
    plan tests => 1;
    fail "${path}: found entry";
  }
}

my $count=make_tree $tempdir => (
  file => 'one/one.txt', "0755",
  file => 'two/two.txt', "0555",
  file => 'three.txt', "0644",
  file => 'four.txt', "0444",
  file => 'five.txt', "0600",
  file => 'six.txt', "0400",
  dir  => 'lemurs_go_here', "0755",
  dir  => 'weasels_go_here', "0555",
  dir  => 'lemons_are_awesome', "0700",
);

my $out=`find "${tempdir}" -ls`;

diag sprintf "\n%s\n", $out;

$index->add($tempdir);

my $files=$tempdir->visit(sub { push @{$_[1]->{files}}, $_[0] }, { recurse => 1 })->{files};

plan tests => scalar @$files;

for my $file (@$files) {
  test_entry $index, $file;
}
