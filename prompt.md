# SyncWrite — Engineering Transformation Specification
### Agentic Implementation Blueprint for Antigravity IDE

---

> **AGENT INSTRUCTION — READ THIS FIRST, EVERY TIME:**
> This file is your single source of truth. You operate in two phases.
> **Phase 1** is analysis and planning only — no code changes to the project.
> **Phase 2** begins only when the user explicitly says `"proceed with Stage N"`.
> The project is already open in the IDE at the current working directory.
> Do not assume anything about file contents — read every file before touching it.

---

## SECTION 0 — PROJECT SNAPSHOT

| Field | Value |
|---|---|
| Project Name | SyncWrite — Collaborative Document Platform |
| Working Directory | `~/Downloads/Flutter_docs_project-main` |
| GitHub | https://github.com/Rabin-Mishra/Flutter_docs_project.git |
| Reference Tutorial | https://youtu.be/W6vAQdzLcu4 |
| Frontend | Flutter / Dart / Riverpod / RouteMaster / Flutter Quill |
| Backend | Node.js 18 / Express.js / Socket.IO |
| Database | MongoDB / Mongoose |
| Auth | Google OAuth 2.0 + custom JWT (no Firebase) |
| Target Scale | **10–20 simultaneous users per document** |
| Deployment Target | Single VPS or local network — no paid cloud services |
| OS | Ubuntu Linux |

**Reference documents already in the project folder:**
- `FinalDefenseFinalYearProj.pdf` — full architecture, schema, sprint history
- `FinalDefenseSlide FYP.pdf` — defense slides with system diagrams

---

## SECTION 1 — CURRENT SYSTEM AUDIT (Phase 1 Task)

### 1.1 What You Must Read Before Writing Anything

In Phase 1, open and read every file in the project. Pay specific attention to:

```
~/Downloads/Flutter_docs_project-main/
├── server/
│   ├── index.js               ← Socket.IO server, all event handlers live here
│   ├── models/                ← Mongoose schemas (User, Document)
│   ├── routes/                ← Express REST API routes
│   ├── middleware/            ← JWT verification middleware
│   └── package.json           ← Backend dependencies
├── lib/
│   ├── main.dart              ← App entry point, RouteMaster setup
│   ├── screens/               ← Flutter UI screens
│   ├── repository/            ← API calls and Socket.IO client logic
│   └── providers/             ← Riverpod state providers
└── pubspec.yaml               ← Flutter dependencies
```

Read both PDF files in the project root. They contain the official architecture diagrams, data models, sprint history, and the team's own list of known limitations. Cross-reference everything against the actual code.

### 1.2 Architecture to Understand (Current State)

The current system works like this:

```
═══════════════════════════════════════════════════════════════════
CURRENT DATA FLOW — AS BUILT
═══════════════════════════════════════════════════════════════════

[Flutter Client A]                    [Flutter Client B]
      │                                      │
      │  User types                          │  User types
      ▼                                      ▼
[Quill Editor]                        [Quill Editor]
      │                                      │
      │  Emit: 'typing' (raw delta)          │  Emit: 'typing' (raw delta)
      ▼                                      ▼
      └──────────────► [Node.js / Socket.IO Server] ◄──────────────┘
                              │
                              │  socket.broadcast.to(room)
                              │  Emit: 'changes' to all OTHER clients
                              │
                              │  [NO CONFLICT RESOLUTION HERE]
                              │  [RACE CONDITION EXISTS HERE]
                              ▼
                        ╔══════════╗
                        ║ MongoDB  ║ ◄── Client Timer fires every 2s
                        ║          ║     Sends FULL document delta
                        ╚══════════╝     findByIdAndUpdate (OVERWRITE)

═══════════════════════════════════════════════════════════════════
AUTH FLOW — AS BUILT
═══════════════════════════════════════════════════════════════════

[Flutter]  →  Google Sign-In  →  ID Token
    │
    ▼
POST /api/signup  →  Node.js verifies ID token with Google Cloud Identity
    │
    ▼
Node.js creates/finds User in MongoDB  →  Signs custom JWT
    │
    ▼
Returns JWT  →  Flutter stores in SharedPreferences
    │
    ▼
All subsequent REST calls send JWT in Authorization header
    │
    ▼
auth middleware verifies JWT  →  Attaches user to req.user

═══════════════════════════════════════════════════════════════════
DOCUMENT LIFECYCLE — AS BUILT
═══════════════════════════════════════════════════════════════════

Open document  →  RouteMaster pushes /document/:id
    │
    ▼
Client emits 'join' (room: documentId)  →  Server: socket.join(documentId)
    │
    ▼
Server sends current document content back to joining client
    │
    ▼
User types  →  Quill onChange fires  →  Client emits 'typing' (delta)
    │
    ▼
Server broadcasts delta to room (excluding sender)
    │
    ▼ [PARALLEL — every 2 seconds regardless]
Client Timer  →  document.toDelta() full snapshot  →  Emit 'save'
    │
    ▼
Server: Document.findByIdAndUpdate({ content: fullDelta })
```

