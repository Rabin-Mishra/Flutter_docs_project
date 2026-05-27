# SyncWrite — Implementation Plan & Architecture Audit

## 1. Architecture Audit
The following table outlines our assessment of each core module, determining whether it should be kept, refactored, or replaced, along with the engineering justification.

| Module | Verdict | Reasoning |
|---|---|---|
| **Flutter UI screens and widgets** | **REFACTOR** | Keep the layout but update them to integrate with user presence indicators, custom selection cursors, and read-only styling for view-only permissions. |
| **Riverpod state providers** | **KEEP** | Clean and modular state management for users and authentication; no structural changes needed. |
| **RouteMaster navigation + route guards** | **KEEP** | Properly manages declarative routing and separates public/private views based on Riverpod user state. |
| **Flutter Quill editor integration** | **REFACTOR** | Update the controller logic to support remote compositions cleanly and toggle `readOnly` dynamically based on document permissions. |
| **Google OAuth + JWT auth flow** | **KEEP** | Simple and secure OAuth verification that generates custom JWTs. Safe to keep, but secret keys must be externalized. |
| **Express REST API routes (CRUD)** | **REFACTOR** | Keep the route structures but integrate permission checks (e.g., owner vs shared list) and history snapshot retrieval endpoints. |
| **Mongoose User model** | **KEEP** | Simple schema storing standard name, email, and avatar properties. |
| **Mongoose Document model** | **REFACTOR** | Add a `version` field for optimistic synchronization and active `sharedWith` array to support granular permissions. |
| **Socket.IO room joining logic** | **REPLACE** | Replace the unauthenticated `join` handler with a secure `join-document` socket handler that validates the JWT handshake and returns the authoritative state. |
| **Socket.IO `typing` event handler** | **REPLACE** | Replace the raw delta broadcast handler with a formal `submit-op` handler that validates rights, composes on the server, and broadcasts verified operations. |
| **Client-side 2-second auto-save timer** | **DELETE** | Remove the periodic client-side timer entirely to eliminate race conditions and DB overwrites. |
| **Server-side `save` event handler** | **DELETE** | Remove direct full-delta save. Replace with a debounced server-side persistence queue writing to MongoDB every 5 seconds. |

---

## 2. Bug Location Report
We audited the codebase and identified the exact file names and line numbers for the five known bugs from the spec:

