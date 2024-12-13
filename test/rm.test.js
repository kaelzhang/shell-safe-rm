const test = require('ava')

const run = require('./cases')

run(test, {
  type: 'rm',
  command: '/bin/rm'
})
