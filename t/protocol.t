use Mojo::Base -strict, -signatures;
use Mojolicious::Lite -signatures;
use Mojo::JSON qw(from_json);
use Test::More;
use Test::Mojo;

app->secrets(['test-only-bifrost-session-secret-do-not-deploy']);
my $version = 'build-1';
my $calls = 0;
my $markup = "A </script> example & a snowman \x{2603}";
plugin Bifrost => {
  template => 'shell', root_id => 'example', version => sub ($c) { $version },
  shared => {site => 'Bifrost', label => 'shared'},
};

get '/tasks' => sub ($c) {
  $c->res->headers->vary('Origin');
  return $c->bifrost->render('Tasks/Index', {
    label => 'page', rows => [{title => $markup}], count => sub ($c) { ++$calls; 7 },
  });
};
get '/login' => sub ($c) { $c->bifrost->render('Login', {caption => 'Sign in'}) };
get '/status' => sub ($c) { $c->render(json => {ok => 1}) };
get '/encoded/:name' => sub ($c) { $c->bifrost->render('Encoded') };
get '/jump' => sub ($c) { $c->bifrost->redirect('/tasks#form') };
put '/tasks' => sub ($c) { $c->bifrost->redirect('/tasks') };
post '/tasks' => sub ($c) { $c->bifrost->invalid('/tasks', {title => 'Enter a title.'}) };
get '/not-found' => sub ($c) { $c->bifrost->render('Error', {message => 'Not found'}, 404) };

my $t = Test::Mojo->new(app);
my $visit = {'X-Inertia' => 'true', 'X-Inertia-Version' => 'build-1'};
my $partial = {%$visit, 'X-Inertia-Partial-Component' => 'Tasks/Index'};

$t->get_ok('/tasks?page=2')->status_is(200)->header_like(Vary => qr/\bOrigin, X-Inertia\b/)
  ->header_is('Cache-Control' => 'private, no-store')->header_isnt('X-Inertia' => 'true')
  ->element_exists('div#example')->element_exists('script[type="application/json"][data-page="example"]');
my $script = $t->tx->res->dom->at('script[data-page="example"]')->content;
unlike($script, qr{</script}i, 'embedded JSON cannot close the script block');
my $initial = from_json($script);
is($initial->{props}{rows}[0]{title}, $markup, 'embedded data round-trips without HTML entities');
is($initial->{url}, '/tasks?page=2', 'direct page keeps local path and query');
is($initial->{version}, 'build-1');
is_deeply($initial->{props}{errors}, {}, 'empty errors are encoded as an object');

$t->get_ok('/tasks?page=2' => $visit)->status_is(200)->header_is('X-Inertia' => 'true')
  ->header_like('Content-Type' => qr{application/json});
is_deeply($t->tx->res->json, $initial, 'HTML and JSON share the same page object');
is_deeply($initial->{sharedProps}, ['site'], 'lists shared props except page overrides');
is($calls, 2, 'normal visits evaluate the closure once each');

$t->get_ok('/tasks' => {%$partial, 'X-Inertia-Partial-Data' => 'rows,label', 'X-Inertia-Partial-Except' => 'label'})
  ->status_is(200)->json_has('/props/rows')->json_hasnt('/props/count')->json_hasnt('/props/site')
  ->json_hasnt('/props/label')->json_is('/props/errors' => {});
is($calls, 2, 'excluded props never execute');
$t->get_ok('/tasks' => {%$partial, 'X-Inertia-Partial-Except' => 'rows, count'})
  ->status_is(200)->json_hasnt('/props/rows')->json_hasnt('/props/count')->json_is('/props/site' => 'Bifrost');
$t->get_ok('/tasks' => {%$partial, 'X-Inertia-Partial-Data' => 'count'})
  ->status_is(200)->json_is('/props/count' => 7)->json_hasnt('/props/rows');
is($calls, 3, 'selected prop evaluates once');
$t->get_ok('/login' => {%$partial, 'X-Inertia-Partial-Data' => 'rows'})
  ->status_is(200)->json_is('/component' => 'Login')->json_is('/props/caption' => 'Sign in');
