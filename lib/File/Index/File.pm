package File::Index::File;

use Moo;
use Carp;

with 'File::Index::Entry';

has crc32 => (
  is => "ro",
  isa => sub { m{^[a-f0-9]{8}$}i or not defined $_ or croak "$_: invalid crc32" },
);

has sha256 => (
  is => "ro",
  isa => sub { m{^[a-f0-9]+$}i or not defined $_ or croak "$_: invalid sha256" },
);

1;
