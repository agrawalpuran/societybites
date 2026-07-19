const LOG_LEVEL = process.env.LOG_LEVEL || "info";
const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };

function shouldLog(level) {
  return LEVELS[level] <= (LEVELS[LOG_LEVEL] || 2);
}

function formatLog(level, category, message, data) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    category,
    message,
    ...(data && { data }),
  };
  return JSON.stringify(entry);
}

const logger = {
  error: (category, message, data) => {
    if (shouldLog("error")) console.error(formatLog("error", category, message, data));
  },
  warn: (category, message, data) => {
    if (shouldLog("warn")) console.warn(formatLog("warn", category, message, data));
  },
  info: (category, message, data) => {
    if (shouldLog("info")) console.log(formatLog("info", category, message, data));
  },
  debug: (category, message, data) => {
    if (shouldLog("debug")) console.log(formatLog("debug", category, message, data));
  },
};

module.exports = logger;
