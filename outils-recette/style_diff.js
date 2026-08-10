#!/usr/bin/env node
'use strict';
/*
 * style_diff.js — diff de STYLES CALCULÉS entre une maquette et l'application.
 *
 *   node style_diff.js --pairs pairs.json --out rapport/
 *
 * On ne compare pas des pixels : on extrait de chaque page l'arbre des éléments
 * visibles avec leurs styles calculés, on apparie les deux arbres, et on liste
 * les écarts de FORME (typo, couleurs, espacements, bordures, layout, boîte).
 * Les différences de CONTENU (textes, nombres, images, nombre de lignes d'un
 * tableau) sont ignorées : ce sont des données, pas de la fidélité visuelle.
 *
 * Voir README.md pour le format de pairs.json.
 */

const fs = require('fs');
const path = require('path');

// ===========================================================================
// 1. RÉGLAGES — c'est ici qu'on calibre
// ===========================================================================

// Allowlist : écarts connus et acceptés, retirés du rapport (comptés à part).
// Une règle matche si TOUS les champs qu'elle déclare matchent. Chaque champ
// accepte une chaîne (égalité ou sous-chaîne) ou une RegExp.
const ALLOWLIST = [
  {
    property: 'background-image',
    reason: "URL d'asset (digest Propshaft, upload seedé) : l'URL diffère, la forme non",
    match: (f) => /^url\(\)$/.test(f.mockup || '') && /^url\(\)$/.test(f.app || '')
  },
  {
    element: /Hub mockups/i,
    reason: 'Lien "Hub mockups" propre à la maquette, remplacé par "Se déconnecter" dans l\'app'
  },
  {
    element: /Se déconnecter/i,
    reason: 'Bouton de déconnexion : présent seulement dans l\'app, par construction'
  },
  {
    // `button_to` et les vrais formulaires remplacent un <a> stylé en bouton
    // par un <button> : la feuille de style du navigateur y met
    // text-align:center. Sans effet visible sur un bouton dont le libellé
    // remplit la boîte, et ça tomberait sur chaque bouton de chaque page.
    property: 'text-align',
    tags: /^(a>button|button>a|a>input|input>a)$/,
    reason: 'text-align:center est le défaut navigateur de <button>, pas un choix de charte'
  },
  {
    // button_to enveloppe le bouton dans un <form> : un niveau de DOM en plus,
    // sans effet visuel. On ne veut pas d'un "élément ajouté" par bouton.
    category: 'structure',
    kind: 'added',
    element: /^form\b/i,
    reason: 'button_to génère un <form> autour du bouton (wrapper Rails, invisible)'
  },
  {
    property: 'font-family',
    match: (f) => normFontStack(f.mockup) === normFontStack(f.app),
    reason: 'Même pile de polices à la casse/aux guillemets près'
  }
];

// Sélecteurs ignorés par défaut (élément ET sous-arbre).
const DEFAULT_IGNORE_SELECTORS = [
  'script', 'style', 'link', 'meta', 'noscript', 'template',
  '[data-style-diff-ignore]',
  '.turbo-progress-bar',
  '#letter_opener'
];

// Tolérances par défaut, en px. Voir README pour la justification.
const DEFAULT_TOLERANCES = {
  font: 0,          // font-size : aucune tolérance (0 px)
  line_height: 0.5, // hauteur de ligne : arrondi sous-pixel du moteur
  tracking: 0.2,    // letter-spacing : idem, valeurs souvent en em converties
  spacing: 1,       // padding / margin / gap / bordures / rayons
  box: 2,           // largeur / hauteur : 2 px (voir README, calibrage)
  offset: 8         // position relative au parent : bruit de rendu important
};

// Un écart de boîte n'est signalé que si l'élément a le MÊME texte des deux
// côtés (sinon c'est la donnée qui pousse la boîte, pas le style).
const BOX_REQUIRES_SAME_TEXT = true;

// Feuilles de style externes tolérées (polices) — signalées en info, pas en écart.
const FONT_CSS_HOSTS = [
  'fonts.googleapis.com', 'fonts.gstatic.com', 'use.typekit.net',
  'fonts.bunny.net', 'rsms.me'
];

// Bibliothèques de style connues : si l'une d'elles cohabite avec la nôtre,
// c'est bloquant (deux systèmes de styles sur la même page).
const KNOWN_CSS_FRAMEWORKS = /(bootstrap|bulma|foundation|materialize|semantic|tachyons|primer|antd|material-?ui|uikit|milligram|pico\.?css|water\.?css|normalize|skeleton)/i;

// Contrôles de saisie : tailles rendues en dessous desquelles on parle de
// défaut. 44 px est la cible tactile recommandée (WCAG 2.2 AA « Target Size
// (Minimum) » : 24 px absolu, 44 px pour l'AAA et pour toutes les
// recommandations plateformes). En dessous de `crushed_px`, le champ n'est plus
// utilisable du tout : c'est le cas mesuré d'un `input` rendu à 18 px de large
// sur un écran déclaré conforme.
const DEFAULT_CONTROLS = {
  min_px: 44,        // cible tactile : en dessous, défaut
  crushed_px: 24,    // champ écrasé : inutilisable, bloquant
  tiny_min_px: 10,   // cases à cocher / radios : légitimement petites
  shrink_ratio: 0.5  // largeur app < ratio × largeur maquette = champ écrasé par l'app
};

// Débordement interne : en dessous de ce nombre de pixels, l'écart entre
// `scrollWidth` et `clientWidth` relève de l'arrondi sous-pixel du moteur.
const CLIP_MIN_EXCESS = 3;

// Nombre maximum d'éléments extraits par page (garde-fou).
const MAX_NODES = 4000;

// Seuil de similarité pour l'appariement approximatif (0..1).
const FUZZY_MIN = 0.62;

// ===========================================================================
// 2. Propriétés observées et leur sémantique
// ===========================================================================

const PROPS = [
  'display', 'position', 'float', 'visibility',
  'font-family', 'font-size', 'font-weight', 'font-style',
  'line-height', 'letter-spacing', 'text-align', 'text-transform',
  'text-decoration-line', 'white-space', 'text-overflow',
  'color', 'background-color', 'background-image',
  'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width',
  'border-top-style', 'border-right-style', 'border-bottom-style', 'border-left-style',
  'border-top-color', 'border-right-color', 'border-bottom-color', 'border-left-color',
  'border-top-left-radius', 'border-top-right-radius',
  'border-bottom-right-radius', 'border-bottom-left-radius',
  'padding-top', 'padding-right', 'padding-bottom', 'padding-left',
  'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
  'row-gap', 'column-gap',
  'flex-direction', 'flex-wrap', 'justify-content', 'align-items', 'align-self',
  'flex-grow', 'flex-shrink', 'flex-basis',
  'grid-template-columns', 'grid-template-rows', 'grid-auto-flow',
  'box-shadow', 'opacity', 'overflow-x', 'overflow-y', 'object-fit', 'z-index'
];

const T = { NUM: 'num', NUMLIST: 'numlist', COLOR: 'color', KW: 'kw', SHADOW: 'shadow', FONT: 'font' };

// cat  : catégorie de regroupement
// type : comment comparer
// tol  : clé de tolérance (pour les numériques)
// sev  : gravité par défaut
// fr   : libellé lisible
const M = (cat, type, tol, sev, fr) => ({ cat, type, tol, sev, fr });
const PROP_META = {
  'display':        M('layout', T.KW, null, 'bloquant', 'display'),
  'position':       M('layout', T.KW, null, 'bloquant', 'position'),
  'float':          M('layout', T.KW, null, 'majeur', 'float'),
  'visibility':     M('layout', T.KW, null, 'bloquant', 'visibilité'),
  'flex-direction': M('layout', T.KW, null, 'bloquant', 'direction flex'),
  'flex-wrap':      M('layout', T.KW, null, 'majeur', 'retour à la ligne flex'),
  'justify-content':M('layout', T.KW, null, 'majeur', 'justification'),
  'align-items':    M('layout', T.KW, null, 'majeur', 'alignement vertical'),
  'align-self':     M('layout', T.KW, null, 'mineur', 'alignement propre'),
  'flex-grow':      M('layout', T.NUM, 'tracking', 'mineur', 'flex-grow'),
  'flex-shrink':    M('layout', T.NUM, 'tracking', 'mineur', 'flex-shrink'),
  'flex-basis':     M('layout', T.KW, null, 'mineur', 'flex-basis'),
  'grid-template-columns': M('layout', T.NUMLIST, 'box', 'majeur', 'colonnes de grille'),
  'grid-template-rows':    M('layout', T.NUMLIST, 'box', 'mineur', 'lignes de grille'),
  'grid-auto-flow': M('layout', T.KW, null, 'mineur', 'flux de grille'),
  'overflow-x':     M('layout', T.KW, null, 'majeur', 'débordement horizontal (overflow-x)'),
  'overflow-y':     M('layout', T.KW, null, 'mineur', 'débordement vertical (overflow-y)'),
  'object-fit':     M('layout', T.KW, null, 'mineur', 'cadrage image'),
  'z-index':        M('layout', T.KW, null, 'mineur', 'z-index'),

  'font-family':    M('typo', T.FONT, null, 'majeur', 'police'),
  'font-size':      M('typo', T.NUM, 'font', 'majeur', 'taille de police'),
  'font-weight':    M('typo', T.NUM, 'font', 'majeur', 'graisse'),
  'font-style':     M('typo', T.KW, null, 'majeur', 'style de police'),
  'line-height':    M('typo', T.NUM, 'line_height', 'mineur', 'hauteur de ligne'),
  'letter-spacing': M('typo', T.NUM, 'tracking', 'mineur', 'interlettrage'),
  'text-align':     M('typo', T.KW, null, 'majeur', 'alignement du texte'),
  'text-transform': M('typo', T.KW, null, 'majeur', 'casse (text-transform)'),
  'text-decoration-line': M('typo', T.KW, null, 'mineur', 'décoration du texte'),
  'white-space':    M('typo', T.KW, null, 'majeur', 'gestion des espaces (white-space)'),
  'text-overflow':  M('typo', T.KW, null, 'mineur', 'troncature (text-overflow)'),

  'color':            M('couleur', T.COLOR, null, 'majeur', 'couleur du texte'),
  'background-color': M('couleur', T.COLOR, null, 'majeur', 'couleur de fond'),
  'background-image': M('couleur', T.KW, null, 'majeur', 'image/dégradé de fond'),

  'box-shadow': M('decor', T.SHADOW, null, 'mineur', 'ombre'),
  'opacity':    M('decor', T.NUM, 'tracking', 'mineur', 'opacité'),

  'border-top-left-radius':     M('decor', T.NUM, 'spacing', 'mineur', 'rayon haut-gauche'),
  'border-top-right-radius':    M('decor', T.NUM, 'spacing', 'mineur', 'rayon haut-droit'),
  'border-bottom-right-radius': M('decor', T.NUM, 'spacing', 'mineur', 'rayon bas-droit'),
  'border-bottom-left-radius':  M('decor', T.NUM, 'spacing', 'mineur', 'rayon bas-gauche')
};
for (const side of ['top', 'right', 'bottom', 'left']) {
  const fr = { top: 'haut', right: 'droite', bottom: 'bas', left: 'gauche' }[side];
  PROP_META[`padding-${side}`] = M('espacement', T.NUM, 'spacing', 'majeur', `padding ${fr}`);
  PROP_META[`margin-${side}`] = M('espacement', T.NUM, 'spacing', 'majeur', `marge ${fr}`);
  PROP_META[`border-${side}-width`] = M('bordure', T.NUM, 'spacing', 'majeur', `épaisseur de bordure ${fr}`);
  PROP_META[`border-${side}-style`] = M('bordure', T.KW, null, 'majeur', `style de bordure ${fr}`);
  PROP_META[`border-${side}-color`] = M('bordure', T.COLOR, null, 'majeur', `couleur de bordure ${fr}`);
}
PROP_META['row-gap'] = M('espacement', T.NUM, 'spacing', 'majeur', 'gap vertical');
PROP_META['column-gap'] = M('espacement', T.NUM, 'spacing', 'majeur', 'gap horizontal');

const BOX_META = {
  w:  M('boite', T.NUM, 'box', 'majeur', 'largeur'),
  h:  M('boite', T.NUM, 'box', 'mineur', 'hauteur'),
  dx: M('boite', T.NUM, 'offset', 'mineur', 'décalage horizontal dans le parent'),
  dy: M('boite', T.NUM, 'offset', 'mineur', 'décalage vertical dans le parent')
};

