package Weather::Product::NWS;
require 5.004;
require Exporter;

use vars qw($VERSION);
$VERSION = "1.0.0";

@ISA = qw(Weather::Product);
@EXPORT = qw();
@EXPORT_OK = qw();

use Carp;
use FileHandle;
use LWP::UserAgent;
use Time::Local;

require Weather::WMO;
require Weather::PIL;
require Weather::UGC;
require Weather::Product;

sub initialize {
    my $self = shift;
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
    my $line,
       $level = 0,
       $that;

    # allows us to update the same object

    my $this = $self->{$count}++;
    $self->{data}->{$this}->{text} = "";

    foreach $line (split /\n/, $product)
    {
        $line =~ s/\s+$//g;	# clean trailing spaces/carriage returns

        if ($level) {
            $self->{data}->{$this}->{text} .= $line."\n";
        }

        if (($level==3) and ($line =~ m/^\=|\$\$/)) {
            $self->{data}->{$that}->{len} = (length($self->{data}->{$this}->{text})
                - length($line) - $self->{data}->{$that}->{start} - 1
            );
            --$level;
        }
        elsif (($level==2) and (Weather::UGC::valid($line)))
        {
            $that = $self->{count}++;

            $self->{data}->{$that}->{WMO} = $self->{WMO};
            $self->{data}->{$that}->{PIL} = $self->{PIL};
            $self->{data}->{$that}->{UGC} = new Weather::UGC($line);

            $self->{data}->{$that}->{ptr} = $this;
            $self->{data}->{$that}->{start} = length($self->{data}->{$this}->{text});

            foreach ($self->{data}->{$that}->{UGC}->zones) {
                $self->add($_, $that);
            }

            ++$level;
        }
        elsif (($level==1) and (Weather::PIL::valid($line)))
        {
            my $that = $self->{count}++;

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
    }
}


sub pointer { # given a zone, it returns a pointer to current product
    my $self = shift;
    my $id = shift;

    my $field = shift;
    my $ptr;

    unless (defined($id)) {
        return undef;
    }
    $ptr = $self->{products}->{$id};

    if (defined($self->{data}->{$ptr}))
    {
        if (defined($field)) {
            return $self->{data}->{$ptr}->{$field};
        } else {
            return $self->{data}->{$ptr};
        }
    } else
    {
        return undef;
    }
}

sub text {
    my $self = shift;
    my $id = shift;

    my $ptr = $self->{products}->{$id};

    unless (defined($self->{data}->{$ptr}->{text})) {
        my $start = 0, $len;

        $start = $self->{data}->{$ptr}->{start};

        $len = $self->{data}->{$ptr}->{len};
        unless (defined($len)) { $len = 999999; }

        $ptr = $self->{data}->{$ptr}->{ptr};

        return substr($self->{data}->{$ptr}->{text}, $start, $len);
    }
    return $self->{data}->{$ptr}->{text};
}

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
                or croak "$self is not an object";

    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion

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

