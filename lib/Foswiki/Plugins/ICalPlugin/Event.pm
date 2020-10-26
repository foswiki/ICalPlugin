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

package Foswiki::Plugins::ICalPlugin::Event;

use strict;
use warnings;

use DateTime::Format::ICal ();
use DateTime::TimeZone ();
use Foswiki::Plugins::ICalPlugin::Core ();

use constant TRACE => 0;    # toggle me

###############################################################################
sub new {
  my $class = shift;
  my $entry = shift;

  my $this = bless({
      _entry => $entry,
      @_
    },
    $class
  );

  return $this;
}

###############################################################################
sub DESTROY {
  my $this = shift;

  undef $this->{_entry};
  undef $this->{_start};
  undef $this->{_end};
  undef $this->{_summary};
  undef $this->{_recs};
  undef $this->{_tz};
}

###############################################################################
sub stringify {
  my ($this) = @_;

  return "undef" unless defined $this->{_entry};
  return "" . $this->getPropertyValue("uid") . ": " . $this->start . " - " . $this->end . ": " . $this->summary;
}

###############################################################################
sub entry {
  my ($this, $entry) = @_;

  if (defined $entry) {
    $this->{_entry} = $entry;
    $this->{_start} = undef;
    $this->{_end} = undef;
  }

  return $this->{_entry};
}

###############################################################################
sub tz {
  my $this = shift;

  unless (defined $this->{_tz}) {
    my $tz = DateTime::TimeZone->new(name => "local");
    $this->{_tz} = $tz->name;
  }

  return $this->{_tz};
}

###############################################################################
sub start {
  my ($this, $dt) = @_;

  if (defined $dt) {
    $this->{_start} = $dt;
  } else {
    $this->{_start} = $this->getPropertyDate("dtstart") unless defined $this->{_start};
  }

  $this->{_start} = DateTime::Infinite::Past->new() unless defined $this->{_start};

  return $this->{_start};
}

###############################################################################
sub end {
  my ($this, $dt) = @_;

  if (defined $dt) {
    $this->{_end} = $dt;
  } else {
    $this->{_end} = $this->getPropertyDate("dtend") unless defined $this->{_end};
  }

  $this->{_end} = DateTime::Infinite::Future->new() unless defined $this->{_end};

  return $this->{_end};
}

###############################################################################
sub summary {
  my ($this, $summary) = @_;

  if (defined $summary) {
    $this->{_summary} = $summary;
  } else {
    $this->{_summary} = $this->getPropertyValue("summary") unless defined $this->{_summary};
  }

  return $this->{_summary};
}

###############################################################################
sub getPropertyValue {
  my ($this, $key) = @_;

  my $props = $this->entry->property($key);
  return unless $props;

  my @result = map { $_->value } @$props;
  return wantarray ? @result : $result[0];
}

###############################################################################
sub getPropertyDate {
  my ($this, $key) = @_;

  if (wantarray) {
    my @dates = $this->getPropertyValue($key);
    return unless @dates;
    return map { $this->parseDateTime($_) } @dates;
  } else {
    my $date = $this->getPropertyValue($key);
    return unless defined $date;
    return $this->parseDateTime($date);
  }
}

###############################################################################
sub parseDateTime {
  my ($this, $str) = @_;

  my $dt = DateTime::Format::ICal->parse_datetime($str);
  $dt->set_time_zone($this->tz);

  return $dt;
}

###############################################################################
sub format {
  my ($this, $params) = @_;

  my $format = $params->{format};
  $format = $params->{eventformat} if defined $params->{eventformat};
  $format = '   * $day $mon $year - $location - $summary' unless defined $format;

  if (defined $params->{rangeformat} && defined $this->end && $this->start != $this->end) {
    $format = $params->{rangeformat};
    _writeDebug("found a range: start=" . $this->start . " - end=" . $this->end . ": " . $this->summary);
  }

  #_writeDebug("### called format($format)");

  my $props = $this->entry->properties;

  foreach my $key (keys %$props) {
    next if $key =~ /^_/;

    my $subst = $key;
    if ($key =~ /^dt(start|end|stamp)$/) {
      $subst = $1;
    } elsif ($key eq 'last-modified') {
      $subst = 'modified';
    }

    my $val;

    if ($key eq 'created') {
      $val = $this->getPropertyDate($key);
      $format = _formatTime($val, $format, "c");
    } elsif ($key eq 'dtstart') {
      $val = $this->start;
      $format = _formatTime($val, $format);
    } elsif ($key eq 'dtend') {
      $val = $this->end;
      $format = _formatTime($val, $format, "e");
    } elsif ($key eq 'last-modified') {
      $val = $this->getPropertyDate($key);
      $format = _formatTime($val, $format, "m");
    } else {
      $val = $this->getPropertyValue($key) // '';
      $format =~ s/\$plainify\(\s*$subst\s*\)/_plainify($val)/ge;
      $format =~ s/\$$subst/$val/g;
    }
  }

  #_writeDebug("### result = $format");

  return $format;
}

