// Per-mount trash routing (issue #50), Linux only.
//
// These tests force Linux mode (SAFE_RM_DEBUG_LINUX) and stub mount detection
// with the SAFE_RM_DEBUG_MOUNT_ROOTS seam: any target whose parent dir is under
// one of the listed prefixes is treated as residing on a separate filesystem
// whose top directory is that prefix. This exercises the full per-mount routing
// (trash-dir selection, sticky-bit checks, relative .trashinfo, fallback) on a
// single real filesystem, without needing root or real mounts.

const path = require('path')
const fs = require('fs')

const fsp = fs.promises
const {spawn} = require('child_process')
const tmp = require('tmp')
const fse = require('fs-extra')
const {v4: uuid} = require('uuid')
const test = require('ava')

const SAFE_RM = path.join(__dirname, '..', 'bin', 'rm.sh')
const UID = process.getuid()
const IS_ROOT = UID === 0

// Resolve symlinks once so prefixes match what the script computes (e.g. on
// macOS /var is a symlink to /private/var).
const TMP_ROOT = fs.realpathSync(tmp.dirSync().name)
const BASE = path.join(TMP_ROOT, 'safe-rm-per-mount')

async function setup () {
  const root = path.join(BASE, uuid())
  const home = path.join(root, 'home')
  const mnt = path.join(root, 'mnt')
  const config = path.join(root, 'config')

  await Promise.all([
    fse.ensureDir(home),
    fse.ensureDir(mnt),
    fse.ensureDir(config)
  ])

  return {
    root, home, mnt, config
  }
}

function baseEnv (o = {}) {
  return {
    HOME: o.home,
    XDG_CONFIG_HOME: '',
    SAFE_RM_CONFIG_ROOT: o.config,
    SAFE_RM_DEBUG_LINUX: '1',
    SAFE_RM_TRASH: o.trash || '',
    SAFE_RM_TRASH_PER_MOUNT: o.perMount === undefined ? 'yes' : o.perMount,
    SAFE_RM_DEBUG_MOUNT_ROOTS: o.mnt || '',
    SAFE_RM_PERM_DEL_FILES_IN_TRASH: o.permDel || ''
  }
}

function run (args, env, cwd) {
  return new Promise(resolve => {
    const child = spawn(SAFE_RM, args, {
      env: {...process.env, ...env},
      cwd
    })

    let stdout = ''
    let stderr = ''

    child.stdout.on('data', d => {
      stdout += d.toString()
    })
    child.stderr.on('data', d => {
      stderr += d.toString()
    })
    child.on('close', code => {
      resolve({code, stdout, stderr})
    })
  })
}

const homeTrashFiles = home => path.join(home, '.local', 'share', 'Trash', 'files')
const mountTrash = (mnt, sub) => path.join(mnt, `.Trash-${UID}`, sub)
const adminTrash = (mnt, sub) => path.join(mnt, '.Trash', String(UID), sub)

async function writeFile (filepath, content = 'data') {
  await fse.ensureDir(path.dirname(filepath))
  await fsp.writeFile(filepath, content)
  return filepath
}

test('gate: per-mount disabled routes to home trash even under a mount root', async t => {
  const {home, mnt, config} = await setup()
  const file = await writeFile(path.join(mnt, 'foo.txt'))

  const {code} = await run([file], baseEnv({
    home, config, mnt, perMount: 'no'
  }))

  t.is(code, 0)
  t.false(await fse.pathExists(file), 'source removed')
  t.true(
    await fse.pathExists(path.join(homeTrashFiles(home), 'foo.txt')),
    'goes to home trash, not a per-mount trash'
  )
  t.false(
    await fse.pathExists(mountTrash(mnt, path.join('files', 'foo.txt'))),
    'no per-mount trash created'
  )
})

test('routes to $topdir/.Trash-$uid when no admin .Trash exists', async t => {
  const {home, mnt, config} = await setup()
  const file = await writeFile(path.join(mnt, 'foo.txt'))

  const {code} = await run([file], baseEnv({home, config, mnt}))

  t.is(code, 0)
  t.false(await fse.pathExists(file), 'source removed')
  t.true(
    await fse.pathExists(mountTrash(mnt, path.join('files', 'foo.txt'))),
    'lands in <mnt>/.Trash-<uid>/files/'
  )
})

test('targets on the home filesystem still go to the home trash', async t => {
  const {
    root, home, mnt, config
  } = await setup()
  // file is NOT under the fake mount root => treated as home filesystem
  const file = await writeFile(path.join(root, 'elsewhere', 'bar.txt'))

  const {code} = await run([file], baseEnv({home, config, mnt}))

  t.is(code, 0)
  t.true(
    await fse.pathExists(path.join(homeTrashFiles(home), 'bar.txt')),
    'lands in home trash'
  )
})

