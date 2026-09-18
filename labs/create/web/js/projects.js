// Project management: the browser, duplicate, rename, delete, export, import,
// the version list, and the import review.
//
// The review is the one dialog here that is not a convenience. An imported
// project holds code that will run as root inside a container, and blueprints
// are exactly what students will pass between each other, so import shows
// everything that executes and nothing spawns until somebody says yes. The
// refusal is not enforced in this file: the mark is a file in the project
// directory, and the TUI's Spawn row, which never talks to this server, checks
// the same file.

import { api } from './api.js';
import { ask, button, confirmAsk, el, modal, pre, toast, when } from './ui.js';

export class Projects {
  constructor(editor, app) {
    this.ed = editor;
    this.app = app;
  }

  async browse() {
    const rows = await api.projects();
    modal((box, close) => {
      box.appendChild(el('h2', 'Sandboxes'));
      box.appendChild(
        el('p', 'Every project under ~/.minilabs/sandboxes. The TUI runs them by these names.'),
      );

      const list = document.createElement('div');
      list.className = 'list';
      if (!rows.length) {
        list.appendChild(el('div', 'Nothing here yet.', 'list-row'));
      }
      for (const r of rows) {
        const row = document.createElement('div');
        row.className = 'list-row';
        const main = document.createElement('div');
        main.className = 'grow';
        main.appendChild(el('div', r.name));
        const bits = [
          `${r.nodes} nodes`,
          `${r.links} links`,
          r.emitted ? 'emitted' : 'not emitted yet',
          `saved ${when(r.modified)}`,
        ];
        if (r.unreviewed) bits.push('imported, not reviewed');
        if (r.draft) bits.push('has an unsaved draft');
        main.appendChild(el('div', bits.join(' · '), 'meta'));
        row.appendChild(main);
        row.onclick = async () => {
          close();
          await this.app.openProject(r.name);
        };
        list.appendChild(row);
      }
      box.appendChild(list);

      const actions = document.createElement('div');
      actions.className = 'actions';
      actions.appendChild(
        button('Import a file', async () => {
          close();
          await this.importBundle();
        }),
      );
      actions.appendChild(
        button('New sandbox', async () => {
          close();
          await this.createProject();
        }, 'primary'),
      );
      box.appendChild(actions);
    });
  }

  async createProject() {
    const name = await ask('New sandbox', {
      label: 'A directory name, with no spaces or slashes',
      value: '',
      ok: 'Create',
      note: 'This is the name the TUI’s Sandboxes rows ask for, and the name every container it creates is labelled with.',
    });
    if (!name) return;
    try {
      await api.createProject(name, null);
      await this.app.openProject(name);
      toast(`created ${name}`);
    } catch (e) {
      toast(e.message, true);
    }
  }

  async duplicate() {
    const to = await ask('Duplicate this sandbox', {
      label: 'New name',
      value: `${this.ed.name}-copy`,
      ok: 'Duplicate',
      note: 'The copy carries the topology and the layout. It carries no emitted scripts, because those are build output and hold the old name.',
    });
    if (!to) return;
    try {
      await api.copy(this.ed.name, to);
      await this.app.openProject(to);
      toast(`copied to ${to}`);
    } catch (e) {
      toast(e.message, true);
    }
  }

  async rename() {
    const to = await ask('Rename this sandbox', {
      label: 'New name',
      value: this.ed.name,
      ok: 'Rename',
      note: 'The directory and the name inside the file both change. If this sandbox is spawned, its containers keep the old name until you tear it down and spawn it again.',
    });
    if (!to || to === this.ed.name) return;
    try {
      await api.rename(this.ed.name, to);
      await this.app.openProject(to);
      toast(`renamed to ${to}`);
    } catch (e) {
      toast(e.message, true);
    }
  }

