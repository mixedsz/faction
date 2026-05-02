// Color Manager - Handles dynamic UI color changes
(function() {
    'use strict';

    // Function to convert hex color to RGB values
    function hexToRgb(hex) {
        // Remove # if present
        hex = hex.replace('#', '');
        
        // Parse hex values
        const r = parseInt(hex.substring(0, 2), 16);
        const g = parseInt(hex.substring(2, 4), 16);
        const b = parseInt(hex.substring(4, 6), 16);
        
        return { r, g, b };
    }

    // Function to darken a color (for secondary color)
    function darkenColor(hex, percent = 15) {
        const rgb = hexToRgb(hex);
        
        const r = Math.max(0, Math.floor(rgb.r * (1 - percent / 100)));
        const g = Math.max(0, Math.floor(rgb.g * (1 - percent / 100)));
        const b = Math.max(0, Math.floor(rgb.b * (1 - percent / 100)));
        
        return '#' + [r, g, b].map(x => {
            const hex = x.toString(16);
            return hex.length === 1 ? '0' + hex : hex;
        }).join('');
    }

    // Function to apply UI color
    window.applyUIColor = function(hexColor) {
        if (!hexColor || typeof hexColor !== 'string') {
            console.warn('Invalid color provided, using default');
            hexColor = '#10b981';
        }

        // Ensure hex color starts with #
        if (!hexColor.startsWith('#')) {
            hexColor = '#' + hexColor;
        }

        // Validate hex color format
        if (!/^#[0-9A-F]{6}$/i.test(hexColor)) {
            console.warn('Invalid hex color format, using default');
            hexColor = '#10b981';
        }

        const rgb = hexToRgb(hexColor);
        const secondaryColor = darkenColor(hexColor, 15);

        // Set CSS variables
        const root = document.documentElement;
        root.style.setProperty('--ui-color-primary', hexColor);
        root.style.setProperty('--ui-color-secondary', secondaryColor);
        root.style.setProperty('--ui-color-rgb', `${rgb.r}, ${rgb.g}, ${rgb.b}`);

        //console.log('UI Color applied:', hexColor);
    };

    // Initialize with default color
    applyUIColor('#10b981');
})();

