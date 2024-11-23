const path = require('path')
const fs = require('fs').promises
const {spawn} = require('child_process')
const tmp = require('tmp')
const fse = require('fs-extra')
const {v4: uuid} = require('uuid')
const log = require('util').debuglog('safe-rm')

const SAFE_RM_PATH = path.join(__dirname, '..', 'bin', 'rm.sh')
const TEST_DIR = path.join(tmp.dirSync().name, 'safe-rm-tests')

const generateContextMethods = (rm_command = SAFE_RM_PATH) => async t => {
  const root_path = path.join(TEST_DIR, uuid())
  t.context.root = await fse.ensureDir(root_path)

  const source_path = path.join(root_path, 'source')
  const trash_path = path.join(root_path, 'trash')

  ;[
    t.context.source_path, t.context.trash_path
  ] = await Promise.all([
    fse.ensureDir(source_path),
    fse.ensureDir(trash_path)
  ])

  // Helper function to create a temporary directory
  async function createDir (dirname = uuid()) {
    const dirpath = path.resolve(t.context.source_path, dirname)
    await fse.ensureDir(dirpath)

    return dirpath
  }

  // Helper function to create a temporary file
  async function createFile (filename = uuid(), content = 'test content') {
    const filepath = path.resolve(t.context.source_path, filename)
    await fs.writeFile(filepath, content)

    return filepath
  }

  // Helper function to run rm commands
  function runRm (args, {
    input = '',
    command = rm_command,
    env: arg_env = {}
  } = {}) {
    return new Promise(resolve => {
      const env = {
        ...process.env,
        ...{
          SAFE_RM_TRASH: t.context.trash_path
        },
        ...arg_env
      }

      const child = spawn(command, args, {
        env
      })
      let stdout = ''
      let stderr = ''

      child.stdout.on('data', data => {
        stdout += data.toString()
      })

      child.stderr.on('data', data => {
        stderr += data.toString()
      })

      if (input) {
        if (!child.stdin) {
          throw new Error('Child process does not support stdin')
        }

        child.stdin.write(input)
        child.stdin.end()
      }

      child.on('close', code => {
        const resolved = {
          code,
          stdout,
          stderr
        }

        log(command, 'result:', resolved)

        resolve(resolved)
      })
    })
  }

  // Helper function to check if path exists
  async function pathExists (filepath) {
    const realpath = path.resolve(t.context.source_path, filepath)

    try {
      await fs.access(realpath)
      return true
    } catch (e) {
      return false
    }
  }

  async function lsFileInTrash (filepath) {
    const {trash_path} = t.context
    const files = await fs.readdir(trash_path)

    const filename = path.basename(filepath)
    const filtered = files.filter(
      f => f === filename || f.startsWith(`${filename} `)
    ).map(f => path.join(trash_path, f))

    return filtered
  }

  Object.assign(t.context, {
    createDir,
    createFile,
    runRm,
    pathExists,
    lsFileInTrash
  })
}

const assertEmptySuccess = (t, result, a = '', b = '', c = '') => {
  t.is(result.code, 0, 'exit code should be 0' + a)
  t.is(result.stdout, '', 'stdout should be empty' + b)
  t.is(result.stderr, '', 'stderr should be empty' + c)
}

module.exports = {
  generateContextMethods,
  assertEmptySuccess
}