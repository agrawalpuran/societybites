function installMockGraphFetch({
  ok = true,
  status = 200,
  body = { messages: [{ id: "wamid.regression" }] },
} = {}) {
  const calls = [];
  const previous = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), options });
    return {
      ok,
      status,
      json: async () => body,
    };
  };
  return {
    calls,
    restore() {
      globalThis.fetch = previous;
    },
  };
}

async function waitForCalls(calls, count, label, timeoutMs = 2500) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (calls.length >= count) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`${label}: expected ${count} Graph call(s), got ${calls.length}`);
}

module.exports = {
  installMockGraphFetch,
  waitForCalls,
};