test('.trashinfo Path is relative to the top directory for mount trash', async t => {
  const {home, mnt, config} = await setup()
  const file = await writeFile(path.join(mnt, 'sub', 'baz.txt'))

  const {code} = await run([file], baseEnv({home, config, mnt}))

  t.is(code, 0)
  t.true(
    await fse.pathExists(mountTrash(mnt, path.join('files', 'baz.txt'))),
    'file in mount trash'
  )

  const info = await fsp.readFile(
    mountTrash(mnt, path.join('info', 'baz.txt.trashinfo')),
    'utf8'
  )
  t.true(info.startsWith('[Trash Info]'), 'has header')
  t.regex(info, /^Path=sub\/baz\.txt$/m, 'Path is relative to topdir')
  t.regex(info, /^DeletionDate=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/m, 'has deletion date')
})

test('uses $topdir/.Trash/$uid when a sticky admin .Trash exists', async t => {
  const {home, mnt, config} = await setup()
  const adminDir = path.join(mnt, '.Trash')
  await fse.ensureDir(adminDir)
  await fsp.chmod(adminDir, 0o1777)

  const file = await writeFile(path.join(mnt, 'qux.txt'))

  const {code} = await run([file], baseEnv({home, config, mnt}))

  t.is(code, 0)
  t.true(
    await fse.pathExists(adminTrash(mnt, path.join('files', 'qux.txt'))),
    'lands in <mnt>/.Trash/<uid>/files/'
  )
})

test('falls back to .Trash-$uid when admin .Trash lacks the sticky bit', async t => {
  const {home, mnt, config} = await setup()
  const adminDir = path.join(mnt, '.Trash')
  await fse.ensureDir(adminDir)
  await fsp.chmod(adminDir, 0o0777)

  const file = await writeFile(path.join(mnt, 'no-sticky.txt'))

  const {code} = await run([file], baseEnv({home, config, mnt}))

  t.is(code, 0)
  t.true(
    await fse.pathExists(mountTrash(mnt, path.join('files', 'no-sticky.txt'))),
    'falls back to .Trash-<uid>'
  )
  t.false(
    await fse.pathExists(adminTrash(mnt, path.join('files', 'no-sticky.txt'))),
    'does not use the non-sticky admin .Trash'
  )
})

test('falls back to .Trash-$uid when admin .Trash is a symlink', async t => {
  const {
    root, home, mnt, config
  } = await setup()
  const realDir = path.join(root, 'real-trash')
  await fse.ensureDir(realDir)
  await fsp.chmod(realDir, 0o1777)
  await fsp.symlink(realDir, path.join(mnt, '.Trash'))

  const file = await writeFile(path.join(mnt, 'linked.txt'))

  const {code} = await run([file], baseEnv({home, config, mnt}))

  t.is(code, 0)
  t.true(
    await fse.pathExists(mountTrash(mnt, path.join('files', 'linked.txt'))),
    'falls back to .Trash-<uid>'
  )
})

test('falls back to the home trash when the mount trash cannot be created', async t => {
  if (IS_ROOT) {
    t.pass('skipped as root (permission checks do not apply)')
    return
  }

  const {home, mnt, config} = await setup()
  const sub = path.join(mnt, 'sub')
  await fse.ensureDir(sub)
  const file = await writeFile(path.join(sub, 'file.txt'))

  // Make the mount root read-only so .Trash-<uid> cannot be created, but the
  // source's own dir stays writable so it can still be moved out.
  await fsp.chmod(mnt, 0o0555)

  try {
    const {code} = await run([file], baseEnv({home, config, mnt}))

    t.is(code, 0)
    t.true(
      await fse.pathExists(path.join(homeTrashFiles(home), 'file.txt')),
      'falls back to home trash'
    )
    t.false(
      await fse.pathExists(path.join(mnt, `.Trash-${UID}`)),
      'no per-mount trash created'
    )
  } finally {
    await fsp.chmod(mnt, 0o0755)
  }
})

test('a custom SAFE_RM_TRASH disables per-mount routing', async t => {
  const {
    root, home, mnt, config
  } = await setup()
  const custom = path.join(root, 'custom-trash')
  await fse.ensureDir(custom)

  const file = await writeFile(path.join(mnt, 'm.txt'))

  const {code} = await run([file], baseEnv({
    home, config, mnt, trash: custom
  }))

  t.is(code, 0)
  t.true(
    await fse.pathExists(path.join(custom, 'files', 'm.txt')),
    'lands in the custom trash'
  )
  t.false(
    await fse.pathExists(mountTrash(mnt, path.join('files', 'm.txt'))),
    'no per-mount trash used'
  )
})

test('permanently deletes a file already inside a per-mount trash', async t => {
  const {home, mnt, config} = await setup()
  const file = await writeFile(path.join(mnt, 'p.txt'))

  // First: trash it into the per-mount trash.
  const first = await run([file], baseEnv({home, config, mnt}))
  t.is(first.code, 0)

  const trashed = mountTrash(mnt, path.join('files', 'p.txt'))
  t.true(await fse.pathExists(trashed), 'trashed into per-mount trash')

  // Then: rm it again with permanent-delete on -> it should be gone, not re-trashed.
  const second = await run(
    [trashed],
    baseEnv({
      home, config, mnt, permDel: 'yes'
    })
  )

  t.is(second.code, 0)
  t.false(await fse.pathExists(trashed), 'permanently removed')
  t.false(
    await fse.pathExists(mountTrash(mnt, path.join('files', 'p.txt.1'))),
    'not re-trashed as a duplicate'
  )
})
