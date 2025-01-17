# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2025 Michael Daum http://michaeldaumconsulting.com
#
# Based on DatabasePlugin Copyright (C) 2002-2007 Tait Cyrus, tait.cyrus@usa.net
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

package Foswiki::Plugins::SqlPlugin::Connection;

use DBI ();
use strict;
use warnings;
use Error qw( :try );
use Foswiki::Sandbox ();
use Foswiki::Plugins ();
use Foswiki::Func ();

use constant TRACE => 0;    # toggle me

###############################################################################
sub writeDebug {
  print STDERR "- SqlPlugin::Connection - $_[0]\n" if TRACE;
}

###############################################################################
sub new {
  my $class = shift;

  my $this = {
    db => undef,
    id => '',
    dsn => '',
    params => {},
    @_
  };

  $this->{params}{PrintError} = 0;
  $this->{params}{RaiseError} = 1;

  bless($this, $class);

  return $this;
}

###############################################################################
sub finish {
  my $this = shift;

  $this->disconnect();
  undef $this->{db};
  #writeDebug("destroying $this->{id}");
}

###############################################################################
sub disconnect {
  my $this = shift;

  return unless $this->{db};

  $this->{db}->disconnect();
  $this->{db} = undef;
}

###############################################################################
sub connect {
  my $this = shift;

  return if $this->{db};

  # just create it
  my $workarea = Foswiki::Func::getWorkArea('SqlPlugin');

  if (defined $this->{attachment}) {

    my $session = $Foswiki::Plugins::SESSION;
    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($this->{web} || $session->{webName}, $this->{topic} || $session->{topicName});

    throw Error::Simple("topic does not exist") unless Foswiki::Func::topicExists($web, $topic);
    throw Error::Simple("attachment does not exist") unless Foswiki::Func::attachmentExists($web, $topic, $this->{attachment});

    # build dsn param
    if ($this->{attachment} =~ /\.xls$/i) {    # doesn't seem to like xlsx
                                               # DBD::Excel

      my $filePath = $Foswiki::cfg{PubDir} . '/' . $web . '/' . $topic . '/' . $this->{attachment};
      $this->{dsn} = 'DBI:Excel:file=' . $filePath;

      $this->{db} = DBI->connect($this->{dsn}, $this->{username}, $this->{password}, $this->{params});

    } elsif ($this->{attachment} =~ /\.csv$/i) {
      # DBD::CSV
      my $dirPath = $Foswiki::cfg{PubDir} . '/' . $web . '/' . $topic;
      $this->{dsn} = 'dbi:CSV:';

      $this->{params}{f_dir} = $dirPath;
      $this->{params}{f_ext} = '.csv';

      $this->{db} = DBI->connect($this->{dsn}, $this->{username}, $this->{password}, $this->{params});
    } else {
      throw Error::Simple("unknown database type");
    }

    #print STDERR "dsn=$this->{dsn}\n";
  } else {
    $this->{db} = DBI->connect($this->{dsn}, $this->{username}, $this->{password}, $this->{params});
  }

  throw Error::Simple("can't open database $this->{id}: " . $DBI::errstr)
    unless $this->{db};

  # see http://foswiki.org/Support/Question1122
  $this->{db}->{LongTruncOk} = 1;
  $this->{db}->{LongReadLen} = 1024;

  return $this->{db};
}

1;

