package File::Index::Directory;

use Moo;

with 'File::Index::Entry';

sub children {
  my $self=shift;
  ...;
}

1;
