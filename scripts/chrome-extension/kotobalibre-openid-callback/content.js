// The content script is a fallback for already-loaded callback pages; the main redirect path lives in DNR rules.
(function () {
    'use strict';

    const DEFAULT_SETTINGS = {
        allowedHosts: '',
        callbackPath: '',
        appScheme: 'kotobalibre'
    };

    function normalizePath(path) {
        const segments = String(path || '')
            .split('/')
            .filter(Boolean);
        return `/${segments.join('/')}`;
    }

    function readAllowedHosts(rawHosts) {
        return String(rawHosts || DEFAULT_SETTINGS.allowedHosts)
            .split(',')
            .map((host) => host.trim().toLowerCase())
            .filter(Boolean);
    }

    function hostMatches(hostname, allowedHosts) {
        if (!hostname) {
            return false;
        }

        const normalizedHost = hostname.toLowerCase();
        return allowedHosts.includes('*') || allowedHosts.includes(normalizedHost);
    }

    function hasUsableSettings(settings) {
        return readAllowedHosts(settings.allowedHosts).length > 0
            && String(settings.callbackPath || '').trim().length > 0;
    }

    function maybeRedirect(settings) {
        if (!hasUsableSettings(settings)) {
            return;
        }

        const currentURL = new URL(window.location.href);
        const allowedHosts = readAllowedHosts(settings.allowedHosts);
        const callbackPath = normalizePath(settings.callbackPath || DEFAULT_SETTINGS.callbackPath);
        const appScheme = String(settings.appScheme || DEFAULT_SETTINGS.appScheme).trim().toLowerCase();

        if (currentURL.protocol !== 'https:') {
            return;
        }

        if (!hostMatches(currentURL.hostname, allowedHosts)) {
            return;
        }

        if (normalizePath(currentURL.pathname) !== callbackPath) {
            return;
        }

        // Swap only the scheme so the original callback URL stays byte-for-byte intact after the host.
        const targetURL = window.location.href.replace(/^https(?=:)/i, appScheme);
        window.location.replace(targetURL);
    }

    chrome.storage.sync.get(DEFAULT_SETTINGS, maybeRedirect);
})();
