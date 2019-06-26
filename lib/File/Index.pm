package File::Index;

use Moo;
use Path::Tiny;
use DBI;
use File::Index::File;
use File::Index::Dir;
use File::Index::Symlink;

has dbfile => ( is => 'ro' );
has dbh => ( is => 'lazy' );
sub _build_dbh {
  my $self=shift;
  my $dbh=DBI->connect(sprintf("dbi:SQLite:dbname=%s", $self->dbfile), undef, undef, { RaiseError => 1, AutoCommit => 1});
  return $dbh;
}

sub index {
  my $self=shift;
  my @queue=map { path($_)->realpath } @_;
  while(@queue) {
    my $item=shift @queue;
    if (-l $item) {
      my $link=File::Index::Symlink->new(path => $item, index => $self);
      $link->_commit;
    }
    elsif (-f $item) {
      my $file=File::Index::File->new(path => $item, index => $self);
      $file->_checksum if $file->size <= $self->checksum_max_size;
      $file->_commit;
    }
    elsif (-d $item) {
      my $dir=File::Index::Dir->new(path => $item, index => $self);
      $dir->_commit;
      push @queue, $dir->subdirs;
    }
    else {
      warn sprintf "%s: %s: unknown type\n", path($0)->basename, $item;
    }
  }
}

sub _add_file {
  my $self=shift;
  my $file=shift;
  my $record=$self->_get_info($file);

}


1;

