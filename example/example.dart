import 'dart:io';

import 'package:laska/laska.dart';

// 1. Define a data class
class Todo {
  int id;
  String text;
  bool done;

  Todo({required this.id, required this.text, this.done = false});

  Todo.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        text = json['text'],
        done = json['done'];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'done': done,
    };
  }
}

// 2. Store list of todos in memory.
List<Todo> todos = [
  Todo(id: 1, text: 'Make something useful'),
  Todo(id: 2, text: 'Make new website'),
];

void main(List<String> args) async {
  // 3. Create a server.
  final laska = Laska();

  // 4. Add routes to get and add a new tasks.
  laska.GET('/tasks', getTasks);
  laska.GET('/tasks/:id', getTask);
  laska.POST('/tasks', putTask);

  // 9. Run the application
  await run(laska);
}

void getTasks(Context context) async {
  // 5. Return todos list.
  await context.JSON(todos);
}

void getTask(Context context) async {
  await context.JSON(todos.firstWhere(
      (t) => t.id == int.parse(context.param('id')!),
      orElse: null));
}

void putTask(Context context) async {
  // 6. Parse request body.
  final httpBody = await context.body;

  // 7. Simple check for a content type
  if (httpBody.type != 'json') {
    return await context.Text('Unsupported Media Type',
        statusCode: HttpStatus.unsupportedMediaType);
  }

  // 8. Create a new task
  todos.add(Todo.fromJson(httpBody.body));
  await context.JSON({'status': 'created'}, statusCode: HttpStatus.created);
}
