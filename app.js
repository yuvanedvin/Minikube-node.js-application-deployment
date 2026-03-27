const express = require("express");
const client = require("prom-client");

const app = express();
const port = 3000;

// Create a Registry
const register = new client.Registry();

// Default metrics (CPU, memory, etc.)
client.collectDefaultMetrics({ register });

// Custom metric: HTTP request counter
const httpRequestCounter = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status"],
});

register.registerMetric(httpRequestCounter);

// Simulate workload
app.get("/", (req, res) => {
  const randomDelay = Math.random() * 500;

  setTimeout(() => {
    httpRequestCounter.inc({
      method: "GET",
      route: "/",
      status: 200,
    });

    res.send("Hello from Kubernetes monitoring app 🚀");
  }, randomDelay);
});

// Metrics endpoint
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

app.listen(port, () => {
  console.log(`App running on port ${port}`);
});