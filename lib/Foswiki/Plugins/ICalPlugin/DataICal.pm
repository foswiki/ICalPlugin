package Foswiki::Plugins::ICalPlugin::DataICal;

use warnings;
use strict;

use Data::ICal ();
our @ISA = ('Data::ICal');

sub parse_object {
    my ( $self, $object ) = @_;

    my $type = lc($object->{type} || '');

    if ($type eq 'vtodo') {
      return {};
    }

    if ($type eq 'vevent') {
      # clear all subobjects of events;
      # at least valarms provokes an Insecure dependency in eval while running with -T switch warning
      $object->{objects} = undef;
    }


    return $self->SUPER::parse_object($object);
}

1;
