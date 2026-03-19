// The options page keeps the extension configurable without requiring code edits or reload-time prompts.
(function () {
    'use strict';

    const DEFAULT_SETTINGS = {
        allowedHosts: '',
        callbackPath: '/oauth/openid/callback',
        appScheme: 'kotobalibre'
    };

    const form = document.getElementById('settings-form');
    const allowedHostsInput = document.getElementById('allowed-hosts');
    const callbackPathInput = document.getElementById('callback-path');
    const resetButton = document.getElementById('reset-button');
    const status = document.getElementById('status');

    function setStatus(message) {
        status.textContent = message;
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

    function normalizeAllowedHosts(rawHosts) {
        return String(rawHosts || DEFAULT_SETTINGS.allowedHosts)
            .split(',')
            .map(normalizeAllowedHost)
            .filter(Boolean)
            .join(', ');
    }

    function normalizePath(path) {
        const segments = String(path || '')
            .split('/')
            .filter(Boolean);
        return `/${segments.join('/')}`;
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

    function applySettings(settings) {
        allowedHostsInput.value = normalizeAllowedHosts(settings.allowedHosts);
        callbackPathInput.value = normalizeCallbackPathValue(settings.callbackPath);
    }

    function loadSettings() {
        chrome.storage.sync.get(DEFAULT_SETTINGS, applySettings);
    }

    form.addEventListener('submit', (event) => {
        event.preventDefault();

        chrome.storage.sync.set({
            allowedHosts: normalizeAllowedHosts(allowedHostsInput.value) || DEFAULT_SETTINGS.allowedHosts,
            callbackPath: normalizeCallbackPathValue(callbackPathInput.value) || DEFAULT_SETTINGS.callbackPath,
            appScheme: DEFAULT_SETTINGS.appScheme
        }, () => {
            setStatus('Settings saved.');
            window.setTimeout(() => setStatus(''), 1800);
        });
    });

    resetButton.addEventListener('click', () => {
        chrome.storage.sync.set(DEFAULT_SETTINGS, () => {
            applySettings(DEFAULT_SETTINGS);
            setStatus('Settings cleared. The extension stays inactive until you save a config.');
            window.setTimeout(() => setStatus(''), 1800);
        });
    });

    loadSettings();
})();
