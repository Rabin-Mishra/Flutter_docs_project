const express = require("express");
const Document = require("../models/document");
const DocumentHistory = require("../models/DocumentHistory");
const User = require("../models/user");
const HTMLtoDOCX = require("html-to-docx");
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

// ─── WORD EXPORT (DOCX) ──────────────────────────────────────────────────────
documentRouter.get("/doc/:id/export/docx", auth, async (req, res) => {
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

    // High-fidelity conversion from Quill Delta JSON to basic semantic HTML
    const ops = document.content || [];
    let html = '';
    let inList = false;
    let listType = '';

    for (let i = 0; i < ops.length; i++) {
      const op = ops[i];
      if (!op.insert) continue;

      const attributes = op.attributes || {};
      let text = op.insert;

      if (typeof text === 'string') {
        const segments = text.split('\n');

        for (let j = 0; j < segments.length; j++) {
          let segment = segments[j];

          if (segment.length > 0) {
            // Escape standard HTML characters safely
            segment = segment
              .replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;');
            
            // Inline formatting tags
            if (attributes.bold) segment = `<strong>${segment}</strong>`;
            if (attributes.italic) segment = `<em>${segment}</em>`;
            if (attributes.underline) segment = `<u>${segment}</u>`;
          }

          if (j < segments.length - 1) {
            // End of line boundary: compile block tags
            if (attributes.header) {
              html += `<h${attributes.header}>${segment}</h${attributes.header}>`;
            } else if (attributes.list) {
              const listTag = attributes.list === 'ordered' ? 'ol' : 'ul';
              if (!inList) {
                html += `<${listTag}>`;
                inList = true;
                listType = listTag;
              }
              html += `<li>${segment}</li>`;
            } else {
              if (inList) {
                html += `</${listType}>`;
                inList = false;
              }
              html += `<p>${segment}</p>`;
            }
          } else {
            // Concat inline styled segment runs
            html += segment;
          }
        }
      }
    }

    if (inList) {
      html += `</${listType}>`;
    }

    const docxHtml = `<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>${html}</body></html>`;

    // Compile DOCX buffer using html-to-docx
    const fileBuffer = await HTMLtoDOCX(docxHtml, null, {
      table: { row: { cantSplit: true } },
      footer: true,
      header: true,
      pageNumber: true,
    });

    const safeTitle = (document.title || "Untitled").replace(/[^a-zA-Z0-9]/g, "_");

    // Set download file headers
    res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
    res.setHeader("Content-Disposition", `attachment; filename=${safeTitle}.docx`);
    res.send(fileBuffer);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = documentRouter;

