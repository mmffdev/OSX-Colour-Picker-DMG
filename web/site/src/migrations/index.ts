import * as migration_20261016_050622_initial from './20261016_050622_initial';

export const migrations = [
  {
    up: migration_20261016_050622_initial.up,
    down: migration_20261016_050622_initial.down,
    name: '20261016_050622_initial'
  },
];
