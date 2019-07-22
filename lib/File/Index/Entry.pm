package File::Index::Entry;

use Carp;
use Moo::Role;

my @STAT_FIELDS=qw{abspath dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks};

around BUILDARGS => sub {
  my ($orig, $class, @args) = @_;
  if (scalar(@STAT_FIELDS) == scalar @args) {
    return { map { ( $STAT_FIELDS[$_] => $args[$_] ) } 0..$#args };
  }
  else {
    croak sprintf "%s: expected %d arguments: %s", path($0)->basename, scalar(@STAT_FIELDS), @args ? join(', ', @args) : "-";
  }
};

has \@STAT_FIELDS => (
  is => 'ro',
  required => 1,
);

sub basename {
  my $self=shift;
  return $self->abspath->basename;
}

sub parent {
  my $self=shift;
  return $self->abspath->parent;
}

sub type {
  my $self=shift;
}

1;