// Propriétés héritées : si l'écart vient du parent, le répéter sur chaque
// descendant noie le rapport. On ne le signale que sur l'élément le plus haut.
const INHERITED = new Set([
  'color', 'font-family', 'font-size', 'font-weight', 'font-style',
  'line-height', 'letter-spacing', 'text-align', 'text-transform',
  'white-space', 'visibility', 'text-decoration-line'
]);

// Propriétés qui ne décrivent QUE la mise en forme du texte : sur un élément
// sans texte (une case à cocher vide, un conteneur d'icône) elles n'ont aucun
// effet visible, et elles ne font qu'hériter de l'ancêtre.
const TEXT_ONLY = new Set([
  'text-align', 'text-transform', 'white-space', 'letter-spacing',
  'line-height', 'text-decoration-line', 'text-overflow',
  'font-family', 'font-size', 'font-weight', 'font-style'
]);

const SEVERITIES = ['bloquant', 'majeur', 'mineur', 'info'];
const SEV_RANK = { bloquant: 0, majeur: 1, mineur: 2, info: 3 };

// ===========================================================================
// 3. Normalisation des valeurs
// ===========================================================================

const EPS = 0.02;

function normFontStack(v) {
  return String(v || '').toLowerCase().replace(/["']/g, '').split(',')
    .map((s) => s.trim()).filter(Boolean).join(', ');
}

function normColor(v) {
  const s = String(v == null ? '' : v).trim().toLowerCase();
  if (!s || s === 'none') return s;
  if (s === 'transparent') return 'transparent';
  let m = s.match(/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.%]+))?\s*\)$/);
  if (!m) return s;
  const [r, g, b] = [m[1], m[2], m[3]].map((x) => Math.round(parseFloat(x)));
  let a = m[4] == null ? 1 : (m[4].endsWith('%') ? parseFloat(m[4]) / 100 : parseFloat(m[4]));
  if (a === 0) return 'transparent';
  const hex = '#' + [r, g, b].map((x) => Math.max(0, Math.min(255, x)).toString(16).padStart(2, '0')).join('');
  return a >= 0.999 ? hex : `${hex} (opacité ${a.toFixed(2)})`;
}

function normLength(v) {
  const n = parseFloat(String(v));
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
}

function normShadow(v) {
  const s = String(v || '').trim();
  if (!s || s === 'none') return 'aucune';
  // couleurs normalisées + px arrondis au dixième
  return s.replace(/rgba?\([^)]*\)/g, (c) => normColor(c))
    .replace(/(-?[\d.]+)px/g, (_, n) => `${Math.round(parseFloat(n) * 10) / 10}px`)
    .replace(/\s+/g, ' ');
}

function normBgImage(v) {
  const s = String(v || '').trim();
  if (!s || s === 'none') return 'aucune';
  if (/^url\(/.test(s)) return 'url()'; // l'URL est de la donnée, pas de la forme
  return s.replace(/rgba?\([^)]*\)/g, (c) => normColor(c)).replace(/\s+/g, ' ');
}

function normValue(prop, v) {
  const meta = PROP_META[prop];
  if (!meta) return String(v == null ? '' : v);
  if (prop === 'background-image') return normBgImage(v);
  switch (meta.type) {
    case T.COLOR: return normColor(v);
    case T.FONT: return normFontStack(v);
    case T.SHADOW: return normShadow(v);
    case T.NUM: {
      const n = normLength(v);
      return n == null ? String(v).trim() : n;
    }
    case T.NUMLIST: {
      const s = String(v || '').trim();
      if (!s || s === 'none') return 'none';
      const parts = s.split(/\s+/);
      if (parts.every((p) => /px$/.test(p))) return parts.map((p) => Math.round(parseFloat(p) * 10) / 10);
      return s;
    }
    default: return String(v == null ? '' : v).trim();
  }
}

function fmt(prop, v) {
  if (v == null) return '—';
  if (Array.isArray(v)) return v.map((x) => `${x}px`).join(' ');
  const meta = PROP_META[prop];
  if (meta && meta.type === T.NUM && typeof v === 'number') {
    if (prop === 'font-weight' || prop === 'opacity' || prop.startsWith('flex-')) return String(v);
    return `${v}px`;
  }
  return String(v);
}

function valuesEqual(prop, a, b, tol) {
  const meta = PROP_META[prop];
  if (!meta) return String(a) === String(b);
  if (meta.type === T.NUM && typeof a === 'number' && typeof b === 'number') {
    const t = (tol[meta.tol] != null ? tol[meta.tol] : 0) + EPS;
    return Math.abs(a - b) <= t;
  }
  if (meta.type === T.NUMLIST && Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    const t = (tol[meta.tol] != null ? tol[meta.tol] : 0) + EPS;
    return a.every((x, i) => Math.abs(x - b[i]) <= t);
  }
  return String(a) === String(b);
}

// ===========================================================================
// 4. Extraction dans la page (exécuté par le navigateur)
// ===========================================================================

