const express = require("express");
const Document = require("../models/document");
const DocumentHistory = require("../models/DocumentHistory");
const User = require("../models/user");
const documentRouter = express.Router();
const auth = require("../middlewares/auth");

documentRouter.post("/doc/create", auth, async (req, res) => {
  try {
    const { createdAt } = req.body;
    let document = new Document({
      uid: req.user,
      title: "Untitled Document",
      createdAt,
    });

    document = await document.save();
    res.json(document);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

documentRouter.get("/docs/me", auth, async (req, res) => {
  try {
    const user = await User.findById(req.user);
    if (!user) return res.status(401).json({ error: "User not found." });

    let documents = await Document.find({
      $or: [
        { uid: req.user },
        { "sharedWith.email": user.email }
      ]
    });
    res.json(documents);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

documentRouter.post("/doc/title", auth, async (req, res) => {
  try {
    const { id, title } = req.body;
    const document = await Document.findByIdAndUpdate(id, { title });

    res.json(document);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

documentRouter.get("/doc/:id", auth, async (req, res) => {
  try {
    const document = await Document.findById(req.params.id);
    if (!document) return res.status(404).json({ error: "Document not found." });

    const user = await User.findById(req.user);
    if (!user) return res.status(401).json({ error: "User not found." });

    const isOwner = document.uid === req.user;
    const share = document.sharedWith.find(s => s.email === user.email);

    if (!isOwner && !share) {
      return res.status(403).json({ error: "You do not have permission to access this document." });
    }

    res.json(document);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

documentRouter.post("/doc/share", auth, async (req, res) => {
  try {
    const { id, email, permission } = req.body;
    const document = await Document.findById(id);
    if (!document) return res.status(404).json({ error: "Document not found." });

    if (document.uid !== req.user) {
      return res.status(403).json({ error: "Only the owner can share this document." });
    }

    // Check if user exists
    const targetUser = await User.findOne({ email });
    if (!targetUser) {
      return res.status(404).json({ error: "No user found with this email." });
    }

    // Don't allow sharing with oneself
    if (targetUser._id.toString() === req.user) {
      return res.status(400).json({ error: "You cannot share the document with yourself." });
    }

    const existingShareIndex = document.sharedWith.findIndex(s => s.email === email);
    if (existingShareIndex > -1) {
      document.sharedWith[existingShareIndex].permission = permission;
    } else {
      document.sharedWith.push({ email, permission });
    }

    await document.save();
    res.json(document);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ─── VERSION HISTORY ──────────────────────────────────────────────────────────
// GET /doc/:id/history — returns the last 10 version snapshots for a document
documentRouter.get("/doc/:id/history", auth, async (req, res) => {
  try {
    const document = await Document.findById(req.params.id);
    if (!document) return res.status(404).json({ error: "Document not found." });

    const user = await User.findById(req.user);
    if (!user) return res.status(401).json({ error: "User not found." });

    const isOwner = document.uid === req.user;
    const share = document.sharedWith.find(s => s.email === user.email);

    if (!isOwner && !share) {
      return res.status(403).json({ error: "You do not have permission to access this document." });
    }

    const history = await DocumentHistory.find({ documentId: req.params.id })
      .sort({ version: -1 })
      .limit(10)
      .select('version content savedAt');

    res.json(history);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /doc/:id/restore/:version — restores a document to a specific version snapshot
documentRouter.post("/doc/:id/restore/:version", auth, async (req, res) => {
  try {
    const document = await Document.findById(req.params.id);
    if (!document) return res.status(404).json({ error: "Document not found." });

    // Only owner and editors can restore
    const user = await User.findById(req.user);
    if (!user) return res.status(401).json({ error: "User not found." });

    const isOwner = document.uid === req.user;
    const share = document.sharedWith.find(s => s.email === user.email);

    if (!isOwner && (!share || share.permission !== 'editor')) {
      return res.status(403).json({ error: "Only the owner or editors can restore versions." });
    }

    const targetVersion = parseInt(req.params.version, 10);
    const snapshot = await DocumentHistory.findOne({
      documentId: req.params.id,
      version: targetVersion,
    });

    if (!snapshot) {
      return res.status(404).json({ error: `Version ${targetVersion} not found.` });
    }

    // Restore the document content and bump version
    const updatedDoc = await Document.findByIdAndUpdate(
      req.params.id,
      {
        $set: { content: snapshot.content },
        $inc: { version: 1 },
        updatedAt: new Date(),
      },
      { new: true }
    );

    // Also save this restore as a new history entry
    await DocumentHistory.create({
      documentId: req.params.id,
      version: updatedDoc.version,
      content: snapshot.content,
    });

    // Prune to keep only the 10 most recent snapshots
    const staleSnapshots = await DocumentHistory.find({ documentId: req.params.id })
      .sort({ version: -1 })
      .skip(10)
      .select('_id');

    if (staleSnapshots.length > 0) {
      await DocumentHistory.deleteMany({ _id: { $in: staleSnapshots.map(s => s._id) } });
    }

    res.json(updatedDoc);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = documentRouter;