###############################################################################
sub _formatTime {
  my ($dt, $formatString, $prefix) = @_;

  return '' unless defined $formatString && defined $dt;

  $prefix ||= '';

  my $value = $formatString;
  $value =~ s/\$${prefix}seco?n?d?s?/sprintf('%.2u',$dt->second)/gei;
  $value =~ s/\$${prefix}minu?t?e?s?/sprintf('%.2u',$dt->minute)/gei;
  $value =~ s/\$${prefix}hour?s?/sprintf('%.2u',$dt->hour)/gei;
  $value =~ s/\$${prefix}day/sprintf('%.2u',$dt->day)/gei;
  $value =~ s/\$${prefix}wday/$dt->day_name/gei;
  $value =~ s/\$${prefix}dow/$dt->dow/gei;
  $value =~ s/\$${prefix}week/$dt->week_number/gei;
  $value =~ s/\$${prefix}mont?h?/$dt->month_abbr/gei;
  $value =~ s/\$${prefix}mo/$dt->month/gei;
  $value =~ s/\$${prefix}year?/sprintf('%.4u',$dt->year)/gei;
  $value =~ s/\$${prefix}ye/sprintf('%.2u',$dt->year()%100)/gei;
  $value =~ s/\$${prefix}epoch/$dt->epoch/gei;
  $value =~ s/\$${prefix}tz/$dt->time_zone_short_name/gei;

  return $value;
}

###############################################################################
sub _writeDebug {
  my $msg = shift;
  print STDERR "ICalPlugin::Event - $msg\n" if TRACE;
}

###############################################################################
sub _plainify {
  my ($text) = @_;

  return "" unless defined $text;

  $text =~ s/<nop>//g;    # remove foswiki pseudo markup
  $text =~ s/<!--.*?-->//gs;    # remove all HTML comments
  $text =~ s/\&[a-z]+;/ /g;     # remove entities
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$2/g;
  $text =~ s/<[^>]*>//g;        # remove all HTML tags
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;    # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;    # remove heading formatting and hbar
  $text =~ s/^\s+//;                    # remove leading whitespace
  $text =~ s/\s+$//;                    # remove trailing whitespace
  $text =~ s/['"]//;
  $text =~ s/%\w+(?:\{.*?\})?%//g;      # remove macros
  $text =~ s/[\n\r]+/ /g;               # remove linefeeds

  return $text;
}

###############################################################################
sub unfoldRecurrences {
  my ($this, $span, $exceptions) = @_;

  my @rrules = $this->getPropertyValue("rrule");
  return unless @rrules;

  # gather recurrences
  my $set = DateTime::Set->empty_set;
  foreach my $rule (@rrules) {
    _writeDebug("   -> rrule=$rule");
    my $recur = DateTime::Format::ICal->parse_recurrence(recurrence => $rule,);
    $set = $set->union($recur);
  }
  return if $set->is_empty_set;

  # handle EXDATE
  #my @exDates = $this->getPropertyDate("exdate");

  my $iter = $set->iterator(span => $span);
  my $found = 0;

  $this->{_recs} = undef;

  my $uid = $this->getPropertyValue("uid");
  while (my $dt = $iter->next) {

    my $foundException;
    if (defined($exceptions) && $exceptions->{$uid}) {
      foreach my $item (@{$exceptions->{$uid}}) {
        if (DateTime->compare($dt, $item->{replace}) == 0) {
          $foundException = $item->{event};
          _writeDebug("   -> replacing date $item->{replace}");
          last;
        }
      }
    }
    my $recEvent = $this->clone;

    if ($foundException) {
      $recEvent->start($foundException->start);
      $recEvent->end($foundException->end);
      _writeDebug("   -> exception start=" . ($recEvent->start // 'undef') . ", end=" . ($recEvent->end // 'undef') . ", summary=" . $this->summary) if TRACE;
    } else {
      $recEvent->start(
        $this->start->clone->set(
          year => $dt->year,
          month => $dt->month,
          day => $dt->day,
        )
      );
      $recEvent->end(
        $this->end->clone->set(
          year => $dt->year,
          month => $dt->month,
          day => $dt->day,
        )
      );
      _writeDebug("   -> recurrence start=" . ($recEvent->start // 'undef') . ", end=" . ($recEvent->end // 'undef') . ", summary=" . $recEvent->summary) if TRACE;
    }

    # remove exdates
    push @{$this->{_recs}}, $recEvent;
    $found = 1;
  }

  return $this->{_recs};
}

###############################################################################
sub clone {
  my ($this) = @_;

  my $clone = Foswiki::Plugins::ICalPlugin::Event->new($this->entry);

  return $clone;
}

1;
