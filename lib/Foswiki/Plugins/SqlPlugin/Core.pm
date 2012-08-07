# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
# 
# Copyright (C) 2009-2010 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Plugins::SqlPlugin::Connection ();
use Error qw( :try );
use Foswiki::Sandbox ();

our $baseWeb;
our $baseTopic;
our %connections;
our %accessControls;
our %cache;
our $defaultDatabase;

use constant DEBUG => 0; # toggle me

###############################################################################
sub writeDebug {
  print STDERR "- SqlPlugin::Core - $_[0]\n" if DEBUG;
#  Foswiki::Func::writeDebug("SqlPlugin::Core", $_[0]);
}

##############################################################################
sub init {
  ($baseWeb, $baseTopic) = @_;

  foreach my $desc (@{$Foswiki::cfg{SqlPlugin}{Databases}}) {
    my $connection = new Foswiki::Plugins::SqlPlugin::Connection(%$desc);
    $connections{$desc->{id}} = $connection;
    $defaultDatabase = $desc->{id} unless $defaultDatabase;
  }

  if (exists $Foswiki::cfg{SqlPlugin}{AccessControl} && $Foswiki::cfg{SqlPlugin}{AccessControl}) {
    foreach my $ac (@{$Foswiki::cfg{SqlPlugin}{AccessControl}}) {
      my $id = $ac->{id};
      my %ac2;
      $ac2{who} = $ac->{who}
        if $ac->{who};
#      $ac2{queries} = [ map { uc $_ } @{$ac->{queries}} ]
      # This fails horribly for regexes :-(
      $ac2{queries} = $ac->{queries}
        if $ac->{queries};
      push @{$accessControls{$id}}, \%ac2;
    }
  }
}

##############################################################################
sub finish {
  undef %connections;
  undef %cache;
}

##############################################################################
sub inlineError {
  my $msg = shift;
  $msg =~ s/\%/&#37;/g;

  return "<noautolink><span class='foswikiAlert'>ERROR: $msg </span></noautolink>";
}

##############################################################################
sub handleExecute {
  my ($theDatabase, $theQuery, @thePlaceHolders) = @_;
  $theDatabase
    or $theDatabase = $defaultDatabase;
  $theQuery
    or throw Error::Simple("No Query provided");

  checkAccess($theDatabase, $theQuery);

  my $connection = $connections{$theDatabase}
    or throw Error::Simple("unknown database '$theDatabase'");

  $connection->connect();

  my $sth = $connection->{db}->prepare_cached($theQuery)
    or throw Error::Simple("Can't prepare cmd '$theQuery': ".$connection->{db}->errstr);
  $sth->execute(@thePlaceHolders)
    or throw Error::Simple("Can't execute cmd '$theQuery': ".$connection->{db}->errstr);
  return $sth;
}

##############################################################################
sub handleSQL {
  my ($session, $params, $theTopic, $theWeb) = @_;

  my $theDatabase = exists $params->{database}
    ? $params->{database}
    : $defaultDatabase;
  my $theId = $params->{id};
  my $theQuery = $params->{_DEFAULT} || $params->{query};
  my $theParams = $params->{params} || '';
  my $theDecode = $params->{decode} || '';

  if ($theDecode eq 'url') {
    $theQuery = urlDecode($theQuery);
  } elsif ($theDecode eq 'entity') {
    $theQuery = entityDecode($theQuery);
  }

  #writeDebug("called handleSQL() - " . $theQuery);

  my @bindVals = split '\s*,\s*', $theParams;

  my $connection = $connections{$theDatabase};
  return inlineError("unknown database '$theDatabase'") unless $connection;
  return inlineError("no query") unless defined $theQuery;

  my $result = '';

  try {
    checkAccess($theDatabase, $theQuery);

    $connection->connect();

    my $sth = $connection->{db}->prepare_cached($theQuery) or
      throw Error::Simple("Can't prepare cmd '$theQuery': ".$connection->{db}->errstr);

    $sth->execute(@bindVals) or 
      throw Error::Simple("Can't execute cmd '$theQuery': ".$connection->{db}->errstr);

    # cache this statement under the given id
    $cache{$theId} = {
      sth => $sth,
      connection => $connection,
    } if $theId;

    if($sth->{NUM_OF_FIELDS}) {
      # select statement
      $result = formatResult($params, $sth);
    } else {
      # non-select statement
      $result = $sth->rows();
    }


  } catch Error::Simple with {
    my $msg = shift->{-text};
    $msg =~ s/ at .*?$//gs;
    $msg .= "<br>for query $theQuery";
    $result = inlineError($msg);
  };

  #writeDebug("result=$result");

  return $result;
}

