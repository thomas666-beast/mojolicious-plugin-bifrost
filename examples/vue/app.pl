use Mojolicious::Lite -signatures;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Digest::SHA qw(sha256_hex);
use FindBin;

my $secret = $ENV{BIFROST_DEMO_SECRET};
die "Set BIFROST_DEMO_SECRET to at least 32 characters.\n"
  unless defined($secret) && length($secret) >= 32;
app->secrets([$secret]);
app->sessions->cookie_name('bifrost_demo');
app->static->paths->[0] = "$FindBin::Bin/public";

my $manifest_file = path($FindBin::Bin, 'public', 'assets-demo', 'manifest.json');
die "Run npm ci && npm run build in examples/vue first.\n" unless -f $manifest_file;
my $manifest = $manifest_file->slurp;
my $assets = decode_json($manifest)->{'src/main.js'};
my @samples = ('Review the route map', 'Add a test', 'Read the docs', 'Check validation', 'Ship the update');

plugin Bifrost => {
  template => 'shell',
  version => $ENV{BIFROST_DEMO_VERSION} // sha256_hex($manifest),
  shared => {appName => 'Bifrost Task Desk'},
};

get '/' => sub ($c) {
  my $raw = $c->param('page') // '1';
  my $page = $raw =~ /\A[1-9][0-9]{0,2}\z/ ? 0 + $raw : 1;
  return $c->bifrost->render('Tasks', {
    tasks => sub ($c) {
      my @tasks = (@{$c->session('tasks') // []}, @samples);
      my $size = 3;
      my $last = int((@tasks + $size - 1) / $size);
      my $number = $page > $last ? $last : $page;
      my $i = ($number - 1) * $size;
      my $end = $i + $size - 1;
      return {
        rows => [@tasks[$i .. ($end < $#tasks ? $end : $#tasks)]],
        page => $number, pages => $last,
      };
    },
    loadedAt => sub ($c) { scalar gmtime },
  });
};

get '/new' => sub ($c) {
  return $c->bifrost->render('Create', {csrfToken => sub ($c) { $c->csrf_token }});
};

post '/tasks' => sub ($c) {
  return $c->render(status => 403, text => 'Invalid CSRF token')
    if $c->validation->csrf_protect->has_error('csrf_token');
  my $json = $c->req->json;
  my $title = ref($json) eq 'HASH' && defined($json->{title}) && !ref($json->{title}) ? "$json->{title}" : '';
  $title =~ s/\A\s+|\s+\z//g;
  return $c->bifrost->invalid('/new', {title => 'Enter a title of 1 to 40 characters.'})
    unless length($title) && length($title) <= 40 && $title !~ /[[:cntrl:]]/;
  my @tasks = ($title, @{$c->session('tasks') // []});
  splice @tasks, 8 if @tasks > 8;
  $c->session(tasks => \@tasks);
  return $c->bifrost->redirect('/');
};

helper demo_assets => sub ($c) { $assets };
app->start;

__DATA__

@@ shell.html.ep
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Bifrost Task Desk</title>
    % for my $css (@{demo_assets()->{css} // []}) {
      <link rel="stylesheet" href="<%= url_for('/assets-demo/' . $css) %>">
    % }
    <script type="module" src="<%= url_for('/assets-demo/' . demo_assets()->{file}) %>"></script>
  </head>
  <body><%= $c->bifrost->mount %></body>
</html>
