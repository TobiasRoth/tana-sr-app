/* TanaSR — PWA-Portierung der iOS-App (TanaSR/ im selben Repo).
 *
 * Architektur unveraendert: cards.json (Dropbox App-Ordner "TanaSR") ist die
 * Quelle der Wahrheit fuer den SM-2-Zustand. Diese App schreibt cards.json NIE,
 * sondern haengt Bewertungen an reviews-pending.json an. Das Mac-Skript
 * Scripts/tana-sr/sync_tana_sr.py rechnet SM-2 nach, aktualisiert cards.json
 * und schreibt das Faelligkeitsdatum ins Tana-srs-Feld zurueck.
 */

'use strict';

const APP_KEY = 'mnrl1klwytt1trq';          // PKCE-App, kein Secret noetig
const TOKEN_KEY = 'tanasr.dropbox_refresh_token';
const QUEUE_KEY = 'tanasr.pending_reviews';
const DATA_CACHE = 'tanasr-data-v1';
const MEDIA_CACHE = 'tanasr-media-v1';
const MEDIA_PREFETCH = 40;                   // Medien der naechsten N Karten vorladen

/* ---------------------------------------------------------------- Dropbox */

class DropboxError extends Error {
  constructor(status, body) {
    super(`Dropbox-Fehler ${status}: ${body}`);
    this.status = status;
  }
}

const dropbox = {
  _accessToken: null,
  _expiry: 0,

  get refreshToken() { return localStorage.getItem(TOKEN_KEY); },
  get isAuthenticated() { return !!this.refreshToken; },

  connect(token) {
    localStorage.setItem(TOKEN_KEY, token.trim());
    this._accessToken = null;
    this._expiry = 0;
  },

  disconnect() {
    localStorage.removeItem(TOKEN_KEY);
    this._accessToken = null;
    this._expiry = 0;
  },

  async accessToken() {
    if (this._accessToken && this._expiry > Date.now()) return this._accessToken;
    const refresh = this.refreshToken;
    if (!refresh) throw new Error('Nicht mit Dropbox verbunden.');

    const res = await fetch('https://api.dropboxapi.com/oauth2/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: refresh,
        client_id: APP_KEY,
      }),
    });
    if (!res.ok) throw new DropboxError(res.status, await res.text());

    const json = await res.json();
    this._accessToken = json.access_token;
    this._expiry = Date.now() + (json.expires_in - 60) * 1000;
    return this._accessToken;
  },

  /** Wirft DropboxError(409) bei "path/not_found" — Aufrufer entscheidet. */
  async download(path) {
    const res = await fetch('https://content.dropboxapi.com/2/files/download', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await this.accessToken()}`,
        'Dropbox-API-Arg': JSON.stringify({ path }),
      },
    });
    if (!res.ok) throw new DropboxError(res.status, await res.text());
    return res.text();
  },

  async upload(path, text) {
    const res = await fetch('https://content.dropboxapi.com/2/files/upload', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await this.accessToken()}`,
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': JSON.stringify({ path, mode: 'overwrite' }),
      },
      body: text,
    });
    if (!res.ok) throw new DropboxError(res.status, await res.text());
  },
};

/* -------------------------------------------------------------------- SM-2 */

const GRADE_QUALITY = { again: 1, hard: 3, good: 4, easy: 5 };
const GRADE_LABELS = Object.keys(GRADE_QUALITY);

/** Pythons round(): kaufmaennisch zur geraden Zahl bei exakt .5, waehrend
 *  Math.round() aufrundet. Ohne das laufen App und sync_tana_sr.py bei
 *  Faellen wie 5 * 1.3 = 6.5 auseinander (6 statt 7 Tage). */
function roundHalfEven(value) {
  if (Math.abs(value % 1) !== 0.5) return Math.round(value);
  const lower = Math.floor(value);
  return lower % 2 === 0 ? lower : lower + 1;
}

const EASY_QUALITY = 5;      // "Einfach"
const EASY_START_DAYS = 14;  // Startsprung, siehe unten
const EASY_BONUS = 1.3;      // Zuschlag auf reife Karten, wie in Anki
const MAX_INTERVAL_DAYS = 365; // Deckel: was Tobi behalten will, soll jaehrlich auftauchen

