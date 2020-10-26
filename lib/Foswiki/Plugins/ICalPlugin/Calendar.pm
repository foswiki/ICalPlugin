# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ICalPlugin is Copyright (C) 2011-2020 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::ICalPlugin::Calendar;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::ICalPlugin::Event ();
use Error qw(:try);
use Digest::MD5 ();
use Cache::FileCache ();
use DateTime::Span ();
use DateTime::Set ();
use DateTime::Format::ICal ();
use Data::ICal ();
use DateTime::Duration ();

# SMELL: these are here to please Storable in Cache::FileCache
use Data::ICal::Entry::Alarm::Display ();
use Data::ICal::Entry::Alarm::Email ();
use Data::ICal::Entry::Event ();
use Data::ICal::Entry::TimeZone ();
use Data::ICal::Entry::TimeZone::Daylight ();
use Data::ICal::Entry::TimeZone::Standard ();
# end SMELL

use constant TRACE => 0;    # toggle me
#use Data::Dump qw(dump);

###############################################################################
sub new {
  my $class = shift;

  my $this = bless({
      cacheExpire => $Foswiki::cfg{ICalPlugin}{CacheExpire} || '1 d',
      cacheDir => Foswiki::Func::getWorkArea('ICalPlugin') . '/cache',
      timeout => $Foswiki::cfg{ICalPlugin}{TimeOut} || 10,
      agent => $Foswiki::cfg{ICalPlugin}{Agent} || 'Mozilla/5.0',
      @_
    },
    $class
  );

  return $this;
}

###############################################################################
sub DESTROY {
  my $this = shift;

  undef $this->{_cache};
  undef $this->{_client};
  undef $this->{_ical};
}

###############################################################################
sub getEvents {
  my ($this, $span) = @_;

  my $index = 0;
  my @events = ();
  my $exceptions = $this->getExceptions($span);

  foreach my $entry (@{$this->ical->entries()}) {
    next unless $entry->ical_entry_type() eq 'VEVENT';

    $index++;
    my $event = Foswiki::Plugins::ICalPlugin::Event->new($entry);

    next if $event->getPropertyValue("recurrence-id");

    unless (defined $event->start) {
      print STDERR "ERROR: invalid event\n";
      print STDERR $entry->as_string;
      next;
    }

    _writeDebug("### $index - " . $event->stringify) if TRACE;
    #_writeDebug($entry->as_string) if TRACE;

    my $recs = $event->unfoldRecurrences($span, $exceptions);
    if ($recs) {
      _writeDebug("   -> adding recurrences");
      foreach my $recEvent (@$recs) {
        _writeDebug("   -> " . $recEvent->stringify);
        push @events, $recEvent;
      }
    } else {
      my $thisSpan = DateTime::Span->from_datetimes(
        start => $event->start,
        end => $event->end,
      );

      if ($span->contains($thisSpan)) {
        _writeDebug("   -> adding");
        push @events, $event;
      } else {
        _writeDebug("   -> skipping");
      }
    }

  }

  return @events;
}

###############################################################################
sub getExceptions {
  my ($this, $span) = @_;

  my %exceptions = ();

  foreach my $entry (@{$this->ical->entries()}) {
    my $event = Foswiki::Plugins::ICalPlugin::Event->new($entry);
    my $rec = $event->getPropertyDate("recurrence-id");
    next unless defined $rec;

    if (defined $span) {
      my $thisSpan = DateTime::Span->from_datetimes(
        start => $event->start,
        end => $event->end,
      );
      next unless $span->contains($thisSpan);
    }

    my $uid = $event->getPropertyValue("uid");
    #print "### exception for $uid - " . $event->summary."\n";

    push @{$exceptions{$uid}},
      {
      replace => $rec->set(
        hour => 0,
        minute => 0,
        second => 0,
        nanosecond => 0
      ),
      event => $event,
      };
  }

  return \%exceptions;
}