function pageExtract(cfg) {
  const { props, ignoreSelectors, maskSelectors, rootSelector, maxNodes } = cfg;

  const SKIP_TAGS = new Set([
    'script', 'style', 'link', 'meta', 'noscript', 'template', 'title', 'head',
    'br', 'wbr', 'source', 'track', 'param', 'base', 'col', 'colgroup'
  ]);
  const SVG_ROOTS = new Set(['svg']);

  function hash32(str) {
    let h = 0x811c9dc5;
    for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 0x01000193); }
    return (h >>> 0).toString(36);
  }
  const norm = (t) => String(t || '').replace(/\s+/g, ' ').trim();
  const matchesAny = (el, sels) => sels.some((s) => { try { return el.matches(s); } catch (e) { return false; } });

  const root = document.querySelector(rootSelector) || document.body;

  const nodes = [];
  const els = [];

  function classList(el) {
    const raw = el.getAttribute('class') || '';
    const cl = raw.split(/\s+/).filter(Boolean)
      // classes d'état injectées à l'exécution : instables entre deux rendus
      .filter((c) => !/^(turbo-|js-|ui-state-|is-active$|active$)/.test(c));
    cl.sort();
    return cl;
  }

  function keyOf(el) {
    const k = el.getAttribute('data-part') || el.getAttribute('data-testid') || el.getAttribute('data-test');
    if (k) return 'k:' + k;
    const id = el.id;
    // Les id porteurs de chiffres viennent d'un enregistrement (client_12) : instables.
    if (id && !/\d/.test(id)) return 'id:' + id;
    const ctrl = el.getAttribute('data-controller');
    if (ctrl) return null; // pas assez discriminant seul
    return null;
  }

  function labelOf(el, ownText, tag, cl) {
    const dp = el.getAttribute('data-part') || el.getAttribute('data-testid');
    if (dp) return dp;
    const aria = el.getAttribute('aria-label');
    if (aria) return `${tag} « ${norm(aria).slice(0, 40)} »`;
    if (ownText) return `${tag} « ${ownText.slice(0, 46)} »`;
    if (el.id && !/\d/.test(el.id)) return `${tag}#${el.id}`;
    const sem = cl.filter((c) => !/^(w-|h-|p[xytrbl]?-|m[xytrbl]?-|gap-|flex|grid|text-|font-|leading-|tracking-)/.test(c)).slice(0, 3);
    return sem.length ? `${tag}.${sem.join('.')}` : tag;
  }

  function ownTextOf(el) {
    let t = '';
    for (const n of el.childNodes) if (n.nodeType === 3) t += n.nodeValue;
    return norm(t);
  }

  function walk(el, parentIdx, parentRect, depth, masked, tableIdx) {
    if (nodes.length >= maxNodes) return;
    const tag = el.tagName ? el.tagName.toLowerCase() : '';
    if (!tag || SKIP_TAGS.has(tag)) return;
    if (matchesAny(el, ignoreSelectors)) return; // élément + sous-arbre écartés

    let cs;
    try { cs = getComputedStyle(el); } catch (e) { return; }
    if (cs.display === 'none') return;           // sous-arbre non rendu
    if (cs.visibility === 'hidden' && el.children.length === 0) return;

    const rect = el.getBoundingClientRect();
    const cl = classList(el);
    const sig = tag + (cl.length ? '.' + cl.join('.') : '');
    const parent = parentIdx >= 0 ? nodes[parentIdx] : null;
    const spath = hash32((parent ? parent.sp : '') + '>' + sig);

    const ownText = ownTextOf(el);
    const fullText = norm(el.textContent).slice(0, 400);

    const styles = props.map((p) => cs.getPropertyValue(p));

    const idx = nodes.length;
    // Rang parmi les frères de MÊME signature : identifie la colonne d'un
    // tableau, la position dans une liste répétée.
    let si = 0;
    if (parent) for (const k of parent.kids) if (nodes[k].sig === sig) si++;
    nodes.push({
      i: idx,
      p: parentIdx,
      d: depth,
      si,
      tbl: tableIdx,
      tag,
      cl,
      sig,
      sp: spath,
      key: keyOf(el),
      lbl: labelOf(el, ownText, tag, cl),
      tx: fullText,
      txh: hash32(fullText),
      ot: ownText.slice(0, 60),
      vis: rect.width > 0 && rect.height > 0,
      box: {
        w: Math.round(rect.width * 100) / 100,
        h: Math.round(rect.height * 100) / 100,
        dx: parentRect ? Math.round((rect.left - parentRect.left) * 100) / 100 : 0,
        dy: parentRect ? Math.round((rect.top - parentRect.top) * 100) / 100 : 0
      },
      st: styles,
      masked: masked,
      kids: []
    });
    els.push(el);
    if (parent) parent.kids.push(idx);

    if (SVG_ROOTS.has(tag)) return; // on ne descend pas dans les <svg>
    const nowMasked = masked || matchesAny(el, maskSelectors);
    if (nowMasked && !masked) {
      // masque : on garde l'élément, on ignore son contenu
      return;
    }
    const nextTable = tag === 'table' ? idx : tableIdx;
    for (const child of el.children) walk(child, idx, rect, depth + 1, nowMasked, nextTable);
  }

  walk(root, -1, null, 0, false, -1);

  // --- débordement horizontal ---------------------------------------------
  const vw = document.documentElement.clientWidth;
  const docOverflow = {
    viewport: vw,
    docScrollWidth: document.documentElement.scrollWidth,
    docClientWidth: document.documentElement.clientWidth,
    bodyScrollWidth: document.body ? document.body.scrollWidth : 0,
    bodyClientWidth: document.body ? document.body.clientWidth : 0
  };

  const beyondSet = new Set();
  for (let i = 0; i < els.length; i++) {
    const r = els[i].getBoundingClientRect();
    if (r.width > 0 && r.right > vw + 1) beyondSet.add(i);
  }
  const beyond = [];
  for (const i of beyondSet) {
    const n = nodes[i];
    if (n.p >= 0 && beyondSet.has(n.p)) continue; // on ne garde que le coupable le plus haut
    const r = els[i].getBoundingClientRect();
    beyond.push({ lbl: n.lbl, sig: n.sig.slice(0, 160), sp: n.sp, right: Math.round(r.right), width: Math.round(r.width), excess: Math.round(r.right - vw) });
  }
  beyond.sort((a, b) => b.excess - a.excess);

  // --- débordement INTERNE aux conteneurs ---------------------------------
  // `document.documentElement.scrollWidth === 390` ne prouve RIEN. Un conteneur
  // en `overflow-y: auto` fait calculer par le navigateur un `overflow-x: auto`
  // implicite (spec CSS Overflow : dès qu'un axe n'est pas `visible`, l'autre
  // devient `auto`). Le document ne déborde alors plus du tout, et pourtant le
  // tableau qu'il contient est tronqué. Mesuré : 41 pages coupaient leurs
  // tableaux en silence pendant que la sonde « document » affichait 46/47
  // conformes.
  //
  // On distingue donc, pour tout élément dont `scrollWidth > clientWidth` :
  //   - le conteneur défilant VOULU  : `overflow-x: auto|scroll` DÉCLARÉ dans
  //     la cascade (ou motif de tableau défilant accessible) → information ;
  //   - le conteneur qui ROGNE       : `overflow-x` calculé à auto/scroll sans
  //     être déclaré (héritage d'un `overflow-y`), ou `hidden`/`clip` → défaut.

  // Index des règles de la cascade qui déclarent un overflow horizontal.
  // Lire la DÉCLARATION est le seul moyen de connaître l'intention : la valeur
  // calculée, elle, est la même dans les deux cas.
  const ovRules = [];
  let sheetsReadable = 0, sheetsUnreadable = 0;
  const declaredX = (style) => {
    if (!style) return '';
    const own = String(style.getPropertyValue('overflow-x') || '').trim();
    if (own) return own.split(/\s+/)[0];
    const sh = String(style.getPropertyValue('overflow') || '').trim();
    return sh ? sh.split(/\s+/)[0] : '';
  };
  const visitRules = (list) => {
    for (const r of list) {
      if (r.selectorText && r.style) {
        const v = declaredX(r.style);
        if (v) ovRules.push({ sel: r.selectorText, v });
        continue;
      }
      if (r.cssRules) {
        // @media / @supports / @layer : on ne retient que ce qui s'applique ici
        const cond = r.conditionText || (r.media && r.media.mediaText) || '';
        if (cond) {
          let ok = true;
          try { ok = r.media ? window.matchMedia(cond).matches : (window.CSS && CSS.supports ? CSS.supports(cond) : true); }
          catch (e) { ok = true; }
          if (!ok) continue;
        }
        try { visitRules(Array.from(r.cssRules)); } catch (e) { /* illisible */ }
      }
    }
  };
  for (const s of Array.from(document.styleSheets)) {
    const owner = s.ownerNode;
    if (owner && owner.getAttribute && owner.getAttribute('data-style-diff') === '1') continue;
    try {
      const rules = s.cssRules;
      if (!rules) { sheetsUnreadable++; continue; }
      sheetsReadable++;
      visitRules(Array.from(rules));
    } catch (e) { sheetsUnreadable++; }
  }
  const declaredCache = new Map();
  function declaredOverflowX(el, idx) {
    if (declaredCache.has(idx)) return declaredCache.get(idx);
    const found = new Set();
    const inline = declaredX(el.style);
    if (inline) found.add(inline);
    for (const r of ovRules) {
      try { if (el.matches(r.sel)) found.add(r.v); } catch (e) { /* sélecteur exotique */ }
    }
    declaredCache.set(idx, found);
    return found;
  }
  // Motif « tableau défilant assumé » : la région focalisable au clavier qui
  // enveloppe un tableau large est une intention explicite, même sans classe.
  function assumedScroller(el) {
    if (el.getAttribute('tabindex') === '0' && (el.getAttribute('role') === 'region' || el.querySelector('table'))) return true;
    const cl = String(el.getAttribute('class') || '');
    return /(^|\s)(overflow-x-(auto|scroll)|overflow-(auto|scroll)|table-responsive|scroll-x)(\s|$)/.test(cl);
  }

  const clipped = [];
  const scrollers = [];
  for (let i = 0; i < els.length; i++) {
    const el = els[i];
    const n = nodes[i];
    if (!n.vis) continue;
    // < 24px de large : pastilles, `sr-only` (clip 1px), icônes — pas un vrai
    // conteneur, le débordement n'y veut rien dire.
    if (el.clientWidth < 24) continue;
    // Les contrôles de formulaire "débordent" dès que leur valeur dépasse leur
    // largeur : c'est leur fonctionnement normal, pas un défaut de mise en page.
    if (n.tag === 'input' || n.tag === 'textarea' || n.tag === 'select') continue;
    const excess = el.scrollWidth - el.clientWidth;
    if (excess < (cfg.clipMinExcess || 3)) continue;
    const csEl = getComputedStyle(el);
    if (csEl.textOverflow === 'ellipsis') continue; // troncature voulue
    const ox = csEl.overflowX;
    // `visible` : le contenu déborde mais reste lisible ; s'il sort du viewport
    // la sonde « beyond » s'en charge, avec le coupable le plus haut.
    if (ox === 'visible') continue;
    const decl = declaredOverflowX(el, i);
    const scrollable = (ox === 'auto' || ox === 'scroll');
    const declaredScroll = decl.has('auto') || decl.has('scroll');
    const entry = {
      lbl: n.lbl, sp: n.sp, sig: n.sig.slice(0, 160), i, p: n.p,
      scrollWidth: el.scrollWidth, clientWidth: el.clientWidth, excess,
      overflowX: ox,
      declared: Array.from(decl).join('/') || null,
      overflowY: csEl.overflowY,
      cssReadable: sheetsReadable > 0
    };
    if (scrollable && (declaredScroll || assumedScroller(el))) {
      entry.cause = 'defilant-voulu';
      scrollers.push(entry);
      continue;
    }
    if (scrollable) {
      // Cas mesuré : `overflow-y: auto` déclaré, `overflow-x` jamais écrit,
      // calculé à `auto` par le navigateur. Rien ne signale à l'utilisateur
      // qu'il reste du contenu à droite : la colonne est perdue.
      entry.cause = 'rogne-implicite';
    } else {
      entry.cause = decl.has(ox) ? 'rogne-declare' : 'rogne-non-declare';
    }
    clipped.push(entry);
  }
  // On ne garde que le conteneur le plus HAUT d'une même chaîne : un tableau
  // coupé dans un wrapper coupé dans une carte coupée = un seul défaut.
  const clipIdx = new Set(clipped.map((c) => c.i));
  const clipTop = clipped.filter((c) => {
    for (let p = c.p; p >= 0; p = nodes[p].p) if (clipIdx.has(p)) return false;
    return true;
  });
  clipped.length = 0;
  for (const c of clipTop) clipped.push(c);
  clipped.sort((a, b) => b.excess - a.excess);
  scrollers.sort((a, b) => b.excess - a.excess);

  // --- contrôles de saisie écrasés ----------------------------------------
  // Un écran « conforme à 390 px » peut rendre ses `input` à 18 px de large :
  // le document ne déborde pas, la charte est respectée, et le formulaire est
  // inutilisable. On mesure la boîte RENDUE de chaque contrôle.
  const CONTROL_TAGS = new Set(['input', 'select', 'textarea', 'button']);
  const controls = [];
  for (let i = 0; i < els.length; i++) {
    const n = nodes[i];
    if (!CONTROL_TAGS.has(n.tag)) continue;
    const el = els[i];
    const type = String(el.getAttribute('type') || '').toLowerCase();
    if (type === 'hidden') continue;
    if (!n.vis) continue;
    const r = el.getBoundingClientRect();
    // Un contrôle VOLONTAIREMENT masqué (`sr-only`, radio de 1×1px derrière une
    // pastille de couleur, `opacity: 0` sous un label stylé) n'est pas un
    // contrôle écrasé : c'est un motif d'accessibilité courant. On le sort de
    // la mesure, sinon chaque sélecteur de couleur remonte en défaut.
    let csC = null;
    try { csC = getComputedStyle(el); } catch (e) { /* noop */ }
    const cls = String(el.getAttribute('class') || '');
    const visuallyHidden = !!csC && (
      csC.opacity === '0'
      || (csC.clipPath && csC.clipPath !== 'none')
      || (csC.clip && csC.clip !== 'auto')
      || /(^|\s)(sr-only|visually-hidden|screen-reader-only)(\s|$)/.test(cls)
      || (r.width <= 2 && r.height <= 2)
    );
    if (visuallyHidden) continue;
    controls.push({
      lbl: n.lbl, sp: n.sp, sig: n.sig.slice(0, 160), tag: n.tag, type: type || null,
      name: el.getAttribute('name') || null,
      w: Math.round(r.width * 100) / 100, h: Math.round(r.height * 100) / 100,
      tiny: type === 'checkbox' || type === 'radio',
      pressable: n.tag === 'button' || type === 'submit' || type === 'button' || type === 'reset' || type === 'image'
    });
  }

  // --- feuilles de style ---------------------------------------------------
  const sheets = [];
  for (const s of Array.from(document.styleSheets)) {
    const owner = s.ownerNode;
    if (owner && owner.getAttribute && owner.getAttribute('data-style-diff') === '1') continue;
    let rules = null, cross = false;
    try { rules = s.cssRules ? s.cssRules.length : 0; } catch (e) { cross = true; }
    sheets.push({
      href: s.href || null,
      inline: !s.href,
      rules,
      cross,
      media: String(s.media && s.media.mediaText || ''),
      owner: owner && owner.tagName ? owner.tagName.toLowerCase() : null
    });
  }
  const linkHrefs = Array.from(document.querySelectorAll('link[rel~="stylesheet"], link[rel="preload"][as="style"]'))
    .map((l) => l.href).filter(Boolean);

  let fonts = [];
  try { fonts = Array.from(document.fonts).map((f) => `${f.family} ${f.weight} ${f.style}`); } catch (e) { /* noop */ }
  fonts = Array.from(new Set(fonts)).sort();

  return {
    url: location.href,
    title: document.title,
    nodes: nodes.map((n) => { const { kids, ...rest } = n; return { ...rest, kids }; }),
    overflow: {
      doc: docOverflow,
      beyond: beyond.slice(0, 12),
      clipped: clipped.slice(0, 12),
      clipped_total: clipped.length,
      scrollers: scrollers.slice(0, 8),
      scrollers_total: scrollers.length,
      css_readable: sheetsReadable > 0,
      sheets_unreadable: sheetsUnreadable
    },
    controls,
    css: { sheets, linkHrefs, fonts }
  };
}

// ===========================================================================
// 5. Appariement des deux arbres
// ===========================================================================

function jaccard(a, b) {
  if (!a.length && !b.length) return 1;
  const sa = new Set(a);
  let inter = 0;
  for (const x of b) if (sa.has(x)) inter++;
  return inter / (a.length + b.length - inter);
}

function similarity(a, b) {
  let s = 0;
  s += 0.55 * jaccard(a.cl, b.cl);
  s += a.tag === b.tag ? 0.20 : 0;
  s += a.kids.length === b.kids.length ? 0.10 : (Math.abs(a.kids.length - b.kids.length) <= 1 ? 0.05 : 0);
  s += a.ot && a.ot === b.ot ? 0.15 : 0;
  return s;
}

/**
 * Aligne deux arbres et renvoie {pairs, missing, added, repeats}.
 * `missing` = présent en maquette, absent de l'app. `added` = l'inverse.
 */
function alignTrees(A, B) {
  const pairs = [];
  const missing = [];
  const added = [];
  const repeats = [];

  const byIdxA = A.nodes, byIdxB = B.nodes;
  if (!byIdxA.length || !byIdxB.length) return { pairs, missing, added, repeats };

  const rootPair = { a: byIdxA[0], b: byIdxB[0], parent: null };
  pairs.push(rootPair);
  const queue = [rootPair];
  const wrappers = [];

  // Un côté a enveloppé toute la zone dans un conteneur de plus (un <form>
  // autour des cartes de réglages, un <turbo-frame> autour d'une liste).
  // On le traverse : sinon tout le contenu passerait pour absent.
  const bestSim = (node, list) => list.reduce((m, k) => Math.max(m, similarity(node, k)), 0);
  const flatten = (kidsX, kidsY, nodesX, side) => {
    let kids = kidsX, guard = 0;
    while (guard++ < 3 && kids.length === 1 && kids[0].kids.length > 0 && kidsY.length) {
      const w = kids[0];
      const inner = w.kids.map((i) => nodesX[i]);
      // Le conteneur ne ressemble à rien d'en face, mais son contenu si :
      // c'est une enveloppe. Sinon on ne descend pas (ce serait décaler
      // l'arbre d'un cran et tout comparer de travers).
      const simSelf = bestSim(w, kidsY);
      const simInner = inner.reduce((m, k) => Math.max(m, bestSim(k, kidsY)), 0);
      if (simSelf >= FUZZY_MIN || simInner < FUZZY_MIN || simInner <= simSelf) break;
      wrappers.push({ side, node: w, inner: inner[0] });
      kids = inner;
    }
    return kids;
  };

  while (queue.length) {
    const cur = queue.shift();
    let kidsA = cur.a.kids.map((i) => byIdxA[i]);
    let kidsB = cur.b.kids.map((i) => byIdxB[i]);
    kidsB = flatten(kidsB, kidsA, byIdxB, 'app');
    kidsA = flatten(kidsA, kidsB, byIdxA, 'maquette');
    const res = alignChildren(kidsA, kidsB, byIdxA, byIdxB, wrappers);
    for (const [na, nb] of res.matched) {
      const p = { a: na, b: nb, parent: cur };
      pairs.push(p);
      queue.push(p);
    }
    for (const n of res.missing) missing.push({ node: n, parent: cur, side: 'mockup' });
    for (const n of res.added) added.push({ node: n, parent: cur, side: 'app' });
    for (const r of res.repeats) repeats.push({ ...r, parent: cur });
  }
  return { pairs, missing, added, repeats, wrappers };
}

