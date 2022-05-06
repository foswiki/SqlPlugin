# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2022 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::SqlPlugin::Core;

use strict;
use warnings;

use Foswiki::Plugins::SqlPlugin::Connection ();
use Error qw( :try );
use Foswiki::Sandbox ();
use Text::ParseWords ();

use constant TRACE => 0;    # toggle me

##############################################################################
sub new {
  my $class = shift;

  my $this = {
    connections => undef,
    accessControls => $Foswiki::cfg{SqlPlugin}{AccessControl},
    cache => undef,
    defaultDatabase => undef,
    @_
  };
  bless($this, $class);

  foreach my $desc (@{$Foswiki::cfg{SqlPlugin}{Databases}}) {
    my $connection = Foswiki::Plugins::SqlPlugin::Connection->new(%$desc);
    $this->connection($desc->{id}, $connection);
    $this->{defaultDatabase} = $desc->{id} unless defined $this->{defaultDatabase};
  }

  return $this;
}

##############################################################################
sub connection {
  my ($this, $id, $connection) = @_;

  if (defined $connection && defined $id) {
    $this->{connections}{$id} = $connection;
  } else {
    if ($id =~ /^($Foswiki::regex{webNameRegex})\.($Foswiki::regex{topicNameRegex})\[(.*?)\]$/) {
      my $web = $1;
      my $topic = $2;
      my $attachment = $3;
      $connection = Foswiki::Plugins::SqlPlugin::Connection->new(
        id => $id,
        web => $web,
        topic => $topic,
        attachment => $attachment,
      );
    } else {
      $connection = $this->{connections}{$id};
      throw Error::Simple("unknown database '$id'") unless defined $connection;
    }
  }

  return $connection;
}

##############################################################################
sub finish {
  my $this = shift;

  foreach my $id (keys %{$this->{connections}}) {
    $this->connection($id)->disconnect;
  }

  undef $this->{connections};
  undef $this->{cache};
}

##############################################################################
sub execute {
  my ($this, $theDatabase, $theQuery, @thePlaceHolders) = @_;

  $theDatabase = $this->{defaultDatabase} unless defined $theDatabase;

  throw Error::Simple("No Query provided") unless defined $theQuery;

  $this->checkAccess($theDatabase, $theQuery);

  my $connection = $this->connection($theDatabase);

  $connection->connect();

  my $sth = $connection->{db}->prepare_cached($theQuery)
    or throw Error::Simple("Can't prepare cmd '$theQuery': " . $connection->{db}->errstr);

  $sth->execute(@thePlaceHolders)
    or throw Error::Simple("Can't execute cmd '$theQuery': " . $connection->{db}->errstr);

  return $sth;
}

##############################################################################
sub handleSQL {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  my $theDatabase = $params->{database} || $this->{defaultDatabase};
  my $theId = $params->{id};
  my $theQuery = $params->{_DEFAULT} || $params->{query};
  my $theParams = $params->{params} || '';
  my $theDecode = $params->{decode} || '';

  return inlineError("no query") unless defined $theQuery;

  if ($theDecode eq 'url') {
    $theQuery = urlDecode($theQuery);
  } elsif ($theDecode eq 'entity') {
    $theQuery = entityDecode($theQuery);
  }

  #writeDebug("called handleSQL() - " . $theQuery);

  my @bindVals = Text::ParseWords::parse_line('\s*,\s*', 0, $theParams);

  my $result = '';

  try {
    my $connection = $this->connection($theDatabase);
    $this->checkAccess($theDatabase, $theQuery);

    $connection->connect();

    my $sth = $connection->{db}->prepare_cached($theQuery)
      or throw Error::Simple("Can't prepare cmd '$theQuery': " . ($connection->{db}->errstr || ''));

    $sth->execute(@bindVals)
      or throw Error::Simple("Can't execute cmd '$theQuery': " . ($connection->{db}->errstr || ''));

    # cache this statement under the given id
    $this->{cache}{$theId} = {
      sth => $sth,
      connection => $connection,
      bindVals => \@bindVals,
    } if $theId;

    if ($sth->{NUM_OF_FIELDS}) {
      # select statement
      $result = $this->formatResult($params, $sth);
    } else {
      # non-select statement
      $result = $sth->rows();
    }

  } catch Error::Simple with {
    my $msg = shift->{-text};
    $msg =~ s/ at .*?$//gs;
    #$msg .= "<br />for query $theQuery";
    $result = inlineError($msg);
  };

  #writeDebug("result=$result");

  return $result;
}

##############################################################################
sub handleSQLFORMAT {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  my $theId = $params->{_DEFAULT} || $params->{id};
  my $theContinue = $params->{'continue'} || 'off';
  $theContinue = ($theContinue eq 'on') ? 1 : 0;

  my $entry = $this->{cache}{$theId};

  return inlineError("unknown statement '$theId'") unless defined $entry;
  my $sth = $entry->{sth};
  my $connection = $entry->{connection};
  my $bindVals = $entry->{bindVals};

  my $result = '';

  try {
    unless ($theContinue) {
      ($bindVals ? $sth->execute(@{$bindVals}) : $sth->execute)
        or throw Error::Simple("Can't execute again: " . $connection->{db}->errstr);
    }

    $result = $this->formatResult($params, $sth);
  } catch Error::Simple with {
    my $msg = shift->{-text};
    $msg =~ s/ at .*?$//gs;
    $result = inlineError($msg);
  };

  return $result;
}

