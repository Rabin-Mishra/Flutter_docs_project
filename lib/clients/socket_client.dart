import 'package:docs_clone_flutter/constants.dart';
import 'package:docs_clone_flutter/repository/socket_repository.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketClient {
  io.Socket? socket;
  static SocketClient? _instance;

  SocketClient._internal();

  static SocketClient get instance {
    _instance ??= SocketClient._internal();
    return _instance!;
  }

  void updateSocket(String token) {
    // Clean up previous socket if it exists
    socket?.disconnect();
    socket?.destroy();

    // Create a fresh socket with the correct Bearer token in OptionBuilder
    socket = io.io(
      host,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setAuth({'token': 'Bearer $token'})
          .build(),
    );

    // Register connect listener immediately to auto-join active rooms on connection/reconnection
    socket!.on('connect', (_) {
      if (SocketRepository.activeDocumentId != null) {
        socket!.emit('join-document', {'documentId': SocketRepository.activeDocumentId});
      }
    });

    socket!.connect();
  }
}