function alignChildren(kidsA, kidsB, allA, allB, wrappers) {
  const matched = [];
  const repeats = [];
  const usedA = new Set(), usedB = new Set();

  // 1) clé explicite (data-part / data-testid / id stable)
  const keyB = new Map();
  kidsB.forEach((n, i) => { if (n.key) { if (!keyB.has(n.key)) keyB.set(n.key, []); keyB.get(n.key).push(i); } });
  kidsA.forEach((n, i) => {
    if (!n.key) return;
    const bucket = keyB.get(n.key);
    if (bucket && bucket.length) {
      const j = bucket.shift();
      matched.push([n, kidsB[j]]); usedA.add(i); usedB.add(j);
    }
  });

  // 2) signature structurelle identique (balise + classes normalisées),
  //    appariée dans l'ordre de fratrie
  const sigA = new Map(), sigB = new Map();
  kidsA.forEach((n, i) => { if (usedA.has(i)) return; if (!sigA.has(n.sig)) sigA.set(n.sig, []); sigA.get(n.sig).push(i); });
  kidsB.forEach((n, j) => { if (usedB.has(j)) return; if (!sigB.has(n.sig)) sigB.set(n.sig, []); sigB.get(n.sig).push(j); });

  const sigBothSides = new Map(); // sig -> {countMockup, countApp}
  for (const [sig, listA] of sigA) {
    const listB = sigB.get(sig);
    if (!listB || !listB.length) continue;
    const k = Math.min(listA.length, listB.length);
    for (let x = 0; x < k; x++) { matched.push([kidsA[listA[x]], kidsB[listB[x]]]); usedA.add(listA[x]); usedB.add(listB[x]); }
    // Le surplus n'est PAS consommé ici : il peut correspondre à un élément
    // dont seule une classe pilotée par la donnée a changé (badge de statut).
    // On ne le classera "répétition" qu'à la fin, s'il reste orphelin.
    if (listA.length !== listB.length) sigBothSides.set(sig, { countMockup: listA.length, countApp: listB.length });
  }

  // 3) enveloppe transparente : un côté a inséré un conteneur intermédiaire
  //    (cible de Turbo Stream, <form> de button_to…). On traverse plutôt que
  //    de déclarer un élément manquant ET un élément ajouté.
  const unwrap = (leftFrom, leftTo, nodesTo, fromKids, toKids, usedFrom, usedTo, toIsApp) => {
    for (const i of leftFrom) {
      if (usedFrom.has(i)) continue;
      for (const j of leftTo) {
        if (usedTo.has(j)) continue;
        // On descend une chaîne de conteneurs à enfant unique : button_to
        // produit <form><button><span>, soit deux niveaux de plus.
        let only = toKids[j], depth = 0, ok = false;
        while (only.kids.length === 1 && depth++ < 3) {
          only = nodesTo[only.kids[0]];
          if (similarity(fromKids[i], only) >= FUZZY_MIN) { ok = true; break; }
        }
        if (!ok) continue;
        matched.push(toIsApp ? [fromKids[i], only] : [only, fromKids[i]]);
        usedFrom.add(i); usedTo.add(j);
        if (wrappers) wrappers.push({ side: toIsApp ? 'app' : 'maquette', node: toKids[j], inner: only });
        break;
      }
    }
  };
  let leftA = kidsA.map((n, i) => i).filter((i) => !usedA.has(i));
  let leftB = kidsB.map((n, j) => j).filter((j) => !usedB.has(j));
  if (allA && allB) {
    unwrap(leftA, leftB, allB, kidsA, kidsB, usedA, usedB, true);
    leftA = kidsA.map((n, i) => i).filter((i) => !usedA.has(i));
    leftB = kidsB.map((n, j) => j).filter((j) => !usedB.has(j));
    unwrap(leftB, leftA, allA, kidsB, kidsA, usedB, usedA, false);
  }

  // 4) rattrapage approximatif sur ce qui reste
  leftA = kidsA.map((n, i) => i).filter((i) => !usedA.has(i));
  leftB = kidsB.map((n, j) => j).filter((j) => !usedB.has(j));
  const cands = [];
  for (const i of leftA) for (const j of leftB) {
    const s = similarity(kidsA[i], kidsB[j]);
    if (s >= FUZZY_MIN) cands.push([s, i, j]);
  }
  cands.sort((x, y) => y[0] - x[0]);
  for (const [, i, j] of cands) {
    if (usedA.has(i) || usedB.has(j)) continue;
    matched.push([kidsA[i], kidsB[j]]); usedA.add(i); usedB.add(j);
  }

  // 5) repli positionnel : même balise, même rang parmi les restants.
  //    Un badge dont la classe de couleur dépend de la donnée
  //    (bg-amber / bg-emerald) reste le même élément.
  const restA = kidsA.map((n, i) => i).filter((i) => !usedA.has(i));
  const restB = kidsB.map((n, j) => j).filter((j) => !usedB.has(j));
  for (const i of restA) {
    const j = restB.find((x) => !usedB.has(x) && kidsB[x].tag === kidsA[i].tag);
    if (j == null) continue;
    matched.push([kidsA[i], kidsB[j]]); usedA.add(i); usedB.add(j);
  }

  // 6) ce qui reste et dont la signature existe des DEUX côtés en nombre
  //    différent est une répétition : une ligne de tableau en plus ou en
  //    moins, c'est du jeu de données, pas un écart de forme.
  const missing = [], added = [];
  const repeatSeen = new Set();
  const classify = (n, into) => {
    const rep = sigBothSides.get(n.sig);
    if (rep) {
      if (!repeatSeen.has(n.sig)) {
        repeatSeen.add(n.sig);
        repeats.push({ sig: n.sig, label: n.lbl, countMockup: rep.countMockup, countApp: rep.countApp });
      }
      return;
    }
    into.push(n);
  };
  kidsA.forEach((n, i) => { if (!usedA.has(i)) classify(n, missing); });
  kidsB.forEach((n, j) => { if (!usedB.has(j)) classify(n, added); });
  return { matched, missing, added, repeats };
}

// ===========================================================================
// 6. Comparaison des styles
// ===========================================================================

/**
 * Une propriété qui VARIE déjà entre éléments jumeaux d'un même côté (la
 * pastille de statut verte/orange/rouge, l'avatar coloré par contact, le
 * montant en rouge s'il est dû) est pilotée par la donnée, pas par la charte.
 * On ne la compare pas d'un côté à l'autre — sauf si les deux éléments
 * portent exactement le même texte, auquel cas l'écart redevient un vrai écart.
 */
function dataDrivenMap(nodes) {
  const flags = new Map();
  const flagOf = (idx) => {
    let f = flags.get(idx);
    if (!f) { f = new Uint8Array(PROPS.length); flags.set(idx, f); }
    return f;
  };

  for (const parent of nodes) {
    if (!parent.kids || parent.kids.length < 2) continue;
    // Groupes de frères de même balise : les lignes d'un tableau, les cartes
    // d'une liste, les items d'un menu.
    const groups = new Map();
    for (const k of parent.kids) {
      const t = nodes[k].tag;
      if (!groups.has(t)) groups.set(t, []);
      groups.get(t).push(k);
    }
    for (const members of groups.values()) {
      if (members.length < 2) continue;
      // On aligne les sous-arbres des frères par chemin POSITIONNEL (et non
      // par classes : c'est justement la classe qui change avec la donnée).
      const buckets = new Map();
      const collect = (idx, rel) => {
        const n = nodes[idx];
        let b = buckets.get(rel);
        if (!b) { b = { first: n.st, list: [idx], varies: new Uint8Array(PROPS.length) }; buckets.set(rel, b); }
        else {
          b.list.push(idx);
          for (let i = 0; i < PROPS.length; i++) if (!b.varies[i] && b.first[i] !== n.st[i]) b.varies[i] = 1;
        }
        const seen = new Map();
        for (const k of n.kids) {
          const t = nodes[k].tag;
          const r = seen.get(t) || 0; seen.set(t, r + 1);
          collect(k, `${rel}/${t}${r}`);
        }
      };
      for (const m of members) collect(m, '');
      for (const b of buckets.values()) {
        if (b.list.length < 2) continue;
        for (let i = 0; i < PROPS.length; i++) {
          if (!b.varies[i]) continue;
          for (const idx of b.list) flagOf(idx)[i] = 1;
        }
      }
    }
  }
  return flags;
}
const variesAt = (flags, node, i) => {
  const f = flags.get(node.i);
  return !!(f && f[i]);
};

