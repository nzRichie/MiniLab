// The command palette.
//
// The users are on lab machines, often over a forwarded port on a slow link,
// where a mouse-only tool is painful. Everything the top bar and the inspector
// can do is reachable from here by typing part of its name, and the list is
// built from the live document so "add a victim" and "renumber lab" are entries
// rather than paths through menus.

import { modal } from './ui.js';

export function openPalette(commands) {
  modal((box, close) => {
    box.appendChild(heading('Commands'));
    const input = document.createElement('input');
    input.type = 'text';
    input.placeholder = 'Type to filter, Enter to run';
    box.appendChild(input);

    const list = document.createElement('div');
    list.className = 'list';
    list.style.marginTop = '10px';
    box.appendChild(list);

    let shown = [];
    let active = 0;

    const draw = () => {
      const q = input.value.trim().toLowerCase();
      shown = commands.filter((c) => !q || score(c, q) > 0);
      shown.sort((a, b) => score(b, q) - score(a, q));
      shown = shown.slice(0, 40);
      active = Math.min(active, Math.max(0, shown.length - 1));
      list.textContent = '';
      shown.forEach((c, i) => {
        const row = document.createElement('div');
        row.className = `list-row${i === active ? ' active' : ''}`;
        const label = document.createElement('div');
        label.className = 'grow';
        label.textContent = c.label;
        row.appendChild(label);
        if (c.hint) {
          const hint = document.createElement('div');
          hint.className = 'meta';
          hint.textContent = c.hint;
          row.appendChild(hint);
        }
        row.onclick = () => {
          close();
          c.run();
        };
        list.appendChild(row);
      });
    };

    input.addEventListener('input', () => {
      active = 0;
      draw();
    });
    input.addEventListener('keydown', (ev) => {
      ev.stopPropagation();
      if (ev.key === 'ArrowDown') {
        active = Math.min(active + 1, shown.length - 1);
        draw();
        ev.preventDefault();
      } else if (ev.key === 'ArrowUp') {
        active = Math.max(active - 1, 0);
        draw();
        ev.preventDefault();
      } else if (ev.key === 'Enter') {
        const chosen = shown[active];
        if (chosen) {
          close();
          chosen.run();
        }
      }
    });

    draw();
  });
}

/// A small subsequence match: every character of the query in order, with a
/// bonus for matching the start of a word. Enough for a list of this size, and
/// it needs no dependency.
function score(cmd, q) {
  if (!q) return 1;
  const text = `${cmd.label} ${cmd.hint || ''}`.toLowerCase();
  let i = 0;
  let points = 0;
  for (const ch of q) {
    const at = text.indexOf(ch, i);
    if (at < 0) return 0;
    points += at === 0 || text[at - 1] === ' ' ? 3 : 1;
    i = at + 1;
  }
  return points;
}

function heading(text) {
  const h = document.createElement('h2');
  h.textContent = text;
  return h;
}
