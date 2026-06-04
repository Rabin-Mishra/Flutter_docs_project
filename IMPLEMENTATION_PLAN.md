# SyncWrite — Master Implementation Plan & Advanced Stages (8 - 10)

This implementation plan details the technical architecture, packages, and code changes required to build the advanced stages (8 through 10). It has been committed directly to your repository so you can easily review the design before we proceed.

---

## 🗺️ Staged Roadmap (Stages 8 - 10)

### STAGE 8 — Export & Download Options (PDF, DOCX, TXT)
**Goal:** Allow users to export and download the document content in multiple common formats.

*   **PDF Exporter (Client-Side)**: Translates the editor's Quill Delta operations natively into print-ready PDF layout elements using the `pdf` package. Completely client-side for immediate downloads.
*   **Plain Text Exporter (Client-Side)**: Extracts raw unformatted strings from the Quill Delta and triggers an instant browser download.
*   **Word Document Exporter (Server-Side)**: Converts composed Delta document operations into clean HTML, which is then compiled into a Microsoft Word `.docx` binary buffer on the server using `html-to-docx`.

#### Technical Details & Changes:
- **[NEW] [export_service.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/services/export_service.dart)**: Implements client-side builders using the `pdf` and `printing` packages.
- **[MODIFY] [document.js routes](file:///home/rabin/Downloads/Flutter_docs_project-main/server/routes/document.js)**: Adds the secure route `/doc/:id/export/docx`.
- **[MODIFY] [document_screen.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/screens/document_screen.dart)**: Adds the "File -> Download" dropdown menu to trigger downloads.

---

### STAGE 9 — Rich Content Insertion (Tables, Links, Images, Charts)
**Goal:** Insert and render rich, collaborative, and interactive elements directly inside the editor canvas.

*   **Links**: Integrates Quill's standard `LinkAttribute` for highlighting text and creating active URLs.
*   **Images**: Adds interactive image embeds by pasting web URLs or uploading local images converting to base64.
*   **Tables**: Inserts editable Markdown-like tables or HTML grid layouts.
*   **Charts**: Inserts interactive chart embeds (Bar, Line, Pie) with user-defined key-value datasets, rendering interactively inside the editor using standard Flutter charts.

#### Technical Details & Changes:
- **[MODIFY] [document_screen.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/screens/document_screen.dart)**: Adds the "Insert" menu group in the toolbar.
- **[MODIFY] [documentRoomManager.js](file:///home/rabin/Downloads/Flutter_docs_project-main/server/services/documentRoomManager.js)**: Standardizes support for rich embeds in the synchronization Delta array.

---

### STAGE 10 — Document Tooling (Word Count & Dictionary)
**Goal:** Introduce writing assistants to improve editing productivity.

*   **Word Count**: A modal dialog computing words (split by whitespace), characters (with/without spacing), and paragraphs (line breaks).
*   **Dictionary Lookup Sidebar**: A sleek collapsible sidebar on the right side of the screen. Double-clicking any word or opening the sidebar queries the public `DictionaryAPI.dev` to display definitions, synonyms, and pronunciation in real-time.

#### Technical Details & Changes:
- **[NEW] [dictionary_service.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/services/dictionary_service.dart)**: Handles dictionary REST API fetches.
- **[MODIFY] [document_screen.dart](file:///home/rabin/Downloads/Flutter_docs_project-main/lib/screens/document_screen.dart)**: Adds the "Tools" dropdown, Word Count dialog, and collapsible sidebar panels.

---

## 🧪 Verification & Testing Plan

*   **Stage 8**: Export tests. Confirm bold, italic, and header elements compile to standard formats. Check DOCX headers on MS Word.
*   **Stage 9**: Live rich-embed sync tests. Confirm tables and custom charts are synchronized in real-time between concurrent active sessions.
*   **Stage 10**: Word count exact verification, and dictionary API sidebar lookup checks.
