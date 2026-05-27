import 'package:docs_clone_flutter/clients/socket_client.dart';
import 'package:socket_io_client/socket_io_client.dart';

class SocketRepository {
  static String? activeDocumentId;

  Socket get socketClient => SocketClient.instance.socket!;

  void connect(String token) {
    SocketClient.instance.updateSocket(token);
  }

  void joinRoom(String documentId) {
    activeDocumentId = documentId;
    if (socketClient.connected) {
      socketClient.emit('join-document', {'documentId': documentId});
    } else {
      // Socket not connected yet — queue the join for when it connects
      socketClient.once('connect', (_) {
        socketClient.emit('join-document', {'documentId': documentId});
      });
    }
  }

  void submitOp(String documentId, dynamic delta, List<dynamic> content) {
    socketClient.emit('submit-op', {
      'documentId': documentId,
      'delta': delta,
    });
  }

  void onReceiveOp(Function(Map<String, dynamic>) callback) {
    socketClient.on('receive-op', (data) {
      if (data != null) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void onDocumentLoaded(Function(Map<String, dynamic>) callback) {
    socketClient.on('load-document', (data) {
      if (data != null) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void onPresenceUpdate(Function(Map<String, dynamic>) callback) {
    socketClient.on('presence-update', (data) {
      if (data != null) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void emitCursorMove(String documentId, int index, int length) {
    socketClient.emit('cursor-move', {
      'documentId': documentId,
      'index': index,
      'length': length,
    });
  }

  void onCursorUpdate(Function(Map<String, dynamic>) callback) {
    socketClient.on('cursor-update', (data) {
      if (data != null) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void disconnect() {
    activeDocumentId = null;
    socketClient.disconnect();
  }
}
