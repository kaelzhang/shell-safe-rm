// Data-safety regression tests for issues found in the deep audit.
// These run on the native platform (custom SAFE_RM_TRASH routes macOS through
// mac_trash and Linux through linux_trash, exercising the shared logic).

const path = require('path')
const fs = require('fs')

const fsp = fs.promises
const {spawn} = require('child_process')
const tmp = require('tmp')
const fse = require('fs-extra')
const {v4: uuid} = require('uuid')
const test = require('ava')

const SAFE_RM = path.join(__dirname, '..', 'bin', 'rm.sh')
const IS_ROOT = process.getuid() === 0
const IS_MACOS = process.platform === 'darwin'
const TMP_ROOT = fs.realpathSync(tmp.dirSync().name)
const BASE = path.join(TMP_ROOT, 'safe-rm-safety')

async function setup () {
  const root = path.join(BASE, uuid())
  const trash = path.join(root, 'trash')
  const work = path.join(root, 'work')
  await Promise.all([fse.ensureDir(trash), fse.ensureDir(work)])
  return {root, trash, work}
}

// Runner that answers interactive prompts from `input` (one per prompt).
function run (args, {
  trash,
  cwd,
  input = [],
  env = {}
} = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(SAFE_RM, args, {
      cwd,
      env: {
        ...process.env,
        XDG_CONFIG_HOME: '',
        SAFE_RM_TRASH: trash,
        ...env
      }
    })

    const queue = [...input]
    let stdout = ''
    let stderr = ''

    child.stdout.on('data', d => {
      stdout += d.toString()
      if (/[?:]\s*$/.test(stdout)) {
        const next = queue.shift()
        if (next === undefined) {
          child.stdin.end()
          return
        }
        child.stdin.write(`${next}\n`)
        stdout += `${next}\n`
        if (queue.length === 0) {
          child.stdin.end()
        }
      }
    })
    child.stderr.on('data', d => {
      stderr += d.toString()
    })
    child.on('error', reject)
    child.on('close', code => resolve({code, stdout, stderr}))
  })
}

const exists = p => fse.pathExists(p)

test('C1: cannot-enter directory must not trash its parent and siblings', async t => {
  if (IS_ROOT) {
    t.pass('skipped as root (permission bits are ignored)')
    return
  }

  const {trash, work} = await setup()
  const proj = path.join(work, 'proj')
  const data = path.join(proj, 'data')
  const notes = path.join(proj, 'notes.txt')
  await fse.ensureDir(data)
  await fsp.writeFile(path.join(data, 'x.txt'), 'inner')
  await fsp.writeFile(notes, 'IMPORTANT SIBLING DATA')

  // Make the target directory non-searchable (no execute bit), so the
  // cd-into-target heuristic fails. It stays writable so the move can succeed.
  await fsp.chmod(data, 0o0600)

  try {
    // User asks to remove ONLY ./data, from within proj/.
    const {code} = await run(['-rf', './data'], {trash, cwd: proj})

    t.is(code, 0, 'exit 0')
    t.true(await exists(proj), 'parent proj/ must survive')
    t.true(await exists(notes), 'unrelated sibling notes.txt must survive')
    t.false(await exists(data), 'the intended target ./data should be trashed')
    t.false(await exists(path.join(trash, 'proj')), 'parent must NOT be trashed (the C1 bug)')
  } finally {
    await fsp.chmod(data, 0o0755).catch(() => {})
  }
})

test('H2: -I prompts once for more than three files (10 files)', async t => {
  const {trash, work} = await setup()

  const files = await Promise.all(
    Array.from({length: 10}, (_, i) => i).map(async i => {
      const f = path.join(work, `f${i}.txt`)
      await fsp.writeFile(f, `content-${i}`)
      return f
    })
  )

  // Decline the once-prompt -> nothing should be removed.
  const {stdout} = await run(['-I', ...files], {trash, input: ['n']})

  t.true(stdout.includes('remove all arguments?'), 'the -I once-prompt must fire for >3 files')
  const survived = await Promise.all(files.map(f => exists(f)))
  survived.forEach((ok, i) => {
    t.true(ok, `${path.basename(files[i])} must survive after declining`)
  })
})

// When -i is given, a per-file confirmation must always fire (BSD semantics),
// even when -I is also present (and would otherwise enter once-mode and skip
// the prompt for a single file).
for (const args of [['-i', '-I'], ['-iI']]) {
  test(`H3: -i still prompts per file with ${args.join(' ')}`, async t => {
    const {trash, work} = await setup()
    const f = path.join(work, 'keep.txt')
    await fsp.writeFile(f, 'precious')

    const {stdout} = await run([...args, f], {trash, input: ['n']})

    t.regex(stdout, /remove .*keep\.txt\?/, 'a per-file prompt must fire')
    t.true(await exists(f), 'file must survive after declining the per-file prompt')
  })
}

