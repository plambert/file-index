package File::Index::Schema;

use Moo;
use Carp;
use re 'eval';

our %ESC=('n' => "\n", 'r' => "\r", 't' => "\t");
our $grammar=do {
  use Regexp::Grammars;
  qr{
    <nocontext:>

    \A <[TableDefinition]>+ <.ws> \z
    <MATCH=(?{
      $MATCH={ map { ( $_->{TableName}, $_->{TableDefinitionEntry} ) } @{$MATCH{TableDefinition}} }
    })>

    <rule: TableDefinition>
      <TableName=Identifier> \{ <[TableDefinitionEntry]>+ \}
    | <matchline> table <TableName=Identifier> \{
        <fatal:(?{"Cannot parse table definition at line $MATCH{matchline}"})>

    <rule: TableDefinitionEntry>
      <MATCH=ColumnDefinition> | <MATCH=IndexDefinition>

    <rule: ColumnDefinition>
      <ColumnName=Identifier> <ColumnType> <ColumnIndexDefinition>?
      (?{
        $MATCH={
          _ => 'column',
          name => $MATCH{ColumnName},
          type => $MATCH{ColumnType},
          index => $MATCH{ColumnIndexDefinition},
        };
      })
    | <matchline> <ColumnName=Identifier>
        <fatal:(?{"Cannot parse column definition at line $MATCH{matchline}"})>

    <rule: IndexDefinition>
      \( <IndexDefinitionType> <[Identifier]>+ % <Comma> \)
        (?{ $MATCH={ _ => 'index', type => $MATCH{IndexDefinitionType}, columns => $MATCH{Identifier} } })

    <rule: ColumnIndexDefinition>
      <MATCH=ColumnIsIndexed> | <MATCH=ColumnIsUnique>

    <rule: Identifier>
      <MATCH=BareWord>
    | <MATCH=QuotedString>

    <token: IndexDefinitionType>
      index(ed)? (?{ $MATCH='index' })
    | unique (?{ $MATCH='unique' })

    <token: IndexType>
      unique        (?{ $MATCH='unique'  })
    | index(?:ed)?+ (?{ $MATCH='index'   })

    <token: QuotedString> " <[QuotedStringElement]>* "
      <MATCH=(?{ join '', @{$MATCH{QuotedStringElement}} })>

    <token: QuotedStringElement> <MATCH=QuotedLiteral> | <MATCH=QuotedChar> | <MATCH=QuotedEscape>

    <token: QuotedLiteral> [^\\"]++

    <token: QuotedChar> \\ u ([a-f0-9]{4}|[a-f0-9]{2})
      <MATCH=(?{ chr(hex($CONTEXT)) })>

    <token: QuotedEscape> \\(.)
      <MATCH=(?{ $ESC{$CONTEXT} // $CONTEXT })>

    <token: BareWord> [\w_]++

    <token: ColumnType> integer | text

    <token: ColumnIsIndexed> index(?:ed)? <MATCH='index'>

    <token: ColumnIsUnique> unique

    <token: Comma> ,

    <token: ws> (?:\s+|\s*\#.*\n)*+

  }ix;
};
our $schema='
  volume {
    hostname      TEXT       indexed
    root          TEXT       indexed
    is_shared     INTEGER    indexed
    ( unique hostname, root )
  }

  symlink {
    entry_id      INTEGER    unique
    link          TEXT       indexed
  }

  entry {
    volume_id     INTEGER    indexed
    abspath       TEXT       unique
    name          TEXT       indexed
    suffix        TEXT       indexed
    type          TEXT       indexed
    crc32         TEXT       indexed
    sha256        TEXT       indexed
    dev           INTEGER
    ino           INTEGER
    mode          INTEGER
    nlink         INTEGER
    uid           INTEGER    indexed
    gid           INTEGER    indexed
    rdev          INTEGER
    size          INTEGER    indexed
    atime         INTEGER
    mtime         INTEGER    indexed
    ctime         INTEGER
    blksize       INTEGER
    blocks        INTEGER
    ( unique volume_id, abspath )
  }
' =~ s{^  }{}gmr;

sub db_init_sql {
  my $class=shift;
  my @sql;
  if ($schema =~ $grammar) {
    push @sql, _to_sql($_, $/{$_}) for (keys %/);
    return @sql;
  }
  else {
    croak "unable to parse table definitions";
  }
}

sub _to_sql {
  my $table=shift;
  my $definitions=shift;
  my @columns=( "id INTEGER PRIMARY KEY" );
  my @indices;
  my @sql;
  for my $def (@$definitions) {
    croak sprintf "%s: expected definition to be a hashref, not '%s'", path($0)->basename, ref $def
      unless 'HASH' eq ref $def;
    if ('column' eq $def->{_}) {
      push @columns, sprintf "%s %s", $def->{name}, $def->{type};
      if (defined $def->{index}) {
        my $index_type=$def->{type} eq 'unique' ? 'UNIQUE INDEX' : 'INDEX';
        my $index_name=sprintf "idx_%s_%s", $table, $def->{name};
        push @indices, sprintf "CREATE INDEX %s IF NOT EXISTS %s ON %s ( %s );\n",
          $index_type,
          $index_name,
          $table,
          $def->{name};
      }
    }
    elsif ('index' eq $def->{_}) {
      my $index_type=$def->{type} eq 'unique' ? 'UNIQUE INDEX' : 'INDEX';
      my $index_name=sprintf "idx_%s_%s", $table, join '_', sort @{$def->{columns}};
      push @indices, sprintf "CREATE %s IF NOT EXISTS %s ON %s (\n  %s\n);\n",
        $index_type,
        $index_name,
        $table,
        join ",\n  ", sort @{$def->{columns}};
    }
  }
  push @sql, sprintf "CREATE TABLE IF NOT EXISTS %s (%s\n);\n",
    $table,
    join ',', map { "\n  $_" } @columns;
  push @sql, @indices;
  return @sql;
}

sub _to_column {
  my $coldef=shift;

}

1;
