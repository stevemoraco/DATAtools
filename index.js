#!/usr/bin/env node

const { execSync, spawn, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const WORKSPACE = '/home/runner/workspace';
const HOME = os.homedir();
const REPLIT_TOOLS = path.join(WORKSPACE, '.replit-tools');

// Helper to run commands safely without crashing the installer
function safeExec(cmd, options = {}) {
  try {
    const result = spawnSync('bash', ['-c', cmd], {
      encoding: 'utf8',
      timeout: options.timeout || 120000,
      env: options.env || process.env,
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 10 * 1024 * 1024 // 10MB
    });

    if (options.showOutput && result.stdout) {
      const lines = result.stdout.trim().split('\n');
      if (lines.length <= 5) {
        lines.forEach(l => console.log(`   ${l}`));
      } else {
        console.log(`   ${lines[0]}`);
        console.log(`   ... (${lines.length - 2} more lines)`);
        console.log(`   ${lines[lines.length - 1]}`);
      }
    }

    return {
      success: result.status === 0,
      stdout: result.stdout || '',
      stderr: result.stderr || '',
      status: result.status
    };
  } catch (err) {
    return {
      success: false,
      stdout: '',
      stderr: err.message,
      status: -1
    };
  }
}

// Helper to migrate data from old location to new
function migrateDirectory(oldPath, newPath, description) {
  if (fs.existsSync(oldPath) && !fs.existsSync(newPath)) {
    try {
      console.log(`   Migrating ${description}...`);
      execSync(`cp -rp "${oldPath}" "${newPath}"`, { shell: '/bin/bash' });
      return true;
    } catch (err) {
      console.log(`   ⚠️  Could not migrate ${description}: ${err.message}`);
      return false;
    }
  }
  return false;
}

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
  // DEFINE DIRECTORY STRUCTURE
  // ═══════════════════════════════════════════════════════════════════

  // Default locations inside .replit-tools (all hidden with dots)
  const defaultClaudeDir = path.join(REPLIT_TOOLS, '.claude-persistent');
  const defaultCodexDir = path.join(REPLIT_TOOLS, '.codex-persistent');
  const sessionsDir = path.join(REPLIT_TOOLS, '.claude-sessions');
  const persistentHomeDir = path.join(REPLIT_TOOLS, '.persistent-home');
  const claudeVersionsDir = path.join(REPLIT_TOOLS, '.claude-versions');
  const logsDir = path.join(REPLIT_TOOLS, '.logs');
  const scriptsDir = path.join(REPLIT_TOOLS, 'scripts');

  // Old locations (for migration)
  const oldLocations = {
    claude: path.join(WORKSPACE, '.claude-persistent'),
    codex: path.join(WORKSPACE, '.codex-persistent'),
    sessions: path.join(WORKSPACE, '.claude-sessions'),
    home: path.join(WORKSPACE, '.persistent-home'),
    versions: path.join(WORKSPACE, '.local/share/claude/versions'),
    logs: path.join(WORKSPACE, 'logs'),
    scripts: path.join(WORKSPACE, 'scripts')
  };

  // ═══════════════════════════════════════════════════════════════════
  // CLAUDE CONFIG DIRECTORY DETECTION
  // ═══════════════════════════════════════════════════════════════════

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
  let claudePersistentDir = defaultClaudeDir;
  let usingCustomClaudeDir = false;

  if (customClaudeDir) {
    if (customClaudeDir.startsWith(WORKSPACE)) {
      claudePersistentDir = customClaudeDir;
      usingCustomClaudeDir = true;
      console.log(`   Using custom Claude directory (not migrating)`);
    } else {
      console.log(`   ⚠️  Custom dir outside workspace - using .replit-tools for persistence`);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // CODEX CONFIG DIRECTORY DETECTION
  // ═══════════════════════════════════════════════════════════════════

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
  let codexPersistentDir = defaultCodexDir;
  let usingCustomCodexDir = false;

  if (customCodexDir) {
    if (customCodexDir.startsWith(WORKSPACE)) {
      codexPersistentDir = customCodexDir;
      usingCustomCodexDir = true;
      console.log(`   Using custom Codex directory (not migrating)`);
    } else {
      console.log(`   ⚠️  Custom dir outside workspace - using .replit-tools for persistence`);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // CHECK FOR API KEYS
  // ═══════════════════════════════════════════════════════════════════

  if (getEnvVar('ANTHROPIC_API_KEY')) {
    console.log('✅ Found ANTHROPIC_API_KEY');
  }
  if (getEnvVar('OPENAI_API_KEY')) {
    console.log('✅ Found OPENAI_API_KEY');
  }

  // ═══════════════════════════════════════════════════════════════════
  // CREATE DIRECTORIES
  // ═══════════════════════════════════════════════════════════════════

  console.log('');
  console.log('📁 Creating directories...');

  // Create base .replit-tools directory
  if (!fs.existsSync(REPLIT_TOOLS)) {
    fs.mkdirSync(REPLIT_TOOLS, { recursive: true });
  }

  // Create all subdirectories
  const dirsToCreate = [
    claudePersistentDir,
    codexPersistentDir,
    sessionsDir,
    persistentHomeDir,
    claudeVersionsDir,
    logsDir,
    scriptsDir,
    path.join(WORKSPACE, '.config') // Keep .config in workspace for Replit auto-sourcing
  ];

  dirsToCreate.forEach(dir => {
    if (!fs.existsSync(dir)) {
      try {
        fs.mkdirSync(dir, { recursive: true });
      } catch (err) {
        console.log(`   ⚠️  Could not create ${dir}: ${err.message}`);
      }
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // MIGRATE FROM OLD LOCATIONS
  // ═══════════════════════════════════════════════════════════════════

  console.log('');
  console.log('🔄 Checking for data migration...');

  let migrated = false;

  // Migrate Claude data (only if not using custom dir)
  if (!usingCustomClaudeDir) {
    if (migrateDirectory(oldLocations.claude, claudePersistentDir, 'Claude config')) {
      migrated = true;
    }
  }

  // Migrate Codex data (only if not using custom dir)
  if (!usingCustomCodexDir) {
    if (migrateDirectory(oldLocations.codex, codexPersistentDir, 'Codex config')) {
      migrated = true;
    }
  }

  // Always migrate these (no custom dir options)
  if (migrateDirectory(oldLocations.sessions, sessionsDir, 'session data')) migrated = true;
  if (migrateDirectory(oldLocations.home, persistentHomeDir, 'bash history')) migrated = true;
  if (migrateDirectory(oldLocations.versions, claudeVersionsDir, 'Claude versions')) migrated = true;

  // Migrate logs (just auth-refresh.log)
  if (fs.existsSync(path.join(oldLocations.logs, 'auth-refresh.log')) && !fs.existsSync(path.join(logsDir, 'auth-refresh.log'))) {
    try {
      fs.copyFileSync(path.join(oldLocations.logs, 'auth-refresh.log'), path.join(logsDir, 'auth-refresh.log'));
      migrated = true;
      console.log('   Migrating auth logs...');
    } catch {}
  }

  if (!migrated) {
    console.log('   No migration needed');
  }

  // ═══════════════════════════════════════════════════════════════════
  // INSTALL CLAUDE CODE
  // ═══════════════════════════════════════════════════════════════════

  console.log('');

  let claudeVersions = [];
  try {
    claudeVersions = fs.readdirSync(claudeVersionsDir).filter(f => !f.startsWith('.'));
  } catch {}

  // Also check old location
  if (claudeVersions.length === 0) {
    try {
      claudeVersions = fs.readdirSync(oldLocations.versions).filter(f => !f.startsWith('.'));
    } catch {}
  }

  const claudeInstalled = commandExists('claude') ||
    fs.existsSync(path.join(HOME, '.local/bin/claude')) ||
    claudeVersions.length > 0;

  if (!claudeInstalled) {
    console.log('📦 Installing Claude Code...');
    const installEnv = {
      ...process.env,
      CLAUDE_CONFIG_DIR: claudePersistentDir,
      CLAUDE_WORKSPACE_DIR: claudePersistentDir
    };
    const result = safeExec('curl -fsSL https://claude.ai/install.sh | bash', {
      env: installEnv,
      timeout: 180000,
      showOutput: true
    });

    if (result.success) {
      console.log('✅ Claude Code installed');
      // Move installed version to our directory
      try {
        const defaultVersionsDir = path.join(HOME, '.local/share/claude/versions');
        if (fs.existsSync(defaultVersionsDir)) {
          const versions = fs.readdirSync(defaultVersionsDir).filter(f => !f.startsWith('.'));
          versions.forEach(v => {
            const src = path.join(defaultVersionsDir, v);
            const dest = path.join(claudeVersionsDir, v);
            if (!fs.existsSync(dest)) {
              fs.copyFileSync(src, dest);
              fs.chmodSync(dest, '755');
            }
          });
        }
      } catch {}
    } else {
      console.log('⚠️  Claude Code installation had issues (may still work)');
      if (result.stderr && result.stderr.length < 200) {
        console.log(`   ${result.stderr.trim()}`);
      }
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
    const installEnv = {
      ...process.env,
      CODEX_HOME: codexPersistentDir
    };
    const result = safeExec('npm i -g @openai/codex', {
      env: installEnv,
      timeout: 180000,
      showOutput: true
    });

    if (result.success) {
      console.log('✅ Codex CLI installed');
    } else {
      console.log('⚠️  Codex installation had issues (may still work)');
      if (result.stderr && result.stderr.length < 200) {
        console.log(`   ${result.stderr.trim()}`);
      }
    }
  } else {
    console.log('✅ Codex CLI already installed');
  }

  // ═══════════════════════════════════════════════════════════════════
  // SET UP SYMLINKS
  // ═══════════════════════════════════════════════════════════════════

  console.log('');
  console.log('🔗 Setting up symlinks...');

  // Claude config symlink (~/.claude -> our persistent dir)
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
    const displayPath = claudePersistentDir.replace(WORKSPACE + '/', '');
    console.log(`   ~/.claude → ${displayPath}/`);
  } catch (err) {
    console.log(`   ⚠️  Could not create Claude symlink: ${err.message}`);
  }

  // Codex config symlink (~/.codex -> our persistent dir)
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
    const displayPath = codexPersistentDir.replace(WORKSPACE + '/', '');
    console.log(`   ~/.codex → ${displayPath}/`);
  } catch (err) {
    console.log(`   ⚠️  Could not create Codex symlink: ${err.message}`);
  }

  // Claude binary symlinks
  const localBin = path.join(HOME, '.local/bin');
  const localShare = path.join(HOME, '.local/share');

  try { fs.mkdirSync(localBin, { recursive: true }); } catch {}
  try { fs.mkdirSync(localShare, { recursive: true }); } catch {}

  // Link .local/share/claude to our versions directory's parent
  const claudeShareTarget = path.join(REPLIT_TOOLS, '.claude-versions');
  try {
    // Create a wrapper directory structure for compatibility
    const shareClaudeDir = path.join(localShare, 'claude');
    const shareVersionsDir = path.join(shareClaudeDir, 'versions');

    if (!fs.existsSync(shareClaudeDir)) {
      fs.mkdirSync(shareClaudeDir, { recursive: true });
    }

    // Symlink versions dir
    try {
      const stat = fs.lstatSync(shareVersionsDir);
      if (stat.isSymbolicLink()) {
        const current = fs.readlinkSync(shareVersionsDir);
        if (current !== claudeVersionsDir) {
          fs.unlinkSync(shareVersionsDir);
          fs.symlinkSync(claudeVersionsDir, shareVersionsDir);
        }
      }
    } catch {
      fs.symlinkSync(claudeVersionsDir, shareVersionsDir);
    }
    console.log(`   ~/.local/share/claude/versions → .replit-tools/.claude-versions/`);
  } catch {}

  // Link binary to latest version
  try {
    let versions = [];
    try {
      versions = fs.readdirSync(claudeVersionsDir).filter(f => !f.startsWith('.')).sort();
    } catch {}

    if (versions.length > 0) {
      const latest = versions[versions.length - 1];
      const binaryPath = path.join(claudeVersionsDir, latest);
      const binLink = path.join(localBin, 'claude');
      try { fs.unlinkSync(binLink); } catch {}
      fs.symlinkSync(binaryPath, binLink);
      console.log(`   ~/.local/bin/claude → .replit-tools/.claude-versions/${latest}`);
    }
  } catch {}

  // ═══════════════════════════════════════════════════════════════════
  // COPY SCRIPTS
  // ═══════════════════════════════════════════════════════════════════

  const packageScriptsDir = path.join(__dirname, 'scripts');

  console.log('');
  console.log('📝 Installing scripts...');

  const scriptFiles = ['setup-claude-code.sh', 'claude-session-manager.sh', 'claude-auth-refresh.sh'];
  scriptFiles.forEach(script => {
    const srcPath = path.join(packageScriptsDir, script);
    const destPath = path.join(scriptsDir, script);

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
# Auto-generated bashrc - v2.0 (.replit-tools structure)

# Base directory for all DATA Tools data
export REPLIT_TOOLS_DIR="${REPLIT_TOOLS}"

# Claude Config Directory (tells Claude where to store data)
export CLAUDE_CONFIG_DIR="${claudePersistentDir}"
export CLAUDE_WORKSPACE_DIR="${claudePersistentDir}"

# Codex Config Directory (tells Codex where to store data)
export CODEX_HOME="${codexPersistentDir}"

# Claude Code Setup
SETUP_SCRIPT="${scriptsDir}/setup-claude-code.sh"
[ -f "\${SETUP_SCRIPT}" ] && source "\${SETUP_SCRIPT}"

# Codex Persistence
mkdir -p "${codexPersistentDir}"
[ ! -L "\${HOME}/.codex" ] && ln -sf "${codexPersistentDir}" "\${HOME}/.codex"

# Bash History Persistence
PERSISTENT_HOME="${persistentHomeDir}"
mkdir -p "\${PERSISTENT_HOME}"
export HISTFILE="\${PERSISTENT_HOME}/.bash_history"
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups
[ -f "\${HISTFILE}" ] && history -r "\${HISTFILE}"

# Session Manager (interactive menu)
SESSION_MANAGER="${scriptsDir}/claude-session-manager.sh"
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
  const onBootLine = `onBoot = "source ${scriptsDir}/setup-claude-code.sh 2>/dev/null || true"`;

  try {
    if (fs.existsSync(replitPath)) {
      let content = fs.readFileSync(replitPath, 'utf8');
      // Remove old onBoot line if present
      content = content.replace(/onBoot\s*=\s*"[^"]*setup-claude-code\.sh[^"]*"\n?/g, '');
      if (!content.includes('setup-claude-code.sh')) {
        content += '\n\n# Claude persistence (added by DATA Tools)\n' + onBootLine + '\n';
      }
      fs.writeFileSync(replitPath, content);
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
  const gitignoreEntries = `
# DATA Tools - All sensitive data in one place (added by DATA Tools)
.replit-tools/
`;

  try {
    if (fs.existsSync(gitignorePath)) {
      let content = fs.readFileSync(gitignorePath, 'utf8');
      if (!content.includes('.replit-tools/')) {
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
  process.env.REPLIT_TOOLS_DIR = REPLIT_TOOLS;

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
  console.log('║   All data stored in: .replit-tools/                        ║');
  console.log('║                                                             ║');
  const claudeDisplay = claudePersistentDir.replace(WORKSPACE + '/', '').padEnd(40);
  const codexDisplay = codexPersistentDir.replace(WORKSPACE + '/', '').padEnd(40);
  console.log(`║   Claude: ${claudeDisplay} ║`);
  console.log(`║   Codex:  ${codexDisplay} ║`);
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
