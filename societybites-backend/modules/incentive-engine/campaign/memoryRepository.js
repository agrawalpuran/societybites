const { randomUUID } = require("crypto");

function clone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function createMemoryRepository() {
  const campaigns = new Map();
  const versions = new Map();
  const audits = [];
  const issued = { rewards: [], ledger: [], events: [], referrals: [], coupons: [] };
  let writes = 0;

  function touch() {
    writes += 1;
  }

  return {
    writes: () => writes,
    issued: () => clone(issued),
    audits: () => clone(audits),
    async createCampaign(row) {
      touch();
      const campaign = {
        id: randomUUID(),
        description: null,
        priority: 0,
        stackingMode: "STACK",
        startsAt: null,
        endsAt: null,
        currentVersionId: null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        ...row,
        status: "DRAFT",
      };
      campaigns.set(campaign.id, campaign);
      return clone(campaign);
    },
    async listCampaigns() {
      return [...campaigns.values()].map((row) => clone(row));
    },
    async getCampaign(id) {
      return clone(campaigns.get(id) || null);
    },
    async saveCampaign(campaign) {
      touch();
      const next = { ...campaign, updatedAt: new Date().toISOString() };
      campaigns.set(campaign.id, next);
      return clone(next);
    },
    async createVersion(row) {
      touch();
      const version = {
        id: randomUUID(),
        publishedAt: null,
        publishedBy: null,
        createdAt: new Date().toISOString(),
        ...row,
      };
      versions.set(version.id, version);
      return clone(version);
    },
    async saveVersion(version) {
      const current = versions.get(version.id);
      if (current && current.publishedAt) {
        const error = new Error("Published campaign versions are immutable");
        error.statusCode = 409;
        throw error;
      }
      touch();
      versions.set(version.id, { ...version });
      return clone(version);
    },
    async listVersions(campaignId) {
      return [...versions.values()]
        .filter((row) => row.campaignId === campaignId)
        .sort((left, right) => left.versionNumber - right.versionNumber)
        .map((row) => clone(row));
    },
    async getVersion(id) {
      return clone(versions.get(id) || null);
    },
    async appendAudit(row) {
      touch();
      audits.push({ id: randomUUID(), createdAt: new Date().toISOString(), ...row });
    },
  };
}

module.exports = { createMemoryRepository };
