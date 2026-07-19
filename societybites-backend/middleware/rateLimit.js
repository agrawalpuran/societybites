const requests = new Map();

function rateLimit({ windowMs = 60000, max = 100 } = {}) {
  return (req, res, next) => {
    const key = req.ip || req.connection.remoteAddress;
    const now = Date.now();
    const windowStart = now - windowMs;

    if (!requests.has(key)) {
      requests.set(key, []);
    }

    const timestamps = requests.get(key).filter((t) => t > windowStart);
    timestamps.push(now);
    requests.set(key, timestamps);

    if (timestamps.length > max) {
      return res.status(429).json({ error: "Too many requests. Please try again later." });
    }

    next();
  };
}

setInterval(() => {
  const cutoff = Date.now() - 300000;
  for (const [key, timestamps] of requests.entries()) {
    const filtered = timestamps.filter((t) => t > cutoff);
    if (filtered.length === 0) requests.delete(key);
    else requests.set(key, filtered);
  }
}, 300000);

module.exports = { rateLimit };
