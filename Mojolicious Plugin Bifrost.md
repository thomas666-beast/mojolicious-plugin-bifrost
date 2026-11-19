# Mojolicious::Plugin::Bifrost

Bifrost is a server-side Perl adapter for the core [Inertia.js v3 protocol](https://inertiajs.com/docs/v3/core-concepts/the-protocol.md). Mojolicious keeps control of routes, sessions, validation, and authorization; page components run in the browser using an [official v3 frontend adapter](https://inertiajs.com/docs/v3/installation/client-side-setup). Bifrost itself does not install Node, bundle JavaScript, or require a Bifrost npm package. [`Example with mojolicious`](https://github.com/thomas666-beast/bifrost-task-desk)

## Install

Requires Perl 5.26 or later and Mojolicious 9.48 or later. With [`cpanm`](https://metacpan.org/pod/App::cpanminus), install the provided archive:

```sh
cpanm ./Mojolicious-Plugin-Bifrost-0.001.tar.gz
```

Or unpack the archive, install Mojolicious through your normal Perl toolchain, and run:

```sh
perl Makefile.PL
make
make test
make install
```

## Connect your first page

In a Mojolicious::Lite app:

```perl
use Mojolicious::Lite -signatures;

plugin Bifrost => {
  template => 'shell',
  version => 'build-1', # In production, use an identifier derived from the asset build.
  shared => {appName => 'My app'},
};

get '/' => sub ($c) {
  $c->bifrost->render('Home', {message => 'Hello from Mojolicious'});
};

app->start;
```

In `templates/shell.html.ep`, load the built JavaScript entry for your project and output the mount markup. The frontend entry should initialize an official v3 adapter, resolve the `Home` page component, and mount into `app`.

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script type="module" src="/assets/app.js"></script>
  </head>
  <body>
    <%= $c->bifrost->mount %>
  </body>
</html>
```

### Helpers and settings

| API | Behavior |
| --- | --- |
| `$c->bifrost->render('Tasks/Index', \%props, $status)` | Renders the shell or the Inertia JSON page. The optional status defaults to `200`; use the redirect helper for navigation after an action. |
| `$c->bifrost->mount` | Outputs the v3 JSON script and mount element inside the shell. Set `root_id` if your frontend uses something other than `app`. |
| `$c->bifrost->is_visit` | Detects `X-Inertia: true`. This is not an authorization check. |
| `$c->bifrost->redirect('/tasks')` | Redirects to a same-origin path, using `303` after POST, PUT, PATCH, or DELETE. Use a leading slash and include the application's mount prefix if needed. |
| `$c->bifrost->invalid('/tasks/new', {title => 'Enter a title.'})` | Flashes short field errors, then redirects. The next rendered page includes an `errors` object; named error bags are supported. |

The `shared` option accepts a hash reference. Page props win on duplicate names, and values supplied as top-level code references receive the current controller. Put expensive work inside a code reference so Bifrost can skip it on partial reloads or asset-version conflicts:

```perl
$c->bifrost->render('Tasks/Index', {
  tasks => sub ($c) { $c->task_repository->page_for($c->current_user, $page, 25) },
  summary => sub ($c) { $c->task_repository->summary_for($c->current_user) },
});
```

This snippet assumes application-provided `task_repository` and `current_user` helpers and an already validated `$page`. A client visit with `only: ['tasks']` skips the summary callback on the same component. The repository should apply its own authorization, limits, and stable ordering; Bifrost does not paginate data on its own.

Set `version` to a short ASCII release ID, asset hash, or a callback that returns one. On a successful page GET with a stale version, Bifrost asks the browser to reload at the same local path and query. Leave it empty if the application does not use asset versioning.

## Try the Vue example

This optional example uses Vue and `@inertiajs/vue3` directly. It needs Node.js 20.19+ on the 20.x line or Node.js 22.12+ and npm, in addition to the Perl dependencies. Run these commands from the extracted distribution:

```sh
cd examples/vue
npm ci
npm run build
export BIFROST_DEMO_SECRET="$(openssl rand -hex 32)"
perl -I../../lib app.pl daemon -l http://127.0.0.1:3000
```

Open [the local Task Desk](http://127.0.0.1:3000/). Click **Next** to fetch only the next page of tasks and keep the displayed full-page load time unchanged. Open **New task**, submit a blank title to see a server-side field error, then submit a valid title to see it added to the task list. To see version recovery, keep the browser tab open, stop the server, restart it with `BIFROST_DEMO_VERSION=demo-2` on the same port, then click a navigation link.

The demo uses a signed session cookie for a small number of sample entries and uses Mojolicious's CSRF validation for POSTs. It is a local example, not a persistence layer or a production deployment template.

## Scope of version 0.001

- **Implemented:** First-visit HTML, Inertia JSON visits, shared and lazy props, top-level `only`/`except` partial reloads, local and fragment redirects, asset version checks, and form errors.
- **Not implemented:** Inertia v2 bootstrap, SSR, nested partial selection, optional/deferred/once/merged/live props, protocol-level flash payloads, infinite-scroll metadata, history encryption, Precognition, or external redirects.
- **Application responsibilities:** Authorization, CSRF protection, session secrets, production cookie settings, and error-page routing stay in the host app. Only pass public-to-the-current-user values as props: page data is readable by the browser and may be retained in its history. Validation flash is for short messages, not input values, secrets, or personal records.

## License

Distributed under the Artistic License 2.0. See `LICENSE` in the archive or the [Artistic License 2.0 text](https://raw.githubusercontent.com/spdx/license-list-data/main/text/Artistic-2.0.txt).
