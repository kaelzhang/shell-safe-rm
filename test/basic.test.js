const test = require('ava')
const {
  pathExists,
  pathInTrash,
  generateContextMethods,
  runSafeRm
} = require('./helper')


// Setup before each test
test.beforeEach(generateContextMethods)

// Cleanup after each test
test.afterEach.always(async t => {
  t.context.cleanup()
})

// Basic removal test
test('removes a single file', async t => {
  const filepath = await t.context.file()
  const result = await runSafeRm([filepath])

  t.is(result.code, 0)
  t.false(await pathExists(filepath))
  t.true(await pathInTrash(filepath))
})
