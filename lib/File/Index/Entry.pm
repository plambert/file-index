package File::Index::Entry;

use Moo::Role;
use List::Util qw/any/;
use Scalar::Util qw/looks_like_number/;
use Carp;
use File::stat ();
use Sys::Hostname;

our @STATS=map { s{^\$st_}{}r } @File::stat::fields;
our $FILETYPE={
  S_IFREG  => 'file',
  S_IFDIR  => 'directory',
  S_IFLNK  => 'symlink',
  S_IFBLK  => 'block',
  S_IFCHR  => 'char',
  S_IFIFO  => 'fifo',
  S_IFSOCK => 'socket',
  S_IFWHT  => 'whitespace',
};

around BUILDARGS => sub {
  my ( $orig, $class, @args ) = @_;
  my $opts=$class->$orig(@args);
  if ($opts->{stat}) {
    if ('ARRAY' eq ref $opts->{stat}) {
      my @stat=@{$opts->{stat}};
      $opts->{$_}=shift @stat for @STATS;
    }
    elsif ('File::stat' eq ref $opts->{stat}) {
      $opts->{$_}=$opts->{stat}->$_ for @STATS;
    }
    else {
      croak "stat must be an arrayref or File::stat object";
    }
    delete $opts->{stat};
  }
  if (not $opts->{volume_id}) {
    if ($opts->{root}) {
      my $h=exists $opts->{hostname} ? delete $opts->{hostname} : hostname;
      my $r=delete $opts->{root};
      my $volume_id=_get_volume($opts->{index}, $h, $r);
      croak "could not find volume" unless defined $volume_id;
      $opts->{volume_id} = $volume_id;
    }
  }
  return $opts;
};

sub _get_volume {
  my $dbh=shift;
  my $hostname=shift;
  my $root=shift;
  my $sth=$dbh->prepare_cached('SELECT id FROM volume WHERE hostname == ? AND root == ?;');
  my ($id)=$sth->selectrow_array($sth, $hostname, $root) or croak $dbh->errstr;
  croak sprintf "hostname '%s', root '%s' not found in volume table", $hostname, $root unless defined $id;
  return $id;
}

has index => (
  is => 'ro',
  isa => sub { 'File::Index' eq ref $_[0] or croak "required File::Index, got " . ref $_[0] },
  weak_ref => 1,
  required => 1,
);

has type => (
  is => 'lazy',
  isa => sub { any { $_[0] eq $_ } values %$FILETYPE },
);

sub _build_type {
  my $self=shift;
  printf STDERR "+ %07o %s\n", $self->mode, $self->name;
  my $mode=first { $self->mode & $_ } keys %$FILETYPE;
  return $FILETYPE->{$mode};
}

has volume_id => (
  is => "ro",
  isa => sub { looks_like_number $_ or croak "$_: expected a hostname" },
  required => 1
);
has abspath  => (
  is => "ro",
  isa => sub { m{^/.*$} or croak "$_: expected an absolute path"    },
  required => 1
);
has \@STATS => (
  is => "ro",
  isa => sub { looks_like_number $_ or croak "$_: expected integer" },
  required => 1
);

has name     => ( is => "lazy", isa => sub { m{^[^/\n]+$} or croak "$_: expected filename" } );

sub _build_name {
  my $self=shift;
  return path($self->hostname)->basename;
}

has suffix   => ( is => "lazy", isa => sub { m{^[^/\n]+$} or croak "$_: expected suffix" } );

sub _build_suffix {
  my $self=shift;
  my $name=$self->hostname;
  my $suffix;
  if ($name =~ m{.\.([^\.]+)$}) {
    $suffix=$1;
  }
  else {
    $suffix='-';
  }
  return $suffix;
}

sub db_insert {
  my $self=shift;
  my $table=shift // 'entry';
  my $fields=$self->_db_fields;
  $self->index->insert($table, $fields);
}

sub _db_fields {
  my $self=shift;
  my $data;
  for my $key (@STATS, qw{})
}
1;
