#!/usr/bin/env node

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const WORKSPACE = '/home/runner/workspace';

// Check if we're on Replit
if (!fs.existsSync(WORKSPACE)) {
  console.error('❌ This tool must be run on Replit');
  console.error('   /home/runner/workspace not found');
  process.exit(1);
}

console.log('');
console.log('╭─────────────────────────────────────────────────────────╮');
console.log('│  Replit Claude Persistence Installer                    │');
console.log('╰─────────────────────────────────────────────────────────╯');
console.log('');

// Create directories
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

console.log('📁 Creating directories...');
dirs.forEach(dir => {
  const fullPath = path.join(WORKSPACE, dir);
  if (!fs.existsSync(fullPath)) {
    fs.mkdirSync(fullPath, { recursive: true });
  }
});

// Copy scripts from the package
const scriptsDir = path.join(__dirname, 'scripts');
const targetScriptsDir = path.join(WORKSPACE, 'scripts');

console.log('📝 Installing scripts...');

// Read and write each script
const scripts = ['setup-claude-code.sh', 'claude-session-manager.sh'];
scripts.forEach(script => {
  const srcPath = path.join(scriptsDir, script);
  const destPath = path.join(targetScriptsDir, script);

  if (fs.existsSync(srcPath)) {
    fs.copyFileSync(srcPath, destPath);
    fs.chmodSync(destPath, '755');
  }
});

// Create/update .config/bashrc
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

console.log('');
console.log('✅ Installation complete!');
console.log('');
console.log('What happens now:');
console.log('  • New shells will show the Claude session picker');
console.log('  • Your conversations persist across container restarts');
console.log('  • Claude binary is cached (faster startup)');
console.log('  • Bash history is preserved');
console.log('');
console.log('To test, open a new shell or run:');
console.log('  source ~/.config/bashrc');
console.log('');
console.log('Options:');
console.log("  Press 'c' - Continue last session");
console.log("  Press 'r' - Pick from session list");
console.log("  Press 'n' - New session");
console.log("  Press 's' - Skip (just a shell)");
console.log('');
console.log('To disable the menu: export CLAUDE_NO_PROMPT=true');
console.log('');
