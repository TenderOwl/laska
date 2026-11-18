/// The deployment artefacts of a workspace.
///
/// The Dockerfile and the Kubernetes manifests are written from the manifest
/// of the workspace, so the image of a service always matches the port and the
/// name the service was given.
library;

import 'dart:io';

import 'workspace.dart';

/// The Dockerfile of a service.
///
/// The image is built in two steps: the Dart SDK compiles the service, and the
/// runtime image holds the binary and nothing else. The build context is the
/// directory of the service.
String renderDockerfile(
  WorkspaceService service, {
  String image = 'laska',
}) =>
    '''# The image of the ${service.name} service.
#
# The image is built from the directory of the service:
#   docker build -f deploy/${service.name}/Dockerfile -t $image/${service.name}:latest .
FROM dart:3.14 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/server.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server

EXPOSE ${service.port}
ENTRYPOINT ["/app/server"]
''';

/// The files a Docker build does not need.
String renderDockerignore() => '''.dart_tool
.git
build
deploy
''';

/// The Kubernetes manifests of a service.
///
/// The file holds a deployment and the service that points at it, so the
/// service is reachable under the name of the service inside the cluster.
String renderKubernetes(
  WorkspaceService service, {
  String image = 'laska',
  String namespace = 'default',
}) =>
    '''# The manifests of the ${service.name} service.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${service.name}
  namespace: $namespace
  labels:
    app: ${service.name}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${service.name}
  template:
    metadata:
      labels:
        app: ${service.name}
    spec:
      containers:
        - name: ${service.name}
          image: $image/${service.name}:latest
          ports:
            - containerPort: ${service.port}
---
apiVersion: v1
kind: Service
metadata:
  name: ${service.name}
  namespace: $namespace
spec:
  selector:
    app: ${service.name}
  ports:
    - port: ${service.port}
      targetPort: ${service.port}
''';

/// Writes the Dockerfile of every service of the [workspace].
///
/// The files are written in `<output>/<name>/Dockerfile`, one directory per
/// service. Returns the paths of the written files.
Future<List<String>> writeDockerfiles(
  Workspace workspace, {
  required String output,
  String image = 'laska',
}) async {
  final written = <String>[];

  for (final service in workspace.services) {
    final directory = Directory('$output/${service.name}');
    await directory.create(recursive: true);

    final dockerfile = File('${directory.path}/Dockerfile');
    await dockerfile.writeAsString(renderDockerfile(service, image: image));
    written.add(dockerfile.path);

    final ignore = File('${directory.path}/.dockerignore');
    await ignore.writeAsString(renderDockerignore());
    written.add(ignore.path);
  }

  return written;
}

/// Writes the Kubernetes manifests of every service of the [workspace].
///
/// The file of a service is `<output>/<name>.yaml`. Returns the paths of the
/// written files.
Future<List<String>> writeKubernetesManifests(
  Workspace workspace, {
  required String output,
  String image = 'laska',
  String namespace = 'default',
}) async {
  final written = <String>[];
  final directory = Directory(output);
  await directory.create(recursive: true);

  for (final service in workspace.services) {
    final file = File('${directory.path}/${service.name}.yaml');
    await file.writeAsString(
      renderKubernetes(service, image: image, namespace: namespace),
    );
    written.add(file.path);
  }

  return written;
}
