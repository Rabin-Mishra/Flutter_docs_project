const mongoose = require("mongoose");

const documentSchema = mongoose.Schema({
  uid: {
    required: true,
    type: String,
  },
  createdAt: {
    required: true,
    type: Number,
  },
  title: {
    required: true,
    type: String,
    trim: true,
  },
  content: {
    type: Array,
    default: [],
  },
  version: {
    type: Number,
    default: 0,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
  sharedWith: [{
    email: {
      type: String,
      required: true,
    },
    permission: {
      type: String,
      enum: ["viewer", "editor"],
      default: "viewer",
    },
  }],
});

const Document = mongoose.model("Document", documentSchema);

module.exports = Document;
