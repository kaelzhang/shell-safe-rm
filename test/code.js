const test = require('ava')
const {v4: uuid} = require('uuid')

const {
  generateContextMethods
} = require('./helper')

const RM_PATH = '/bin/rm'


// Setup before each test
test.beforeEach(generateContextMethods)

// Cleanup after each test
test.afterEach.always(async t => {
  t.context.cleanup()
})


const CASES = [
  [
    // Directories
    [],
    // Files
    [uuid()],
    // args
    []
  ]
]

CASES.forEach((c, i) => {
  test(`${i}: rm`, async t => {
    const [dirs, files, _args, files_to_del = files] = typeof c === 'function'
      ? c(t)
      : c

    const args = typeof _args === 'function'
      ? _args(files_to_del)

    const dirpaths = await Promise.all(dirs.map(t.context.dir))
    const filepaths = await Promise.all(files.map(t.context.file))

    const result = await runRm([...args, ...filepaths, ...dirpaths], {
      command: RM_PATH
    })

    t.is(result.code, 0)

    for (const filepath of filepaths) {
      t.false(await pathExists(filepath))
    }

    for (const dirpath of dirpaths) {
      t.false(await pathExists
  })
})
