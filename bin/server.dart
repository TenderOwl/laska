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
  final app = Laska()..get('/', (context) => context.Text('Hello, world.'));

  await run(app);
}
