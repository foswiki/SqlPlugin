# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
# 
# Copyright (C) 2009-2014 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::SqlPlugin;

use strict;
use warnings;

our $VERSION = '3.00';
our $RELEASE = '3.00';
our $SHORTDESCRIPTION = 'SQL interface for Foswiki';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

=begin TML
---++ StaticMethod core() -> $core

defered construction of the plugin's core; this is a singleton instance.

=cut
sub core {

  unless (defined $core) {
    require Foswiki::Plugins::SqlPlugin::Core;
    $core = Foswiki::Plugins::SqlPlugin::Core->new();
  }

  return $core;
}

=begin TML
---++ StaticMethod initPlugin($topic, $web) -> $boolean

plugin constructor called at the beginning of every request

=cut
sub initPlugin {

  Foswiki::Func::registerTagHandler('SQL', sub {
    return core->handleSQL(@_);
  });

  Foswiki::Func::registerTagHandler('SQLFORMAT', sub {
    return core->handleSQLFORMAT(@_);
  });

  Foswiki::Func::registerTagHandler('SQLINFO', sub {
    return core->handleSQLINFO(@_);
  });

  $core = undef;
  return 1;
}

=begin TML
---++ StaticMethod finishPlugin

function called at the end of every request

=cut
sub finishPlugin {
  return unless $core;

  $core->finish(@_);

  undef $core;
}

=begin TML
---++ StaticMethod handleSQL($session, $params, $topic, $web) -> $string

expands the SQL makro

=cut
sub handleSQL {
  core->handleSQL(@_);
}

=begin TML
---++ StaticMethod handleSQLFORM($session, $params, $topic, $web) -> $string

expands the SQLFORMAT makro

=cut
sub handleSQLFORMAT {
  init();
  return Foswiki::Plugins::SqlPlugin::Core::handleSQLFORMAT(@_);
}

=begin TML
---++ StaticMethod handleSQLINFO($session, $params, $topic, $web) -> $string

expands the SQLINFO makro

=cut
sub handleSQLINFO {
  init();
  return Foswiki::Plugins::SqlPlugin::Core::handleSQLINFO(@_);
}

=begin TML
---++ StaticMethod execute($dbconn, $query, @bindvals) -> $sth

Executes the provided $query and returns a DBI Statement handle.  It is the 
caller's responsibility to call $sth->finish after processing is complete.

   $ $dbconn: The database connection defined in the configure screen.
   $ $query: The SQL query to be run, possibly with placeholders (?).
   $ @bindvals: An OPTIONAL list of values to be applied.  Only needed if $query has placeholders.

Throws Error::Simple on errors.

=cut
sub execute {
  return core->execute(@_);
}

1;