/** Portierung von sm2() in sync_tana_sr.py — gegen die Python-Funktion ueber
 *  19'360 Kombinationen auf Gleichheit geprueft. Rechnet nur fuer die laufende
 *  Session vor, massgeblich bleibt der Nachlauf des Mac-Skripts.
 *
 *  Abweichung vom klassischen SM-2, bewusst (Entscheid Tobi 06.09.2026): dort
 *  sind die Intervalle der ersten beiden Stufen fest (1 und 6 Tage), die Note
 *  aendert daran nichts. Bei der Migration bekamen 1120 der 1181 Karten
 *  repetitions=1 als Heuristik und landeten alle auf der 6-Tage-Stufe, obwohl
 *  Tobi sie teils seit Jahren sicher kann. "Einfach" springt deshalb auf diesen
 *  Stufen direkt auf EASY_START_DAYS und traegt danach den Easy-Bonus. */
function sm2(ease, interval, repetitions, quality) {
  if (quality < 3) {
    repetitions = 0;
    interval = 1;
  } else {
    if (quality === EASY_QUALITY && repetitions <= 1) interval = EASY_START_DAYS;
    else if (repetitions === 0) interval = 1;
    else if (repetitions === 1) interval = 6;
    // Klammerung wie in sync_tana_sr.py (erst ease * bonus): eine andere
    // Reihenfolge weicht durch Gleitkomma-Rundung um einen Tag ab.
    else interval = roundHalfEven(interval * (ease * (quality === EASY_QUALITY ? EASY_BONUS : 1)));
    repetitions += 1;
    interval = Math.min(interval, MAX_INTERVAL_DAYS);
  }
  const newEase = Math.max(1.3, ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)));
  return { ease: roundHalfEven(newEase * 100) / 100, interval, repetitions };
}

/* -------------------------------------------------------------------- Datum */

/** ISO-Datum in Europe/Zurich — dieselbe Zeitzone, in der das Mac-Skript
 *  date.today() auswertet. 'sv-SE' liefert YYYY-MM-DD. */
function isoDate(date = new Date()) {
  return date.toLocaleDateString('sv-SE', { timeZone: 'Europe/Zurich' });
}

function isoDatePlusDays(days) {
  return isoDate(new Date(Date.now() + days * 86400000));
}

/* -------------------------------------------------------------------- Store */

const store = {
  async loadCards() {
    try {
      const text = await dropbox.download('/cards.json');
      const cache = await caches.open(DATA_CACHE);
      await cache.put('cards.json', new Response(text));
      return JSON.parse(text);
    } catch (err) {
      const cached = await (await caches.open(DATA_CACHE)).match('cards.json');
      if (cached) return JSON.parse(await cached.text());
      throw err;
    }
  },

  queue() {
    try { return JSON.parse(localStorage.getItem(QUEUE_KEY) || '[]'); }
    catch { return []; }
  },

  saveQueue(reviews) {
    localStorage.setItem(QUEUE_KEY, JSON.stringify(reviews));
  },

  /** Bewertung zuerst lokal sichern (funktioniert offline), dann best effort
   *  nach Dropbox mergen. Scheitert der Upload, bleibt sie in der Warteschlange. */
  async submitReview(review) {
    this.saveQueue([...this.queue(), review]);
    await this.flush();
  },

  async flush() {
    const queued = this.queue();
    if (!queued.length || !navigator.onLine) return;
    try {
      let remote = [];
      try {
        remote = JSON.parse(await dropbox.download('/reviews-pending.json'));
      } catch (err) {
        if (!(err instanceof DropboxError && err.status === 409)) throw err;
        // 409 = Datei existiert noch nicht, erster Review ueberhaupt.
      }
      await dropbox.upload('/reviews-pending.json',
        JSON.stringify([...remote, ...queued], null, 2));
      // Nur die hochgeladenen entfernen — waehrend des Uploads koennen weitere dazugekommen sein.
      const ids = new Set(queued.map(r => r.tana_node_id + r.reviewed_at));
      this.saveQueue(this.queue().filter(r => !ids.has(r.tana_node_id + r.reviewed_at)));
    } catch {
      /* bleibt in der Warteschlange, naechster Versuch beim naechsten Review */
    }
  },
};