### 1.3 Known Bugs — Exact Location Mapping

For each bug below, find the exact file and line number in the codebase and record it in your audit report.

| # | Bug | Where to Look | Severity |
|---|---|---|---|
| 1 | **Concurrent edit corruption** — Two users typing simultaneously produces garbled text because raw deltas are broadcast with no transformation. The last write wins. | `server/index.js` — the `typing` event handler | CRITICAL |
| 2 | **Full-document overwrite on save** — Every 2 seconds the entire document is overwritten in MongoDB. If User A saves at t=0ms and User B saves at t=50ms, A's changes are gone. | `server/index.js` — the `save` event handler. Flutter: find `Timer.periodic` in the document screen | CRITICAL |
| 3 | **No WebSocket authentication** — The Socket.IO server accepts connections from any client. A user who is not logged in can join any document room by guessing its ID. | `server/index.js` — the `connection` handler. Look for JWT verification on socket handshake. It will be absent. | HIGH |
| 4 | **Link-only access control** — Anyone with the document URL has full edit access. There is no viewer/editor permission distinction. | `server/models/Document.js` — the `sharedWith` array is commented out or empty. REST routes have no permission check. | HIGH |
| 5 | **In-memory socket state** — All Socket.IO room memberships live in Node.js process memory. A server restart or crash silently drops all active sessions with no reconnection logic on the client. | `server/index.js` — no Redis adapter, no reconnection handler | MEDIUM |

### 1.4 What to Keep vs. What to Replace

After reading the code, populate this table in your audit report with KEEP / REFACTOR / REPLACE and one sentence of reasoning per row:

| Module | Verdict | Reasoning |
|---|---|---|
| Flutter UI screens and widgets | ? | |
| Riverpod state providers | ? | |
| RouteMaster navigation + route guards | ? | |
| Flutter Quill editor integration | ? | |
| Google OAuth + JWT auth flow | ? | |
| Express REST API routes (CRUD) | ? | |
| Mongoose User model | ? | |
| Mongoose Document model | ? | |
| Socket.IO room joining logic | ? | |
| Socket.IO `typing` event handler | ? | |
| Client-side 2-second auto-save timer | ? | |
| Server-side `save` event handler | ? | |

### 1.5 Synchronization Engine Decision

After reviewing the codebase, recommend ONE of the three options below and justify your choice in one paragraph. The recommendation must account for the 10–20 user target and the goal of finishing the project, not architecting it forever.

**Option A — Server-Side Delta Composition (Recommended for simplicity)**
Keep Socket.IO. Add the `quill-delta` npm package on the server. The server maintains an authoritative in-memory copy of each open document as a `Delta` object. When a client submits a change, the server applies it to the authoritative copy using `compose()`, then broadcasts the verified operation to the room. The 2-second timer is replaced by a server-side debounced write queue that flushes to MongoDB every 3–5 seconds.

```
Client emits op  →  Server composes op onto authoritative Delta
                 →  Broadcasts composed op to room
                 →  Stages doc ID in write queue
                 →  Queue flushes to MongoDB every 5s
```

- Pros: No new major libraries. Stays on the current stack. Correct for 10–20 users. Implementable in a weekend.
- Cons: Authoritative state lives in server memory (solved partially by Redis). Not true CRDT.

**Option B — ShareDB (Operational Transform)**
Replace the Socket.IO event handlers with ShareDB's built-in OT protocol. ShareDB handles all transformation logic. Requires both Flutter client and Node server to speak the ShareDB wire protocol.
- Pros: Battle-tested OT. Used in production systems.
- Cons: Significant refactor. Flutter client needs a custom ShareDB adapter.

**Option C — Yjs CRDT**
Introduce Yjs on the server with `y-socket.io`. Flutter client uses a JS interop bridge or WebView.
- Pros: Gold standard for CRDTs. Works offline.
- Cons: Flutter CRDT integration is non-trivial. Heaviest refactor of the three.

---

## SECTION 2 — PHASE 1 DELIVERABLE

Before any code changes, produce a file named `IMPLEMENTATION_PLAN.md` in the project root. It must contain:

1. **Architecture Audit** — filled-in verdict table from Section 1.4
2. **Bug Location Report** — file name and line number for each of the 5 bugs in Section 1.3
3. **Additional Bugs Found** — anything you discovered beyond the 5 listed
4. **Sync Engine Recommendation** — your justified choice from Section 1.5
5. **Staged Implementation Plan** — the full plan from Section 3 with any adjustments based on what you found in the code

Present this file to the user. Do not proceed to Phase 2 until the user reviews it and says `"proceed with Stage N"`.

---

## SECTION 3 — STAGED IMPLEMENTATION PLAN

