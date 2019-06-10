package File::Index;

use Moo;
use Path::Tiny;

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
        path  => $absolute_target->parent,
        name  => $absolute_target->basename,
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

sub by_id {
  my $self=shift;
  my $id=shift;
  my $dbh=$self->dbh;
  my $select=$self->_select_by_id;
  my $result=$dbh->selectrow_hashref($select, {}, $id);
  return $result;
}

sub by_path {
  my $self=shift;
  my $path=path(shift)->realpath;
  my $dbh=$self->dbh;
  my $select=$self->_select_by_name;
  my $result=$dbh->selectrow_hashref($select, {}, $path->parent, $path->basename);
  return $result;
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
  my $id;
  my $is_new;
  my $dbh=$self->dbh;
  my $insert=$self->_statement_cache->{insert_entry};
  # name, path, mode, size, mtime
  my $result=$dbh->execute($insert, {}, $entry->{name}, $entry->{path}, $entry->{mode}, $entry->{size}, $entry->{mtime});
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
        name        VARCHAR(255) NOT NULL,
        path        VARCHAR(1023) NOT NULL,
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
  $cache->{insert_entry}=$dbh->prepare('INSERT OR REPLACE INTO entries (name, path, mode, size, mtime) VALUES (?, ?, ?, ?, ?);');
  $cache->{insert_}
  return $cache;
}

1;