/** Bilder und Vogelstimmen der naechsten Karten in den Cache holen, damit die
 *  Session offline (Zug) vollstaendig ist. no-cors: opaque Responses reichen
 *  fuer <img> und <audio>. */
async function prefetchMedia(cards) {
  if (!navigator.onLine) return;
  const cache = await caches.open(MEDIA_CACHE);
  const urls = cards.slice(0, MEDIA_PREFETCH)
    .flatMap(c => [c.image_url, c.audio_url])
    .filter(Boolean);

  for (const url of urls) {
    if (await cache.match(url)) continue;
    try {
      const res = await fetch(url, { mode: 'no-cors', cache: 'no-store' });
      await cache.put(url, res);
    } catch { /* egal, dann eben online nachladen */ }
  }
}

/* ----------------------------------------------------------------- Rendering */

const $ = id => document.getElementById(id);
const VIEWS = ['connect', 'loading', 'error', 'done', 'study'];

function showView(name) {
  VIEWS.forEach(v => { $(`view-${v}`).hidden = v !== name; });
}

function escapeHtml(text) {
  return text.replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));
}

/* Inline-Auszeichnung, wie sie aus Tana in answer_markdown ankommt (gegen alle
 * 1181 Karten erhoben): <a href>-Links, <mark>-Hervorhebungen, Markdown-Links
 * (ganz ueberwiegend eingebettete Bilder), Tana-Referenzen [Text](tana:ID),
 * nackte URLs, **fett**, *kursiv* und #tags. */

const IMAGE_URL_RE = /\.(png|jpe?g|gif|webp|avif)(\?|$)/i;
const SAFE_URL_RE = /^(https?:|mailto:|tana:)/i;
const TANA_INLINE_LIMIT = 60;   // ab hier steht der Tana-Sprung hinter dem Text

/** Nur bekannte Schemata verlinken — verhindert javascript: aus Kartentext. */
function safeUrl(url) {
  const trimmed = (url || '').trim();
  return SAFE_URL_RE.test(trimmed) ? trimmed : null;
}

/** Eine nackte URL als Linktext ist unlesbar (Readwise-Referenzen aus Tana):
 *  auf die Domain kuerzen, das Ziel steht ohnehin im href. */
function linkLabel(text) {
  const trimmed = text.trim();
  if (!/^https?:\/\/\S+$/.test(trimmed)) return null;
  try {
    return new URL(trimmed).hostname.replace(/^www\./, '') + '/…';
  } catch {
    return null;
  }
}

/** Aussenlinks muessen aus der installierten PWA heraus in Safari aufgehen —
 *  sonst ersetzt die Seite die App und es gibt keinen Weg zurueck. */
function linkHtml(url, innerHtml) {
  const safe = safeUrl(url);
  if (!safe) return innerHtml;
  const external = !safe.toLowerCase().startsWith('tana:');
  const target = external ? ' target="_blank" rel="noopener noreferrer"' : '';
  return `<a href="${escapeHtml(safe)}"${target}>${innerHtml}</a>`;
}

// Reihenfolge zaehlt: frueh stehende Alternativen verbrauchen ihren Text, damit
// z.B. eine URL innerhalb eines <a href> nicht nochmals als nackte URL matcht.
const INLINE_RE = new RegExp([
  /<a\s+href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/.source,   // 1 href, 2 Text
  /<mark>([\s\S]*?)<\/mark>/.source,                    // 3 Text
  /!?\[([^\]]*)\]\(([^)\s]+)\)/.source,               // 4 Text, 5 Ziel
  /(https?:\/\/[^\s<>()]+)/.source,                     // 6 nackte URL
  /\*\*([^*]+)\*\*/.source,                             // 7 fett
  /\*([^*\n]+)\*/.source,                               // 8 kursiv
  /#([A-Za-zÄÖÜäöü][\w-]*)/.source,                      // 9 Tana-Tag
].join('|'), 'g');

