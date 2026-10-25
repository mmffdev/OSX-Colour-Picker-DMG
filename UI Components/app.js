(function () {
  'use strict';
  const UI = window.ColorgainUI;
  const byId = id => document.getElementById(id);
  let toastTimer;
  function announce(message) {
    const toast = byId('toast'); toast.textContent = message; toast.classList.add('visible');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.remove('visible'), 2200);
  }
  function mount(id, ...nodes) { byId(id).append(...nodes); }

  mount('buttons-demo',
    UI.actionButton({ label: 'Save Preset', role: 'primary', onClick: () => announce('Save Preset pressed') }),
    UI.actionButton({ label: 'Add Field', role: 'secondary', onClick: () => announce('Add Field pressed') }),
    UI.actionButton({ label: 'Cancel', onClick: () => announce('Cancel pressed') }),
    UI.actionButton({ label: 'Remove Field', role: 'danger', onClick: () => announce('Remove Field pressed') }),
    UI.actionButton({ label: 'Unavailable', disabled: true })
  );
  for (const [icon, label, disabled] of [['gear', 'Settings', false], ['plus', 'Add', false], ['tag', 'Tags', false], ['close', 'Close', false], ['gear', 'Disabled', true]]) {
    const item = document.createElement('div'); item.className = 'icon-demo-item';
    item.append(UI.iconButton({ icon, label, disabled, onClick: () => announce(`${label} pressed`) }), document.createTextNode(label));
    mount('icons-demo', item);
  }
  mount('choices-demo',
    UI.choiceBar({ labels: ['Grid', 'List', 'Compare'], onChange: label => announce(`View: ${label}`) }),
    UI.choiceButton({ icon: 'folder', label: 'Reference Files', selected: true, onClick: selected => announce(`Reference Files: ${selected ? 'selected' : 'off'}`) }),
    UI.choiceButton({ icon: 'plus', label: 'Copy Files', onClick: selected => announce(`Copy Files: ${selected ? 'selected' : 'off'}`) })
  );
  const raisedExamples = [
    ['New Palette', 'Create colour set', 'plus'], ['Save Preset', 'Keep this layout', 'dot'], ['Add Collection', 'Group your assets', 'plus'],
    ['Add Field', 'Extend metadata', 'plus'], ['Apply Profile', 'Set output colour', 'dot'], ['Open Asset', 'Inspect details', 'diamond'],
    ['Import Files', 'Bring into library', 'plus'], ['More Options', 'Fine-tune settings', 'dot'], ['Close Preview', 'Return to library', 'close'],
    ['New Swatch', 'Capture a colour', 'plus'], ['Set Favourite', 'Keep close at hand', 'dot'], ['Quick Add', 'Create instantly', 'plus', true]
  ];
  mount('raised-demo', ...raisedExamples.map(([label, subtitle, icon, glow]) =>
    UI.raisedButton({ label, subtitle, icon, glow, onClick: () => announce(`${label} pressed`) })
  ));
  const raisedStage = document.querySelector('.raised-stage');
  document.querySelectorAll('.depth-switch button').forEach(button => button.addEventListener('click', () => {
    raisedStage.dataset.depth = button.dataset.depth;
    document.querySelectorAll('.depth-switch button').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
  }));
  for (const [label, state, caption] of [['Include Metadata', 'on', 'Selected'], ['Show Colour Values', 'off', 'Unselected'], ['Apply to Selection', 'mixed', 'Mixed'], ['Locked Option', 'disabled', 'Disabled']]) {
    const cell = document.createElement('div'); cell.className = 'check-cell';
    cell.append(UI.checkbox({ label, checked: state === 'on', mixed: state === 'mixed', disabled: state === 'disabled', onChange: value => announce(`${label}: ${value ? 'on' : 'off'}`) }));
    const note = document.createElement('span'); note.className = 'check-caption'; note.textContent = caption; cell.append(note);
    mount('checks-demo', cell);
  }
  const presetOptions = ['All fields', 'Core metadata', 'Copyright & credits', { separator: true }, 'Custom'];
  mount('dropdown-demo', UI.select({ label: 'Metadata preset', value: 'Core metadata', options: presetOptions, onChange: value => announce(`Preset: ${value}`) }));
  mount('dropup-demo', UI.select({ label: 'Output profile', value: 'Display P3', direction: 'up', options: ['Display P3', 'Adobe RGB', 'sRGB IEC61966-2.1', 'CMYK proof'], onChange: value => announce(`Profile: ${value}`) }));
  mount('inline-demo', UI.select({ label: 'Toolbar view', value: 'All Assets', inline: true, options: ['All Assets', 'Palettes', 'Swatches', 'Photographs'], onChange: value => announce(`View: ${value}`) }));
  mount('fields-demo',
    UI.field({ label: 'Name', placeholder: 'Enter a name', help: 'Empty field' }),
    UI.field({ label: 'Creator', value: 'MMFFDev', help: 'Filled field' }),
    UI.field({ label: 'Identifier', value: 'Palette 001', invalid: true, help: 'This identifier is already in use.' }),
    UI.field({ label: 'Locked Field', value: 'Read only in this context', disabled: true, help: 'Disabled field' })
  );
  mount('dates-demo',
    UI.field({ label: 'Date Created', type: 'date', value: '2026-10-21', help: 'Use the calendar or type a date.' }),
    UI.field({ label: 'Review Date', type: 'date', help: 'No date selected' }),
    UI.field({ label: 'Archived Date', type: 'date', value: '2026-09-14', disabled: true, help: 'Disabled date' })
  );
  mount('textboxes-demo',
    UI.field({ label: 'Description', multiline: true, placeholder: 'Describe this asset…', help: 'Empty text box' }),
    UI.field({ label: 'Asset Notes', multiline: true, value: 'Colour reference for the autumn campaign.\nApproved for print and digital delivery.', help: 'Filled text box' }),
    UI.field({ label: 'Delivery Instructions', multiline: true, value: 'Missing output details.', invalid: true, help: 'Add the destination colour profile.' })
  );
  const links = [...document.querySelectorAll('.nav-link')];
  const sections = links.map(link => document.querySelector(link.getAttribute('href')));
  let activeFrame = 0;
  function updateActive() {
    activeFrame = 0;
    const edge = innerWidth <= 650 ? 150 : 110;
    const active = sections.filter(section => section.getBoundingClientRect().top <= edge).at(-1) || sections[0];
    links.forEach(link => link.classList.toggle('active', link.getAttribute('href') === `#${active.id}`));
  }
  function queueActive() { if (!activeFrame) activeFrame = requestAnimationFrame(updateActive); }
  window.addEventListener('scroll', queueActive, { passive: true });
  window.addEventListener('resize', queueActive);
  window.addEventListener('hashchange', queueActive);
  queueActive();
})();
