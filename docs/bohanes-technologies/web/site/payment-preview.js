(() => {
  const root = document.querySelector('[data-payment-preview]');
  if (!root) return;

  const detail = root.querySelector('[data-payment-detail]');
  const buttons = [...root.querySelectorAll('[data-payment-method]')];
  const apple = root.querySelector('[data-payment-method="apple"]');
  const google = root.querySelector('[data-payment-method="google"]');
  const ua = navigator.userAgent || '';
  const isApple = /iPhone|iPad|iPod|Macintosh/.test(ua);
  const isAndroid = /Android/.test(ua);

  if (isApple) apple?.classList.add('is-recommended');
  if (isAndroid) google?.classList.add('is-recommended');

  const views = {
    apple: `
      <div class="payment-detail-copy">
        <span class="payment-detail-badge">Nejrychlejší</span>
        <b>Apple Pay</b>
        <p>Bez opisování karty. Uživatel jen potvrdí částku 299 Kč pomocí Face ID, Touch ID nebo kódu zařízení.</p>
      </div>`,
    google: `
      <div class="payment-detail-copy">
        <span class="payment-detail-badge">Nejrychlejší</span>
        <b>Google Pay</b>
        <p>Bez opisování karty. Uživatel vybere uloženou platební metodu a potvrdí částku 299 Kč.</p>
      </div>`,
    qr: `
      <div class="payment-detail-qr" aria-hidden="true"><span></span><span></span><span></span><span></span><span></span><span></span><span></span><span></span><span></span></div>
      <div class="payment-detail-copy">
        <span class="payment-detail-badge">Bez poplatku bráně</span>
        <b>QR platba · 299 Kč</b>
        <p>QR bude obsahovat účet, přesnou částku i variabilní symbol. Klient nic nepřepisuje.</p>
      </div>`,
    bank: `
      <div class="payment-detail-copy payment-bank-copy">
        <span class="payment-detail-badge">Bez karty</span>
        <b>Zaplatit přes banku</b>
        <p>Klient zvolí svoji banku, přihlásí se a už jen potvrdí připravenou platbu.</p>
        <div class="payment-bank-list" aria-label="Příklady bank"><span>Fio</span><span>KB</span><span>MONETA</span><span>Raiffeisenbank</span><span>ČSOB</span><span>další</span></div>
      </div>`,
    card: `
      <div class="payment-detail-copy">
        <span class="payment-detail-badge">Záložní možnost</span>
        <b>Platební karta</b>
        <p>Klasické zadání karty zůstane dostupné pro klienta, který nechce použít peněženku, QR ani svoji banku.</p>
      </div>`,
  };

  function select(method) {
    buttons.forEach(button => button.classList.toggle('is-selected', button.dataset.paymentMethod === method));
    detail.innerHTML = views[method] || '';
  }

  buttons.forEach(button => button.addEventListener('click', () => select(button.dataset.paymentMethod)));
  select(isAndroid ? 'google' : isApple ? 'apple' : 'qr');
})();
