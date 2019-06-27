package File::Index::Role::DBObject;

use 5.016;
use strict;
use warnings;
use DBI;
use Moo::Role;
use Carp;

our @COLUMNS;

has dbh => (
  is => 'ro',
  isa => sub { ref $_[0] =~ m{^DBI(?:::.*)?$} },
  weak_ref => 1,
  required => 1,
);

# Must be re-implemented in each consuming class for all but the simplest cases...
sub _to_key_value {
  my $self=shift;
  my $obj={};
  for my $attr (@COLUMNS) {
    $obj->{$attr}=$self->$attr;
  }
  return $obj;
}

# Private class method called like: My::Module->_from_key_value({key => value});
sub _from_key_value {
  my $class=shift;
  my $obj=shift;
  return __PACKAGE__->new($obj);
}

has _statement_cache => ( is => 'ro', default => sub { {} } );

for my $method (qw{ selectrow_hashref selectall_array }) {
  ## no critic
  eval sprintf 'sub %s {
    my $self=shift;
    my $name=shift;
    my $sth=$self->_statement_cache->{$name} or croak "${name}: unknown SQL statement name";
    my $opts=(@_ and "HASH" eq ref $_[0]) ? shift @_ : {};
    return $self->dbh->%s($sth, $opts, @_);
  } ', $method, $method;
}

1;