  async remove() {
    const name = this.ed.name;
    const typed = await ask(`Delete ${name}`, {
      label: `Type ${name} to confirm`,
      ok: 'Delete',
      note: 'This removes the directory and everything in it. If the sandbox is spawned, tear it down first: deleting the directory leaves its containers with nothing that can name them.',
    });
    if (typed !== name) {
      if (typed !== null) toast('the name did not match, so nothing was deleted');
      return;
    }
    try {
      await api.remove(name, typed);
      toast(`deleted ${name}`);
      this.ed.name = null;
      this.ed.doc = null;
      await this.browse();
    } catch (e) {
      toast(e.message, true);
    }
  }

  /// Export: the whole project as one file, which is what gets passed around.
  ///
  /// Downloaded through a blob rather than by navigating to the URL, so the page
  /// and its token stay where they are.
  async exportBundle() {
    try {
      const text = await api.exportText(this.ed.name);
      const blob = new Blob([text], { type: 'text/plain' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `${this.ed.name}.minilab.toml`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
      toast('exported');
    } catch (e) {
      toast(e.message, true);
    }
  }

  /// Export as a lab skeleton, which this cannot do: it prints the command.
  ///
  /// The editor container's only writable mount is ~/.minilabs/sandboxes, so it
  /// cannot reach labs/catalogue/ even if it knew where a source checkout was,
  /// and a release tree has no labs/catalogue/ at all. So the bridge to the
  /// catalogue is a host command, and the editor's whole part in it is to say
  /// what to type.
  skeletonCommand() {
    const name = this.ed.name || '<sandbox>';
    const cmd = `labs/create/scripts/skeleton.sh ${name}`;
    modal((box, close) => {
      box.appendChild(el('h2', 'Export as a lab skeleton'));
      box.appendChild(
        el(
          'p',
          'This writes the topology into labs/catalogue/ as the start of a lab: the same ' +
            'containers under the four-segment lab names, a handout that compiles and says ' +
            'TODO everywhere it needs prose, and a selftest that exits non-zero until it is ' +
            'written. From that point the lab is hand authored.',
        ),
      );
      box.appendChild(
        el(
          'p',
          'Run it yourself, in a source checkout of the MiniLabs repository. The editor runs ' +
            'in a container that can write to your sandboxes and nothing else, and a released ' +
            'tree has no catalogue to write into.',
        ),
      );
      box.appendChild(pre(cmd));
      box.appendChild(
        el(
          'p',
          'Both release scripts refuse to build while the exported manifest still carries ' +
            'status = "skeleton", so an unfinished lab cannot reach a student.',
        ),
      );
      box.appendChild(
        actionsRow([
          button('Copy the command', async () => {
            try {
              await navigator.clipboard.writeText(cmd);
              toast('copied');
            } catch {
              // Clipboard access is refused on a page served over plain HTTP in
              // some browsers, and the command is on screen either way.
              toast('copy it from the box above', true);
            }
          }),
          button('Close', close, 'primary'),
        ]),
      );
    });
  }

  async importBundle() {
    const file = await pickFile();
    if (!file) return;
    const text = await file.text();
    const suggested = file.name.replace(/\.minilab\.toml$|\.toml$/, '');
    const name = await ask('Import a sandbox', {
      label: 'Name it',
      value: suggested,
      ok: 'Import',
      note: 'It arrives marked as not reviewed. Nothing spawns until you have looked at what it runs.',
    });
    if (!name) return;
    try {
      const res = await api.import(name, text);
      if (res.presets_not_installed?.length) {
        toast(
          `this machine does not have these presets: ${res.presets_not_installed.join(', ')}`,
          true,
        );
      }
      await this.app.openProject(name);
      await this.review();
    } catch (e) {
      toast(e.message, true);
    }
  }

  /// Everything an imported project will run, and the one place it is accepted.
  async review() {
    const res = await api.review(this.ed.name);
    const items = res.review?.items || [];
    modal((box, close) => {
      box.appendChild(el('h2', `What ${this.ed.name} runs`));
      box.appendChild(
        el(
          'p',
          items.length
            ? 'Each of these executes as root inside a container. A Dockerfile RUN line executes when the image is built, which is as much a payload as an init script.'
            : 'Nothing in this project executes: no init script, no docker run arguments, no added capabilities, no image override, and no preset Dockerfile of its own.',
        ),
      );

      for (const item of items) {
        const wrap = document.createElement('div');
        wrap.className = 'review-item';
        wrap.appendChild(el('div', `${item.kind} on ${item.subject}`, 'what'));
        wrap.appendChild(pre(item.body));
        box.appendChild(wrap);
      }

      const actions = document.createElement('div');
      actions.className = 'actions';
      if (res.unreviewed) {
        actions.appendChild(
          button('Leave it blocked', () => {
            close();
            toast('spawning stays refused until this is confirmed');
          }),
        );
        actions.appendChild(
          button('I have read this; allow it to spawn', async () => {
            close();
            try {
              await api.confirmReview(this.ed.name);
              this.ed.unreviewed = false;
              this.ed.emit('changed', this.ed);
              toast('confirmed');
            } catch (e) {
              toast(e.message, true);
            }
          }, 'primary'),
        );
      } else {
        actions.appendChild(button('Close', close, 'primary'));
      }
      box.appendChild(actions);
    });
  }

  // ------------------------------------------------------------- versions

  async versions() {
    const res = await api.versions(this.ed.name);
    modal((box, close) => {
      box.appendChild(el('h2', 'Versions'));
      if (!res.available) {
        box.appendChild(el('p', res.reason || 'Version history is not available here.'));
        box.appendChild(actionsRow([button('Close', close, 'primary')]));
        return;
      }
      box.appendChild(
        el('p', 'Each version is a commit of this project directory. Saving one changes nothing about what spawns.'),
      );

      const list = document.createElement('div');
      list.className = 'list';
      if (!res.entries.length) {
        list.appendChild(el('div', 'No versions saved yet.', 'list-row'));
      }
      for (const entry of res.entries) {
        const row = document.createElement('div');
        row.className = 'list-row';
        const main = document.createElement('div');
        main.className = 'grow';
        main.appendChild(el('div', entry.message));
        main.appendChild(el('div', `${entry.rev} · ${entry.when}`, 'meta'));
        row.appendChild(main);
        row.appendChild(
          button('Diff', async (ev) => {
            ev.stopPropagation();
            const d = await api.versionDiff(this.ed.name, entry.rev);
            modal((inner, innerClose) => {
              inner.appendChild(el('h2', `${entry.rev}  ${entry.message}`));
              inner.appendChild(pre(d.diff || 'nothing changed'));
              inner.appendChild(actionsRow([button('Close', innerClose, 'primary')]));
            });
          }),
        );
        row.appendChild(
          button('Restore', async (ev) => {
            ev.stopPropagation();
            const yes = await confirmAsk(
              `Restore ${entry.rev}`,
              'This puts the files back as they were in that version. The history stays, so you can restore a later one again.',
              { ok: 'Restore' },
            );
            if (!yes) return;
            close();
            try {
              await api.restoreVersion(this.ed.name, entry.rev);
              await this.app.openProject(this.ed.name);
              toast(`restored ${entry.rev}`);
            } catch (e) {
              toast(e.message, true);
            }
          }),
        );
        list.appendChild(row);
      }
      box.appendChild(list);
      box.appendChild(
        actionsRow([
          button('Close', close),
          button('Save a version now', async () => {
            close();
            await this.saveVersion();
          }, 'primary'),
        ]),
      );
    });
  }

  async saveVersion() {
    const message = await ask('Save a version', {
      label: 'What changed',
      value: '',
      ok: 'Save',
    });
    if (message === null) return;
    try {
      if (this.ed.dirty) await this.ed.save();
      const res = await api.saveVersion(this.ed.name, message);
      toast(`saved version ${res.rev}`);
    } catch (e) {
      toast(e.message, true);
    }
  }
}

function actionsRow(children) {
  const a = document.createElement('div');
  a.className = 'actions';
  for (const c of children) a.appendChild(c);
  return a;
}

/// A file chooser, without leaving the page.
function pickFile() {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.toml,text/plain';
    input.onchange = () => resolve(input.files?.[0] || null);
    input.oncancel = () => resolve(null);
    input.click();
  });
}
