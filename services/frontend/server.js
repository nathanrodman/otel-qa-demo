// Frontend: a tiny storefront that calls the orders service.
// Intentionally uninstrumented -- OpenTelemetry is expected to be auto-injected.
const http = require("http");

const PORT = Number(process.env.PORT || 8080);
const ORDERS_URL = process.env.ORDERS_URL || "http://orders:8080";

const PRODUCTS = ["sku-apple", "sku-banana", "sku-cherry", "sku-durian"];

function callOrders(method, path, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, ORDERS_URL);
    const payload = body ? JSON.stringify(body) : undefined;
    const req = http.request(
      url,
      {
        method,
        headers: payload
          ? { "content-type": "application/json", "content-length": Buffer.byteLength(payload) }
          : {},
        timeout: 5000,
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => resolve({ status: res.statusCode, body: data }));
      }
    );
    req.on("timeout", () => req.destroy(new Error("orders request timed out")));
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

// Relay the upstream status; non-JSON bodies (e.g. a framework error page) become a JSON error.
function relay(res, r) {
  let body;
  try {
    body = JSON.parse(r.body);
  } catch {
    body = { error: "upstream returned non-JSON response", upstreamStatus: r.status };
  }
  send(res, r.status, body);
}

function send(res, status, obj) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(obj));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  try {
    if (url.pathname === "/healthz") return send(res, 200, { ok: true });

    if (url.pathname === "/" && req.method === "GET") {
      res.writeHead(200, { "content-type": "text/html" });
      return res.end(`<h1>Tiny Shop</h1>
<p>Endpoints:</p>
<ul>
  <li>GET /api/products</li>
  <li>POST /api/checkout?sku=sku-apple&qty=1</li>
  <li>GET /api/orders</li>
</ul>`);
    }

    if (url.pathname === "/api/products" && req.method === "GET") {
      const r = await callOrders("GET", "/stock");
      return relay(res, r);
    }

    if (url.pathname === "/api/checkout" && req.method === "POST") {
      const sku = url.searchParams.get("sku") || PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
      const qty = Number(url.searchParams.get("qty") || 1);
      const r = await callOrders("POST", "/orders", { sku, qty });
      return relay(res, r);
    }

    if (url.pathname === "/api/orders" && req.method === "GET") {
      const r = await callOrders("GET", "/orders");
      return relay(res, r);
    }

    send(res, 404, { error: "not found" });
  } catch (err) {
    console.error(`request ${req.method} ${url.pathname} failed: ${err.message}`);
    send(res, 502, { error: err.message });
  }
});

server.listen(PORT, () => console.log(`frontend listening on :${PORT}, orders=${ORDERS_URL}`));
