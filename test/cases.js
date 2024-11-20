const path = require('path')
const {v4: uuid} = require('uuid')

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

    if (need_test_trash) {
      const files = await lsFileInTrash(filepath)
      t.is(files.length, 1)
      t.is(files[0], path.basename(filepath))
    }
  })

  test(`${des_prefix}: removes multiple files of the same name`, async t => {
    const {
      createFile,
      runRm,
      pathExists,
      lsFileInTrash
    } = t.context

    const filename = uuid()

    const filepath1 = await createFile(filename, '1')

    const result = await runRm([filepath1])

    t.is(result.code, 0)
    t.false(await pathExists(filepath1))
    t.false(await pathExists(filepath2))


    const filepath2 = await createFile(filename, '2')
    const filepath3 = await createFile(filename, '3')

    const files1 = await lsFileInTrash(filepath1)
    t.is(files1.length, 1)
    t.is(files1[0], path.basename(filepath1))

    const files2 = await lsFileInTrash(filepath2)
    t.is(files2.length, 1)
    t.is(files2[0], path.basename(filepath2))
  })
}
