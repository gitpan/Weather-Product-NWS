package Weather::Product::NWS;
require 5.004;
require Exporter;

=head1 NAME

Weather::Product::NWS - routines for parsing NWS weather products

=head1 DESCRIPTION

Weather::Product::NWS is a module for parsing U.S. National Weather Service
(NWS) weather products. Products can be fetched from local files, URLs, or
parsed directly from pre-fetched data.

Weather products are organized by zones and counties (as well as WMO and
AWIPS Product IDs) along with relevant timestamps and expiration dates.

=head1 EXAMPLE

=cut

use vars qw($VERSION $AUTOLOAD);
$VERSION = "1.0.3";

@ISA = qw(Weather::Product);
@EXPORT = qw();
@EXPORT_OK = qw();

use Carp;

require Weather::WMO;
require Weather::PIL;
require Weather::UGC;
require Weather::Product;	# VERSION >= 1.2.2

sub initialize {
    my $self = shift;
    $self->{PIL} = undef;
}

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new();
    $self->initialize;
    $self->import (@_);
    bless $self, $class;
    return $self;
}

sub parse {
    my $self = shift;
    my $product = shift;
    my $line, $line_last = '';
       $level = 0,
       $that;

    # allows us to update the same object

    my $this = ++$self->{$count};
    $self->{data}->{$this}->{text} = "";

    foreach $line (split /\n/, $product)
    {
        $line =~ s/\s+$//g;	# clean trailing spaces/carriage returns

        if ($level) {
            $self->{data}->{$this}->{text} .= $line."\n";
        }

        if (($level) and ($line_last =~ m/\-$/)) {
            $line = $line_last . $line;
        }

        if (($level==3) and ($line =~ m/^\=|\$\$/)) {
            $self->{data}->{$that}->{len} = (length($self->{data}->{$this}->{text})
                - length($line) - $self->{data}->{$that}->{start} - 1
            );
            --$level;
        }
        elsif (($level>0) and ($level<3) and (Weather::UGC::valid($line)))
        {

            $that = ++$self->{count};

            $self->{data}->{$that}->{WMO} = $self->{WMO};
            $self->{data}->{$that}->{PIL} = $self->{PIL};
            $self->{data}->{$that}->{UGC} = new Weather::UGC($line);

            $self->{data}->{$that}->{ptr} = $this;
            $self->{data}->{$that}->{start} = length($self->{data}->{$this}->{text});

            foreach ($self->{data}->{$that}->{UGC}->zones) {
                $self->add($_, $that);
            }

            $level=3;
        }
        elsif (($level==1) and (Weather::PIL::valid($line)))
        {
            $that = ++$self->{count};

            $self->{data}->{$that}->{WMO} = $self->{WMO};
            $self->{data}->{$that}->{PIL} = new Weather::PIL($line);
            if (defined($self->{PIL})) {
                unless ($self->{PIL}->cmp( $self->{data}->{$that}->{PIL})) {
                    croak "Cannot import different product types";
                }
            } else {
                $self->{PIL} = $self->{data}->{$that}->{PIL};
            }
            $self->{data}->{$that}->{ptr} = $this;
            $self->{data}->{$that}->{start} = length($self->{data}->{$this}->{text});

            $self->add($self->{WMO}->station . $self->{PIL}->PIL, $that);
            $self->add($self->{PIL}->PIL, $that);

            ++$level;
        }
        elsif (($level==0) and (Weather::WMO::valid($line)))
        {
            # To-do: check if this is a later addition/amendment

            $self->{data}->{$this}->{WMO} = new Weather::WMO($line);
            if (defined($self->{WMO})) {
                unless ($self->{WMO}->cmp( $self->{data}->{$this}->{WMO})) {
                    croak "Cannot import different product types";
                }
            } else {
                $self->{WMO} = $self->{data}->{$this}->{WMO};
            }
            ++$level;
            $self->add($self->{WMO}->product, $this);
        }
        $line_last = $line;
    }
    $self->SUPER::purge();
}

sub purge {
    my $self = shift;
    my $class = ref($self) || $self;

    my @purge_list = @_;

    foreach ($self->products()) {
        if (defined($self->expires($_))) {
            if ($self->expires($_)<=time) {
                push @purge_list, $_;
            }
        }
    }

    $self->SUPER::purge(@purge_list);
}

sub expires {
    my $self = shift;
    my $id = shift;

    my $UGC = $self->pointer($id, 'UGC');
   
    if (defined($UGC)) {
        return Weather::Product::int_time( $UGC->expires );
    } else {
        return undef;
    }
}

sub text {
    my $self = shift;
    my $id = shift;

    my $ptr = $self->pointer($id);

    unless (defined($ptr->{text}))
    {
        my $start = 0, $len;

        $start = $ptr->{start};

        $len = $ptr->{len};
        unless (defined($len))
        {
            $len = 999999;	# weather products are never this long
        }

        $ptr = $ptr->{ptr};

        return substr($self->{data}->{$ptr}->{text}, $start, $len);
    }
    return $ptr->{text};
}

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
                or croak "$self is not an object";

    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion

    if (grep(/^$name$/,	# settable (global) properties
        qw(max_age)
    )) {
        if (@_) {
            return $self->{$name} = shift;
        } else {
            return $self->{$name};
        }
    }

    if (grep(/^$name$/,
        qw(WMO PIL UGC)
    )) {
        if (@_) {
            return $self->pointer(@_, $name);
        } else {
            croak "Method `$name' requires arguments in class $type";
        }
    } else {
        croak "Can't access `$name' in class $type";
    }

}

1;

__END__

=pod

=head1 KNOWN BUGS

This version of the module does not (yet) handle addendums or multi-part
weather products.

Other issues with returning the I<time> are are a limitation of the WMO
header format, not this module.

=head1 SEE ALSO

F<Weather::WMO>, F<Weather::PIL>, F<Weather::UGC> and F<Weather::Product>.

Perusing documentation on the format of WMO-style weather products online from
the U.S. National Weather Service http://www.nws.noaa.gov may also be of help.

=head1 DISCLAIMER

I am not a meteorologist nor am I associated with any weather service.
This module grew out of a hack which would fetch weather reports every
morning and send them to my pager. So I said to myself "Why not do this
the I<right> way..." and spent a bit of time surfing around the web
looking for documentation about this stuff....

=head1 AUTHOR

Robert Rothenberg <wlkngowl@unix.asb.com>

=cut

