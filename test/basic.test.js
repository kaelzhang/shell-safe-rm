const test = require('ava')
const {
  pathExists,
  generateContextMethods,
  runSafeRm
} = require('./helper')


// Setup before each test
test.beforeEach(async t => {
  await generateContextMethods(t)
})

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
})

