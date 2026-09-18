// Modals, prompts and the toast line. Nothing here knows what a topology is.

const host = () => document.getElementById('modal-host');

/// Open a modal. `build` fills the body and gets a `close` it can call.
///
/// Escape closes, and so does a click on the backdrop: a dialog a keyboard user
/// cannot dismiss is the one that ends up dismissed with the browser's back
/// button, which loses the page.
export function modal(build) {
  const h = host();
  h.hidden = false;
  h.textContent = '';
  const box = document.createElement('div');
  box.className = 'modal';
  h.appendChild(box);

  const close = () => {
    h.hidden = true;
    h.textContent = '';
    document.removeEventListener('keydown', onKey, true);
  };
  const onKey = (ev) => {
    if (ev.key === 'Escape') {
      ev.stopPropagation();
      close();
    }
  };
  document.addEventListener('keydown', onKey, true);
  h.onclick = (ev) => {
    if (ev.target === h) close();
  };

  build(box, close);
  const first = box.querySelector('input, select, textarea, button');
  if (first) first.focus();
  return close;
}

/// One line of text, with a confirm. Returns the string, or null.
export function ask(title, { label = '', value = '', ok = 'OK', note = '' } = {}) {
  return new Promise((resolve) => {
    modal((box, close) => {
      box.appendChild(el('h2', title));
      if (note) box.appendChild(el('p', note));
      const field = document.createElement('div');
      field.className = 'field';
      if (label) field.appendChild(el('label', label));
      const input = document.createElement('input');
      input.type = 'text';
      input.value = value;
      field.appendChild(input);
      box.appendChild(field);

      const actions = document.createElement('div');
      actions.className = 'actions';
      const cancel = button('Cancel', () => {
        close();
        resolve(null);
      });
      const accept = button(ok, () => {
        const v = input.value.trim();
        close();
        resolve(v || null);
      });
      accept.className = 'primary';
      actions.append(cancel, accept);
      box.appendChild(actions);

      input.addEventListener('keydown', (ev) => {
        ev.stopPropagation();
        if (ev.key === 'Enter') accept.click();
      });
      setTimeout(() => input.select(), 0);
    });
  });
}

/// A yes or no question. The dangerous answer is never the default.
export function confirmAsk(title, body, { ok = 'Yes', danger = false } = {}) {
  return new Promise((resolve) => {
    modal((box, close) => {
      box.appendChild(el('h2', title));
      box.appendChild(el('p', body));
      const actions = document.createElement('div');
      actions.className = 'actions';
      const no = button('Cancel', () => {
        close();
        resolve(false);
      });
      const yes = button(ok, () => {
        close();
        resolve(true);
      });
      yes.className = danger ? 'danger' : 'primary';
      actions.append(no, yes);
      box.appendChild(actions);
      setTimeout(() => no.focus(), 0);
    });
  });
}

let toastTimer = null;

export function toast(message, bad = false) {
  const t = document.getElementById('toast');
  t.textContent = message;
  t.className = `toast${bad ? ' bad' : ''}`;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    t.hidden = true;
  }, bad ? 7000 : 3500);
}

export function el(tag, text, cls) {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  if (cls) e.className = cls;
  return e;
}

export function button(label, onClick, cls) {
  const e = document.createElement('button');
  e.textContent = label;
  if (cls) e.className = cls;
  e.addEventListener('click', onClick);
  return e;
}

export function pre(text) {
  const e = document.createElement('pre');
  e.className = 'code';
  e.textContent = text;
  return e;
}

/// Seconds since the epoch, as something a person reads.
export function when(secs) {
  if (!secs) return 'never';
  const d = new Date(secs * 1000);
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  if (mins < 60 * 24) return `${Math.round(mins / 60)} h ago`;
  return d.toLocaleDateString();
}
