const express = require("express");
const client = require("prom-client");

const app = express();
const PORT = process.env.PORT || 3000;
const APP_ENV = process.env.APP_ENV || "development";

// ─── Structured Logger ────────────────────────────────────────────────────────
const log = {
  info: (msg, meta = {}) =>
    console.log(JSON.stringify({ level: "info", msg, env: APP_ENV, ...meta, ts: new Date().toISOString() })),
  warn: (msg, meta = {}) =>
    console.warn(JSON.stringify({ level: "warn", msg, env: APP_ENV, ...meta, ts: new Date().toISOString() })),
  error: (msg, meta = {}) =>
    console.error(JSON.stringify({ level: "error", msg, env: APP_ENV, ...meta, ts: new Date().toISOString() })),
};

// ─── Prometheus Metrics ───────────────────────────────────────────────────────
const register = new client.Registry();
register.setDefaultLabels({ app: "monitoring-app", env: APP_ENV });
client.collectDefaultMetrics({ register });

// Counter: total HTTP requests by method, route, status
const httpRequestCounter = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status"],
  registers: [register],
});

// Histogram: request duration in seconds
const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "route", "status"],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

// Gauge: currently active requests
const activeRequests = new client.Gauge({
  name: "http_active_requests",
  help: "Number of active HTTP requests",
  registers: [register],
});

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  if (req.path === "/metrics" || req.path === "/healthz" || req.path === "/readyz") {
    return next();
  }
  const end = httpRequestDuration.startTimer({ method: req.method, route: req.path });
  activeRequests.inc();

  res.on("finish", () => {
    const status = res.statusCode.toString();
    httpRequestCounter.inc({ method: req.method, route: req.path, status });
    end({ status });
    activeRequests.dec();
    log.info("request", { method: req.method, path: req.path, status, ip: req.ip });
  });
  next();
});

// ─── Routes ───────────────────────────────────────────────────────────────────

// Liveness probe — is the process alive?
app.get("/healthz", (req, res) => {
  res.status(200).json({ status: "ok", uptime: process.uptime() });
});

// Readiness probe — is the app ready to serve traffic?
app.get("/readyz", (req, res) => {
  // Add real dependency checks here (DB, cache, etc.)
  res.status(200).json({ status: "ready", env: APP_ENV });
});

// Main route
app.get("/", (req, res) => {
  const randomDelay = Math.random() * 500;
  setTimeout(() => {
    res.send("Hello from Kubernetes production-ready app 🚀");
  }, randomDelay);
});

// Metrics endpoint for Prometheus
app.get("/metrics", async (req, res) => {
  try {
    res.set("Content-Type", register.contentType);
    res.end(await register.metrics());
  } catch (err) {
    log.error("metrics endpoint failed", { error: err.message });
    res.status(500).end();
  }
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: "Not found" });
});

// Global error handler
app.use((err, req, res, next) => {
  log.error("unhandled error", { error: err.message, stack: err.stack });
  res.status(500).json({ error: "Internal server error" });
});

// ─── Server + Graceful Shutdown ───────────────────────────────────────────────
const server = app.listen(PORT, () => {
  log.info(`App started`, { port: PORT, env: APP_ENV });
});

const shutdown = (signal) => {
  log.warn(`Received ${signal}, shutting down gracefully...`);
  server.close(() => {
    log.info("Server closed. Exiting.");
    process.exit(0);
  });

  // Force exit if graceful shutdown takes too long
  setTimeout(() => {
    log.error("Forced shutdown after timeout");
    process.exit(1);
  }, 10000);
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

process.on("uncaughtException", (err) => {
  log.error("Uncaught exception", { error: err.message, stack: err.stack });
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  log.error("Unhandled rejection", { reason: String(reason) });
  process.exit(1);
});
