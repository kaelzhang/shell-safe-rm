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
  for (const f of files) {
    t.true(await exists(f), `${path.basename(f)} must survive after declining`)
  }
})
