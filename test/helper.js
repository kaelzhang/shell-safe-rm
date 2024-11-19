
const path = require('path')
const fs = require('fs').promises
const {spawn} = require('child_process')
const tmp = require('tmp')
const fse = require('fs-extra')
const {v4: uuid} = require('uuid')

const SAFE_RM_PATH = path.join(__dirname, '..', 'bin', 'rm.sh')
const TEST_DIR = path.join(tmp.dirSync().name, 'safe-rm-tests')
const TRASH_BIN = path.join()

// Helper function to check if path exists
async function pathExists (filepath) {
  try {
    await fs.access(filepath)
    return true
  } catch (e) {
    return false
  }
}

const generateContextMethods = async t => {
  t.context.tmpResources = []

  // Helper function to create a temporary directory
  async function createTempDir (dirname = '') {
    const dirpath = dirname
      ? path.join(TEST_DIR, dirname)
      : TEST_DIR

    await fse.ensureDir(dirpath)

    t.context.tmpResources.push(dirpath)

    return dirpath
  }

  t.context.root = await createTempDir()

  // Helper function to create a temporary file
  async function createTempFile (filename = uuid()) {
    const filepath = path.join(t.context.root, filename)
    await fs.writeFile(filepath, 'test content')
    // await fs.chmod(filepath, 777)

    // Add to list of resources to clean up
    t.context.tmpResources.push(filepath)

    return filepath
  }

  async function cleanup () {
    await Promise.all(t.context.tmpResources.reverse().map(r => fse.remove(r)))
    t.context.tmpResources.length = 0
  }

  t.context.file = createTempFile
  t.context.dir = createTempDir
  t.context.cleanup = cleanup
}

// Helper function to run safe-rm command
function runSafeRm (args, input = '') {
  return new Promise(resolve => {
    const child = spawn(SAFE_RM_PATH, args)
    let stdout = ''
    let stderr = ''

    child.stdout.on('data', data => {
      stdout += data.toString()
    })

    child.stderr.on('data', data => {
      stderr += data.toString()
    })

    if (input) {
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

module.exports = {
  pathExists,
  generateContextMethods,
  runSafeRm
}
