const Document = require('../models/document');
const DocumentHistory = require('../models/DocumentHistory');

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
        this._persistDocument(docId, content).catch(err => {
          console.error(`[PersistenceQueue] Failed to write document ${docId}:`, err.message);
          // Re-stage the failed write so it retries on the next flush
          this.stage(docId, content);
        })
      );
    }

    await Promise.all(writeOps);
    console.log(`[PersistenceQueue] Flushed ${snapshot.size} document(s) to MongoDB.`);
  }

  async _persistDocument(docId, content) {
    // Update the main document and increment the version atomically
    const updatedDoc = await Document.findByIdAndUpdate(
      docId,
      { $set: { content }, $inc: { version: 1 }, updatedAt: new Date() },
      { new: true } // Return the updated document so we get the new version number
    );

    if (!updatedDoc) {
      throw new Error(`Document ${docId} not found during flush.`);
    }

    // Save a version history snapshot
    await DocumentHistory.create({
      documentId: docId,
      version: updatedDoc.version,
      content,
    });

    // Prune to keep only the 10 most recent snapshots for this document
    const staleSnapshots = await DocumentHistory.find({ documentId: docId })
      .sort({ version: -1 })
      .skip(10)
      .select('_id');

    if (staleSnapshots.length > 0) {
      await DocumentHistory.deleteMany({ _id: { $in: staleSnapshots.map(s => s._id) } });
    }
  }

  // Call this on server shutdown for a clean final write
  async forceFlush() {
    clearInterval(this.timer);
    this.timer = null;
    await this._flush();
  }
}

module.exports = new PersistenceQueue();
