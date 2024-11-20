const path = require('path')
const fs = require('fs').promises
const {spawn} = require('child_process')
const tmp = require('tmp')
const fse = require('fs-extra')
const {v4: uuid} = require('uuid')

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
    const dirpath = path.join(t.context.source_path, dirname)
    await fse.ensureDir(dirpath)

    return dirpath
  }

  // Helper function to create a temporary file
  async function createFile (filename = uuid(), content = 'test content') {
    const filepath = path.join(t.context.source_path, filename)
    await fs.writeFile(filepath, content)

    return filepath
  }

  // Helper function to run rm commands
  function runRm (args, {
    input = '',
    command = rm_command,
    env = {}
  } = {}) {
    return new Promise(resolve => {
      const child = spawn(command, args, {
        env: Object.assign({
          SAFE_RM_TRASH: t.context.trash_path
        }, env)
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
        resolve({
          code,
          stdout,
          stderr
        })
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
    const files = await fs.readdir(t.context.trash_path)

    const filename = path.basename(filepath)
    const filtered = files.filter(
      f => f === filename || f.startsWith(`${filename} `)
    )

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

module.exports = {
  generateContextMethods
}