function compareTrees(A, B, tol, ctx) {
  const { pairs, missing, added, repeats, wrappers } = alignTrees(A, B);
  const raw = [];
  const ddA = dataDrivenMap(A.nodes);
  const ddB = dataDrivenMap(B.nodes);
  const pairByA = new Map();
  for (const p of pairs) pairByA.set(p.a.i, p);

  // --- structure -----------------------------------------------------------
  // Un élément peut manquer à un endroit et apparaître à un autre : la ligne
  // de facture qui propose « Créer un avoir » n'est pas la même des deux côtés,
  // la carte du pipeline n'est pas dans la même colonne. L'élément existe bien
  // dans l'app : c'est un écart de DONNÉES, pas une brique absente.
  const visMissing = missing.filter((m) => m.node.vis);
  const visAdded = added.filter((m) => m.node.vis);
  const takenAdded = new Set();
  const moved = [];
  for (const m of visMissing) {
    const twin = visAdded.find((x) => !takenAdded.has(x) && jaccard(m.node.cl, x.node.cl) >= 0.7);
    if (!twin) continue;
    takenAdded.add(twin);
    m.moved = twin;
    const extra = twin.node.cl.filter((c) => !m.node.cl.includes(c));
    const gone = m.node.cl.filter((c) => !twin.node.cl.includes(c));
    moved.push({
      node: m.node, twin: twin.node,
      tagChanged: m.node.tag !== twin.node.tag,
      note: (extra.length || gone.length)
        ? ` (classes${extra.length ? ' en plus côté app : ' + extra.join(' ') : ''}${gone.length ? ' absentes côté app : ' + gone.join(' ') : ''})`
        : ''
    });
  }
  for (const mv of moved) {
    // Même bloc de part et d'autre : soit il a simplement changé de place
    // (donnée), soit il a changé de BALISE — et ça, ça se signale.
    raw.push({
      severity: mv.tagChanged ? 'majeur' : 'info',
      category: mv.tagChanged ? 'structure' : 'donnees',
      kind: mv.tagChanged ? 'tag-change' : 'moved',
      property: null, element: mv.node.lbl, spath: 'moved:' + mv.node.sp,
      sig: mv.node.sig.slice(0, 200),
      mockup: `<${mv.node.tag}>`, app: `<${mv.twin.tag}>`,
      message: mv.tagChanged
        ? `${mv.node.lbl} : balise <${mv.node.tag}> en maquette, <${mv.twin.tag}> dans l'app${mv.note}`
        : `${mv.node.lbl} : présent des deux côtés mais pas au même endroit${mv.note} — dépend de la donnée`,
      context: null
    });
  }

  for (const m of missing) {
    if (!m.node.vis || m.moved) continue;
    raw.push({
      severity: 'bloquant', category: 'structure', kind: 'missing',
      property: null, element: m.node.lbl, spath: m.node.sp,
      sig: m.node.sig.slice(0, 200), mockup: 'présent', app: 'absent',
      message: `élément absent de l'app : ${m.node.lbl}${m.node.tx ? ` (texte maquette : « ${trunc(m.node.tx, 60)} »)` : ''}`,
      context: m.parent ? m.parent.a.lbl : null
    });
  }
  for (const m of added) {
    if (!m.node.vis || takenAdded.has(m)) continue;
    raw.push({
      severity: 'majeur', category: 'structure', kind: 'added',
      property: null, element: m.node.lbl, spath: m.node.sp,
      sig: m.node.sig.slice(0, 200), mockup: 'absent', app: 'présent',
      message: `élément ajouté dans l'app, absent de la maquette : ${m.node.lbl}${m.node.tx ? ` (texte : « ${trunc(m.node.tx, 60)} »)` : ''}`,
      context: m.parent ? m.parent.b.lbl : null
    });
  }
  for (const r of repeats) {
    raw.push({
      severity: 'info', category: 'donnees', kind: 'repeat',
      property: null, element: r.label, spath: 'rep:' + r.sig,
      mockup: `${r.countMockup} occurrence(s)`, app: `${r.countApp} occurrence(s)`,
      message: `${r.label} : ${r.countApp} occurrence(s) dans l'app contre ${r.countMockup} en maquette (différence de jeu de données)`,
      context: r.parent ? r.parent.a.lbl : null
    });
  }

  // --- styles --------------------------------------------------------------
  const boxDiffsByPair = new Map(); // pair -> {prop: delta}
  const offsetsByParent = new Map(); // pair parent -> deltas déjà signalés
  const styleDiffsByPair = new Map(); // pair -> {prop: "va→vb"} pour l'héritage
  for (const w of wrappers || []) {
    raw.push({
      severity: 'info', category: 'structure', kind: 'wrapper',
      property: null, element: w.node.lbl, spath: 'wrap:' + w.node.sp,
      sig: w.node.sig.slice(0, 200),
      mockup: w.side === 'app' ? 'absent' : 'présent', app: w.side === 'app' ? 'présent' : 'absent',
      message: `conteneur intermédiaire présent uniquement côté ${w.side} autour de ${w.inner.lbl} : ${w.node.lbl} (sans effet visuel, la comparaison le traverse)`,
      context: null
    });
  }

  for (const p of pairs) {
    const a = p.a, b = p.b;
    if (!a.vis || !b.vis) continue;
    const sameTextPair = a.txh === b.txh;

    for (let i = 0; i < PROPS.length; i++) {
      const prop = PROPS[i];
      const meta = PROP_META[prop];
      if (!meta) continue;
      // Propriété pilotée par la donnée : on ne la compare que si les deux
      // éléments portent le même texte (alors l'écart redevient interprétable),
      // et on le dit dans le rapport car la cause peut rester la donnée.
      const dataDriven = variesAt(ddA, a, i) || variesAt(ddB, b, i);
      if (!sameTextPair && dataDriven) continue;
      const va = normValue(prop, a.st[i]);
      const vb = normValue(prop, b.st[i]);
      if (valuesEqual(prop, va, vb, tol)) continue;
      if (TEXT_ONLY.has(prop) && !a.tx && !b.tx) continue; // aucun texte à mettre en forme
      // Héritage : si un ancêtre porte déjà exactement le même écart, c'est
      // la même cause — on ne le répète pas sur toute la descendance.
      if (INHERITED.has(prop)) {
        const stamp = `${va}→${vb}`;
        let inherited = false;
        for (let anc = p.parent; anc; anc = anc.parent) {
          const sd = styleDiffsByPair.get(anc);
          if (sd && sd[prop] === stamp) { inherited = true; break; }
        }
        let own = styleDiffsByPair.get(p);
        if (!own) { own = {}; styleDiffsByPair.set(p, own); }
        own[prop] = stamp;
        if (inherited) continue;
      }
      const demoted = dataDriven && meta.sev !== 'mineur';
      const tagNote = a.tag !== b.tag ? ` (balise <${a.tag}> en maquette, <${b.tag}> dans l'app)` : '';
      raw.push({
        severity: demoted ? 'mineur' : meta.sev, category: meta.cat, kind: 'style',
        property: prop, element: a.lbl, spath: a.sp, sig: a.sig.slice(0, 200),
        tags: a.tag === b.tag ? a.tag : `${a.tag}>${b.tag}`,
        mockup: fmt(prop, va), app: fmt(prop, vb),
        message: `${a.lbl} : ${meta.fr} ${fmt(prop, vb)} au lieu de ${fmt(prop, va)}${tagNote}`
          + (dataDriven ? ' — cette propriété varie déjà d\'une ligne à l\'autre, la cause peut être la donnée' : ''),
        context: p.parent ? p.parent.a.lbl : null
      });
    }

    // --- boîte ---
    // Un tableau en `table-layout: auto` répartit ses largeurs selon le
    // contenu : si les données diffèrent, toutes les colonnes bougent et
    // aucune de ces largeurs n'est un écart de style.
    let inVariableTable = false;
    if (a.tbl >= 0) {
      const tp = pairByA.get(a.tbl);
      if (!tp || tp.a.txh !== tp.b.txh) inVariableTable = true;
    }
    const sameText = a.txh === b.txh;
    const deltas = {};
    for (const key of ['w', 'h', 'dx', 'dy']) {
      const meta = BOX_META[key];
      const t = tol[meta.tol] + EPS;
      const d = b.box[key] - a.box[key];
      if (Math.abs(d) <= t) continue;
      deltas[key] = d;
      if (inVariableTable) continue;
      if (BOX_REQUIRES_SAME_TEXT && !sameText) continue; // la donnée pousse la boîte
      // Une POSITION dépend de tout ce qui précède dans le parent : elle n'est
      // interprétable que si le parent entier a le même contenu des deux côtés.
      if ((key === 'dx' || key === 'dy') && !(p.parent && p.parent.a.txh === p.parent.b.txh)) continue;
      // Un décalage se propage aussi aux frères SUIVANTS : un bloc qui grandit
      // de 24 px pousse tout ce qui vient après. On ne signale que la première
      // occurrence sous un même parent.
      if (key === 'dx' || key === 'dy') {
        let seen = offsetsByParent.get(p.parent);
        if (!seen) { seen = []; offsetsByParent.set(p.parent, seen); }
        if (seen.some((e) => e.key === key && Math.abs(e.d - d) <= 1.5)) continue;
        seen.push({ key, d });
      }
      // cascade : si un ancêtre porte déjà le même écart, on ne répète pas
      let cascade = false;
      for (let anc = p.parent; anc; anc = anc.parent) {
        const ad = boxDiffsByPair.get(anc);
        if (ad && ad[key] != null && Math.abs(ad[key] - d) <= 1.5) { cascade = true; break; }
      }
      if (cascade) continue;
      raw.push({
        severity: meta.sev, category: 'boite', kind: 'box',
        property: key, element: a.lbl, spath: a.sp, sig: a.sig.slice(0, 200),
        mockup: `${a.box[key]}px`, app: `${b.box[key]}px`,
        message: `${a.lbl} : ${meta.fr} ${b.box[key]}px au lieu de ${a.box[key]}px (${d > 0 ? '+' : ''}${Math.round(d)}px)`,
        context: p.parent ? p.parent.a.lbl : null
      });
    }
    boxDiffsByPair.set(p, deltas);

    // --- contrôle écrasé PAR RAPPORT À LA MAQUETTE ---
    // La comparaison de boîte ci-dessus est tolérante et se tait quand les
    // textes diffèrent. Un champ que la maquette montrait normal et que l'app
    // rend à un tiers de sa largeur n'est pas une nuance de gabarit : le
    // formulaire est cassé, et ça se dit fort.
    const cc = (ctx && ctx.controls) || DEFAULT_CONTROLS;
    const isCtl = (n) => n.tag === 'input' || n.tag === 'select' || n.tag === 'textarea' || n.tag === 'button';
    if (isCtl(a) && isCtl(b) && a.box.w >= cc.crushed_px
        && b.box.w < a.box.w * cc.shrink_ratio && a.box.w - b.box.w > 8) {
      raw.push({
        severity: 'bloquant', category: 'controle', kind: 'control-shrunk',
        property: 'w', element: a.lbl, spath: 'ctlw:' + a.sp, sig: a.sig.slice(0, 200),
        mockup: `${a.box.w}px`, app: `${b.box.w}px`,
        message: `${a.lbl} : <${b.tag}> rendu à ${b.box.w}px de large dans l'app contre ${a.box.w}px en maquette`
          + ` (${Math.round(100 * b.box.w / a.box.w)}% de la largeur attendue) — la maquette le montrait normal, l'app l'a écrasé`,
        context: p.parent ? p.parent.a.lbl : null
      });
    }
  }

  const stats = {
    nodes_mockup: A.nodes.length,
    nodes_app: B.nodes.length,
    matched: pairs.length,
    missing: missing.filter((m) => m.node.vis).length,
    added: added.filter((m) => m.node.vis).length
  };
  return { raw, stats };
}

function trunc(s, n) { s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }

// ===========================================================================
// 7. Débordement + feuilles de style étrangères
// ===========================================================================

