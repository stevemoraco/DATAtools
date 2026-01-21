#!/usr/bin/env node

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const WORKSPACE = '/home/runner/workspace';
const HOME = os.homedir();

// Wrap everything in try-catch to prevent crashes
try {
  main();
} catch (err) {
  console.error('');
  console.error('❌ Installation error:', err.message);
  console.error('');
  console.error('You can try running manually:');
  console.error('  curl -fsSL https://claude.ai/install.sh | bash');
  console.error('  npm i -g @openai/codex');
  process.exit(1);
}

function main() {
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

  // Helper to get env var value
  function getEnvVar(name) {
    return process.env[name] || null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // CLAUDE CONFIG DIRECTORY DETECTION
  // ═══════════════════════════════════════════════════════════════════

  // Check for all possible Claude config env vars
  const claudeConfigEnvVars = [
    'CLAUDE_CONFIG_DIR',
    'CLAUDE_WORKSPACE_DIR',
    'CLAUDE_DATA_DIR',
    'CLAUDE_HOME'
  ];

  let claudeEnvVarUsed = null;
  let customClaudeDir = null;

  for (const envVar of claudeConfigEnvVars) {
    const value = getEnvVar(envVar);
    if (value) {
      customClaudeDir = value;
      claudeEnvVarUsed = envVar;
      console.log(`✅ Found ${envVar} = ${value}`);
      break;
    }
  }

  // Determine Claude persistent directory
  let claudePersistentDir = path.join(WORKSPACE, '.claude-persistent');

  if (customClaudeDir) {
    if (customClaudeDir.startsWith(WORKSPACE)) {
      claudePersistentDir = customClaudeDir;
      console.log(`   Using custom Claude directory`);
    } else {
      console.log(`   ⚠️  Custom dir outside workspace - will redirect to workspace for persistence`);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // CODEX CONFIG DIRECTORY DETECTION
  // ═══════════════════════════════════════════════════════════════════

  // Check for Codex config env vars
  const codexConfigEnvVars = [
    'CODEX_HOME',
    'CODEX_CONFIG_DIR',
    'CODEX_DATA_DIR'
  ];

  let codexEnvVarUsed = null;
  let customCodexDir = null;

  for (const envVar of codexConfigEnvVars) {
    const value = getEnvVar(envVar);
    if (value) {
      customCodexDir = value;
      codexEnvVarUsed = envVar;
      console.log(`✅ Found ${envVar} = ${value}`);
      break;
    }
  }

  // Determine Codex persistent directory
  let codexPersistentDir = path.join(WORKSPACE, '.codex-persistent');

  if (customCodexDir) {
    if (customCodexDir.startsWith(WORKSPACE)) {
      codexPersistentDir = customCodexDir;
      console.log(`   Using custom Codex directory`);
    } else {
      console.log(`   ⚠️  Custom dir outside workspace - will redirect to workspace for persistence`);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // CHECK FOR EXISTING CONFIG
  // ═══════════════════════════════════════════════════════════════════

  const existingClaudeConfig = fs.existsSync(claudePersistentDir);
  const existingCodexConfig = fs.existsSync(codexPersistentDir);

  if (existingClaudeConfig) {
    console.log(`✅ Found existing Claude config`);
  }
  if (existingCodexConfig) {
    console.log('✅ Found existing Codex config');
  }

  // Check for API key secrets
  if (getEnvVar('ANTHROPIC_API_KEY')) {
    console.log('✅ Found ANTHROPIC_API_KEY');
  }
  if (getEnvVar('OPENAI_API_KEY')) {
    console.log('✅ Found OPENAI_API_KEY');
  }

  // ═══════════════════════════════════════════════════════════════════
  // CREATE DIRECTORIES
  // ═══════════════════════════════════════════════════════════════════

  const dirs = [
    '.claude-sessions',
    '.local/share/claude/versions',
    '.persistent-home',
    '.config',
    'scripts',
    'logs'
  ];

  // Add Claude persistent dir
  if (claudePersistentDir.startsWith(WORKSPACE)) {
    const relativePath = claudePersistentDir.replace(WORKSPACE + '/', '');
    if (!dirs.includes(relativePath)) {
      dirs.unshift(relativePath);
    }
  }

  // Add Codex persistent dir
  if (codexPersistentDir.startsWith(WORKSPACE)) {
    const relativePath = codexPersistentDir.replace(WORKSPACE + '/', '');
    if (!dirs.includes(relativePath)) {
      dirs.unshift(relativePath);
    }
  }

  console.log('');
  console.log('📁 Creating directories...');
  dirs.forEach(dir => {
    const fullPath = path.join(WORKSPACE, dir);
    if (!fs.existsSync(fullPath)) {
      try {
        fs.mkdirSync(fullPath, { recursive: true });
      } catch (err) {
        console.log(`   ⚠️  Could not create ${dir}: ${err.message}`);
      }
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // INSTALL CLAUDE CODE
  // ═══════════════════════════════════════════════════════════════════

  console.log('');

  let claudeVersions = [];
  try {
    claudeVersions = fs.readdirSync(path.join(WORKSPACE, '.local/share/claude/versions'))
      .filter(f => !f.startsWith('.'));
  } catch {}

  const claudeInstalled = commandExists('claude') ||
    fs.existsSync(path.join(HOME, '.local/bin/claude')) ||
    claudeVersions.length > 0;

  if (!claudeInstalled) {
    console.log('📦 Installing Claude Code...');
    try {
      const installEnv = {
        ...process.env,
        CLAUDE_CONFIG_DIR: claudePersistentDir,
        CLAUDE_WORKSPACE_DIR: claudePersistentDir
      };
      execSync('curl -fsSL https://claude.ai/install.sh | bash', {
        stdio: 'inherit',
        shell: '/bin/bash',
        env: installEnv,
        timeout: 120000 // 2 minute timeout
      });
      console.log('✅ Claude Code installed');
    } catch (err) {
      console.log('⚠️  Claude Code installation had issues (may still work)');
    }
  } else {
    const version = claudeVersions.sort().pop() || 'installed';
    console.log(`✅ Claude Code already installed (${version})`);
  }

  // ═══════════════════════════════════════════════════════════════════
  // INSTALL CODEX CLI
  // ═══════════════════════════════════════════════════════════════════

  const codexInstalled = commandExists('codex');

  if (!codexInstalled) {
    console.log('📦 Installing OpenAI Codex CLI...');
    try {
      const installEnv = {
        ...process.env,
        CODEX_HOME: codexPersistentDir
      };
      execSync('npm i -g @openai/codex', {
        stdio: 'inherit',
        shell: '/bin/bash',
        env: installEnv,
        timeout: 120000 // 2 minute timeout
      });
      console.log('✅ Codex CLI installed');
    } catch (err) {
      console.log('⚠️  Codex installation had issues (may still work)');
    }
  } else {
    console.log('✅ Codex CLI already installed');
  }

  // ═══════════════════════════════════════════════════════════════════
  // SET UP SYMLINKS
  // ═══════════════════════════════════════════════════════════════════

  console.log('');
  console.log('🔗 Setting up symlinks...');

  // Claude symlink
  const claudeLink = path.join(HOME, '.claude');
  try {
    let needsLink = false;
    try {
      const stat = fs.lstatSync(claudeLink);
      if (stat.isSymbolicLink()) {
        const current = fs.readlinkSync(claudeLink);
        if (current !== claudePersistentDir) {
          fs.unlinkSync(claudeLink);
          needsLink = true;
        }
      } else if (stat.isDirectory()) {
        console.log('   Moving existing ~/.claude data to persistent storage...');
        execSync(`cp -rn "${claudeLink}"/* "${claudePersistentDir}/" 2>/dev/null || true`, { shell: '/bin/bash' });
        execSync(`rm -rf "${claudeLink}"`, { shell: '/bin/bash' });
        needsLink = true;
      }
    } catch {
      needsLink = true;
    }

    if (needsLink) {
      fs.symlinkSync(claudePersistentDir, claudeLink);
    }
    console.log(`   ~/.claude → ${claudePersistentDir.replace(WORKSPACE + '/', '')}/`);
  } catch (err) {
    console.log(`   ⚠️  Could not create Claude symlink: ${err.message}`);
  }

  // Codex symlink
  const codexLink = path.join(HOME, '.codex');
  try {
    let needsLink = false;
    try {
      const stat = fs.lstatSync(codexLink);
      if (stat.isSymbolicLink()) {
        const current = fs.readlinkSync(codexLink);
        if (current !== codexPersistentDir) {
          fs.unlinkSync(codexLink);
          needsLink = true;
        }
      } else if (stat.isDirectory()) {
        console.log('   Moving existing ~/.codex data to persistent storage...');
        execSync(`cp -rn "${codexLink}"/* "${codexPersistentDir}/" 2>/dev/null || true`, { shell: '/bin/bash' });
        execSync(`rm -rf "${codexLink}"`, { shell: '/bin/bash' });
        needsLink = true;
      }
    } catch {
      needsLink = true;
    }

    if (needsLink) {
      fs.symlinkSync(codexPersistentDir, codexLink);
    }
    console.log(`   ~/.codex → ${codexPersistentDir.replace(WORKSPACE + '/', '')}/`);
  } catch (err) {
    console.log(`   ⚠️  Could not create Codex symlink: ${err.message}`);
  }

  // Claude binary symlinks
  const localBin = path.join(HOME, '.local/bin');
  const localShare = path.join(HOME, '.local/share');
  const claudeShareTarget = path.join(WORKSPACE, '.local/share/claude');

  try { fs.mkdirSync(localBin, { recursive: true }); } catch {}
  try { fs.mkdirSync(localShare, { recursive: true }); } catch {}

  // Link .local/share/claude
  try {
    let needsLink = false;
    try {
      const stat = fs.lstatSync(path.join(localShare, 'claude'));
      if (stat.isSymbolicLink()) {
        const current = fs.readlinkSync(path.join(localShare, 'claude'));
        if (current !== claudeShareTarget) {
          fs.unlinkSync(path.join(localShare, 'claude'));
          needsLink = true;
        }
      }
    } catch {
      needsLink = true;
    }

    if (needsLink) {
      fs.symlinkSync(claudeShareTarget, path.join(localShare, 'claude'));
    }
    console.log('   ~/.local/share/claude → .local/share/claude/');
  } catch {}

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

  // ═══════════════════════════════════════════════════════════════════
  // COPY SCRIPTS
  // ═══════════════════════════════════════════════════════════════════

  const scriptsDir = path.join(__dirname, 'scripts');
  const targetScriptsDir = path.join(WORKSPACE, 'scripts');

  console.log('');
  console.log('📝 Installing scripts...');

  const scripts = ['setup-claude-code.sh', 'claude-session-manager.sh', 'claude-auth-refresh.sh'];
  scripts.forEach(script => {
    const srcPath = path.join(scriptsDir, script);
    const destPath = path.join(targetScriptsDir, script);

    if (fs.existsSync(srcPath)) {
      try {
        fs.copyFileSync(srcPath, destPath);
        fs.chmodSync(destPath, '755');
        console.log(`   ${script}`);
      } catch (err) {
        console.log(`   ⚠️  Could not copy ${script}: ${err.message}`);
      }
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // CREATE BASHRC
  // ═══════════════════════════════════════════════════════════════════

  console.log('');
  console.log('📝 Creating .config/bashrc...');

  const bashrcContent = `#!/bin/bash
# DATA Tools - Replit Claude & Codex Persistence
# Auto-generated bashrc

# Claude Config Directory (tells Claude where to store data)
export CLAUDE_CONFIG_DIR="${claudePersistentDir}"
export CLAUDE_WORKSPACE_DIR="${claudePersistentDir}"

# Codex Config Directory (tells Codex where to store data)
export CODEX_HOME="${codexPersistentDir}"

# Claude Code Setup
SETUP_SCRIPT="/home/runner/workspace/scripts/setup-claude-code.sh"
[ -f "\${SETUP_SCRIPT}" ] && source "\${SETUP_SCRIPT}"

# Codex Persistence
mkdir -p "${codexPersistentDir}"
[ ! -L "\${HOME}/.codex" ] && ln -sf "${codexPersistentDir}" "\${HOME}/.codex"

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

  try {
    fs.writeFileSync(path.join(WORKSPACE, '.config/bashrc'), bashrcContent);
  } catch (err) {
    console.log(`   ⚠️  Could not write bashrc: ${err.message}`);
  }

  // ═══════════════════════════════════════════════════════════════════
  // UPDATE .replit
  // ═══════════════════════════════════════════════════════════════════

  console.log('📝 Updating .replit configuration...');
  const replitPath = path.join(WORKSPACE, '.replit');
  const onBootLine = 'onBoot = "source /home/runner/workspace/scripts/setup-claude-code.sh 2>/dev/null || true"';

  try {
    if (fs.existsSync(replitPath)) {
      let content = fs.readFileSync(replitPath, 'utf8');
      if (!content.includes('setup-claude-code.sh')) {
        content += '\n\n# Claude persistence (added by DATA Tools)\n' + onBootLine + '\n';
        fs.writeFileSync(replitPath, content);
      }
    } else {
      fs.writeFileSync(replitPath, '# Claude persistence (DATA Tools)\n' + onBootLine + '\n');
    }
  } catch (err) {
    console.log(`   ⚠️  Could not update .replit: ${err.message}`);
  }

  // ═══════════════════════════════════════════════════════════════════
  // UPDATE .gitignore
  // ═══════════════════════════════════════════════════════════════════

  console.log('📝 Updating .gitignore...');
  const gitignorePath = path.join(WORKSPACE, '.gitignore');
  const gitignoreEntries = '\n# Claude/Codex credentials (added by DATA Tools)\n.claude-persistent/\n.codex-persistent/\n';

  try {
    if (fs.existsSync(gitignorePath)) {
      let content = fs.readFileSync(gitignorePath, 'utf8');
      if (!content.includes('.claude-persistent')) {
        fs.writeFileSync(gitignorePath, content + gitignoreEntries);
      }
    } else {
      fs.writeFileSync(gitignorePath, gitignoreEntries.trim() + '\n');
    }
  } catch (err) {
    console.log(`   ⚠️  Could not update .gitignore: ${err.message}`);
  }

  // ═══════════════════════════════════════════════════════════════════
  // SET UP ENVIRONMENT
  // ═══════════════════════════════════════════════════════════════════

  process.env.PATH = `${localBin}:${process.env.PATH}`;
  process.env.CLAUDE_CONFIG_DIR = claudePersistentDir;
  process.env.CLAUDE_WORKSPACE_DIR = claudePersistentDir;
  process.env.CODEX_HOME = codexPersistentDir;

  // ═══════════════════════════════════════════════════════════════════
  // SHOW COMPLETION MESSAGE
  // ═══════════════════════════════════════════════════════════════════

  console.log('');
  console.log('╔═════════════════════════════════════════════════════════════╗');
  console.log('║                                                             ║');
  console.log('║   ✅  DATA Tools Installation Complete!                     ║');
  console.log('║                                                             ║');
  console.log('╠═════════════════════════════════════════════════════════════╣');
  console.log('║                                                             ║');
  console.log('║   Your setup now persists across container restarts:        ║');
  console.log('║                                                             ║');
  console.log('║   • Claude Code conversations & credentials                 ║');
  console.log('║   • Codex CLI data & authentication                         ║');
  console.log('║   • Command history (bash)                                  ║');
  console.log('║   • Per-terminal session tracking                           ║');
  console.log('║                                                             ║');
  console.log('╠═════════════════════════════════════════════════════════════╣');
  console.log('║                                                             ║');
  console.log(`║   Claude config: ${claudePersistentDir.replace(WORKSPACE + '/', '').padEnd(38)}  ║`);
  console.log(`║   Codex config:  ${codexPersistentDir.replace(WORKSPACE + '/', '').padEnd(38)}  ║`);
  console.log('║                                                             ║');
  console.log('╚═════════════════════════════════════════════════════════════╝');
  console.log('');

  // Check if Claude needs login
  let needsLogin = true;
  try {
    const authCheck = execSync('claude auth status 2>&1 || true', {
      encoding: 'utf8',
      shell: '/bin/bash',
      env: process.env,
      timeout: 10000
    });
    if (authCheck.includes('Logged in') || authCheck.includes('valid') || authCheck.includes('authenticated')) {
      needsLogin = false;
    }
  } catch {}

  if (needsLogin && !getEnvVar('ANTHROPIC_API_KEY')) {
    console.log('⚠️  Claude needs authentication. Run: claude login');
    console.log('');
  }

  // ═══════════════════════════════════════════════════════════════════
  // LAUNCH SESSION MANAGER
  // ═══════════════════════════════════════════════════════════════════

  console.log('Launching session manager...');
  console.log('');

  // Use spawn to run bash interactively with our session manager
  const sessionManager = spawn('bash', ['--rcfile', path.join(WORKSPACE, '.config/bashrc'), '-i'], {
    stdio: 'inherit',
    cwd: WORKSPACE,
    env: process.env
  });

  sessionManager.on('error', (err) => {
    console.error('Failed to launch session manager:', err.message);
    process.exit(1);
  });

  sessionManager.on('exit', (code) => {
    process.exit(code || 0);
  });
}
