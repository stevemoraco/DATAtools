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
console.log('│  DATA Tools - Claude & Codex Persistence               │');
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

// Helper to get Replit secret value
function getReplitSecret(name) {
  return process.env[name] || null;
}

// Check for CLAUDE_CONFIG_DIR or similar env vars that specify custom Claude location
const claudeConfigEnvVars = [
  'CLAUDE_CONFIG_DIR',
  'CLAUDE_WORKSPACE_DIR',
  'CLAUDE_DATA_DIR',
  'CLAUDE_HOME'
];

let customClaudeDir = null;
for (const envVar of claudeConfigEnvVars) {
  const value = getReplitSecret(envVar);
  if (value) {
    customClaudeDir = value;
    console.log(`✅ Found ${envVar} = ${value}`);
    break;
  }
}

// Determine Claude persistent directory
// Priority: 1) CLAUDE_CONFIG_DIR from env, 2) existing .claude-persistent, 3) default
let claudePersistentDir = path.join(WORKSPACE, '.claude-persistent');

if (customClaudeDir) {
  // User has specified a custom directory via env var
  if (customClaudeDir.startsWith(WORKSPACE)) {
    // It's already in workspace - use it directly
    claudePersistentDir = customClaudeDir;
    console.log(`   Using custom Claude directory: ${claudePersistentDir}`);
  } else {
    // It's outside workspace - we'll symlink to it but also ensure persistence
    console.log(`   Custom dir outside workspace - will set up persistence`);
  }
}

// Check for existing persistent config
const existingClaudeConfig = fs.existsSync(claudePersistentDir);
const existingCodexConfig = fs.existsSync(path.join(WORKSPACE, '.codex-persistent'));

if (existingClaudeConfig) {
  console.log(`✅ Found existing Claude config at ${claudePersistentDir}`);
}
if (existingCodexConfig) {
  console.log('✅ Found existing Codex config in workspace');
}

// Check for API key secrets
if (getReplitSecret('ANTHROPIC_API_KEY')) {
  console.log('✅ Found ANTHROPIC_API_KEY in Replit secrets');
}
if (getReplitSecret('OPENAI_API_KEY')) {
  console.log('✅ Found OPENAI_API_KEY in Replit secrets');
}

// Create directories (preserving existing data)
const dirs = [
  '.codex-persistent',
  '.claude-sessions',
  '.local/share/claude/versions',
  '.persistent-home',
  '.config',
  'scripts',
  'logs'
];

// Add Claude persistent dir if it's relative to workspace
if (claudePersistentDir.startsWith(WORKSPACE)) {
  const relativePath = claudePersistentDir.replace(WORKSPACE + '/', '');
  if (!dirs.includes(relativePath)) {
    dirs.unshift(relativePath);
  }
}

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
  claudeVersions = fs.readdirSync(path.join(WORKSPACE, '.local/share/claude/versions'))
    .filter(f => !f.startsWith('.'));
} catch {}

