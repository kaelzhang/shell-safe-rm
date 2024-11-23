const path = require('path')
const {v4: uuid} = require('uuid')
const delay = require('delay')

const {
  generateContextMethods,
  assertEmptySuccess
} = require('./helper')


module.exports = (
  test,
  des_prefix,
  test_safe_rm = true,
  rm_command
) => {

  // Setup before each test
  test.beforeEach(generateContextMethods(rm_command))

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
    assertEmptySuccess(t, result1)
    t.false(await pathExists(filepath1), 'file 1 should be removed')

    const filepath2 = await createFile(filename, '2')
    const result2 = await runRm([filepath2])
    assertEmptySuccess(t, result2)
    t.false(await pathExists(filepath2), 'file 2 should be removed')

    const filepath3 = await createFile(filename, '3')
    const result3 = await runRm([filepath3])
    assertEmptySuccess(t, result3)
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

  test(`${des_prefix}: removes a single file in trash permanently`, async t => {
    const {
      trash_path,
      createFile,
      runRm,
      pathExists,
      lsFileInTrash
    } = t.context

    const filepath = await createFile(path.join(trash_path, uuid()))
    const result = await runRm([filepath], {
      env: {
        SAFE_RM_PERM_DEL_FILES_IN_TRASH: 'yes'
      }
    })

    assertEmptySuccess(t, result)
    t.false(await pathExists(filepath), 'file should be removed')

    if (!test_safe_rm) {
      return
    }

    const files = await lsFileInTrash(filepath)

    t.is(files.length, 0, 'should be already removed')
  })

  test(`${des_prefix}: #22 exit code with -f option`, async t => {
    const {
      source_path,
      createFile,
      runRm,
      pathExists,
      lsFileInTrash
    } = t.context

    const filepath = path.join(source_path, uuid())
    const result = await runRm(['-f', filepath])

    assertEmptySuccess(t, result, ', if rm -f a non-existing file')

    const result_no_f = await runRm([filepath])

    t.is(result_no_f.code, 1, 'exit code should be 1 without -f')
    t.is(result_no_f.stdout, '', 'stdout should be empty')
    t.true(result_no_f.stderr.includes(`: ${filepath}: No such file or directory`), 'stderr should include "No such file or directory"')
  })
}
