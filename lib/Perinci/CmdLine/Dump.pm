package Perinci::CmdLine::Dump;

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);

# AUTHORITY
# DATE
# DIST
# VERSION

our @EXPORT_OK = qw(
                       dump_pericmd_script
                       dump_perinci_cmdline_script
               );

our %SPEC;

$SPEC{dump_pericmd_script} = {
    v => 1.1,
    summary => 'Run a Perinci::CmdLine-based script but only to '.
        'dump the object',
    description => <<'_',

This function runs a CLI script that uses `Perinci::CmdLine` (or its variant
`Perinci::CmdLine::Lite` or `Perinci::CmdLine::Any`) but monkey-patches
`Perinci::CmdLine::Base` beforehand so that `run()` will dump the object and
then exit. The goal is to get the object without actually running the script.

This can be used to gather information about the script and then generate
documentation about it (e.g. `Pod::Weaver::Plugin::Rinci` to insert POD sections
based on information from the Rinci metadata of the function used by the script)
or do other things (e.g. `App::shcompgen` to generate a completion script for
the original script).

CLI script needs to use `Perinci::CmdLine`. This is detected currently by a
simple regex. If script is not detected as using `Perinci::CmdLine`, status 412
is returned.

Will return the `Perinci::CmdLine` object dump. In addition to that, if detected
that script refers to function URL `/main` (which might mean that function
metadata is embedded in the script itself and not in a separate module), will
also dump the target function's metadata in `func.meta` in this function's
result metadata.

_
    args => {
        filename => {
            summary => 'Path to the script',
            schema => 'str*',
            req => 1,
            pos => 0,
            cmdline_aliases => {f=>{}},
        },
        libs => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'lib',
            summary => 'Libraries to unshift to @INC when running script',
            schema  => ['array*' => of => 'str*'],
            cmdline_aliases => {I=>{}},
        },
        skip_detect => {
            schema => ['bool', is=>1],
            cmdline_aliases => {D=>{}},
        },
        method => {
            schema => ['str*', in=>['patch', 'self-dump']],
            description => <<'_',

The `patch` method is using monkey-patching to replace run() with a routine that
dumps the object and exit. This has a disadvantage of exiting too early, for
example some attributes like `common_opts` is filled during run(). Another
method is `self-dump` that requires <pm:Perinci::CmdLine::Lite> version 1.73 or
later.

The default is to use `self-dump`, but `patch` for /main/.

_
        },
    },
};
sub dump_pericmd_script {
    require Capture::Tiny;
    require Perinci::CmdLine::Util;
    require Scalar::Util;
    require UUID::Random;

    my %args = @_;

    my $filename = $args{filename} or return [400, "Please specify filename"];
    my $detres;
    if ($args{skip_detect}) {
        $detres = [200, "OK (skip_detect)", 1, {"func.reason" => "skip detect, forced"}];
    } else {
        $detres = Perinci::CmdLine::Util::detect_perinci_cmdline_script(
            filename => $filename);
        return $detres if $detres->[0] != 200;
        return [412, "File '$filename' is not script using Perinci::CmdLine (".
                    $detres->[3]{'func.reason'}.")"] unless $detres->[2];
    }

    my $res = [200, "OK", undef, {
        'func.detect_res' => $detres,
    }];

    # dump pericmd-inline script as if it were pericmd-lite script, but strips
    # the extra stuffs not yet supported by pericmd-inline
    if ($detres->[3]{'func.is_inline'}) {
        my $attrs = $detres->[3]{'func.pericmd_inline_attrs'};
        if (!$attrs) {
            return [412, "Script is Perinci::CmdLine::Inline script, but ".
                        "can't dump its attributes"];
        }
        require Perinci::CmdLine::Lite;
        $res->[2] = Perinci::CmdLine::Lite->new(
            %$attrs,
        );
        goto RETURN_RES;
    }

    my $libs = $args{libs} // [];

    my $tag = UUID::Random::generate();
    my ($stdout, $stderr, $exit) = Capture::Tiny::capture(
        sub {
            my $meth = $args{method} // 'self-dump';
            if ($meth eq 'self-dump') {
                local $ENV{PERINCI_CMDLINE_DUMP_OBJECT} = $tag;
                system $^X, (map {"-I$_"} @$libs), $filename;
            } else {
                my @cmd = (
                    $^X, (map {"-I$_"} @$libs),
                    "-MPerinci::CmdLine::Base::Patch::DumpAndExit=-tag,$tag",
                    $filename, "--version",
                );
                system @cmd;
            }
        },
    );

    my $cli;
    if ($stdout =~ /^# BEGIN DUMP $tag\s+(.*)^# END DUMP $tag/ms) {
        $cli = eval $1;
        if ($@) {
            return [500, "Script '$filename' detected as using ".
                        "Perinci::CmdLine, but error in eval-ing captured ".
                            "object: $@, raw captured object: <<<$1>>>"];
        }
        if (!Scalar::Util::blessed($cli)) {
            return [500, "Script '$filename' detected as using ".
                        "Perinci::CmdLine, but didn't get an object?, ".
                            "raw captured output=<<$stdout>>"];
        }
    } else {
        return [500, "Script '$filename' detected as using Perinci::CmdLine, ".
                    "but can't capture object, raw captured output: ".
                        "stdout=<<$stdout>>, stderr=<<$stderr>>"];
    }

    $res->[2] = $cli;

    # XXX handle embedded but not in /main?
    if ($cli->{url} =~ m!^(pl:)?/main/!) {
        # function is embedded in script (/main/FOO), we need to load the
        # metadata in-process
        no warnings;
        local %main::SPEC = (); # empty first to avoid mixing w/ other scripts'
        local @INC = (@$libs, @INC);
        (undef, undef, undef) = Capture::Tiny::capture(
            sub {
                my $meth = $args{method} // 'patch';
                if ($meth eq 'self-dump') {
                    local $ENV{PERINCI_CMDLINE_DUMP} = $tag;
                    do $filename;
                } else {
                    eval q{
package main;
use Perinci::CmdLine::Base::Patch::DumpAndExit -tag=>'$tag',-exit_method=>'die';
do "$filename";
};
                }
            },
        );
        $res->[3]{'func.meta'} = \%main::SPEC;
    }

  RETURN_RES:
    $res;
}

{
    no strict 'refs';
    no warnings 'once';
    # old name, deprecated
    *dump_perinci_cmdline_script = \&dump_pericmd_script;
}

1;
# ABSTRACT:

=for Pod::Coverage ^(dump_perinci_cmdline_script)$