if (!claudeInstalled || claudeVersions.length === 0) {
  console.log('📦 Installing Claude Code...');
  try {
    // Set CLAUDE_CONFIG_DIR before install so it installs to the right place
    const installEnv = { ...process.env, CLAUDE_CONFIG_DIR: claudePersistentDir };
    execSync('curl -fsSL https://claude.ai/install.sh | bash', {
      stdio: 'inherit',
      shell: '/bin/bash',
      env: installEnv
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

// Claude symlink - only if we're using default location
const claudeLink = path.join(HOME, '.claude');
if (!customClaudeDir || customClaudeDir.startsWith(WORKSPACE)) {
  try {
    const stat = fs.lstatSync(claudeLink);
    if (stat.isSymbolicLink()) {
      const current = fs.readlinkSync(claudeLink);
      if (current !== claudePersistentDir) {
        fs.unlinkSync(claudeLink);
        fs.symlinkSync(claudePersistentDir, claudeLink);
      }
    } else if (stat.isDirectory()) {
      // Move existing data to persistent location
      console.log('   Moving existing ~/.claude data to persistent storage...');
      execSync(`cp -rn ${claudeLink}/* ${claudePersistentDir}/ 2>/dev/null || true`, { shell: '/bin/bash' });
      execSync(`rm -rf ${claudeLink}`, { shell: '/bin/bash' });
      fs.symlinkSync(claudePersistentDir, claudeLink);
    }
  } catch {
    // Doesn't exist, create it
    fs.symlinkSync(claudePersistentDir, claudeLink);
  }
  console.log(`   ~/.claude → ${claudePersistentDir.replace(WORKSPACE + '/', '')}/`);
}

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
  const versions = fs.readdirSync(path.join(WORKSPACE, '.local/share/claude/versions'))
    .filter(f => !f.startsWith('.'))
    .sort();
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

// Create/update .config/bashrc with CLAUDE_CONFIG_DIR export
console.log('');
console.log('📝 Creating .config/bashrc...');
const bashrcContent = `#!/bin/bash
# DATA Tools - Replit Claude & Codex Persistence
# Auto-generated bashrc

# Claude Config Directory (tells Claude where to store data)
export CLAUDE_CONFIG_DIR="${claudePersistentDir}"

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
    content += '\n\n# Claude persistence (added by DATA Tools)\n' + onBootLine + '\n';
    fs.writeFileSync(replitPath, content);
  }
} else {
  fs.writeFileSync(replitPath, '# Claude persistence (DATA Tools)\n' + onBootLine + '\n');
}

// Update .gitignore (only essential sensitive dirs)
console.log('📝 Updating .gitignore...');
const gitignorePath = path.join(WORKSPACE, '.gitignore');
const gitignoreEntries = '\n# Claude/Codex credentials (added by DATA Tools)\n.claude-persistent/\n.codex-persistent/\n';

if (fs.existsSync(gitignorePath)) {
  let content = fs.readFileSync(gitignorePath, 'utf8');
  if (!content.includes('.claude-persistent')) {
    fs.writeFileSync(gitignorePath, content + gitignoreEntries);
  }
} else {
  fs.writeFileSync(gitignorePath, gitignoreEntries.trim() + '\n');
}

// Add PATH and CLAUDE_CONFIG_DIR to current process
process.env.PATH = `${localBin}:${process.env.PATH}`;
process.env.CLAUDE_CONFIG_DIR = claudePersistentDir;

console.log('');
console.log('╭─────────────────────────────────────────────────────────╮');
console.log('│  ✅ Installation complete!                              │');
console.log('╰─────────────────────────────────────────────────────────╯');
console.log('');
console.log('Your conversations and credentials now persist across restarts.');
console.log(`Claude config directory: ${claudePersistentDir}`);
console.log('');

// Check if Claude needs login
let needsLogin = true;
try {
  const authCheck = execSync('claude auth status 2>&1 || true', {
    encoding: 'utf8',
    shell: '/bin/bash',
    env: { ...process.env, CLAUDE_CONFIG_DIR: claudePersistentDir }
  });
  if (authCheck.includes('Logged in') || authCheck.includes('valid')) {
    needsLogin = false;
  }
} catch {}

if (needsLogin && !getReplitSecret('ANTHROPIC_API_KEY')) {
  console.log('⚠️  Claude needs authentication. Run: claude login');
  console.log('');
}

// Launch the session picker
console.log('Launching session manager...');
console.log('');

// Use spawn to run bash interactively with our session manager
const sessionManager = spawn('bash', ['--rcfile', path.join(WORKSPACE, '.config/bashrc'), '-i'], {
  stdio: 'inherit',
  cwd: WORKSPACE,
  env: { ...process.env, CLAUDE_CONFIG_DIR: claudePersistentDir }
});

sessionManager.on('exit', (code) => {
  process.exit(code || 0);
});
