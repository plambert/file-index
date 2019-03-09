package File::Index;

use 5.014;
use strict;
use warnings;
use Moo;
use Path::Tiny;
use DBI;
use DBD::SQLite;
use Try::Tiny;
use Types::Path::Tiny qw/AbsPath/;
use Carp;
use Digest::SHA;
use Digest::CRC;
use Fcntl ':mode';
use Sys::Hostname ();

# we separated the database stuff out into a role...
with 'File::Index::SQL';

has hostname => ( is => 'lazy', isa => sub { (defined $_[0] and length $_[0]) or croak "@_: invalid hostname" } );

sub _build_hostname {
  my $self=shift;
  my $hostname=Sys::Hostname::hostname;
  return $hostname;
}

our $DEFAULT_DBI_OPTIONS={ RaiseError => 1, AutoCommit => 1 };

sub find {
  my $self=shift;
  my $query=1==@_ ? shift @_ : { @_ };
  croak "expected a hashref or key/value pairs" unless (ref $query and 'HASH' eq ref $query);
  my $sql="SELECT * FROM entry WHERE";
  my @where;
  my @params;
  state $op_alias={ '+' => '>', '-' => '<' };
  state $unit_multiplier={ 'b' => 1, 'k' => 1024, 'm' => 1024*1024, 'g' => 1024*1024*1024, 't' => 1024*1024*1024*1024};
  if ($query->{path}) {
    push @where, " path LIKE ?";
    push @params, $query->{path} . "%";
  }
  if ($query->{dir}) {
    push @where, " path == ?";
    push @params, $query->{dir};
  }
  if ($query->{glob}) {
    $sql .= " ( path || name ) GLOB ? ESCAPE ?";
    push @params, $query->{glob}, "\\";
  }
  if ($query->{like}) {
    $sql .= " ( path || name ) REGEXP ? ESCAPE ?";
    push @params, $query->{like}, "\\";
  }
  if ($query->{ext}) {
    $sql .= " WHERE name LIKE ?";
    my $ext=$query->{ext};
    $ext =~ s{^\.?}{%.};
    push @params, $ext;
  }
  if ($query->{size}) {
    if ($query->{size} =~ m{^( <= | >= | == | < | > | = | \+ | - | ) (\d+(?:\.\d*)?) (k|m|g|t|)?b?$}ix) {
      my ($op, $count, $unit) = ($1, $2, $3);
      $op = '==' unless defined $op and length $op;
      $op = $op_alias->{$op} // $op;
      $unit=($unit_multiplier->{$unit} ? $unit_multiplier->{$unit} * $unit : 1) * $unit;
      $sql .= ""
    }
  }
}

sub index {
  my $self=shift;
  my @queue=map { path $_ } @_;
  while(@queue) {
    my $entry=shift @queue;
    my $stat;
    try {
      $stat=$entry->stat;
    }
    catch {
      warn sprintf "%s: %s: not found\n", path($0)->basename, $entry;
    };
    next unless defined $stat;
    my $basename=$entry->basename;
    my $suffix;
    $suffix=$1 if $basename =~ m{.\.([^\.]+)$};
    my $data={
      abspath => $entry->realpath,
      name => $basename,
      hostname => $self->hostname,
      suffix => $suffix,
      stat => $stat,
    };
    if ($ENV{FILE_INDEX_CHECKSUM} and -f $entry) {
      $self->add_checksums($data);
    }
    $self->insert('entry', $data);
    if (S_ISDIR($stat->mode)) {
      push @queue, map { path($_)->realpath } $entry->children;
    }
  }
}

sub add_checksums {
  my $self=shift;
  my $data=shift;
  my @checksums=(
    [ 'crc32', Digest::CRC->new(type => 'crc32') ],
    [ 'sha256', Digest::SHA->new(256) ],
  );
  my $fh=path($data->{abspath})->openr_raw;
  while(my $bytes=$fh->sysread(my $buffer, 32*1024)) {
    $_->[1]->add($buffer) for @checksums;
  }
  $fh->close;
  $data->{$_->[0]}=$_->[1]->hexdigest for @checksums;
  return $data;
}

sub select {
  my $self=shift;
  my $where=shift;
  my $result;
  $where =~ s{;\s*$}{};
  my $query=sprintf "SELECT * FROM entry WHERE %s;", $where;
  my $sth=$self->dbh->prepare_cached($query);
  $sth->execute(@_);
  while (my $entry=$sth->fetchrow_hashref) {
    $result->{$entry->{id}}=$self->_from_hash($entry);
  }
  return $result;
}

sub _from_path {
  my $self=shift;
  my $path=shift;
  my $hash;
  my $data;
  my $obj;
  $path=path($path)->realpath;
  $data->{abspath}=$path;
  croak sprintf "%s: %s: no such file or directory",
    path($0)->basename,
    $path
      unless -e $path;
  $data->{stat}=$path->stat;
  if (-l $path) {
    $obj=File::Index::Symlink->new($data);
  }
  elsif (-f $path) {
    $obj=File::Index::File->new($data);
  }
  elsif (-d $path) {
    $obj=File::Index::Directory->new($data);
  }
}

sub _from_hash {
  my $self=shift;
  my $hash=shift;
  croak sprintf "%s: %s: expected a hash",
      path($0)->basename,
      JSON->new->canonical->allow_nonref->encode($hash)
        unless defined $hash and 'HASH' eq ref $hash;
  croak sprintf "%s: %s: missing 'abspath' key",
      path($0)->basename,
      JSON->new->canonical->allow_nonref->encode($hash)
        unless exists $hash->{abspath};
  $hash->{index} //= $self;
  if (-f $hash->{abspath}) {
    return File::Index::File->new($hash);
  }
  elsif (-d $hash->{abspath}) {
    return File::Index::Directory->new($hash);
  }
  else {
    return File::Index::Other->new($hash);
  }
}

1;
