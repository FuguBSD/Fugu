# Install Fugu

Fugu runs on core Perl v5.36 or later. There are two install flows: from a
checkout with make, and from a release tarball with cpanm.

## From a checkout

```sh
git clone https://github.com/FuguBSD/Fugu.git
cd Fugu
make deps
doas make install
```

`make install` copies `lib/Fugu/` and `lib/Protocol/` with their `.pod` sidecars
into the site_perl tree. `make uninstall` removes them.

The runtime tier of `deps/` is empty: Fugu itself needs core Perl only. Install
the optional features you use:

- `Net::SSH2` for `Fugu::SSH`
- `Net::MQTT::Simple` for `Fugu::MQTT`
- `HTTP::Daemon`, `HTTP::Message`, `LWP::UserAgent`, and `URI` for `Fugu::Proxy`

`make deps-test` installs the test dependencies; `make deps-develop` installs
everything.

## From a release tarball

Every release carries a standard Perl distribution tarball. The stable URL
always serves the latest release:

```sh
cpanm --notest https://github.com/FuguBSD/Fugu/releases/latest/download/Fugu.tar.gz
```

Both flows install the modules with their `.pod` sidecars, so `perldoc` serves
the documentation either way.

## Verify

```sh
perl -MFugu::Daemon -e 'print "ok\n"'
perldoc Fugu::Daemon
```