These stages are ordered by impact-to-effort ratio. Each stage is independent and deployable. Do not start a stage until the previous one passes its acceptance test.

---

### STAGE 1 — WebSocket Authentication & Environment Hardening

**Goal:** Lock down the Socket.IO server so only authenticated users can join document rooms. Clean up environment variable handling.

**Why first:** This is a security fix that requires zero architecture change and takes less than two hours. Every other stage builds on a secure foundation.

**Files to modify:**
- `server/index.js` — add JWT verification on socket handshake
- `server/.env` — add all required variables
- `server/.env.example` — create this file (commit it, never commit `.env`)

**Files to create:**
- `server/middleware/socketAuth.js`

**New packages needed:** None (jsonwebtoken is already installed for REST middleware)

**Implementation:**

```javascript
// server/middleware/socketAuth.js
const jwt = require('jsonwebtoken');

function socketAuthMiddleware(socket, next) {
  // Client must send JWT in the auth handshake object:
  // socket = io('http://...', { auth: { token: 'Bearer <jwt>' } })
  const authHeader = socket.handshake.auth?.token;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(new Error('AUTHENTICATION_REQUIRED: No token provided on socket handshake.'));
  }

  const token = authHeader.split(' ')[1];

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET_KEY);
    socket.user = decoded; // Attach user data to socket for use in handlers
    next();
  } catch (err) {
    next(new Error('AUTHENTICATION_FAILED: Token is invalid or expired.'));
  }
}

module.exports = socketAuthMiddleware;
```

```javascript
// server/index.js — add this BEFORE the io.on('connection') block
const socketAuthMiddleware = require('./middleware/socketAuth');
io.use(socketAuthMiddleware);

// Inside io.on('connection', (socket) => { ... })
// You now have access to socket.user (the authenticated user's JWT payload)
// Log it to verify:
io.on('connection', (socket) => {
  console.log(`Authenticated socket connection: user=${socket.user.id}, socketId=${socket.id}`);
  // ... rest of handlers
});
```

```dart
// lib/repository/socket_repository.dart — update the connection init
// The Flutter client must pass the JWT in the auth object

IO.Socket initSocket(String jwtToken) {
  return IO.io(
    AppConfig.serverUrl,
    IO.OptionBuilder()
      .setTransports(['websocket'])
      .enableForceNew()
      .setAuth({'token': 'Bearer $jwtToken'}) // Add this line
      .build(),
  );
}
```

```env
# server/.env
PORT=3001
MONGO_URI=mongodb://localhost:27017/syncwrite
JWT_SECRET_KEY=replace_with_a_long_random_string_minimum_32_chars
GOOGLE_CLIENT_ID=your_google_oauth_client_id.apps.googleusercontent.com
NODE_ENV=development
```

```env
# server/.env.example  (safe to commit)
PORT=3001
MONGO_URI=mongodb://localhost:27017/syncwrite
JWT_SECRET_KEY=REPLACE_WITH_SECRET
GOOGLE_CLIENT_ID=REPLACE_WITH_GOOGLE_CLIENT_ID
NODE_ENV=development
```

**Acceptance Test:**
1. Start the server
2. Open two browser tabs — log in with Google in Tab 1, do NOT log in in Tab 2
3. Tab 1 should connect to a document socket room successfully
4. Tab 2 should receive a connection error in the browser console: `AUTHENTICATION_REQUIRED`
5. Check server console — only Tab 1's connection should be logged

---

### STAGE 2 — Server-Side Debounced Persistence (Kill the 2-Second Timer)

**Goal:** Remove the client-side `Timer.periodic` auto-save. Replace it with a server-side write queue that batches MongoDB writes every 5 seconds. This eliminates the full-document overwrite race condition.

**Why second:** Until the save mechanism is fixed, any test of real-time sync will produce unreliable results. This stage also makes the app feel faster because the client is no longer doing background work every 2 seconds.

**Files to modify:**
- `server/index.js` — remove the `save-document` handler, call the queue instead
- Flutter `lib/screens/document_screen.dart` (or wherever `Timer.periodic` lives) — remove the timer entirely

**Files to create:**
- `server/workers/persistenceQueue.js`

**New packages needed:** None

**Implementation:**

