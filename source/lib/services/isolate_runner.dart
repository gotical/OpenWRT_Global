import 'dart:isolate';

class IsolateRunner {
  static Future<R> compute<T, R>(Future<R> Function(T) func, T arg) async {
    final receivePort = ReceivePort();
    await Isolate.spawn((SendPort sendPort) async {
      final result = await func(arg);
      sendPort.send(result);
      Isolate.exit(sendPort);
    }, receivePort.sendPort);
    return await receivePort.first as R;
  }
}