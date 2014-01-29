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

our $VERSION = '1.99';
our $RELEASE = '1.99';
our $SHORTDESCRIPTION = 'SQL interface for Foswiki';
our $NO_PREFS_IN_TOPIC = 1;
our $doneInit;
our $baseWeb;
our $baseTopic;

##############################################################################
sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  Foswiki::Func::registerTagHandler('SQL', \&handleSQL);
  Foswiki::Func::registerTagHandler('SQLFORMAT', \&handleSQLFORMAT);
  Foswiki::Func::registerTagHandler('SQLINFO', \&handleSQLINFO);

  $doneInit = 0;
  return 1;
}

###############################################################################
sub init {
  return if $doneInit;
  $doneInit = 1;
  require Foswiki::Plugins::SqlPlugin::Core;
  Foswiki::Plugins::SqlPlugin::Core::init($baseWeb, $baseTopic);
}

###############################################################################
sub finishPlugin {
  return unless $doneInit;
  Foswiki::Plugins::SqlPlugin::Core::finish(@_);
}

##############################################################################
sub handleSQL {
  init();
  return Foswiki::Plugins::SqlPlugin::Core::handleSQL(@_);
}

##############################################################################
sub handleSQLFORMAT {
  init();
  return Foswiki::Plugins::SqlPlugin::Core::handleSQLFORMAT(@_);
}

##############################################################################
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
  init();
  return Foswiki::Plugins::SqlPlugin::Core::handleExecute(@_);
}

1;

