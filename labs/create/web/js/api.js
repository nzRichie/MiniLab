// The JSON API, in one place.
//
// Every path is relative to the page, which is `/<token>/`, so the token rides
// in the address bar and never appears in this file or in any request this file
// builds. That is also why nothing here stores it: there is nowhere for it to
// leak to that does not already have it.

/** A failed call, carrying the status and whatever the server said. */
export class ApiError extends Error {
  constructor(status, message, body) {
    super(message);
    this.status = status;
    this.body = body;
  }
}

async function call(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let parsed = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = null;
  }
  if (!res.ok) {
    const message = (parsed && (parsed.error || parsed.message)) || text || res.statusText;
    throw new ApiError(res.status, message, parsed);
  }
  return parsed;
}

const enc = encodeURIComponent;

export const api = {
  presets: () => call('GET', 'api/presets'),

  projects: () => call('GET', 'api/projects'),
  createProject: (name, asn) => call('POST', 'api/projects', { name, asn }),
  project: (name) => call('GET', `api/projects/${enc(name)}`),
  save: (name, doc) => call('PUT', `api/projects/${enc(name)}`, doc),
  copy: (name, to) => call('POST', `api/projects/${enc(name)}/copy`, { to }),
  rename: (name, to) => call('POST', `api/projects/${enc(name)}/rename`, { to }),
  remove: (name, confirm) => call('DELETE', `api/projects/${enc(name)}`, { confirm }),

  // Every edit. The whole document goes up and comes back applied, so there is
  // one implementation of what an edit means and it is not this one.
  ops: (doc, commands) => call('POST', 'api/ops', { ...doc, commands }),

  findings: (name) => call('GET', `api/projects/${enc(name)}/findings`),
  footprint: (name) => call('GET', `api/projects/${enc(name)}/footprint`),
  emit: (name) => call('POST', `api/projects/${enc(name)}/emit`),

  getDraft: (name) => call('GET', `api/projects/${enc(name)}/draft`),
  putDraft: (name, doc) => call('PUT', `api/projects/${enc(name)}/draft`, doc),
  dropDraft: (name) => call('DELETE', `api/projects/${enc(name)}/draft`),

  review: (name) => call('GET', `api/projects/${enc(name)}/review`),
  confirmReview: (name) => call('POST', `api/projects/${enc(name)}/review`, { confirm: true }),

  versions: (name) => call('GET', `api/projects/${enc(name)}/versions`),
  saveVersion: (name, message) => call('POST', `api/projects/${enc(name)}/versions`, { message }),
  versionDiff: (name, rev) => call('GET', `api/projects/${enc(name)}/versions/${enc(rev)}`),
  restoreVersion: (name, rev) =>
    call('POST', `api/projects/${enc(name)}/versions/${enc(rev)}/restore`),

  blueprints: () => call('GET', 'api/blueprints'),
  blueprint: (name) => call('GET', `api/blueprints/${enc(name)}`),
  deleteBlueprint: (name) => call('DELETE', `api/blueprints/${enc(name)}`),
  saveBlueprint: (project, body) => call('POST', `api/projects/${enc(project)}/blueprints`, body),
  pushBlueprint: (project, scope) =>
    call('POST', `api/projects/${enc(project)}/blueprints/push`, { scope }),

  exportUrl: (name) => `api/projects/${enc(name)}/export`,
  exportText: async (name) => {
    const res = await fetch(`api/projects/${enc(name)}/export`);
    if (!res.ok) throw new ApiError(res.status, await res.text(), null);
    return res.text();
  },
  import: (name, bundle) => call('POST', 'api/import', { name, bundle }),
};