```javascript
// server/workers/persistenceQueue.js
// A singleton write queue. Stages document content in memory.
// Flushes all staged documents to MongoDB every FLUSH_INTERVAL ms.
// This means at most one DB write per document every 5 seconds,
// regardless of how many users are editing it.

const Document = require('../models/Document');

const FLUSH_INTERVAL_MS = 5000;

class PersistenceQueue {
  constructor() {
    this.pendingWrites = new Map(); // Map<documentId: string, content: object>
    this.timer = null;
  }

  stage(documentId, content) {
    this.pendingWrites.set(documentId, content);

    // Start the flush timer if it is not already running
    if (!this.timer) {
      this.timer = setInterval(() => this._flush(), FLUSH_INTERVAL_MS);
    }
  }

  async _flush() {
    if (this.pendingWrites.size === 0) {
      clearInterval(this.timer);
      this.timer = null;
      return;
    }

    // Snapshot and clear the pending map before awaiting
    // so new writes during this flush are not lost
    const snapshot = new Map(this.pendingWrites);
    this.pendingWrites.clear();

    const writeOps = [];
    for (const [docId, content] of snapshot.entries()) {
      writeOps.push(
        Document.findByIdAndUpdate(
          docId,
          { $set: { content }, $inc: { version: 1 }, updatedAt: new Date() },
          { new: false }
        ).catch(err => {
          console.error(`[PersistenceQueue] Failed to write document ${docId}:`, err.message);
          // Re-stage the failed write so it retries on the next flush
          this.stage(docId, content);
        })
      );
    }

    await Promise.all(writeOps);
    console.log(`[PersistenceQueue] Flushed ${snapshot.size} document(s) to MongoDB.`);
  }

  // Call this on server shutdown for a clean final write
  async forceFlush() {
    clearInterval(this.timer);
    this.timer = null;
    await this._flush();
  }
}

module.exports = new PersistenceQueue();
```

```javascript
// server/index.js — update the socket handlers

const persistenceQueue = require('./workers/persistenceQueue');

// REMOVE the old 'save-document' handler entirely
// REPLACE with a call to the queue inside the existing 'submit-op' or 'typing' handler:

socket.on('submit-op', ({ documentId, delta, content }) => {
  // Broadcast the delta to other clients in the room immediately
  socket.to(documentId).emit('receive-op', { delta });

  // Stage the latest full content snapshot for debounced DB write
  // 'content' here is the full document state AFTER the client applied the delta locally
  persistenceQueue.stage(documentId, content);
});
```

```dart
// lib/screens/document_screen.dart (find and remove this block)
// DELETE the following pattern entirely:
//
// _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
//   final content = _controller.document.toDelta().toJson();
//   socketRepository.saveDocument(documentId, content);
// });
//
// Also cancel and null the timer in dispose() if it still exists during transition
```

**Mongoose Document model update** — add the `version` field if it does not exist:

```javascript
// server/models/Document.js — add version field
const DocumentSchema = new mongoose.Schema({
  title:      { type: String, required: true, trim: true },
  content:    { type: Object, default: { ops: [] } },
  uid:        { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  version:    { type: Number, default: 0 },  // ADD THIS
}, { timestamps: true });

DocumentSchema.index({ uid: 1 });
DocumentSchema.index({ updatedAt: -1 });
```

**Clean server shutdown** — add to `server/index.js`:

```javascript
// Ensure final flush on graceful shutdown
process.on('SIGTERM', async () => {
  console.log('[Server] SIGTERM received. Flushing persistence queue...');
  await persistenceQueue.forceFlush();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('[Server] SIGINT received. Flushing persistence queue...');
  await persistenceQueue.forceFlush();
  process.exit(0);
});
```

**Acceptance Test:**
1. Open a document in two browsers
2. Both users type rapidly for 30 seconds
3. Open MongoDB Compass or run `mongosh syncwrite --eval "db.documents.findOne()"` 
4. Verify the document version field is incrementing
5. Verify writes are happening approximately every 5 seconds (not every 2)
6. Close both browsers, wait 10 seconds, reopen the document
7. All content from both users must be present and uncorrupted

---

### STAGE 3 — Real-Time Conflict-Free Synchronization

**Goal:** Replace raw delta broadcasting with server-side delta composition using the `quill-delta` library. The server becomes the authoritative source of truth for each open document. No two users' operations can corrupt each other.

**Why third:** Stages 1 and 2 must be solid before this. Auth ensures only valid users send ops. The persistence queue provides safe storage. Now we fix the core sync problem.

**Files to modify:**
- `server/index.js` — full rewrite of the real-time event handlers
- `server/workers/persistenceQueue.js` — minor update to accept Delta objects

**Files to create:**
- `server/services/documentRoomManager.js`

**New packages needed:**
```bash
cd server && npm install quill-delta
```

**Architecture after this stage:**

```
═══════════════════════════════════════════════════════════════════
TARGET DATA FLOW — AFTER STAGE 3
═══════════════════════════════════════════════════════════════════

[Client A types]  →  emit 'submit-op' { documentId, delta }
                                │
                                ▼
                    [documentRoomManager]
                    Holds authoritative Delta per document
                                │
                                ▼
                    authoritative.compose(incomingDelta)
                    → produces new authoritative state
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
          broadcast 'receive-op'    stage in persistenceQueue
          { delta } to ALL clients  (flushes to MongoDB every 5s)
          INCLUDING sender
          (sender uses this to confirm)
═══════════════════════════════════════════════════════════════════
```