###############################################################################
sub ical {
  my ($this, $ical) = @_;

  $this->{_ical} = $ical if $ical;

  return $this->{_ical};
}

###############################################################################
sub parseData {
  my ($this, $data, $key, $expire) = @_;

  $key ||= _cache_key($data);
  my $ical = $this->_cache->get($key);

  if ($ical) {
    _writeDebug("found ical $key in cache");
  } else {
    $ical = Data::ICal->new(data => $data);
    _writeDebug("caching ical for $key");
    $this->_cache->set($key, $ical, $expire);
  }

  return $this->ical($ical);
}

###############################################################################
sub getDataFromUrl {
  my ($this, $url, $expire) = @_;

  my $data = $this->_getExternalResource($url, $expire);
  return $this->parseData($data, $url . '::ICAL', $expire);
}

###############################################################################
sub _getExternalResource {
  my ($this, $url, $expire) = @_;

  my $content;
  my $contentType;

  $url =~ s/\/$//;

  my $bucket = $this->_cache->get(_cache_key($url));

  if (defined $bucket) {
    $content = $bucket->{content};
    $contentType = $bucket->{type};
    _writeDebug("found content for $url in cache contentType=$contentType");
  }

  unless (defined $content) {
    my $client = $this->_client;
    my $res = $client->get($url);

    throw Error::Simple("error fetching url")
      unless $res;

    unless ($res->is_success) {
      _writeDebug("url=$url, http error=" . $res->status_line);
      throw Error::Simple("http error fetching url: " . $res->code . " - " . $res->status_line);
    }

    _writeDebug("http status=" . $res->status_line);

    $content = $res->decoded_content();
    $contentType = $res->header('Content-Type');
    _writeDebug("content type=$contentType");

    _writeDebug("caching content for $url");
    $this->_cache->set(_cache_key($url), {content => $content, type => $contentType}, $expire);
  }

  return ($content, $contentType) if wantarray;
  return $content;
}

sub _cache_key {
  return _untaint(Digest::MD5::md5_hex($_[0]));
}

sub _untaint {
  my $content = shift;
  if (defined $content && $content =~ /^(.*)$/s) {
    $content = $1;
  }
  return $content;
}

sub _cache {
  my $this = shift;

  unless ($this->{cache}) {
    $this->{_cache} = new Cache::FileCache({
        default_expires_in => $this->{cacheExpire},
        cache_root => $this->{cacheDir},
        directory_umask => 077,
      }
    );
  }

  return $this->{_cache};
}

sub _client {
  my $this = shift;

  unless (defined $this->{_client}) {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    $ua->timeout($this->{timeout});
    $ua->agent($this->{agent});

    my $attachLimit = Foswiki::Func::getPreferencesValue('ATTACHFILESIZELIMIT') || 0;
    $attachLimit =~ s/[^\d]//g;
    if ($attachLimit) {
      $attachLimit *= 1024;
      $ua->max_size($attachLimit);
    }

    my $proxy = $Foswiki::cfg{PROXY}{HOST};
    if ($proxy) {
      $ua->proxy(['http', 'https'], $proxy);

      my $proxySkip = $Foswiki::cfg{PROXY}{NoProxy};
      if ($proxySkip) {
        my @skipDomains = split(/\s*,\s*/, $proxySkip);
        $ua->no_proxy(@skipDomains);
      }
    }

    $ua->ssl_opts(
      verify_hostname => 0,    # SMELL
    );

    $this->{_client} = $ua;
  }

  return $this->{_client};
}

###############################################################################
sub clearCache {
  my ($this, $key) = @_;

  if ($key) {
  } else {
    $this->_cache->clear;
  }
}

###############################################################################
sub purgeCache {
  my $this = shift;

  $this->_cache->purge;
}

###############################################################################
sub _writeDebug {
  my $msg = shift;
  print STDERR "ICalPlugin::Calendar - $msg\n" if TRACE;
}

1;
