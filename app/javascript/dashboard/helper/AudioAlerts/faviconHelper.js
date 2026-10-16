let titleInterval = null;
let originalTitle = document.title || 'Chatwoot';

export const startTitleFlashing = () => {
  if (document.visibilityState === 'visible') return;
  if (titleInterval) return;

  originalTitle = document.title.replace(/【🔔 新消息待处理！】\s*/g, '') || 'Chatwoot';
  let isFlashing = false;

  titleInterval = setInterval(() => {
    if (document.visibilityState === 'visible') {
      stopTitleFlashing();
      return;
    }
    document.title = isFlashing ? '【🔔 新消息待处理！】' : originalTitle;
    isFlashing = !isFlashing;
  }, 900);
};

export const stopTitleFlashing = () => {
  if (titleInterval) {
    clearInterval(titleInterval);
    titleInterval = null;
  }
  if (originalTitle) {
    document.title = originalTitle;
  }
};

export const showBadgeOnFavicon = () => {
  const favicons = document.querySelectorAll('.favicon');

  favicons.forEach(favicon => {
    const newFileName = `/favicon-badge-${favicon.sizes[[0]]}.png`;
    favicon.href = newFileName;
  });

  startTitleFlashing();
};

export const initFaviconSwitcher = () => {
  const favicons = document.querySelectorAll('.favicon');

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      favicons.forEach(favicon => {
        const oldFileName = `/favicon-${favicon.sizes[[0]]}.png`;
        favicon.href = oldFileName;
      });
      stopTitleFlashing();
    }
  });
};