function analyseOverflow(A, B, viewport) {
  const out = [];
  const mkSide = (side, data) => {
    const doc = data.overflow.doc;
    const excess = doc.docScrollWidth - doc.docClientWidth;
    return { side, excess, doc, beyond: data.overflow.beyond, clipped: data.overflow.clipped };
  };
  const m = mkSide('maquette', A), a = mkSide('app', B);

  if (a.excess > 1 || m.excess > 1) {
    const both = a.excess > 1 && m.excess > 1;
    const who = both ? 'la maquette ET l\'app' : (a.excess > 1 ? "l'app" : 'la maquette');
    const worst = (a.excess > 1 ? a : m);
    const culprits = worst.beyond.slice(0, 4)
      .map((c) => `${c.lbl} dépasse de ${c.excess}px`).join(' ; ');
    out.push({
      severity: a.excess > 1 ? 'bloquant' : 'majeur',
      category: 'debordement', kind: 'overflow-doc',
      property: null, element: 'page', spath: 'overflow:doc',
      mockup: m.excess > 1 ? `déborde de ${m.excess}px` : 'pas de débordement',
      app: a.excess > 1 ? `déborde de ${a.excess}px` : 'pas de débordement',
      message: `débordement horizontal en ${viewport.name} (${viewport.width}px) sur ${who} : la page fait ${worst.doc.docScrollWidth}px de large pour ${worst.doc.docClientWidth}px visibles${culprits ? `. Coupable(s) : ${culprits}` : ''}`,
      context: null
    });
  }

  // Éléments dépassant du viewport côté app SANS débordement du document :
  // si le document déborde déjà, tout le reste n'en est que la conséquence et
  // l'écart a été signalé au-dessus avec ses coupables.
  const mockupBeyond = new Set(A.overflow.beyond.map((c) => c.sp));
  for (const c of (a.excess > 1 ? [] : B.overflow.beyond.slice(0, 6))) {
    if (mockupBeyond.has(c.sp)) continue; // déjà comme ça en maquette : signalé plus haut
    out.push({
      severity: 'majeur', category: 'debordement', kind: 'overflow-el',
      property: null, element: c.lbl, spath: 'overflow:' + c.sp,
      mockup: 'dans le viewport', app: `dépasse de ${c.excess}px`,
      message: `${c.lbl} sort du viewport ${viewport.name} de ${c.excess}px dans l'app (largeur ${c.width}px), alors qu'il tient en maquette`,
      context: null
    });
  }
  // --- conteneurs qui rognent ---------------------------------------------
  // Indépendant du débordement du document : c'est même le cas dangereux, celui
  // où `documentElement.scrollWidth === viewport` et où le contenu est perdu
  // quand même. On dit lequel des deux cas on a rencontré, sinon la correction
  // est un jeu de devinettes.
  const docQuiet = a.excess <= 1;
  const mockupClipped = new Map((A.overflow.clipped || []).map((c) => [c.sp, c]));
  const CAUSE_FR = {
    'rogne-implicite': "overflow-x calculé à « %s » sans jamais avoir été déclaré : c'est le navigateur qui l'a dérivé d'un overflow-y (%s). Rien n'indique à l'utilisateur qu'il reste du contenu à droite",
    'rogne-declare': "overflow-x: %s déclaré dans la feuille de style : le contenu est coupé net",
    'rogne-non-declare': "overflow-x calculé à « %s » (déclaration introuvable dans la cascade) : le contenu est coupé net"
  };
  for (const c of (B.overflow.clipped || []).slice(0, 6)) {
    const twin = mockupClipped.get(c.sp);
    const cause = (CAUSE_FR[c.cause] || 'overflow-x: %s').replace('%s', c.overflowX).replace('%s', c.overflowY);
    out.push({
      severity: c.cssReadable ? 'bloquant' : 'majeur',
      category: 'debordement', kind: c.cause === 'rogne-implicite' ? 'clip-implicite' : 'clip-declare',
      property: null, element: c.lbl, spath: 'clip:' + c.sp, sig: c.sig,
      mockup: twin ? `coupé aussi (${twin.scrollWidth}px dans ${twin.clientWidth}px)` : 'pas de coupe',
      app: `contenu ${c.scrollWidth}px dans ${c.clientWidth}px`,
      message: `${c.lbl} : contenu coupé en ${viewport.name} — ${c.scrollWidth}px de contenu pour ${c.clientWidth}px visibles (${c.excess}px perdus). ${cause}.`
        + (docQuiet ? ` Le document, lui, ne déborde pas (scrollWidth ${a.doc.docScrollWidth}px = viewport) : ce défaut est INVISIBLE pour la sonde « page ».` : '')
        + (twin ? ' La maquette coupe au même endroit.' : '')
        + (c.cssReadable ? '' : ' (cascade illisible depuis la page : la déclaration n\'a pas pu être vérifiée, gravité abaissée)'),
      context: null
    });
  }
  const clipExtra = (B.overflow.clipped_total || 0) - Math.min(6, (B.overflow.clipped || []).length);
  if (clipExtra > 0) {
    out.push({
      severity: 'majeur', category: 'debordement', kind: 'clip-reste',
      property: null, element: 'page', spath: 'clip:reste',
      mockup: '—', app: `${clipExtra} conteneur(s) de plus`,
      message: `${clipExtra} autre(s) conteneur(s) rognent leur contenu en ${viewport.name} (seuls les ${Math.min(6, B.overflow.clipped.length)} plus larges sont détaillés)`,
      context: null
    });
  }
  // Maquette qui rogne alors que l'app tient : c'est la maquette qu'il faut
  // corriger, et ça se dit avant que le code ne la recopie.
  const appClipped = new Set((B.overflow.clipped || []).map((c) => c.sp));
  for (const c of (A.overflow.clipped || []).slice(0, 3)) {
    if (appClipped.has(c.sp)) continue;
    out.push({
      severity: 'majeur', category: 'debordement', kind: 'clip-maquette',
      property: null, element: c.lbl, spath: 'clipm:' + c.sp, sig: c.sig,
      mockup: `contenu ${c.scrollWidth}px dans ${c.clientWidth}px`, app: 'pas de coupe',
      message: `${c.lbl} : c'est la MAQUETTE qui coupe son contenu en ${viewport.name} (${c.excess}px perdus, ${c.cause}) — l'app, elle, tient`,
      context: null
    });
  }
  // Conteneurs défilants assumés : information. Un tableau qui défile
  // horizontalement est une décision, pas un défaut — mais elle doit être
  // visible dans le rapport pour qu'on sache que le tableau ne tient pas.
  for (const c of (B.overflow.scrollers || []).slice(0, 5)) {
    out.push({
      severity: 'info', category: 'debordement', kind: 'scroll-voulu',
      property: null, element: c.lbl, spath: 'scroll:' + c.sp, sig: c.sig,
      mockup: '—', app: `défile sur ${c.excess}px`,
      message: `${c.lbl} : conteneur défilant VOULU (overflow-x: ${c.declared || c.overflowX} déclaré), ${c.scrollWidth}px de contenu pour ${c.clientWidth}px visibles — information, pas un défaut`,
      context: null
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Contrôles de saisie : taille rendue
// ---------------------------------------------------------------------------

/**
 * Un écran peut être déclaré conforme (pas de débordement, charte respectée) et
 * rendre ses `input` à 18 px de large. La parité de styles ne le voit pas : les
 * styles calculés sont les mêmes des deux côtés, c'est la boîte RÉSOLUE qui
 * s'effondre (grille, flex, `min-width: 0`, largeur en % d'un parent écrasé).
 * On mesure donc la boîte rendue de chaque contrôle, en valeur absolue.
 */
function analyseControls(A, B, viewport, cc) {
  const out = [];
  // Retrouver le MÊME contrôle en maquette : le chemin structurel ne suffit pas
  // (un wrapper de plus côté app et il ne matche plus). On tente, dans l'ordre,
  // le chemin, puis le nom du champ, puis le libellé. Sans équivalent trouvé,
  // on le dit au lieu de conclure à une régression.
  const idxSp = new Map(), idxName = new Map(), idxLbl = new Map();
  for (const c of (A.controls || [])) {
    if (!idxSp.has(c.sp)) idxSp.set(c.sp, c);
    const nk = c.tag + '|' + (c.type || '') + '|' + (c.name || '');
    if (c.name && !idxName.has(nk)) idxName.set(nk, c);
    const lk = c.tag + '|' + c.lbl;
    if (!idxLbl.has(lk)) idxLbl.set(lk, c);
  }
  const twinOf = (c) => idxSp.get(c.sp)
    || (c.name && idxName.get(c.tag + '|' + (c.type || '') + '|' + c.name))
    || idxLbl.get(c.tag + '|' + c.lbl)
    || null;

  const seen = new Set();
  for (const c of (B.controls || [])) {
    // Un même champ répété (une ligne de tableau par enregistrement) ne vaut
    // qu'un défaut : c'est le gabarit qui est en cause.
    const key = c.sp + '|' + Math.round(c.w) + 'x' + Math.round(c.h);
    if (seen.has(key)) continue;
    seen.add(key);

    const twin = twinOf(c);
    const what = c.tag === 'button' ? 'bouton' : (c.tag === 'select' ? 'liste déroulante' : (c.tag === 'textarea' ? 'zone de texte' : 'champ'));
    // La maquette est la référence : si elle rend le même contrôle aussi petit,
    // c'est un défaut de charte, pas une régression de l'app. On le dit et on
    // descend d'un cran, pour que le gate de parité ne se mette pas à rouge sur
    // un choix de design déjà validé.
    const twinShort = (axis) => twin && twin[axis] < cc.min_px;
    const demote = (sev) => (sev === 'majeur' ? 'mineur' : (sev === 'mineur' ? 'info' : sev));
    const promote = (sev) => (sev === 'info' ? 'mineur' : (sev === 'mineur' ? 'majeur' : sev));

    if (c.tiny) {
      // Cases à cocher et boutons radio : légitimement petits (13 à 20 px).
      // On ne les mesure qu'à la recherche de l'écrasement franc.
      if (c.w >= cc.tiny_min_px && c.h >= cc.tiny_min_px) continue;
      const tinyBoth = twin && (twin.w < cc.tiny_min_px || twin.h < cc.tiny_min_px);
      out.push({
        severity: tinyBoth ? 'mineur' : 'majeur', category: 'controle', kind: 'control-tiny',
        property: null, element: c.lbl, spath: 'ctl:' + c.sp, sig: c.sig,
        mockup: twin ? `${twin.w}×${twin.h}px` : '—', app: `${c.w}×${c.h}px`,
        message: `${c.lbl} : ${c.type === 'radio' ? 'bouton radio' : 'case à cocher'} rendu à ${c.w}×${c.h}px en ${viewport.name} — en dessous de ${cc.tiny_min_px}px, la case est inutilisable`,
        context: null
      });
      continue;
    }

    if (c.w < cc.crushed_px || c.h < cc.crushed_px / 2) {
      out.push({
        severity: 'bloquant', category: 'controle', kind: 'control-crushed',
        property: null, element: c.lbl, spath: 'ctl:' + c.sp, sig: c.sig,
        mockup: twin ? `${twin.w}×${twin.h}px` : '—', app: `${c.w}×${c.h}px`,
        message: `${c.lbl} : ${what} écrasé à ${c.w}×${c.h}px en ${viewport.name} (largeur ${viewport.width}px)`
          + (c.name ? `, name="${c.name}"` : '')
          + ` — en dessous de ${cc.crushed_px}px il n'est plus saisissable`
          + (twin ? `. En maquette : ${twin.w}×${twin.h}px.` : '.'),
        context: null
      });
      continue;
    }

    const shortW = c.w < cc.min_px, shortH = c.h < cc.min_px;
    if (!shortW && !shortH) continue;
    // Trop ÉTROIT pour saisir n'est pas la même chose que trop court d'un
    // cheveu : un champ de 36px de large ne reçoit pas de texte, un champ de
    // 38px de haut se saisit très bien (il rate juste la cible tactile de 44).
    // La hauteur seule reste donc une remarque de charte (info) tant qu'elle ne
    // vient pas d'une régression par rapport à la maquette.
    let sev;
    let why;
    if (!c.pressable && shortW) { sev = 'majeur'; why = 'trop étroit pour une saisie'; }
    else if (shortW && shortH) { sev = 'majeur'; why = 'sous la cible tactile sur les deux axes'; }
    else { sev = 'info'; why = `${shortW ? 'largeur' : 'hauteur'} de ${shortW ? c.w : c.h}px, sous la cible tactile de ${cc.min_px}px`; }
    const alsoMockup = (shortW && twinShort('w')) || (shortH && twinShort('h'));
    const regression = twin && (c.w < twin.w - 8 || c.h < twin.h - 4);
    if (regression) sev = promote(sev);
    else if (alsoMockup) sev = demote(sev);
    out.push({
      severity: sev, category: 'controle', kind: 'control-target',
      property: null, element: c.lbl, spath: 'ctl:' + c.sp, sig: c.sig,
      mockup: twin ? `${twin.w}×${twin.h}px` : '—', app: `${c.w}×${c.h}px`,
      message: `${c.lbl} : ${what} rendu à ${c.w}×${c.h}px en ${viewport.name}, ${why}`
        + (regression ? ` — plus petit que la maquette (${twin.w}×${twin.h}px) : c'est l'app qui a rétréci` : '')
        + (!regression && alsoMockup ? ' — déjà le cas en maquette, c\'est la charte qu\'il faut reprendre, pas l\'app' : '')
        + (!twin ? ' — pas d\'équivalent trouvé en maquette, comparaison impossible' : ''),
      context: null
    });
  }
  return out;
}

function classifySheet(href, pageOrigin, allow) {
  if (!href) return { cls: 'inline', label: 'style inline' };
  let u;
  try { u = new URL(href); } catch (e) { return { cls: 'inconnu', label: href }; }
  if (u.origin === pageOrigin) return { cls: 'interne', label: u.pathname };
  if (FONT_CSS_HOSTS.some((h) => u.host.endsWith(h))) return { cls: 'police', label: u.host + u.pathname };
  if (allow.some((h) => u.host.endsWith(h))) return { cls: 'autorise', label: u.host + u.pathname };
  return { cls: 'etranger', label: u.host + u.pathname };
}

function analyseCss(A, B, allow) {
  const out = [];
  const originOf = (u) => { try { return new URL(u).origin; } catch (e) { return ''; } };
  const oA = originOf(A.url), oB = originOf(B.url);

  const sheetsOf = (data, origin) => data.css.sheets.map((s) => ({ ...s, ...classifySheet(s.href, origin, allow) }));
  const sa = sheetsOf(A, oA), sb = sheetsOf(B, oB);

  for (const s of sb) {
    if (s.cls === 'etranger' || (s.cls === 'police' && false)) {
      const framework = s.href && KNOWN_CSS_FRAMEWORKS.test(s.href);
      out.push({
        severity: framework ? 'bloquant' : 'majeur',
        category: 'css-etranger', kind: 'foreign-sheet',
        property: null, element: s.label, spath: 'css:' + s.label,
        mockup: sa.some((x) => x.label === s.label) ? 'chargée aussi' : 'absente',
        app: `chargée (${s.rules == null ? 'illisible, cross-origin' : s.rules + ' règles'})`,
        message: `feuille de style étrangère chargée par l'app : ${s.label}${framework ? ' — bibliothèque de style connue, deux systèmes cohabitent' : ''}`,
        context: null
      });
    }
  }
  // Feuille interne présente d'un seul côté (un fichier CSS en plus dans l'app)
  const labA = new Set(sa.filter((s) => s.cls === 'interne').map((s) => s.label.replace(/-[0-9a-f]{8,}\./, '.')));
  for (const s of sb.filter((s) => s.cls === 'interne')) {
    const norm = s.label.replace(/-[0-9a-f]{8,}\./, '.');
    if (!labA.has(norm)) {
      out.push({
        severity: 'majeur', category: 'css-etranger', kind: 'extra-sheet',
        property: null, element: norm, spath: 'css:' + norm,
        mockup: 'absente', app: `chargée (${s.rules == null ? '?' : s.rules} règles)`,
        message: `l'app charge une feuille de style que la maquette n'a pas : ${norm}`,
        context: null
      });
    }
  }
  const inventory = {
    mockup: sa.map((s) => ({ label: s.label, cls: s.cls, rules: s.rules })),
    app: sb.map((s) => ({ label: s.label, cls: s.cls, rules: s.rules })),
    fonts_mockup: A.css.fonts, fonts_app: B.css.fonts
  };
  return { findings: out, inventory };
}

// ===========================================================================
// 8. Allowlist + agrégation
// ===========================================================================

function ruleMatches(rule, f, pairName, viewportName) {
  const test = (spec, value) => {
    if (spec == null) return true;
    if (spec instanceof RegExp) return spec.test(String(value == null ? '' : value));
    return String(value == null ? '' : value).includes(String(spec));
  };
  if (!test(rule.pair, pairName)) return false;
  if (!test(rule.viewport, viewportName)) return false;
  if (!test(rule.category, f.category)) return false;
  if (!test(rule.kind, f.kind)) return false;
  if (!test(rule.property, f.property)) return false;
  if (!test(rule.severity, f.severity)) return false;
  if (!test(rule.element, f.element)) return false;
  if (!test(rule.sig, f.sig)) return false;
  if (!test(rule.tags, f.tags)) return false;
  if (!test(rule.message, f.message)) return false;
  if (rule.match && !rule.match(f)) return false;
  return true;
}

function applyAllowlist(raw, pairName, viewportName, extraRules) {
  const rules = ALLOWLIST.concat(extraRules || []);
  const kept = [], ignored = [];
  for (const f of raw) {
    const hit = rules.find((r) => ruleMatches(r, f, pairName, viewportName));
    if (hit) ignored.push({ ...f, allowlist_reason: hit.reason || 'allowlist' });
    else kept.push(f);
  }
  return { kept, ignored };
}

function aggregate(findings) {
  const map = new Map();
  for (const f of findings) {
    const k = [f.category, f.kind, f.property, f.spath, f.mockup, f.app].join('|');
    const prev = map.get(k);
    if (prev) { prev.occurrences++; continue; }
    map.set(k, { ...f, occurrences: 1 });
  }
  const out = Array.from(map.values());
  out.sort((a, b) => (SEV_RANK[a.severity] - SEV_RANK[b.severity])
    || (b.occurrences - a.occurrences)
    || a.category.localeCompare(b.category));
  return out;
}

function countBySeverity(findings) {
  const c = { bloquant: 0, majeur: 0, mineur: 0, info: 0 };
  for (const f of findings) c[f.severity] = (c[f.severity] || 0) + 1;
  return c;
}

// Un total ne se tient jamais à part : il se recompte depuis la liste qu'il
// résume. Ces trois fonctions sont la seule source des chiffres du rapport.
function allFindings(pairs) {
  const out = [];
  for (const p of pairs) for (const vp of Object.values(p.viewports)) out.push(...(vp.findings || []));
  return out;
}
function allIgnored(pairs) {
  const out = [];
  for (const p of pairs) for (const vp of Object.values(p.viewports)) out.push(...(vp.ignored || []));
  return out;
}
function viewportErrors(pairs) {
  const out = [];
  for (const p of pairs) {
    for (const [name, vp] of Object.entries(p.viewports)) {
      if (vp.error) out.push({ pair: p.name, viewport: name, error: vp.error });
    }
  }
  return out;
}

// ===========================================================================
// 9. Pilotage navigateur
// ===========================================================================

function loadPlaywright() {
  const candidates = [
    'playwright',
    '/usr/lib/node_modules/@playwright/cli/node_modules/playwright',
    '/usr/lib/node_modules/playwright',
    '/usr/local/lib/node_modules/playwright'
  ];
  for (const c of candidates) { try { return require(c); } catch (e) { /* suivant */ } }
  throw new Error("Playwright introuvable. Installe-le (npm i playwright) ou expose le module global via NODE_PATH.");
}

// Le module playwright disponible n'embarque pas toujours la révision de
// Chromium présente dans le cache. On retombe alors sur le binaire le plus
// récent trouvé sur la machine plutôt que d'échouer.
function findChromium() {
  if (process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE) return process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  const roots = [
    process.env.PLAYWRIGHT_BROWSERS_PATH,
    path.join(process.env.HOME || '', '.cache', 'ms-playwright')
  ].filter(Boolean);
  const found = [];
  for (const root of roots) {
    let entries = [];
    try { entries = fs.readdirSync(root); } catch (e) { continue; }
    for (const e of entries) {
      const m = e.match(/^chromium(?:_headless_shell)?-(\d+)$/);
      if (!m) continue;
      for (const rel of [
        'chrome-linux/chrome', 'chrome-linux/headless_shell',
        'chrome-headless-shell-linux64/chrome-headless-shell',
        'chrome-mac/Chromium.app/Contents/MacOS/Chromium'
      ]) {
        const p = path.join(root, e, rel);
        if (fs.existsSync(p)) found.push({ rev: parseInt(m[1], 10), p, shell: /headless_shell/.test(e) });
      }
    }
  }
  if (!found.length) return null;
  found.sort((a, b) => (b.rev - a.rev) || (a.shell ? -1 : 1));
  return found[0].p;
}

async function launchChromium(chromium, opts) {
  try {
    return await chromium.launch(opts);
  } catch (err) {
    const exe = findChromium();
    if (!exe) throw err;
    console.error(`  (Chromium par défaut indisponible, repli sur ${exe})`);
    return chromium.launch({ ...opts, executablePath: exe });
  }
}

const ANIM_CSS = '*,*::before,*::after{animation:none!important;animation-duration:0s!important;'
  + 'transition:none!important;transition-duration:0s!important;'
  + 'caret-color:transparent!important;scroll-behavior:auto!important}';

async function preparePage(page, url, timeout) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout });
  try { await page.waitForLoadState('networkidle', { timeout: Math.min(timeout, 15000) }); } catch (e) { /* on continue */ }
  await page.addStyleTag({ content: ANIM_CSS }).catch(() => {});
  await page.evaluate(() => document.fonts && document.fonts.ready).catch(() => {});
  // `autofocus` d'un côté et pas de l'autre ferait passer tout l'anneau de
  // focus (bordure + box-shadow) pour un écart de charte.
  await page.evaluate(() => {
    const el = document.activeElement;
    if (el && el !== document.body && typeof el.blur === 'function') el.blur();
    if (window.getSelection) window.getSelection().removeAllRanges();
  }).catch(() => {});
  await page.waitForTimeout(180);
}

async function login(context, baseUrl, profile, timeout) {
  const page = await context.newPage();
  const url = absolute(baseUrl, profile.url);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout });
  for (const [sel, val] of profile.fill || []) await page.fill(sel, val, { timeout });
  await page.click(profile.submit || 'button[type=submit]', { timeout });
  if (profile.expect_url) {
    await page.waitForURL((u) => String(u).includes(profile.expect_url), { timeout }).catch(() => {});
  }
  await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
  if (profile.expect_url && !page.url().includes(profile.expect_url)) {
    const flash = await page.evaluate(() => (document.body ? document.body.innerText : '').slice(0, 200)).catch(() => '');
    await page.close();
    throw new Error(`Connexion "${profile.name}" échouée : arrivé sur ${page.url()}, attendu ${profile.expect_url}. Page : ${String(flash).replace(/\s+/g, ' ').slice(0, 160)}`);
  }
  await page.close();
}

