// The service worker keeps Chrome's dynamic redirect rules in sync with the saved extension settings.
const DEFAULT_SETTINGS = {
    allowedHosts: '',
    callbackPath: '/oauth/openid/callback',
    appScheme: 'kotobalibre'
};

const RULE_ID_BASE = 10_000;

function normalizePath(path) {
    const segments = String(path || '')
        .split('/')
        .filter(Boolean);
    return `/${segments.join('/')}`;
}

function normalizeAllowedHost(host) {
    const trimmedHost = String(host || '').trim().toLowerCase();
    if (!trimmedHost) {
        return '';
    }

    if (trimmedHost === '*') {
        return '*';
    }

    const candidate = trimmedHost.includes('://')
        ? trimmedHost
        : `https://${trimmedHost}`;

    try {
        const url = new URL(candidate);
        if (url.protocol === 'https:' && url.host) {
            return url.host.toLowerCase();
        }
    } catch {
    }

    return trimmedHost
        .replace(/^https:\/\//, '')
        .split(/[/?#]/, 1)[0];
}

function normalizeCallbackPathValue(path) {
    const trimmedPath = String(path || '').trim();
    if (!trimmedPath) {
        return '';
    }

    if (trimmedPath.includes('://')) {
        try {
            const url = new URL(trimmedPath);
            if (url.protocol === 'https:') {
                return normalizePath(url.pathname);
            }
        } catch {
        }
    }

    const firstSlashIndex = trimmedPath.indexOf('/');
    if (firstSlashIndex > 0) {
        const authorityCandidate = trimmedPath.slice(0, firstSlashIndex).toLowerCase();
        if (authorityCandidate.includes('.') || authorityCandidate.includes(':') || authorityCandidate === 'localhost') {
            return normalizePath(trimmedPath.slice(firstSlashIndex));
        }
    }

    return normalizePath(trimmedPath);
}

function escapeForRegex(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function readAllowedHosts(rawHosts) {
    return String(rawHosts || DEFAULT_SETTINGS.allowedHosts)
        .split(',')
        .map(normalizeAllowedHost)
        .filter(Boolean);
}

function hasUsableSettings(settings) {
    return readAllowedHosts(settings.allowedHosts).length > 0
        && normalizeCallbackPathValue(settings.callbackPath || DEFAULT_SETTINGS.callbackPath).length > 0;
}

function buildRegexFilter(host, callbackPath) {
    const escapedPath = escapeForRegex(callbackPath);
    const hostPattern = host === '*'
        // Capture the full HTTPS authority so optional ports survive the redirect.
        ? '([^/?#]+)'
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

    const callbackPath = normalizeCallbackPathValue(settings.callbackPath || DEFAULT_SETTINGS.callbackPath);
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
