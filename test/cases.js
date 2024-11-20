const path = require('path')
const {v4: uuid} = require('uuid')
const delay = require('delay')

const {
  generateContextMethods
} = require('./helper')


module.exports = (
  test,
  des_prefix,
  need_test_trash = true,
  rm_command
) => {

  // Setup before each test
  test.beforeEach(generateContextMethods(rm_command))

  // Basic removal test
  test(`${des_prefix}: removes a single file`, async t => {
    const {
      createFile,
      runRm,
      pathExists,
      lsFileInTrash
    } = t.context

    const filepath = await createFile()
    const result = await runRm([filepath])

    t.is(result.code, 0)
    t.false(await pathExists(filepath))

    if (!need_test_trash) {
      return
    }

    const files = await lsFileInTrash(filepath)
    t.is(files.length, 1)
    t.is(files[0], path.basename(filepath))
  })

  test(`${des_prefix}: removes multiple files of the same name`, async t => {
    const {
      createFile,
      runRm,
      pathExists,
      lsFileInTrash
    } = t.context

    const filename = uuid()

    const now = Date.now()
    const to_next_second = 1000 - now % 1000
    await delay(to_next_second)

    const filepath1 = await createFile(filename, '1')
    const result1 = await runRm([filepath1])
    t.is(result1.code, 0)
    t.false(await pathExists(filepath1))

    const filepath2 = await createFile(filename, '2')
    const result2 = await runRm([filepath2])
    t.is(result2.code, 0)
    t.false(await pathExists(filepath2))

    const filepath3 = await createFile(filename, '3')
    const result3 = await runRm([filepath3])
    t.is(result3.code, 0)
    t.false(await pathExists(filepath3))

    if (!need_test_trash) {
      return
    }

    const files = await lsFileInTrash(filename)

    console.log(files)
  })
}
