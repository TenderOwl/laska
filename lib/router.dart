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
  String method = 'GET';
  String path;
  Map<String, dynamic> data;
  Function handler;

  Route(this.path, this.data, this.handler);
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

  Map<String, dynamic> lookup(String path) {
    path = validateInput(path);
    // optimization, if a route is static and does not have any
    // variable sections, retrieve from a static routes map
    if (staticRoutesMap.containsKey(path)) {
      return staticRoutesMap[path].data;
    }

    return findNode(path, rootNode);
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

    var params = <Symbol, dynamic>{};
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
          params[node.paramSymbol] = section;
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
}