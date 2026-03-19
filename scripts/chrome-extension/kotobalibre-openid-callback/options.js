// The options page keeps the extension configurable without requiring code edits or reload-time prompts.
(function () {
    'use strict';

    const DEFAULT_SETTINGS = {
        allowedHosts: '',
        callbackPath: '',
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

    function applySettings(settings) {
        allowedHostsInput.value = settings.allowedHosts;
        callbackPathInput.value = settings.callbackPath;
    }

    function loadSettings() {
        chrome.storage.sync.get(DEFAULT_SETTINGS, applySettings);
    }

    form.addEventListener('submit', (event) => {
        event.preventDefault();

        chrome.storage.sync.set({
            allowedHosts: allowedHostsInput.value.trim() || DEFAULT_SETTINGS.allowedHosts,
            callbackPath: callbackPathInput.value.trim() || DEFAULT_SETTINGS.callbackPath,
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