function renderInline(text, depth = 0, insideLink = false) {
  let out = '';
  let last = 0;

  for (const m of String(text).matchAll(INLINE_RE)) {
    out += escapeHtml(text.slice(last, m.index));
    last = m.index + m[0].length;

    const [, aHref, aText, markText, mdText, mdUrl, bareUrl, bold, italic, tag] = m;
    // Verschachtelte <a> sind ungueltiges HTML: innerhalb eines Links bleibt
    // alles Weitere Text (Fall: Tana-Referenz, deren Name eine URL ist).
    const inner = (value, nested = insideLink) =>
      (depth < 2 ? renderInline(value, depth + 1, nested) : escapeHtml(value));

    if (aHref !== undefined) {
      out += insideLink ? inner(aText) : linkHtml(aHref, inner(aText, true));
    } else if (markText !== undefined) {
      out += `<mark>${inner(markText)}</mark>`;
    } else if (mdUrl !== undefined) {
      const safe = safeUrl(mdUrl);
      if (safe && IMAGE_URL_RE.test(safe) && !safe.toLowerCase().startsWith('tana:')) {
        out += `<img class="inline-image" src="${escapeHtml(safe)}" alt="${escapeHtml(mdText)}" loading="lazy">`;
      } else if (insideLink) {
        out += inner(mdText) || escapeHtml(mdUrl);
      } else {
        // Bullets der Form [](tana:ID) haben keinen Linktext — die nackte ID
        // waere unlesbar, deshalb eine Beschriftung.
        const isTana = safe && safe.toLowerCase().startsWith('tana:');
        const shortened = linkLabel(mdText);
        if (isTana && !shortened && mdText.length > TANA_INLINE_LIMIT) {
          // Ganze Zitate sind in Tana die Referenz. Den Absatz durchgehend blau
          // zu faerben macht ihn unlesbar, deshalb steht der Sprung dahinter.
          out += `${inner(mdText)} ${linkHtml(mdUrl, '↗')}`;
        } else {
          const label = shortened
            ? escapeHtml(shortened)
            : inner(mdText, true) || (isTana ? '↗ Tana' : escapeHtml(mdUrl));
          out += linkHtml(mdUrl, label);
        }
      }
    } else if (bareUrl !== undefined) {
      out += insideLink ? escapeHtml(bareUrl) : linkHtml(bareUrl, escapeHtml(bareUrl));
    } else if (bold !== undefined) {
      out += `<strong>${inner(bold)}</strong>`;
    } else if (italic !== undefined) {
      out += `<em>${inner(italic)}</em>`;
    } else if (tag !== undefined) {
      out += `<span class="tag">#${escapeHtml(tag)}</span>`;
    }
  }

  return out + escapeHtml(text.slice(last));
}

function answerBullets(markdown) {
  return (markdown || '')
    .split('\n')
    .map(line => line.trim())
    .map(line => line.startsWith('- ') ? line.slice(2) : line)
    .filter(Boolean);
}

/* -------------------------------------------------------------------- Session */

