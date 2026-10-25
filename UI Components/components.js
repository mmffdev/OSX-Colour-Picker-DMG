/* Reusable review primitives. The specimen page in app.js only composes these. */
(function () {
  'use strict';

  const icons = {
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-1.86 1.86-.06-.06A1.7 1.7 0 0 0 16 18.4a1.7 1.7 0 0 0-1 1.55V20h-2v-.05a1.7 1.7 0 0 0-1-1.55 1.7 1.7 0 0 0-1.88.34l-.06.06-1.86-1.86.06-.06A1.7 1.7 0 0 0 8.6 15a1.7 1.7 0 0 0-1.55-1H7v-2h.05a1.7 1.7 0 0 0 1.55-1 1.7 1.7 0 0 0-.34-1.88L8.2 9.06 10.06 7.2l.06.06A1.7 1.7 0 0 0 12 7.6a1.7 1.7 0 0 0 1-1.55V6h2v.05a1.7 1.7 0 0 0 1 1.55 1.7 1.7 0 0 0 1.88-.34l.06-.06L19.8 9.06l-.06.06A1.7 1.7 0 0 0 19.4 11a1.7 1.7 0 0 0 1.55 1H21v2h-.05A1.7 1.7 0 0 0 19.4 15Z" transform="translate(-2 -1)"/>',
    plus: '<path d="M12 4v16M4 12h16"/>',
    close: '<path d="M5 5l14 14M19 5 5 19"/>',
    tag: '<path d="M3 4h9l9 9-8 8-9-9V4Z"/><circle cx="8" cy="8" r="1"/>',
    folder: '<path d="M3 6h7l2 2h9v11H3V6Z"/>',
    diamond: '<path d="m12 2 10 10-10 10L2 12 12 2Z"/><path d="M8 12h8"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4M17 3v4M3 10h18"/>'
  };
  let nextId = 1;
  let openSelect = null;

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function svg(name) {
    const node = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    node.setAttribute('viewBox', '0 0 24 24');
    node.setAttribute('aria-hidden', 'true');
    node.innerHTML = icons[name];
    return node;
  }
  function actionButton({ label, role = 'quiet', disabled = false, onClick = () => {} }) {
    const button = el('button', `ui-action ${role}`);
    button.type = 'button'; button.disabled = disabled;
    button.append(el('span', 'action-arrow', '↗'), el('span', 'action-label', label));
    button.addEventListener('click', onClick);
    return button;
  }
  function iconButton({ icon, label, disabled = false, onClick = () => {} }) {
    const button = el('button', 'ui-icon');
    button.type = 'button'; button.disabled = disabled;
    button.setAttribute('aria-label', label); button.title = label;
    button.append(svg(icon)); button.addEventListener('click', onClick);
    return button;
  }
  function choiceBar({ labels, selected = 0, onChange = () => {} }) {
    const bar = el('div', 'ui-choice-bar'); bar.setAttribute('role', 'radiogroup');
    const buttons = labels.map((label, index) => {
      const button = el('button', 'ui-choice', label); button.type = 'button';
      button.setAttribute('role', 'radio'); button.setAttribute('aria-checked', String(index === selected));
      button.tabIndex = index === selected ? 0 : -1;
      button.addEventListener('click', () => choose(index));
      button.addEventListener('keydown', event => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + buttons.length) % buttons.length;
        choose(next); buttons[next].focus();
      });
      bar.append(button); return button;
    });
    function choose(index) {
      selected = index;
      buttons.forEach((button, i) => { button.setAttribute('aria-checked', String(i === index)); button.tabIndex = i === index ? 0 : -1; });
      onChange(labels[index]);
    }
    return bar;
  }
  function choiceButton({ icon, label, selected = false, onClick = () => {} }) {
    const button = el('button', 'ui-choice-button'); button.type = 'button';
    button.setAttribute('aria-pressed', String(selected));
    button.append(svg(icon), el('span', '', label));
    button.addEventListener('click', () => { selected = !selected; button.setAttribute('aria-pressed', String(selected)); onClick(selected); });
    return button;
  }
  function raisedButton({ label, subtitle, icon = 'plus', glow = false, onClick = () => {} }) {
    const button = el('button', `ui-raised${glow ? ' has-glow' : ''}`);
    button.type = 'button';
    button.setAttribute('aria-label', `${label}, ${subtitle}`);
    const copy = el('span', 'raised-copy');
    copy.append(el('strong', '', label), el('small', '', subtitle));
    const mark = el('span', `raised-mark${icon === 'dot' ? ' is-dot' : ''}`);
    mark.setAttribute('aria-hidden', 'true');
    if (icon !== 'dot') mark.append(svg(icon));
    button.append(copy, mark);
    button.addEventListener('click', () => {
      button.classList.add('clicked');
      window.setTimeout(() => button.classList.remove('clicked'), 260);
      onClick();
    });
    return button;
  }
  function checkbox({ label, checked = false, mixed = false, disabled = false, onChange = () => {} }) {
    const wrapper = el('label', 'ui-check');
    const input = el('input'); input.type = 'checkbox'; input.checked = checked;
    input.disabled = disabled; input.indeterminate = mixed;
    if (mixed) input.dataset.mixed = 'true';
    const mark = el('span', 'check-symbol');
    mark.setAttribute('aria-hidden', 'true');
    mark.innerHTML = '<svg viewBox="0 0 24 24"><path class="check-ring" d="M17.4 4.9A9.3 9.3 0 1 0 21.2 12"/><path class="check-tick" d="M4.6 11.6 9.8 17l10.7-12.1c.6-.7.5-.9-.3-.5L10 13.1l-3.2-3.3c-.5-.5-1-.4-1.5.1-.6.5-.8 1.1-.7 1.7Z"/><path class="check-dash" d="M7.5 12h9"/></svg>';
    wrapper.append(input, mark, el('span', '', label));
    input.addEventListener('change', () => {
      input.indeterminate = false; delete input.dataset.mixed;
      onChange(input.checked);
    });
    return wrapper;
  }

  function closeMenu(restoreFocus = false) {
    if (!openSelect) return;
    const { trigger, menu } = openSelect;
    menu.remove(); trigger.setAttribute('aria-expanded', 'false');
    if (restoreFocus) trigger.focus();
    openSelect = null;
  }
  function select({ options, value, inline = false, direction = 'down', label, onChange = () => {} }) {
    const root = el('div', `ui-select${inline ? ' inline' : ''}`);
    root.dataset.direction = direction;
    const trigger = el('button', 'ui-select-trigger'); trigger.type = 'button';
    trigger.setAttribute('aria-label', label); trigger.setAttribute('aria-haspopup', 'listbox');
    trigger.setAttribute('aria-expanded', 'false');
    const listId = `ui-list-${nextId++}`; trigger.setAttribute('aria-controls', listId);
    const display = el('span', 'select-value', value);
    const arrow = el('span', 'select-arrow');
    arrow.innerHTML = '<svg aria-hidden="true" width="12" height="12" viewBox="0 0 12 12"><path d="m2.5 4.5 3.5 3 3.5-3" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    trigger.append(display, arrow); root.append(trigger);
    const choices = options.map(option => typeof option === 'string' ? { label: option, value: option } : option);
    let selected = value;
    function showMenu(focusIndex) {
      closeMenu();
      const menu = el('div', 'ui-menu'); menu.id = listId; menu.setAttribute('role', 'listbox');
      menu.setAttribute('aria-label', label);
      const items = [];
      choices.forEach(choice => {
        if (choice.separator) { menu.append(el('div', 'menu-separator')); return; }
        const item = el('button', '', choice.label); item.type = 'button'; item.setAttribute('role', 'option');
        item.setAttribute('aria-selected', String(choice.value === selected));
        item.addEventListener('click', () => { selected = choice.value; display.textContent = choice.label; onChange(choice.value); closeMenu(true); });
        menu.append(item); items.push(item);
      });
      document.body.append(menu);
      const rect = trigger.getBoundingClientRect();
      const width = Math.max(rect.width, 186);
      menu.style.width = `${width}px`;
      const height = menu.offsetHeight;
      const roomBelow = window.innerHeight - rect.bottom - 8;
      const roomAbove = rect.top - 8;
      const above = direction === 'up' ? roomAbove >= height || roomAbove > roomBelow : roomBelow < height && roomAbove > roomBelow;
      menu.style.top = `${Math.max(8, Math.min(window.innerHeight - height - 8, above ? rect.top - height - 6 : rect.bottom + 6))}px`;
      menu.style.left = `${Math.max(8, Math.min(window.innerWidth - width - 8, rect.left))}px`;
      trigger.setAttribute('aria-expanded', 'true');
      openSelect = { trigger, menu };
      const current = items.findIndex(item => item.getAttribute('aria-selected') === 'true');
      const target = focusIndex === 'first' ? 0 : focusIndex === 'last' ? items.length - 1 : Math.max(0, current);
      items[target]?.focus();
      menu.addEventListener('keydown', event => {
        const index = items.indexOf(document.activeElement);
        if (event.key === 'ArrowDown') { event.preventDefault(); items[(index + 1) % items.length]?.focus(); }
        if (event.key === 'ArrowUp') { event.preventDefault(); items[(index - 1 + items.length) % items.length]?.focus(); }
        if (event.key === 'Home') { event.preventDefault(); items[0]?.focus(); }
        if (event.key === 'End') { event.preventDefault(); items[items.length - 1]?.focus(); }
        if (event.key === 'Escape') { event.preventDefault(); closeMenu(true); }
        if (event.key === 'Tab') closeMenu();
      });
    }
    trigger.addEventListener('click', () => openSelect?.trigger === trigger ? closeMenu(true) : showMenu());
    trigger.addEventListener('keydown', event => {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); showMenu(event.key === 'ArrowDown' ? 'first' : 'last'); }
    });
    return root;
  }
  document.addEventListener('pointerdown', event => {
    if (openSelect && !openSelect.menu.contains(event.target) && !openSelect.trigger.contains(event.target)) closeMenu();
  });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') closeMenu(true); });
  window.addEventListener('resize', () => closeMenu());
  window.addEventListener('scroll', () => closeMenu(), true);

  function field({ label, value = '', placeholder = '', type = 'text', multiline = false, disabled = false, invalid = false, help = '', rows = 4 }) {
    const root = el('div', 'ui-field'); if (invalid) root.dataset.invalid = 'true';
    const id = `ui-field-${nextId++}`;
    const caption = el('label', '', label); caption.htmlFor = id;
    const input = el(multiline ? 'textarea' : 'input'); input.id = id;
    if (!multiline) input.type = type; else input.rows = rows;
    input.value = value; input.placeholder = placeholder; input.disabled = disabled;
    if (invalid) input.setAttribute('aria-invalid', 'true');
    root.append(caption, input);
    if (help) { const hint = el('div', `field-help${invalid ? ' error' : ''}`, help); hint.id = `${id}-help`; input.setAttribute('aria-describedby', hint.id); root.append(hint); }
    return root;
  }
  window.ColorgainUI = Object.freeze({ actionButton, iconButton, choiceBar, choiceButton, raisedButton, checkbox, select, field, icons });
})();
