(() => {
  const notice = document.getElementById('notice');
  const label = document.getElementById('notice-text');
  let timer;
  window.addEventListener('message', ({data}) => {
    if (data?.type !== 'bd:notice' || typeof data.message !== 'string') return;
    label.textContent = data.message.slice(0, 220);
    notice.hidden = false;
    clearTimeout(timer);
    timer = setTimeout(() => { notice.hidden = true; }, 4200);
  });
})();
