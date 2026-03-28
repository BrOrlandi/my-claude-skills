/**
 * spotlight.js — Inject a spotlight overlay highlighting a specific element on the page.
 *
 * Usage (via browser_evaluate):
 *   Read this file, then wrap in: () => { <file contents>; return spotlight({...}); }
 *
 * Parameters:
 *   selector        (string)  CSS selector for the target element
 *   annotationText  (string)  Explanation text for the annotation box
 *   margin          (number)  Pixels of padding around the spotlight cutout (default: 16)
 *   borderRadius    (number)  Corner radius of the cutout ring in px (default: 12)
 *   overlayOpacity  (number)  Darkness of the overlay, 0-1 (default: 0.6)
 *   position        (string)  Annotation placement: "auto"|"top"|"bottom"|"left"|"right" (default: "auto")
 */

function spotlight(config) {
  const {
    selector,
    annotationText = '',
    margin = 16,
    borderRadius = 12,
    overlayOpacity = 0.6,
    position = 'auto',
  } = config;

  // Clean up any existing spotlight
  document.querySelectorAll('[data-spotlight]').forEach(el => el.remove());

  // Find target element
  const el = document.querySelector(selector);
  if (!el) {
    return { error: 'Element not found', selector };
  }

  // Check for multiple matches
  const allMatches = document.querySelectorAll(selector);
  const multipleWarning = allMatches.length > 1
    ? `Warning: selector matched ${allMatches.length} elements, using first match`
    : null;

  // Scroll into view if needed
  const viewportHeight = window.innerHeight;
  const viewportWidth = window.innerWidth;
  const initialRect = el.getBoundingClientRect();
  if (
    initialRect.bottom < 0 ||
    initialRect.top > viewportHeight ||
    initialRect.right < 0 ||
    initialRect.left > viewportWidth
  ) {
    el.scrollIntoView({ block: 'center', behavior: 'instant' });
    // Force layout flush after scroll so getBoundingClientRect returns updated position
    void el.offsetHeight;
  }

  // Measure after potential scroll
  const rect = el.getBoundingClientRect();

  // Cutout coordinates (with margin)
  const cutTop = Math.max(0, rect.top - margin);
  const cutLeft = Math.max(0, rect.left - margin);
  const cutBottom = Math.min(viewportHeight, rect.bottom + margin);
  const cutRight = Math.min(viewportWidth, rect.right + margin);
  const cutWidth = cutRight - cutLeft;
  const cutHeight = cutBottom - cutTop;

  // --- Root container ---
  const root = document.createElement('div');
  root.setAttribute('data-spotlight', 'root');
  Object.assign(root.style, {
    position: 'fixed',
    inset: '0',
    zIndex: '99998',
    pointerEvents: 'none',
  });

  // --- Dark overlay using four bands around the cutout ---
  // This avoids clip-path compatibility issues and creates a true transparent cutout.
  const overlayColor = `rgba(0, 0, 0, ${overlayOpacity})`;
  const bands = [
    // Top band: full width, from top of viewport to top of cutout
    { top: 0, left: 0, width: viewportWidth, height: cutTop },
    // Bottom band: full width, from bottom of cutout to bottom of viewport
    { top: cutBottom, left: 0, width: viewportWidth, height: viewportHeight - cutBottom },
    // Left band: between top and bottom bands, from left edge to cutout left
    { top: cutTop, left: 0, width: cutLeft, height: cutHeight },
    // Right band: between top and bottom bands, from cutout right to right edge
    { top: cutTop, left: cutRight, width: viewportWidth - cutRight, height: cutHeight },
  ];

  bands.forEach((band, i) => {
    const bandEl = document.createElement('div');
    bandEl.setAttribute('data-spotlight', `overlay-${i}`);
    Object.assign(bandEl.style, {
      position: 'absolute',
      top: `${band.top}px`,
      left: `${band.left}px`,
      width: `${band.width}px`,
      height: `${band.height}px`,
      background: overlayColor,
    });
    root.appendChild(bandEl);
  });

  // --- Spotlight ring (rounded border) ---
  const ring = document.createElement('div');
  ring.setAttribute('data-spotlight', 'ring');
  Object.assign(ring.style, {
    position: 'absolute',
    top: `${cutTop}px`,
    left: `${cutLeft}px`,
    width: `${cutWidth}px`,
    height: `${cutHeight}px`,
    borderRadius: `${borderRadius}px`,
    boxShadow: '0 0 0 3px rgba(255, 255, 255, 0.9), 0 0 20px 4px rgba(255, 255, 255, 0.15)',
    pointerEvents: 'none',
  });
  root.appendChild(ring);

  // --- Annotation box ---
  let resolvedPlacement = null;
  if (annotationText) {
    const annotation = document.createElement('div');
    annotation.setAttribute('data-spotlight', 'annotation');

    // Determine best position for annotation
    const spaceTop = cutTop;
    const spaceBottom = viewportHeight - cutBottom;
    const spaceLeft = cutLeft;
    const spaceRight = viewportWidth - cutRight;

    resolvedPlacement = position;
    if (resolvedPlacement === 'auto') {
      const spaces = { top: spaceTop, bottom: spaceBottom, left: spaceLeft, right: spaceRight };
      resolvedPlacement = Object.entries(spaces).sort((a, b) => b[1] - a[1])[0][0];
    }

    const annotationMaxWidth = 400;
    const annotationGap = 16; // gap between ring and annotation
    const arrowSize = 10;

    // Base annotation styles
    Object.assign(annotation.style, {
      position: 'absolute',
      maxWidth: `${annotationMaxWidth}px`,
      padding: '12px 16px',
      background: 'rgba(20, 20, 20, 0.92)',
      color: '#ffffff',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
      fontSize: '14px',
      lineHeight: '1.5',
      borderRadius: '10px',
      border: '1px solid rgba(255, 255, 255, 0.15)',
      boxShadow: '0 4px 24px rgba(0, 0, 0, 0.4)',
      pointerEvents: 'none',
      boxSizing: 'border-box',
    });

    // Create arrow element
    const arrow = document.createElement('div');
    arrow.setAttribute('data-spotlight', 'arrow');
    Object.assign(arrow.style, {
      position: 'absolute',
      width: '0',
      height: '0',
      borderStyle: 'solid',
    });

    // Position annotation and arrow based on placement
    const cutCenterX = cutLeft + cutWidth / 2;
    const cutCenterY = cutTop + cutHeight / 2;

    switch (resolvedPlacement) {
      case 'bottom':
        Object.assign(annotation.style, {
          top: `${cutBottom + annotationGap + arrowSize}px`,
          left: `${Math.max(8, Math.min(cutCenterX - annotationMaxWidth / 2, viewportWidth - annotationMaxWidth - 8))}px`,
        });
        Object.assign(arrow.style, {
          top: `-${arrowSize}px`,
          left: '50%',
          marginLeft: `-${arrowSize}px`,
          borderWidth: `0 ${arrowSize}px ${arrowSize}px ${arrowSize}px`,
          borderColor: `transparent transparent rgba(20, 20, 20, 0.92) transparent`,
        });
        break;

      case 'top':
        Object.assign(annotation.style, {
          bottom: `${viewportHeight - cutTop + annotationGap + arrowSize}px`,
          left: `${Math.max(8, Math.min(cutCenterX - annotationMaxWidth / 2, viewportWidth - annotationMaxWidth - 8))}px`,
        });
        Object.assign(arrow.style, {
          bottom: `-${arrowSize}px`,
          left: '50%',
          marginLeft: `-${arrowSize}px`,
          borderWidth: `${arrowSize}px ${arrowSize}px 0 ${arrowSize}px`,
          borderColor: `rgba(20, 20, 20, 0.92) transparent transparent transparent`,
        });
        break;

      case 'right':
        Object.assign(annotation.style, {
          top: `${Math.max(8, Math.min(cutCenterY - 30, viewportHeight - 80))}px`,
          left: `${cutRight + annotationGap + arrowSize}px`,
        });
        Object.assign(arrow.style, {
          top: '16px',
          left: `-${arrowSize}px`,
          borderWidth: `${arrowSize}px ${arrowSize}px ${arrowSize}px 0`,
          borderColor: `transparent rgba(20, 20, 20, 0.92) transparent transparent`,
        });
        break;

      case 'left':
        Object.assign(annotation.style, {
          top: `${Math.max(8, Math.min(cutCenterY - 30, viewportHeight - 80))}px`,
          right: `${viewportWidth - cutLeft + annotationGap + arrowSize}px`,
        });
        Object.assign(arrow.style, {
          top: '16px',
          right: `-${arrowSize}px`,
          borderWidth: `${arrowSize}px 0 ${arrowSize}px ${arrowSize}px`,
          borderColor: `transparent transparent transparent rgba(20, 20, 20, 0.92)`,
        });
        break;
    }

    annotation.appendChild(arrow);

    // Annotation text content
    const textEl = document.createElement('div');
    textEl.setAttribute('data-spotlight', 'text');
    textEl.textContent = annotationText;
    annotation.appendChild(textEl);

    root.appendChild(annotation);
  }

  // Inject into page
  document.body.appendChild(root);

  const result = {
    success: true,
    rect: { top: rect.top, left: rect.left, width: rect.width, height: rect.height },
    cutout: { top: cutTop, left: cutLeft, width: cutWidth, height: cutHeight },
    placement: resolvedPlacement,
  };

  if (multipleWarning) {
    result.warning = multipleWarning;
  }

  return result;
}