const LINUX_ENV = {SAFE_RM_DEBUG_LINUX: '1'}

async function seedLinuxTrash (trash) {
  await Promise.all([
    fse.ensureDir(path.join(trash, 'files')),
    fse.ensureDir(path.join(trash, 'info'))
  ])
}

test('H4: trashing must not clobber an orphan .trashinfo', async t => {
  const {trash, work} = await setup()
  await seedLinuxTrash(trash)

  // An orphan info entry whose files/ counterpart no longer exists.
  const orphan = path.join(trash, 'info', 'report.doc.trashinfo')
  const orphanContent = '[Trash Info]\nPath=/PRECIOUS/report.doc\nDeletionDate=2020-01-01T00:00:00\n'
  await fsp.writeFile(orphan, orphanContent)

  const f = path.join(work, 'report.doc')
  await fsp.writeFile(f, 'new content')

  const {code} = await run([f], {trash, env: LINUX_ENV})
  t.is(code, 0)

  t.is(
    await fsp.readFile(orphan, 'utf8'),
    orphanContent,
    'the orphan .trashinfo must be preserved, not overwritten'
  )
  t.true(
    await exists(path.join(trash, 'files', 'report.doc.1')),
    'the new file must take a fresh name (report.doc.1)'
  )
})

async function concurrentRound (t, round) {
  const {trash, work} = await setup()
  await seedLinuxTrash(trash)

  const a = path.join(work, 'a', 'dup.txt')
  const b = path.join(work, 'b', 'dup.txt')
  await fse.ensureDir(path.dirname(a))
  await fse.ensureDir(path.dirname(b))
  await Promise.all([fsp.writeFile(a, 'AAAA'), fsp.writeFile(b, 'BBBB')])

  const [ra, rb] = await Promise.all([
    run([a], {trash, env: LINUX_ENV}),
    run([b], {trash, env: LINUX_ENV})
  ])
  t.is(ra.code, 0)
  t.is(rb.code, 0)

  const filesDir = path.join(trash, 'files')
  const names = await fsp.readdir(filesDir)
  const contents = await Promise.all(
    names.map(n => fsp.readFile(path.join(filesDir, n), 'utf8'))
  )
  t.true(contents.includes('AAAA'), `round ${round}: AAAA must survive`)
  t.true(contents.includes('BBBB'), `round ${round}: BBBB must survive`)
}

test('H4: concurrent same-name trashing must not lose data', async t => {
  await Promise.all(Array.from({length: 6}, (_, round) => concurrentRound(t, round)))
})

test('A1: a broken symlink already in the trash must not be overwritten', async t => {
  if (!IS_MACOS) {
    t.pass('macOS-only: check_mac_trash_path is on the mac_trash path')
    return
  }

  const {trash, work} = await setup()

  // A broken (dangling) symlink already sitting in the trash, named like the
  // file we are about to trash. `-e` follows it and reports "not present".
  await fsp.symlink('/nonexistent/target', path.join(trash, 'foo.txt'))

  const f = path.join(work, 'foo.txt')
  await fsp.writeFile(f, 'REAL')

  // Force genuine macOS mode (mac_trash); under `test:mock-linux` the inherited
  // SAFE_RM_DEBUG_LINUX=1 would otherwise route through linux_trash.
  const {code} = await run([f], {trash, env: {SAFE_RM_DEBUG_LINUX: ''}})
  t.is(code, 0)

  const link = await fsp.lstat(path.join(trash, 'foo.txt'))
  t.true(link.isSymbolicLink(), 'the pre-existing broken symlink must be preserved')

  const names = await fsp.readdir(trash)
  const realContents = await Promise.all(
    names.map(async n => {
      const st = await fsp.lstat(path.join(trash, n))
      return st.isFile() ? fsp.readFile(path.join(trash, n), 'utf8') : null
    })
  )
  t.true(realContents.includes('REAL'), 'the real file must be trashed under a fresh name')
})

