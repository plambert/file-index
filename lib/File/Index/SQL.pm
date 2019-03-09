package File::Index::SQL;

use 5.014;
use strict;
use warnings;
use Moo::Role;
use Path::Tiny;
use DBI;
use Try::Tiny;
use Types::Path::Tiny qw/AbsPath/;
use Carp;

our $DEFAULT_DBI_OPTIONS={ RaiseError => 1, AutoCommit => 1 };
our $TABLES={
  entry => {
    hostname    => { index => 'TEXT' },
    abspath     => { unique => 'TEXT' },
    name        => { index => 'TEXT' },
    suffix      => { index => 'TEXT' },
    type        => { index => 'TEXT' },
    crc32       => { unique => 'TEXT' },
    sha256      => { unique => 'TEXT' },
    dev         => 'INTEGER',
    ino         => 'INTEGER',
    mode        => 'INTEGER',
    nlink       => 'INTEGER',
    uid         => 'INTEGER',
    gid         => 'INTEGER',
    rdev        => 'INTEGER',
    size        => 'INTEGER',
    atime       => 'INTEGER',
    mtime       => 'INTEGER',
    ctime       => 'INTEGER',
    blksize     => 'INTEGER',
    blocks      => 'INTEGER',
    _indices    => [
      {
        columns => [ 'hostname', 'abspath' ],
        unique => 1,
      },
    ],
  },
  symlink => {
    hostname    => { index => 'TEXT' },
    abspath     => { index => 'TEXT' },
    link_target => { index => 'TEXT' },
    _indices    => [
      {
        columns => [ 'hostname', 'abspath' ],
        unique => 1,
      },
    ],
  },
};

has dbfile => (
  is => 'lazy',
  isa => AbsPath,
  coerce => 1,
);

sub _build_dbfile {
  my $self=shift;
  my $dbfile=path '~/.cache/file-index.sqlite3';
  return $dbfile;
}

has dbh => (
  is => 'lazy',
  isa => sub { 'DBI::db' eq ref $_[0] or croak "$0: $_[0]: must be dbi handle" },
  builder => "_build_dbh",
);

sub _build_dbh {
  my $self=shift;
  my $dbstring=sprintf "dbi:SQLite:dbname=%s", $self->dbfile;
  my $dbh=DBI->connect($dbstring, undef, undef, $DEFAULT_DBI_OPTIONS);
  return $dbh;
}

sub BUILD {
  my $self=shift;
  if ($self->dbfile->is_file) {
    if ($ENV{FILE_INDEX_RESET}) {
      $self->dbfile->remove;
    }
    else {
      return;
    }
  }
  while (my ($table, $def) = each %$TABLES) {
    $self->create_table($table, $def);
  }
}

sub sql_do {
  my $self=shift;
  # we can debug here... but no debugging is available yet.
  printf STDERR "+SQL %s\n", join(' ', @_) if $ENV{DEBUG};
  $self->dbh->do(@_);
}

sub sql {
  my $self=shift;
  return $self->dbh->prepare_cached(@_);
}

sub create_table {
  my $self=shift;
  my $table=shift;
  my $definition=shift;
  my $dbh=$self->dbh;
  my @indices;
  my @columns;
  my $sql;
  for my $column (sort keys %$definition) {
    next unless defined $definition->{$column};
    next if $column eq '_indices';
    my $type;
    my $name;
    if ('HASH' eq ref $definition->{$column}) {
      $name=exists($definition->{$column}->{name})
          ? delete($definition->{$column}->{name})
          : $column;
      my ($index_type)=(keys %{$definition->{$column}});
      $type=$definition->{$column}->{$index_type};
      push @indices, [ [$column], $name, $index_type ];
    }
    elsif (not ref $definition->{$column}) {
      ($name, $type)=($column, $definition->{$column});
    }
    else {
      croak sprintf "%s: %s: unexpected type of table definition", path($0)->basename, ref $definition->{$column};
    }
    push @columns, sprintf "%s %s", $self->dbh->quote_identifier($name), $type;
  }
  $sql=sprintf 'CREATE TABLE IF NOT EXISTS %s (%s);', $self->dbh->quote_identifier($table), join(', ', @columns);
  $self->sql_do($sql);
  if ($definition->{_indices}) {
    for my $idx_def (@{$definition->{_indices}}) {
      my $idx_name;
      if ($idx_def->{name}) {
        $idx_name=$idx_def->{name};
      }
      else {
        $idx_name=sprintf "idx_%s_%s", $table, join('_', @{$idx_def->{columns}});
      }
      push @indices, [ $idx_def->{columns}, $idx_name, $idx_def->{unique} ? 'unique' : 'index' ];
    }
  }
  for my $index (@indices) {
    my ($columns, $name, $type) = @$index;
    my $index_name=sprintf "idx_%s_%s", $table, join("_", sort @$columns);
    my $column_spec=join ', ', map { $self->dbh->quote_identifier($_) } sort @$columns;
    $sql=sprintf 'CREATE %s %s ON %s (%s);',
      $type eq 'unique' ? 'UNIQUE INDEX' : 'INDEX',
      $self->dbh->quote_identifier($index_name),
      $self->dbh->quote_identifier($table),
      $column_spec;
    $self->sql_do($sql);
  }
}

sub insert {
  my $self=shift;
  my $table=shift;
  my $data=shift;
  my @columns=sort keys %$data;
  my $sql=sprintf 'INSERT OR REPLACE INTO %s (%s) VALUES (%s);',
    $table,
    join(', ', @columns),
    join(', ', map { '?' } @columns);
  my $sth=$self->sql($sql);
  return $sth->execute(map { $data->{$_} } @columns);
}

1;
