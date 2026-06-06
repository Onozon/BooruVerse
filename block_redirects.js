// Блокировщик редиректов для kemono.cr
// Этот скрипт можно использовать как расширение браузера или внедрить в Selenium

(function() {
    'use strict';

    console.log('🚫 Kemono Redirect Blocker activated');

    // Блокируемые домены
    const blockedDomains = [
        'nachdiewelt.click',
        'quantum',
        'survey',
        'tsyndicate.com',
        'go.tscprts.com',
        'stripchat.com',
        'chaturbate.com',
        'myfreecams.com',
        'bonga',
        'camsoda',
        'camgirl',
        'adultfriendfinder',
        'pornhub',
        'xvideos',
        'xhamster',
        'youporn'
    ];

    // Функция проверки URL
    function isBlockedUrl(url) {
        if (!url) return false;

        try {
            const urlObj = new URL(url);
            const hostname = urlObj.hostname.toLowerCase();

            return blockedDomains.some(domain => hostname.includes(domain));
        } catch (e) {
            // Если URL некорректный, проверяем по строке
            return blockedDomains.some(domain => url.toLowerCase().includes(domain));
        }
    }

    // Перехват XMLHttpRequest
    const originalXHR = window.XMLHttpRequest;
    window.XMLHttpRequest = function() {
        const xhr = new originalXHR();
        const originalOpen = xhr.open;

        xhr.open = function(method, url, ...args) {
            if (isBlockedUrl(url)) {
                console.log('🚫 Blocked XMLHttpRequest:', url);
                return;
            }
            return originalOpen.call(this, method, url, ...args);
        };

        return xhr;
    };

    // Перехват fetch
    const originalFetch = window.fetch;
    window.fetch = function(url, options) {
        if (isBlockedUrl(url)) {
            console.log('🚫 Blocked fetch:', url);
            return Promise.reject(new Error('Blocked URL'));
        }
        return originalFetch.call(this, url, options);
    };

    // Перехват создания iframe
    const originalCreateElement = document.createElement;
    document.createElement = function(tagName) {
        const element = originalCreateElement.call(this, tagName);

        if (tagName.toLowerCase() === 'iframe') {
            const originalSetAttribute = element.setAttribute;
            element.setAttribute = function(name, value) {
                if (name === 'src' && isBlockedUrl(value)) {
                    console.log('🚫 Blocked iframe src:', value);
                    return;
                }
                return originalSetAttribute.call(this, name, value);
            };
        }

        return element;
    };

    // Перехват meta refresh
    const metaTags = document.getElementsByTagName('meta');
    for (let meta of metaTags) {
        if (meta.getAttribute('http-equiv') === 'refresh') {
            const content = meta.getAttribute('content');
            if (content && content.includes('url=')) {
                const url = content.split('url=')[1].split(';')[0];
                if (isBlockedUrl(url)) {
                    console.log('🚫 Blocked meta refresh:', url);
                    meta.remove();
                }
            }
        }
    }

    // Наблюдатель за новыми meta тегами
    const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
                if (node.tagName === 'META' &&
                    node.getAttribute('http-equiv') === 'refresh') {
                    const content = node.getAttribute('content');
                    if (content && content.includes('url=')) {
                        const url = content.split('url=')[1].split(';')[0];
                        if (isBlockedUrl(url)) {
                            console.log('🚫 Blocked dynamic meta refresh:', url);
                            node.remove();
                        }
                    }
                }
            });
        });
    });

    observer.observe(document, {
        childList: true,
        subtree: true
    });

    // Перехват window.location.assign
    const originalAssign = window.location.assign;
    window.location.assign = function(url) {
        if (isBlockedUrl(url)) {
            console.log('🚫 Blocked location.assign:', url);
            return;
        }
        return originalAssign.call(this, url);
    };

    // Перехват window.location.replace
    const originalReplace = window.location.replace;
    window.location.replace = function(url) {
        if (isBlockedUrl(url)) {
            console.log('🚫 Blocked location.replace:', url);
            return;
        }
        return originalReplace.call(this, url);
    };

    // Перехват window.location.href
    let originalHref = window.location.href;
    Object.defineProperty(window.location, 'href', {
        get: function() {
            return originalHref;
        },
        set: function(value) {
            if (isBlockedUrl(value)) {
                console.log('🚫 Blocked location.href redirect:', value);
                return;
            }
            originalHref = value;
        }
    });

    console.log('✅ Kemono Redirect Blocker ready');
})();
