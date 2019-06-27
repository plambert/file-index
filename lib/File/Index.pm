package File::Index;

use strict;
use warnings;
use Path::Tiny;
use DBI;
use JSON::MaybeXS;
use File::Index::Entry;
# use File::Index::Regular;
use Moo;

##### private data #####

our $statements={
  get_entry_id_by_path_and_name => 'SELECT id FROM entries WHERE filepath=? AND filename=?;',
  get_entry_by_path_and_name => 'SELECT * FROM entries WHERE filepath=? AND filename=?;',
  get_entry_by_id => 'SELECT * FROM entries WHERE id=?;',
  insert_entry => 'INSERT INTO entries (filename, filepath, mode, size, mtime) VALUES (?, ?, ?, ?, ?);',
  delete_entry_by_path_and_name => 'DELETE FROM entries WHERE filepath=? AND filename=?;',
  delete_entry_by_id => 'DELETE FROM entries WHERE id=?;',
  update_entry_by_path_and_name => 'UPDATE entries SET mode=?, size=?, mtime=? WHERE filepath=? AND filename=?;',
  update_entry_by_id => 'UPDATE entries SET mode=?, size=?, mtime=? WHERE id=?;',
};

##### public attributes #####

has dbfile  => ( is => 'lazy' );
has dbspec  => ( is => 'lazy' );
has dbh     => ( is => 'lazy' );
has schema  => ( is => 'lazy' );

##### private attributes #####

has _statement_cache => ( is => 'lazy' );

##### public methods #####

sub index {
  my $self=shift;
  my @targets=@_;
  my $count_all;
  my $count_new;
  return $self unless @targets;
  while (@targets) {
    my $target=path shift @targets;
    if (! -e $target) {
      warn sprintf "%s: %s: not found\n", path($0)->basename, $target;
      next;
    }
    my $stat=$target->stat;
    my $absolute_target=$target->realpath;
    if (-d $absolute_target or -f $absolute_target) {
      my ($id, $is_new) = $self->_add_or_update_entry({
        filepath  => $absolute_target->parent,
        filename  => $absolute_target->basename,
        mode  => $stat->mode,
        size  => $stat->size,
        mtime => $stat->mtime,
      });
      push @targets, $absolute_target->children if -d $absolute_target;
      $count_new += 1 if $is_new;
      $count_all += 1;
    }
    else {
      warn sprintf "%s: %s: not a file or directory\n", path($0)->basename, $target;
    }
  }
  return({ count => $count_all, added => $count_new });
}

BEGIN {
  *add = \&index;
  *add_or_update = \&index;
}

sub by_id {
  my $self=shift;
  my $id=shift;
  my $dbh=$self->dbh;
  my $select=$self->_select_by_id;
  my $result=$dbh->selectrow_hashref($select, {}, $id);
  return File::Index::Entry->new_from_hash($result);
}

sub by_path {
  my $self=shift;
  my $path=path(shift)->realpath;
  my $dbh=$self->dbh;
  my $select=$self->_statement_cache->{get_entry_by_path_and_name};
  my $result=$dbh->selectrow_hashref($select, {}, $path->parent, $path->basename);
  return File::Index::Entry->new_from_hash($result);
}

sub all_by_name {
  my $self=shift;
  my $path=path(shift)->realpath;
  my $dbh=$self->dbh;
  my ($select, $count)=$self->_all_by_name;
  if (wantarray) {
    my @result=$dbh->selectall_array($select, {Slice=>{}}, $path->parent, $path->basename);
    return @result;
  }
  elsif (defined wantarray) {
    my ($count) = $dbh->selectall_array($count, {}, $path->parent, $path->basename);
  }
}

##### internal methods #####

# add an entry to the database, or update it if it's already tehre
# return the id of the entry, and a boolean true if it is newly created

sub _add_or_update_entry {
  my $self=shift;
  my $entry=shift;
  my $is_new;
  my $dbh=$self->dbh;
  my $insert=$self->_statement_cache->{insert_entry};
  my $update=$self->_statement_cache->{update_entry_by_id};
  my $find=$self->_statement_cache->{get_entry_id_by_path_and_name};
  # filename, filepath, mode, size, mtime
  my ($id, @x)=$find->execute($entry->{filepath}, $entry->{filename});
  # printf STDERR "=== %s\n", JSON->new->canonical->allow_blessed->convert_blessed->allow_nonref->encode([ $id, @x ]);
  if ($id and $id > 0) {
    printf STDERR "=== %d --> %s\n", $id, JSON->new->canonical->allow_blessed->convert_blessed->allow_nonref->encode($entry);
    $update->execute(map { $entry->{$_} // undef } qw{mode size mtime id});
    return $id, 1;
  }
  else {
    my $result=$insert->execute($entry->{filename}, $entry->{filepath}, $entry->{mode}, $entry->{size}, $entry->{mtime});
    # printf STDERR "+++ %d --> %s\n", $dbh->last_insert_id, JSON->new->canonical->allow_blessed->convert_blessed->allow_nonref->encode($entry);
    return $result, defined $id;
  }
}

# create database tables if they don't exist
sub BUILD {
  my $self=shift;
  my $dbh=$self->dbh;
  $dbh->do($_) for $self->schema->@*;
}

##### build default values for attributes #####

sub _build_dbfile {
  my $self=shift;
  my $file=path($ENV{FILE_INDEX_DB} || '~/.cache/file-index.sqlite3');
  $file->parent->mkpath unless -d $file->parent;
  return $file;
}

sub _build_dbspec {
  my $self=shift;
  my $file=$self->dbfile;
  return sprintf "dbi:SQLite:dbname=${file}";
}

sub _build_dbh {
  my $self=shift;
  my $dbh=DBI->connect($self->dbspec, undef, undef, { AutoCommit => 1, RaiseError => 1 });
  return $dbh;
}

sub _build_schema {
  my $self=shift;
  my @schema=grep { /\S/ and !/^\s*\#/ } split /(?<=;)\s*/, <<~SCHEMA;

      CREATE TABLE IF NOT EXISTS entries (
        id          INTEGER PRIMARY KEY,
        filename    VARCHAR(255) NOT NULL,
        filepath    VARCHAR(1023) NOT NULL,
        mode        INTEGER NOT NULL,
        size        INTEGER NOT NULL,
        mtime       INTEGER NOT NULL,
        index_time  INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );

      CREATE TABLE IF NOT EXISTS checksums (
        id          INTEGER PRIMARY KEY,
        entry_id    INTEGER NOT NULL,
        algorithm   TEXT NOT NULL,
        checksum    TEXT NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_checksum_entry_algo ON checksums (entry_id, algorithm);

    SCHEMA
  return \@schema;
}

sub _build__statement_cache {
  my $self=shift;
  my $dbh=$self->dbh;
  my $cache={};
  for my $key (keys %$statements) {
    $cache->{$key}=$dbh->prepare($statements->{$key});
  }
  return $cache;
}

1;

