package File::Index::Types;

use 5.016;
use strict;
use warnings;
use Type::Library
  -base,
  -declare => qw( AbsPath EpochTime IntegerNotNull FileMode );
use Type::Utils -all;
use Types::Standard qw( Int Str );
use Path::Tiny;
use Date::Parse;

class_type AbsPath, { class => "Path::Tiny" };

coerce AbsPath, from Str, via { path $_ };

declare IntegerNotNull,
  as Int, where { defined $_ and $_ > 0 };

declare EpochTime, as Int;

coerce EpochTime, from Str, via { str2time $_ };

declare FileMode, as IntegerNotNull;

1;