**Implementation:**

```javascript
// server/services/documentRoomManager.js
// Manages the authoritative in-memory document state for every open document room.

const Delta = require('quill-delta');
const Document = require('../models/Document');

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

      this.rooms.set(documentId, {
        delta: new Delta(doc.content?.ops || []),
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

    const incoming = new Delta(incomingDelta.ops || incomingDelta);
    room.delta = room.delta.compose(incoming);

    return room.delta;
  }

  getCurrentDelta(documentId) {
    return this.rooms.get(documentId)?.delta || null;
  }
}

module.exports = new DocumentRoomManager();
```

```javascript
// server/index.js — replace ALL real-time socket handlers with this

const roomManager = require('./services/documentRoomManager');
const persistenceQueue = require('./workers/persistenceQueue');

io.on('connection', (socket) => {
  console.log(`[Socket] Connected: user=${socket.user.id} socket=${socket.id}`);

  // ─── JOIN DOCUMENT ROOM ───────────────────────────────────────────────────
  socket.on('join-document', async ({ documentId }) => {
    try {
      const currentDelta = await roomManager.joinRoom(documentId, socket.id);
      socket.join(documentId);
      socket.currentDocumentId = documentId; // Track for disconnect cleanup

      // Send the current authoritative document state to the joining client
      socket.emit('load-document', { content: currentDelta });

      console.log(`[Socket] User ${socket.user.id} joined document ${documentId}`);
    } catch (err) {
      socket.emit('error', { message: err.message });
      console.error(`[Socket] join-document error:`, err.message);
    }
  });

  // ─── SUBMIT AN OPERATION ─────────────────────────────────────────────────
  // Client emits this whenever the user makes an edit.
  // Payload: { documentId: string, delta: { ops: [...] } }
  socket.on('submit-op', ({ documentId, delta }) => {
    try {
      const newAuthoritative = roomManager.applyOp(documentId, delta);

      // Broadcast the incoming delta to ALL OTHER clients in the room
      // They apply it to their local document with quill.updateContents(delta)
      socket.to(documentId).emit('receive-op', { delta });

      // Stage the new authoritative snapshot for database persistence
      persistenceQueue.stage(documentId, newAuthoritative);
    } catch (err) {
      socket.emit('error', { message: err.message });
      console.error(`[Socket] submit-op error:`, err.message);
    }
  });

  // ─── DISCONNECT ──────────────────────────────────────────────────────────
  socket.on('disconnect', () => {
    if (socket.currentDocumentId) {
      roomManager.leaveRoom(socket.currentDocumentId, socket.id);
    }
    console.log(`[Socket] Disconnected: socket=${socket.id}`);
  });
});
```

**Flutter client update** — update the socket repository event names to match:

```dart
// lib/repository/socket_repository.dart

// JOIN a document — call this when the document screen opens
void joinDocument(String documentId) {
  _socket.emit('join-document', {'documentId': documentId});
}

// LISTEN for the initial document load (replaces REST call for content)
void onDocumentLoaded(Function(Map<String, dynamic>) callback) {
  _socket.on('load-document', (data) => callback(data));
}

// SUBMIT an operation — call this inside the Quill onChanged handler
// delta: the QuillController change delta, serialized to JSON
void submitOp(String documentId, Map<String, dynamic> delta) {
  _socket.emit('submit-op', {'documentId': documentId, 'delta': delta});
}

// RECEIVE an operation from another user — apply to local Quill editor
void onReceiveOp(Function(Map<String, dynamic>) callback) {
  _socket.on('receive-op', (data) => callback(data['delta']));
}
```

**Acceptance Test:**
1. Open the same document in two separate browser windows (both logged in as different users)
2. User A types a sentence from the left side
3. User B types a sentence from the right side — at the same moment
4. Both users must see both sentences in their editors within 200ms
5. Close both browsers, reopen the document
6. Both sentences must be present and correctly ordered
7. Repeat 5 times with increasingly rapid typing — no corruption should occur

---

### STAGE 4 — Document Permissions & Secure Sharing

**Goal:** Give the document owner control over who can edit and who can only view. Replace anonymous link sharing with role-aware access.

**Files to modify:**
- `server/models/Document.js` — activate the `sharedWith` array
- `server/routes/document.js` — add permission-check middleware
- `server/index.js` — verify permission before allowing `submit-op`

**Files to create:**
- `server/middleware/documentPermission.js`

**New packages needed:** None

**Schema update:**

```javascript
// server/models/Document.js — activate the sharedWith field
const DocumentSchema = new mongoose.Schema({
  title:    { type: String, required: true, trim: true },
  content:  { type: Object, default: { ops: [] } },
  uid:      { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  version:  { type: Number, default: 0 },
  sharedWith: [{
    userId:     { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    permission: { type: String, enum: ['viewer', 'editor'], default: 'viewer' },
  }],
}, { timestamps: true });
```

