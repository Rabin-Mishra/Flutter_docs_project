const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const http = require("http");
const authRouter = require("./routes/auth");
const documentRouter = require("./routes/document");
const Document = require("./models/document");
const User = require("./models/user");

const PORT = process.env.PORT || 3005;

const app = express();
var server = http.createServer(app);
var io = require("socket.io")(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});
const socketAuthMiddleware = require("./middlewares/socketAuth");
const persistenceQueue = require("./workers/persistenceQueue");
const roomManager = require("./services/documentRoomManager");
const presenceManager = require("./services/presenceManager");

app.use(cors());
app.use(express.json());
app.use(authRouter);
app.use(documentRouter);

const DB = process.env.MONGO_URI || "mongodb://localhost:27017/syncwrite";

mongoose
  .connect(DB)
  .then(() => {
    console.log("Connection successful!");
  })
  .catch((err) => {
    console.log(err);
  });

io.use(socketAuthMiddleware);

io.on("connection", (socket) => {
  console.log(`[Socket] Connected: user=${socket.user.id} socket=${socket.id}`);

  // ─── JOIN DOCUMENT ROOM ───────────────────────────────────────────────────
  socket.on("join-document", async ({ documentId }) => {
    try {
      const doc = await Document.findById(documentId);
      if (!doc) throw new Error("Document not found.");

      const user = await User.findById(socket.user.id);
      if (!user) throw new Error("User not found.");

      const isOwner = doc.uid === socket.user.id;
      const share = doc.sharedWith.find(s => s.email === user.email);

      if (!isOwner && !share) {
        throw new Error("You do not have permission to access this document.");
      }

      const userPermission = isOwner ? "owner" : share.permission;
      socket.userPermission = userPermission; // Cache for other event handlers

      const currentDelta = await roomManager.joinRoom(documentId, socket.id);
      socket.join(documentId);
      socket.currentDocumentId = documentId; // Track for disconnect cleanup

      // Send the current authoritative document state and user permission to the client
      socket.emit("load-document", { 
        content: currentDelta.ops,
        permission: userPermission
      });

      // Join the presence tracker
      const userInfo = {
        userId: user._id.toString(),
        name: user.name,
        email: user.email,
        avatarUrl: user.profilePic || "",
      };
      presenceManager.join(documentId, socket.id, userInfo);

      // Broadcast updated presence list to everyone in the room
      io.to(documentId).emit("presence-update", {
        users: presenceManager.getPresenceList(documentId)
      });

      console.log(`[Socket] User ${socket.user.id} (${userPermission}) joined document ${documentId}`);
    } catch (err) {
      socket.emit("error", { message: err.message });
      console.error(`[Socket] join-document error:`, err.message);
    }
  });

  // ─── SUBMIT AN OPERATION ─────────────────────────────────────────────────
  socket.on("submit-op", ({ documentId, delta }) => {
    try {
      if (socket.userPermission === "viewer") {
        throw new Error("You have view-only access to this document.");
      }

      const newAuthoritative = roomManager.applyOp(documentId, delta);

      // Broadcast the incoming delta to other clients in the room immediately
      socket.to(documentId).emit("receive-op", { delta });

      // Stage the new authoritative snapshot's operations array for database persistence
      persistenceQueue.stage(documentId, newAuthoritative.ops);
    } catch (err) {
      socket.emit("error", { message: err.message });
      console.error(`[Socket] submit-op error:`, err.message);
    }
  });

  // ─── CURSOR POSITION UPDATES ──────────────────────────────────────────────
  socket.on("cursor-move", ({ documentId, index, length }) => {
    try {
      presenceManager.updateCursor(documentId, socket.id, { index, length });
      const presenceList = presenceManager.getPresenceList(documentId);
      const user = presenceList.find(u => u.userId === socket.user.id);
      
      socket.to(documentId).emit("cursor-update", {
        userId: socket.user.id,
        color: user ? user.color : "#E53935",
        cursor: { index, length },
      });
    } catch (err) {
      console.error(`[Socket] cursor-move error:`, err.message);
    }
  });

  // ─── DISCONNECT ──────────────────────────────────────────────────────────
  socket.on("disconnect", () => {
    if (socket.currentDocumentId) {
      roomManager.leaveRoom(socket.currentDocumentId, socket.id);
      presenceManager.leave(socket.currentDocumentId, socket.id);
      io.to(socket.currentDocumentId).emit("presence-update", {
        users: presenceManager.getPresenceList(socket.currentDocumentId)
      });
    }
    console.log(`[Socket] Disconnected: socket=${socket.id}`);
  });
});

// Ensure final flush on graceful shutdown
process.on("SIGTERM", async () => {
  console.log("[Server] SIGTERM received. Flushing persistence queue...");
  await persistenceQueue.forceFlush();
  process.exit(0);
});

process.on("SIGINT", async () => {
  console.log("[Server] SIGINT received. Flushing persistence queue...");
  await persistenceQueue.forceFlush();
  process.exit(0);
});

// Intercept nodemon restart signal to force immediate MongoDB flush
process.once("SIGUSR2", async () => {
  console.log("[Server] SIGUSR2 received (nodemon restart). Flushing persistence queue...");
  await persistenceQueue.forceFlush();
  process.kill(process.pid, "SIGUSR2");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`connected at port ${PORT}`);
});
