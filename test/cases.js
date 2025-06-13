const path = require('path')
const {v4: uuid} = require('uuid')
const delay = require('delay')

const {
  generateContextMethods,
  assertEmptySuccess,
  IS_MACOS
} = require('./helper')

const SAFE_RM_PATH = path.join(__dirname, '..', 'bin', 'rm.sh')

const is_rm = type => type === 'rm'
// const is_safe_rm = type => type === 'safe-rm'

// Whether it is a test spec for AppleScript version of safe-rm
const is_as = type => type === 'safe-rm-as'

// We skip testing trash dir for vanilla rm
const should_skip_test_trash_dir = type => is_rm(type) || is_as(type)

module.exports = (
  test,
  {
    type,
    // test_trash_dir,
    command = SAFE_RM_PATH,
    env = {}
  } = {}
) => {
  // Setup before each test
  test.beforeEach(generateContextMethods(command, env))

  test(`removes a single file`, async t => {
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

    if (should_skip_test_trash_dir(type)) {
      return
    }

    const files = await lsFileInTrash(filepath)

    t.is(files.length, 1, 'should be one in the trash')
    t.is(
      path.basename(files[0]),
      path.basename(filepath),
      'file name should match'
    )
  })

  const EXTs = [
    '',
    '.jpg'
  ]

  EXTs.forEach(ext => {
    const extra = ext
      ? ` with ext "${ext}"`
      : ''

    test(`removes multiple files of the same name${extra}`, async t => {
      const {
        createFile,
        runRm,
        pathExists,
        lsFileInTrash
      } = t.context

      const filename = uuid()
      const full_name = filename + ext

      const now = Date.now()
      const to_next_second = 1000 - now % 1000
      await delay(to_next_second)

      const filepath1 = await createFile({name: full_name, content: '1'})
      const result1 = await runRm([filepath1])

      const filepath2 = await createFile({name: full_name, content: '2'})
      const result2 = await runRm([filepath2])

      const filepath3 = await createFile({name: full_name, content: '3'})
      const result3 = await runRm([filepath3])

      assertEmptySuccess(t, result1)
      t.false(await pathExists(filepath1), 'file 1 should be removed')

      assertEmptySuccess(t, result2)
      t.false(await pathExists(filepath2), 'file 2 should be removed')

      assertEmptySuccess(t, result3)
      t.false(await pathExists(filepath3), 'file 3 should be removed')

      if (should_skip_test_trash_dir(type)) {
        return
      }

      const files = (await lsFileInTrash(full_name))
      .sort((a, b) => a.length - b.length)

      if (IS_MACOS) {
        // /path/to/foo[.jpg]
        // /path/to/foo 12.58.23[.jpg]
        // /path/to/foo 12.58.23 12.58.23[.jpg]
        const [f1, f2, f3] = files

        const [fb1, fb2, fb3] = [f1, f2, f3].map(
          f => {
            const base = path.basename(f)

            return base.slice(0, base.length - ext.length)
          }
        )

        const [fbs1, fbs2, fbs3] = [fb1, fb2, fb3].map(f => f.split(' '))

        const time = fbs2[1]

        t.true(files.every(f => f.endsWith(ext)), 'should have the same ext')

        t.is(fb1, filename)
        t.is(fbs1[0], filename)
        t.is(fbs2[0], filename)
        t.is(fbs3[0], filename)

        t.is(fbs3[1], time)
        t.is(fbs3[2], time)
      } else {
        // /path/to/foo[.jpg]
        // /path/to/foo[.jpg].1
        // /path/to/foo[.jpg].2
        const nums = []
        const bases = []
        const re = /(\.(\d+))?$/

        for (const file of files) {
          const match = file.match(re)
          const n = match[2]
            ? parseInt(match[2], 10)
            : 0

          const f = file.slice(0, match.index)

          nums.push(n)
          bases.push(f)
        }

        t.true(bases.every(f => f.endsWith(ext)), 'should have the same ext')
        t.is(nums[0], 0)
        t.is(nums[1], 1)
        t.is(nums[2], 2)
      }
    })
  })

  test(`removes a single file in trash permanently`, async t => {
    const {
      trash_path,
      createFile,
      runRm,
      pathExists,
      lsFileInTrash
    } = t.context

    const filepath = await createFile({name: path.join(trash_path, uuid())})
    const result = await runRm([filepath], {
      env: {
        SAFE_RM_PERM_DEL_FILES_IN_TRASH: 'yes'
      }
    })

    assertEmptySuccess(t, result)
    t.false(await pathExists(filepath), 'file should be removed')

    if (should_skip_test_trash_dir(type)) {
      return
    }

    const files = await lsFileInTrash(filepath)

    t.is(files.length, 0, 'should be already removed')
  })

  test(`#22 exit code with -f option`, async t => {
    const {
      source_path,
      runRm
    } = t.context

    const filepath = path.join(source_path, uuid())
    const result = await runRm(['-f', filepath])

    assertEmptySuccess(t, result, ', if rm -f a non-existing file')

    const result_no_f = await runRm([filepath])

    t.is(result_no_f.code, 1, 'exit code should be 1 without -f')
    t.is(result_no_f.stdout, '', 'stdout should be empty')

    t.true(
      // The stderr of different rm distributions may vary:
      // - Linux rm: "rm: cannot remove 'nonexistent.txt': No such file or directory"
      // - Mac rm: "rm: nonexistent.txt: No such file or directory"
      // So we just check if the stderr includes "No such file or directory"
      result_no_f.stderr.includes('No such file or directory'), `stderr should include "No such file or directory": ${
        result_no_f.stderr
      }`)
  })

  test(`removes an empty directory: -d`, async t => {
    const {
      createDir,
      runRm,
      pathExists
    } = t.context

    const dirpath = await createDir()
    const result1 = await runRm([dirpath])

    t.is(result1.code, 1, 'exit code should be 1')
    t.true(result1.stderr.includes('a directory'), 'stderr should include "a directory"')

    const result2 = await runRm(['-d', dirpath])

    assertEmptySuccess(t, result2)
    t.false(await pathExists(dirpath), 'directory should be removed')
  })

  // Only test for safe-rm
  !is_rm(type) && test(`protected rules`, async t => {
    const {
      createDir,
      createFile,
      runRm,
      pathExists
    } = t.context

    const config_root = await createDir({
      name: '.safe-rm'
    })

    const dir = await createDir()
    const filepath = await createFile({
      under: dir
    })

    await createFile({
      name: '.gitignore',
      under: config_root,
      content: `${dir}
`
    })

    const result = await runRm([filepath], {
      env: {
        SAFE_RM_CONFIG_ROOT: config_root
      }
    })

    t.is(result.code, 1, 'exit code should be 1')
    t.true(result.stderr.includes('protected'), 'stderr should include "protected"')
    t.true(await pathExists(filepath), 'file should not be removed')
  })

  !is_as(type) && test(`#44: recursively and interactively`, async t => {
    const {
      createDir,
      createFile,
      runRm,
      pathExists
    } = t.context

    const name = 'foo'

    const dir = await createDir({
      name
    })

    const fileA = await createFile({
      name: 'a',
      under: dir
    })

    const fileB = await createFile({
      name: 'b',
      under: dir
    })

    const result = await runRm(['-ri', dir], {
      input: ['y', 'y', 'y', 'y']
    })

    t.is(result.stderr, '', 'stderr should be empty')
    t.is(result.code, 0, 'exit code should be 0')
    t.is(
      result.stdout,
      `examine files in directory ${dir}? y
remove ${fileA}? y
remove ${fileB}? y
remove ${dir}? y
`,
      'stdout does not match'
    )

    t.false(await pathExists(dir), 'directory should be removed')
  })
}
