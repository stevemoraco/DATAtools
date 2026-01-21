#!/usr/bin/env node

const { execSync, spawn, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const WORKSPACE = '/home/runner/workspace';
const HOME = os.homedir();

// Check if we're on Replit
if (!fs.existsSync(WORKSPACE)) {
  console.error('❌ This tool must be run on Replit');
  console.error('   /home/runner/workspace not found');
  process.exit(1);
}

console.log('');
console.log('╭─────────────────────────────────────────────────────────╮');
console.log('│  Replit Tools - Claude & Codex Persistence             │');
console.log('╰─────────────────────────────────────────────────────────╯');
console.log('');

// Helper to check if command exists
function commandExists(cmd) {
  try {
    execSync(`which ${cmd}`, { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

// Helper to check for Replit secret
function hasReplitSecret(name) {
  return process.env[name] !== undefined;
}

// Check for existing persistent config
const existingClaudeConfig = fs.existsSync(path.join(WORKSPACE, '.claude-persistent'));
const existingCodexConfig = fs.existsSync(path.join(WORKSPACE, '.codex-persistent'));

if (existingClaudeConfig) {
  console.log('✅ Found existing Claude config in workspace');
}
if (existingCodexConfig) {
  console.log('✅ Found existing Codex config in workspace');
}

// Check for Replit secrets
if (hasReplitSecret('ANTHROPIC_API_KEY')) {
  console.log('✅ Found ANTHROPIC_API_KEY in Replit secrets');
}
if (hasReplitSecret('OPENAI_API_KEY')) {
  console.log('✅ Found OPENAI_API_KEY in Replit secrets');
}

// Create directories (preserving existing data)
const dirs = [
  '.claude-persistent',
  '.codex-persistent',
  '.claude-sessions',
  '.local/share/claude/versions',
  '.persistent-home',
  '.config',
  'scripts',
  'logs'
];

console.log('');
console.log('📁 Creating directories...');
dirs.forEach(dir => {
  const fullPath = path.join(WORKSPACE, dir);
  if (!fs.existsSync(fullPath)) {
    fs.mkdirSync(fullPath, { recursive: true });
  }
});

// Check and install Claude Code if needed
console.log('');
const claudeInstalled = commandExists('claude') ||
  fs.existsSync(path.join(HOME, '.local/bin/claude')) ||
  fs.existsSync(path.join(WORKSPACE, '.local/share/claude/versions'));

let claudeVersions = [];
try {
  claudeVersions = fs.readdirSync(path.join(WORKSPACE, '.local/share/claude/versions'));
} catch {}

if (!claudeInstalled || claudeVersions.length === 0) {
  console.log('📦 Installing Claude Code...');
  try {
    execSync('curl -fsSL https://claude.ai/install.sh | bash', {
      stdio: 'inherit',
      shell: '/bin/bash'
    });
    console.log('✅ Claude Code installed');
  } catch (err) {
    console.log('⚠️  Claude Code installation failed (you can install manually later)');
  }
} else {
  const version = claudeVersions.sort().pop() || 'unknown';
  console.log(`✅ Claude Code already installed (${version})`);
}

// Check and install Codex if needed
const codexInstalled = commandExists('codex');

if (!codexInstalled) {
  console.log('📦 Installing OpenAI Codex CLI...');
  try {
    execSync('npm i -g @openai/codex', {
      stdio: 'inherit',
      shell: '/bin/bash'
    });
    console.log('✅ Codex CLI installed');
  } catch (err) {
    console.log('⚠️  Codex installation failed (you can install manually later)');
  }
} else {
  console.log('✅ Codex CLI already installed');
}

// Set up symlinks
console.log('');
console.log('🔗 Setting up symlinks...');

// Claude symlink
const claudeTarget = path.join(WORKSPACE, '.claude-persistent');
const claudeLink = path.join(HOME, '.claude');
try {
  const stat = fs.lstatSync(claudeLink);
  if (stat.isSymbolicLink()) {
    const current = fs.readlinkSync(claudeLink);
    if (current !== claudeTarget) {
      fs.unlinkSync(claudeLink);
      fs.symlinkSync(claudeTarget, claudeLink);
    }
  } else if (stat.isDirectory()) {
    // Move existing data to persistent location
    console.log('   Moving existing ~/.claude data to persistent storage...');
    execSync(`cp -rn ${claudeLink}/* ${claudeTarget}/ 2>/dev/null || true`, { shell: '/bin/bash' });
    execSync(`rm -rf ${claudeLink}`, { shell: '/bin/bash' });
    fs.symlinkSync(claudeTarget, claudeLink);
  }
} catch {
  // Doesn't exist, create it
  fs.symlinkSync(claudeTarget, claudeLink);
}
console.log('   ~/.claude → .claude-persistent/');

// Codex symlink
const codexTarget = path.join(WORKSPACE, '.codex-persistent');
const codexLink = path.join(HOME, '.codex');
try {
  const stat = fs.lstatSync(codexLink);
  if (stat.isSymbolicLink()) {
    const current = fs.readlinkSync(codexLink);
    if (current !== codexTarget) {
      fs.unlinkSync(codexLink);
      fs.symlinkSync(codexTarget, codexLink);
    }
  } else if (stat.isDirectory()) {
    console.log('   Moving existing ~/.codex data to persistent storage...');
    execSync(`cp -rn ${codexLink}/* ${codexTarget}/ 2>/dev/null || true`, { shell: '/bin/bash' });
    execSync(`rm -rf ${codexLink}`, { shell: '/bin/bash' });
    fs.symlinkSync(codexTarget, codexLink);
  }
} catch {
  fs.symlinkSync(codexTarget, codexLink);
}
console.log('   ~/.codex → .codex-persistent/');

// Claude binary symlinks
const localBin = path.join(HOME, '.local/bin');
const localShare = path.join(HOME, '.local/share');
const claudeShareTarget = path.join(WORKSPACE, '.local/share/claude');

try { fs.mkdirSync(localBin, { recursive: true }); } catch {}
try { fs.mkdirSync(localShare, { recursive: true }); } catch {}

// Link .local/share/claude
try {
  const stat = fs.lstatSync(path.join(localShare, 'claude'));
  if (stat.isSymbolicLink()) {
    const current = fs.readlinkSync(path.join(localShare, 'claude'));
    if (current !== claudeShareTarget) {
      fs.unlinkSync(path.join(localShare, 'claude'));
      fs.symlinkSync(claudeShareTarget, path.join(localShare, 'claude'));
    }
  }
} catch {
  try {
    fs.symlinkSync(claudeShareTarget, path.join(localShare, 'claude'));
  } catch {}
}
console.log('   ~/.local/share/claude → .local/share/claude/');

// Link binary to latest version
try {
  const versions = fs.readdirSync(path.join(WORKSPACE, '.local/share/claude/versions')).sort();
  if (versions.length > 0) {
    const latest = versions[versions.length - 1];
    const binaryPath = path.join(WORKSPACE, '.local/share/claude/versions', latest);
    const binLink = path.join(localBin, 'claude');
    try { fs.unlinkSync(binLink); } catch {}
    fs.symlinkSync(binaryPath, binLink);
    console.log(`   ~/.local/bin/claude → versions/${latest}`);
  }
} catch {}

// Copy scripts from the package
const scriptsDir = path.join(__dirname, 'scripts');
const targetScriptsDir = path.join(WORKSPACE, 'scripts');

console.log('');
console.log('📝 Installing scripts...');

const scripts = ['setup-claude-code.sh', 'claude-session-manager.sh'];
scripts.forEach(script => {
  const srcPath = path.join(scriptsDir, script);
  const destPath = path.join(targetScriptsDir, script);

  if (fs.existsSync(srcPath)) {
    fs.copyFileSync(srcPath, destPath);
    fs.chmodSync(destPath, '755');
    console.log(`   ${script}`);
  }
});

// Create/update .config/bashrc
console.log('');
console.log('📝 Creating .config/bashrc...');
const bashrcContent = `#!/bin/bash
# Replit Claude Persistence - Auto-generated bashrc

# Claude Code Setup
SETUP_SCRIPT="/home/runner/workspace/scripts/setup-claude-code.sh"
[ -f "\${SETUP_SCRIPT}" ] && source "\${SETUP_SCRIPT}"

# Codex Persistence
CODEX_PERSISTENT="/home/runner/workspace/.codex-persistent"
mkdir -p "\${CODEX_PERSISTENT}"
[ ! -L "\${HOME}/.codex" ] && ln -sf "\${CODEX_PERSISTENT}" "\${HOME}/.codex"

# Bash History Persistence
PERSISTENT_HOME="/home/runner/workspace/.persistent-home"
mkdir -p "\${PERSISTENT_HOME}"
export HISTFILE="\${PERSISTENT_HOME}/.bash_history"
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups
[ -f "\${HISTFILE}" ] && history -r "\${HISTFILE}"

# Session Manager (interactive menu)
SESSION_MANAGER="/home/runner/workspace/scripts/claude-session-manager.sh"
[ -f "\${SESSION_MANAGER}" ] && source "\${SESSION_MANAGER}"

# Aliases
alias cr='claude -c --dangerously-skip-permissions'
alias claude-resume='claude -c --dangerously-skip-permissions'
alias claude-pick='claude -r --dangerously-skip-permissions'
`;

fs.writeFileSync(path.join(WORKSPACE, '.config/bashrc'), bashrcContent);

// Update .replit
console.log('📝 Updating .replit configuration...');
const replitPath = path.join(WORKSPACE, '.replit');
const onBootLine = 'onBoot = "source /home/runner/workspace/scripts/setup-claude-code.sh 2>/dev/null || true"';

if (fs.existsSync(replitPath)) {
  let content = fs.readFileSync(replitPath, 'utf8');
  if (!content.includes('setup-claude-code.sh')) {
    content += '\n\n# Claude persistence (added by installer)\n' + onBootLine + '\n';
    fs.writeFileSync(replitPath, content);
  }
} else {
  fs.writeFileSync(replitPath, '# Claude persistence\n' + onBootLine + '\n');
}

// Update .gitignore (only essential sensitive dirs)
console.log('📝 Updating .gitignore...');
const gitignorePath = path.join(WORKSPACE, '.gitignore');
const gitignoreEntries = '\n# Claude/Codex credentials (added by replit-tools)\n.claude-persistent/\n.codex-persistent/\n';

if (fs.existsSync(gitignorePath)) {
  let content = fs.readFileSync(gitignorePath, 'utf8');
  if (!content.includes('.claude-persistent')) {
    fs.writeFileSync(gitignorePath, content + gitignoreEntries);
  }
} else {
  fs.writeFileSync(gitignorePath, gitignoreEntries.trim() + '\n');
}

// Add PATH to current process for session manager
process.env.PATH = `${localBin}:${process.env.PATH}`;

console.log('');
console.log('╭─────────────────────────────────────────────────────────╮');
console.log('│  ✅ Installation complete!                              │');
console.log('╰─────────────────────────────────────────────────────────╯');
console.log('');
console.log('Your conversations and credentials now persist across restarts.');
console.log('');

// Check if Claude needs login
let needsLogin = true;
try {
  const authCheck = execSync('claude auth status 2>&1 || true', { encoding: 'utf8', shell: '/bin/bash' });
  if (authCheck.includes('Logged in') || authCheck.includes('valid')) {
    needsLogin = false;
  }
} catch {}

if (needsLogin && !hasReplitSecret('ANTHROPIC_API_KEY')) {
  console.log('⚠️  Claude needs authentication. Run: claude login');
  console.log('');
}

// Launch the session picker
console.log('Launching session manager...');
console.log('');

// Use spawn to run bash interactively with our session manager
const sessionManager = spawn('bash', ['--rcfile', path.join(WORKSPACE, '.config/bashrc'), '-i'], {
  stdio: 'inherit',
  cwd: WORKSPACE
});

sessionManager.on('exit', (code) => {
  process.exit(code || 0);
});