1. **Concurrent edit corruption**:
   - **Location**: [server/index.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/index.js#L37-L39)
   - **Snippet**:
     ```javascript
     socket.on("typing", (data) => {
       socket.broadcast.to(data.room).emit("changes", data);
     });
     ```
   - **Explanation**: Raw deltas are broadcast directly to other clients with no conflict resolution or synchronization engine. The last write wins, producing corrupted document states when two users type simultaneously.

2. **Full-document overwrite on save**:
   - **Location**: [server/index.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/index.js#L41-L43) & [server/index.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/index.js#L46-L50) (Server), and [lib/screens/document_screen.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/screens/document_screen.dart#L47-L53) (Flutter client).
   - **Snippet (Server)**:
     ```javascript
     socket.on("save", (data) => {
       saveData(data);
     });
     const saveData = async (data) => {
       let document = await Document.findById(data.room);
       document.content = data.delta;
       document = await document.save();
     };
     ```
   - **Explanation**: The client emits `save` with the full document snapshot every 2 seconds. The server performs a full document save (`document.content = data.delta`), overwriting whatever changes have been saved by other users in the meantime.

3. **No WebSocket authentication**:
   - **Location**: [server/index.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/index.js#L32-L44)
   - **Explanation**: The Socket.IO server processes connection handshakes and joins rooms without validating user identity or verifying a JWT. Any client can connect and intercept data inside a document room by guessing its ID.

4. **Link-only access control**:
   - **Location**: [server/models/document.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/models/document.js#L3-L21) & [server/routes/document.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/routes/document.js#L42-L49)
   - **Explanation**: The Mongoose `DocumentSchema` lacks any `sharedWith` array to store access control lists. The REST routes perform simple document fetches based on the ID without asserting if the requesting user owns or has explicit access to the document.

5. **In-memory socket state**:
   - **Location**: [server/index.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/index.js)
   - **Explanation**: Socket connections, rooms, and states exist strictly within the Node.js memory. There is no Redis adapter or backup storage mapping socket states, meaning restarts drop active sessions silently without client-side auto-reconnect.

---

## 3. Additional Bugs Found
During our thorough audit, we discovered several additional critical security, architecture, and stability bugs:

1. **Null-Pointer Crash in Client Auto-Save Timer**:
   - **Location**: [lib/screens/document_screen.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/screens/document_screen.dart#L47-L53)
   - **Explanation**: `Timer.periodic` is instantiated inside `initState()`, immediately scheduling checks. However, the `_controller` is initialized asynchronously inside `fetchDocumentData()` after the API network request resolves. If the request takes longer than 2 seconds, the timer fires, attempts to read `_controller!.document`, and crashes the app with a null pointer exception.
   
2. **Hardcoded MongoDB Connection string**:
   - **Location**: [server/index.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/index.js#L20-L21)
   - **Explanation**: A MongoDB Atlas connection string is hardcoded in the codebase: `mongodb+srv://rivaan:test123@...`. This leaks developer credentials to git history and makes environment separation impossible. We will move this to a secure `.env` file.

3. **Hardcoded JWT Secret String**:
   - **Location**: [server/middlewares/auth.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/middlewares/auth.js#L10) & [server/routes/auth.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/routes/auth.js#L22)
   - **Explanation**: JWT signing and verification is performed with a hardcoded `"passwordKey"` string. This is highly vulnerable and will be externalized to `process.env.JWT_SECRET_KEY`.

4. **Early socket changeListener loses events**:
   - **Location**: [lib/screens/document_screen.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/screens/document_screen.dart#L39-L45)
   - **Explanation**: The socket `changes` listener is registered before `fetchDocumentData()` finishes. It relies on the safe-navigation operator `_controller?.compose(...)`. If other clients emit changes while this client is fetching the initial document state, those edits are silently dropped, resulting in a desynchronized editor state immediately upon opening.

5. **Bitwise operator typo in Server Port**:
   - **Location**: [server/index.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/index.js#L9)
   - **Explanation**: The expression `const PORT = process.env.PORT | 3001;` uses a bitwise OR operator (`|`) instead of the logical OR operator (`||`). Although it resolves to `3001` when the port is undefined, it is a syntax typo that can cause unexpected behavior if a custom numeric port is provided.

---

## 4. Sync Engine Recommendation
We strongly recommend **Option A — Server-Side Delta Composition**.

### Justification:
- **Project Scope and Timeline**: Option A allows us to leverage the existing Socket.IO stack without completely rewriting both the client and server communication layers.
- **Complexity and Risk**: Option B (ShareDB) and Option C (Yjs) require introducing massive dependencies with complex Flutter-JS interop wrappers or writing custom adapters. Integrating a Yjs CRDT or ShareDB OT wire protocol inside Dart would take weeks of troubleshooting and introduce massive stability risks.
- **Performance at Target Scale**: The project specification requires supporting **10–20 simultaneous users per document**. The `quill-delta` engine is highly performant. Maintaining an authoritative in-memory `Delta` document state on the server, composing incoming modifications via `delta.compose()`, and broadcasting validated changes resolves conflict corruption completely, easily meeting the scale requirements.
- **Database Write Optimization**: The server-side debounced queue flushes the authoritative composed content to MongoDB every 5 seconds, resulting in a single write operation per document instead of hundreds under active typing, drastically reducing DB load.

---

## 5. Staged Implementation Plan (Stages 1-7)

Our implementation strategy consists of 7 isolated, testable, and sequentially ordered stages:

### STAGE 1 — WebSocket Authentication & Environment Hardening
- **Backend changes**:
  - Extract `JWT_SECRET_KEY`, `MONGO_URI`, `PORT`, and `GOOGLE_CLIENT_ID` into `.env` file.
  - Create [server/.env.example](file:///home/rabin/Downloads/Flutter_docs_project-main/server/.env.example) and update `.gitignore`.
  - Create a new socket auth middleware `server/middleware/socketAuth.js` that checks for a JWT token on connection handshake.
- **Frontend changes**:
  - Update `lib/repository/socket_repository.dart` and `lib/clients/socket_client.dart` to retrieve the current user's JWT from Riverpod and pass it as a `Bearer` token inside the Socket.IO connection's `auth` parameters.

### STAGE 2 — Server-Side Debounced Persistence (Kill the 2-Second Timer)
- **Backend changes**:
  - Implement a singleton `PersistenceQueue` (`server/workers/persistenceQueue.js`) mapping active documents in memory.
  - Set up a debounced timer that flushes dirty documents to MongoDB every 5 seconds.
  - Clean up index.js: delete the obsolete `save` socket handler and replace it with a call to the queue staging logic.
  - Add optimistic lock `version` fields to the Mongoose `Document` model.
  - Implement clean SIGTERM/SIGINT signal listeners to force a final flush before server exit.
- **Frontend changes**:
  - Identify and delete the periodic client-side auto-save `Timer` inside `lib/screens/document_screen.dart` entirely.

### STAGE 3 — Real-Time Conflict-Free Synchronization
- **Backend changes**:
  - Install `quill-delta` NPM package.
  - Create `server/services/documentRoomManager.js` to manage authoritative in-memory document deltas.
  - Rewrite socket events in `server/index.js` under a clean `// EVENT REGISTRY`:
    - Handle `join-document`: load document content into memory room, register socket room, and emit `load-document`.
    - Handle `submit-op`: validate client edit delta, compose it onto authoritative state, broadcast the operation to other room members using `receive-op`, and stage in persistence queue.
- **Frontend changes**:
  - Modify `lib/repository/socket_repository.dart` to emit `submit-op` instead of `typing` and map `receive-op` to local composer updates.
  - Update `lib/screens/document_screen.dart` to listen for initial states, delay socket listeners until `_controller` is initialized, and apply edits safely.

### STAGE 4 — Document Permissions & Secure Sharing
- **Backend changes**:
  - Activate `sharedWith` array in Mongoose `DocumentSchema` (e.g. `userId` ref, `permission: viewer|editor`).
  - Create `server/middleware/documentPermission.js` for checking REST operations.
  - Integrate permission checks inside the socket `submit-op` event handler to reject edits from users with `viewer` permissions.
- **Frontend changes**:
  - Enable sharing menu UI to grant roles.
  - Set `readOnly: true` on the `QuillEditor` if the user has a `viewer` role on the document.

### STAGE 5 — User Presence Indicators
- **Backend/Frontend changes**:
  - Implement `server/services/presenceManager.js` tracking active socket users per room.
  - Emit cursor coordinates under `cursor-move` socket event.
  - Show colored avatars in the top menu and render user cursors dynamically in the editor wrapper.

### STAGE 6 — Version History (Last 10 Snapshots)
- **Backend/Frontend changes**:
  - Create Mongoose model `DocumentHistory` to track version snapshots.
  - Save snapshot inside `persistenceQueue.js` on every DB write, keeping at most 10 historical snapshots.
  - Add REST routes `/api/documents/:id/history` and `/api/documents/:id/restore/:version` to inspect and roll back states.

### STAGE 7 — Docker Compose Full Stack
- **Infrastructure setup**:
  - Create `docker-compose.yml` linking `mongodb`, `redis`, and the `backend` Node.js container with persistent storage volumes.
  - Create `server/Dockerfile` compiling an optimized production build.

---

## 6. Verification & Acceptance Plan
Each stage will be verified using the following automated and manual criteria:

- **Stage 1 (Auth)**: Test with authenticated and unauthenticated connections. Unauthenticated sockets must be rejected with `AUTHENTICATION_REQUIRED`.
- **Stage 2 (Timer)**: Write content rapidly for 30s; verify MongoDB records are updated exactly once every 5 seconds with an incrementing version number.
- **Stage 3 (Sync)**: Open two browser windows, type concurrently in real-time. Verify changes merge instantly without text corruption.
- **Stage 4 (Permissions)**: Open as a Viewer. Verify that keyboard edits are disabled and any manual websocket edit injection receives a 403 error.
- **Stage 5 (Presence)**: Confirm other active users' colored avatars show in the top header and their colored cursors move in real-time.
- **Stage 6 (History)**: Perform 15 separate edits. Verify `/history` API returns exactly 10 states. Restore version 5 and confirm the text updates.
- **Stage 7 (Docker)**: Run `docker-compose up` and confirm all database, authentication, and synchronization processes initiate successfully.