function absolute(base, u) {
  if (!u) return u;
  if (/^https?:\/\//.test(u)) return u;
  return String(base || '').replace(/\/$/, '') + (u.startsWith('/') ? u : '/' + u);
}

// ===========================================================================
// 10. Rapport HTML
// ===========================================================================

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function renderHtml(report) {
  const totals = report.totals;
  const pageBlocks = report.pairs.map((p) => {
    const vps = Object.entries(p.viewports).map(([vpName, vp]) => {
      const rows = vp.findings.map((f) => `
        <tr class="f" data-sev="${f.severity}" data-cat="${esc(f.category)}">
          <td><span class="sev sev-${f.severity}">${f.severity}</span></td>
          <td class="cat">${esc(f.category)}</td>
          <td class="msg">${esc(f.message)}${f.occurrences > 1 ? ` <span class="occ">×${f.occurrences}</span>` : ''}
            ${f.context ? `<div class="ctx">dans ${esc(f.context)}</div>` : ''}
            ${f.sig ? `<div class="sig">${esc(trunc(f.sig, 150))}</div>` : ''}</td>
          <td class="v"><span class="lbl">maquette</span>${esc(f.mockup)}</td>
          <td class="v"><span class="lbl">app</span>${esc(f.app)}</td>
        </tr>`).join('');
      const c = vp.counts;
      return `
      <div class="vp">
        <h4>${esc(vpName)} <span class="dim">${vp.width}×${vp.height}</span>
          ${badges(c)}
          <span class="dim">· ${vp.stats.matched} éléments appariés / ${vp.stats.nodes_mockup} maquette · ${vp.stats.ignored_by_allowlist} filtrés</span>
        </h4>
        ${vp.error ? `<p class="err">${esc(vp.error)}</p>` : ''}
        ${vp.findings.length ? `<table><thead><tr><th>Gravité</th><th>Catégorie</th><th>Écart</th><th>Maquette</th><th>App</th></tr></thead><tbody>${rows}</tbody></table>`
        : '<p class="ok">Aucun écart hors tolérance.</p>'}
      </div>`;
    }).join('');
    return `
    <section class="pair" id="p-${esc(p.slug)}">
      <h3>${esc(p.name)} ${badges(p.counts)}</h3>
      <p class="urls"><a href="${esc(p.mockup_url)}">${esc(p.mockup_url)}</a> → <a href="${esc(p.app_url)}">${esc(p.app_url)}</a></p>
      ${vps}
    </section>`;
  }).join('');

  const cssInv = report.pairs.map((p) => {
    const inv = p.css_inventory;
    if (!inv) return '';
    const list = (arr) => arr.map((s) => `<li><code class="c-${esc(s.cls)}">${esc(s.cls)}</code> ${esc(s.label)} <span class="dim">${s.rules == null ? 'illisible' : s.rules + ' règles'}</span></li>`).join('');
    return `<details><summary>${esc(p.name)}</summary>
      <div class="two"><div><b>Maquette</b><ul>${list(inv.mockup)}</ul></div>
      <div><b>App</b><ul>${list(inv.app)}</ul></div></div>
      <div class="two"><div><b>Polices chargées (maquette)</b><ul>${inv.fonts_mockup.map((f) => `<li>${esc(f)}</li>`).join('')}</ul></div>
      <div><b>Polices chargées (app)</b><ul>${inv.fonts_app.map((f) => `<li>${esc(f)}</li>`).join('')}</ul></div></div>
    </details>`;
  }).join('');

  return `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Diff de styles maquette / app</title>
<style>
:root{--bg:#fff;--fg:#1b1f24;--dim:#6a737d;--line:#e5e7eb;--card:#fafbfc;
--bloquant:#b91c1c;--majeur:#c2410c;--mineur:#a16207;--info:#0369a1}
*{box-sizing:border-box}
body{margin:0;font:14px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--fg);background:var(--bg)}
header{padding:22px 28px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--bg);z-index:5}
h1{margin:0 0 6px;font-size:19px}
h3{margin:26px 0 4px;font-size:16px}
h4{margin:16px 0 6px;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.04em;color:var(--dim)}
main{padding:0 28px 60px;max-width:1500px}
.dim{color:var(--dim);font-weight:400;text-transform:none;letter-spacing:0}
.urls{color:var(--dim);font-size:12px;margin:2px 0 0}
.urls a{color:var(--dim)}
table{border-collapse:collapse;width:100%;margin:6px 0 4px;font-size:13px;display:block;overflow-x:auto}
th{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:var(--dim);border-bottom:1px solid var(--line);padding:6px 8px;white-space:nowrap}
td{border-bottom:1px solid var(--line);padding:7px 8px;vertical-align:top}
td.v{white-space:nowrap;font-variant-numeric:tabular-nums;width:1%}
td.cat{color:var(--dim);white-space:nowrap;width:1%}
.lbl{display:block;font-size:10px;text-transform:uppercase;color:var(--dim);letter-spacing:.04em}
.sev{display:inline-block;padding:1px 7px;border-radius:99px;font-size:11px;font-weight:700;color:#fff;white-space:nowrap}
.sev-bloquant{background:var(--bloquant)}.sev-majeur{background:var(--majeur)}
.sev-mineur{background:var(--mineur)}.sev-info{background:var(--info)}
.b{display:inline-block;margin-left:6px;padding:1px 8px;border-radius:99px;font-size:11px;font-weight:700;color:#fff}
.ctx,.sig{color:var(--dim);font-size:11px}
.sig{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;word-break:break-all;opacity:.65}
.occ{background:#eef1f4;border-radius:99px;padding:0 6px;font-size:11px;color:var(--dim)}
.ok{color:#15803d;margin:4px 0 0}
.err{color:var(--bloquant)}
.pair{border-top:1px solid var(--line);padding-top:8px}
.filters{display:flex;gap:14px;align-items:center;flex-wrap:wrap;font-size:13px;margin-top:8px}
.filters label{display:flex;gap:5px;align-items:center;cursor:pointer}
input[type=search]{padding:5px 9px;border:1px solid var(--line);border-radius:6px;font:inherit;min-width:240px}
details{border:1px solid var(--line);border-radius:8px;padding:8px 12px;margin:8px 0;background:var(--card)}
summary{cursor:pointer;font-weight:600}
.two{display:flex;gap:28px;flex-wrap:wrap}.two>div{flex:1;min-width:280px}
ul{margin:4px 0;padding-left:18px}li{font-size:12px}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;padding:0 4px;border-radius:4px;background:#eef1f4}
code.c-etranger{background:#fee2e2;color:#991b1b}code.c-police{background:#e0f2fe;color:#075985}
.tolerances{font-size:12px;color:var(--dim);margin-top:10px}
@media (prefers-color-scheme:dark){:root{--bg:#0f1216;--fg:#e6e8eb;--dim:#8b949e;--line:#262b31;--card:#161a1f}
code{background:#1d2229}.occ{background:#1d2229}}
</style></head><body>
<header>
  <h1>Diff de styles calculés — maquette vs application</h1>
  <div class="dim">${esc(report.generated_at)} · ${report.pairs.length} paire(s) · ${report.viewports.map((v) => `${v.name} ${v.width}×${v.height}`).join(' · ')}</div>
  <div style="margin-top:8px">${badges(totals, true)}
    <span class="dim">· ${allFindings(report.pairs).length} ligne(s) listée(s), total recompté depuis la liste</span></div>
  ${report.totals_errors ? `<div class="err" style="margin-top:6px"><b>${report.totals_errors} écran(s) non mesuré(s)</b> : ${esc(report.errors.slice(0, 3).map((e) => e.pair + ' [' + e.viewport + ']').join(', '))}${report.totals_errors > 3 ? '…' : ''} — leurs zéros ne sont pas des conformités.</div>` : ''}
  <div class="filters">
    ${SEVERITIES.map((s) => `<label><input type="checkbox" class="fs" value="${s}" ${s === 'info' ? '' : 'checked'}> ${s}</label>`).join('')}
    <input type="search" id="q" placeholder="filtrer (texte, catégorie, propriété)…">
  </div>
</header>
<main>
${pageBlocks}
<h3>Feuilles de style chargées</h3>
${cssInv}
<p class="tolerances">Tolérances : ${esc(JSON.stringify(report.tolerances))} — écarts filtrés par l'allowlist : ${report.totals_ignored}. Sortie du process : ${report.exit_code}.</p>
</main>
<script>
const sevs=()=>new Set([...document.querySelectorAll('.fs:checked')].map(c=>c.value));
const q=document.getElementById('q');
function apply(){const s=sevs();const t=q.value.trim().toLowerCase();
document.querySelectorAll('tr.f').forEach(r=>{const okS=s.has(r.dataset.sev);
const okT=!t||r.textContent.toLowerCase().includes(t);r.style.display=(okS&&okT)?'':'none'});
document.querySelectorAll('.vp').forEach(v=>{const any=[...v.querySelectorAll('tr.f')].some(r=>r.style.display!=='none');
const tbl=v.querySelector('table');if(tbl)tbl.style.display=any?'block':'none'});}
document.querySelectorAll('.fs').forEach(c=>c.addEventListener('change',apply));
q.addEventListener('input',apply);apply();
</script>
</body></html>`;
}

function badges(c, big) {
  return SEVERITIES.filter((s) => c[s]).map((s) => `<span class="b sev-${s}">${c[s]} ${s}${big ? '' : ''}</span>`).join('');
}

// ===========================================================================
// 11. main
// ===========================================================================

function parseArgs(argv) {
  const out = { pairs: null, out: 'rapport', only: null, viewport: null, failOn: 'mineur', headed: false, timeout: 30000, verbose: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--pairs') out.pairs = next();
    else if (a === '--out') out.out = next();
    else if (a === '--only') out.only = next();
    else if (a === '--viewport') out.viewport = next();
    else if (a === '--fail-on') out.failOn = next();
    else if (a === '--timeout') out.timeout = parseInt(next(), 10);
    else if (a === '--headed') out.headed = true;
    else if (a === '--verbose' || a === '-v') out.verbose = true;
    else if (a === '--help' || a === '-h') { usage(); process.exit(0); }
    else { console.error(`Option inconnue : ${a}`); usage(); process.exit(2); }
  }
  if (!out.pairs) { usage(); process.exit(2); }
  return out;
}

function usage() {
  console.log(`Usage : node style_diff.js --pairs pairs.json --out rapport/

  --pairs <fichier>   description des paires maquette/app (obligatoire)
  --out <dossier>     dossier de sortie (défaut : rapport/)
  --only <motif>      ne traiter que les paires dont le nom contient <motif>
  --viewport <nom>    ne traiter qu'un viewport (ex. mobile)
  --fail-on <niveau>  bloquant | majeur | mineur | aucun (défaut : mineur)
  --timeout <ms>      délai par navigation (défaut : 30000)
  --headed            navigateur visible (débogage)
  -v, --verbose       journal détaillé`);
}

function slugify(s) {
  return String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60);
}