const session = {
  cards: [],
  index: 0,
  revealed: false,

  get card() { return this.cards[this.index]; },

  async load() {
    showView('loading');
    try {
      const all = await store.loadCards();
      const today = isoDate();
      this.cards = all
        .filter(c => !c.due_date || c.due_date <= today)
        .sort((a, b) => (a.due_date || '').localeCompare(b.due_date || ''));
      this.index = 0;
      this.revealed = false;
      store.flush();
      prefetchMedia(this.cards);
      this.render();
    } catch (err) {
      $('error-text').textContent = err.message;
      showView('error');
    }
  },

  render() {
    updateSyncBadge();
    const card = this.card;
    if (!card) {
      const pending = store.queue().length;
      $('done-pending').hidden = pending === 0;
      $('done-pending').textContent = `${pending} Bewertung(en) warten auf die Synchronisation.`;
      showView('done');
      return;
    }

    showView('study');
    $('remaining').textContent = `${this.cards.length - this.index} verbleibend`;
    $('card-scroll').scrollTop = 0;

    const image = $('card-image');
    image.hidden = !card.image_url;
    if (card.image_url) image.src = card.image_url;

    const audio = $('card-audio');
    const audioBtn = $('audio-btn');
    audioBtn.hidden = !card.audio_url;
    if (card.audio_url) {
      audio.src = card.audio_url;
      audio.play().catch(() => { /* iOS verlangt ggf. eine Nutzergeste */ });
    } else {
      audio.pause();
      audio.removeAttribute('src');
    }

    // Fragen tragen vereinzelt **fett** und #tags, deshalb derselbe Renderer.
    $('card-question').innerHTML = renderInline(card.question || '');

    $('card-answer').hidden = !this.revealed;
    $('reveal-btn').hidden = this.revealed;
    $('grade-row').hidden = !this.revealed;
    if (this.revealed) {
      $('answer-list').innerHTML = answerBullets(card.answer_markdown)
        .map(bullet => `<li>${renderInline(bullet)}</li>`)
        .join('');
    }
  },

  reveal() {
    this.revealed = true;
    this.render();
  },

  async grade(grade) {
    const card = this.card;
    if (!card || !this.revealed) return;

    const quality = GRADE_QUALITY[grade];
    const result = sm2(card.ease_factor, card.interval_days, card.repetitions, quality);
    Object.assign(card, {
      ease_factor: result.ease,
      interval_days: result.interval,
      repetitions: result.repetitions,
      due_date: isoDatePlusDays(result.interval),
      last_reviewed_at: new Date().toISOString(),
    });

    await store.submitReview({
      tana_node_id: card.tana_node_id,
      grade,
      reviewed_at: new Date().toISOString(),
    });

    this.revealed = false;
    this.index += 1;
    this.render();
  },
};

function updateSyncBadge() {
  const pending = store.queue().length;
  const badge = $('sync-badge');
  badge.hidden = pending === 0;
  badge.textContent = `${pending} nicht synchronisiert`;
}

/* ------------------------------------------------------------------- Aufbau */

$('connect-btn').addEventListener('click', async () => {
  const btn = $('connect-btn');
  const error = $('connect-error');
  const token = $('token-input').value.trim();
  if (!token) return;

  btn.disabled = true;
  btn.textContent = 'Prüfen…';
  error.hidden = true;

  dropbox.connect(token);
  try {
    await dropbox.download('/cards.json');
    $('token-input').value = '';
    session.load();
  } catch (err) {
    dropbox.disconnect();
    error.textContent = `Verbindung fehlgeschlagen: ${err.message}`;
    error.hidden = false;
  } finally {
    btn.disabled = false;
    btn.textContent = 'Verbinden';
  }
});

$('reveal-btn').addEventListener('click', () => session.reveal());
$('reload-btn').addEventListener('click', () => session.load());
$('retry-btn').addEventListener('click', () => session.load());

$('reset-btn').addEventListener('click', () => {
  if (!confirm('Dropbox-Verbindung trennen? Nicht synchronisierte Bewertungen bleiben erhalten.')) return;
  dropbox.disconnect();
  showView('connect');
});

$('audio-btn').addEventListener('click', () => {
  const audio = $('card-audio');
  audio.currentTime = 0;
  audio.play().catch(() => {});
});

document.querySelectorAll('.grade').forEach(btn => {
  btn.addEventListener('click', () => session.grade(btn.dataset.grade));
});

// Tastatur fuer den Desktop-Browser: Leertaste zeigt die Antwort, 1-4 bewerten.
document.addEventListener('keydown', event => {
  if ($('view-study').hidden) return;
  if (event.key === ' ' || event.key === 'Enter') {
    event.preventDefault();
    if (!session.revealed) session.reveal();
  } else if (session.revealed && event.key >= '1' && event.key <= '4') {
    session.grade(GRADE_LABELS[Number(event.key) - 1]);
  }
});

window.addEventListener('online', () => store.flush().then(updateSyncBadge));

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js')
    .catch(err => console.error('Service Worker nicht registriert:', err));
}

if (dropbox.isAuthenticated) session.load();
else showView('connect');
