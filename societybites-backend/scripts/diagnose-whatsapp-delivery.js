/**
 * End-to-end WhatsApp delivery diagnostics (no message send unless --send).
 */
require("dotenv").config();
const { readConfig, isConfigured, graphMessagesUrl, templatePayload, orderTemplateParameters } = require("../lib/whatsappCloud");
const prisma = require("../lib/prisma");

async function graphGet(cfg, path, query = "") {
  const q = query ? (query.startsWith("?") ? query : `?${query}`) : "";
  const url = `https://graph.facebook.com/${cfg.apiVersion}/${path}${q}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${cfg.token}` },
  });
  const body = await response.json();
  return { ok: response.ok, status: response.status, body };
}

async function findWabaId(cfg) {
  const wabaEnv = String(process.env.WHATSAPP_BUSINESS_ACCOUNT_ID || "").trim();
  if (wabaEnv) return wabaEnv;

  const attempts = [
    `${cfg.phoneNumberId}?fields=account_mode,display_phone_number,verified_name,quality_rating,name_status,status`,
    `${cfg.phoneNumberId}?fields=throughput`,
  ];
  for (const path of attempts) {
    const r = await graphGet(cfg, path);
    if (r.ok && r.body) {
      const id = r.body.whatsapp_business_account_id || r.body.waba_id;
      if (id) return String(id);
    }
  }

  const biz = await graphGet(cfg, "me", "fields=businesses");
  if (biz.ok && biz.body?.businesses?.data?.length) {
    for (const b of biz.body.businesses.data) {
      const owned = await graphGet(cfg, b.id, "fields=owned_whatsapp_business_accounts");
      const list = owned.body?.owned_whatsapp_business_accounts?.data || [];
      for (const w of list) {
        if (w.id) return String(w.id);
      }
    }
  }
  return null;
}

async function fetchTemplate(cfg, wabaId, name) {
  const r = await graphGet(
    cfg,
    wabaId,
    `message_templates?fields=name,status,language,category,components&limit=50`
  );
  if (!r.ok) return { error: r.body };
  const all = r.body.data || [];
  return all.filter((t) => t.name === name);
}

async function main() {
  const doSend = process.argv.includes("--send");
  const toOverride = process.argv.find((a) => a.startsWith("--to="))?.split("=")[1];

  const cfg = readConfig();
  console.log("=== 1. Environment ===");
  console.log({
    apiConfigured: isConfigured(cfg),
    phoneNumberId: cfg.phoneNumberId,
    templateName: cfg.templateName,
    templateLanguage: cfg.templateLanguage,
    emergencyOff: cfg.emergencyOff,
  });

  if (!isConfigured(cfg)) {
    console.log("FAIL: WHATSAPP_TOKEN or WHATSAPP_PHONE_NUMBER_ID missing.");
    return;
  }

  console.log("\n=== 2. Token + sender (live number) ===");
  const phone = await graphGet(
    cfg,
    cfg.phoneNumberId,
    "fields=id,display_phone_number,verified_name,account_mode,quality_rating,name_status,status,is_official_business_account"
  );
  if (!phone.ok) {
    console.log("FAIL: Cannot read phone number — token or ID wrong.");
    console.log(phone.body?.error || phone.body);
    return;
  }
  console.log(phone.body);

  console.log("\n=== 3. Template on WABA (must match .env) ===");
  const wabaId = await findWabaId(cfg);
  if (!wabaId) {
    console.log(
      "SKIP: Set WHATSAPP_BUSINESS_ACCOUNT_ID in .env (WhatsApp Manager account ID) to audit template components."
    );
  } else {
    console.log("WABA ID:", wabaId);
    const templates = await fetchTemplate(cfg, wabaId, cfg.templateName);
    if (templates.error) {
      console.log("FAIL fetching templates:", templates.error?.error || templates.error);
    } else if (!templates.length) {
      console.log(`FAIL: Template "${cfg.templateName}" not on this WABA.`);
    } else {
      for (const t of templates) {
        console.log(JSON.stringify(t, null, 2));
        const body = (t.components || []).find((c) => c.type === "BODY" || c.type === "body");
        if (body?.text) {
          const varCount = (body.text.match(/\{\{\d+\}\}/g) || []).length;
          console.log(`Template BODY variable placeholders: ${varCount} (app sends 5 body params)`);
          if (varCount !== 5) {
            console.log("FAIL: Parameter count mismatch likely blocks delivery.");
          }
        }
      }
    }
  }

  console.log("\n=== 4. Recipient (seller phone on latest order) ===");
  const order = await prisma.order.findFirst({
    orderBy: { createdAt: "desc" },
    include: {
      buyer: { select: { phone: true, name: true } },
      items: { include: { listing: { include: { seller: { select: { phone: true, name: true } } } } } },
    },
  });
  if (order) {
    const sellerPhone = order.items[0]?.listing?.seller?.phone;
    const params = orderTemplateParameters(order);
    console.log({
      orderNumber: order.orderNumber,
      sellerPhone,
      sellerName: order.items[0]?.listing?.seller?.name,
      buyerPhone: order.buyer?.phone,
      bodyParamCount: params?.length,
    });
  }

  if (doSend) {
    const to = toOverride || "919845154070";
    const sampleOrder = order || {
      orderNumber: "SE-DIAG",
      total: 1,
      buyer: { name: "Test User" },
      items: [
        {
          quantity: 1,
          listing: { name: "Test Item", seller: { name: "Agrawal's", phone: "+919845154070" } },
        },
      ],
    };
    const parameters = orderTemplateParameters(sampleOrder);
    const payload = templatePayload(to, {
      templateName: cfg.templateName,
      language: cfg.templateLanguage,
      parameters,
    });
    console.log("\n=== 5. Test send to", to, "===");
  const response = await fetch(graphMessagesUrl(cfg), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cfg.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    const body = await response.json();
    console.log("HTTP", response.status);
    console.log(JSON.stringify(body, null, 2));
    if (body.error) {
      console.log("\nMeta rejected the send — fix error above.");
    } else if (body.messages?.[0]?.message_status === "accepted") {
      console.log("\nMeta ACCEPTED. If phone still empty within 5 min:");
      console.log("- WhatsApp Manager → +1 711 → Insights (include TODAY)");
      console.log("- Phone logged in as +91 9845154070; search SocietyEats / 711; check Business tab");
      console.log("- Message +1 711-008-4893 once from that phone, then retry");
    }
  } else {
    console.log("\n=== 5. Test send (skipped) ===");
    console.log("Run: node scripts/diagnose-whatsapp-delivery.js --send");
    console.log("Or:  node scripts/diagnose-whatsapp-delivery.js --send --to=919845154070");
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
