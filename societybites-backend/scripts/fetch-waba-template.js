require("dotenv").config();
const { readConfig } = require("../lib/whatsappCloud");

async function get(url, token) {
  const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  return { status: r.status, body: await r.json() };
}

async function main() {
  const cfg = readConfig();
  const name = process.argv[2] || cfg.templateName;

  const dbg = await get(
    `https://graph.facebook.com/${cfg.apiVersion}/debug_token?input_token=${encodeURIComponent(cfg.token)}&access_token=${encodeURIComponent(cfg.token)}`,
    cfg.token
  );
  const granular = dbg.body?.data?.granular_scopes || [];
  const wabaIds = new Set();
  for (const g of granular) {
    if (g.scope && String(g.scope).includes("whatsapp")) {
      for (const id of g.target_ids || []) wabaIds.add(String(id));
    }
  }
  console.log("Granular WABA targets from token:", [...wabaIds]);

  let templates = null;
  for (const wabaId of wabaIds) {
    const url = `https://graph.facebook.com/${cfg.apiVersion}/${wabaId}/message_templates?fields=name,status,language,category,components,sub_category,rejected_reason,quality_score&limit=50`;
    const r = await get(url, cfg.token);
    if (!r.body?.error) {
      const match = (r.body.data || []).filter((t) => t.name === name);
      if (match.length) {
        console.log("\n=== WABA", wabaId, "template", name, "===");
        console.log(JSON.stringify(match, null, 2));
        templates = match;
        break;
      }
    } else {
      console.log("WABA", wabaId, r.body.error.message);
    }
  }

  if (!templates?.length) {
    console.log("\nNo template found via token WABA list. Set WHATSAPP_BUSINESS_ACCOUNT_ID in .env and retry.");
    return;
  }

  for (const t of templates) {
    const comps = t.components || [];
    const hasFlow = comps.some(
      (c) =>
        (c.buttons || []).some((b) => b.type === "FLOW" || b.flow_id) ||
        c.type === "BUTTONS" && (c.buttons || []).length
    );
    const body = comps.find((c) => c.type === "BODY");
    const vars = body?.text ? (body.text.match(/\{\{\d+\}\}/g) || []).length : 0;
    console.log("\n=== Analysis ===");
    console.log({ status: t.status, category: t.category, bodyVarCount: vars, hasFlowOrButtons: hasFlow });
    if (hasFlow) {
      console.log(
        "CRITICAL: Template has FLOW/BUTTONS. Insights 131000 often means Flow endpoint or missing business public key.",
        "Fix: Create a new template with NO buttons/flows, or configure Flow encryption in Meta."
      );
    }
    console.log("Components:", comps.map((c) => c.type));
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