**Permission middleware:**

```javascript
// server/middleware/documentPermission.js
const Document = require('../models/Document');

// Usage: router.get('/:id', authMiddleware, requirePermission('viewer'), handler)
function requirePermission(minimumRole) {
  const roleHierarchy = { viewer: 0, editor: 1, owner: 2 };

  return async (req, res, next) => {
    try {
      const doc = await Document.findById(req.params.id);
      if (!doc) return res.status(404).json({ error: 'Document not found.' });

      const userId = req.user.id;
      const isOwner = doc.uid.toString() === userId;
      if (isOwner) return next(); // Owners have all permissions

      const share = doc.sharedWith.find(s => s.userId.toString() === userId);
      if (!share) return res.status(403).json({ error: 'Access denied.' });

      const userLevel = roleHierarchy[share.permission] ?? -1;
      const requiredLevel = roleHierarchy[minimumRole] ?? 99;

      if (userLevel < requiredLevel) {
        return res.status(403).json({ error: `Requires '${minimumRole}' permission or higher.` });
      }

      req.docPermission = share.permission;
      req.doc = doc;
      next();
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  };
}

module.exports = requirePermission;
```

```javascript
// server/index.js — add inside 'submit-op' handler before applyOp()
// Prevent viewer-only users from submitting edits

socket.on('submit-op', async ({ documentId, delta }) => {
  try {
    const doc = await Document.findById(documentId).select('uid sharedWith');
    const userId = socket.user.id;
    const isOwner = doc.uid.toString() === userId;
    const share = doc.sharedWith.find(s => s.userId.toString() === userId);
    const canEdit = isOwner || share?.permission === 'editor';

    if (!canEdit) {
      socket.emit('error', { message: 'You have view-only access to this document.' });
      return;
    }

    // ... rest of the existing submit-op logic
  } catch (err) {
    socket.emit('error', { message: err.message });
  }
});
```

**Acceptance Test:**
1. User A (owner) opens a document, generates a share link with viewer permission
2. User B opens the link — should see the document content but Quill editor should be read-only
3. Owner upgrades User B to editor via API call (`PATCH /api/documents/:id/share`)
4. User B refreshes — should now be able to type and have changes sync to User A
5. Owner revokes User B's access — User B's next `submit-op` should receive a 403

---

### STAGE 5 — User Presence Indicators (Who Is In This Document)

**Goal:** Show a colored avatar and cursor label for every user currently editing the same document. This is the feature that makes a collaborative editor *feel* alive.

**Files to modify:**
- `server/index.js` — add presence tracking events
- Flutter: document screen and Quill editor wrapper

**Files to create:**
- `server/services/presenceManager.js`

**New packages needed:** None (server-side). Flutter: none new.

**Implementation:**

```javascript
// server/services/presenceManager.js
// Tracks which users are actively in each document room

class PresenceManager {
  constructor() {
    // Map<documentId, Map<socketId, { userId, name, avatarUrl, color, cursor }>>
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
```

```javascript
// server/index.js — add presence events alongside existing handlers

const presenceManager = require('./services/presenceManager');

// Inside 'join-document' handler — add after socket.join(documentId):
const userInfo = {
  userId: socket.user.id,
  name: socket.user.name || 'Anonymous',
  avatarUrl: socket.user.profilePic || null,
};
presenceManager.join(documentId, socket.id, userInfo);

// Broadcast updated presence list to everyone in the room
io.to(documentId).emit('presence-update', {
  users: presenceManager.getPresenceList(documentId)
});

// Cursor position updates (lightweight — no DB involved)
socket.on('cursor-move', ({ documentId, index, length }) => {
  presenceManager.updateCursor(documentId, socket.id, { index, length });
  socket.to(documentId).emit('cursor-update', {
    userId: socket.user.id,
    color: presenceManager.getPresenceList(documentId)
              .find(u => u.userId === socket.user.id)?.color,
    cursor: { index, length },
  });
});

// Inside 'disconnect' handler — add after roomManager.leaveRoom():
if (socket.currentDocumentId) {
  presenceManager.leave(socket.currentDocumentId, socket.id);
  io.to(socket.currentDocumentId).emit('presence-update', {
    users: presenceManager.getPresenceList(socket.currentDocumentId)
  });
}
```

**Acceptance Test:**
1. User A opens a document — should see their own avatar in a presence bar
2. User B opens the same document — User A's presence bar updates to show two avatars
3. User B types — User A sees a colored cursor label near User B's text position
4. User B closes the tab — User A's presence bar updates to show only themselves within 3 seconds

---

### STAGE 6 — Version History (Last 10 Snapshots)

**Goal:** Every time the persistence queue flushes, save a snapshot. Allow users to browse and restore any of the last 10 versions.

**Files to modify:**
- `server/workers/persistenceQueue.js` — save a snapshot alongside the main document
- `server/routes/document.js` — add `/history` and `/restore/:version` endpoints

