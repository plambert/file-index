#!/usr/bin/env perl

# create the test directories

use strict;
use warnings;
use Test::More tests => 4;
use FindBin;
use Path::Tiny;
use Try::Tiny;
use JSON;

my $testdir=path $FindBin::Bin;
my $treedir=path $FindBin::Bin, '.testtrees';
my @trees;
my $json=JSON->new->canonical->allow_blessed->convert_blessed->allow_nonref;

SKIP: {
  skip "using manual test trees", 4;
  exit;
}
exit;

sub make_treedir {
  my $dir=shift;
  my $result=JSON->true;
  try {
    $dir->mkpath;
  }
  catch {
    $result=JSON->false;
  };
  return $result;
}

sub parse_treefile {
  my $treefile=shift;
  my $result;
  my $content;
  try {
    $content=$treefile->slurp_utf8;
  };
  return unless $content;
  try {
    $result=$json->decode($content);
  };
  return $result;
}

sub make_tree {
  my $basedir=shift;
  my $tree=shift;
  my $dir=path $basedir, $tree->{name};
  my $result;
  diag(sprintf "+ %s -> %s", $json->encode($dir), $json->encode($tree));
  $dir->mkpath;
  try {
    $result=_make_tree_recursive($dir, $tree->{content});
  };
  return $result;
}

sub _make_tree_recursive {
  my $dir=shift;
  my $content=shift;
  while(my ($key, $value) = each %$content) {
    if (not ref $value) {
      $dir->child($key)->spew_utf8($value);
    }
    elsif ('ARRAY' eq ref $value) {
      $dir->child($key)->spew_utf8(map { s{\n?$}{\n}r } @$value);
    }
    elsif ('HASH' eq ref $value) {
      $dir->child($key)->mkpath;
      _make_tree_recursive($dir->child($key), $value);
    }
    else {
      warn "unknown value in tree: " . ref $value;
      return;
    }
  }
  return 1;
}

ok(make_treedir($treedir), "test tree directory exists");

my @treefiles=$testdir->children(qr{\.tree$});

ok(scalar(@treefiles) > 0, "found at least one tree definition file");

if (@treefiles) {
  subtest 'read tree definition files' => sub {
    plan tests => scalar @treefiles;
    for my $treefile (@treefiles) {
      my $definition=parse_treefile($treefile);
      diag($json->encode($definition));
      ok(defined $definition, sprintf "treefile %s", $treefile->basename);
      push @trees, $definition;
    }
  };
}
else {
  ok(1, 'no tree definition files');
}

if (@treefiles) {
  subtest 'create trees' => sub {
    plan tests => scalar @trees;
    for my $treedef (@trees) {
      my $result=make_tree($treedir, $treedef);
      ok($result, "create tree: " . $treedef->{name});
    }
  }
}
else {
  ok(1, "no tree definition files");
}
