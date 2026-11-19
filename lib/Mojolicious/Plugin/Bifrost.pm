package Mojolicious::Plugin::Bifrost;
use Mojo::Base 'Mojolicious::Plugin', -signatures;
use Carp qw(croak);
use Mojo::ByteStream;
use Mojo::JSON qw(to_json);

our $VERSION = '0.001';
my $ERRORS = 'bifrost.validation_errors';

sub register ($self, $app, $conf = {}) {
  my $template = $conf->{template} // 'bifrost';
  my $root = $conf->{root_id} // 'app';
  my $version = $conf->{version} // '';
  my $shared = $conf->{shared} // {};
  croak 'Bifrost: root_id must be a valid mount identifier'
    if ref($root) || $root !~ /\A[A-Za-z][A-Za-z0-9_-]*\z/;
  croak 'Bifrost: shared must be a hash reference' unless ref($shared) eq 'HASH';
  my %shared = %$shared;
  _check_props(\%shared);
  _version($version) unless ref($version) eq 'CODE';

  $app->helper('bifrost.is_visit' => \&_is_visit);
  $app->helper('bifrost.mount' => sub ($c) {
    my $page = $c->stash('bifrost.page') // croak 'Bifrost: mount requires a rendered page';
    my $json = to_json($page);
    # Escape for a script data block, not for an HTML attribute.
    $json =~ s/</\\u003c/g;
    return Mojo::ByteStream->new(qq{<script type="application/json" data-page="$root">$json</script><div id="$root"></div>});
  });
  $app->helper('bifrost.redirect' => \&_redirect);
  $app->helper('bifrost.invalid' => sub ($c, $target, $errors) {
    croak 'Bifrost: invalid() needs a safe local destination' unless _local($target);
    my $bag = $c->req->headers->header('X-Inertia-Error-Bag');
    $bag = undef unless defined($bag) && _key($bag);
    my $clean = _errors($errors);
    $c->flash($ERRORS => defined $bag ? {$bag => $clean} : $clean);
    return _redirect($c, $target);
  });
  $app->helper('bifrost.render' => sub ($c, $component, $props = {}, $status = 200) {
    return _render($c, $template, $version, \%shared, $component, $props, $status);
  });
  return $self;
}

