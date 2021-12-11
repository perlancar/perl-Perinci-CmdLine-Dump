package Perinci::CmdLine::Base::Patch::DumpAndExit;

use 5.010001;
use strict;
no warnings;

use Data::Dump;
use Module::Patch qw();
use base qw(Module::Patch);

# AUTHORITY
# DATE
# DIST
# VERSION

our %config;

sub _dump {
    print "# BEGIN DUMP $config{-tag}\n";
    dd @_;
    print "# END DUMP $config{-tag}\n";
}

sub patch_data {
    return {
        v => 3,
        patches => [
            {
                action      => 'replace',
                sub_name    => 'run',
                code        => sub {
                    my $self = shift;
                    $self->{'x.main.spec'} = \%main::SPEC;
                    _dump($self);
                    $config{-exit_method} eq 'exit' ? exit(0) : die;
                },
            },
        ],
        config => {
            -tag => {
                schema  => 'str*',
                default => 'TAG',
            },
            -exit_method => {
                schema  => 'str*',
                default => 'exit',
            },
        },
   };
}

1;
# ABSTRACT: Patch Perinci::CmdLine::Base to dump object + exit on run()

=for Pod::Coverage ^(patch_data)$

=head1 DESCRIPTION

This patch can be used to extract Perinci::CmdLine object information from a
script by running the script but exiting early after getting the object dump.