**Files to create:**
- `server/models/DocumentHistory.js`

**New packages needed:** None

**Schema:**

```javascript
// server/models/DocumentHistory.js
const mongoose = require('mongoose');

const DocumentHistorySchema = new mongoose.Schema({
  documentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Document', required: true, index: true },
  version:    { type: Number, required: true },
  content:    { type: Object, required: true },
  savedAt:    { type: Date, default: Date.now },
});

// Keep only the latest 10 snapshots per document — enforced at the app level
DocumentHistorySchema.index({ documentId: 1, version: -1 });

module.exports = mongoose.model('DocumentHistory', DocumentHistorySchema);
```

```javascript
// server/workers/persistenceQueue.js — update _flush() to save history
const DocumentHistory = require('../models/DocumentHistory');

// Inside _flush(), after the successful Document.findByIdAndUpdate:
const doc = await Document.findById(docId).select('version');
await DocumentHistory.create({
  documentId: docId,
  version: doc.version,
  content,
});

// Prune to keep only the 10 most recent snapshots for this document
const snapshots = await DocumentHistory.find({ documentId: docId })
  .sort({ version: -1 })
  .skip(10)
  .select('_id');

if (snapshots.length > 0) {
  await DocumentHistory.deleteMany({ _id: { $in: snapshots.map(s => s._id) } });
}
```

**Acceptance Test:**
1. Make 15 separate edits to a document (wait 5s between edits to trigger flushes)
2. `GET /api/documents/:id/history` — should return exactly 10 snapshot records
3. Pick version 5 and call `POST /api/documents/:id/restore/5`
4. Reload the document — content should match the version-5 snapshot

---

### STAGE 7 — Docker Compose Full Stack

**Goal:** One command starts the entire system. Consistent across all developer machines.

**Files to create:**
- `docker-compose.yml` (project root)
- `server/Dockerfile`

**New packages needed:** None

```yaml
# docker-compose.yml (project root)
version: '3.8'

services:
  mongodb:
    image: mongo:6.0
    container_name: syncwrite-mongodb
    restart: unless-stopped
    ports:
      - "27017:27017"
    volumes:
      - mongo-data:/data/db
    networks:
      - syncwrite-network

  redis:
    image: redis:7.2-alpine
    container_name: syncwrite-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    networks:
      - syncwrite-network

  backend:
    build:
      context: ./server
      dockerfile: Dockerfile
    container_name: syncwrite-backend
    restart: unless-stopped
    ports:
      - "3001:3001"
    environment:
      - PORT=3001
      - MONGO_URI=mongodb://mongodb:27017/syncwrite
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
      - NODE_ENV=production
    depends_on:
      - mongodb
      - redis
    networks:
      - syncwrite-network

volumes:
  mongo-data:

networks:
  syncwrite-network:
    driver: bridge
```

```dockerfile
# server/Dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

EXPOSE 3001

CMD ["node", "index.js"]
```

**Acceptance Test:**
1. From project root, run: `docker-compose up --build`
2. All three containers start (mongodb, redis, backend) with no errors
3. Open the Flutter web app pointing at `localhost:3001` — full auth and real-time sync works
4. Run `docker-compose down` — all containers stop cleanly
5. Run `docker-compose up` again (no `--build`) — system restores with all previously saved documents intact (data persisted in `mongo-data` volume)

---

### STAGE 8 — Export & Download Options (PDF, DOCX, TXT)


**Goal:** Export and download the document content in multiple standard formats.

**Files to modify/create:**
- `lib/screens/document_screen.dart` (Add File -> Download menu)
- `lib/services/export_service.dart` (NEW: Native client-side PDF and plain text builders)
- `server/routes/document.js` (Add `/doc/:id/export/docx` REST endpoint)

**New packages needed:**
- `pdf: ^3.10.0` (Flutter client: high-performance PDF layout and document generation)
- `html-to-docx: ^1.8.0` (Node.js server: converts compiled HTML string from Quill Delta to standard Microsoft Word .docx format)

**Acceptance Test:**
1. Open a document and write structured text with bold, italic, and bullet list formats.
2. Click **File -> Download -> Plain Text (.txt)** — Downloads a plain text file containing your exact content.
3. Click **File -> Download -> PDF Document (.pdf)** — Client compiles Delta into standard PDF layout elements and downloads a print-ready PDF file.
4. Click **File -> Download -> Word Document (.docx)** — Server converts the composed document to a clean DOCX file and downloads it instantly.

---

### STAGE 9 — Rich Content Insertion (Tables, Links, Images, Charts)

**Goal:** Insert and render rich, interactive elements within the collaborative document.

**Files to modify:**
- `lib/screens/document_screen.dart` (Add "Insert" menu in toolbar)
- `server/services/documentRoomManager.js` (Support custom rich-media embed deltas)

