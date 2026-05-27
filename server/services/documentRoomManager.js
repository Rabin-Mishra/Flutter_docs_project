const Delta = require('quill-delta');
const Document = require('../models/document');

class DocumentRoomManager {
  constructor() {
    // Map<documentId: string, { delta: Delta, clients: Set<socketId> }>
    this.rooms = new Map();
  }

  // Called when a client joins a document room
  // Returns the current authoritative document content
  async joinRoom(documentId, socketId) {
    if (!this.rooms.has(documentId)) {
      // Load the document from MongoDB to initialize the room
      const doc = await Document.findById(documentId);
      if (!doc) throw new Error(`Document ${documentId} not found.`);

      // Ensure content has ops array structure and ends with standard newline to prevent Quill client assertion crashes
      const ops = doc.content && Array.isArray(doc.content) && doc.content.length > 0 
        ? doc.content 
        : [{ insert: "\n" }];
      this.rooms.set(documentId, {
        delta: new Delta(ops),
        clients: new Set(),
      });
    }

    const room = this.rooms.get(documentId);
    room.clients.add(socketId);

    return room.delta;
  }

  // Called when a client disconnects or leaves
  leaveRoom(documentId, socketId) {
    const room = this.rooms.get(documentId);
    if (!room) return;

    room.clients.delete(socketId);

    // If the room is now empty, remove it from memory
    // The persistence queue will have already staged the last save
    if (room.clients.size === 0) {
      this.rooms.delete(documentId);
      console.log(`[RoomManager] Room ${documentId} is empty and has been evicted from memory.`);
    }
  }

  // Called when a client submits an operation
  // Applies the operation to the authoritative state and returns the new state
  applyOp(documentId, incomingDelta) {
    const room = this.rooms.get(documentId);
    if (!room) throw new Error(`Room ${documentId} does not exist. Client must join first.`);

    // Handle incoming delta representation (either direct array or wrapper object)
    const incomingOps = Array.isArray(incomingDelta) ? incomingDelta : (incomingDelta.ops || []);
    const incoming = new Delta(incomingOps);
    
    // Authoritative state composition
    room.delta = room.delta.compose(incoming);

    return room.delta;
  }

  getCurrentDelta(documentId) {
    return this.rooms.get(documentId)?.delta || null;
  }
}

module.exports = new DocumentRoomManager();
