# The files and the HTML of a service

A service of a workspace does not have to be an API. Sometimes a service
carries the frontend of the workspace — a landing page, an admin panel — and
the frontend calls the other services of the workspace over their contracts.

The runtime serves the files of a directory and answers with HTML. It does not
build the frontend and it does not render the templates: the application
writes the HTML and the frontend is built by the toolchain of the
application. The runtime only does what a runtime does — it reads the files,
it answers with the right content type and it keeps the cache of the browser
in order.

## The files of a directory

`app.staticFiles` mounts a directory under a prefix:

```dart
final app = Laska();

app.staticFiles('/assets', 'web/assets', maxAge: const Duration(hours: 1));
app.staticFiles('/', 'web', fallback: 'index.html');
```

- `/assets/app.js` answers with the file `web/assets/app.js`.
- `/` answers with the file `web/index.html`, and every path that does not
  name a file of the directory answers with it as well — the fallback of a
  single page application.

The method is named `staticFiles`, and not `static`, because `static` is a
keyword of Dart.

| Option | What it does |
|---|---|
| `fallback` | The file served when the requested one is missing. |
| `maxAge` | How long a browser may keep the file, written in `Cache-Control`. |
| `index` | The file served when the request points at a directory. The default is `index.html`. |
| `headers` | Extra headers written to every answer of the files. |

The registration answers `GET` and `HEAD`. A `HEAD` answer holds the length
of the file and no body.

The files are served with the content type of their extension — `text/html`
for a page, `text/css` for a style, `image/png` for a picture — and a file
with an extension the runtime does not know is served as
`application/octet-stream`.

## The HTML of an answer

`ctx.html` builds an answer with the content type of a document of HTML:

```dart
app.get('/', (ctx) => ctx.html(
  '<!doctype html><html><body><h1>Laska</h1></body></html>',
));
```

`Response.html` does the same outside of a handler, and both of them take a
status:

```dart
app.get('/missing', (ctx) => ctx.html('<h1>Not found</h1>', status: 404));
```

## The cache of the browser

Every file is served with the validators of the cache — an `ETag` built of the
size and of the time of the file, and a `Last-Modified`:

```http
HTTP/1.1 200 OK
content-type: text/javascript; charset=utf-8
etag: "f-19d3a1c2b0"
last-modified: Sun, 06 Nov 1994 08:49:37 GMT
x-content-type-options: nosniff
cache-control: public, max-age=3600
```

A browser that holds the file sends the validator back, and the runtime
answers `304` without a body:

```http
HTTP/1.1 304 Not Modified
etag: "f-19d3a1c2b0"
cache-control: public, max-age=3600
```

Both validators are read: `If-None-Match` wins over `If-Modified-Since`,
because the first one is the stronger of the two.

## The path of the file

The path of the request is not decoded by the server, so the runtime decodes
it itself. A path that points outside of the directory is refused with `404`:

- a segment of `..` is refused, encoded (`%2e%2e`) as well;
- a segment that holds a separator is refused;
- the file is compared with the directory after the links of the path are
  resolved, so a link inside of the directory that points outside of it is
  refused as well.

The header `X-Content-Type-Options: nosniff` is written to every answer, so a
browser does not guess the type of a file and does not run a file that was
uploaded as an image.

## The frontend of a workspace

The frontend of a workspace is a service like any other. It is registered in
the manifest of the workspace, it is started by `laska dev` next to the
services it calls, and it holds the client of their contracts:

```yaml
services:
  - name: admin
    entrypoint: apps/admin/bin/main.dart
    port: 8081
    depends_on:
      - users
```

The service itself serves the built frontend and calls the other services
over their generated clients:

```dart
final app = Laska();

app.staticFiles('/', 'web/dist', fallback: 'index.html');

app.get('/api/me', (ctx) async {
  final client = UsersClient(baseUrl: Config.string('USERS_URL')!);
  return ctx.json(await client.getUser(ctx.params['id']!));
});
```

The framework does not build the frontend and does not watch it: the build of
the application belongs to the application, e.g. `npm run build` in the
directory of the frontend, and the result of it is the directory the service
serves.

## What the runtime does not do

- **It does not render the templates.** The HTML of an answer is written by
  the application. A service that needs templates picks a library for them.
- **It does not build the frontend.** The bundler of the application builds
  it, and the runtime serves the result.
- **It does not hold a session of the browser.** The state of the caller lives
  in the services of the workspace, and the frontend holds the token of it.
