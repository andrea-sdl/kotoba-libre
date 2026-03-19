// The service worker keeps Chrome's dynamic redirect rules in sync with the saved extension settings.
const DEFAULT_SETTINGS = {
    allowedHosts: '',
    callbackPath: '',
    appScheme: 'kotobalibre'
};

const RULE_ID_BASE = 10_000;

function normalizePath(path) {
    const segments = String(path || '')
        .split('/')
        .filter(Boolean);
    return `/${segments.join('/')}`;
}

function escapeForRegex(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function readAllowedHosts(rawHosts) {
    return String(rawHosts || DEFAULT_SETTINGS.allowedHosts)
        .split(',')
        .map((host) => host.trim().toLowerCase())
        .filter(Boolean);
}

function hasUsableSettings(settings) {
    return readAllowedHosts(settings.allowedHosts).length > 0
        && String(settings.callbackPath || '').trim().length > 0;
}

function buildRegexFilter(host, callbackPath) {
    const escapedPath = escapeForRegex(callbackPath);
    const hostPattern = host === '*'
        ? '([^/:?#]+)'
        : escapeForRegex(host);
    return `^https://${hostPattern}${escapedPath}([?#].*)?$`;
}

function buildRegexSubstitution(appScheme, host, callbackPath) {
    if (host === '*') {
        return `${appScheme}://\\1${callbackPath}\\2`;
    }

    return `${appScheme}://${host}${callbackPath}\\1`;
}

function buildDynamicRules(settings) {
    if (!hasUsableSettings(settings)) {
        return [];
    }

    const callbackPath = normalizePath(settings.callbackPath || DEFAULT_SETTINGS.callbackPath);
    const appScheme = String(settings.appScheme || DEFAULT_SETTINGS.appScheme).trim().toLowerCase();
    const allowedHosts = readAllowedHosts(settings.allowedHosts);

    return allowedHosts.map((host, index) => ({
        id: RULE_ID_BASE + index,
        priority: 1,
        action: {
            type: 'redirect',
            redirect: {
                regexSubstitution: buildRegexSubstitution(appScheme, host, callbackPath)
            }
        },
        condition: {
            regexFilter: buildRegexFilter(host, callbackPath),
            resourceTypes: ['main_frame']
        }
    }));
}

async function syncRedirectRules() {
    const settings = await chrome.storage.sync.get(DEFAULT_SETTINGS);
    const existingRules = await chrome.declarativeNetRequest.getDynamicRules();
    const ruleIDsToRemove = existingRules.map((rule) => rule.id);
    const rulesToAdd = buildDynamicRules(settings);

    await chrome.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: ruleIDsToRemove,
        addRules: rulesToAdd
    });
}

chrome.runtime.onInstalled.addListener(() => {
    void syncRedirectRules();
    chrome.storage.sync.get(DEFAULT_SETTINGS).then((settings) => {
        if (!hasUsableSettings(settings)) {
            return chrome.runtime.openOptionsPage();
        }
        return undefined;
    });
});

chrome.runtime.onStartup.addListener(() => {
    void syncRedirectRules();
});

chrome.storage.onChanged.addListener((changes, areaName) => {
    if (areaName !== 'sync') {
        return;
    }

    if (!changes.allowedHosts && !changes.callbackPath && !changes.appScheme) {
        return;
    }

    void syncRedirectRules();
});

chrome.action.onClicked.addListener(() => {
    chrome.runtime.openOptionsPage();
});