sub _render ($c, $template, $version, $shared, $component, $props, $status) {
  croak 'Bifrost: invalid component name' unless defined($component) && !ref($component)
    && $component =~ m{\A[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\z};
  _check_props($props);
  my $visit = _is_visit($c);
  my $current = _version(ref($version) eq 'CODE' ? $version->($c) : $version);
  my $request = $c->req;
  my $headers = $request->headers;
  my $url = $request->url->to_abs;
  my $path = $url->path->to_abs_string;
  my $query = $url->query->to_string;
  $path .= "?$query" if length $query;
  $path = '/' unless _local($path);
  _headers($c);

  if ($visit && $request->method eq 'GET' && $status == 200
      && ($headers->header('X-Inertia-Version') // '') ne $current) {
    # Only carry Bifrost's own validation flash across this extra visit.
    my $errors = $c->flash($ERRORS);
    $c->flash($ERRORS => $errors) if ref($errors) eq 'HASH';
    my $out = $c->res->headers;
    $out->header('X-Inertia-Location' => $path);
    $out->header('X-Inertia-Version' => $current);
    return $c->render(status => 409, data => '');
  }

  my %page_props = (%$shared, %$props);
  if ($visit && ($headers->header('X-Inertia-Partial-Component') // '') eq $component) {
    my %only = _keys($headers->header('X-Inertia-Partial-Data'));
    my %except = _keys($headers->header('X-Inertia-Partial-Except'));
    delete @page_props{grep { (%only && !$only{$_}) || $except{$_} } keys %page_props};
  }
  for my $name (sort keys %page_props) {
    my $value = $page_props{$name};
    $page_props{$name} = $value->($c) if ref($value) eq 'CODE';
  }
  $page_props{errors} = $c->flash($ERRORS) // {};

  my $page = {component => $component, props => \%page_props, url => $path, version => $current};
  my @shared_keys = sort grep { !exists $props->{$_} && exists $page_props{$_} } keys %$shared;
  $page->{sharedProps} = \@shared_keys if @shared_keys;
  if ($visit) {
    $c->res->headers->header('X-Inertia' => 'true');
    return $c->render(status => $status, json => $page);
  }
  $c->stash('bifrost.page' => $page);
  return $c->render(status => $status, template => $template, format => 'html');
}

sub _redirect ($c, $target) {
  croak 'Bifrost: redirects require a safe local destination' unless _local($target);
  _headers($c);
  my $headers = $c->res->headers;
  if (_is_visit($c) && $target =~ /#/ && ($c->req->headers->header('Purpose') // '') ne 'prefetch') {
    $headers->header('X-Inertia-Redirect' => $target);
    return $c->render(status => 409, data => '');
  }
  $headers->location($target);
  return $c->render(status => $c->req->method =~ /\A(?:GET|HEAD)\z/ ? 302 : 303, data => '');
}

sub _headers ($c) {
  my $headers = $c->res->headers;
  my $vary = $headers->vary // '';
  unless ($vary =~ /(?:\A|,)\s*(?:X-Inertia|\*)\s*(?:,|\z)/i) {
    $headers->vary(length($vary) ? "$vary, X-Inertia" : 'X-Inertia');
  }
  # Pages can contain shared user data, validation errors or CSRF tokens.
  $headers->cache_control('private, no-store');
}

sub _is_visit ($c) { return ($c->req->headers->header('X-Inertia') // '') eq 'true' }

sub _version ($value) {
  croak 'Bifrost: version must be empty or a short ASCII asset identifier'
    if !defined($value) || ref($value) || $value !~ /\A[A-Za-z0-9_.:-]{0,128}\z/;
  return "$value";
}

sub _local ($value) {
  return defined($value) && !ref($value) && length($value) <= 8192
    && $value =~ m{\A/(?!/|%2f|%5c)}i && $value !~ /[\\\x00-\x20\x7f-\xff]/
    && $value !~ /[^\x21-\x7e]/;
}

sub _key ($key) {
  return $key =~ /\A[A-Za-z0-9_-]{1,128}\z/ && $key !~ /\A(?:__proto__|prototype|constructor)\z/;
}

sub _keys ($header) {
  return () unless defined($header) && length($header);
  # Nonempty but unsupported selections must not turn into "include all".
  my %keys = map { ($_ => 1) } grep { _key($_) } split /\s*,\s*/, $header, 129;
  return %keys ? %keys : ('' => 1);
}

sub _check_props ($props) {
  croak 'Bifrost: props must be a hash reference' unless ref($props) eq 'HASH';
  croak 'Bifrost: invalid or reserved top-level prop name'
    if grep { !_key($_) || $_ eq 'errors' } keys %$props;
}

sub _errors ($errors) {
  croak 'Bifrost: errors must be a hash reference' unless ref($errors) eq 'HASH';
  for my $key (keys %$errors) {
    my $value = $errors->{$key};
    croak 'Bifrost: errors must map safe field names to single messages'
      if length($key) > 128 || !length($key) || grep { !_key($_) } split /\./, $key, -1;
    croak 'Bifrost: errors must map safe field names to single messages'
      unless defined($value) && !ref($value);
  }
  croak 'Bifrost: validation messages exceed the session budget'
    if length(Mojo::JSON::encode_json($errors)) > 1200;
  return {%$errors};
}

1;

__END__

=head1 NAME

Mojolicious::Plugin::Bifrost - Server-side Inertia.js v3 adapter for Mojolicious

=head1 SYNOPSIS

  plugin Bifrost => {template => 'shell', version => 'build-1'};
  get '/' => sub ($c) {
    $c->bifrost->render('Home', {message => 'Hello from Mojolicious'});
  };

In the C<shell.html.ep> template, load your frontend and put
C<< %= $c->bifrost->mount >> in the body. See the distribution README for the
supported protocol subset and the runnable Vue example.

=head1 METHODS

=head2 register

Install the C<bifrost> helpers. Options: C<template> (default C<bifrost>),
C<root_id> (default C<app>), C<version> (an asset version string or callback
receiving the controller), and C<shared> (a hashref of shared props).

=head1 HELPERS

=over

=item bifrost.render($component, \%props, $status = 200)

Render an HTML shell or an Inertia JSON page. Page props override shared
props. Top-level code refs receive the controller and run only if selected.

=item bifrost.mount()

Render the escaped v3 page-data script and the root element in an EP template.

=item bifrost.is_visit()

Return true for a request with C<X-Inertia: true>.

=item bifrost.redirect($path)

Navigate to an app-local path after an action.

=item bifrost.invalid($path, \%errors)

Flash field errors and redirect to a local form page. Use short, public
messages, not rejected inputs or secrets.

=back

=cut
