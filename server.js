const path = require("path");
const fs = require("fs");
const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const Database = require("better-sqlite3");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" },
  maxHttpBufferSize: 1e7,
});

const PORT = process.env.PORT || 3000;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "data");
fs.mkdirSync(DATA_DIR, { recursive: true });

const db = new Database(path.join(DATA_DIR, "conference.db"));
db.pragma("journal_mode = WAL");
db.exec(`
  CREATE TABLE IF NOT EXISTS app_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    data TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
`);

const getRow = db.prepare("SELECT data, updated_at FROM app_state WHERE id = 1");
const upsert = db.prepare(`
  INSERT INTO app_state (id, data, updated_at)
  VALUES (1, @data, @updated_at)
  ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at
`);

function readState() {
  const row = getRow.get();
  if (!row) return { state: null, updatedAt: null };
  try {
    return { state: JSON.parse(row.data), updatedAt: row.updated_at };
  } catch {
    return { state: null, updatedAt: row.updated_at };
  }
}

function writeState(state) {
  const updatedAt = new Date().toISOString();
  upsert.run({ data: JSON.stringify(state || {}), updated_at: updatedAt });
  return updatedAt;
}

app.use(express.json({ limit: "10mb" }));
app.use((req, res, next) => {
  res.setHeader("Cache-Control", "no-store");
  next();
});
app.use(express.static(path.join(__dirname, "public")));

app.get("/api/state", (req, res) => {
  res.json(readState());
});

app.post("/api/state", (req, res) => {
  const clientId = req.body && req.body.clientId;
  const state = req.body && req.body.state;
  if (!state || typeof state !== "object") {
    return res.status(400).json({ ok: false, error: "state object is required" });
  }
  const updatedAt = writeState(state);
  io.emit("state-updated", { clientId, state, updatedAt });
  res.json({ ok: true, updatedAt });
});

io.on("connection", (socket) => {
  const current = readState();
  socket.emit("server-state", current);

  socket.on("save-state", (payload = {}) => {
    if (!payload.state || typeof payload.state !== "object") return;
    const updatedAt = writeState(payload.state);
    socket.broadcast.emit("state-updated", {
      clientId: payload.clientId,
      state: payload.state,
      updatedAt,
    });
    socket.emit("state-saved", { updatedAt });
  });
});

server.listen(PORT, () => {
  console.log(`Conference manager online app is running on port ${PORT}`);
});
