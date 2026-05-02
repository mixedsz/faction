// Color Handler - Intercepts NUI messages to apply UI colors
(function() {
    'use strict';

    // Store the original addEventListener
    const originalAddEventListener = window.addEventListener;

    // Override addEventListener to intercept 'message' events
    window.addEventListener = function(type, listener, options) {
        if (type === 'message') {
            // Wrap the listener to intercept and process messages
            const wrappedListener = function(event) {
                const data = event.data;
                
                // Check if the message contains uiColor
                if (data && data.uiColor) {
                    // Apply the UI color before the original listener processes the message
                    if (window.applyUIColor) {
                        window.applyUIColor(data.uiColor);
                    }
                }
                
                // Call the original listener
                return listener.call(this, event);
            };
            
            // Call the original addEventListener with the wrapped listener
            return originalAddEventListener.call(this, type, wrappedListener, options);
        } else {
            // For non-message events, use the original addEventListener
            return originalAddEventListener.call(this, type, listener, options);
        }
    };
})();

