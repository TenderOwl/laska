enum NodeType { NORMAL, WILDCARD, PLACEHOLDER }

class Node {
  NodeType type;
  Map<String, dynamic> data;
  String method;
  Function handler;
  Node parent;
  Map<String, Node> children = {};

  // keep track of special child nodes
  String paramName;
  Symbol paramSymbol;
  Node wildcardChildNode;
  Node placeholderChildNode;

  Node({this.type = NodeType.NORMAL, this.handler, this.parent});
}

class Route {
  String method;
  String path;
  Function handler;
  Map<String, dynamic> params;

  Route(this.method, this.path, this.handler, {this.params});
}

class Router {
  final Node rootNode = Node();
  Map<String, Node> staticRoutesMap = {};
  final strictMode;

  Router({List<Route> routes, this.strictMode = true}) {
    if (routes != null) {
      routes.forEach((route) {
        insert(route.method, route.path, route.handler);
      });
    }
  }

  void insert(String method, String path, Function handler) {
    var isStaticRoute = true;

    // Validate and normalize path
    path = validateInput(path);

    final sections = path.split('/');
    var node = rootNode;

    // Iterate over all sections
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      if (section.isEmpty) continue;

      final children = node.children;
      var childNode;

      if (children != null && children.containsKey(section)) {
        node = children[section];
      } else {
        final type = getNodeType(section);

        childNode = Node(type: type, parent: node);

        node.children[section] = childNode;

        final nodeType = getNodeType(section);
        if (nodeType == NodeType.PLACEHOLDER) {
          childNode.paramName = section.substring(1);
          childNode.paramSymbol = Symbol(childNode.paramName);
          node.placeholderChildNode = childNode;
          isStaticRoute = false;
        } else if (nodeType == NodeType.WILDCARD) {
          node.wildcardChildNode = childNode;
          isStaticRoute = false;
        }

        node = childNode;
      }
    }

    // Save route data
    node.method = method;
    node.handler = handler;

    if (isStaticRoute) {
      staticRoutesMap[path] = node;
    }
  }

  Route lookup(String path) {
    path = validateInput(path);
    // optimization, if a route is static and does not have any
    // variable sections, retrieve from a static routes map
    if (staticRoutesMap.containsKey(path)) {
      final staticRoute = staticRoutesMap[path];
      return Route(staticRoute.method, path, staticRoute.handler);
    }

    final nodeMap = findNode(path, rootNode);
    return Route(nodeMap['node']?.method, path, nodeMap['node']?.handler,
        params: nodeMap['params']);
  }

  String validateInput(String path) {
    assert(path != null, '"path" must be provided');

    if (!strictMode && path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  NodeType getNodeType(String path) {
    NodeType type;
    if (path[0] == ':') {
      type = NodeType.PLACEHOLDER;
    } else if (path == '*') {
      type = NodeType.WILDCARD;
    } else {
      type = NodeType.NORMAL;
    }
    return type;
  }

  Map<String, dynamic> findNode(String path, Node rootNode) {
    var sections = path.split('/');

    var params = <String, dynamic>{};
    var paramsFound = false;
    var wildcardNode;
    var node = rootNode;

    for (var i = 0; i < sections.length; i++) {
      var section = sections[i];
      if (section.isEmpty) continue;

      if (node.wildcardChildNode != null) {
        wildcardNode = node.wildcardChildNode;
      }

      final nextNode = node.children[section];
      if (nextNode != null) {
        node = nextNode;
      } else {
        node = node.placeholderChildNode;
        if (node != null) {
          params[node.paramName] = section;
          paramsFound = true;
        } else {
          break;
        }
      }
    }

    if ((node == null || node.data == null) && wildcardNode != null) {
      node = wildcardNode;
    }

    return {'node': node, 'params': paramsFound ? params : null};
  }

  void GET(String path, Function handler) {
    custom('GET', path, handler);
  }

  void POST(String path, Function handler) {
    custom('POST', path, handler);
  }

  void PUT(String path, Function handler) {
    custom('PUT', path, handler);
  }

  void DELETE(String path, Function handler) {
    custom('DELETE', path, handler);
  }

  void custom(String method, String path, Function handler) {
    insert(method, path, handler);
  }
}
