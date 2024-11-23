const path = require('path')
const {v4: uuid} = require('uuid')
const delay = require('delay')

const {
  generateContextMethods
} = require('./helper')


module.exports = (
  test,
  des_prefix,
  test_safe_rm = true,
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

    t.is(result.code, 0, 'exit code should be 0')
    t.false(await pathExists(filepath), 'file should be removed')

    if (!test_safe_rm) {
      return
    }

    const files = await lsFileInTrash(filepath)

    t.is(files.length, 1, 'should be one in the trash')
    t.is(
      path.basename(files[0]), path.basename(filepath),
      'file name should match'
    )
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
    t.is(result1.code, 0, 'exit code 1 should be 0')
    t.false(await pathExists(filepath1), 'file 1 should be removed')

    const filepath2 = await createFile(filename, '2')
    const result2 = await runRm([filepath2])
    t.is(result2.code, 0, 'exit code 2 should be 0')
    t.false(await pathExists(filepath2), 'file 2 should be removed')

    const filepath3 = await createFile(filename, '3')
    const result3 = await runRm([filepath3])
    t.is(result3.code, 0, 'exit code 3 should be 0')
    t.false(await pathExists(filepath3), 'file 3 should be removed')

    if (!test_safe_rm) {
      return
    }

    // /path/to/foo
    // /path/to/foo 12.58.23
    // /path/to/foo 12.58.23 12.58.23
    const [f1, f2, f3] = (await lsFileInTrash(filename))
    const [fb1, fb2, fb3] = [f1, f2, f3].map(f => path.basename(f))
    const [fbs1, fbs2, fbs3] = [fb1, fb2, fb3].map(f => f.split(' '))

    const time = fbs2[1]

    t.is(fb1, filename)
    t.is(fbs2[0], filename)
    t.is(fbs3[0], filename)

    t.is(fbs3[1], time)
    t.is(fbs3[2], time)
  })
}
