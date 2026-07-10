const fs = require('fs');
const path = require('path');
const os = require('os');

const SKILL_NAME = 'ai-zemax-optical-design';
const srcDir = __dirname;
const TARGETS = {
  claude: {
    label: 'Claude Code',
    root: () => path.join(os.homedir(), '.claude', 'skills'),
    restart: 'Restart Claude Code to use it.',
  },
  codex: {
    label: 'Codex',
    root: () => path.join(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'), 'skills'),
    restart: 'Restart Codex to use it.',
  },
};

function parseArgs(argv) {
  const options = {
    target: (process.env.SKILL_TARGET || 'claude').toLowerCase(),
    destRoot: null,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--target') {
      options.target = (argv[++i] || '').toLowerCase();
    } else if (arg.startsWith('--target=')) {
      options.target = arg.slice('--target='.length).toLowerCase();
    } else if (arg === '--codex') {
      options.target = 'codex';
    } else if (arg === '--claude') {
      options.target = 'claude';
    } else if (arg === '--dest') {
      options.destRoot = argv[++i] || null;
    } else if (arg.startsWith('--dest=')) {
      options.destRoot = arg.slice('--dest='.length);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!TARGETS[options.target]) {
    throw new Error(`Unsupported target "${options.target}". Use "claude" or "codex".`);
  }

  return options;
}

function copyDir(src, dest) {
  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      fs.mkdirSync(destPath, { recursive: true });
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const target = TARGETS[options.target];
  const destRoot = options.destRoot ? path.resolve(options.destRoot) : target.root();
  const destDir = path.join(destRoot, SKILL_NAME);

  console.log(`\nInstalling "${SKILL_NAME}" skill for ${target.label}...\n`);

  // Ensure destination exists
  fs.mkdirSync(destDir, { recursive: true });

  // Copy SKILL.md
  const skillMd = path.join(srcDir, 'SKILL.md');
  if (fs.existsSync(skillMd)) {
    fs.copyFileSync(skillMd, path.join(destDir, 'SKILL.md'));
    console.log('  copied SKILL.md');
  }

  // Copy subdirectories
  const dirs = ['agents', 'scripts', 'references', 'examples', 'tests'];
  for (const dir of dirs) {
    const src = path.join(srcDir, dir);
    const dest = path.join(destDir, dir);
    if (fs.existsSync(src)) {
      fs.mkdirSync(dest, { recursive: true });
      copyDir(src, dest);
      console.log(`  copied ${dir}/`);
    }
  }

  console.log(`\nSkill installed to: ${destDir}`);
  console.log(`   ${target.restart}\n`);
}

try {
  main();
} catch (error) {
  console.error(`Error: ${error.message}`);
  process.exit(1);
}