##############################################################################
sub handleSQLFORMAT {

  my ($session, $params, $theTopic, $theWeb) = @_;

  my $theId = $params->{_DEFAULT} || $params->{id};
  my $theContinue = $params->{'continue'} || 'off';
  $theContinue = ($theContinue eq 'on')?1:0;

  my $entry = $cache{$theId};

  return inlineError("unknown statement '$theId'") unless defined $entry;
  my $sth = $entry->{sth};
  my $connection = $entry->{connection};
  
  my $result = '';

  try {

    unless ($theContinue) {
      $sth->execute or 
        throw Error::Simple("Can't execute again: ".$connection->{db}->errstr);
    }

    $result = formatResult($params, $sth);
  } catch Error::Simple with {
    my $msg = shift->{-text};
    $msg =~ s/ at .*?$//gs;
    $result = inlineError($msg);
  };

  return $result;
}

##############################################################################
sub handleSQLINFO {
  my ($session, $params, $theTopic, $theWeb) = @_;

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
    push @selectedIds, keys %connections;
  }
  
  my @result = ();
  foreach my $id (@selectedIds) {
    my $connection = $connections{$id};
    next unless $connection;# ignore

    my $line = $theFormat;
    $line =~ s/\$id/$id/g;
    $line =~ s/\$dsn/$connection->{dsn}/g;
    $line =~ s/\$nop//go;
    $line =~ s/\$n/\n/go;
    $line =~ s/\$perce?nt/\%/go;
    $line =~ s/\$dollar/\$/go;
    push @result, $line;
  }

  return '' unless @result;
  return $theHeader.join($theSeparator, @result).$theFooter;
}


##############################################################################
sub formatResult {
  my ($params, $sth) = @_;
  
  my $theFormat = $params->{format};
  my $theHeader = $params->{header};
  my $theFooter = $params->{footer};
  my $theSeparator = $params->{separator};
  my $theHidenull = $params->{hidenull} || 'off';
  $theHidenull = ($theHidenull eq 'on')?1:0;
  my $theLimit = $params->{limit} || 0;
  my $theSkip = $params->{skip} || 0;

  if (!defined($theFormat) && !defined($theHeader) && !defined($theFooter)) {
    $theHeader = '<table class="foswikiTable"><tr>';
    foreach my $key (@{$sth->{NAME}}) {
      $theHeader .= "<th> $key </th>";
    }
    $theHeader .= '</tr>';
    $theFormat = '<tr>';
    foreach my $key (@{$sth->{NAME}}) {
      $key ||= '';
      $theFormat .= "<td> \$$key </td>";
    }
    $theFormat .= '</tr>';
    $theFooter = '</table>'
  }

  my @lines = ();
  if ($theFormat) {
    my $index = 0;
    while (my $res = $sth->fetchrow_hashref() ) {
      $index++;
      next if $theSkip && $index <= $theSkip;
      my $line = $theFormat;

      foreach my $key (keys %$res) {
        my $val = $res->{$key} || '';
        $line =~ s/\$index/$index/g;
        $line =~ s/\$\Q$key/$val/g;
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
    $result = $theHeader.join($theSeparator, @lines).$theFooter;
    $result =~ s/\$nop//go;
    $result =~ s/\$n/\n/go;
    $result =~ s/\$perce?nt/\%/go;
    $result =~ s/\$dollar/\$/go;
  }

  return $result;
}

##############################################################################
# Check if the currently logged in user has permission to run
# $theQuery on $theDatabase.  Thows Error::Simple on access failure.
##############################################################################
sub checkAccess {
  my ($theDatabase, $theQuery) = @_;
  my $ret = _checkAccess(@_);

  my $message = $theQuery;
  $message =~ s/\n/ /g; # remove newlines
  if (! $ret) {
    $message .= " [ACCESS DENIED]";
  }
  Foswiki::Func::writeEvent("sql", $message);

  if (! $ret) {
    Foswiki::Func::writeWarning("SqlPlugin", "Access control check failed on database '$theDatabase' for query '$theQuery'");
    throw Error::Simple("Access control check failed on database $theDatabase for query $theQuery");
  }
}

sub _checkAccess {
  my ($theDatabase, $theQuery) = @_;

  if (! %accessControls || ! exists $accessControls{$theDatabase}) {
    return 1;
  }

  my $user = Foswiki::Func::getWikiName();
  foreach my $access (@{$accessControls{$theDatabase}}) {

    my $whoPasses = 0;
    if (! exists $access->{who} ) {
      $whoPasses = 1;
    } else {
      my $who = $access->{who};
      if ($who eq $user) {
        $whoPasses = 1;
      } elsif ( Foswiki::Func::isGroupMember( $who)) {
        $whoPasses = 1;
      }
    }

    my $queryPasses = 0;
    if (! exists $access->{queries} ) {
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
      	}
      }
    }

    if ($whoPasses && $queryPasses) {
      return 1;
    }
  }

  return undef;
}


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

1;
