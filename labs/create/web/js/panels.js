// The findings dock and the footprint meter: the two things that are true about
// a topology whether or not anyone asked.
//
// A finding carries the id of the object it is about rather than only a
// sentence, which is what lets clicking one select the node or the link it
// names. That is the whole reason the API returns a subject and not a string.

import { el } from './ui.js';

export class Findings {
  constructor(root, editor, onSelect) {
    this.root = root;
    this.ed = editor;
    this.onSelect = onSelect;
  }

  render() {
    const r = this.root;
    r.textContent = '';
    const list = this.ed.findings || [];
    if (!list.length) {
      r.appendChild(el('div', 'No findings.', 'empty'));
      return;
    }
    // Errors first, and errors are what blocks an emit. A warning is a thing
    // worth knowing: two DHCP servers in one broadcast domain is a mistake in
    // most labs and the premise of one of them.
    const sorted = [...list].sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'error' ? -1 : 1));
    for (const f of sorted) {
      const row = document.createElement('div');
      row.className = `finding ${f.severity}`;
      row.appendChild(el('span', f.severity === 'error' ? 'error' : 'warn', 'sev'));
      row.appendChild(el('span', f.message));
      row.appendChild(el('span', f.kind, 'kind'));
      if (f.subject?.id) {
        row.title = 'Select what this is about';
        row.onclick = () => this.onSelect(f.subject);
      } else {
        row.style.cursor = 'default';
      }
      r.appendChild(row);
    }
  }
}

export class FootprintMeter {
  constructor(root, editor) {
    this.root = root;
    this.ed = editor;
  }

  render() {
    const f = this.ed.footprint;
    const r = this.root;
    r.textContent = '';
    if (!f) return;

    const over = f.host_free_mb != null && f.estimated_memory_mb > f.host_free_mb;
    const line = document.createElement('div');
    line.innerHTML =
      `<b>${f.containers}</b> containers · <b>${f.estimated_memory_mb}</b> MB · ` +
      `about <b>${f.estimated_spawn_seconds}</b>s to spawn`;
    r.appendChild(line);

    const second = document.createElement('div');
    second.className = over ? 'over' : '';
    second.textContent =
      f.host_free_mb == null
        ? 'this machine does not say how much memory is free'
        : over
          ? `this machine has ${f.host_free_mb} MB free, which is less than this sandbox needs`
          : `${f.host_free_mb} MB free on this machine`;
    r.appendChild(second);

    // The premise of the project is 4 to 15 containers on a laptop where the
    // full topology needs a server. The meter is what shows a user they are
    // drifting to the wrong side of that line, before the machine swaps.
    if (f.containers > 15) {
      const note = el(
        'div',
        `${f.containers} containers is past what a laptop runs comfortably`,
        'over',
      );
      r.appendChild(note);
    }
  }
}