##############################################################################
sub handleSQLINFO {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  my $theDatabase = $params->{_DEFAULT} || $params->{database};
  my $theFormat = $params->{format} || '$id';
  my $theSeparator = $params->{separator};
  my $theHeader = $params->{header} || '';
  my $theFooter = $params->{footer} || '';

  $theSeparator = ', ' unless defined $theSeparator;

  my @selectedIds = ();

  if ($theDatabase) {
    push @selectedIds, split(/\s*,\s*/, $theDatabase);
  } else {
    push @selectedIds, keys %{$this->{connections}};
  }

  my @result = ();
  foreach my $id (sort @selectedIds) {
    my $connection = $this->connection($id);
    next unless $connection;    # ignore

    my $line = $theFormat;
    $line =~ s/\$id/$id/g;
    $line =~ s/\$dsn/$connection->{dsn}/g;
    $line =~ s/\$nop//g;
    $line =~ s/\$n/\n/g;
    $line =~ s/\$perce?nt/\%/g;
    $line =~ s/\$dollar/\$/g;
    push @result, $line;
  }

  return '' unless @result;
  return $theHeader . join($theSeparator, @result) . $theFooter;
}

##############################################################################
sub formatResult {
  my ($this, $params, $sth) = @_;

  my $theFormat = $params->{format};
  my $theHeader = $params->{header};
  my $theFooter = $params->{footer};
  my $theSeparator = $params->{separator};
  my $theHidenull = $params->{hidenull} || 'off';
  $theHidenull = ($theHidenull eq 'on') ? 1 : 0;
  my $theLimit = $params->{limit} || 0;
  my $theSkip = $params->{skip} || 0;

  if (!defined($theFormat) && !defined($theHeader) && !defined($theFooter)) {
    $theHeader = '<table class="foswikiTable"><thead><tr>';
    foreach my $key (@{$sth->{NAME}}) {
      $theHeader .= "<th> $key </th>";
    }
    $theHeader .= '</tr></thead><tbody>';
    $theFormat = '<tr>';
    foreach my $key (@{$sth->{NAME}}) {
      $key ||= '';
      $theFormat .= "<td> \$$key </td>";
    }
    $theFormat .= '</tr>';
    $theFooter = '</tbody></table>';
  }

  my @lines = ();
  if ($theFormat) {
    my $index = 0;
    while (my $res = $sth->fetchrow_hashref()) {
      $index++;
      next if $theSkip && $index <= $theSkip;
      my $line = $theFormat;

      foreach my $key (keys %$res) {
        my $val = $res->{$key} // '';
        $line =~ s/\$index/$index/g;
        $line =~ s/\$\Q$key\E\b/$val/g;
      }
      push @lines, $line;
      last if $theLimit && $index >= $theLimit;
    }
  }

  my $result = '';
  if (!$theHidenull || @lines) {
    $theHeader ||= '';
    $theFooter ||= '';
    $theSeparator ||= '';
    $result = $theHeader . join($theSeparator, @lines) . $theFooter;
    $result =~ s/\$nop//g;
    $result =~ s/\$n/\n/g;
    $result =~ s/\$perce?nt/\%/g;
    $result =~ s/\$dollar/\$/g;
  }

  return $result;
}

##############################################################################
# Check if the currently logged in user has permission to run
# $theQuery on $theDatabase.  Throws Error::Simple on access failure.
##############################################################################
sub checkAccess {
  my ($this, $theDatabase, $theQuery) = @_;

  my $isAllowed = 1;

  if ($this->{accessControls}) {
    my $user = Foswiki::Func::getWikiName();
    foreach my $access (@{$this->{accessControls}}) {
      next unless $access->{id} eq $theDatabase;

      $isAllowed = 0;

      my $whoPasses = 0;
      my $who = $access->{who};
      if (!defined($who)) {
        $whoPasses = 1;
      } else {
        if ($who eq $user) {
          $whoPasses = 1;
        } elsif (Foswiki::Func::isGroup($who) && Foswiki::Func::isGroupMember($who, $user)) {
          $whoPasses = 1;
        }
      }

      my $queryPasses = 0;
      if (!defined($access->{queries})) {
        $queryPasses = 1;
      } else {

        my $searchQuery = uc $theQuery;

        # convert multiple lines into one
        $searchQuery = join ' ', ($searchQuery =~ /^(.*)$/gm);
        $searchQuery =~ s/\s+/ /g;
        for my $query (@{$access->{queries}}) {
          if ($searchQuery eq $query) {
            $queryPasses = 1;
            last;
          }
          # Trap regexp compilation errors - we don't care.
          eval {
            if ($searchQuery =~ /^\s*$query\s*$/) {
              $queryPasses = 1;
              last;
            }
          };
        }
      }

      if ($whoPasses && $queryPasses) {
        $isAllowed = 1;
        last;
      }
    }
  }

  my $message = $theQuery;
  $message =~ s/\n/ /g;    # remove newlines
  $message .= " [ACCESS DENIED]" unless $isAllowed;

  Foswiki::Func::writeEvent("sql", $message)
    unless exists $Foswiki::cfg{Log}{Action}{sql} && !$Foswiki::cfg{Log}{Action}{sql};

  unless ($isAllowed) {
    $message = "Access control check failed on database '$theDatabase' for query '$theQuery'";
    Foswiki::Func::writeWarning("SqlPlugin", $message);
    throw Error::Simple($message);
  }

  return $isAllowed;
}

################################################################################
# static helpers
sub urlDecode {
  my $text = shift;
  $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;
  return $text;
}

sub entityDecode {
  my $text = shift;

  $text =~ s/&#(\d+);/chr($1)/ge;
  return $text;
}

sub writeDebug {
  print STDERR "- SqlPlugin::Core - $_[0]\n" if TRACE;
  #  Foswiki::Func::writeDebug("SqlPlugin::Core", $_[0]);
}

sub inlineError {
  my $msg = shift;
  $msg =~ s/\%/&#37;/g;

  return "<noautolink><span class='foswikiAlert'>ERROR: $msg </span></noautolink>";
}

1;
