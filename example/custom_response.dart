import 'dart:io';

import 'package:laska/laska.dart';

// 1. Make a data class
class Todo {
  String id;
  String text;

  Todo({this.id, this.text});

  Todo.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        text = json['text'];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
    };
  }
}

// Custom response class.
// It is a simple class with `toJson()` method
// which returns required JSON structure.
class APIResponse {
  dynamic data;
  dynamic status;

  APIResponse({this.data, this.status});

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'status': status,
    };
  }
}

// 2. Store list of todos in memory.
List<Todo> todos = [
  Todo(id: '1', text: 'Make something useful'),
  Todo(id: '2', text: 'Make new website'),
];

void main(List<String> args) async {
  // 3. Create a server.
  final laska = Laska(isolateCount: 1);

  // 4. Add routes to get and add a new tasks.
  laska.GET('/tasks', getTasks);
  laska.POST('/tasks', putTask);

  // 7. Run the application
  await run(laska);
}

void getTasks(Context context) async {
  // 5. Return todos list.
  await context.JSON(APIResponse(data: todos));
}

void putTask(Context context) async {
  // 6. Read text and id from JSON body and put into todos list.
  todos.add(Todo(id: '3', text: 'New todo'));
  await context.JSON(APIResponse(status: {'status': 'created'}),
      statusCode: HttpStatus.created);
}
