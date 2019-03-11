package File::Index::Volume;

use Moo;
use Carp;
use Sys::Hostname;

has id => (
  is => 'ro',
  isa => sub { (not defined $_ or looks_like_number $_) or croak "invalid id" },
  default => undef,
);

has hostname => (
  is => 'ro',
  isa => sub { 1; },
  default => sub { hostname; },
);

has root => (
  is => 'ro',
  isa => sub {
    defined $_[0] or croak "root must be defined";
    ('Path::Tiny' eq ref $_[0] or not ref $_[0]) or croak "root must be a path string or Path::Tiny";
    (ref $_[0] ? $_[0]->is_absolute : $_[0] =~ m{^/}) or croak "root must be an absolute path";
  },
  required => 1,
);

# generally false
# if true, it means the hostname isn't really a "hostname", and the volume
# might exist in many places.  for example, Dropbox or an nfs mount point
has is_shared => (
  is => 'ro',
  isa => sub { 1; },
  required => 1,
);

has index => (
  is => 'ro',
  isa => sub { 'File::Index' eq ref $_[0] or croak "required File::Index, got " . ref $_[0] },
  weak_ref => 1,
  required => 1,
);

sub BUILD {
  my $self=shift;
  return if (defined $self->id);
  my $data={hostname => $self->hostname, root => $self->root, is_shared => $self->is_shared};
  $data->{id}=$self->id if defined $self->id;
  $self->index->insert('volume', $data) or croak sprintf "hostname '%s', root '%s': could not write volume: %s", $self->hostname, $self->root, $self->index->dbh->errstr;
  return $self->id if defined $self->id;
  my $id=$self->index->dbh->selectrow_array('SELECT id FROM volume WHERE hostname=? AND root=?;', $self->hostname, $self->root);
  $self->id($id) if defined $id;
}

1;
