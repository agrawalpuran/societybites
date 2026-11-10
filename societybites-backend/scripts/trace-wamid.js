require("dotenv").config();

const messageId = process.argv[2];
if (!messageId) {
  console.error("Usage: node scripts/trace-wamid.js <wamid or id>");
  process.exit(1);
}

async function main() {
  const token = process.env.WHATSAPP_TOKEN;
  const version = process.env.WHATSAPP_API_VERSION || "v21.0";
  if (!token) {
    console.error("Missing WHATSAPP_TOKEN");
    process.exit(1);
  }

  const id = messageId.startsWith("wamid.") ? messageId : messageId;
  const url = `https://graph.facebook.com/${version}/${encodeURIComponent(id)}`;

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const body = await response.json();
  console.log("HTTP", response.status);
  console.log(JSON.stringify(body, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
