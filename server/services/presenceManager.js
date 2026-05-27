class PresenceManager {
  constructor() {
    // Map<documentId, Map<socketId, { userId, name, email, avatarUrl, color, cursor }>>
    this.rooms = new Map();
    
    // Pre-defined palette — assign a color per user deterministically
    this.colorPalette = [
      '#E53935', '#8E24AA', '#1E88E5', '#00ACC1',
      '#43A047', '#FB8C00', '#6D4C41', '#546E7A',
    ];
  }

  _getColorForUser(userId) {
    // Simple deterministic color from user ID hash
    let hash = 0;
    for (let i = 0; i < userId.length; i++) {
      hash = userId.charCodeAt(i) + ((hash << 5) - hash);
    }
    return this.colorPalette[Math.abs(hash) % this.colorPalette.length];
  }

  join(documentId, socketId, userInfo) {
    if (!this.rooms.has(documentId)) {
      this.rooms.set(documentId, new Map());
    }
    this.rooms.get(documentId).set(socketId, {
      ...userInfo,
      color: this._getColorForUser(userInfo.userId),
      cursor: null,
    });
  }

  leave(documentId, socketId) {
    this.rooms.get(documentId)?.delete(socketId);
    if (this.rooms.get(documentId)?.size === 0) {
      this.rooms.delete(documentId);
    }
  }

  updateCursor(documentId, socketId, cursorPosition) {
    const user = this.rooms.get(documentId)?.get(socketId);
    if (user) user.cursor = cursorPosition;
  }

  getPresenceList(documentId) {
    const room = this.rooms.get(documentId);
    if (!room) return [];
    return Array.from(room.values());
  }
}

module.exports = new PresenceManager();
