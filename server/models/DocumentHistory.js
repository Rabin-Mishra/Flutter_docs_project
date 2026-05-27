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