async function main() {
  const args = parseArgs(process.argv);
  const cfg = JSON.parse(fs.readFileSync(args.pairs, 'utf8'));

  const viewports = (cfg.viewports && cfg.viewports.length ? cfg.viewports : [
    { name: 'desktop', width: 1440, height: 900 },
    { name: 'mobile', width: 390, height: 844 }
  ]).filter((v) => !args.viewport || v.name === args.viewport);

  const tol = { ...DEFAULT_TOLERANCES, ...(cfg.tolerances || {}) };
  const controlsCfg = { ...DEFAULT_CONTROLS, ...(cfg.controls || {}) };
  const clipMinExcess = cfg.clip_min_excess != null ? cfg.clip_min_excess : CLIP_MIN_EXCESS;
  const baseM = cfg.base_mockup || cfg.base_url || '';
  const baseA = cfg.base_app || cfg.base_url || '';
  const globalIgnore = DEFAULT_IGNORE_SELECTORS.concat(cfg.ignore_selectors || []);
  const globalMask = cfg.mask_selectors || [];
  const foreignAllow = cfg.foreign_css_allow || [];
  const extraRules = (cfg.allowlist || []).map((r) => ({
    ...r,
    pair: r.pair ? new RegExp(r.pair, 'i') : undefined,
    element: r.element ? new RegExp(r.element, 'i') : undefined,
    message: r.message ? new RegExp(r.message, 'i') : undefined,
    sig: r.sig ? new RegExp(r.sig, 'i') : undefined
  }));

  const pairsCfg = (cfg.pairs || []).filter((p) => !args.only || p.name.includes(args.only));
  if (!pairsCfg.length) { console.error('Aucune paire à traiter.'); process.exit(2); }

  const { chromium } = loadPlaywright();
  const browser = await launchChromium(chromium, { headless: !args.headed });

  // Un contexte par profil d'authentification (+ un anonyme pour les maquettes)
  const contexts = new Map();
  async function ctxFor(profileName, viewport) {
    const key = `${profileName || 'anon'}@${viewport.name}`;
    if (contexts.has(key)) return contexts.get(key);
    const c = await browser.newContext({
      viewport: { width: viewport.width, height: viewport.height },
      deviceScaleFactor: 1, reducedMotion: 'reduce', colorScheme: 'light',
      locale: cfg.locale || 'fr-FR', timezoneId: cfg.timezone || 'Europe/Paris'
    });
    await c.addInitScript((css) => {
      const add = () => {
        const s = document.createElement('style');
        s.setAttribute('data-style-diff', '1'); s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
      };
      if (document.head) add();
      else document.addEventListener('DOMContentLoaded', add, { once: true });
    }, ANIM_CSS);
    if (profileName) {
      const prof = (cfg.auth || {})[profileName];
      if (!prof) throw new Error(`Profil d'authentification inconnu : ${profileName}`);
      await login(c, baseA, { ...prof, name: profileName }, args.timeout);
    }
    contexts.set(key, c);
    return c;
  }

  const report = {
    generated_at: new Date().toISOString().replace('T', ' ').slice(0, 19),
    tolerances: tol, viewports, pairs: [],
    totals: { bloquant: 0, majeur: 0, mineur: 0, info: 0 }, totals_ignored: 0
  };

  fs.mkdirSync(args.out, { recursive: true });
  fs.mkdirSync(path.join(args.out, 'paires'), { recursive: true });

  for (const pc of pairsCfg) {
    const slug = slugify(pc.name);
    const mockupUrl = absolute(baseM, pc.mockup_url);
    const appUrl = absolute(baseA, pc.app_url);
    const rootSelector = pc.root_selector || cfg.root_selector || 'body';
    const ignoreSelectors = globalIgnore.concat(pc.ignore_selectors || []);
    const maskSelectors = globalMask.concat(pc.mask_selectors || []);

    const entry = {
      name: pc.name, slug, mockup_url: mockupUrl, app_url: appUrl,
      root_selector: rootSelector, viewports: {},
      counts: { bloquant: 0, majeur: 0, mineur: 0, info: 0 }, css_inventory: null
    };
    process.stdout.write(`▸ ${pc.name}\n`);

    for (const vp of viewports) {
      const vpEntry = { width: vp.width, height: vp.height, findings: [], ignored: [], counts: { bloquant: 0, majeur: 0, mineur: 0, info: 0 }, stats: {} };
      try {
        const anon = await ctxFor(pc.mockup_auth_profile || null, vp);
        // `auth_profile: null | false` = page publique, on force le contexte anonyme
        const appProfile = Object.prototype.hasOwnProperty.call(pc, 'auth_profile')
          ? (pc.auth_profile || null)
          : (cfg.default_auth_profile || null);
        const appCtx = await ctxFor(appProfile, vp);

        const pageM = await anon.newPage();
        const pageA = await appCtx.newPage();
        const exArgs = { props: PROPS, ignoreSelectors, maskSelectors, rootSelector, maxNodes: MAX_NODES, clipMinExcess };

        await preparePage(pageM, mockupUrl, args.timeout);
        const A = await pageM.evaluate(pageExtract, exArgs);
        await preparePage(pageA, appUrl, args.timeout);
        const B = await pageA.evaluate(pageExtract, exArgs);
        await pageM.close(); await pageA.close();

        const { raw, stats } = compareTrees(A, B, tol, { pair: pc.name, vp: vp.name, controls: controlsCfg });
        const over = analyseOverflow(A, B, vp);
        const ctl = analyseControls(A, B, vp, controlsCfg);
        const cssRes = analyseCss(A, B, foreignAllow);
        if (!entry.css_inventory) entry.css_inventory = cssRes.inventory;

        const all = raw.concat(over, ctl, cssRes.findings);
        const { kept, ignored } = applyAllowlist(all, pc.name, vp.name, extraRules);
        vpEntry.findings = aggregate(kept);
        vpEntry.ignored = aggregate(ignored);
        vpEntry.counts = countBySeverity(vpEntry.findings);
        vpEntry.stats = {
          ...stats,
          ignored_by_allowlist: vpEntry.ignored.length,
          controls_app: (B.controls || []).length,
          clipped_app: B.overflow.clipped_total || 0,
          scrollers_app: B.overflow.scrollers_total || 0,
          doc_scroll_width_app: B.overflow.doc.docScrollWidth,
          css_readable_app: B.overflow.css_readable !== false
        };
      } catch (err) {
        vpEntry.error = `Échec sur ${vp.name} : ${err.message}`;
        vpEntry.stats = { ignored_by_allowlist: 0 };
        console.error(`   ! ${vpEntry.error}`);
      }
      entry.viewports[vp.name] = vpEntry;
      const c = vpEntry.counts;
      process.stdout.write(`  ${vp.name.padEnd(8)} ${c.bloquant} bloquant · ${c.majeur} majeur · ${c.mineur} mineur · ${c.info} info`
        + (vpEntry.stats.matched ? ` (${vpEntry.stats.matched} éléments appariés)` : '') + '\n');
    }
    // Les compteurs d'une paire SONT la liste de ses écarts, recomptée : rien
    // n'est incrémenté à côté, donc rien ne peut diverger de ce qui est affiché.
    entry.counts = countBySeverity(allFindings([entry]));
    report.pairs.push(entry);
    fs.writeFileSync(path.join(args.out, 'paires', `${slug}.json`), JSON.stringify(entry, null, 2));
  }

  await browser.close();

  // Idem au niveau du rapport : les totaux sont RECALCULÉS depuis les listes
  // publiées, jamais tenus à part. Un livrable qui se résume lui-même ment par
  // défaut : le seul résumé qui ne ment pas est celui qu'on dérive.
  report.totals = countBySeverity(allFindings(report.pairs));
  report.totals_ignored = allIgnored(report.pairs).length;
  report.totals_errors = viewportErrors(report.pairs).length;
  report.errors = viewportErrors(report.pairs);

  const gate = args.failOn === 'aucun' ? null : SEV_RANK[args.failOn];
  const blocking = gate == null ? 0 : SEVERITIES.filter((s) => SEV_RANK[s] <= gate).reduce((n, s) => n + report.totals[s], 0);
  report.exit_code = blocking > 0 ? 1 : 0;

  fs.writeFileSync(path.join(args.out, 'index.html'), renderHtml(report));
  const summary = { ...report, pairs: report.pairs.map((p) => ({ name: p.name, slug: p.slug, mockup_url: p.mockup_url, app_url: p.app_url, counts: p.counts })) };
  fs.writeFileSync(path.join(args.out, 'resume.json'), JSON.stringify(summary, null, 2));

  const t = report.totals;
  console.log(`\n${t.bloquant} bloquant · ${t.majeur} majeur · ${t.mineur} mineur · ${t.info} info`
    + ` (${report.totals_ignored} filtrés par l'allowlist)`);
  if (report.totals_errors) {
    // Un écran qui a planté rend 0 écart : sans cette ligne, l'échec de mesure
    // se lit comme un feu vert.
    console.log(`${report.totals_errors} écran(s)/viewport(s) NON MESURÉ(S) (erreur) : leurs zéros ne sont pas des conformités.`);
    for (const e of report.errors.slice(0, 5)) console.log(`   · ${e.pair} [${e.viewport}] : ${e.error}`);
  }
  console.log(`Rapport : ${path.resolve(args.out, 'index.html')}`);
  process.exit(report.exit_code);
}

main().catch((e) => { console.error(e); process.exit(2); });
