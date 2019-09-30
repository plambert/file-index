package File::Index::Entry;

use 5.016;
use strict;
use warnings;
use DBI;
use Path::Tiny;
use lib './lib';
use File::Index::Types qw/-all/;
use Fcntl ':mode';
use Moo;

with 'File::Index::Role::DBObject';
with 'File::Index::Role::PermissionSymbols';

our @COLUMNS=qw{ id filename filepath mode mtime index_time };

has id => (
  is => 'ro',
  isa => IntegerPrimaryKey,
);
has filename => (
  is => 'ro',
  required => 1,
);
has filepath => (
  is => 'ro',
  isa => AbsPath,
  coerce => 1,
  required => 1,
);
has mode => (
  is => 'ro',
  isa => FileMode,
);
has mtime => (
  is => 'ro',
  isa => EpochTime,
  coerce => 1,
);
has index_time => (
  is => 'ro',
  isa => EpochTime,
  coerce => 1,
);

# now all the methods we need to make the raw data in the object useful

sub fullpath {
  my $self=shift;
  return path $self->filepath, $self->filename;
}

# generate a '-rwxr-xr-x' or 'drwxr-xr-x' type string
sub rwx {
  my $self=shift;
  ...;  ####  NOT IMPLEMENTED YET!
}

sub is_dir {
  my $self=shift;
  return S_ISDIR($self->mode);
}

sub is_file {
  my $self=shift;
  return S_ISREG($self->mode);
}

sub is_symlink {
  my $self=shift;
  return S_ISLNK($self->mode);
}

sub is_block {
  my $self=shift;
  return S_ISBLK($self->mode);
}

sub is_char {
  my $self=shift;
  return S_ISCHR($self->mode);
}

sub is_fifo {
  my $self=shift;
  return S_ISFIFO($self->mode);
}

sub is_sock {
  my $self=shift;
  return S_ISSOCK($self->mode);
}

# S_ISUID S_ISGID S_ISVTX S_ISTXT
# Setuid/Setgid/Stickiness/SaveText

sub is_setuid {
  my $self=shift;
  return($self->mode & S_ISUID);
}

sub is_setgid {
  my $self=shift;
  return($self->mode & S_ISGID);
}

sub is_sticky {
  my $self=shift;
  return($self->mode & S_ISVTX);
}

sub is_savetext {
  my $self=shift;
  return($self->mode & S_ISTXT);
}

# S_IRWXU S_IRUSR S_IWUSR S_IXUSR
# S_IRWXG S_IRGRP S_IWGRP S_IXGRP
# S_IRWXO S_IROTH S_IWOTH S_IXOTH
do {
  my $who={     user  => 'USR',     group => 'GRP',      world => 'OTH' };
  my $perm={ readable => 'R',   writeable => 'W',   executable => 'X'   };
  for my $w (keys %$who) {
    for my $p (keys %$perm) {
      my $method=sprintf 'sub %s { my $self=shift; return($self->mode & S_I%s%s); }', sprintf("%s_%s", $w, $p), $who->{$w}, $perm->{$p};
      eval $method; ## no critic
    }
  }
};

sub _rwx {
  my $self=shift;
  my ($read, $write, $exec, $setid, $special) = @_;
  my $rwx='';
  $rwx .= $read ? 'r' : '-';
  $rwx .= $write ? 'w' : '-';
  if ($setid) {
    $rwx .= $exec ? substr($special, 0, 1) : substr($special, 1, 1);
  }
  else {
    $rwx .= $exec ? 'x' : '-';
  }
  return $rwx;
}

has user_perms => ( is => 'lazy' );

sub _build_user_perms {
  my $self=shift;
  my $rwx=$self->_rwx($self->user_readable, $self->user_writeable, $self->user_executable, $self->is_setuid, 'Ss');
  return $rwx;
}

has group_perms => ( is => 'lazy' );

sub _build_group_perms {
  my $self=shift;
  my $rwx=$self->_rwx($self->group_readable, $self->group_writeable, $self->group_executable, $self->is_setgid, 'Ss');
  return $rwx;
}

has world_perms => ( is => 'lazy' );

sub _build_world_perms {
  my $self=shift;
  my $rwx=$self->_rwx($self->world_readable, $self->world_writeable, $self->world_executable, $self->is_sticky, 'Tt');
  return $rwx;
}

has perms => ( is => 'lazy' );

sub _build_perms {
  my $self=shift;
  my $type_char = $self->is_dir     ? 'd' : 
                  $self->is_file    ? '-' :
                  $self->is_sock    ? 's' : 
                  $self->is_fifo    ? 'p' :
                  $self->is_symlink ? 'l' :
                  $self->is_char    ? 'c' :
                  $self->is_block   ? 'b' :
                  '?';
  my $perms=join '', $type_char, $self->user_perms, $self->group_perms, $self->world_perms;
  return $perms;
}

# public class method
sub new_from_hash {
  my $class=shift;
  my $obj=shift;
  return File::Index::Entry->new($obj);
  # if ($obj->{mode} & S_IFDIR) {
  #   return File::Index::Directory->new($obj);
  # }
  # elsif ($obj->{mode} & S_IFREG) {
  #   return File::Index::Regular->new($obj);
  # }
  # elsif ($obj->{mode} & S_IFSOCK) {
  #   return File::Index::Socket->new($obj);
  # }
  # elsif ($obj->{mode} & S_IFLNK) {
  #   return File::Index::Symlink->new($obj);
  # }
  # elsif ($obj->{mode} & S_IFBLK) {
  #   return File::Index::Block->new($obj);
  # }
  # elsif ($obj->{mode} & S_IFCHR) {
  #   return File::Index::Character->new($obj);
  # }
  # elsif ($obj->{mode} & S_IFIFO) {
  #   return File::Index::NamedPipe->new($obj);
  # }
  # else {
  #   die sprintf "%s: %04o: unrecognized file type!\n", path($0)->basename, $obj->{mode} & S_IFMT;
  # }
}

1;