**Acceptance Test:**
1. Click **Insert -> Link** — Type text and URL. The link is correctly underlined, styled, and clickable.
2. Click **Insert -> Image** — Paste a public image URL or upload a local image. The image is rendered inside the editor in real-time and synchronized immediately to other co-editors.
3. Click **Insert -> Table** — Insert a 3x3 table. The table rows and cells are editable collaboratively.
4. Click **Insert -> Chart** — Select from Bar, Pie, or Line charts, input simple key-value data, and verify the chart widget displays interactively inside the document card.

---

### STAGE 10 — Document Tooling (Word Count & Dictionary)

**Goal:** Add productivity tools to improve editing capabilities.

**Files to modify/create:**
- `lib/screens/document_screen.dart` (Add "Tools" menu, Word Count dialog, and Dictionary Sidebar)
- `lib/services/dictionary_service.dart` (NEW: Fetches definitions and synonyms from open API)

**Acceptance Test:**
1. Click **Tools -> Word Count** — Displays a premium modal dialog showing the exact count of words, characters, and paragraphs inside the editor.
2. Double-click any word in the document, or click **Tools -> Dictionary** — Opens a sleek collapsible sidebar panel on the right.
3. The sidebar queries DictionaryAPI.dev and displays definitions, parts of speech, pronunciations, and synonyms in real-time.

---


## SECTION 4 — CODE QUALITY RULES FOR PHASE 2

These rules apply to every file you touch in every stage. No exceptions.

1. **Read before writing.** Never modify a file without first showing its current content and explaining exactly what will change.
2. **One stage at a time.** Do not start Stage N+1 work inside a Stage N commit. If you discover something that requires a future stage, note it in `IMPLEMENTATION_PLAN.md` and continue.
3. **No silent dependency additions.** Every new `npm install` or `flutter pub add` must be preceded by an explanation of what the package does and why it is the right choice.
4. **Environment variables.** Every new env variable must be added to both `.env` (with a real value for local dev) and `.env.example` (with a placeholder and a comment explaining what it is).
5. **New Socket.IO events.** Every new event name (both emitted and listened for) must be documented in a comment block at the top of `server/index.js` in a section called `// EVENT REGISTRY`.
6. **No paid services.** Do not introduce Firebase, AWS, GCP, Stripe, or any service requiring a credit card. Everything must run locally or on a simple VPS.
7. **Preserve existing data.** Never drop a MongoDB collection or delete documents in a migration. Use additive schema changes only.
8. **Verify before claiming done.** Run the acceptance test for each stage yourself and report the result before telling the user the stage is complete.

---

## SECTION 5 — SUCCESS DEFINITION

The project is done when every item below is checked:

- [ ] Two users can type in the same document simultaneously — no text is lost or corrupted
- [ ] Closing and reopening a document always loads exactly the last saved content
- [ ] An unauthenticated client cannot connect to any Socket.IO room
- [ ] A viewer-permission user cannot submit edits (the Quill editor is read-only for them)
- [ ] The presence bar shows an avatar for each user currently in the document
- [ ] A colored cursor label appears near where each other user is typing
- [ ] At least 10 historical snapshots are accessible and restorable per document
- [ ] The entire stack starts with `docker-compose up` from the project root
- [ ] `flutter doctor` reports no issues in the project environment
- [ ] The server logs show clean startup with MongoDB and (optionally) Redis connections confirmed

---

## SECTION 6 — QUICK REFERENCE: LOCAL STARTUP COMMANDS

```bash
# ── Infrastructure (run once per session) ──────────────────────────────────
docker-compose up -d

# ── Backend ────────────────────────────────────────────────────────────────
cd ~/Downloads/Flutter_docs_project-main/server
npm install
npm run dev
# Expected: "Server listening on port 3001" + "MongoDB connected"

# ── Frontend (Flutter Web) ─────────────────────────────────────────────────
cd ~/Downloads/Flutter_docs_project-main
flutter pub get
flutter run -d chrome --web-port=5000

# ── Diagnostics ────────────────────────────────────────────────────────────
# Inspect all live documents in MongoDB:
docker exec -it syncwrite-mongodb mongosh syncwrite --eval "db.documents.find().pretty()"

# Watch real-time Redis activity:
docker exec -it syncwrite-redis redis-cli MONITOR

# Check socket connections:
# Add this to server/index.js temporarily:
# setInterval(() => console.log('[Rooms]', io.sockets.adapter.rooms), 5000);

# Flutter dependency issues:
flutter pub get && flutter clean && flutter pub get

# Environment verification:
node -v && npm -v && flutter --version && docker --version
```

---

*Phase 1: Analyze the codebase, read the PDFs, produce `IMPLEMENTATION_PLAN.md`. Present it to the user.*
*Phase 2: Wait for `"proceed with Stage N"`. Implement one stage. Run its acceptance test. Report results. Wait.*