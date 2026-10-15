const fs = require('fs');
const path = require('path');
const runtime = require('../runtime');

function getLogFilePath() {
  return path.join(runtime.getAppRoot(), 'error.log');
}
const COMPANY_HEADER =
  'Maleesha Sanjana - Jazz Business Solution (Pvt.) Ltd.';
const DAY_SEPARATOR = '='.repeat(80);

let lastLoggedDateKey = null;
let consoleHookInstalled = false;

function getDateKey(date = new Date()) {
  try {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Colombo',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const lookup = Object.fromEntries(parts.map((p) => [p.type, p.value]));
    if (lookup.year && lookup.month && lookup.day) {
      return `${lookup.year}-${lookup.month}-${lookup.day}`;
    }
  } catch (_) {}

  const d = new Date(date);
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function formatDisplayDate(dateKey) {
  let year, month, day;
  if (typeof dateKey === 'string' && dateKey.includes('-')) {
    const parts = dateKey.split('-').map(Number);
    if (parts.length === 3 && parts[0] > 1000) {
      [year, month, day] = parts;
    }
  } else if (typeof dateKey === 'string' && dateKey.includes('/')) {
    const parts = dateKey.split('/').map(Number);
    if (parts.length === 3) {
      if (parts[2] > 1000) {
        year = parts[2];
        month = parts[0];
        day = parts[1];
      } else if (parts[0] > 1000) {
        year = parts[0];
        month = parts[1];
        day = parts[2];
      }
    }
  }

  let date;
  if (year && month && day) {
    date = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
  } else {
    date = new Date(dateKey);
  }

  if (isNaN(date.getTime())) {
    return dateKey;
  }

  return date.toLocaleDateString('en-GB', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'Asia/Colombo',
  });
}

function formatTimestamp(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
    timeZone: 'Asia/Colombo',
  }).formatToParts(date);

  const lookup = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${lookup.year}-${lookup.month}-${lookup.day} ${lookup.hour}:${lookup.minute}:${lookup.second}`;
}

function fileHasTodayHeader(todayKey) {
  try {
    const logFile = getLogFilePath();
    if (!fs.existsSync(logFile)) {
      return false;
    }
    const content = fs.readFileSync(logFile, 'utf8');
    return content.includes(`DATE: ${todayKey}`);
  } catch {
    return false;
  }
}

function writeDayHeader(dateKey) {
  const block = [
    '',
    DAY_SEPARATOR,
    `DATE: ${dateKey} (${formatDisplayDate(dateKey)})`,
    COMPANY_HEADER,
    DAY_SEPARATOR,
    '',
  ].join('\n');

  fs.appendFileSync(getLogFilePath(), block, 'utf8');
}

function ensureDayHeader() {
  const todayKey = getDateKey();
  if (lastLoggedDateKey === todayKey) {
    return;
  }

  if (!fileHasTodayHeader(todayKey)) {
    writeDayHeader(todayKey);
  }

  lastLoggedDateKey = todayKey;
}

function formatError(error) {
  if (!error) {
    return '';
  }

  if (error instanceof Error) {
    return [error.message, error.stack].filter(Boolean).join('\n');
  }

  if (typeof error === 'object') {
    try {
      return JSON.stringify(error, null, 2);
    } catch {
      return String(error);
    }
  }

  return String(error);
}

function logError(message, error = null, meta = null) {
  try {
    ensureDayHeader();

    let entry = `[${formatTimestamp()}] ${message}`;
    const errorText = formatError(error);
    if (errorText) {
      entry += `\n${errorText}`;
    }
    if (meta) {
      try {
        entry += `\nMeta: ${JSON.stringify(meta)}`;
      } catch {
        // Ignore meta serialization issues.
      }
    }
    entry += '\n\n';

    fs.appendFileSync(getLogFilePath(), entry, 'utf8');
  } catch (logErr) {
    process.stderr.write(`Failed to write error.log: ${logErr.message}\n`);
  }
}

function installConsoleErrorCapture() {
  if (consoleHookInstalled) {
    return;
  }
  consoleHookInstalled = true;

  const originalError = console.error.bind(console);
  console.error = (...args) => {
    originalError(...args);

    const message = args
      .map((arg) => {
        if (arg instanceof Error) {
          return arg.stack || arg.message;
        }
        if (typeof arg === 'object') {
          try {
            return JSON.stringify(arg);
          } catch {
            return String(arg);
          }
        }
        return String(arg);
      })
      .join(' ');

    logError(message);
  };
}

function installProcessHandlers() {
  process.on('uncaughtException', (err) => {
    logError('Uncaught Exception', err);
  });

  process.on('unhandledRejection', (reason) => {
    logError(
      'Unhandled Promise Rejection',
      reason instanceof Error ? reason : new Error(String(reason)),
    );
  });
}

function initialize() {
  installConsoleErrorCapture();
  installProcessHandlers();
  ensureDayHeader();
  console.log(`📝 Error log file: ${getLogFilePath()}`);
}

module.exports = {
  initialize,
  logError,
  getLogFilePath,
  COMPANY_HEADER,
};