test('A3: an unwritable info/ fails fast instead of spinning', async t => {
  if (IS_ROOT) {
    t.pass('skipped as root (permission bits are ignored)')
    return
  }

  const {trash, work} = await setup()
  await seedLinuxTrash(trash)
  await fsp.chmod(path.join(trash, 'info'), 0o0555) // unwritable -> reservation always fails

  const f = path.join(work, 'doc.txt')
  await fsp.writeFile(f, 'keep me')

  try {
    const {code} = await run([f], {trash, env: LINUX_ENV})
    t.not(code, 0, 'must fail (could not reserve a trash name), not spin to timeout')
    t.true(await exists(f), 'original file must be preserved on reservation failure')
  } finally {
    await fsp.chmod(path.join(trash, 'info'), 0o0755).catch(() => {})
  }
})

test('M1: honors an absolute $XDG_DATA_HOME for the home trash', async t => {
  const {root, work} = await setup()
  const home = path.join(root, 'home')
  const xdg = path.join(root, 'xdgdata')
  await Promise.all([fse.ensureDir(home), fse.ensureDir(xdg)])

  const f = path.join(work, 'doc.txt')
  await fsp.writeFile(f, 'data')

  // Linux mode, default trash (SAFE_RM_TRASH unset) -> trash dir derives from XDG.
  const {code} = await run([f], {
    trash: '',
    env: {
      SAFE_RM_DEBUG_LINUX: '1', HOME: home, XDG_DATA_HOME: xdg, SAFE_RM_TRASH: ''
    }
  })

  t.is(code, 0)
  t.true(
    await exists(path.join(xdg, 'Trash', 'files', 'doc.txt')),
    'file must land in $XDG_DATA_HOME/Trash'
  )
  t.false(
    await exists(path.join(home, '.local', 'share', 'Trash', 'files', 'doc.txt')),
    'must NOT fall back to $HOME/.local/share when XDG_DATA_HOME is set'
  )
})

test('L1: a dotfile duplicate keeps its name without a leading space', async t => {
  if (!IS_MACOS) {
    t.pass('macOS-only (mac_trash naming)')
    return
  }
  const {trash, work} = await setup()
  const macEnv = {SAFE_RM_DEBUG_LINUX: ''}
  const f = path.join(work, '.bashrc')

  await fsp.writeFile(f, 'one')
  await run([f], {trash, env: macEnv})
  await fsp.writeFile(f, 'two')
  await run([f], {trash, env: macEnv})

  const names = await fsp.readdir(trash)
  t.true(names.includes('.bashrc'), 'first copy keeps .bashrc')
  t.true(names.some(n => /^\.bashrc \d\d\.\d\d\.\d\d/.test(n)), 'duplicate named ".bashrc HH.MM.SS"')
  t.false(names.some(n => n.startsWith(' ')), 'no trash entry has a leading space')
})

test('L2: -v on a symlink (default trash) prints the path once', async t => {
  if (!IS_MACOS) {
    t.pass('macOS-only (AppleScript path)')
    return
  }
  const {root, work} = await setup()
  const home = path.join(root, 'home')
  await fse.ensureDir(path.join(home, '.Trash'))
  const target = path.join(work, 'target.txt')
  await fsp.writeFile(target, 'data')
  const link = path.join(work, 'mylink')
  await fsp.symlink(target, link)

  const {stdout} = await run(['-v', link], {
    trash: '',
    env: {SAFE_RM_DEBUG_LINUX: '', HOME: home, SAFE_RM_TRASH: ''}
  })

  t.is(stdout.split(link).length - 1, 1, 'symlink path printed exactly once')
  t.true(await exists(target), 'the symlink target must be untouched')
})

test('L3: -d on a non-empty directory says "Directory not empty"', async t => {
  const {trash, work} = await setup()
  const dir = path.join(work, 'd')
  await fse.ensureDir(dir)
  await fsp.writeFile(path.join(dir, 'x'), 'x')

  const {code, stderr} = await run(['-d', dir], {trash})
  t.is(code, 1, 'exit 1')
  t.regex(stderr, /Directory not empty/, 'message must say Directory not empty')
  t.true(await exists(dir), 'directory must be preserved')
})

test('L4: a trailing slash on a regular file says "Not a directory"', async t => {
  const {trash, work} = await setup()
  const f = path.join(work, 'reg.txt')
  await fsp.writeFile(f, 'data')

  const {code, stderr} = await run([`${f}/`], {trash})
  t.is(code, 1, 'exit 1')
  t.regex(stderr, /Not a directory/, 'message must say Not a directory')
  t.true(await exists(f), 'file must be preserved')

  const forced = await run(['-f', `${f}/`], {trash})
  t.is(forced.code, 1, '-f must still exit 1 for ENOTDIR')
  t.true(await exists(f), 'file still preserved under -f')
})