$t->get_ok('/tasks' => {'X-Inertia-Partial-Component' => 'Tasks/Index', 'X-Inertia-Partial-Data' => 'label'})
  ->status_is(200)->content_like(qr/"count":7/, 'non-Inertia visits ignore partial headers');

$t->get_ok('/tasks?page=3' => {%$visit, 'X-Inertia-Version' => 'old'})
  ->status_is(409)->header_is('X-Inertia-Location' => '/tasks?page=3')->header_is('X-Inertia-Version' => 'build-1')
  ->header_isnt('X-Inertia' => 'true');
is($calls, 4, 'version conflict does not run prop callbacks');
$t->get_ok('/tasks' => {'X-Inertia' => 'true'})->status_is(409);
$t->put_ok('/tasks' => {%$visit, 'X-Inertia-Version' => 'old'})->status_is(303)->header_is(Location => '/tasks');
$t->get_ok('/jump' => $visit)->status_is(409)->header_is('X-Inertia-Redirect' => '/tasks#form');
$t->get_ok('/jump' => {%$visit, Purpose => 'prefetch'})->status_is(302)->header_is(Location => '/tasks#form');
$t->get_ok('/jump')->status_is(302)->header_is(Location => '/tasks#form');

$t->post_ok('/tasks' => $visit)->status_is(303)->header_is(Location => '/tasks');
$t->get_ok('/tasks' => {%$partial, 'X-Inertia-Partial-Data' => 'rows', 'X-Inertia-Partial-Except' => 'errors'})
  ->status_is(200)->json_is('/props/errors/title' => 'Enter a title.');
$t->get_ok('/tasks' => $visit)->status_is(200)->json_is('/props/errors' => {});
$t->post_ok('/tasks' => {%$visit, 'X-Inertia-Error-Bag' => 'task'})->status_is(303);
$version = 'build-2';
$t->get_ok('/tasks' => $visit)->status_is(409)->header_is('X-Inertia-Version' => 'build-2');
$t->get_ok('/tasks')->status_is(200)->content_like(qr/Enter a title/, 'version reload preserves validation errors');
$t->get_ok('/tasks' => {%$visit, 'X-Inertia-Version' => 'build-2'})
  ->status_is(200)->json_is('/props/errors' => {});

$t->get_ok('/not-found' => $visit)->status_is(404)->json_is('/component' => 'Error');
$t->get_ok('/status' => $visit)->status_is(200)->json_is('/ok' => 1)->header_isnt('X-Inertia' => 'true');
$t->get_ok('/encoded/caf%C3%A9?q=a%2Bb' => {%$visit, 'X-Inertia-Version' => 'build-2'})
  ->status_is(200)->json_is('/url' => '/encoded/caf%C3%A9?q=a%2Bb');
$t->get_ok('/encoded/caf%C3%A9?q=a%2Bb' => {%$visit, Host => 'bifrost.example'})
  ->status_is(409)->header_is('X-Inertia-Location' => '/encoded/caf%C3%A9?q=a%2Bb');

my $parent = Mojolicious->new;
$parent->routes->any('/desk')->partial(1)->to(app => app);
my $mounted = Test::Mojo->new($parent);
$mounted->get_ok('/desk/tasks?page=3' => {%$visit, 'X-Inertia-Version' => 'build-2'})
  ->status_is(200)->json_is('/url' => '/desk/tasks?page=3');
$mounted->get_ok('/desk/tasks?page=3' => $visit)
  ->status_is(409)->header_is('X-Inertia-Location' => '/desk/tasks?page=3');

my $c = app->build_controller;
for my $destination ('https://example.com/tasks', '//example.com/tasks', 'tasks') {
  eval { $c->bifrost->redirect($destination) };
  like($@, qr/safe local destination/, "rejects unsupported redirect destination: $destination");
}

$t->post_ok('/tasks' => {%$visit, 'X-Inertia-Error-Bag' => 'task'})->status_is(303);
$t->get_ok('/tasks' => {%$visit, 'X-Inertia-Version' => 'build-2'})
  ->status_is(200)->json_is('/props/errors/task/title' => 'Enter a title.');
done_testing;

__DATA__

@@ shell.html.ep
<!doctype html><html lang="en"><title>Bifrost test</title><body><%= $c->bifrost->mount %></body></html>
