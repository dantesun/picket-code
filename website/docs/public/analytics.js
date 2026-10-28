// Picket Code 第一方访问统计打点（同域 /api/event，Firefox 不拦截）
(function () {
  function send() {
    try {
      fetch('/api/event', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          path: location.pathname,
          referer: document.referrer.slice(0, 512),
        }),
        keepalive: true,
      })
    } catch (e) {
      /* 打点失败静默，不影响页面 */
    }
  }
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    send()
  } else {
    window.addEventListener('load', send)
  }
})()
