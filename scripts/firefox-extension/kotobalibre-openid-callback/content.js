// The content script is a fallback for already-loaded callback pages; the main redirect path lives in webRequest.
(async function () {
    'use strict';

    const DEFAULT_SETTINGS = {
        allowedHosts: '',
        callbackPath: '/oauth/openid/callback',
        appScheme: 'kotobalibre'
    };

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

    function readAllowedHosts(rawHosts) {
        return String(rawHosts || DEFAULT_SETTINGS.allowedHosts)
            .split(',')
            .map(normalizeAllowedHost)
            .filter(Boolean);
    }

    function authorityMatches(authority, allowedHosts) {
        if (!authority) {
            return false;
        }

        const normalizedAuthority = authority.toLowerCase();
        return allowedHosts.includes('*') || allowedHosts.includes(normalizedAuthority);
    }

    function hasUsableSettings(settings) {
        return readAllowedHosts(settings.allowedHosts).length > 0
            && normalizeCallbackPathValue(settings.callbackPath || DEFAULT_SETTINGS.callbackPath).length > 0;
    }

    function maybeRedirect(settings) {
        if (!hasUsableSettings(settings)) {
            return;
        }

        const currentURL = new URL(window.location.href);
        const allowedHosts = readAllowedHosts(settings.allowedHosts);
        const callbackPath = normalizeCallbackPathValue(settings.callbackPath || DEFAULT_SETTINGS.callbackPath);
        const appScheme = String(settings.appScheme || DEFAULT_SETTINGS.appScheme).trim().toLowerCase();
        const currentAuthority = currentURL.host.toLowerCase();

        if (currentURL.protocol !== 'https:') {
            return;
        }

        // Compare against the full authority so callbacks on host:port still redirect.
        if (!authorityMatches(currentAuthority, allowedHosts)) {
            return;
        }

        if (normalizePath(currentURL.pathname) !== callbackPath) {
            return;
        }

        // Swap only the scheme so the original callback URL stays byte-for-byte intact after the host.
        const targetURL = window.location.href.replace(/^https(?=:)/i, appScheme);
        window.location.replace(targetURL);
    }

    maybeRedirect(await browser.storage.sync.get(DEFAULT_SETTINGS));
})();
