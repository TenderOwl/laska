import 'package:laska_core/laska_core.dart';

import '../generated/users.pb.dart';

/// An in-memory implementation of the users service.
class UsersServiceImpl implements UsersService {
  final Map<String, User> _users = <String, User>{
    'u_1': User(
      id: 'u_1',
      email: 'ada@example.com',
      displayName: 'Ada Lovelace',
      role: UserRole.userRoleAdmin,
      tags: <String>['founder', 'mathematician'],
      createdAt: ProtoTimestamp.fromDateTime(DateTime.utc(2026, 1, 1)),
    ),
  };

  @override
  Future<User> getUser(GetUserRequest request) async {
    final user = _users[request.id];
    if (user == null) {
      throw HttpException(
        404,
        'User "${request.id}" was not found',
        code: 'user_not_found',
      );
    }
    return user;
  }

  @override
  Future<ListUsersResponse> listUsers(ListUsersRequest request) async {
    final limit = request.limit == 0 ? _users.length : request.limit;
    final users = _users.values.take(limit).toList();
    return ListUsersResponse(users: users, nextCursor: '');
  }

  @override
  Future<User> createUser(CreateUserRequest request) async {
    final id = 'u_${_users.length + 1}';
    final user = User(
      id: id,
      email: request.email,
      displayName: request.displayName,
      role: request.role,
      createdAt: ProtoTimestamp.fromDateTime(DateTime.now().toUtc()),
    );
    _users[id] = user;
    return user;
  }
}
