#!/usr/bin/env node
// Cross-platform manifest gate. Runs on Linux/macOS/Windows and in CI, so a bad
// tweak definition is caught before it ever reaches a Windows machine.
//
//   node tools/validate-manifest.mjs
//
// Checks: schema shape, duplicate ids, id naming, risk/scope enums, provider
// existence (parsed from PowerShell/Providers.ps1), provider-specific settings,
// and the reversible/rollback contract.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const errors = [];
const warnings = [];

const manifest = JSON.parse(readFileSync(join(root, 'Config/Tweaks.json'), 'utf8'));
const providerSrc = readFileSync(join(root, 'PowerShell/Providers.ps1'), 'utf8');

// Read the provider registry straight out of the source of truth.
const providers = new Map();
const re = /Register-WinUtilProvider\s+-Name\s+'([^']+)'\s+-Kind\s+(\w+)/g;
for (let m; (m = re.exec(providerSrc)); ) {
  const block = providerSrc.slice(m.index, providerSrc.indexOf('\n\n', m.index) + 1 || undefined);
  providers.set(m[1], { kind: m[2], rollback: /-Rollback\s+\{/.test(block) });
}

if (providers.size === 0) errors.push('No providers parsed from PowerShell/Providers.ps1.');

const RISK = ['Low', 'Medium', 'High'];
const SCOPE = ['User', 'System'];
const REG_TYPES = ['String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord'];
const START_TYPES = ['Automatic', 'Manual', 'Disabled'];

if (manifest.SchemaVersion !== 1) errors.push(`Unsupported SchemaVersion: ${manifest.SchemaVersion}`);
if (!Array.isArray(manifest.Tweaks)) errors.push('Tweaks must be an array.');

const seen = new Set();

for (const t of manifest.Tweaks ?? []) {
  const id = t.Id ?? '<missing Id>';
  const fail = (m) => errors.push(`${id}: ${m}`);
  const warn = (m) => warnings.push(`${id}: ${m}`);

  for (const f of ['Id', 'Name', 'Description', 'Category', 'Scope', 'Provider', 'Risk']) {
    if (typeof t[f] !== 'string' || !t[f].trim()) fail(`missing or empty '${f}'.`);
  }
  for (const f of ['RequiresAdmin', 'Reversible', 'EnabledByDefault', 'RequiresRestorePoint']) {
    if (typeof t[f] !== 'boolean') fail(`'${f}' must be a boolean.`);
  }

  if (seen.has(t.Id)) fail('duplicate Id.');
  seen.add(t.Id);

  if (t.Id && !/^[A-Za-z]+\.[A-Za-z0-9]+$/.test(t.Id)) fail("Id must look like 'Category.Name'.");
  if (t.Risk && !RISK.includes(t.Risk)) fail(`Risk must be one of ${RISK.join(', ')}.`);
  if (t.Scope && !SCOPE.includes(t.Scope)) fail(`Scope must be one of ${SCOPE.join(', ')}.`);
  if (!Array.isArray(t.SupportedOS) || t.SupportedOS.length === 0) fail('SupportedOS must be a non-empty array.');

  const p = providers.get(t.Provider);
  if (!p) {
    fail(`unknown provider '${t.Provider}'. Register it in PowerShell/Providers.ps1 first.`);
    continue;
  }

  // The contract that matters most: never promise an undo the engine cannot perform.
  if (t.Reversible && !p.rollback) fail(`marked Reversible but provider '${t.Provider}' has no Rollback block.`);
  if (p.kind === 'ReadOnly' && t.Reversible) fail('a ReadOnly provider cannot be Reversible.');
  if (p.kind === 'ReadOnly' && t.RequiresAdmin) warn('read-only tweak requests admin; usually unnecessary.');

  const s = t.Settings ?? {};

  if (t.Provider === 'Registry') {
    for (const f of ['RegistryPath', 'ValueName', 'PropertyType']) {
      if (!s[f]) fail(`Registry settings require '${f}'.`);
    }
    if (s.DesiredValue === undefined) fail("Registry settings require 'DesiredValue'.");
    if (s.PropertyType && !REG_TYPES.includes(s.PropertyType)) fail(`PropertyType must be one of ${REG_TYPES.join(', ')}.`);
    if (s.RegistryPath && !/^(HKLM|HKCU|HKCR|HKU|HKCC):\\/.test(s.RegistryPath)) fail('RegistryPath must start with a PowerShell hive prefix such as HKLM:\\.');
    if (s.RegistryPath?.startsWith('HKCU:') && t.Scope !== 'User') fail('an HKCU path must use Scope "User".');
    if (s.RegistryPath?.startsWith('HKLM:') && t.Scope !== 'System') fail('an HKLM path must use Scope "System".');
    if (s.RegistryPath?.startsWith('HKLM:') && !t.RequiresAdmin) fail('an HKLM write requires RequiresAdmin true.');
  }

  if (t.Provider === 'ServiceStartup') {
    if (!s.ServiceName) fail("ServiceStartup settings require 'ServiceName'.");
    if (!START_TYPES.includes(s.StartupType)) fail(`StartupType must be one of ${START_TYPES.join(', ')}.`);
  }

  if (t.Provider === 'PowerPlan' && !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(s.Guid ?? '')) {
    fail("PowerPlan settings require a valid 'Guid'.");
  }

  if (t.Risk === 'High' && t.EnabledByDefault) fail('a High-risk tweak must not be EnabledByDefault.');
}

for (const w of warnings) console.warn(`warn  ${w}`);

if (errors.length) {
  for (const e of errors) console.error(`error ${e}`);
  console.error(`\n${errors.length} error(s) in Config/Tweaks.json.`);
  process.exit(1);
}

console.log(`OK: ${seen.size} tweak(s), ${providers.size} provider(s), 0 errors, ${warnings.length} warning(s).`);
