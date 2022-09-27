import 'dart:io';

import 'package:laska/laska.dart';

// 1. Make a data class
class Todo {
  String text;
  bool done;

  Todo({required this.text, this.done = false});

  Todo.fromJson(Map<String, dynamic> json)
      : text = json['text'],
        done = json['done'];

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'done': done,
    };
  }
}

// 2. Store list of todos in memory.
List<Todo> todos = [
  Todo(text: 'Make something useful'),
  Todo(
    text: 'Make new website',
  ),
];

void main(List<String> args) async {
  // 3. Create a server.
  final laska = Laska(isolateCount: 1);

  // 4. Add routes to get and add a new tasks.
  laska.GET('/tasks', getTasks);
  laska.POST('/tasks', putTask);

  // 9. Run the application
  await run(laska);
}

void getTasks(Context context) async {
  // 5. Return todos list.
  await context.JSON(todos);
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
